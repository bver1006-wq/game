--!strict
-- 구르기·무기별 스킬 (2026-10-09 사용자 요청). 클라이언트는 "구르고 싶다"·"스킬을 쓰고 싶다"만 보낸다.
--   구르기(RollRequest): 쿨다운·마나를 확인하고 잠깐 무적(MobService.protect "Roll"). 움직임은 클라가 한다 (캐릭터 물리는 클라 소유)
--   스킬(SkillRequest): 들고 있는 도구 종류에 맞는 스킬 하나 (Config.Skills의 Kind)
--     칼 = 방패 막기(Block): 잠깐 몹 피해를 크게 줄인다
--     방망이 = 내려찍기(Slam): 둘레 몹에게 센 타격 + 기절(MobService.stun) + 밀쳐 내기
--     활 = 연사(RapidFire): 노리는 몹에게 화살 여러 발 (화살을 그만큼 쓴다)
--     곡괭이·도끼 = 강하게 찍기(PowerStrike): 다음 한 번이 세다 (MiningService.armPowerStrike, 장비 벽·주인 규칙 그대로)
--   전부 서버가 검사한다: 맞는 종류를 들었나, 마나, 쿨다운, 거리, 주인, 장비 벽, 피버 중인지
--   성공하면 SkillEffect(kind, userId, position, data)를 근처 플레이어에게 보내 연출·쿨다운 표시를 시작한다

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local OreDefs = require(ReplicatedStorage.Shared.OreDefs)
local PickaxeDefs = require(ReplicatedStorage.Shared.PickaxeDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local AntiCheatService = require(script.Parent.AntiCheatService)
local CombatService = require(script.Parent.CombatService)
local EquipmentService = require(script.Parent.EquipmentService)
local FeverService = require(script.Parent.FeverService)
local ManaService = require(script.Parent.ManaService)
local MiningService = require(script.Parent.MiningService)
local MobService = require(script.Parent.MobService)
local NotifyService = require(script.Parent.NotifyService)
local OreService = require(script.Parent.OreService)
local OwnershipService = require(script.Parent.OwnershipService)
local PickaxeService = require(script.Parent.PickaxeService)

local SkillService = {}

local effectRemote: RemoteEvent
local lastRoll: { [Player]: number } = {}
local lastSkill: { [Player]: { [string]: number } } = {} -- 스킬 Id마다 따로 (도구를 바꿔도 쿨다운이 안 풀린다)
local lastNotice: { [Player]: number } = {}

-- 도구 종류 → 스킬 Id (Config.Skills의 Kind 목록으로 만든다)
local skillByKind: { [string]: string } = {}
for id, def in Config.Skills :: any do
	if typeof(def) == "table" and typeof(def.Kind) == "table" then
		for _, kind in def.Kind do
			skillByKind[kind] = id
		end
	end
end

-- 위치 근처의 플레이어에게 연출을 보낸다 (except는 빼고)
local function fireNearby(position: Vector3, except: Player?, ...: any)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if player ~= except and root and root:IsA("BasePart") and (root.Position - position).Magnitude <= Config.Combat.MobBroadcastRange then
			effectRemote:FireClient(player, ...)
		end
	end
end

-- 살아 있는 캐릭터의 뿌리 부품
local function aliveRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return root
	end
	return nil
end

-- 알림을 너무 자주 띄우지 않는다 (연타 방지)
local function notify(player: Player, message: string)
	local now = os.clock()
	if now - (lastNotice[player] or -math.huge) < 1 then
		return
	end
	lastNotice[player] = now
	NotifyService.send(player, message, "bad")
end

-- 마나가 충분한지 미리 본다 (실제로 쓰는 건 모든 검사가 끝난 뒤 ManaService.spend)
local function hasMana(player: Player, amount: number): boolean
	if ManaService.get(player) < amount then
		notify(player, "마나가 모자라요! 마을에서 쉬거나 마나 베리를 먹어요.")
		return false
	end
	return true
end

-- 숫자가 정상인지 (NaN·무한대 거르기)
local function finite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

-- RollRequest: (direction) 구르기. 방향은 수평으로만 쓰고, 이상하면 바라보는 쪽
local function onRoll(player: Player, directionArg: unknown)
	local root = aliveRoot(player)
	if not root or FeverService.isActive(player) then
		return
	end
	local roll = Config.Roll
	local now = os.clock()
	if now - (lastRoll[player] or -math.huge) < roll.Cooldown - roll.CooldownTolerance then
		return
	end
	local direction = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if typeof(directionArg) == "Vector3" then
		local flat = (directionArg :: Vector3) * Vector3.new(1, 0, 1)
		if finite(flat.X) and finite(flat.Z) and flat.Magnitude > 0.01 then
			direction = flat
		end
	end
	direction = if direction.Magnitude > 0.01 then direction.Unit else Vector3.zAxis
	if not hasMana(player, roll.ManaCost) or not ManaService.spend(player, roll.ManaCost) then
		return
	end
	lastRoll[player] = now
	MobService.protect(player, "Roll", 1, roll.IFrame)
	-- 구른 사람은 이미 자기 화면에서 굴렀다. 다른 사람에게만 연출
	fireNearby(root.Position, player, "Roll", player.UserId, root.Position, direction)
end

-- 방패 막기 (칼). 방패를 차고 있으면 더 많이·더 오래 막는다 (Config.Skills.Block ShieldReduction·ShieldDuration, 2026-10-10)
local function useBlock(player: Player, root: BasePart): boolean
	local def = Config.Skills.Block
	if not ManaService.spend(player, def.ManaCost) then
		return false
	end
	local withShield = EquipmentService.hasActiveShield(player)
	local reduction = if withShield then def.ShieldReduction else def.Reduction
	local duration = if withShield then def.ShieldDuration else def.Duration
	MobService.protect(player, "Block", reduction, duration)
	fireNearby(root.Position, nil, "Block", player.UserId, root.Position, duration)
	return true
end

-- 내려찍기 (방망이): 둘레 몹을 세게 치고 기절시킨다. 남이 사냥 중인 몹은 건너뛴다
local function useSlam(player: Player, root: BasePart): boolean
	local def = Config.Skills.Slam
	if not ManaService.spend(player, def.ManaCost) then
		return false
	end
	local stunned: { Model } = {}
	for _, state in MobService.getAllStates() do
		local offset = state.Position - root.Position
		local flat = (offset * Vector3.new(1, 0, 1)).Magnitude - state.Radius
		if flat <= def.Radius and math.abs(offset.Y) <= def.Radius and OwnershipService.canHit(state, player) then
			local mob = state.Model
			local damage = CombatService.skillHit(player, mob, def.DamageMultiplier, def.Knockback)
			-- 흠집도 못 내면(장비 벽) 기절도 안 한다
			if damage > 0 and MobService.getState(mob) then
				MobService.stun(mob, def.StunTime)
				table.insert(stunned, mob)
			end
		end
	end
	fireNearby(root.Position, nil, "Slam", player.UserId, root.Position, stunned)
	return true
end

-- 연사 (활): 노리는 몹에게 화살 여러 발. 한 발마다 화살 1개 (모자라면 거기서 멈춤)
local function useRapidFire(player: Player, root: BasePart, weapon: PickaxeDefs.PickaxeDef, targetArg: unknown): boolean
	local def = Config.Skills.RapidFire
	if typeof(targetArg) ~= "Instance" or not (targetArg :: Instance):IsA("Model") then
		return false
	end
	local mob = targetArg :: Model
	if not CollectionService:HasTag(mob, MobService.Tag) then
		return false
	end
	local state = MobService.getState(mob)
	local config = Config.Weapons[weapon.Id]
	if not state or not config then
		return false
	end
	if not OwnershipService.canHit(state, player) then
		OwnershipService.notifyBlocked(player, "다른 사람이 사냥 중인 몹이에요.")
		return false
	end
	local flat = ((state.Position - root.Position) * Vector3.new(1, 0, 1)).Magnitude
	if flat > config.Range + state.Radius + Config.Combat.RangeTolerance then
		return false
	end
	if EquipmentService.getArrows(player) <= 0 then
		notify(player, "화살이 없어요!")
		return false
	end
	if not ManaService.spend(player, def.ManaCost) then
		return false
	end
	fireNearby(root.Position, nil, "RapidFire", player.UserId, root.Position, mob)
	for index = 1, def.Arrows do
		task.delay((index - 1) * def.Interval, function()
			-- 쏘는 사이 활을 내려놓았거나 몹이 쓰러졌으면 그만
			local held = PickaxeService.getEquipped(player)
			if not held or held.Kind ~= "Bow" or not MobService.getState(mob) or not aliveRoot(player) then
				return
			end
			if EquipmentService.useArrow(player) then
				CombatService.skillHit(player, mob, def.DamageMultiplier, nil)
			end
		end)
	end
	return true
end

-- 강하게 찍기 (곡괭이·도끼): 가까운 바위·나무를 노리고 다음 한 번을 세게. 장비 벽이면 마나를 안 쓰고 알린다
local function usePowerStrike(player: Player, weapon: PickaxeDefs.PickaxeDef, targetArg: unknown): boolean
	local def = Config.Skills.PowerStrike
	if typeof(targetArg) ~= "Instance" or not (targetArg :: Instance):IsA("Model") then
		return false
	end
	local rock = targetArg :: Model
	if not CollectionService:HasTag(rock, OreService.Tag) then
		return false
	end
	local state = OreService.getState(rock)
	local oreDef = state and OreDefs[state.OreType]
	if not state or state.Depleted or not oreDef then
		return false
	end
	local neededKind: PickaxeDefs.ToolKind = if oreDef.Kind == "Tree" then "Axe" else "Pickaxe"
	if weapon.Kind ~= neededKind then
		notify(player, if neededKind == "Axe" then "나무는 도끼로 베어야 해요." else "바위는 곡괭이로 캐야 해요.")
		return false
	end
	if not AntiCheatService.isInRange(player, state.Position, state.ExtraReach) then
		return false
	end
	if not OwnershipService.canHit(state, player) then
		OwnershipService.notifyBlocked(player, if oreDef.Kind == "Tree" then "다른 사람이 베고 있는 나무예요." else "다른 사람이 캐고 있는 바위예요.")
		return false
	end
	if weapon.Tier < oreDef.RequiredTier then
		notify(player, "너무 단단해요! 더 좋은 도구가 필요해요.")
		return false
	end
	if not ManaService.spend(player, def.ManaCost) then
		return false
	end
	MiningService.armPowerStrike(player, def.ArmTime)
	fireNearby(state.Position, nil, "PowerStrike", player.UserId, state.Position, rock)
	return true
end

-- SkillRequest: (target) 들고 있는 도구에 맞는 스킬. target은 연사(몹)·강하게 찍기(바위·나무)만 쓴다
local function onSkill(player: Player, targetArg: unknown)
	local root = aliveRoot(player)
	if not root or FeverService.isActive(player) then
		return
	end
	local weapon = PickaxeService.getEquipped(player)
	local skillId = weapon and skillByKind[weapon.Kind]
	local def = skillId and (Config.Skills :: any)[skillId]
	if not weapon or not skillId or not def then
		return
	end
	local now = os.clock()
	local times = lastSkill[player]
	if not times then
		times = {}
		lastSkill[player] = times
	end
	if now - (times[skillId] or -math.huge) < def.Cooldown - Config.Skills.CooldownTolerance then
		return
	end
	if not hasMana(player, def.ManaCost) then
		return
	end
	local used = false
	if skillId == "Block" then
		used = useBlock(player, root)
	elseif skillId == "Slam" then
		used = useSlam(player, root)
	elseif skillId == "RapidFire" then
		used = useRapidFire(player, root, weapon, targetArg)
	elseif skillId == "PowerStrike" then
		used = usePowerStrike(player, weapon, targetArg)
	end
	if used then
		times[skillId] = now
	end
end

-- 서버 시작 시 한 번 호출 (MobService·CombatService·MiningService.init 이후)
function SkillService.init()
	effectRemote = Remotes.get(Remotes.Names.SkillEffect)
	Remotes.get(Remotes.Names.RollRequest).OnServerEvent:Connect(onRoll)
	Remotes.get(Remotes.Names.SkillRequest).OnServerEvent:Connect(onSkill)
	Players.PlayerRemoving:Connect(function(player)
		lastRoll[player] = nil
		lastSkill[player] = nil
		lastNotice[player] = nil
	end)
end

return SkillService
