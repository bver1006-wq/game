--!nocheck
-- Studio 제작 스크립트: 밤에 마을과 길을 밝히는 횃불·가로등 (2026-10-09 사용자 요청: 밤에 너무 깜깜해서 못 다님).
-- Rojo가 ServerStorage/StudioTools/BuildTorches(ModuleScript)로 넣고, 서버(Main.server)가 게임을 시작할 때마다 실행한다.
-- 편집 상태에서 직접 실행하려면 명령 모음에: require(game.ServerStorage.StudioTools.BuildTorches:Clone())
-- 다시 실행하면 전에 만든 것(속성 GeneratedBy = "BuildTorches")을 지우고 새로 만든다.
--
-- 만드는 것 → Workspace/Torches
--   1. 마을 가로등(Lamp): 광장 가운데 둘레, NPC 가판대 옆, 마을 둘레 고리 몇 겹 (Config.Torches.TownRings)
--   2. 길 횃불(Torch): 마을 둘레를 격자로 아래로 광선을 쏴서 길 칸을 찾고, 길 가장자리 바깥에 RoadSpacing 간격으로
--      길 칸 = 지형 재질 돌길(Cobblestone·Pavement·Brick·Asphalt·Concrete·WoodPlanks) / 이름에 Road·Path·Street·길·도로가 든 납작한 부품
--              / 흙(Ground·Mud) 띠가 DirtRoadMaxWidth보다 좁으면(양쪽이 풀밭 등) 흙길
--   3. 길을 거의 못 찾으면 마을 → 광산 입구 직선을 따라 지그재그로 세운다
-- 물·건물 안·지붕 위·광산 구역·도착점·광석/몹 생성 자리는 피하고, 다른 불빛(맵에 원래 있던 가로등 포함)과 너무 가까우면 건너뛴다.
-- 불은 서버 TorchService가 밤(Config.DayNight)에만 켠다. 편집 상태에서는 켜진 채로 보인다.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local GENERATED = "BuildTorches"
local cfg = Config.Torches

---------------------------------------------------------------- 정리
local torches = workspace:FindFirstChild("Torches")
if torches then
	for _, child in torches:GetChildren() do
		if child:GetAttribute("GeneratedBy") == GENERATED then
			child:Destroy()
		end
	end
else
	torches = Instance.new("Folder")
	torches.Name = "Torches"
	torches.Parent = workspace
end
torches:SetAttribute("GeneratedBy", GENERATED)
torches:SetAttribute("BuildId", os.clock()) -- TorchService가 새로 지은 것을 알아채고 켜기·끄기를 다시 맞춘다

---------------------------------------------------------------- 마을 위치
local function positionOf(instance: Instance): Vector3?
	if instance:IsA("Model") then
		return instance:GetPivot().Position
	elseif instance:IsA("BasePart") then
		return instance.Position
	end
	return nil
end

-- 수평 거리 (높이는 무시)
local function flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local town = CollectionService:GetTagged("TownArrival")[1]
local center = (town and positionOf(town)) or Vector3.zero
if not town then
	warn("[BuildTorches] TownArrival 태그가 없어 (0, 0, 0)을 마을로 봤어요.")
end

-- NPC (ShopNPC 태그, 없으면 Workspace/NPCs 아래 모델)
local npcs = {}
for _, npc in CollectionService:GetTagged("ShopNPC") do
	if npc:IsA("Model") and npc:IsDescendantOf(workspace) then
		table.insert(npcs, npc)
	end
end
if #npcs == 0 and workspace:FindFirstChild("NPCs") then
	for _, npc in workspace.NPCs:GetChildren() do
		if npc:IsA("Model") then
			table.insert(npcs, npc)
		end
	end
end

-- 마을 반경 = 가장 먼 NPC + 여유
local townRadius = cfg.TownMinRadius
for _, npc in npcs do
	townRadius = math.max(townRadius, flatDistance(npc:GetPivot().Position, center) + cfg.TownMargin)
end

-- 피할 점: 도착점·광산 입구 (KeepAway), 광석·몹 생성 자리 (5스터드)
local keepAway = {}
for _, tag in { "TownArrival", "MinePortal" } do
	for _, instance in CollectionService:GetTagged(tag) do
		local p = positionOf(instance)
		if p then
			table.insert(keepAway, p)
		end
	end
end
local spawnPoints = {}
for _, name in { "OreSpawns", "MobSpawns" } do
	local f = workspace:FindFirstChild(name)
	if f then
		for _, d in f:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(spawnPoints, d.Position)
			end
		end
	end
end
local mineZones = CollectionService:GetTagged("MineZone")

local function insideMineZone(position: Vector3): boolean
	for _, zone in mineZones do
		if zone:IsA("BasePart") then
			local localPos = zone.CFrame:PointToObjectSpace(position)
			local half = zone.Size / 2 + Vector3.new(3, 3, 3)
			if math.abs(localPos.X) < half.X and math.abs(localPos.Y) < half.Y and math.abs(localPos.Z) < half.Z then
				return true
			end
		end
	end
	return false
end

---------------------------------------------------------------- 이미 있는 불빛 (간격 계산에 넣는다)
local placed = {} -- 세운 횃불 + 원래 있던 불빛 위치
local existingLights = 0
for _, d in workspace:GetDescendants() do
	if d:IsA("Light") and d.Enabled and d.Range >= 10 and not d:IsDescendantOf(torches) then
		local holder = d.Parent
		if holder and holder:IsA("BasePart") and holder.Position.Y > center.Y - 60 then
			table.insert(placed, holder.Position)
			existingLights += 1
		end
	end
end

local function farFromPlaced(position: Vector3, gap: number): boolean
	for _, p in placed do
		if flatDistance(p, position) < gap then
			return false
		end
	end
	return true
end

---------------------------------------------------------------- 광선
-- 안 보이거나 안 부딪히는 부품(생성 자리·구역 상자 등)은 한 번 맞으면 계속 무시한다
local ignore = { torches }
for _, name in { "Ores", "OreSpawns", "MobSpawns", "ClientEffects" } do
	local f = workspace:FindFirstChild(name)
	if f then
		table.insert(ignore, f)
	end
end
for _, zone in mineZones do
	table.insert(ignore, zone)
end
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = ignore
rayParams.IgnoreWater = false

local function isSolid(hit: Instance): boolean
	if hit:IsA("Terrain") then
		return true
	end
	return hit:IsA("BasePart") and hit.CanCollide and hit.Transparency < 0.9
end

-- (x, z)에서 fromY부터 아래로 쏴 처음 닿는 단단한 것
local function castDown(x: number, z: number, fromY: number, depth: number?): RaycastResult?
	for _ = 1, 8 do
		local result = workspace:Raycast(Vector3.new(x, fromY, z), Vector3.new(0, -(depth or 700), 0), rayParams)
		if not result then
			return nil
		end
		if isSolid(result.Instance) then
			return result
		end
		table.insert(ignore, result.Instance)
		rayParams.FilterDescendantsInstances = ignore
	end
	return nil
end

-- 부품의 축 정렬 높이 범위 (아래, 위)
local function verticalExtent(p: BasePart): (number, number)
	local cf, s = p.CFrame, p.Size
	local half = (math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z) / 2
	return p.Position.Y - half, p.Position.Y + half
end

local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude
overlap.FilterDescendantsInstances = { torches, workspace.Terrain }

-- 횃불 기둥 자리에 벽·집·나무 같은 것이 있는가
local function blocked(ground: Vector3, groundPart: Instance): boolean
	local parts = workspace:GetPartBoundsInBox(CFrame.new(ground + Vector3.new(0, 3.6, 0)), Vector3.new(2.6, 6, 2.6), overlap)
	for _, p in parts do
		if p ~= groundPart and not p:IsA("Terrain") and p.CanCollide and p.Transparency < 0.9 then
			local _, top = verticalExtent(p)
			if top > ground.Y + 0.8 then
				return true
			end
		end
	end
	return false
end

-- 이 수평 위치에 세울 수 있으면 땅 위치를 돌려준다
-- opts.fromY: 광선 시작 높이, opts.refY·opts.maxDy: 기준 높이에서 이만큼까지만 (길 옆 등)
local function groundSpot(x: number, z: number, opts): (Vector3?, string?)
	local result = castDown(x, z, opts.fromY)
	if not result then
		return nil, "땅 없음"
	end
	local hit = result.Instance
	if hit:IsA("Terrain") and result.Material == Enum.Material.Water then
		return nil, "물"
	end
	if result.Normal.Y < 0.75 then
		return nil, "가파름"
	end
	local ground = result.Position
	if opts.refY and math.abs(ground.Y - opts.refY) > (opts.maxDy or 5) then
		return nil, "높이 차"
	end
	-- 지붕·담장 위인가: 그 부품 바로 아래로 한 번 더 쏴서 한참 아래에 땅이 있으면 지붕
	if not hit:IsA("Terrain") then
		local below = RaycastParams.new()
		below.FilterType = Enum.RaycastFilterType.Exclude
		local list = table.clone(ignore)
		table.insert(list, hit)
		below.FilterDescendantsInstances = list
		below.IgnoreWater = false
		local under = workspace:Raycast(ground - Vector3.new(0, 0.05, 0), Vector3.new(0, -40, 0), below)
		if under and ground.Y - under.Position.Y > 4 then
			return nil, "지붕"
		end
	end
	if insideMineZone(ground) then
		return nil, "광산"
	end
	for _, p in keepAway do
		if flatDistance(p, ground) < cfg.KeepAway then
			return nil, "도착점"
		end
	end
	for _, p in spawnPoints do
		if flatDistance(p, ground) < 5 then
			return nil, "생성 자리"
		end
	end
	if blocked(ground, hit) then
		return nil, "막힘"
	end
	return ground, nil
end

---------------------------------------------------------------- 모양
local WOOD = Color3.fromRGB(128, 86, 52)
local DARK_WOOD = Color3.fromRGB(92, 62, 40)
local IRON = Color3.fromRGB(60, 54, 50)
local STONE = Color3.fromRGB(140, 136, 128)

local function part(props, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	if props.Shape then
		p.Shape = props.Shape -- 모양을 먼저 (Ball은 크기를 바꾸므로)
	end
	for key, value in props do
		if key ~= "Shape" then
			p[key] = value
		end
	end
	p.Parent = parent
	return p
end

-- 세로로 선 원기둥 (Cylinder 축은 X라 90° 돌린다)
local function cylinder(name: string, height: number, diameter: number, cframe: CFrame, color: Color3, material, parent): BasePart
	return part({
		Name = name, Shape = Enum.PartType.Cylinder, Size = Vector3.new(height, diameter, diameter),
		CFrame = cframe * CFrame.Angles(0, 0, math.rad(90)), Color = color, Material = material,
	}, parent)
end

-- 불꽃 부품 + 불빛 (TorchService가 켜고 끈다)
local function flame(model: Model, cframe: CFrame, size: number, range: number, brightness: number, shadows: boolean, withFire: boolean): BasePart
	local f = part({
		Name = "Flame", Shape = Enum.PartType.Ball, Size = Vector3.new(size, size, size),
		CFrame = cframe, Color = cfg.FlameColor, Material = Enum.Material.Neon, Transparency = 0.1, CastShadow = false,
	}, model)
	f:SetAttribute("TorchFlame", true)
	f:SetAttribute("OnTransparency", 0.1)
	local core = part({
		Name = "FlameCore", Shape = Enum.PartType.Ball, Size = Vector3.new(size * 0.6, size * 0.6, size * 0.6),
		CFrame = cframe * CFrame.new(0, -size * 0.1, 0), Color = Color3.fromRGB(255, 225, 140), Material = Enum.Material.Neon, CastShadow = false,
	}, model)
	core:SetAttribute("TorchFlame", true)
	core:SetAttribute("OnTransparency", 0)
	local light = Instance.new("PointLight")
	light.Color = cfg.LightColor
	light.Range = range
	light.Brightness = brightness
	light.Shadows = shadows
	light.Parent = f
	if withFire then
		local fire = Instance.new("Fire")
		fire.Size = size * 2.2
		fire.Heat = 4
		fire.Color = cfg.FlameColor
		fire.SecondaryColor = Color3.fromRGB(255, 210, 120)
		fire.Parent = f
	end
	return f
end

-- 길 횃불: 돌 받침 + 나무 기둥 + 쇠 띠 + 쇠 그릇 + 불꽃 (키 약 7.5)
local function makeTorch(ground: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Torch"
	local base = CFrame.new(ground) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	part({ Name = "Base", Size = Vector3.new(1.6, 0.6, 1.6), CFrame = base * CFrame.new(0, 0.2, 0), Color = STONE, Material = Enum.Material.Slate }, model)
	local post = part({ Name = "Post", Size = Vector3.new(0.6, 6.2, 0.6), CFrame = base * CFrame.new(0, 3.3, 0), Color = WOOD, Material = Enum.Material.Wood }, model)
	post.CanCollide = true
	post.CanQuery = true
	for _, y in { 2.2, 5.6 } do
		part({ Name = "Band", Size = Vector3.new(0.72, 0.18, 0.72), CFrame = base * CFrame.new(0, y, 0), Color = IRON, Material = Enum.Material.Metal }, model)
	end
	cylinder("Bowl", 0.7, 1.5, base * CFrame.new(0, 6.6, 0), IRON, Enum.Material.Metal, model)
	cylinder("Rim", 0.15, 1.75, base * CFrame.new(0, 6.95, 0), Color3.fromRGB(95, 80, 60), Enum.Material.Metal, model)
	flame(model, base * CFrame.new(0, 7.45, 0), 0.9, cfg.RoadRange, cfg.RoadBrightness, false, cfg.UseFire)
	model.WorldPivot = base
	model:SetAttribute("GeneratedBy", GENERATED)
	model:SetAttribute("TorchKind", "Road")
	model.Parent = torches
	return model
end

-- 마을 가로등: 돌 받침 + 굵은 기둥 + 팔 + 매달린 등불(유리 + 불꽃). 팔은 face 방향
local function makeLamp(ground: Vector3, face: Vector3, shadows: boolean): Model
	local model = Instance.new("Model")
	model.Name = "Lamp"
	local flat = Vector3.new(face.X, 0, face.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.zAxis
	end
	local base = CFrame.lookAt(ground, ground + flat.Unit)
	part({ Name = "Base", Size = Vector3.new(2, 0.8, 2), CFrame = base * CFrame.new(0, 0.3, 0), Color = STONE, Material = Enum.Material.Cobblestone }, model)
	local post = part({ Name = "Post", Size = Vector3.new(0.8, 9, 0.8), CFrame = base * CFrame.new(0, 4.7, 0), Color = DARK_WOOD, Material = Enum.Material.Wood }, model)
	post.CanCollide = true
	post.CanQuery = true
	part({ Name = "Cap", Shape = Enum.PartType.Ball, Size = Vector3.new(1.1, 1.1, 1.1), CFrame = base * CFrame.new(0, 9.4, 0), Color = IRON, Material = Enum.Material.Metal }, model)
	-- 팔 (앞 = -Z)
	part({ Name = "Arm", Size = Vector3.new(0.35, 0.35, 2.6), CFrame = base * CFrame.new(0, 8.6, -1.3), Color = IRON, Material = Enum.Material.Metal }, model)
	part({ Name = "Brace", Size = Vector3.new(0.25, 0.25, 1.6), CFrame = base * CFrame.new(0, 7.9, -0.6) * CFrame.Angles(math.rad(-40), 0, 0), Color = IRON, Material = Enum.Material.Metal }, model)
	-- 등불
	local lantern = base * CFrame.new(0, 7.3, -2.4)
	part({ Name = "Hook", Size = Vector3.new(0.12, 0.6, 0.12), CFrame = lantern * CFrame.new(0, 1.1, 0), Color = IRON, Material = Enum.Material.Metal }, model)
	part({ Name = "LanternTop", Size = Vector3.new(1.4, 0.3, 1.4), CFrame = lantern * CFrame.new(0, 0.8, 0), Color = IRON, Material = Enum.Material.Metal }, model)
	part({ Name = "LanternRoof", Size = Vector3.new(0.9, 0.3, 0.9), CFrame = lantern * CFrame.new(0, 1.05, 0), Color = IRON, Material = Enum.Material.Metal }, model)
	part({ Name = "Glass", Size = Vector3.new(1.1, 1.3, 1.1), CFrame = lantern, Color = Color3.fromRGB(255, 214, 150), Material = Enum.Material.Glass, Transparency = 0.45, CastShadow = false }, model)
	part({ Name = "LanternBottom", Size = Vector3.new(1.3, 0.25, 1.3), CFrame = lantern * CFrame.new(0, -0.75, 0), Color = IRON, Material = Enum.Material.Metal }, model)
	flame(model, lantern * CFrame.new(0, -0.1, 0), 0.6, cfg.TownRange, cfg.TownBrightness, shadows, false)
	model.WorldPivot = base
	model:SetAttribute("GeneratedBy", GENERATED)
	model:SetAttribute("TorchKind", "Town")
	model.Parent = torches
	return model
end

---------------------------------------------------------------- 1. 마을 가로등
local townCount = 0
local townFails = {}
local townFromY = center.Y + 60

-- 자리 (x, z) 근처에서 세울 수 있는 곳을 찾아 가로등을 세운다. nudge = 비켜 볼 방향들
local function tryLamp(target: Vector3, face: Vector3, gap: number): boolean
	local offsets = { Vector3.zero }
	for _, r in { 3, 6 } do
		for k = 0, 5 do
			local a = k / 6 * math.pi * 2
			table.insert(offsets, Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
		end
	end
	local reason = "간격"
	for _, offset in offsets do
		local p = target + offset
		if farFromPlaced(p, gap) then
			local ground, why = groundSpot(p.X, p.Z, { fromY = townFromY })
			if ground then
				townCount += 1
				local shadows = cfg.ShadowEvery > 0 and townCount % cfg.ShadowEvery == 0
				makeLamp(ground, face, shadows)
				table.insert(placed, ground)
				return true
			end
			reason = why or reason
		end
	end
	townFails[reason] = (townFails[reason] or 0) + 1
	return false
end

-- 광장 가운데 둘레 (팔은 바깥쪽)
for k = 0, cfg.PlazaCount - 1 do
	local a = k / cfg.PlazaCount * math.pi * 2 + 0.3
	local dir = Vector3.new(math.cos(a), 0, math.sin(a))
	tryLamp(center + dir * cfg.PlazaRadius, dir, cfg.TownMinGap)
end

-- NPC 가판대 옆: 마을 가운데 쪽으로 NpcDistance 나와서 옆으로 조금 (팔은 NPC 쪽)
for _, npc in npcs do
	local pos = npc:GetPivot().Position
	local toCenter = Vector3.new(center.X - pos.X, 0, center.Z - pos.Z)
	toCenter = if toCenter.Magnitude > 0.1 then toCenter.Unit else npc:GetPivot().LookVector
	local side = Vector3.new(-toCenter.Z, 0, toCenter.X)
	for n = 1, cfg.PerNpc do
		local sign = if n % 2 == 1 then 1 else -1
		local target = pos + toCenter * cfg.NpcDistance * 0.7 + side * sign * cfg.NpcDistance * 0.7
		tryLamp(target, pos - target, cfg.TownMinGap * 0.7)
	end
end

-- 마을 둘레 고리 (팔은 마을 가운데 쪽)
for ringIndex, ring in cfg.TownRings do
	local radius = townRadius * ring.Scale
	for k = 0, ring.Count - 1 do
		local a = (k + (ringIndex % 2) * 0.5) / ring.Count * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		tryLamp(center + dir * radius, -dir, cfg.TownMinGap)
	end
end

---------------------------------------------------------------- 2. 길 찾기 (격자)
local PATH_MATERIALS = {
	[Enum.Material.Cobblestone] = true, [Enum.Material.Pavement] = true, [Enum.Material.Brick] = true,
	[Enum.Material.Asphalt] = true, [Enum.Material.Concrete] = true, [Enum.Material.WoodPlanks] = true,
}
local DIRT_MATERIALS = { [Enum.Material.Ground] = true, [Enum.Material.Mud] = true }
local ROAD_WORDS = { "road", "path", "street", "trail", "sidewalk", "길", "도로" }
local NOT_ROAD_WORDS = { "light", "lamp", "sign", "torch" }

-- 이름(또는 위쪽 모델 이름)에 길 낱말이 들어간 부품인가 (가로등·표지판은 빼기)
local function hasRoadName(instance: Instance): boolean
	local node = instance
	for _ = 1, 4 do
		if not node or node == workspace then
			break
		end
		local lower = string.lower(node.Name)
		for _, word in NOT_ROAD_WORDS do
			if string.find(lower, word, 1, true) then
				return false
			end
		end
		for _, word in ROAD_WORDS do
			if string.find(lower, word, 1, true) then
				return true
			end
		end
		node = node.Parent
	end
	return false
end

local step = cfg.RoadScanStep
local N = math.ceil(cfg.RoadScanRadius / step)
local W = 2 * N + 1
local cellClass = {} -- 칸 번호 → "Road" / "Dirt" / "Land" / "Water"
local cellY = {}
local function key(i: number, j: number): number
	return (i + N) * W + (j + N)
end
local function inGrid(i: number, j: number): boolean
	return i >= -N and i <= N and j >= -N and j <= N
end
local scanFromY = center.Y + 300
local scanned = 0
for i = -N, N do
	for j = -N, N do
		if i * i + j * j <= N * N then
			local x, z = center.X + i * step, center.Z + j * step
			local result = castDown(x, z, scanFromY)
			scanned += 1
			if result then
				local hit = result.Instance
				local class
				if hit:IsA("Terrain") then
					if result.Material == Enum.Material.Water then
						class = "Water"
					elseif PATH_MATERIALS[result.Material] then
						class = "Road"
					elseif DIRT_MATERIALS[result.Material] then
						class = "Dirt"
					else
						class = "Land"
					end
				elseif result.Normal.Y > 0.9 then
					local s = hit.Size
					local thin = math.min(s.X, s.Y, s.Z) <= 3
					if thin and (hasRoadName(hit) or PATH_MATERIALS[hit.Material]) then
						class = "Road"
					else
						class = "Land"
					end
				end
				if class then
					local k = key(i, j)
					cellClass[k] = class
					cellY[k] = result.Position.Y
				end
			end
		end
	end
end

-- 흙 띠가 좁으면 흙길: 가로나 세로로 양쪽에 풀밭(Land·Road)이 maxCells 안에 있으면
local maxCells = math.max(1, math.floor(cfg.DirtRoadMaxWidth / step))
local function landish(i: number, j: number): boolean
	local c = inGrid(i, j) and cellClass[key(i, j)]
	return c == "Land" or c == "Road"
end
local function narrowDirt(i: number, j: number): boolean
	for _, axis in { { 1, 0 }, { 0, 1 } } do
		local dx, dz = axis[1], axis[2]
		local a, b
		for k = 1, maxCells do
			local c = inGrid(i - dx * k, j - dz * k) and cellClass[key(i - dx * k, j - dz * k)]
			if c ~= "Dirt" then
				a = if landish(i - dx * k, j - dz * k) then k else nil
				break
			end
		end
		if a then
			for k = 1, maxCells do
				local c = inGrid(i + dx * k, j + dz * k) and cellClass[key(i + dx * k, j + dz * k)]
				if c ~= "Dirt" then
					b = if landish(i + dx * k, j + dz * k) then k else nil
					break
				end
			end
			if b and a + b - 1 <= maxCells then
				return true
			end
		end
	end
	return false
end

local roadCells = {}
local pavedCells, dirtCells = 0, 0
local dirtRoads = {}
for i = -N, N do
	for j = -N, N do
		local k = key(i, j)
		local c = cellClass[k]
		if c == "Road" then
			table.insert(roadCells, { I = i, J = j })
			pavedCells += 1
		elseif c == "Dirt" and narrowDirt(i, j) then
			table.insert(dirtRoads, k)
			table.insert(roadCells, { I = i, J = j })
			dirtCells += 1
		end
	end
end
for _, k in dirtRoads do
	cellClass[k] = "Road" -- 가장자리 찾기에서 흙길도 길로 본다
end

---------------------------------------------------------------- 3. 길 횃불 세우기
local DIRECTIONS = {}
for k = 0, 7 do
	local a = k / 8 * math.pi * 2
	table.insert(DIRECTIONS, Vector3.new(math.cos(a), 0, math.sin(a)))
end
local function cellAt(position: Vector3): (number, number)
	return math.floor((position.X - center.X) / step + 0.5), math.floor((position.Z - center.Z) / step + 0.5)
end

-- 마을에서 가까운 길부터 (마을에서 이어지는 길을 먼저 밝힌다)
for _, cell in roadCells do
	cell.D = cell.I * cell.I + cell.J * cell.J
end
table.sort(roadCells, function(a, b)
	return a.D < b.D
end)

local roadCount = 0
local roadFails = {}
for _, cell in roadCells do
	if roadCount >= cfg.MaxRoadTorches then
		break
	end
	local k = key(cell.I, cell.J)
	local roadPos = Vector3.new(center.X + cell.I * step, cellY[k], center.Z + cell.J * step)
	if farFromPlaced(roadPos, cfg.RoadSpacing) then
		-- 길 가장자리까지 거리를 8방향으로 재서 가까운 쪽부터 길 밖에 세워 본다
		local edges = {}
		for _, dir in DIRECTIONS do
			local d = step * 0.5
			while d <= cfg.RoadSideSearch do
				local i, j = cellAt(roadPos + dir * d)
				if not inGrid(i, j) or cellClass[key(i, j)] ~= "Road" then
					table.insert(edges, { Dir = dir, D = d })
					break
				end
				d += step * 0.5
			end
		end
		table.sort(edges, function(a, b)
			return a.D < b.D
		end)
		local done, reason = false, if #edges == 0 then "넓은 길" else "자리 없음"
		for n = 1, math.min(#edges, 4) do
			local edge = edges[n]
			local spot = roadPos + edge.Dir * (edge.D - step * 0.25 + cfg.RoadSideOffset)
			local ground, why = groundSpot(spot.X, spot.Z, { fromY = roadPos.Y + 40, refY = roadPos.Y, maxDy = 4 })
			if ground and farFromPlaced(ground, cfg.RoadSpacing * 0.8) then
				makeTorch(ground)
				table.insert(placed, ground)
				roadCount += 1
				done = true
				break
			end
			reason = why or reason
		end
		if not done then
			roadFails[reason] = (roadFails[reason] or 0) + 1
		end
	end
end

---------------------------------------------------------------- 4. 길을 못 찾으면: 마을 → 광산 입구 직선
local routeCount = 0
local routeNote = ""
if roadCount < cfg.RouteFallbackMin then
	-- 땅 위 광산 입구 = 마을 높이 근처의 MinePortal 중 마을에서 가장 가까운 것 (없으면 Mine/Floor0)
	local mineEntrance, best = nil, math.huge
	for _, portal in CollectionService:GetTagged("MinePortal") do
		local p = positionOf(portal)
		if p and p.Y > center.Y - 60 then
			local d = flatDistance(p, center)
			if d < best then
				mineEntrance, best = p, d
			end
		end
	end
	local mine = workspace:FindFirstChild("Mine")
	if not mineEntrance and mine and mine:FindFirstChild("Floor0") then
		mineEntrance = mine.Floor0:GetPivot().Position
	end
	if mineEntrance then
		local flat = Vector3.new(mineEntrance.X - center.X, 0, mineEntrance.Z - center.Z)
		local length = flat.Magnitude
		if length > 1 then
			local dir = flat.Unit
			local side = Vector3.new(-dir.Z, 0, dir.X)
			local fromY = math.max(center.Y, mineEntrance.Y) + 80
			local t = townRadius + cfg.RouteSpacing * 0.5
			local n = 0
			while t < length - 12 do
				n += 1
				local sign = if n % 2 == 1 then 1 else -1
				local mid = center + dir * t
				for _, try in { { sign, 0 }, { -sign, 0 }, { sign, 8 }, { sign, -8 }, { -sign, 8 } } do
					local p = mid + side * try[1] * cfg.RouteSideOffset + dir * try[2]
					if farFromPlaced(p, cfg.RouteSpacing * 0.7) then
						local ground = groundSpot(p.X, p.Z, { fromY = fromY })
						if ground then
							makeTorch(ground)
							table.insert(placed, ground)
							routeCount += 1
							break
						end
					end
				end
				t += cfg.RouteSpacing
			end
			routeNote = ` / 광산 가는 길(직선 {math.floor(length)}스터드): {routeCount}개`
		end
	else
		routeNote = " / 광산 입구를 못 찾아 직선 경로 없음"
	end
end

---------------------------------------------------------------- 요약
local function reasons(t): string
	local list = {}
	for why, count in t do
		table.insert(list, `{why} {count}`)
	end
	return if #list > 0 then ` (못 세운 곳: {table.concat(list, ", ")})` else ""
end
print(`[BuildTorches] 마을 가로등 {townCount}개 (마을 반경 약 {math.floor(townRadius)}, NPC {#npcs}명){reasons(townFails)}`)
print(`[BuildTorches] 길 횃불 {roadCount}개 - 격자 {scanned}칸 중 돌길 {pavedCells}칸·흙길 {dirtCells}칸{reasons(roadFails)}{routeNote}`)
if existingLights > 0 then
	print(`[BuildTorches] 원래 있던 불빛 {existingLights}개 근처는 건너뜀`)
end

return true
