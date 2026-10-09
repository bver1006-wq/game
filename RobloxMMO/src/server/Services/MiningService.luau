--!strict
-- 휘두르기 요청 검증, 판정, 데미지, 깨짐·보상 처리. 보상은 가방(InventoryService)에 넣는다.
-- 클라이언트는 "이 바위를 이 시각에 휘둘렀다"만 보낸다. 대상·거리·쿨다운·판정·보상은 전부 서버가 정한다.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local OreDefs = require(ReplicatedStorage.Shared.OreDefs)
local PickaxeDefs = require(ReplicatedStorage.Shared.PickaxeDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local AntiCheatService = require(script.Parent.AntiCheatService)
local ChargeService = require(script.Parent.ChargeService)
local FeverService = require(script.Parent.FeverService)
local InventoryService = require(script.Parent.InventoryService)
local ManaService = require(script.Parent.ManaService)
local NotifyService = require(script.Parent.NotifyService)
local OreService = require(script.Parent.OreService)
local OwnershipService = require(script.Parent.OwnershipService)
local PickaxeService = require(script.Parent.PickaxeService)
local TimingService = require(script.Parent.TimingService)

type RockState = OreService.RockState

local MiningService = {}

local random = Random.new()
local hitEffectRemote: RemoteEvent
local rockBrokenRemote: RemoteEvent

-- 위치 근처(EffectBroadcastRange 이내)에 있는 플레이어에게 이벤트를 보낸다
local function fireNearby(remote: RemoteEvent, position: Vector3, ...: any)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - position).Magnitude <= Config.Mining.EffectBroadcastRange then
			remote:FireClient(player, ...)
		end
	end
end

-- 바위 하나의 플레이어별 산출량을 계산한다
-- 랜덤 BaseMin~BaseMax개를 기여 비율대로 나누고, 피버를 연 사람은 자기 몫에 피버 배수를 곱한다
local function computeRewards(state: RockState, feverPlayer: Player?, feverMultiplier: number): { [number]: number }
	local reward = Config.Reward
	local base = random:NextInteger(reward.BaseMin, reward.BaseMax)

	local totalDamage = 0
	for _, damage in state.Contributions do
		totalDamage += damage
	end

	local rewards: { [number]: number } = {}
	for userId, damage in state.Contributions do
		local share = if totalDamage > 0 then damage / totalDamage else 0
		rewards[userId] = math.max(math.round(base * state.RewardMultiplier * share), reward.MinPerContributor)
	end
	if feverPlayer and feverMultiplier > 1 then
		local own = rewards[feverPlayer.UserId] or reward.MinPerContributor
		rewards[feverPlayer.UserId] = math.max(math.round(own * feverMultiplier), own + 1)
	end
	return rewards
end

-- 바위를 깨뜨린다: 보상 계산 → 연출 알림 → 제거·리스폰 예약
local function finishRock(state: RockState, feverPlayer: Player?, feverMultiplier: number)
	local rewards = computeRewards(state, feverPlayer, feverMultiplier)
	TimingService.clearRock(state.Rock)
	OreService.breakRock(state)

	-- 가방에 넣는다. 가방이 차면 들어간 만큼만 받고, 나머지는 사라진다
	for userId, amount in rewards do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			local added = InventoryService.add(player, state.OreType, amount)
			if added < amount then
				NotifyService.send(player, "가방이 가득 찼어요! 마을 상인에게 팔고 오세요.", "bad")
			end
			rewards[userId] = added
		else
			rewards[userId] = nil -- 그사이 나간 플레이어
		end
	end

	-- RemoteEvent는 숫자 키 딕셔너리를 제대로 못 보내므로 UserId를 문자열 키로 바꿔 보낸다
	local rewardsByKey: { [string]: number } = {}
	for userId, amount in rewards do
		rewardsByKey[tostring(userId)] = amount
	end
	fireNearby(rockBrokenRemote, state.Position, state.Position, state.OreType, rewardsByKey, feverMultiplier)

	-- 테스트 확인용 로그
	for userId, amount in rewards do
		local counts = state.Judgments[userId]
		print(
			`[MiningService] 바위 깨짐 userId={userId} 획득 {amount}개`
				.. ` (Nice {counts and counts.Nice or 0}, Perfect {counts and counts.Perfect or 0}, 피버 x{feverMultiplier})`
		)
	end
end

local lastWallNotice: { [Player]: number } = {}

-- 타격 위치: 바위는 중심에서 캐릭터 쪽 표면 근처, 나무는 밑동(기준점) 위 HitHeight 높이의 줄기 표면
local function hitPositionFor(state: RockState, oreDef: OreDefs.OreDef, rock: Model, player: Player): Vector3
	local root = (player.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart
	local toPlayer = (root.Position - state.Position) * Vector3.new(1, 0, 1)
	local direction = if toPlayer.Magnitude > 0.01 then toPlayer.Unit else Vector3.zAxis
	if oreDef.Kind == "Tree" then
		-- 줄기 반지름은 템플릿 속성 HitRadius(맵 나무에서 잰 값)가 우선
		local radiusAttribute = rock:GetAttribute("HitRadius")
		local radius = if typeof(radiusAttribute) == "number" then radiusAttribute else oreDef.HitRadius or 1
		return state.Position + direction * radius + Vector3.new(0, oreDef.HitHeight or 2.5, 0)
	end
	local size = rock:GetExtentsSize()
	return state.Position + direction * (math.max(size.X, size.Z) * 0.45) + Vector3.new(0, size.Y * 0.1, 0)
end

-- SwingRequest 처리. 인자는 전부 의심하고 검사한다
local function onSwingRequest(player: Player, rockArg: unknown, clientTimeArg: unknown, isTouchArg: unknown)
	-- 인자 형식 검사
	if typeof(rockArg) ~= "Instance" or not (rockArg :: Instance):IsA("Model") then
		return
	end
	local rock = rockArg :: Model
	if not CollectionService:HasTag(rock, OreService.Tag) then
		return
	end
	if typeof(clientTimeArg) ~= "number" or clientTimeArg ~= clientTimeArg then -- NaN 거르기
		return
	end
	local clientTime = clientTimeArg :: number
	local isTouch = isTouchArg == true
	-- 모은 정도는 요청이 오면 무조건 꺼낸다 (거절돼도 느린 걸음이 남지 않게)
	local charge = ChargeService.consume(player)

	local state = OreService.getState(rock)
	if not state or state.Depleted then
		return
	end
	if FeverService.isActive(player) then
		return
	end

	-- 맞는 도구(바위는 곡괭이, 나무는 도끼)를 들고 있고, 이 노드를 캘 수 있는 티어인가
	local pickaxe = PickaxeService.getEquipped(player)
	local oreDef = OreDefs[state.OreType]
	if not pickaxe or not oreDef then
		return
	end
	local neededKind: PickaxeDefs.ToolKind = if oreDef.Kind == "Tree" then "Axe" else "Pickaxe"
	if pickaxe.Kind ~= neededKind then
		NotifyService.send(player, if neededKind == "Axe" then "나무는 도끼로 베어야 해요." else "바위는 곡괭이로 캐야 해요.", "bad")
		return
	end
	-- 거리, 쿨다운 (쿨다운은 다른 검사를 통과한 뒤에 소모한다)
	if not AntiCheatService.isInRange(player, state.Position, state.ExtraReach) then
		return
	end
	-- 다른 사람이 캐는 중이면 못 친다
	if not OwnershipService.canHit(state, player) then
		OwnershipService.notifyBlocked(player, if oreDef.Kind == "Tree" then "다른 사람이 베고 있는 나무예요." else "다른 사람이 캐고 있는 바위예요.")
		return
	end
	if not AntiCheatService.tryConsumeSwing(player) then
		return
	end

	-- 장비 벽: 도구 단계가 모자라면 때릴 수는 있지만 체력이 안 닳는다 ("팅" 하고 튕겨 나온다)
	if pickaxe.Tier < oreDef.RequiredTier then
		local now = os.clock()
		if now - (lastWallNotice[player] or -math.huge) >= Config.TierWall.NoticeInterval then
			lastWallNotice[player] = now
			NotifyService.send(player, `{oreDef.DisplayName}: 너무 단단해요! {PickaxeService.nameFor(neededKind, oreDef.RequiredTier)} 이상이 필요해요.`, "bad")
		end
		fireNearby(hitEffectRemote, state.Position, rock, "Normal", hitPositionFor(state, oreDef, rock, player), player.UserId, 0, 0, pickaxe.Tier, "Blocked")
		return
	end

	-- 판정
	local swingTime = TimingService.resolveSwingTime(clientTime)
	local judgment = TimingService.judge(player, rock, swingTime, isTouch)
	local ghostDuration = TimingService.recordHit(player, rock, swingTime)
	OreService.recordJudgment(rock, player, judgment)

	-- 데미지: 기본 데미지 × 곡괭이 Power × 판정 배수 (Perfect 2배, Nice 1.5배)
	local damage = Config.Mining.BaseDamage * PickaxeService.getPower(pickaxe) * Config.Judgment.DamageMultiplier[judgment]
	-- 번개 (다이아몬드 도끼 등 LightningChance가 있는 도구로 나무를 칠 때): 남은 HP를 한 번에 깎는다
	local toolConfig = Config.Pickaxes[pickaxe.Id]
	local special: string? = nil
	-- 다 모은 강타: 마나를 써서 데미지 배수 (마나가 모자라면 보통 타격)
	if charge >= 1 and ManaService.spend(player, Config.Charge.ManaCost) then
		special = "Charged"
		damage *= Config.Charge.Multiplier
	end
	if oreDef.Kind == "Tree" and toolConfig and toolConfig.LightningChance and random:NextNumber() < toolConfig.LightningChance then
		special = "Lightning"
		damage = math.max(damage, state.Hp)
	end
	local depleted = OreService.applyDamage(rock, player, damage)

	local hitPosition = hitPositionFor(state, oreDef, rock, player)

	fireNearby(hitEffectRemote, state.Position, rock, judgment, hitPosition, player.UserId, swingTime, ghostDuration, pickaxe.Tier, special)

	if depleted then
		if FeverService.roll() then
			FeverService.start(player, rock, function(multiplier)
				finishRock(state, player, multiplier)
			end)
		else
			finishRock(state, nil, 1)
		end
	end
end

-- 서버 시작 시 한 번 호출 (OreService.init 이후)
function MiningService.init()
	hitEffectRemote = Remotes.get(Remotes.Names.HitEffect)
	rockBrokenRemote = Remotes.get(Remotes.Names.RockBroken)
	Remotes.get(Remotes.Names.SwingRequest).OnServerEvent:Connect(onSwingRequest)
end

return MiningService
