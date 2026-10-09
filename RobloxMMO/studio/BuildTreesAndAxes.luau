--!nocheck
-- Studio 명령 줄(보기 → 명령 줄)에 통째로 붙여 넣고 Enter로 실행하는 제작 스크립트.
-- 게임 코드가 아니다 (Rojo가 동기화하지 않는다). 다시 실행하면 전에 만든 것을 지우고 새로 만든다.
--
-- 만드는 것
--   1. 도끼 Tool 4종  → ServerStorage/Templates/Pickaxes/{StoneAxe, CopperAxe, IronAxe, DiamondAxe}
--      같은 티어 곡괭이 Tool을 복제해 손잡이·잡는 위치(Grip)는 그대로 쓰고, 머리만 도끼날로 바꾼다.
--   2. 나무 템플릿 5종 → ServerStorage/Templates/Ores/{Pine, Oak, Birch, Maple, Ebony}/ (모양 변형 3개씩)
--      기준점(Pivot)은 줄기 밑동 가운데, 줄기 굵기는 OreDefs.HitRadius와 같다 (잔상 고리가 줄기에 딱 맞게).
--   3. 아이콘           → ReplicatedStorage/ItemIcons/{통나무 5종, 도끼 4종}
--   4. 스폰 자리        → Workspace/OreSpawns (속성 OreType)
--      소나무·참나무·자작나무는 마을(TownArrival) 둘레 곳곳, 단풍나무는 근처에서 가장 높은 곳에 모아서,
--      흑단나무는 마을에서 가장 먼 후보 자리들(속성 RandomPool = "Ebony", 그중 Config.RandomPools.Ebony.Active개만 선다)
--
-- 실행 뒤 할 일: 플레이 테스트로 도끼 날 방향을 확인. 날이 뒤로 달렸으면 FLIP_BLADE = true로 바꿔 다시 실행.
-- 스폰 자리는 Workspace/OreSpawns에서 GeneratedBy = "BuildTreesAndAxes" 파트를 옮기거나 지워서 다듬는다.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local OreDefs = require(ReplicatedStorage.Shared.OreDefs)
local Config = require(ReplicatedStorage.Shared.Config)

---------------------------------------------------------------- 설정
local FLIP_BLADE = false -- 도끼날이 반대쪽에 달렸으면 true
local GENERATED = "BuildTreesAndAxes" -- 이 스크립트가 만든 것 표시 (속성 GeneratedBy)
local SCATTER_MIN = 45 -- 마을 중심에서 이 거리 밖부터 나무를 심는다 (스터드)
local SCATTER_MAX = 230 -- 이 거리 안까지
local KEEP_AWAY = 22 -- NPC·광산 입구·마을 도착점에서 이만큼 떨어뜨린다
local MIN_SPACING = 12 -- 나무끼리 최소 간격
local COUNTS = { Pine = 14, Oak = 12, Birch = 10 } -- 흔한 나무 개수
local MAPLE_COUNT = 7 -- 단풍나무 무리 크기
local MAPLE_CLUSTER_RADIUS = 22
local EBONY_CANDIDATES = 6 -- 흑단나무 후보 자리 수
local GROUND_MATERIALS = { -- 나무를 심어도 되는 땅
	[Enum.Material.Grass] = true, [Enum.Material.LeafyGrass] = true, [Enum.Material.Ground] = true,
	[Enum.Material.Mud] = true, [Enum.Material.Sand] = false,
}

local random = Random.new()

---------------------------------------------------------------- 공용
-- 부품 하나 만들기
local function part(props: { [string]: any }, parent: Instance): BasePart
	local p = Instance.new(props.ClassName or "Part")
	props.ClassName = nil
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		p[key] = value
	end
	p.Parent = parent
	return p
end

-- 전에 이 스크립트가 만든 것을 지운다
local function clearGenerated(container: Instance)
	for _, child in container:GetChildren() do
		if child:GetAttribute("GeneratedBy") == GENERATED then
			child:Destroy()
		end
	end
end

local function folder(parent: Instance, name: string): Folder
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

local recording = ChangeHistoryService:TryBeginRecording("BuildTreesAndAxes")

local templates = folder(ServerStorage, "Templates")
local pickaxeFolder = folder(templates, "Pickaxes")
local oreFolder = folder(templates, "Ores")
local iconFolder = folder(ReplicatedStorage, "ItemIcons")

---------------------------------------------------------------- 1. 도끼
local AXES = {
	{ Id = "StoneAxe", From = "StonePickaxe", Head = Color3.fromRGB(150, 145, 140), Edge = Color3.fromRGB(190, 185, 180), Material = Enum.Material.Slate, BladeLen = 1.0, BladeH = 1.0 },
	{ Id = "CopperAxe", From = "CopperPickaxe", Head = Color3.fromRGB(205, 115, 60), Edge = Color3.fromRGB(240, 170, 110), Material = Enum.Material.Metal, BladeLen = 1.15, BladeH = 1.15, Trail = Color3.fromRGB(235, 140, 70) },
	{ Id = "IronAxe", From = "IronPickaxe", Head = Color3.fromRGB(170, 170, 175), Edge = Color3.fromRGB(235, 235, 240), Material = Enum.Material.Metal, BladeLen = 1.3, BladeH = 1.3, Trail = Color3.fromRGB(225, 230, 240) },
	{ Id = "DiamondAxe", From = "SteelPickaxe", Head = Color3.fromRGB(110, 220, 255), Edge = Color3.fromRGB(220, 250, 255), Material = Enum.Material.Glass, BladeLen = 1.5, BladeH = 1.5, Trail = Color3.fromRGB(110, 235, 255), Sparkle = true },
}

-- 손잡이 기준 주축 중 v와 가장 가까운 축 (부호 포함)
local function principal(v: Vector3): Vector3
	local ax, ay, az = math.abs(v.X), math.abs(v.Y), math.abs(v.Z)
	if ax >= ay and ax >= az then
		return Vector3.new(math.sign(v.X), 0, 0)
	elseif ay >= az then
		return Vector3.new(0, math.sign(v.Y), 0)
	end
	return Vector3.new(0, 0, math.sign(v.Z))
end

-- 곡괭이가 없을 때 쓸 기본 손잡이 Tool
local function fallbackTool(): Tool
	local tool = Instance.new("Tool")
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	part({ Name = "Handle", Size = Vector3.new(0.3, 3.2, 0.3), Color = Color3.fromRGB(120, 85, 55), Material = Enum.Material.Wood, Anchored = false, CanCollide = false }, tool)
	tool.Grip = CFrame.new(0, -1.1, 0)
	warn("[BuildTreesAndAxes] 곡괭이 템플릿이 없어 기본 손잡이로 만들었어요. 잡는 위치(Grip)를 확인하세요.")
	return tool
end

local function buildAxe(spec): Tool
	local source = pickaxeFolder:FindFirstChild(spec.From)
	local tool: Tool
	local headAxis: Vector3? = nil
	if source and source:IsA("Tool") and source:FindFirstChild("Handle") then
		tool = source:Clone()
		local handle = tool.Handle
		-- 곡괭이 머리가 뻗은 방향(손잡이 기준)을 알아낸 뒤, 머리 부품은 전부 지운다
		local far, farDist = nil, -1
		for _, d in tool:GetDescendants() do
			if d:IsA("BasePart") and d ~= handle then
				local offset = handle.CFrame:PointToObjectSpace(d.Position)
				if offset.Magnitude > farDist then
					far, farDist = offset, offset.Magnitude
				end
			end
		end
		for _, child in tool:GetChildren() do
			if child ~= handle and not child:IsA("LuaSourceContainer") then
				child:Destroy()
			end
		end
		for _, d in handle:GetChildren() do
			if d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("Trail") or d:IsA("Attachment") or d:IsA("ParticleEmitter") then
				d:Destroy()
			end
		end
		if far then
			headAxis = far
		end
	else
		tool = fallbackTool()
	end
	tool.Name = spec.Id
	tool:SetAttribute("PickaxeId", nil)
	tool:SetAttribute("GeneratedBy", GENERATED)
	local handle = tool.Handle :: BasePart

	-- u: 손잡이 긴 축(머리 쪽), a: 날이 뻗는 축, w: 두께 축 (모두 손잡이 기준)
	local size = handle.Size
	local long = if size.Y >= size.X and size.Y >= size.Z then Vector3.yAxis elseif size.X >= size.Z then Vector3.xAxis else Vector3.zAxis
	local grip = tool.Grip.Position
	local u = if grip:Dot(long) > 0.01 then -long else long -- 잡는 쪽 반대 끝에 머리
	local a: Vector3
	if headAxis then
		local side = headAxis - u * headAxis:Dot(u)
		a = if side.Magnitude > 0.05 then principal(side) else principal(u:Cross(Vector3.new(0.3, 0.2, 1)))
	else
		a = principal(u:Cross(Vector3.zAxis).Magnitude > 0.5 and u:Cross(Vector3.zAxis) or u:Cross(Vector3.xAxis))
	end
	if FLIP_BLADE then
		a = -a
	end
	local half = math.abs(size:Dot(long)) / 2
	local headCenter = u * (half - 0.3)

	-- 손잡이 기준 위치·축으로 부품을 붙인다. sizes = (a 방향, u 방향, w 방향)
	local function attach(name: string, center: Vector3, sizes: Vector3, color: Color3, material: Enum.Material, className: string?)
		local localCf = CFrame.fromMatrix(center, a, u)
		local p = part({
			ClassName = className,
			Name = name,
			Size = sizes,
			Color = color,
			Material = material,
			Anchored = false,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Massless = true,
			CFrame = handle.CFrame * localCf,
		}, tool)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = p
		weld.Parent = p
		return p
	end

	local bladeStart = 0.2
	attach("Collar", headCenter, Vector3.new(0.5, 0.6, 0.5), spec.Head:Lerp(Color3.new(0, 0, 0), 0.25), spec.Material)
	local blade = attach("Blade", headCenter + a * (bladeStart + spec.BladeLen / 2), Vector3.new(spec.BladeLen, spec.BladeH, 0.2), spec.Head, spec.Material)
	attach("Edge", headCenter + a * (bladeStart + spec.BladeLen + 0.07), Vector3.new(0.14, spec.BladeH * 1.25, 0.12), spec.Edge, if spec.Sparkle then Enum.Material.Neon else spec.Material)
	attach("Poll", headCenter - a * 0.4, Vector3.new(0.4, 0.5, 0.45), spec.Head:Lerp(Color3.new(0, 0, 0), 0.15), spec.Material)

	-- 좋은 도끼: 휘두를 때 날 끝 궤적 (SwingAnimation이 휘두르는 동안만 켠다)
	if spec.Trail then
		local top = Instance.new("Attachment")
		top.Name = "TrailTop"
		top.Position = Vector3.new(spec.BladeLen / 2, spec.BladeH * 0.6, 0)
		top.Parent = blade
		local bottom = Instance.new("Attachment")
		bottom.Name = "TrailBottom"
		bottom.Position = Vector3.new(spec.BladeLen / 2, -spec.BladeH * 0.6, 0)
		bottom.Parent = blade
		local trail = Instance.new("Trail")
		trail.Attachment0 = top
		trail.Attachment1 = bottom
		trail.Color = ColorSequence.new(spec.Trail)
		trail.Transparency = NumberSequence.new(0.3, 1)
		trail.Lifetime = 0.15
		trail.LightEmission = 0.6
		trail.Enabled = false
		trail.Parent = blade
	end
	if spec.Sparkle then
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Color = ColorSequence.new(spec.Edge)
		sparkles.LightEmission = 1
		sparkles.Size = NumberSequence.new(0.25, 0)
		sparkles.Lifetime = NumberRange.new(0.4, 0.8)
		sparkles.Rate = 4
		sparkles.Speed = NumberRange.new(0.5, 1)
		sparkles.Parent = blade
	end
	return tool
end

-- 도구를 아이콘용 모델로 (부품만 복사, 고정)
local function iconFromTool(tool: Tool, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	for _, d in tool:GetChildren() do
		if d:IsA("BasePart") then
			local copy = d:Clone()
			for _, c in copy:GetChildren() do
				if not (c:IsA("SpecialMesh") or c:IsA("SurfaceAppearance") or c:IsA("Decal") or c:IsA("Texture")) then
					c:Destroy()
				end
			end
			copy.Anchored = true
			copy.Parent = model
		end
	end
	model:SetAttribute("GeneratedBy", GENERATED)
	return model
end

for _, spec in AXES do
	local old = pickaxeFolder:FindFirstChild(spec.Id)
	if old then
		old:Destroy()
	end
	local tool = buildAxe(spec)
	tool.Parent = pickaxeFolder
	local oldIcon = iconFolder:FindFirstChild(spec.Id)
	if oldIcon then
		oldIcon:Destroy()
	end
	iconFromTool(tool, spec.Id).Parent = iconFolder
end
print("[BuildTreesAndAxes] 도끼 4종 완료")

---------------------------------------------------------------- 2. 나무
local LEAF_MATERIAL = Enum.Material.LeafyGrass

-- 줄기 (원통, 밑동이 origin)
local function trunk(model: Model, origin: CFrame, radius: number, height: number, color: Color3, material: Enum.Material): BasePart
	return part({
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = origin * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material,
	}, model)
end

-- 잎 덩어리 (공)
local function leafBall(model: Model, origin: CFrame, offset: Vector3, diameter: number, color: Color3, material: Enum.Material?)
	part({
		Name = "Leaves",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(diameter, diameter, diameter),
		CFrame = origin * CFrame.new(offset),
		Color = color,
		Material = material or LEAF_MATERIAL,
		CanCollide = false,
	}, model)
end

-- 잎이 둥글게 뭉친 활엽수 (참나무·자작나무·단풍나무·흑단나무)
local function broadleaf(model: Model, origin: CFrame, radius: number, height: number, canopy: number, leafColor: Color3, balls: number)
	leafBall(model, origin, Vector3.new(0, height + canopy * 0.25, 0), canopy, leafColor)
	for i = 1, balls do
		local angle = (i / balls) * math.pi * 2 + random:NextNumber(-0.3, 0.3)
		local r = canopy * random:NextNumber(0.35, 0.5)
		local size = canopy * random:NextNumber(0.55, 0.75)
		local shade = leafColor:Lerp(Color3.new(0, 0, 0), random:NextNumber(0, 0.18))
		leafBall(model, origin, Vector3.new(math.cos(angle) * r, height + random:NextNumber(-0.4, 0.6) * canopy * 0.4, math.sin(angle) * r), size, shade)
	end
	-- 굵은 가지 두 개
	for i = 1, 2 do
		local angle = random:NextNumber(0, math.pi * 2)
		part({
			Name = "Branch",
			Size = Vector3.new(radius * 0.7, canopy * 0.45, radius * 0.7),
			CFrame = origin * CFrame.new(0, height * 0.82, 0) * CFrame.Angles(0, angle, 0) * CFrame.Angles(math.rad(40), 0, 0) * CFrame.new(0, canopy * 0.2, 0),
			Color = model.Trunk.Color,
			Material = model.Trunk.Material,
			CanCollide = false,
		}, model)
	end
end

local TREE_BUILDERS = {}

-- 소나무: 곧고 높은 줄기 + 층층이 좁아지는 잎
TREE_BUILDERS.Pine = function(model, origin, def, scale)
	local height = 11 * scale
	trunk(model, origin, def.HitRadius, height, def.Color, Enum.Material.Wood)
	local layers = 4
	for i = 1, layers do
		local t = (i - 1) / (layers - 1)
		local width = (7.5 - t * 4.5) * scale
		local y = height * 0.45 + t * height * 0.55
		part({
			Name = "Leaves",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.8 * scale, width, width),
			CFrame = origin * CFrame.new(0, y, 0) * CFrame.Angles(0, random:NextNumber(0, 6.28), math.rad(90)),
			Color = def.LeafColor:Lerp(Color3.new(0, 0, 0), t * 0.15),
			Material = LEAF_MATERIAL,
			CanCollide = false,
		}, model)
	end
	leafBall(model, origin, Vector3.new(0, height + 0.8 * scale, 0), 2.2 * scale, def.LeafColor)
end

-- 참나무: 굵고 낮은 줄기 + 크고 넓은 잎
TREE_BUILDERS.Oak = function(model, origin, def, scale)
	local height = 7 * scale
	trunk(model, origin, def.HitRadius, height, def.Color, Enum.Material.Wood)
	broadleaf(model, origin, def.HitRadius, height, 8 * scale, def.LeafColor, 5)
end

-- 자작나무: 가늘고 높은 흰 줄기에 검은 줄무늬 + 작은 연두 잎
TREE_BUILDERS.Birch = function(model, origin, def, scale)
	local height = 11 * scale
	trunk(model, origin, def.HitRadius, height, def.Color, Enum.Material.SmoothPlastic)
	for i = 1, 6 do
		local y = random:NextNumber(1, height - 1)
		part({
			Name = "Stripe",
			Size = Vector3.new(def.HitRadius * random:NextNumber(0.6, 1.1), 0.18, 0.1),
			CFrame = origin * CFrame.Angles(0, random:NextNumber(0, 6.28), 0) * CFrame.new(0, y, def.HitRadius - 0.03),
			Color = Color3.fromRGB(35, 35, 35),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
		}, model)
	end
	broadleaf(model, origin, def.HitRadius, height, 5.5 * scale, def.LeafColor, 4)
end

-- 단풍나무: 붉은 잎
TREE_BUILDERS.Maple = function(model, origin, def, scale)
	local height = 8 * scale
	trunk(model, origin, def.HitRadius, height, def.Color, Enum.Material.Wood)
	broadleaf(model, origin, def.HitRadius, height, 7.5 * scale, def.LeafColor, 6)
end

-- 흑단나무: 검보라 줄기와 잎, 은은한 빛과 반짝이 (희귀)
TREE_BUILDERS.Ebony = function(model, origin, def, scale)
	local height = 9 * scale
	trunk(model, origin, def.HitRadius, height, def.Color, Enum.Material.Wood)
	broadleaf(model, origin, def.HitRadius, height, 7 * scale, def.LeafColor, 6)
	local glow = part({
		Name = "Glow",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1, 1, 1),
		CFrame = origin * CFrame.new(0, height, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	}, model)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(190, 120, 255)
	light.Range = 14
	light.Brightness = 1.2
	light.Parent = glow
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(Color3.fromRGB(210, 160, 255))
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new(0.4, 0)
	sparkles.Lifetime = NumberRange.new(1.5, 2.5)
	sparkles.Speed = NumberRange.new(0.3, 0.8)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Rate = 3
	sparkles.Parent = glow
end

local TREE_IDS = { "Pine", "Oak", "Birch", "Maple", "Ebony" }
local VARIANT_SCALES = { 0.9, 1.0, 1.12 }

for _, id in TREE_IDS do
	local def = OreDefs[id]
	local old = oreFolder:FindFirstChild(def.TemplateName)
	if old then
		old:Destroy()
	end
	local treeFolder = folder(oreFolder, def.TemplateName)
	for index, scale in VARIANT_SCALES do
		local model = Instance.new("Model")
		model.Name = `{id}{index}`
		local origin = CFrame.new(0, 0, 0)
		TREE_BUILDERS[id](model, origin, def, scale)
		model.PrimaryPart = model.Trunk
		model.WorldPivot = origin -- 기준점 = 줄기 밑동 가운데 (OreService·연출이 이 점을 기준으로 쓴다)
		model.Parent = treeFolder
	end
end
print("[BuildTreesAndAxes] 나무 5종 x 3모양 완료")

---------------------------------------------------------------- 3. 통나무 아이콘
for _, id in TREE_IDS do
	local def = OreDefs[id]
	local old = iconFolder:FindFirstChild(id)
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = id
	local length, radius = 2.4, 0.6
	part({ Name = "Bark", Shape = Enum.PartType.Cylinder, Size = Vector3.new(length, radius * 2, radius * 2), Color = def.Color, Material = if id == "Birch" then Enum.Material.SmoothPlastic else Enum.Material.Wood }, model)
	for _, side in { -1, 1 } do
		part({
			Name = "Ring",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.05, radius * 1.7, radius * 1.7),
			CFrame = CFrame.new(side * (length / 2 + 0.01), 0, 0),
			Color = Color3.fromRGB(225, 195, 145):Lerp(def.Color, if id == "Ebony" then 0.7 else 0.25),
			Material = Enum.Material.Wood,
		}, model)
	end
	model:SetAttribute("GeneratedBy", GENERATED)
	model.Parent = iconFolder
end
print("[BuildTreesAndAxes] 아이콘 완료")

---------------------------------------------------------------- 4. 스폰 자리
local spawns = folder(workspace, "OreSpawns")
clearGenerated(spawns)

local town = CollectionService:GetTagged("TownArrival")[1]
local center = if town and town:IsA("BasePart") then town.Position elseif town and town:IsA("Model") then town:GetPivot().Position else Vector3.zero
if not town then
	warn("[BuildTreesAndAxes] TownArrival 태그가 없어 (0, 0, 0) 둘레에 심었어요.")
end

-- 피해야 할 곳: NPC, 광산 입구, 마을 도착점
local avoid = {}
for _, tag in { "ShopNPC", "MinePortal", "TownArrival" } do
	for _, instance in CollectionService:GetTagged(tag) do
		local position = if instance:IsA("Model") then instance:GetPivot().Position elseif instance:IsA("BasePart") then instance.Position else nil
		if position then
			table.insert(avoid, position)
		end
	end
end
local zones = CollectionService:GetTagged("MineZone")

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = { spawns, workspace:FindFirstChild("Ores") }

-- 이 수평 위치에 나무를 심을 수 있으면 땅 위치를 돌려준다
local function groundAt(x: number, z: number): Vector3?
	local result = workspace:Raycast(Vector3.new(x, center.Y + 400, z), Vector3.new(0, -800, 0), params)
	if not result or result.Normal.Y < 0.8 then
		return nil -- 땅이 없거나 너무 가파름
	end
	local isGround = result.Instance:IsA("Terrain") and GROUND_MATERIALS[result.Material]
		or (result.Instance:IsA("BasePart") and result.Instance.Material == Enum.Material.Grass and result.Instance.Size.X > 30)
	if not isGround then
		return nil -- 건물·길·물 위
	end
	for _, zone in zones do
		if zone:IsA("BasePart") then
			local localPos = zone.CFrame:PointToObjectSpace(result.Position)
			local half = zone.Size / 2 + Vector3.new(4, 4, 4)
			if math.abs(localPos.X) < half.X and math.abs(localPos.Y) < half.Y and math.abs(localPos.Z) < half.Z then
				return nil -- 광산 구역 안
			end
		end
	end
	for _, position in avoid do
		if (position - result.Position).Magnitude < KEEP_AWAY then
			return nil
		end
	end
	return result.Position
end

-- 후보 땅 자리를 고루 모은다
local candidates = {}
for _ = 1, 1500 do
	local angle = random:NextNumber(0, math.pi * 2)
	local distance = math.sqrt(random:NextNumber(SCATTER_MIN ^ 2, SCATTER_MAX ^ 2)) -- 넓이 기준 고르게
	local ground = groundAt(center.X + math.cos(angle) * distance, center.Z + math.sin(angle) * distance)
	if ground then
		table.insert(candidates, ground)
	end
end

local placed = {}
local function farFromOthers(position: Vector3): boolean
	for _, other in placed do
		if (other - position).Magnitude < MIN_SPACING then
			return false
		end
	end
	return true
end

local function addSpawn(position: Vector3, oreType: string, pool: string?)
	local p = part({
		Name = `{oreType}Spawn`,
		Size = Vector3.new(2, 1, 2),
		CFrame = CFrame.new(position + Vector3.new(0, 1, 0)),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	}, spawns)
	p:SetAttribute("OreType", oreType)
	p:SetAttribute("Floor", 0)
	p:SetAttribute("GeneratedBy", GENERATED)
	if pool then
		p:SetAttribute("RandomPool", pool)
	end
	table.insert(placed, position)
end

-- 흑단나무: 마을에서 가장 먼 후보 자리들 (서로 멀리)
table.sort(candidates, function(a, b)
	return (a - center).Magnitude > (b - center).Magnitude
end)
local ebony = 0
for _, position in candidates do
	if ebony >= EBONY_CANDIDATES then
		break
	end
	local spread = true
	for _, other in placed do
		if (other - position).Magnitude < SCATTER_MAX * 0.5 then
			spread = false
			break
		end
	end
	if spread then
		addSpawn(position, "Ebony", "Ebony")
		ebony += 1
	end
end

-- 단풍나무: 가장 높은 곳 둘레에 모아서
local peak = nil
for _, position in candidates do
	if farFromOthers(position) and (not peak or position.Y > peak.Y) then
		peak = position
	end
end
local maple = 0
if peak then
	for _ = 1, 300 do
		if maple >= MAPLE_COUNT then
			break
		end
		local angle = random:NextNumber(0, math.pi * 2)
		local r = random:NextNumber(0, MAPLE_CLUSTER_RADIUS)
		local ground = groundAt(peak.X + math.cos(angle) * r, peak.Z + math.sin(angle) * r)
		if ground and farFromOthers(ground) then
			addSpawn(ground, "Maple")
			maple += 1
		end
	end
end

-- 흔한 나무: 남은 후보 자리에 무작위로
for i = #candidates, 2, -1 do
	local j = random:NextInteger(1, i)
	candidates[i], candidates[j] = candidates[j], candidates[i]
end
local commonCounts = {}
local cursor = 1
for oreType, count in COUNTS do
	commonCounts[oreType] = 0
	while commonCounts[oreType] < count and cursor <= #candidates do
		local position = candidates[cursor]
		cursor += 1
		if farFromOthers(position) then
			addSpawn(position, oreType)
			commonCounts[oreType] += 1
		end
	end
end

print(
	`[BuildTreesAndAxes] 스폰 자리: 소나무 {commonCounts.Pine} / 참나무 {commonCounts.Oak} / 자작나무 {commonCounts.Birch}`
		.. ` / 단풍나무 {maple} / 흑단나무 후보 {ebony} (동시에 {Config.RandomPools.Ebony.Active}그루). 후보 땅 {#candidates}곳`
)
if #candidates == 0 then
	warn("[BuildTreesAndAxes] 심을 땅을 못 찾았어요. GROUND_MATERIALS나 SCATTER_MIN/MAX를 맵에 맞게 바꿔 보세요.")
end

if recording then
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end
print("[BuildTreesAndAxes] 끝. Ctrl+Z로 한 번에 되돌릴 수 있어요.")
