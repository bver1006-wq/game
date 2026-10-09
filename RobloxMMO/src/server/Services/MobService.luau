--!strict
-- 몹 생성·이동(AI)·체력·처치 보상.
-- Workspace/MobSpawns의 생성 자리(속성 MobType)마다 몹을 하나씩 두고, 쓰러지면 Respawn초 뒤 같은 자리에 다시 만든다.
-- 몹 모델은 고정된 뿌리 부품(Root)에 나머지가 용접돼 있어서, 서버가 PivotTo로 옮기면 통째로 따라온다.
-- 체력·기여도는 서버 메모리에 두고, 클라이언트에는 Mob 태그와 MobType·Hp·MaxHp 속성만 보인다.

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
	Target: Player?,
	NextAttack: number,
	WanderTarget: Vector3?,
	WanderUntil: number,
	Knockback: Vector3, -- 밀려나는 속도 (스터드/초)
	KnockbackUntil: number,
	LungeUntil: number,
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

	local model = template:Clone()
	model.Name = mobType
	local home = Vector3.new(spawnPart.Position.X, groundY(spawnPart.Position, spawnPart.Position.Y - 1), spawnPart.Position.Z)
	local facing = Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1))
	facing = if facing.Magnitude > 0.01 then facing.Unit else Vector3.zAxis
	model:PivotTo(CFrame.lookAt(home, home + facing))
	local size = model:GetExtentsSize()

	model:SetAttribute("MobType", mobType)
	model:SetAttribute("MaxHp", config.Hp)
	model:SetAttribute("Hp", config.Hp)
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
		Radius = math.max(size.X, size.Z) / 2,
		Hp = config.Hp,
		MaxHp = config.Hp,
		Target = nil,
		NextAttack = 0,
		WanderTarget = nil,
		WanderUntil = os.clock() + random:NextNumber(0, 3),
		Knockback = Vector3.zero,
		KnockbackUntil = 0,
		LungeUntil = 0,
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

	-- 쫓던 대상이 사라졌거나 너무 멀어졌으면 포기한다
	local target = state.Target
	if target then
		local root = aliveRoot(target)
		if not root or (state.Position - state.Home).Magnitude > ai.Leash or (root.Position - state.Position).Magnitude > config.Aggro * 2 then
			state.Target = nil
		end
	end
	-- 가까이 온 플레이어를 알아챈다 (집 근처에 있을 때만). 주인이 있으면 주인만 노린다 (남은 반격을 못 하니까)
	OwnershipService.expire(state, state.Model, now)
	local owner = OwnershipService.ownerOf(state)
	if not state.Target and (state.Position - state.Home).Magnitude < ai.Leash * 0.6 then
		local best, bestDistance = nil, config.Aggro
		for _, player in Players:GetPlayers() do
			local root = aliveRoot(player)
			if root and (owner == nil or owner == player.UserId) then
				local distance = (root.Position - state.Position).Magnitude
				if distance < bestDistance then
					best, bestDistance = player, distance
				end
			end
		end
		state.Target = best
	end

	local goal: Vector3? = nil
	local speed = config.Speed
	if now < state.KnockbackUntil then
		-- 맞아서 밀려나는 중
		state.Position += state.Knockback * dt
	elseif state.Target then
		local root, humanoid = aliveRoot(state.Target)
		if root and humanoid then
			local flat = (root.Position - state.Position) * Vector3.new(1, 0, 1)
			if flat.Magnitude > 0.05 then
				state.Facing = flat.Unit
			end
			if flat.Magnitude > config.AttackRange * 0.8 then
				goal = root.Position
			elseif now >= state.NextAttack then
				-- 공격: 앞으로 살짝 들이받고 피해를 준다 (피버 중인 플레이어는 무적)
				state.NextAttack = now + config.AttackInterval
				state.LungeUntil = now + 0.15
				local player = state.Target :: Player
				if not FeverService.isActive(player) then
					local damage = EquipmentService.reduceDamage(player, config.Damage) -- 방어구로 줄인다
					humanoid:TakeDamage(damage)
					fireNearby(attackRemote, state.Position, state.Model, player.UserId, damage)
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
			state.WanderTarget = state.Home + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
		end
		goal = state.WanderTarget
		speed *= 0.45
	end

	-- 자연 회복: 쫓는 대상이 없고 한동안 안 맞았으면 천천히 찬다
	if not state.Target and state.Hp < state.MaxHp and now - state.LastHit >= Config.Regen.Delay then
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
			state.Facing = flat.Unit
			state.Position += flat.Unit * math.min(speed * dt, distance)
			moving = true
		end
	end
	moving = moving or now < state.KnockbackUntil

	-- 땅에 붙인다
	state.Position = Vector3.new(state.Position.X, groundY(state.Position, state.Position.Y), state.Position.Z)

	-- 흔들림: 슬라임은 통통 튀고, 나머지는 걸을 때 살짝 위아래로
	local bob = 0
	if moving then
		state.Phase += dt * (if def.Hop then 7 else 10)
		bob = math.abs(math.sin(state.Phase)) * (if def.Hop then ai.HopHeight else ai.WalkBob)
	elseif def.Hop then
		state.Phase += dt * 3
		bob = math.abs(math.sin(state.Phase)) * 0.15 -- 제자리에서 말랑말랑
	end
	local lunge = if now < state.LungeUntil then ai.LungeDistance else 0
	local base = state.Position + Vector3.new(0, bob, 0) + state.Facing * lunge
	state.Model:PivotTo(CFrame.lookAt(base, base + state.Facing))
end

-- 몹을 쓰러뜨린다: 보상 → 연출 알림 → 제거 → 다시 생성 예약
local function die(state: MobState, killer: Player)
	state.Dead = true
	states[state.Model] = nil
	local config = Config.Mobs[state.Type]
	local def = MobDefs[state.Type]

	local gold = random:NextInteger(config.Gold[1], config.Gold[2])
	local lootCount = random:NextInteger(config.Loot[1], config.Loot[2])
	InventoryService.addGold(killer, gold)
	local added = InventoryService.add(killer, def.LootId, lootCount)
	if added < lootCount then
		NotifyService.send(killer, "가방이 가득 찼어요! 마을 상인에게 팔고 오세요.", "bad")
	end
	fireNearby(diedRemote, state.Position, state.Position, state.Type, killer.UserId, gold, def.LootId, added)
	print(`[MobService] {killer.Name}이(가) {def.DisplayName} 처치: {gold}G, {ItemDefs.Items[def.LootId].DisplayName} {added}개`)

	state.Model:Destroy()
	local spawnPart = state.SpawnPart
	task.delay(config.Respawn, function()
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
	state.Target = player -- 때린 사람을 쫓는다 (데미지가 안 들어가도 화는 난다)
	state.LastHit = os.clock()
	if amount <= 0 then
		return false
	end
	state.Hp = math.max(state.Hp - amount, 0)
	mob:SetAttribute("Hp", state.Hp)
	OwnershipService.claim(state, mob, player) -- 데미지를 준 사람이 주인 (흠집도 못 내면 주인이 안 된다)
	state.Target = player -- 때린 사람을 쫓는다
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

-- 서버 시작 시 한 번 호출 (InventoryService.init 이후)
function MobService.init()
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
