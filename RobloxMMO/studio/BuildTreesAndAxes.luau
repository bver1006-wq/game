--!strict
-- Studio 명령 모음(Command Bar)에 통째로 붙여 넣고 실행하는 1회용 제작 스크립트. (Rojo 동기화 대상 아님)
-- 만드는 것:
--   1) 나무 5종 원본: ServerStorage/Templates/Ores/<Pine|Oak|Birch|Maple|Ebony>/ 안에 모양 변형 3개씩
--      (기준점 = 줄기 밑동 가운데, PrimaryPart = Trunk. OreDefs의 HitHeight·HitRadius와 줄기 굵기를 맞춤)
--   2) 도끼 4종 Tool: ServerStorage/Templates/Pickaxes/<StoneAxe|CopperAxe|IronAxe|DiamondAxe>
--   3) 아이콘: ReplicatedStorage/ItemIcons/ 에 통나무 5종 + 도끼 4종
--   4) 나무 스폰 자리: Workspace/OreSpawns/ 에 투명 파트 (마을 도착 지점 주변 풀밭에 무작위로)
-- 다시 실행하면 이 스크립트가 만든 것(속성 GeneratedBy)만 지우고 새로 만든다. Ctrl+Z로 되돌릴 수 있다.
-- 스폰 자리가 마음에 안 들면 PLACE_SPAWNS만 true로 두고 다시 돌리거나, 파트를 직접 옮기면 된다.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

-- ===== 설정 =====
local BUILD_TEMPLATES = true
local BUILD_ICONS = true
local PLACE_SPAWNS = true

local SPAWN_RADIUS_MIN = 50 -- 마을 도착 지점에서 이만큼 떨어진 곳부터 (스터드)
local SPAWN_RADIUS_MAX = 260 -- 이만큼까지
local SPAWN_COUNTS = { Pine = 18, Oak = 14, Birch = 10, Maple = 8 }
local EBONY_CANDIDATES = 8 -- 흑단나무 후보 자리 수 (그중 Config.RandomPools.Ebony.Active개만 서 있다)
local TREE_SPACING = 10 -- 나무끼리 최소 거리
local EBONY_SPACING = 45 -- 흑단 후보끼리 최소 거리
local MAPLE_CLUSTER_RADIUS = 28 -- 단풍나무 무리 반경
local BUILDING_CLEARANCE = 9 -- 건물·소품(지형이 아닌 파트)과 이만큼 떨어뜨린다
local SEED = 20261009

local MARK = "GeneratedBy"
local MARK_VALUE = "TreeAxeBuilder"

local random = Random.new(SEED)

-- ===== 공용 =====

-- 이 스크립트가 만든 표시를 붙인다
local function mark(instance: Instance)
	instance:SetAttribute(MARK, MARK_VALUE)
end

-- 이전 실행에서 만든 것 지우기
local function clearGenerated(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:GetAttribute(MARK) == MARK_VALUE then
			child:Destroy()
		end
	end
end

-- 폴더를 찾거나 만든다
local function folderOf(parent: Instance, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- 파트 하나 만들기
local function part(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	if props.Shape then
		p.Shape = props.Shape
	end
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		if key ~= "Shape" then
			(p :: any)[key] = value
		end
	end
	return p
end

-- ===== 나무 =====

type TreeStyle = {
	TrunkColor: Color3,
	TrunkMaterial: Enum.Material,
	TrunkDiameter: number,
	TrunkHeight: number,
	Leaves: Color3,
	Leaves2: Color3,
	LeafMaterial: Enum.Material,
	Shape: "Pine" | "Round" | "Tall",
	Spots: Color3?, -- 자작나무 줄기 무늬
	Glow: Color3?, -- 흑단나무 빛나는 열매
}

-- 줄기 굵기는 OreDefs.HitRadius보다 조금 가늘게 (타격 위치가 줄기 표면 바로 밖)
local TREE_STYLES: { [string]: TreeStyle } = {
	Pine = {
		TrunkColor = Color3.fromRGB(110, 75, 45),
		TrunkMaterial = Enum.Material.Wood,
		TrunkDiameter = 1.4,
		TrunkHeight = 10,
		Leaves = Color3.fromRGB(40, 95, 55),
		Leaves2 = Color3.fromRGB(55, 115, 65),
		LeafMaterial = Enum.Material.Grass,
		Shape = "Pine",
	},
	Oak = {
		TrunkColor = Color3.fromRGB(105, 72, 45),
		TrunkMaterial = Enum.Material.Wood,
		TrunkDiameter = 2.2,
		TrunkHeight = 7,
		Leaves = Color3.fromRGB(75, 140, 55),
		Leaves2 = Color3.fromRGB(95, 160, 65),
		LeafMaterial = Enum.Material.Grass,
		Shape = "Round",
	},
	Birch = {
		TrunkColor = Color3.fromRGB(232, 228, 215),
		TrunkMaterial = Enum.Material.SmoothPlastic,
		TrunkDiameter = 1.2,
		TrunkHeight = 11,
		Leaves = Color3.fromRGB(160, 200, 80),
		Leaves2 = Color3.fromRGB(190, 215, 95),
		LeafMaterial = Enum.Material.Grass,
		Shape = "Tall",
		Spots = Color3.fromRGB(45, 40, 40),
	},
	Maple = {
		TrunkColor = Color3.fromRGB(100, 62, 40),
		TrunkMaterial = Enum.Material.Wood,
		TrunkDiameter = 1.8,
		TrunkHeight = 8,
		Leaves = Color3.fromRGB(215, 75, 40),
		Leaves2 = Color3.fromRGB(240, 150, 50),
		LeafMaterial = Enum.Material.Grass,
		Shape = "Round",
	},
	Ebony = {
		TrunkColor = Color3.fromRGB(40, 28, 40),
		TrunkMaterial = Enum.Material.Wood,
		TrunkDiameter = 1.8,
		TrunkHeight = 9,
		Leaves = Color3.fromRGB(70, 40, 95),
		Leaves2 = Color3.fromRGB(95, 55, 125),
		LeafMaterial = Enum.Material.Grass,
		Shape = "Round",
		Glow = Color3.fromRGB(190, 120, 255),
	},
}
local TREE_ORDER = { "Pine", "Oak", "Birch", "Maple", "Ebony" }

-- 나무 하나 만들기 (원점 = 밑동 가운데). variant마다 크기·잎 배치가 조금 다르다
local function buildTree(name: string, style: TreeStyle, variant: number): Model
	local r = Random.new(SEED + variant * 31 + #name)
	local model = Instance.new("Model")
	model.Name = `{name}_{variant}`

	local height = style.TrunkHeight * r:NextNumber(0.85, 1.15)
	local d = style.TrunkDiameter
	-- 원통은 X축이 길이 방향이라 세운다
	local trunk = part({
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, d, d),
		CFrame = CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = style.TrunkColor,
		Material = style.TrunkMaterial,
	})
	trunk.Parent = model
	model.PrimaryPart = trunk
	-- 기준점을 밑동 가운데로 (OreDefs.HitHeight가 밑동 기준). 원통이 누워 있어서 로컬 X가 위아래다
	trunk.PivotOffset = CFrame.new(-height / 2, 0, 0) * CFrame.Angles(0, 0, -math.pi / 2)

	-- 밑동 뿌리 (조금 넓게 퍼진 판)
	local root = part({
		Name = "Root",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, d * 1.5, d * 1.5),
		CFrame = CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = style.TrunkColor,
		Material = style.TrunkMaterial,
		CanCollide = false,
	})
	root.Parent = model

	if style.Spots then
		for i = 1, 7 do
			local y = r:NextNumber(1, height - 1)
			local angle = r:NextNumber(0, math.pi * 2)
			local spot = part({
				Name = "Spot",
				Size = Vector3.new(0.05, r:NextNumber(0.15, 0.3), r:NextNumber(0.4, 0.8)),
				CFrame = CFrame.new(0, y, 0) * CFrame.Angles(0, angle, 0) * CFrame.new(d / 2, 0, 0),
				Color = style.Spots,
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				CanQuery = false,
			})
			spot.Parent = model
		end
	end

	-- 잎: 충돌 없이 (밑으로 지나다녀도 걸리지 않게)
	local function leaf(size: Vector3, cframe: CFrame, color: Color3, shape: Enum.PartType?)
		local p = part({
			Name = "Leaves",
			Shape = shape or Enum.PartType.Ball,
			Size = size,
			CFrame = cframe,
			Color = color,
			Material = style.LeafMaterial,
			CanCollide = false,
			CanQuery = false,
			CastShadow = true,
		})
		p.Parent = model
	end

	if style.Shape == "Pine" then
		-- 위로 갈수록 작아지는 층 (45도씩 돌린 네모 판을 겹쳐 뾰족하게)
		local layers = 4
		for i = 1, layers do
			local t = (i - 1) / (layers - 1)
			local width = (7 - t * 4.8) * r:NextNumber(0.92, 1.08)
			local y = height * 0.35 + t * height * 0.6
			local color = if i % 2 == 0 then style.Leaves2 else style.Leaves
			leaf(Vector3.new(width, 1.8, width), CFrame.new(0, y, 0) * CFrame.Angles(0, math.rad(45 * i), 0), color, Enum.PartType.Block)
			leaf(Vector3.new(width * 0.7, 1.4, width * 0.7), CFrame.new(0, y + 1.1, 0) * CFrame.Angles(0, math.rad(45 * i + 22), 0), color, Enum.PartType.Block)
		end
		leaf(Vector3.new(1.2, 2.2, 1.2), CFrame.new(0, height + 0.8, 0), style.Leaves2, Enum.PartType.Block)
	else
		local tall = style.Shape == "Tall"
		local spread = if tall then 3 else 4.5
		local size = if tall then 4.2 else 6.5
		local top = height + (if tall then 0 else 1.2)
		leaf(Vector3.one * size * 1.15, CFrame.new(0, top, 0), style.Leaves)
		local blobs = if tall then 5 else 6
		for i = 1, blobs do
			local angle = (i / blobs) * math.pi * 2 + r:NextNumber(-0.3, 0.3)
			local s = size * r:NextNumber(0.7, 0.95)
			local y = top - (if tall then r:NextNumber(0.5, 3.5) else r:NextNumber(-0.8, 1.2))
			local offset = Vector3.new(math.cos(angle) * spread, 0, math.sin(angle) * spread) * r:NextNumber(0.75, 1)
			leaf(Vector3.one * s, CFrame.new(offset.X, y, offset.Z), if i % 2 == 0 then style.Leaves2 else style.Leaves)
		end
		if tall then
			leaf(Vector3.one * size * 0.8, CFrame.new(0, top + 2.6, 0), style.Leaves2)
		end
	end

	if style.Glow then
		-- 흑단나무: 잎 사이에 빛나는 열매 + 은은한 빛 (희귀한 나무라는 표시)
		for i = 1, 6 do
			local angle = r:NextNumber(0, math.pi * 2)
			local fruit = part({
				Name = "GlowFruit",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 0.6,
				CFrame = CFrame.new(math.cos(angle) * 3.6, height + r:NextNumber(-1.5, 1.5), math.sin(angle) * 3.6),
				Color = style.Glow,
				Material = Enum.Material.Neon,
				CanCollide = false,
				CanQuery = false,
			})
			fruit.Parent = model
		end
		local light = Instance.new("PointLight")
		light.Color = style.Glow
		light.Range = 16
		light.Brightness = 1.2
		light.Parent = trunk
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkle.Color = ColorSequence.new(style.Glow)
		sparkle.LightEmission = 1
		sparkle.Size = NumberSequence.new(0.3, 0)
		sparkle.Lifetime = NumberRange.new(1, 2)
		sparkle.Rate = 4
		sparkle.Speed = NumberRange.new(0.5, 1.5)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Parent = trunk
	end

	mark(model)
	return model
end

local function buildTreeTemplates()
	local ores = folderOf(folderOf(ServerStorage, "Templates"), "Ores")
	for _, name in TREE_ORDER do
		local folder = folderOf(ores, name)
		clearGenerated(folder)
		for variant = 1, 3 do
			buildTree(name, TREE_STYLES[name], variant).Parent = folder
		end
	end
	print("[TreeAxeBuilder] 나무 원본 5종 x 3개 완료")
end

-- ===== 도끼 =====

type AxeStyle = {
	HeadColor: Color3,
	HeadMaterial: Enum.Material,
	EdgeColor: Color3,
	EdgeMaterial: Enum.Material,
	HandleColor: Color3,
	Scale: number, -- 티어가 높을수록 조금 크게
	Trail: Color3?,
}

local AXE_STYLES: { [string]: AxeStyle } = {
	StoneAxe = {
		HeadColor = Color3.fromRGB(125, 122, 118),
		HeadMaterial = Enum.Material.Slate,
		EdgeColor = Color3.fromRGB(160, 157, 150),
		EdgeMaterial = Enum.Material.Slate,
		HandleColor = Color3.fromRGB(120, 85, 50),
		Scale = 1,
	},
	CopperAxe = {
		HeadColor = Color3.fromRGB(190, 105, 55),
		HeadMaterial = Enum.Material.Metal,
		EdgeColor = Color3.fromRGB(235, 160, 100),
		EdgeMaterial = Enum.Material.Metal,
		HandleColor = Color3.fromRGB(150, 105, 65), -- 소나무 손잡이
		Scale = 1.05,
		Trail = Color3.fromRGB(235, 140, 70),
	},
	IronAxe = {
		HeadColor = Color3.fromRGB(150, 152, 160),
		HeadMaterial = Enum.Material.Metal,
		EdgeColor = Color3.fromRGB(225, 230, 240),
		EdgeMaterial = Enum.Material.Metal,
		HandleColor = Color3.fromRGB(215, 205, 185), -- 자작나무 손잡이
		Scale = 1.12,
		Trail = Color3.fromRGB(225, 230, 240),
	},
	DiamondAxe = {
		HeadColor = Color3.fromRGB(70, 80, 95),
		HeadMaterial = Enum.Material.Metal,
		EdgeColor = Color3.fromRGB(110, 235, 255),
		EdgeMaterial = Enum.Material.Neon,
		HandleColor = Color3.fromRGB(150, 85, 50), -- 단풍나무 손잡이
		Scale = 1.2,
		Trail = Color3.fromRGB(110, 235, 255),
	},
}
local AXE_ORDER = { "StoneAxe", "CopperAxe", "IronAxe", "DiamondAxe" }

-- 도끼 부품들을 만든다 (자루 = Z축, 손은 -Z 쪽, 머리는 +Z 끝, 날은 -X 쪽)
-- 돌려주는 첫 번째가 자루(Handle)
local function buildAxeParts(style: AxeStyle): { BasePart }
	local s = style.Scale
	local length = 4 * s
	local handle = part({
		Name = "Handle",
		Size = Vector3.new(0.32, 0.32, length),
		CFrame = CFrame.new(0, 0, 0),
		Color = style.HandleColor,
		Material = Enum.Material.Wood,
	})
	local headZ = length / 2 - 0.45 * s
	local head = part({
		Name = "Head",
		Size = Vector3.new(0.9 * s, 0.42, 0.9 * s),
		CFrame = CFrame.new(-0.25 * s, 0, headZ),
		Color = style.HeadColor,
		Material = style.HeadMaterial,
	})
	-- 날: 자루에서 바깥(-X)으로 뻗은 판. 끝의 Edge가 더 길어서 날이 퍼져 보인다
	local bladeLen = 1.1 * s
	local blade = part({
		Name = "Blade",
		Size = Vector3.new(bladeLen, 0.2, 1.2 * s),
		CFrame = CFrame.new(-0.7 * s - bladeLen / 2, 0, headZ),
		Color = style.HeadColor,
		Material = style.HeadMaterial,
	})
	local edge = part({
		Name = "Edge",
		Size = Vector3.new(0.14, 0.24, 1.55 * s),
		CFrame = CFrame.new(-0.7 * s - bladeLen - 0.05, 0, headZ),
		Color = style.EdgeColor,
		Material = style.EdgeMaterial,
	})
	local poll = part({
		Name = "Poll",
		Size = Vector3.new(0.45 * s, 0.38, 0.55 * s),
		CFrame = CFrame.new(0.35 * s, 0, headZ),
		Color = style.HeadColor,
		Material = style.HeadMaterial,
	})
	local grip = part({
		Name = "Wrap",
		Size = Vector3.new(0.38, 0.38, 0.9),
		CFrame = CFrame.new(0, 0, -length / 2 + 0.75),
		Color = Color3.fromRGB(70, 45, 30),
		Material = Enum.Material.Fabric,
	})
	return { handle, head, blade, edge, poll, grip }
end

local function buildAxeTool(id: string, style: AxeStyle): Tool
	local tool = Instance.new("Tool")
	tool.Name = id
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	-- ClassicSword와 같은 잡는 방향: 자루(Z축)가 손 위쪽으로 뻗는다. 손은 자루 아래쪽 끝 근처
	-- 모양이 어색하면 Studio에서 Tool의 Grip 속성(GripPos 등)만 조절하면 된다
	tool.GripForward = Vector3.new(-1, 0, 0)
	tool.GripRight = Vector3.new(0, 1, 0)
	tool.GripUp = Vector3.new(0, 0, 1)
	tool.GripPos = Vector3.new(0, 0, -2 * style.Scale + 0.75)

	local parts = buildAxeParts(style)
	local handle = parts[1]
	for _, p in parts do
		p.Anchored = false
		p.CanCollide = false
		p.Massless = true
		p.CanQuery = false
		p.CanTouch = false
		p.Parent = tool
		if p ~= handle then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = p
			weld.Parent = p
		end
	end

	-- 좋은 도끼는 휘두를 때 궤적 (SwingAnimation이 휘두르는 동안만 켠다)
	if style.Trail then
		local edge = tool:FindFirstChild("Edge") :: BasePart
		local a0 = Instance.new("Attachment")
		a0.Name = "TrailTop"
		a0.Position = Vector3.new(0, 0, 0.7 * style.Scale)
		a0.Parent = edge
		local a1 = Instance.new("Attachment")
		a1.Name = "TrailBottom"
		a1.Position = Vector3.new(0, 0, -0.7 * style.Scale)
		a1.Parent = edge
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(style.Trail)
		trail.Transparency = NumberSequence.new(0.3, 1)
		trail.Lifetime = 0.18
		trail.LightEmission = 0.8
		trail.Enabled = false
		trail.Parent = edge
	end

	mark(tool)
	return tool
end

local function buildAxeTemplates()
	local pickaxes = folderOf(folderOf(ServerStorage, "Templates"), "Pickaxes")
	for _, id in AXE_ORDER do
		local old = pickaxes:FindFirstChild(id)
		if old and old:GetAttribute(MARK) == MARK_VALUE then
			old:Destroy()
		end
		if pickaxes:FindFirstChild(id) then
			warn(`[TreeAxeBuilder] Templates/Pickaxes/{id}가 이미 있어서(직접 만든 것) 건드리지 않았어요.`)
		else
			buildAxeTool(id, AXE_STYLES[id]).Parent = pickaxes
		end
	end
	print("[TreeAxeBuilder] 도끼 4종 완료")
end

-- ===== 아이콘 =====

local LOG_COLORS = {
	Pine = { Bark = Color3.fromRGB(110, 75, 45), Wood = Color3.fromRGB(225, 190, 135) },
	Oak = { Bark = Color3.fromRGB(95, 65, 40), Wood = Color3.fromRGB(190, 145, 95) },
	Birch = { Bark = Color3.fromRGB(232, 228, 215), Wood = Color3.fromRGB(240, 225, 190) },
	Maple = { Bark = Color3.fromRGB(100, 62, 40), Wood = Color3.fromRGB(215, 160, 110) },
	Ebony = { Bark = Color3.fromRGB(40, 28, 40), Wood = Color3.fromRGB(85, 55, 85) },
}

-- 통나무 아이콘: 누운 원통 + 밝은 나이테 단면
local function buildLogIcon(name: string): Model
	local colors = LOG_COLORS[name]
	local model = Instance.new("Model")
	model.Name = name
	local log = part({
		Name = "Log",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3, 1.4, 1.4),
		CFrame = CFrame.new(),
		Color = colors.Bark,
		Material = Enum.Material.Wood,
	})
	log.Parent = model
	for _, side in { -1, 1 } do
		local cap = part({
			Name = "Cap",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.06, 1.25, 1.25),
			CFrame = CFrame.new(side * 1.5, 0, 0),
			Color = colors.Wood,
			Material = Enum.Material.WoodPlanks,
		})
		cap.Parent = model
		local ring = part({
			Name = "Ring",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.08, 0.6, 0.6),
			CFrame = CFrame.new(side * 1.5, 0, 0),
			Color = colors.Bark:Lerp(colors.Wood, 0.5),
			Material = Enum.Material.WoodPlanks,
		})
		ring.Parent = model
	end
	model.PrimaryPart = log
	mark(model)
	return model
end

-- 도끼 아이콘: 도끼 부품을 그대로 비스듬히 세운 모델
local function buildAxeIcon(id: string): Model
	local model = Instance.new("Model")
	model.Name = id
	for _, p in buildAxeParts(AXE_STYLES[id]) do
		p.CFrame = CFrame.Angles(math.rad(-90), 0, math.rad(-35)) * p.CFrame
		p.Parent = model
	end
	model.PrimaryPart = model:FindFirstChild("Handle") :: BasePart
	mark(model)
	return model
end

local function buildIcons()
	local icons = folderOf(ReplicatedStorage, "ItemIcons")
	for _, name in TREE_ORDER do
		local old = icons:FindFirstChild(name)
		if old and old:GetAttribute(MARK) == MARK_VALUE then
			old:Destroy()
		end
		if not icons:FindFirstChild(name) then
			buildLogIcon(name).Parent = icons
		end
	end
	for _, id in AXE_ORDER do
		local old = icons:FindFirstChild(id)
		if old and old:GetAttribute(MARK) == MARK_VALUE then
			old:Destroy()
		end
		if not icons:FindFirstChild(id) then
			buildAxeIcon(id).Parent = icons
		end
	end
	print("[TreeAxeBuilder] 아이콘 9개 완료")
end

-- ===== 스폰 자리 =====

local spawnsFolder: Instance
local placed: { Vector3 } = {}

-- 마을 기준점 (태그 TownArrival, 없으면 SpawnLocation, 그것도 없으면 원점)
local function townCenter(): Vector3
	for _, town in CollectionService:GetTagged("TownArrival") do
		if town:IsA("BasePart") then
			return town.Position
		end
	end
	local spawnLocation = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	return if spawnLocation then spawnLocation.Position else Vector3.zero
end

local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude

local GRASSY = {
	[Enum.Material.Grass] = true,
	[Enum.Material.LeafyGrass] = true,
	[Enum.Material.Ground] = true,
	[Enum.Material.Mud] = true,
}

-- 그 자리가 나무 심기에 괜찮으면 땅 위치를 돌려준다
-- 풀밭(지형 또는 풀 재질 파트)이고, 물이 아니고, 건물·광산 구역과 떨어져 있어야 한다
local function groundAt(x: number, z: number, center: Vector3): Vector3?
	local origin = Vector3.new(x, center.Y + 400, z)
	local result = Workspace:Raycast(origin, Vector3.new(0, -900, 0), castParams)
	if not result or not GRASSY[result.Material] then
		return nil
	end
	local hit = result.Instance
	if hit ~= Workspace.Terrain and not (hit:IsA("BasePart") and hit.Size.X > 60 and hit.Size.Z > 60) then
		return nil -- 지형이나 큰 바닥판이 아니면(지붕·소품 위) 안 심는다
	end
	local position = result.Position
	-- 근처에 지형이 아닌 파트(집, 울타리, NPC, 바위)가 있으면 건너뛴다. 큰 바닥판은 무시
	for _, nearby in Workspace:GetPartBoundsInRadius(position + Vector3.new(0, 4, 0), BUILDING_CLEARANCE, overlapParams) do
		if not (nearby.Size.X > 60 and nearby.Size.Z > 60) then
			return nil
		end
	end
	for _, zone in CollectionService:GetTagged("MineZone") do
		if zone:IsA("BasePart") then
			local localPos = zone.CFrame:PointToObjectSpace(position)
			local half = zone.Size / 2 + Vector3.one * 10
			if math.abs(localPos.X) < half.X and math.abs(localPos.Y) < half.Y + 40 and math.abs(localPos.Z) < half.Z then
				return nil
			end
		end
	end
	return position
end

local function farEnough(position: Vector3, spacing: number): boolean
	for _, other in placed do
		if (Vector3.new(other.X, 0, other.Z) - Vector3.new(position.X, 0, position.Z)).Magnitude < spacing then
			return false
		end
	end
	return true
end

local function addSpawn(oreType: string, position: Vector3, pool: string?)
	local p = part({
		Name = `TreeSpawn_{oreType}`,
		Size = Vector3.new(2, 2, 2),
		Position = position + Vector3.new(0, 1, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	p:SetAttribute("OreType", oreType)
	if pool then
		p:SetAttribute("RandomPool", pool)
	end
	mark(p)
	p.Parent = spawnsFolder
	table.insert(placed, position)
end

-- 마을 주변 고리 안의 무작위 지점
local function randomRingPoint(center: Vector3, minR: number, maxR: number): (number, number)
	local angle = random:NextNumber(0, math.pi * 2)
	local radius = math.sqrt(random:NextNumber(minR * minR, maxR * maxR)) -- 넓이에 고르게
	return center.X + math.cos(angle) * radius, center.Z + math.sin(angle) * radius
end

local function placeSpawns()
	spawnsFolder = folderOf(Workspace, "OreSpawns")
	clearGenerated(spawnsFolder)
	table.clear(placed)
	-- 이미 있던 스폰(광석 등)과 겹치지 않게 등록
	for _, child in spawnsFolder:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(placed, child.Position)
		end
	end
	local ores = Workspace:FindFirstChild("Ores")
	castParams.FilterDescendantsInstances = { spawnsFolder, ores :: Instance }
	overlapParams.FilterDescendantsInstances = { spawnsFolder, Workspace.Terrain, ores :: Instance }

	local center = townCenter()
	print(`[TreeAxeBuilder] 마을 기준점 {center}`)

	-- 단풍나무 무리: 후보 중 높고 먼 곳 ("산 구석")
	local bestCorner: Vector3? = nil
	local bestScore = -math.huge
	for _ = 1, 300 do
		local x, z = randomRingPoint(center, SPAWN_RADIUS_MAX * 0.5, SPAWN_RADIUS_MAX)
		local ground = groundAt(x, z, center)
		if ground then
			local score = (ground.Y - center.Y) + (ground - center).Magnitude * 0.15
			if score > bestScore then
				bestScore = score
				bestCorner = ground
			end
		end
	end

	local function scatter(oreType: string, count: number, attempt: () -> (number, number), spacing: number, pool: string?)
		local made = 0
		for _ = 1, count * 60 do
			if made >= count then
				break
			end
			local x, z = attempt()
			local ground = groundAt(x, z, center)
			if ground and farEnough(ground, spacing) then
				addSpawn(oreType, ground, pool)
				made += 1
			end
		end
		print(`[TreeAxeBuilder] {oreType} 자리 {made}/{count}`)
	end

	if bestCorner then
		local corner = bestCorner
		scatter("Maple", SPAWN_COUNTS.Maple, function()
			local angle = random:NextNumber(0, math.pi * 2)
			local radius = random:NextNumber(0, MAPLE_CLUSTER_RADIUS)
			return corner.X + math.cos(angle) * radius, corner.Z + math.sin(angle) * radius
		end, TREE_SPACING * 0.8)
		print(`[TreeAxeBuilder] 단풍나무 무리 위치 {corner}`)
	else
		warn("[TreeAxeBuilder] 단풍나무 무리 자리를 못 찾았어요. 풀밭 지형이 있는지 확인하세요.")
	end

	local function ring()
		return randomRingPoint(center, SPAWN_RADIUS_MIN, SPAWN_RADIUS_MAX)
	end
	scatter("Pine", SPAWN_COUNTS.Pine, ring, TREE_SPACING)
	scatter("Oak", SPAWN_COUNTS.Oak, ring, TREE_SPACING)
	scatter("Birch", SPAWN_COUNTS.Birch, ring, TREE_SPACING)
	-- 흑단 후보: 마을에서 먼 곳에 흩어서
	scatter("Ebony", EBONY_CANDIDATES, function()
		return randomRingPoint(center, SPAWN_RADIUS_MAX * 0.55, SPAWN_RADIUS_MAX)
	end, EBONY_SPACING, "Ebony")
end

-- ===== 실행 =====
local recording = ChangeHistoryService:TryBeginRecording("TreeAxeBuilder")
local ok, err = pcall(function()
	if BUILD_TEMPLATES then
		buildTreeTemplates()
		buildAxeTemplates()
	end
	if BUILD_ICONS then
		buildIcons()
	end
	if PLACE_SPAWNS then
		placeSpawns()
	end
end)
if recording then
	ChangeHistoryService:FinishRecording(recording, if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel)
end
if not ok then
	warn(`[TreeAxeBuilder] 실패: {err}`)
else
	print("[TreeAxeBuilder] 끝! 플레이 테스트로 확인하세요.")
end
