--!strict
-- 몹 생성·이동(AI)·체력·처치 보상.
-- Workspace/MobSpawns의 생성 자리(속성 MobType)마다 몹을 하나씩 두고, 쓰러지면 Respawn초 뒤 같은 자리에 다시 만든다.
-- 몹 모델은 고정된 뿌리 부품(Root)에 나머지가 용접돼 있어서, 서버가 PivotTo로 옮기면 통째로 따라온다.
-- 체력·기여도는 서버 메모리에 두고, 클라이언트에는 Mob 태그와 MobType·Hp·MaxHp·Boss·BossScale 속성만 보인다.
-- 마을 안전지대(TownArrival·ShopNPC 둘레 Config.MobAI.SafeZoneRadius)에는 몹이 생기지도, 들어가지도 않는다.
-- 얌전한 몹(Config.Mobs의 Passive, 슬라임)은 먼저 공격하지 않고, 맞으면 잠깐 도망친다.
-- 생성 때 Config.MobBoss 확률로 크고 센 보스가 된다 (Model:ScaleTo, 보상도 크기만큼).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local ItemDefs = require(ReplicatedStorage.Shared.ItemDefs)
local MobDefs = require(ReplicatedStorage.Shared.MobDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local EquipmentService = require(script.Parent.EquipmentService)
local FeverService = require(script.Parent.FeverService)
local InventoryService = require(script.Parent.InventoryService)
local NotifyService = require(script.Parent.NotifyService)
local OwnershipService = require(script.Parent.OwnershipService)

-- 몹 하나의 서버 상태
export type MobState = {
	Model: Model,
	Type: string,
	SpawnPart: BasePart,
	Home: Vector3, -- 생성 자리 (어슬렁거리는 중심, 쫓다가 돌아오는 곳)
	Position: Vector3, -- 발밑 위치
	Facing: Vector3, -- 바라보는 수평 방향
	Height: number,
	Radius: number,
	Hp: number,
	MaxHp: number,
	Boss: boolean, -- 보스인지
	Scale: number, -- 보스 크기 배율 (보통 몹은 1)
	Damage: number, -- 한 번에 주는 피해 (보스는 커진 만큼)
	AttackRange: number, -- 공격 거리 (보스는 몸이 커진 만큼 더 멀리)
	Speed: number,
	Target: Player?,
	FleeFrom: Player?, -- 얌전한 몹이 도망치는 상대
	FleeUntil: number,
	NextAttack: number,
	WanderTarget: Vector3?,
	WanderUntil: number,
	Knockback: Vector3, -- 밀려나는 속도 (스터드/초)
	KnockbackUntil: number,
	LungeUntil: number,
	StunUntil: number, -- 이 시각까지 기절 (움직이지도 공격하지도 못함, 방망이 내려찍기)
	Phase: number, -- 걷기·통통 튀기 흔들림 위상
	LastHit: number, -- 마지막으로 맞은 시각 (자연 회복용)
	Owner: number?, -- 주인 UserId (OwnershipService)
	OwnerAt: number,
	Dead: boolean,
}

local MOB_TAG = "Mob"

local MobService = {}
MobService.Tag = MOB_TAG

local states: { [Model]: MobState } = {}
local random = Random.new()
local mobsFolder: Folder
local templatesFolder: Instance?
local spawnsFolder: Instance?
local attackRemote: RemoteEvent
local diedRemote: RemoteEvent

local safePoints: { Vector3 } = {} -- 안전지대 가운데들 (마을 도착점·NPC)

-- 플레이어가 몹 피해를 덜 받는 시간 (구르기 무적·방패 막기). 출처마다 { 줄이는 비율, 끝 시각 }
type Guard = { Reduction: number, Until: number }
local guards: { [Player]: { [string]: Guard } } = {}

-- 지금 받는 피해를 얼마나 줄이는지 (0~1, 1이면 안 맞음). 끝난 기록은 지운다
local function guardReduction(player: Player, now: number): number
	local list = guards[player]
	if not list then
		return 0
	end
	local best = 0
	for source, guard in list do
		if now >= guard.Until then
			list[source] = nil
		else
			best = math.max(best, guard.Reduction)
		end
	end
	return best
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = false

-- 위치 근처의 플레이어에게 이벤트를 보낸다
local function fireNearby(remote: RemoteEvent, position: Vector3, ...: any)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - position).Magnitude <= Config.Combat.MobBroadcastRange then
			remote:FireClient(player, ...)
		end
	end
end

-- 살아 있는 캐릭터의 뿌리 부품과 Humanoid
local function aliveRoot(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return root, humanoid
	end
	return nil, nil
end

-- 레이 검사에서 뺄 것: 몹, 생성 자리, 캐릭터들
local function refreshGroundFilter()
	local list: { Instance } = { mobsFolder }
	if spawnsFolder then
		table.insert(list, spawnsFolder)
	end
	for _, name in { "Ores", "OreSpawns", "ClientEffects" } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(list, folder)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	groundParams.FilterDescendantsInstances = list
end

-- 수평 위치 아래의 땅 높이 (못 찾으면 fallbackY)
local function groundY(position: Vector3, fallbackY: number): number
	local result = Workspace:Raycast(position + Vector3.new(0, 8, 0), Vector3.new(0, -40, 0), groundParams)
	return if result then result.Position.Y else fallbackY
end

-- 안전지대 가운데 목록을 새로 읽는다 (마을 도착점 + 상점 NPC)
local function refreshSafePoints()
	local list: { Vector3 } = {}
	for _, tag in { "TownArrival", "ShopNPC" } do
		for _, instance in CollectionService:GetTagged(tag) do
			if instance:IsA("Model") then
				table.insert(list, instance:GetPivot().Position)
			elseif instance:IsA("BasePart") then
				table.insert(list, instance.Position)
			end
		end
	end
	safePoints = list
end

-- 위치가 안전지대 안으로 얼마나 깊이 들어가 있는지 (0이면 바깥). 높이는 무시한다
local function safeDepth(position: Vector3): number
	local radius = Config.MobAI.SafeZoneRadius
	local depth = 0
	for _, point in safePoints do
		local flat = Vector3.new(position.X - point.X, 0, position.Z - point.Z).Magnitude
		depth = math.max(depth, radius - flat)
	end
	return depth
end

-- from에서 to로 가면 안전지대에 (더 깊이) 들어가는지. 안에 갇힌 몹이 밖으로 나가는 건 막지 않는다
local function entersSafeZone(from: Vector3, to: Vector3): boolean
	local depth = safeDepth(to)
	return depth > 0 and depth >= safeDepth(from)
end

-- 이번 생성이 보스인지 정하고 크기 배율을 돌려준다 (보스가 아니면 nil)
local function rollBoss(spawnPart: BasePart): number?
	local boss = Config.MobBoss
	local chance = if spawnPart:GetAttribute("BossSpot") == true then boss.SpotChance else boss.Chance
	if random:NextNumber() >= chance then
		return nil
	end
	return random:NextNumber(boss.Scale[1], boss.Scale[2])
end

-- 생성 자리에 몹을 하나 만든다
local function spawnMob(spawnPart: BasePart)
	local mobType = spawnPart:GetAttribute("MobType")
	if typeof(mobType) ~= "string" then
		return
	end
	local def = MobDefs[mobType]
	local config = Config.Mobs[mobType]
	local template = templatesFolder and templatesFolder:FindFirstChild(def and def.TemplateName or "")
	if not def or not config or not template or not template:IsA("Model") then
		return
	end

	if safeDepth(spawnPart.Position) > 0 then
		warn(`[MobService] {spawnPart:GetFullName()}은(는) 마을 안전지대 안이라 몹을 만들지 않아요`)
		return
	end

	local model = template:Clone()
	model.Name = mobType
	-- 보스: 기준점(발밑)을 중심으로 키운다. 템플릿이 이미 Config.Mobs.Scale만큼 커져 있으니 거기에 곱한다
	local bossScale = rollBoss(spawnPart)
	local scale = bossScale or 1
	if bossScale then
		model:ScaleTo(model:GetScale() * bossScale)
	end
	local home = Vector3.new(spawnPart.Position.X, groundY(spawnPart.Position, spawnPart.Position.Y - 1), spawnPart.Position.Z)
	local facing = Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1))
	facing = if facing.Magnitude > 0.01 then facing.Unit else Vector3.zAxis
	model:PivotTo(CFrame.lookAt(home, home + facing))
	local size = model:GetExtentsSize()
	local radius = math.max(size.X, size.Z) / 2

	local bossConfig = Config.MobBoss
	local maxHp = if bossScale then math.floor(config.Hp * bossConfig.HpPerScale * scale + 0.5) else config.Hp
	local damage = if bossScale then config.Damage * bossConfig.DamagePerScale * scale else config.Damage
	local speed = if bossScale then config.Speed * bossConfig.SpeedMultiplier else config.Speed
	-- 커진 몸만큼 공격 거리를 늘린다 (원래 반지름 = 지금 반지름 / 배율)
	local attackRange = config.AttackRange + radius * (1 - 1 / scale)

	model:SetAttribute("MobType", mobType)
	model:SetAttribute("MaxHp", maxHp)
	model:SetAttribute("Hp", maxHp)
	if bossScale then
		model:SetAttribute("Boss", true)
		model:SetAttribute("BossScale", math.floor(bossScale * 100 + 0.5) / 100)
	end
	CollectionService:AddTag(model, MOB_TAG)
	model.Parent = mobsFolder

	states[model] = {
		Model = model,
		Type = mobType,
		SpawnPart = spawnPart,
		Home = home,
		Position = home,
		Facing = facing,
		Height = size.Y,
		Radius = radius,
		Hp = maxHp,
		MaxHp = maxHp,
		Boss = bossScale ~= nil,
		Scale = scale,
		Damage = damage,
		AttackRange = attackRange,
		Speed = speed,
		Target = nil,
		FleeFrom = nil,
		FleeUntil = 0,
		NextAttack = 0,
		WanderTarget = nil,
		WanderUntil = os.clock() + random:NextNumber(0, 3),
		Knockback = Vector3.zero,
		KnockbackUntil = 0,
		LungeUntil = 0,
		StunUntil = 0,
		Phase = random:NextNumber(0, math.pi * 2),
		LastHit = 0,
		Owner = nil,
		OwnerAt = 0,
		Dead = false,
	}
end

-- 몹 하나의 생각·움직임 (dt초만큼)
local function stepMob(state: MobState, dt: number, now: number)
	local config = Config.Mobs[state.Type]
	local ai = Config.MobAI
	local def = MobDefs[state.Type]
	local passive = config.Passive == true

	-- 쫓던 대상이 사라졌거나, 너무 멀어졌거나, 마을 안전지대로 들어갔으면 포기한다
	local target = state.Target
	if target then
		local root = aliveRoot(target)
		if
			not root
			or passive
			or (state.Position - state.Home).Magnitude > ai.Leash
			or (root.Position - state.Position).Magnitude > config.Aggro * 2
			or safeDepth(root.Position) > 0
		then
			state.Target = nil
		end
	end
	-- 얌전한 몹의 도망은 FleeTime이 지나면 진정한다
	if state.FleeFrom and now >= state.FleeUntil then
		state.FleeFrom = nil
	end
	-- 가까이 온 플레이어를 알아챈다 (집 근처에 있을 때만, 얌전한 몹은 안 함). 주인이 있으면 주인만 노린다 (남은 반격을 못 하니까)
	OwnershipService.expire(state, state.Model, now)
	local owner = OwnershipService.ownerOf(state)
	if not passive and not state.Target and (state.Position - state.Home).Magnitude < ai.Leash * 0.6 then
		local best, bestDistance = nil, config.Aggro
		for _, player in Players:GetPlayers() do
			local root = aliveRoot(player)
			if root and (owner == nil or owner == player.UserId) and safeDepth(root.Position) <= 0 then
				local distance = (root.Position - state.Position).Magnitude
				if distance < bestDistance then
					best, bestDistance = player, distance
				end
			end
		end
		state.Target = best
	end

	local goal: Vector3? = nil
	local speed = state.Speed
	local fleeing = false
	if now < state.KnockbackUntil then
		-- 맞아서 밀려나는 중 (안전지대 안으로는 안 밀린다)
		local nextPosition = state.Position + state.Knockback * dt
		if entersSafeZone(state.Position, nextPosition) then
			state.KnockbackUntil = 0
		else
			state.Position = nextPosition
		end
	elseif now < state.StunUntil then
		-- 기절: 제자리에서 꼼짝 못 하고 공격도 못 한다 (쫓던 대상은 기억한다)
		goal = nil
	elseif state.FleeFrom then
		-- 도망: 때린 사람 반대쪽으로 빠르게
		fleeing = true
		local root = aliveRoot(state.FleeFrom)
		local away = if root then (state.Position - root.Position) * Vector3.new(1, 0, 1) else state.Facing
		away = if away.Magnitude > 0.05 then away.Unit else state.Facing
		goal = state.Position + away * 6
		speed *= config.FleeSpeed or 1.5
	elseif state.Target then
		local root, humanoid = aliveRoot(state.Target)
		if root and humanoid then
			local flat = (root.Position - state.Position) * Vector3.new(1, 0, 1)
			if flat.Magnitude > 0.05 then
				state.Facing = flat.Unit
			end
			if flat.Magnitude > state.AttackRange * 0.8 then
				goal = root.Position
			elseif now >= state.NextAttack and state.Damage > 0 then
				-- 공격: 앞으로 살짝 들이받고 피해를 준다 (피버 중인 플레이어는 무적)
				-- 구르기 무적·방패 막기 중이면 피해를 줄인다 (1이면 0, guarded = true로 알려 클라가 "피함!"·"막음!")
				state.NextAttack = now + config.AttackInterval
				state.LungeUntil = now + 0.15
				local player = state.Target :: Player
				if not FeverService.isActive(player) then
					local damage = EquipmentService.reduceDamage(player, state.Damage) -- 방어구로 줄인다
					local reduction = guardReduction(player, now)
					if reduction > 0 then
						damage = if reduction >= 1 then 0 else damage * (1 - reduction)
					end
					if damage > 0 then
						humanoid:TakeDamage(damage)
					end
					fireNearby(attackRemote, state.Position, state.Model, player.UserId, math.round(damage * 10) / 10, reduction > 0)
				end
			end
		end
	else
		-- 한가할 때: 집 주변을 어슬렁거리다 잠깐 쉰다. 집에서 멀어졌으면 돌아간다
		if (state.Position - state.Home).Magnitude > ai.WanderRadius * 1.5 then
			state.WanderTarget = state.Home
		elseif not state.WanderTarget and now >= state.WanderUntil then
			local angle = random:NextNumber(0, math.pi * 2)
			local r = random:NextNumber(2, ai.WanderRadius)
			local wander = state.Home + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
			if safeDepth(wander) > 0 then
				state.WanderUntil = now + random:NextNumber(ai.WanderPause[1], ai.WanderPause[2]) -- 마을 쪽이면 이번엔 쉰다
			else
				state.WanderTarget = wander
			end
		end
		goal = state.WanderTarget
		speed *= 0.45
	end

	-- 자연 회복: 쫓거나 도망치는 중이 아니고 한동안 안 맞았으면 천천히 찬다
	if not state.Target and not fleeing and state.Hp < state.MaxHp and now - state.LastHit >= Config.Regen.Delay then
		state.Hp = math.min(state.MaxHp, state.Hp + state.MaxHp * Config.Regen.MobPercentPerSecond * dt)
		state.Model:SetAttribute("Hp", math.floor(state.Hp * 10 + 0.5) / 10)
	end

	local moving = false
	if goal then
		local flat = (goal - state.Position) * Vector3.new(1, 0, 1)
		local distance = flat.Magnitude
		if distance < 0.5 then
			if goal == state.WanderTarget then
				state.WanderTarget = nil
				state.WanderUntil = now + random:NextNumber(ai.WanderPause[1], ai.WanderPause[2])
			end
		else
			-- 안전지대 쪽이면 돌아간다: 도망은 옆으로 비켜 보고, 쫓기는 포기하고 집으로
			local step = math.min(speed * dt, distance)
			local direction: Vector3? = flat.Unit
			if entersSafeZone(state.Position, state.Position + flat.Unit * step) then
				direction = nil
				if fleeing then
					for _, angle in { 70, -70, 120, -120 } do
						local side = CFrame.Angles(0, math.rad(angle), 0):VectorToWorldSpace(flat.Unit)
						if not entersSafeZone(state.Position, state.Position + side * step) then
							direction = side
							break
						end
					end
				else
					state.Target = nil
					state.WanderTarget = state.Home
				end
			end
			if direction then
				state.Facing = direction
				state.Position += direction * step
				moving = true
			end
		end
	end
	moving = moving or now < state.KnockbackUntil

	-- 땅에 붙인다
	state.Position = Vector3.new(state.Position.X, groundY(state.Position, state.Position.Y), state.Position.Z)

	-- 흔들림: 슬라임은 통통 튀고, 나머지는 걸을 때 살짝 위아래로 (보스는 크기만큼)
	local bob = 0
	if moving then
		state.Phase += dt * (if def.Hop then 7 else 10) / math.sqrt(state.Scale)
		bob = math.abs(math.sin(state.Phase)) * (if def.Hop then ai.HopHeight else ai.WalkBob) * state.Scale
	elseif def.Hop then
		state.Phase += dt * 3
		bob = math.abs(math.sin(state.Phase)) * 0.15 * state.Scale -- 제자리에서 말랑말랑
	end
	local lunge = if now < state.LungeUntil then ai.LungeDistance * state.Scale else 0
	local base = state.Position + Vector3.new(0, bob, 0) + state.Facing * lunge
	state.Model:PivotTo(CFrame.lookAt(base, base + state.Facing))
end

-- 몹을 쓰러뜨린다: 보상(보스는 크기만큼 더) → 연출 알림 → 제거 → 다시 생성 예약
local function die(state: MobState, killer: Player)
	state.Dead = true
	states[state.Model] = nil
	local config = Config.Mobs[state.Type]
	local def = MobDefs[state.Type]
	local boss = Config.MobBoss

	local gold = random:NextInteger(config.Gold[1], config.Gold[2])
	local lootCount = random:NextInteger(config.Loot[1], config.Loot[2])
	if state.Boss then
		gold = math.floor(gold * boss.GoldPerScale * state.Scale + 0.5)
		lootCount = math.max(lootCount, math.floor(lootCount * boss.LootPerScale * state.Scale + 0.5))
	end
	InventoryService.addGold(killer, gold)
	local added = InventoryService.add(killer, def.LootId, lootCount)
	if added < lootCount then
		NotifyService.send(killer, "가방이 가득 찼어요! 마을 상인에게 팔고 오세요.", "bad")
	end
	if state.Boss then
		NotifyService.send(killer, `{boss.NamePrefix}{def.DisplayName}을(를) 물리쳤어요! +{gold}G`, "good")
	end
	fireNearby(diedRemote, state.Position, state.Position, state.Type, killer.UserId, gold, def.LootId, added)
	local label = if state.Boss then boss.NamePrefix .. def.DisplayName else def.DisplayName
	print(`[MobService] {killer.Name}이(가) {label} 처치: {gold}G, {ItemDefs.Items[def.LootId].DisplayName} {added}개`)

	state.Model:Destroy()
	local spawnPart = state.SpawnPart
	local delay = if state.Boss then config.Respawn * boss.RespawnMultiplier else config.Respawn
	task.delay(delay, function()
		if spawnPart.Parent then
			spawnMob(spawnPart)
		end
	end)
end

-- 몹 상태 (없거나 이미 쓰러졌으면 nil)
function MobService.getState(mob: Instance): MobState?
	if not mob:IsA("Model") then
		return nil
	end
	local state = states[mob]
	return if state and not state.Dead then state else nil
end

-- 몹에게 피해를 준다. 쓰러뜨렸으면 true. 검증(거리·쿨다운)은 호출하는 쪽(CombatService)이 끝낸 뒤 부른다
-- knockback이 있으면 direction 쪽으로 밀려난다 (방망이)
function MobService.damage(mob: Model, player: Player, amount: number, direction: Vector3, knockback: number?): boolean
	local state = states[mob]
	if not state or state.Dead then
		return false
	end
	-- 맞으면: 얌전한 몹(슬라임)은 때린 사람에게서 도망치고, 나머지는 때린 사람을 쫓는다 (데미지가 안 들어가도 화는 난다)
	local config = Config.Mobs[state.Type]
	local function react()
		if config.Passive then
			state.FleeFrom = player
			state.FleeUntil = os.clock() + (config.FleeTime or 4)
			state.Target = nil
		else
			state.Target = player
		end
	end
	react()
	state.LastHit = os.clock()
	if amount <= 0 then
		return false
	end
	state.Hp = math.max(state.Hp - amount, 0)
	mob:SetAttribute("Hp", state.Hp)
	OwnershipService.claim(state, mob, player) -- 데미지를 준 사람이 주인 (흠집도 못 내면 주인이 안 된다)
	if knockback and knockback > 0 then
		local time = Config.MobAI.KnockbackTime
		state.Knockback = direction * (knockback / time)
		state.KnockbackUntil = os.clock() + time
	end
	if state.Hp <= 0 then
		die(state, player)
		return true
	end
	return false
end

-- 몹을 seconds초 동안 기절시킨다 (방망이 내려찍기). 검증은 부르는 쪽(SkillService)이 끝낸 뒤 부른다
function MobService.stun(mob: Model, seconds: number)
	local state = states[mob]
	if not state or state.Dead or seconds <= 0 then
		return
	end
	state.StunUntil = math.max(state.StunUntil, os.clock() + seconds)
end

-- 플레이어가 seconds초 동안 몹 피해를 reduction(0~1)만큼 덜 받게 한다. source마다 따로 ("Roll" 구르기, "Block" 방패)
-- 겹치면 가장 많이 줄이는 것을 쓴다. 검증은 부르는 쪽(SkillService)이 끝낸 뒤 부른다
function MobService.protect(player: Player, source: string, reduction: number, seconds: number)
	local list = guards[player]
	if not list then
		list = {}
		guards[player] = list
	end
	list[source] = { Reduction = math.clamp(reduction, 0, 1), Until = os.clock() + seconds }
end

-- 모든 살아 있는 몹 상태 (방망이 내려찍기처럼 둘레의 몹을 찾을 때)
function MobService.getAllStates(): { MobState }
	local list = {}
	for _, state in states do
		if not state.Dead then
			table.insert(list, state)
		end
	end
	return list
end

-- 서버 시작 시 한 번 호출 (InventoryService.init 이후)
function MobService.init()
	Players.PlayerRemoving:Connect(function(player)
		guards[player] = nil
	end)
	attackRemote = Remotes.get(Remotes.Names.MobAttack)
	diedRemote = Remotes.get(Remotes.Names.MobDied)

	local templates = ServerStorage:FindFirstChild("Templates")
	templatesFolder = templates and templates:FindFirstChild("Mobs")
	spawnsFolder = Workspace:FindFirstChild("MobSpawns")
	local existing = Workspace:FindFirstChild("Mobs")
	if existing and existing:IsA("Folder") then
		mobsFolder = existing
	else
		mobsFolder = Instance.new("Folder")
		mobsFolder.Name = "Mobs"
		mobsFolder.Parent = Workspace
	end
	if not templatesFolder or not spawnsFolder then
		warn("[MobService] 몹 템플릿(ServerStorage/Templates/Mobs)이나 생성 자리(Workspace/MobSpawns)가 없어요")
		return
	end

	refreshGroundFilter()
	refreshSafePoints()
	local count = 0
	for _, child in spawnsFolder:GetChildren() do
		if child:IsA("BasePart") then
			spawnMob(child)
			count += 1
		end
	end
	print(`[MobService] 몹 {count}마리 생성`)

	-- 생각·움직임은 TickRate번/초. 근처에 플레이어가 없는 몹은 쉰다
	local accumulator = 0
	local interval = 1 / Config.MobAI.TickRate
	local filterTimer = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < interval then
			return
		end
		local step = math.min(accumulator, interval * 3)
		accumulator = 0
		filterTimer += step
		if filterTimer > 1 then
			filterTimer = 0
			refreshGroundFilter()
			refreshSafePoints()
		end
		local now = os.clock()
		local roots = {}
		for _, player in Players:GetPlayers() do
			local root = aliveRoot(player)
			if root then
				table.insert(roots, root.Position)
			end
		end
		for _, state in states do
			local awake = false
			for _, position in roots do
				if (position - state.Position).Magnitude < 200 then
					awake = true
					break
				end
			end
			if awake and not state.Dead then
				stepMob(state, step, now)
			end
		end
	end)
end

return MobService
