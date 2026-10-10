--!strict
-- 몹 생성·이동(AI)·체력·처치 보상.
-- Workspace/MobSpawns의 생성 자리(속성 MobType)마다 몹을 하나씩 두고, 쓰러지면 Respawn초 뒤 같은 자리에 다시 만든다.
-- 몹 모델은 고정된 뿌리 부품(Root)에 나머지가 용접돼 있어서, 서버가 PivotTo로 옮기면 통째로 따라온다.
-- 체력·기여도는 서버 메모리에 두고, 클라이언트에는 Mob 태그와 MobType·Hp·MaxHp·Boss·BossScale 속성만 보인다.
-- 마을 안전지대(TownArrival·ShopNPC 둘레 Config.MobAI.SafeZoneRadius)에는 몹이 생기지도, 들어가지도 않는다.
-- 얌전한 몹(Config.Mobs의 Passive, 슬라임)은 먼저 공격하지 않고, 맞으면 잠깐 도망친다.
-- 생성 때 Config.MobBoss 확률로 크고 센 보스가 된다 (Model:ScaleTo, 보상도 크기만큼).
-- 바다 생물(Config.Mobs의 Swim, 2026-10-09)은 stepSwimmer가 따로 움직인다: 지형 물 속에서 수면 아래·바닥 위로 3D로 헤엄치고,
--   물에 들어온 플레이어만 노리며, 대상이 물 밖으로 나가면 포기한다. 떼(생성 자리 속성 School)는 목적지를 같이 쓴다 (지금은 떼 몹 없음).
--   낙지는 먹물을 뿜는다(Ink → MobSpecial), 해파리는 닿으면 쏜다(Drift). Prick(맞으면 부풀어 찌름)은 물고기 삭제(2026-10-10) 뒤 쓰는 몹이 없다.
-- 활 쏘는 몹(Config.Mobs의 Ranged, 스켈레톤 궁수, 2026-10-10): 가까우면 물러나고 멀리서 화살을 쏜다.
--   화살은 날아가는 시간이 있고, 도착할 때 그 자리(HitRadius)에 있어야 맞는다 → 움직이거나 구르면 피한다. 연출은 MobSpecial "Arrow"
-- 거대 몬스터(Config.Mobs의 Specials, 2026-10-10): 큰 기술을 Windup초 동안 바닥에 표시(MobSpecial "Telegraph")한 뒤
--   내려찍기·발구르기(원 안 모두) 또는 돌진(지나가는 길에 닿은 사람)으로 때린다 ("Impact"). 기절하면 준비하던 기술이 취소된다.

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
local QuestService = require(script.Parent.QuestService)

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
	-- 바다 생물 (2026-10-09). 땅 몹은 Swim = false, 나머지는 안 쓴다
	Swim: boolean, -- 물 속을 헤엄치는지 (Config.Mobs Swim)
	School: string?, -- 물고기 떼 이름 (같은 떼는 목적지를 같이 쓴다)
	SchoolOffset: Vector3, -- 떼 목적지에서 내 자리까지
	BaseScale: number, -- 원래 크기 (복어가 부풀었다가 돌아올 크기)
	PuffUntil: number, -- 복어: 이 시각까지 부풀어 있다 (0이면 원래 크기)
	NextPrick: number, -- 복어: 다음에 찌를 수 있는 시각
	NextInk: number, -- 낙지: 다음에 먹물을 뿜을 수 있는 시각
	Pitch: number, -- 위아래로 기운 각도(라디안, + = 머리 위로)
	-- 거대 몬스터 큰 기술 (2026-10-10). 기술이 없는 몹은 안 쓴다
	NextSpecial: number, -- 다음 큰 기술을 쓸 수 있는 시각
	SpecialIndex: number, -- 다음에 쓸 기술 번호 (Config.Mobs Specials, 차례로 돈다)
	Cast: Cast?, -- 준비 중인 기술 (At에 판정)
	Charge: Charge?, -- 돌진 중
}

-- 준비 중인 큰 기술: Spec = Config.Mobs Specials 한 줄, At = 판정 시각, Center = 원 가운데(내려찍기·발구르기), Dir = 돌진 방향
type Cast = { Spec: any, At: number, Center: Vector3, Dir: Vector3 }
-- 돌진: Until까지 Dir로 Speed(스터드/초), 닿은 사람(HitRange 안)은 한 번씩 Damage
type Charge = { Until: number, Dir: Vector3, Speed: number, Damage: number, HitRange: number, Hit: { [Player]: boolean } }

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
local specialRemote: RemoteEvent -- 바다 생물 특수 연출 (MobSpecial)

local safePoints: { Vector3 } = {} -- 안전지대 가운데들 (마을 도착점·NPC)

-- 물고기 떼 (School 이름 → 같이 쓰는 목적지). Target이 없거나 Until이 지나면 떼 집 둘레에서 새로 고른다
type School = { Home: Vector3, Target: Vector3?, Until: number }
local schools: { [string]: School } = {}

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

---------------------------------------------------------------- 물 (바다 생물, 2026-10-09)
-- 물 기둥: 지형만 보는 광선으로 수면(물 무시 안 함)과 바닥(물 무시)을 잰다. 물이 안 바뀌니 칸마다 한 번만 재서 기억한다
local waterParams = RaycastParams.new()
waterParams.FilterType = Enum.RaycastFilterType.Include
waterParams.FilterDescendantsInstances = { Workspace.Terrain }
waterParams.IgnoreWater = false
local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Include
floorParams.FilterDescendantsInstances = { Workspace.Terrain }
floorParams.IgnoreWater = true

type WaterColumn = { Surface: number?, Floor: number } -- Surface가 nil이면 물이 아니다
local columns: { [string]: WaterColumn } = {}

-- (x, z) 칸의 물 기둥
local function waterColumn(x: number, z: number): WaterColumn
	local sea = Config.SeaAI
	local cell = sea.ColumnCell
	local cx, cz = math.floor(x / cell), math.floor(z / cell)
	local key = `{cx},{cz}`
	local cached = columns[key]
	if cached then
		return cached
	end
	local top = Vector3.new((cx + 0.5) * cell, sea.ScanTop, (cz + 0.5) * cell)
	local column: WaterColumn = { Surface = nil, Floor = -math.huge }
	local hit = Workspace:Raycast(top, Vector3.new(0, -sea.ScanLength, 0), waterParams)
	if hit and hit.Material == Enum.Material.Water then
		local floorHit = Workspace:Raycast(hit.Position, Vector3.new(0, -sea.ScanLength, 0), floorParams)
		column = { Surface = hit.Position.Y, Floor = if floorHit then floorHit.Position.Y else hit.Position.Y - sea.ScanLength }
	end
	columns[key] = column
	return column
end

-- 키가 height인 몸이 (x, z)에서 있을 수 있는 높이 범위 (발밑 기준). 물이 없거나 너무 얕으면 nil
local function swimBand(x: number, z: number, height: number): (number?, number?)
	local column = waterColumn(x, z)
	if not column.Surface then
		return nil, nil
	end
	local sea = Config.SeaAI
	local low = column.Floor + sea.FloorMargin
	local high = column.Surface - sea.SurfaceMargin - height
	if high < low then
		return nil, nil
	end
	return low, high
end

-- 위치를 물 속 범위로 맞춘다 (높이만 고침). 거기가 물이 아니면 nil
local function clampSwim(position: Vector3, height: number): Vector3?
	local low, high = swimBand(position.X, position.Z, height)
	if not low or not high then
		return nil
	end
	return Vector3.new(position.X, math.clamp(position.Y, low, high), position.Z)
end

-- 플레이어(뿌리 위치)가 물 속(수면에서 헤엄치는 중 포함)에 있는지
local function inWater(position: Vector3): boolean
	local column = waterColumn(position.X, position.Z)
	return column.Surface ~= nil
		and position.Y <= column.Surface + Config.SeaAI.PlayerWaterAbove
		and position.Y >= column.Floor - 2
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

-- 몹이 플레이어 하나를 때린다: 피버 중이면 무적, 방어구로 줄이고, 구르기 무적·방패 막기면 더 줄인다 (1이면 0)
-- 연출은 MobAttack (guarded = true면 클라가 "피함!"·"막음!")
local function hurtPlayer(state: MobState, player: Player, humanoid: Humanoid, amount: number, now: number)
	if FeverService.isActive(player) then
		return
	end
	local damage = EquipmentService.reduceDamage(player, amount) -- 방어구로 줄인다
	local reduction = guardReduction(player, now)
	if reduction > 0 then
		damage = if reduction >= 1 then 0 else damage * (1 - reduction)
	end
	if damage > 0 then
		humanoid:TakeDamage(damage)
	end
	fireNearby(attackRemote, state.Position, state.Model, player.UserId, math.round(damage * 10) / 10, reduction > 0)
end

-- 이번 생성이 보스인지 정하고 크기 배율을 돌려준다 (보스가 아니면 nil)
-- 몹마다 Config.Mobs BossScale이 있으면 그 크기 범위 (이미 큰 거대 몬스터는 덜 커진다, 2026-10-10)
local function rollBoss(spawnPart: BasePart, mobConfig: any): number?
	local boss = Config.MobBoss
	local chance = if spawnPart:GetAttribute("BossSpot") == true then boss.SpotChance else boss.Chance
	if random:NextNumber() >= chance then
		return nil
	end
	local range = if typeof(mobConfig.BossScale) == "table" then mobConfig.BossScale else boss.Scale
	return random:NextNumber(range[1], range[2])
end

---------------------------------------------------------------- 활 쏘는 몹 (2026-10-10)
-- 스켈레톤 궁수가 player에게 화살을 쏜다. 움직이는 사람은 조금 앞(Lead)을 노린다.
-- 벽·땅에 막히면 안 쏘고 false. 화살이 도착할 때(날아가는 시간 뒤) 그 자리 HitRadius 안에 있어야 맞는다 (구르기 무적이면 "피함!")
local function shootArrow(state: MobState, player: Player, root: BasePart, ranged: any): boolean
	local from = state.Position + Vector3.new(0, state.Height * 0.55, 0) + state.Facing * (state.Radius * 0.6)
	local velocity = root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
	local travel = (root.Position - from).Magnitude / ranged.ArrowSpeed
	local aim = root.Position + velocity * travel * (ranged.Lead or 0)
	travel = math.max((aim - from).Magnitude / ranged.ArrowSpeed, 0.05)
	local blocker = Workspace:Raycast(from, aim - from, groundParams)
	if blocker and (blocker.Position - aim).Magnitude > 2 then
		return false
	end
	fireNearby(specialRemote, state.Position, state.Model, "Arrow", player.UserId, from, { To = aim, Time = travel })
	local damage = state.Damage
	task.delay(travel, function()
		local hitRoot, humanoid = aliveRoot(player)
		if hitRoot and humanoid and (hitRoot.Position - aim).Magnitude <= ranged.HitRadius and safeDepth(hitRoot.Position) <= 0 then
			hurtPlayer(state, player, humanoid, damage, os.clock())
		end
	end)
	return true
end

---------------------------------------------------------------- 거대 몬스터 큰 기술 (2026-10-10)
-- 기술에 맞을 수 있는 플레이어 (주인이 있으면 주인만 = 남이 사냥 중인 거인에게 휘말리지 않게)
local function canBeHit(state: MobState, player: Player): boolean
	local owner = OwnershipService.ownerOf(state)
	return owner == nil or owner == player.UserId
end

-- 기술 데미지 (보스는 커진 만큼 = 보통 공격과 같은 비율)
local function specialDamage(state: MobState, spec: any): number
	local base = Config.Mobs[state.Type].Damage
	return spec.Damage * (if base > 0 then state.Damage / base else 1)
end

-- 원(center, radius) 안의 플레이어를 한 번씩 때린다. 높이는 반경의 절반 + 5까지
local function hurtInCircle(state: MobState, center: Vector3, radius: number, damage: number, now: number)
	for _, player in Players:GetPlayers() do
		local root, humanoid = aliveRoot(player)
		if root and humanoid and canBeHit(state, player) and safeDepth(root.Position) <= 0 then
			local flat = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z).Magnitude
			if flat <= radius + 1 and math.abs(root.Position.Y - center.Y) <= radius * 0.5 + 5 then
				hurtPlayer(state, player, humanoid, damage, now)
			end
		end
	end
end

-- 큰 기술 시작: 바닥에 경고 표시(Telegraph)를 보내고 Windup초 뒤 stepMob이 판정한다
-- 내려찍기 = 대상이 선 자리 둘레 / 발구르기 = 내 둘레 / 돌진 = 대상 쪽 직선
local function startSpecial(state: MobState, spec: any, targetRoot: BasePart, now: number)
	local s = state.Scale
	local flat = (targetRoot.Position - state.Position) * Vector3.new(1, 0, 1)
	local dir = if flat.Magnitude > 0.05 then flat.Unit else state.Facing
	state.Facing = dir
	local center = state.Position
	local data: { [string]: any } = { Kind = spec.Kind, Time = spec.Windup, Shape = "Circle", Radius = (spec.Radius or 0) * s }
	if spec.Kind == "Slam" then
		local p = targetRoot.Position
		center = Vector3.new(p.X, groundY(p, p.Y - 3), p.Z)
	elseif spec.Kind == "Charge" then
		data.Shape = "Line"
		data.Length = spec.Distance * s
		data.Width = spec.Width * s
		data.Dir = dir
	end
	state.Cast = { Spec = spec, At = now + spec.Windup, Center = center, Dir = dir }
	fireNearby(specialRemote, state.Position, state.Model, "Telegraph", 0, center, data)
end

-- 준비가 끝난 기술을 판정한다: 원 안 모두 때리기, 또는 돌진 시작
local function resolveSpecial(state: MobState, now: number)
	local cast = state.Cast
	if not cast then
		return
	end
	state.Cast = nil
	local spec = cast.Spec
	local s = state.Scale
	local damage = specialDamage(state, spec)
	if spec.Kind == "Charge" then
		state.Charge = {
			Until = now + spec.Distance / spec.Speed,
			Dir = cast.Dir,
			Speed = spec.Speed * s,
			Damage = damage,
			HitRange = math.max(spec.Width * s / 2, state.Radius * 0.6) + 1.5,
			Hit = {},
		}
		fireNearby(specialRemote, state.Position, state.Model, "Impact", 0, state.Position, { Kind = "Charge", Radius = state.Radius })
	else
		local radius = (spec.Radius or 0) * s
		hurtInCircle(state, cast.Center, radius, damage, now)
		fireNearby(specialRemote, state.Position, state.Model, "Impact", 0, cast.Center, { Kind = spec.Kind, Radius = radius })
	end
	state.NextAttack = math.max(state.NextAttack, now + 0.6) -- 기술 바로 뒤 보통 공격은 잠깐 쉰다
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
	local bossScale = rollBoss(spawnPart, config)
	local scale = bossScale or 1
	if bossScale then
		model:ScaleTo(model:GetScale() * bossScale)
	end
	-- 바다 생물은 생성 자리(물 속) 높이 그대로 두되 수면 아래·바닥 위로 맞추고, 땅 몹은 땅에 붙인다
	local swim = (config :: any).Swim == true
	local home: Vector3
	if swim then
		local height = model:GetExtentsSize().Y
		home = clampSwim(spawnPart.Position - Vector3.new(0, height / 2, 0), height) or spawnPart.Position
	else
		home = Vector3.new(spawnPart.Position.X, groundY(spawnPart.Position, spawnPart.Position.Y - 1), spawnPart.Position.Z)
	end
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

	-- 물고기 떼: 같은 School 이름끼리 목적지를 같이 쓴다. 떼 집 = 처음 생긴 물고기의 집
	local schoolAttribute = spawnPart:GetAttribute("School")
	local school: string? = if swim and typeof(schoolAttribute) == "string" and schoolAttribute ~= "" then schoolAttribute else nil
	local schoolOffset = Vector3.zero
	if school then
		if not schools[school] then
			schools[school] = { Home = home, Target = nil, Until = 0 }
		end
		schoolOffset = home - schools[school].Home
		if schoolOffset.Magnitude > Config.SeaSpawn.SchoolSpread * 2 then
			schoolOffset = schoolOffset.Unit * Config.SeaSpawn.SchoolSpread * 2
		end
	end

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
		Swim = swim,
		School = school,
		SchoolOffset = schoolOffset,
		BaseScale = model:GetScale(),
		PuffUntil = 0,
		NextPrick = 0,
		NextInk = 0,
		Pitch = 0,
		NextSpecial = 0,
		SpecialIndex = 1,
		Cast = nil,
		Charge = nil,
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
		if best then
			state.NextSpecial = math.max(state.NextSpecial, now + 1.5) -- 알아채자마자 큰 기술을 쓰진 않는다
		end
	end

	local goal: Vector3? = nil
	local speed = state.Speed
	local fleeing = false
	local retreating = false -- 활 쏘는 몹이 뒤로 물러나는 중 (막히면 도망처럼 옆으로 비킨다)
	local charging = false -- 거대 몬스터 돌진 중
	local faceAfterMove: Vector3? = nil -- 물러난 뒤에도 대상을 바라본다
	local ranged = (config :: any).Ranged
	local specials = (config :: any).Specials
	local cast = state.Cast
	if cast and now >= state.StunUntil and now >= cast.At then
		resolveSpecial(state, now) -- 준비 끝: 쾅! (돌진이면 여기서 시작)
	end
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
	elseif state.Cast then
		-- 큰 기술 준비 중: 제자리에서 힘을 모은다 (바닥 경고 표시가 차오르는 동안)
		goal = nil
	elseif state.Charge then
		-- 돌진: 정한 방향으로 곧장 달리며 닿은 사람을 한 번씩 들이받는다. 안전지대 앞에서는 멈춘다
		local charge = state.Charge :: Charge
		local nextPosition = state.Position + charge.Dir * charge.Speed * dt
		if now >= charge.Until or entersSafeZone(state.Position, nextPosition) then
			state.Charge = nil
		else
			state.Position = nextPosition
			state.Facing = charge.Dir
			charging = true
			for _, player in Players:GetPlayers() do
				local root, humanoid = aliveRoot(player)
				if root and humanoid and not charge.Hit[player] and canBeHit(state, player) and safeDepth(root.Position) <= 0 then
					local offset = root.Position - state.Position
					if Vector3.new(offset.X, 0, offset.Z).Magnitude <= charge.HitRange and offset.Y > -3 and offset.Y < state.Height + 3 then
						charge.Hit[player] = true
						hurtPlayer(state, player, humanoid, charge.Damage, now)
					end
				end
			end
		end
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
			local distance = flat.Magnitude
			-- 거대 몬스터: 큰 기술 차례가 됐고 대상이 Trigger 거리 안이면 준비를 시작한다 (2026-10-10)
			if typeof(specials) == "table" and #specials > 0 and now >= state.NextSpecial then
				local spec = specials[state.SpecialIndex] or specials[1]
				if distance <= spec.Trigger * math.max(state.Scale, 1) then
					startSpecial(state, spec, root, now)
					state.SpecialIndex = state.SpecialIndex % #specials + 1
					state.NextSpecial = now + spec.Windup + spec.Cooldown
				end
			end
			if state.Cast then
				goal = nil -- 방금 기술 준비를 시작했다
			elseif typeof(ranged) == "table" then
				-- 활 쏘는 몹 (스켈레톤 궁수): 너무 가까우면 뒤로 물러나고, 너무 멀면 다가가고, 사이면 서서 쏜다
				if distance < ranged.KeepAway then
					local away = if distance > 0.05 then -flat.Unit else -state.Facing
					goal = state.Position + away * 6
					speed *= ranged.RetreatSpeed or 1
					retreating = true
					faceAfterMove = state.Facing
				elseif distance > ranged.Range * 0.9 then
					goal = root.Position
				end
				if distance <= ranged.Range and now >= state.NextAttack and state.Damage > 0 then
					if shootArrow(state, state.Target :: Player, root, ranged) then
						state.NextAttack = now + config.AttackInterval
					elseif not retreating then
						goal = root.Position -- 벽에 막혀 못 쏜다 → 다가간다
					end
				end
			elseif distance > state.AttackRange * 0.8 then
				goal = root.Position
			elseif now >= state.NextAttack and state.Damage > 0 then
				-- 공격: 앞으로 살짝 들이받고 피해를 준다 (피버 중인 플레이어는 무적)
				-- 구르기 무적·방패 막기 중이면 피해를 줄인다 (1이면 0, guarded = true로 알려 클라가 "피함!"·"막음!")
				state.NextAttack = now + config.AttackInterval
				state.LungeUntil = now + 0.15
				hurtPlayer(state, state.Target :: Player, humanoid, state.Damage, now)
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
				if fleeing or retreating then
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
	moving = moving or charging or now < state.KnockbackUntil
	if faceAfterMove then
		state.Facing = faceAfterMove -- 뒷걸음질: 물러나면서도 대상을 본다
	end

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

-- 물 속 무작위 목적지: center 둘레 radius 안 (위아래도 무작위). 물이 아니거나 너무 얕거나 안전지대면 nil
local function randomSwimPoint(center: Vector3, radius: number, height: number): Vector3?
	local angle = random:NextNumber(0, math.pi * 2)
	local r = random:NextNumber(2, math.max(radius, 2.5))
	local x, z = center.X + math.cos(angle) * r, center.Z + math.sin(angle) * r
	local low, high = swimBand(x, z, height)
	if not low or not high then
		return nil
	end
	local point = Vector3.new(x, random:NextNumber(low, high), z)
	if safeDepth(point) > 0 then
		return nil
	end
	return point
end

-- 바다 생물 하나의 생각·헤엄 (dt초만큼, 2026-10-09). 땅 몹(stepMob)과 순서는 같지만 3D로 움직이고 물 밖으로는 안 나간다
-- 얌전한 바다 몹(Passive, 지금은 없음): 맞으면 도망 / 낙지(Retaliate): 맞으면 쫓아와 때림 / 해파리(Drift): 둥둥, 닿으면 쏨 / 상어: 물에 들어온 사람에게 돌진
local function stepSwimmer(state: MobState, dt: number, now: number)
	local config = Config.Mobs[state.Type] :: any
	local sea = Config.SeaAI
	local def = MobDefs[state.Type]
	local passive = config.Passive == true
	local drift = config.Drift == true
	local hunter = not passive and not drift and config.Retaliate ~= true -- 먼저 덤비는 몹 (상어)

	-- 복어: 부푼 시간이 끝나면 원래 크기로
	if state.PuffUntil > 0 and now >= state.PuffUntil then
		state.PuffUntil = 0
		state.Model:ScaleTo(state.BaseScale)
	end

	-- 쫓던 대상 포기: 사라짐·너무 멂·집에서 멂·안전지대·물 밖으로 나감
	local chaseRange = math.max(config.Aggro, sea.MinChaseRange) * 2
	local target = state.Target
	if target then
		local root = aliveRoot(target)
		if
			not root
			or passive
			or drift
			or (state.Position - state.Home).Magnitude > sea.Leash
			or (root.Position - state.Position).Magnitude > chaseRange
			or safeDepth(root.Position) > 0
			or not inWater(root.Position)
		then
			state.Target = nil
		end
	end
	if state.FleeFrom and now >= state.FleeUntil then
		state.FleeFrom = nil
	end
	OwnershipService.expire(state, state.Model, now)
	local owner = OwnershipService.ownerOf(state)
	-- 상어: 물에 들어온 가까운 플레이어를 알아챈다 (주인이 있으면 주인만)
	if hunter and not state.Target and (state.Position - state.Home).Magnitude < sea.Leash * 0.6 then
		local best: Player? = nil
		local bestDistance = config.Aggro
		for _, player in Players:GetPlayers() do
			local root = aliveRoot(player)
			if root and (owner == nil or owner == player.UserId) and safeDepth(root.Position) <= 0 and inWater(root.Position) then
				local distance = (root.Position - state.Position).Magnitude
				if distance < bestDistance then
					best, bestDistance = player, distance
				end
			end
		end
		state.Target = best
	end

	local center = state.Position + Vector3.new(0, state.Height / 2, 0)
	-- 해파리: 몸에 닿은 사람(가장 가까운 한 명)을 AttackInterval마다 쏜다
	if drift and state.Damage > 0 and now >= state.NextAttack and now >= state.StunUntil then
		local bestPlayer: Player? = nil
		local bestHumanoid: Humanoid? = nil
		local bestDistance = state.AttackRange + state.Radius
		for _, player in Players:GetPlayers() do
			local root, humanoid = aliveRoot(player)
			if root and humanoid and (owner == nil or owner == player.UserId) and safeDepth(root.Position) <= 0 then
				local distance = (root.Position - center).Magnitude
				if distance < bestDistance then
					bestPlayer, bestHumanoid, bestDistance = player, humanoid, distance
				end
			end
		end
		if bestPlayer and bestHumanoid then
			state.NextAttack = now + config.AttackInterval
			state.LungeUntil = now + 0.15
			hurtPlayer(state, bestPlayer, bestHumanoid, state.Damage, now)
		end
	end

	local goal: Vector3? = nil
	local speed = state.Speed
	local fleeing = false
	local chasing = false
	if now < state.KnockbackUntil then
		-- 맞아서 밀려나는 중 (물 밖·안전지대로는 안 밀린다)
		local nextPosition = clampSwim(state.Position + state.Knockback * dt, state.Height)
		if not nextPosition or entersSafeZone(state.Position, nextPosition) then
			state.KnockbackUntil = 0
		else
			state.Position = nextPosition
		end
	elseif now < state.StunUntil then
		goal = nil -- 기절: 제자리
	elseif state.FleeFrom then
		-- 도망: 때린 사람 반대쪽으로 (위아래는 조금만)
		fleeing = true
		local root = aliveRoot(state.FleeFrom)
		local away = if root then state.Position - root.Position else state.Facing
		away = Vector3.new(away.X, away.Y * 0.5, away.Z)
		away = if away.Magnitude > 0.05 then away.Unit else state.Facing
		goal = state.Position + away * 6
		speed *= config.FleeSpeed or 1.5
	elseif state.Target then
		local root, humanoid = aliveRoot(state.Target)
		if root and humanoid then
			local offset = root.Position - center
			local flat = offset * Vector3.new(1, 0, 1)
			if flat.Magnitude > 0.05 then
				state.Facing = flat.Unit
			end
			if offset.Magnitude > state.AttackRange * 0.8 then
				goal = root.Position - Vector3.new(0, state.Height / 2, 0) -- 몸 가운데가 상대 몸통 높이로 (수면 위면 수면 바로 아래까지)
				chasing = true
				if config.ChargeSpeed and offset.Magnitude < (config.ChargeRange or 0) then
					speed *= config.ChargeSpeed -- 상어 돌진
				end
			elseif now >= state.NextAttack and state.Damage > 0 then
				state.NextAttack = now + config.AttackInterval
				state.LungeUntil = now + 0.15
				hurtPlayer(state, state.Target :: Player, humanoid, state.Damage, now)
			end
		end
	else
		-- 한가할 때: 집 둘레를 헤엄치다 잠깐 쉰다. 물고기 떼는 떼 목적지 + 내 자리
		local schoolName = state.School
		local school = if schoolName then schools[schoolName] else nil
		if (state.Position - state.Home).Magnitude > sea.WanderRadius * 1.5 then
			state.WanderTarget = state.Home
		elseif school then
			if not school.Target or now >= school.Until then
				school.Target = randomSwimPoint(school.Home, sea.WanderRadius, state.Height) or school.Home
				school.Until = now + random:NextNumber(sea.SchoolRetarget[1], sea.SchoolRetarget[2])
			end
			local schoolTarget = school.Target or school.Home
			state.WanderTarget = clampSwim(schoolTarget + state.SchoolOffset, state.Height) or schoolTarget
		elseif not state.WanderTarget and now >= state.WanderUntil then
			local wander = randomSwimPoint(state.Home, sea.WanderRadius, state.Height)
			if wander then
				state.WanderTarget = wander
			else
				state.WanderUntil = now + random:NextNumber(sea.WanderPause[1], sea.WanderPause[2])
			end
		end
		goal = state.WanderTarget
		speed *= if drift then 1 else 0.5
	end

	-- 자연 회복 (땅 몹과 같음)
	if not state.Target and not fleeing and state.Hp < state.MaxHp and now - state.LastHit >= Config.Regen.Delay then
		state.Hp = math.min(state.MaxHp, state.Hp + state.MaxHp * Config.Regen.MobPercentPerSecond * dt)
		state.Model:SetAttribute("Hp", math.floor(state.Hp * 10 + 0.5) / 10)
	end

	-- 3D로 움직인다. 다음 자리가 물이 아니거나(땅·얕은 물) 안전지대면 안 간다
	local maxPitch = math.rad(sea.MaxPitch)
	local moving = false
	if goal then
		local delta = goal - state.Position
		local distance = delta.Magnitude
		if distance < 0.5 then
			if goal == state.WanderTarget then
				state.WanderTarget = nil
				state.WanderUntil = now + random:NextNumber(sea.WanderPause[1], sea.WanderPause[2])
			end
		else
			local step = math.min(speed * dt, distance)
			local function tryMove(direction: Vector3): Vector3?
				local nextPosition = clampSwim(state.Position + direction * step, state.Height)
				if not nextPosition or entersSafeZone(state.Position, nextPosition) then
					return nil
				end
				return nextPosition
			end
			local nextPosition = tryMove(delta.Unit)
			if not nextPosition and fleeing then
				-- 도망은 옆으로 비켜 본다
				for _, angle in { 70, -70, 120, -120 } do
					nextPosition = tryMove(CFrame.Angles(0, math.rad(angle), 0):VectorToWorldSpace(delta.Unit))
					if nextPosition then
						break
					end
				end
			end
			if nextPosition then
				local moved = nextPosition - state.Position
				local flat = moved * Vector3.new(1, 0, 1)
				if flat.Magnitude > 0.01 then
					state.Facing = flat.Unit
				end
				-- 오르내릴 때 머리를 그쪽으로 살짝 기울인다
				local pitchGoal = math.clamp(math.atan2(moved.Y, math.max(flat.Magnitude, 0.001)), -maxPitch, maxPitch)
				state.Pitch += (pitchGoal - state.Pitch) * math.min(1, dt * 5)
				state.Position = nextPosition
				moving = true
			elseif chasing then
				-- 대상 쪽이 물 밖·안전지대라 못 간다 → 포기하고 집으로
				state.Target = nil
				state.WanderTarget = state.Home
			elseif goal == state.WanderTarget then
				-- 못 가는 목적지 → 쉬었다가 다른 곳
				state.WanderTarget = nil
				state.WanderUntil = now + random:NextNumber(sea.WanderPause[1], sea.WanderPause[2])
			end
		end
	end
	if not moving then
		state.Pitch *= math.max(0, 1 - dt * 3)
	end
	moving = moving or now < state.KnockbackUntil
	-- 수면 높이가 바뀌는 곳에서도 늘 물 속에
	local clamped = clampSwim(state.Position, state.Height)
	if clamped then
		state.Position = clamped
	end

	-- 헤엄 모양: 물고기는 꼬리를 좌우로 살랑(몸 전체 흔들기), 낙지·해파리는 위아래로 둥실 (보스는 크기만큼 느리고 크게)
	local bob, wiggle = 0, 0
	if def.SwimStyle == "Pulse" then
		state.Phase += dt * sea.PulseSpeed * (if moving then 1.6 else 1) / math.sqrt(state.Scale)
		bob = math.sin(state.Phase) * sea.PulseBob * state.Scale
	else
		local rate = (if moving then 1 else 0.35) * (if fleeing or chasing then 1.6 else 1)
		state.Phase += dt * sea.WiggleSpeed * rate / math.sqrt(state.Scale)
		wiggle = math.sin(state.Phase) * math.rad(sea.WiggleAngle) * (if moving then 1 else 0.4)
		bob = math.sin(state.Phase * 0.3) * 0.12 * state.Scale
	end
	local lunge = if now < state.LungeUntil then Config.MobAI.LungeDistance * state.Scale else 0
	local base = state.Position + Vector3.new(0, bob, 0) + state.Facing * lunge
	state.Model:PivotTo(CFrame.lookAt(base, base + state.Facing) * CFrame.Angles(state.Pitch, wiggle, 0))
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
	local bagFull = added < lootCount

	-- 두 번째 전리품(Config.Mobs ExtraLoot, 보스는 크기만큼 더) + 보스 전리품(Config.MobBoss.ExtraLoot) (2026-10-09)
	local extras: { { Id: string, Count: number } } = {}
	local function rollExtra(list: any, scaleWithBoss: boolean)
		if typeof(list) ~= "table" then
			return
		end
		for _, entry in list do
			if ItemDefs.Items[entry.Id] and random:NextNumber() < (entry.Chance or 1) then
				local count = random:NextInteger(entry.Count[1], entry.Count[2])
				if scaleWithBoss and state.Boss then
					count = math.max(count, math.floor(count * boss.LootPerScale * state.Scale + 0.5))
				end
				local got = InventoryService.add(killer, entry.Id, count)
				if got < count then
					bagFull = true
				end
				if got > 0 then
					table.insert(extras, { Id = entry.Id, Count = got })
				end
			end
		end
	end
	rollExtra((config :: any).ExtraLoot, true)
	if state.Boss then
		rollExtra((boss :: any).ExtraLoot, false)
	end

	if bagFull then
		NotifyService.send(killer, "가방이 가득 찼어요! 마을 상인에게 팔고 오세요.", "bad")
	end
	if state.Boss then
		NotifyService.send(killer, `{boss.NamePrefix}{def.DisplayName}을(를) 물리쳤어요! +{gold}G`, "good")
	end
	-- 7번째 인자 extras: 주 전리품 말고 더 받은 전리품 목록 (예전 클라는 무시해도 된다)
	fireNearby(diedRemote, state.Position, state.Position, state.Type, killer.UserId, gold, def.LootId, added, extras)
	local label = if state.Boss then boss.NamePrefix .. def.DisplayName else def.DisplayName
	local lootText = `{ItemDefs.Items[def.LootId].DisplayName} {added}개`
	for _, extra in extras do
		lootText ..= `, {ItemDefs.Items[extra.Id].DisplayName} {extra.Count}개`
	end
	print(`[MobService] {killer.Name}이(가) {label} 처치: {gold}G, {lootText}`)
	QuestService.report(killer, "Kill", state.Type, 1) -- 시작 퀘스트 (슬라임·스켈레톤 잡기)

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
		elseif not (config :: any).Drift then -- 해파리는 맞아도 둥둥 (쫓지 않는다)
			state.Target = player
		end
	end
	react()
	state.LastHit = os.clock()
	-- 바다 생물 특수 반응 (2026-10-09): 복어는 부풀어 가까이서 때린 사람을 찌르고, 낙지는 가끔 먹물을 뿜는다
	local now = os.clock()
	local special = config :: any
	local center = state.Position + Vector3.new(0, state.Height / 2, 0)
	local prick = special.Prick
	if prick then
		if state.PuffUntil <= 0 then
			mob:ScaleTo(state.BaseScale * prick.PuffScale)
			fireNearby(specialRemote, state.Position, mob, "Puff", player.UserId, center, prick.PuffTime)
		end
		state.PuffUntil = now + prick.PuffTime
		local root, humanoid = aliveRoot(player)
		if root and humanoid and now >= state.NextPrick and (root.Position - center).Magnitude <= prick.Range + state.Radius then
			state.NextPrick = now + prick.Cooldown
			hurtPlayer(state, player, humanoid, prick.Damage * (if state.Boss then state.Scale else 1), now)
		end
	end
	local ink = special.Ink
	if ink and now >= state.NextInk and random:NextNumber() < ink.Chance then
		state.NextInk = now + ink.Cooldown
		fireNearby(specialRemote, state.Position, mob, "Ink", player.UserId, center, ink.Blind)
	end
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
	-- 거대 몬스터가 준비하던 큰 기술·돌진은 기절하면 취소된다 (클라에 "Cancel"로 바닥 표시를 지우게, 2026-10-10)
	if state.Cast then
		fireNearby(specialRemote, state.Position, mob, "Cancel", 0, state.Position, nil)
	end
	state.Cast = nil
	state.Charge = nil
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
	specialRemote = Remotes.get(Remotes.Names.MobSpecial)

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
				if state.Swim then
					stepSwimmer(state, step, now) -- 바다 생물 (2026-10-09)
				else
					stepMob(state, step, now)
				end
			end
		end
	end)
end

return MobService
