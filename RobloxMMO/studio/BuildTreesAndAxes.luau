--!nocheck
-- Studio 제작 스크립트. Rojo가 ServerStorage/StudioTools/BuildTreesAndAxes(ModuleScript)로 넣어 준다.
-- 게임 중에는 아무도 require하지 않으므로 실행되지 않는다. 편집 상태에서 명령 모음에 아래 한 줄을 넣고 Enter:
--   require(game.ServerStorage.StudioTools.BuildTreesAndAxes:Clone())
-- (:Clone()을 붙여야 두 번째부터도 다시 실행된다.) 다시 실행하면 전에 만든 것을 지우고 새로 만든다.
-- 서버(Main.server)가 게임을 시작할 때마다 실행한다 (그때 만든 건 저장되지 않는다).
--
-- 만드는 것
--   1. 도끼 Tool 4종  → ServerStorage/Templates/Pickaxes/{StoneAxe, CopperAxe, IronAxe, DiamondAxe}
--      같은 티어 곡괭이 Tool을 복제해 쥐는 각도(Grip)는 그대로 쓰고, 곡괭이 모양은 숨긴 뒤 곡괭이 머리 방향에 맞춰
--      단계마다 다른 도끼를 부품으로 짓는다: 돌 한날 손도끼 / 구리 바이킹 수염 도끼 / 철 양날 전투도끼 / 다이아 대형 양날 도끼
--   2. 나무 템플릿 5종 → ServerStorage/Templates/Ores/{Pine, Oak, Birch, Maple, Ebony}/
--      맵에 원래 있는 나무(이름에 "Tree")를 본떠 종류별로 잎·줄기 색만 바꾼다. 맵 나무가 없으면 부품으로 만든다.
--      기준점(Pivot)은 줄기 밑동 가운데, 잰 줄기 반지름은 속성 HitRadius (잔상 고리가 줄기에 딱 맞게).
--   3. 아이콘           → ReplicatedStorage/ItemIcons/{통나무 5종, 도끼 4종}
--   4. 스폰 자리        → Workspace/OreSpawns (속성 OreType)
--      맵 나무가 서 있던 자리를 그대로 쓴다 (원본 나무는 지운다). 맵 나무가 적으면 빈 땅에 더 심는다.
--      소나무·참나무·자작나무는 곳곳, 단풍나무는 근처에서 가장 높은 곳에 모아서,
--      흑단나무는 마을에서 가장 먼 후보 자리들(속성 RandomPool = "Ebony", 그중 Config.RandomPools.Ebony.Active개만 선다)
--
-- 스폰 자리는 Workspace/OreSpawns에서 GeneratedBy = "BuildTreesAndAxes" 파트를 옮기거나 지워서 다듬는다.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local OreDefs = require(ReplicatedStorage.Shared.OreDefs)
local Config = require(ReplicatedStorage.Shared.Config)

---------------------------------------------------------------- 설정
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

-- 게임 실행 중(서버)에는 되돌리기 기록을 쓸 수 없으므로 실패해도 넘어간다
local okRecording, recording = pcall(ChangeHistoryService.TryBeginRecording, ChangeHistoryService, "BuildTreesAndAxes")
if not okRecording then
	recording = nil
end

local templates = folder(ServerStorage, "Templates")
local pickaxeFolder = folder(templates, "Pickaxes")
local oreFolder = folder(templates, "Ores")
local iconFolder = folder(ReplicatedStorage, "ItemIcons")

---------------------------------------------------------------- 1. 도끼
local AXE_EDGE_SIGN = 1 -- 한날 도끼의 날이 뒤를 보면 -1로 (플레이 테스트로 맞춘다)

-- 도끼 4종 설계. 단위는 스터드, 머리 좌표계: x = 날 방향(앞), y = 자루 방향(위), 원점 = 머리 가운데
-- Scale: 머리 크기 배수, Reach: 자루 길이 배수(곡괭이 기준), Shaft: 자루 굵기
local METAL = Enum.Material.Metal
local AXES = {
	{
		Id = "StoneAxe", From = "StonePickaxe", Scale = 1.0, Reach = 1.0, Shaft = 0.26,
		Head = Color3.fromRGB(120, 118, 115), Edge = Color3.fromRGB(200, 198, 192), Material = Enum.Material.Slate,
		ShaftColor = Color3.fromRGB(150, 105, 65), ShaftMaterial = Enum.Material.Wood,
	},
	{
		Id = "CopperAxe", From = "CopperPickaxe", Scale = 1.2, Reach = 1.08, Shaft = 0.28,
		Head = Color3.fromRGB(196, 112, 58), Edge = Color3.fromRGB(245, 185, 125), Material = METAL,
		ShaftColor = Color3.fromRGB(80, 55, 40), ShaftMaterial = Enum.Material.Wood,
		Trail = Color3.fromRGB(255, 150, 70), TrailLife = 0.16,
	},
	{
		Id = "IronAxe", From = "IronPickaxe", Scale = 1.35, Reach = 1.15, Shaft = 0.3,
		Head = Color3.fromRGB(150, 152, 158), Edge = Color3.fromRGB(235, 238, 245), Material = METAL,
		ShaftColor = Color3.fromRGB(70, 72, 78), ShaftMaterial = METAL, Gold = Color3.fromRGB(215, 170, 70),
		Trail = Color3.fromRGB(230, 235, 255), TrailLife = 0.2,
	},
	{
		Id = "DiamondAxe", From = "SteelPickaxe", Scale = 1.6, Reach = 1.25, Shaft = 0.34,
		Head = Color3.fromRGB(95, 205, 245), Edge = Color3.fromRGB(215, 250, 255), Material = Enum.Material.Glass,
		ShaftColor = Color3.fromRGB(35, 30, 45), ShaftMaterial = METAL, Gold = Color3.fromRGB(230, 185, 80),
		Trail = Color3.fromRGB(110, 235, 255), TrailLife = 0.28, Glow = true,
	},
}

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

-- 곡괭이 Tool에서 쥐는 점·자루 방향·머리 가운데·머리 방향을 읽고, 곡괭이 부품은 전부 투명하게 한다
-- (쥐는 각도는 곡괭이와 같아야 하므로 Tool과 Handle·Grip은 그대로 쓴다)
local function prepareFromPickaxe(source: Tool)
	local tool = source:Clone()
	local handle = tool.Handle :: BasePart
	local gripWorld = handle.CFrame:PointToWorldSpace(tool.Grip.Position) -- 손이 쥐는 점

	-- 곡괭이 머리 = 쥐는 점에서 먼 쪽 부품 무리 (가장 먼 거리의 75% 넘게 떨어진 부품, 부피 가중 평균이 머리 가운데)
	local farthest = 0
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			farthest = math.max(farthest, (d.Position - gripWorld).Magnitude)
		end
	end
	local weighted, totalVolume = Vector3.zero, 0
	local headPart: BasePart = handle
	local biggest = -1
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") and (d.Position - gripWorld).Magnitude >= farthest * 0.75 then
			local volume = d.Size.X * d.Size.Y * d.Size.Z
			weighted += d.Position * volume
			totalVolume += volume
			if volume > biggest then
				headPart, biggest = d, volume
			end
		end
	end
	local center = if totalVolume > 0 then weighted / totalVolume else headPart.Position
	local shaft = (center - gripWorld).Unit

	-- 머리 방향 = 머리 부품의 축 중 자루와 수직이면서 가장 긴 축 (곡괭이 끝이 뻗은 방향)
	local best, bestSize = nil, -1
	for _, pair in {
		{ headPart.CFrame.RightVector, headPart.Size.X },
		{ headPart.CFrame.UpVector, headPart.Size.Y },
		{ headPart.CFrame.LookVector, headPart.Size.Z },
	} do
		if math.abs(pair[1]:Dot(shaft)) < 0.7 and pair[2] > bestSize then
			best, bestSize = pair[1], pair[2]
		end
	end
	local axis = (best or shaft:Cross(Vector3.yAxis)) :: Vector3
	local edge = (axis - shaft * axis:Dot(shaft)).Unit

	-- 곡괭이 모양은 숨긴다 (Handle은 Tool에 꼭 있어야 해서 지우지 않는다)
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 1
			d.CanCollide = false
		elseif d:IsA("Decal") or d:IsA("Texture") or d:IsA("Trail") or d:IsA("ParticleEmitter") or d:IsA("Light") then
			d:Destroy()
		end
	end
	return tool, gripWorld, center, shaft, edge
end

-- 세 점으로 삼각형 판을 만든다 (쐐기 두 개). 점은 월드 좌표, thickness는 판 두께
local function triangle(parent: Instance, a: Vector3, b: Vector3, c: Vector3, thickness: number, color: Color3, material: Enum.Material, weldTo: BasePart)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	if ac:Cross(ab).Magnitude < 1e-4 then
		return -- 한 줄로 늘어선 점
	end
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	for _, w in {
		{ Size = Vector3.new(thickness, height, math.abs(ab:Dot(back))), CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back) },
		{ Size = Vector3.new(thickness, height, math.abs(ac:Dot(back))), CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back) },
	} do
		if w.Size.Y > 0.01 and w.Size.Z > 0.01 then
			local wedge = part({
				ClassName = "WedgePart", Name = "Blade", Size = w.Size, CFrame = w.CFrame, Color = color, Material = material,
				Anchored = false, CanCollide = false, CanQuery = false, CanTouch = false, Massless = true,
			}, parent)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = weldTo
			weld.Part1 = wedge
			weld.Parent = wedge
		end
	end
end

-- 도끼 하나 만들기
local function buildAxe(spec): Tool
	local source = pickaxeFolder:FindFirstChild(spec.From)
	local tool, gripWorld, center, shaft, edge
	if source and source:IsA("Tool") and source:FindFirstChild("Handle") then
		tool, gripWorld, center, shaft, edge = prepareFromPickaxe(source)
	else
		tool = fallbackTool()
		local h = tool.Handle :: BasePart
		gripWorld = h.CFrame:PointToWorldSpace(tool.Grip.Position)
		center = h.CFrame:PointToWorldSpace(Vector3.new(0, h.Size.Y / 2 - 0.3, 0))
		shaft = h.CFrame.UpVector
		edge = h.CFrame.LookVector
	end
	tool.Name = spec.Id
	tool:SetAttribute("PickaxeId", nil)
	tool:SetAttribute("GeneratedBy", GENERATED)
	local handle = tool.Handle :: BasePart

	-- 자루를 곡괭이보다 Reach배 길게: 머리 가운데를 자루 방향으로 민다
	local reach = (center - gripWorld).Magnitude * spec.Reach
	center = gripWorld + shaft * reach
	local s = spec.Scale
	local frame = CFrame.fromMatrix(center, edge * AXE_EDGE_SIGN, shaft) -- x 날, y 자루, z 두께

	-- 머리 좌표(x, y)를 월드 좌표로
	local function at(x: number, y: number, z: number?): Vector3
		return frame:PointToWorldSpace(Vector3.new(x * s, y * s, (z or 0) * s))
	end
	-- 볼록 다각형 판 (점들은 머리 좌표, 둘레 순서대로)
	local function plate(points: { Vector2 }, thickness: number, color: Color3, material: Enum.Material, z: number?)
		local world = {}
		for _, p in points do
			table.insert(world, at(p.X, p.Y, z))
		end
		for i = 2, #world - 1 do
			triangle(tool, world[1], world[i], world[i + 1], thickness * s, color, material, handle)
		end
	end
	-- 날 끝 하이라이트: 선분마다 안쪽으로 inset만큼 들어간 띠
	local function edgeStrip(points: { Vector2 }, inset: number, thickness: number)
		for i = 1, #points - 1 do
			local p, q = points[i], points[i + 1]
			local dir = (q - p).Unit
			local normal = Vector2.new(-dir.Y, dir.X) -- 안쪽(원점 쪽)으로
			if normal:Dot(-(p + q) / 2) < 0 then
				normal = -normal
			end
			plate({ p, q, q + normal * inset, p + normal * inset }, thickness, spec.Edge, if spec.Glow then Enum.Material.Neon else spec.Material)
		end
	end
	-- 머리 좌표의 블록·원통 부품
	local function block(name: string, x: number, y: number, size: Vector3, color: Color3, material: Enum.Material, shape: Enum.PartType?, rotation: CFrame?)
		local p = part({
			Name = name, Shape = shape or Enum.PartType.Block, Size = size * s, Color = color, Material = material,
			CFrame = (frame + (at(x, y) - frame.Position)) * (rotation or CFrame.new()),
			Anchored = false, CanCollide = false, CanQuery = false, CanTouch = false, Massless = true,
		}, tool)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = p
		weld.Parent = p
		return p
	end
	-- 자루를 따라 놓는 원통 (from~to는 쥐는 점 기준 자루 방향 거리, 스터드)
	local SHAFT_ROT = CFrame.Angles(0, 0, math.rad(90)) -- 원통 X축을 자루 방향(y)으로
	local function shaftPiece(name: string, from: number, to: number, diameter: number, color: Color3, material: Enum.Material)
		local mid = gripWorld + shaft * ((from + to) / 2)
		local p = part({
			Name = name, Shape = Enum.PartType.Cylinder, Size = Vector3.new(to - from, diameter, diameter), Color = color, Material = material,
			CFrame = CFrame.fromMatrix(mid, edge, shaft) * SHAFT_ROT,
			Anchored = false, CanCollide = false, CanQuery = false, CanTouch = false, Massless = true,
		}, tool)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = p
		weld.Parent = p
		return p
	end

	local V = Vector2.new
	local d = spec.Shaft
	local top = reach + 0.25 * s -- 자루 윗끝
	local trailTop: Vector3, trailBottom: Vector3

	if spec.Id == "StoneAxe" then
		-- 한날 손도끼: 나무 자루 + 빨간 끈 손잡이, 사다리꼴 날, 뒤쪽 뭉툭한 머리
		shaftPiece("Shaft", -0.9, top, d, spec.ShaftColor, spec.ShaftMaterial)
		for i = 0, 4 do
			shaftPiece("Wrap", -0.6 + i * 0.28, -0.6 + i * 0.28 + 0.14, d + 0.07, Color3.fromRGB(190, 40, 45), Enum.Material.Fabric)
		end
		block("Socket", 0, 0.05, Vector3.new(0.55, 0.75, 0.42), spec.Head:Lerp(Color3.new(0, 0, 0), 0.3), spec.Material)
		block("Poll", -0.42, 0.05, Vector3.new(0.3, 0.5, 0.38), spec.Head:Lerp(Color3.new(0, 0, 0), 0.2), spec.Material)
		local blade = { V(0.25, 0.32), V(1.2, 0.5), V(1.32, -0.6), V(0.25, -0.22) }
		plate(blade, 0.16, spec.Head, spec.Material)
		edgeStrip({ V(1.2, 0.5), V(1.32, -0.6) }, 0.12, 0.18)
		trailTop, trailBottom = at(1.2, 0.5), at(1.32, -0.6)
	elseif spec.Id == "CopperAxe" then
		-- 바이킹 수염 도끼: 아래로 길게 늘어진 날, 새김 무늬, 가죽 감은 자루
		shaftPiece("Shaft", -1.0, top, d, spec.ShaftColor, spec.ShaftMaterial)
		for i = 0, 6 do
			shaftPiece("Leather", -0.75 + i * 0.22, -0.75 + i * 0.22 + 0.16, d + 0.06, Color3.fromRGB(110, 70, 45), Enum.Material.Leather)
		end
		shaftPiece("Cap", top - 0.05, top + 0.15, d + 0.12, spec.Edge, METAL)
		block("Socket", 0, 0, Vector3.new(0.6, 0.85, 0.46), spec.Head:Lerp(Color3.new(0, 0, 0), 0.25), spec.Material)
		plate({ V(-0.28, 0.22), V(-0.65, 0), V(-0.28, -0.22) }, 0.3, spec.Head:Lerp(Color3.new(0, 0, 0), 0.15), spec.Material) -- 뒤쪽 짧은 뿔
		plate({ V(0.28, 0.35), V(1.3, 0.78), V(1.56, 0.2), V(1.6, -0.4), V(0.28, -0.25) }, 0.15, spec.Head, spec.Material)
		plate({ V(0.28, -0.25), V(1.6, -0.4), V(1.35, -1.1), V(0.75, -0.62) }, 0.15, spec.Head, spec.Material)
		edgeStrip({ V(1.3, 0.78), V(1.56, 0.2), V(1.6, -0.4), V(1.35, -1.1) }, 0.13, 0.17)
		-- 새김 무늬: 날 위의 가는 빛나는 선
		for _, line in { { V(0.5, 0.2), V(1.1, 0.4) }, { V(0.55, -0.1), V(1.2, -0.25) }, { V(0.85, -0.45), V(1.2, -0.85) } } do
			local p, q = line[1], line[2]
			local n = V(-(q - p).Unit.Y, (q - p).Unit.X) * 0.04
			plate({ p - n, q - n, q + n, p + n }, 0.19, Color3.fromRGB(255, 170, 80), Enum.Material.Neon)
		end
		trailTop, trailBottom = at(1.3, 0.78), at(1.35, -1.1)
	elseif spec.Id == "IronAxe" then
		-- 양날 전투도끼: 넓은 날개 두 장, 위에 창끝, 금 장식, 쇠 자루와 고리
		shaftPiece("Shaft", -1.1, top, d, spec.ShaftColor, spec.ShaftMaterial)
		for _, ring in { -0.95, -0.2, reach - 0.65 * s } do
			shaftPiece("Ring", ring, ring + 0.12, d + 0.12, spec.Gold, METAL)
		end
		shaftPiece("Pommel", -1.3, -1.1, d + 0.15, spec.Gold, METAL)
		block("Socket", 0, 0, Vector3.new(0.5, 1.0, 0.5), spec.ShaftColor, METAL)
		for _, side in { 1, -1 } do
			local wing = { V(0.28, 0.3), V(1.05, 0.95), V(1.45, 0.05), V(1.05, -0.95), V(0.28, -0.3) }
			local edgeLine = { V(1.05, 0.95), V(1.45, 0.05), V(1.05, -0.95) }
			for i, p in wing do
				wing[i] = V(p.X * side, p.Y)
			end
			for i, p in edgeLine do
				edgeLine[i] = V(p.X * side, p.Y)
			end
			plate(wing, 0.15, spec.Head, spec.Material)
			edgeStrip(edgeLine, 0.13, 0.17)
			-- 금색 숫양 뿔 장식
			block("Horn", 0.33 * side, 0.12, Vector3.new(0.28, 0.28, 0.34), spec.Gold, METAL, Enum.PartType.Ball)
			block("Horn", 0.42 * side, -0.12, Vector3.new(0.2, 0.2, 0.3), spec.Gold, METAL, Enum.PartType.Ball)
		end
		plate({ V(0, 0.45), V(0.17, 0.95), V(0, 1.55), V(-0.17, 0.95) }, 0.14, spec.Edge, METAL) -- 창끝
		block("Collar", 0, 0.5, Vector3.new(0.42, 0.14, 0.42), spec.Gold, METAL)
		block("Collar", 0, -0.5, Vector3.new(0.42, 0.14, 0.42), spec.Gold, METAL)
		trailTop, trailBottom = at(1.05, 0.95), at(1.05, -0.95)
	else
		-- 다이아몬드 대형 양날 도끼: 계단식 날개, 가운데 빛나는 마름모, 금 고리 감은 검은 자루
		shaftPiece("Shaft", -1.2, top, d, spec.ShaftColor, spec.ShaftMaterial)
		for i = 0, 7 do
			local y = -1.0 + i * 0.38
			if y < reach - 0.9 * s then
				shaftPiece("GoldBand", y, y + 0.08, d + 0.06, spec.Gold, METAL)
			end
		end
		shaftPiece("Pommel", -1.45, -1.2, d + 0.2, spec.Head, Enum.Material.Neon)
		for _, side in { 1, -1 } do
			local inner = { V(0.32, 0.5), V(1.0, 0.75), V(1.0, -0.75), V(0.32, -0.5) }
			local wing = { V(1.0, 0.75), V(1.6, 1.2), V(1.75, 0.2), V(1.75, -0.2), V(1.6, -1.2), V(1.0, -0.75) }
			local edgeLine = { V(1.6, 1.2), V(1.75, 0.2), V(1.75, -0.2), V(1.6, -1.2) }
			for _, list in { inner, wing, edgeLine } do
				for i, p in list do
					list[i] = V(p.X * side, p.Y)
				end
			end
			plate(inner, 0.2, spec.Head:Lerp(Color3.new(0, 0, 0), 0.2), spec.Material)
			plate(wing, 0.16, spec.Head, spec.Material)
			edgeStrip(edgeLine, 0.15, 0.2)
		end
		plate({ V(0, 0.75), V(0.48, 0), V(0, -0.75), V(-0.48, 0) }, 0.42, spec.Gold, METAL) -- 가운데 마름모 받침
		plate({ V(0, 0.5), V(0.32, 0), V(0, -0.5), V(-0.32, 0) }, 0.5, spec.Edge, Enum.Material.Neon) -- 빛나는 마름모
		trailTop, trailBottom = at(1.6, 1.2), at(1.6, -1.2)
	end

	-- 휘두를 때 날 끝 궤적 (SwingAnimation이 휘두르는 동안만 켠다). 좋은 도끼일수록 길고 밝다
	if spec.Trail then
		local a0 = Instance.new("Attachment")
		a0.Name = "TrailTop"
		a0.Parent = handle
		a0.WorldPosition = trailTop
		local a1 = Instance.new("Attachment")
		a1.Name = "TrailBottom"
		a1.Parent = handle
		a1.WorldPosition = trailBottom
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(spec.Trail)
		trail.Transparency = NumberSequence.new(0.2, 1)
		trail.Lifetime = spec.TrailLife
		trail.LightEmission = if spec.Glow then 1 else 0.6
		trail.Enabled = false
		trail.Parent = handle
	end
	-- 다이아몬드: 은은한 빛과 반짝이
	if spec.Glow then
		local glow = Instance.new("Attachment")
		glow.Name = "Glow"
		glow.Parent = handle
		glow.WorldPosition = center
		local light = Instance.new("PointLight")
		light.Color = spec.Head
		light.Range = 8
		light.Brightness = 1.5
		light.Parent = glow
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Color = ColorSequence.new(spec.Edge)
		sparkles.LightEmission = 1
		sparkles.Size = NumberSequence.new(0.35, 0)
		sparkles.Lifetime = NumberRange.new(0.4, 0.9)
		sparkles.Rate = 6
		sparkles.Speed = NumberRange.new(0.5, 1.2)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Parent = glow
	end
	return tool
end

-- 도구를 아이콘용 모델로 (부품만 복사, 고정)
local function iconFromTool(tool: Tool, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	for _, d in tool:GetChildren() do
		if d:IsA("BasePart") and d.Transparency < 1 then -- 숨긴 곡괭이 부품은 아이콘에서 뺀다
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
print("[BuildTreesAndAxes] (버전 9, 도끼 4종 디자인) 도끼 4종 완료")

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
	local height = 18 * scale
	trunk(model, origin, def.HitRadius, height, def.Color, Enum.Material.Wood)
	local layers = 5
	for i = 1, layers do
		local t = (i - 1) / (layers - 1)
		local width = (10 - t * 6.5) * scale
		local y = height * 0.35 + t * height * 0.62
		part({
			Name = "Leaves",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.6 * scale, width, width),
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
	local height = 12 * scale
	trunk(model, origin, def.HitRadius, height, def.Color, Enum.Material.Wood)
	broadleaf(model, origin, def.HitRadius, height, 12 * scale, def.LeafColor, 5)
end

-- 자작나무: 가늘고 높은 흰 줄기에 검은 줄무늬 + 작은 연두 잎
TREE_BUILDERS.Birch = function(model, origin, def, scale)
	local height = 17 * scale
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
	broadleaf(model, origin, def.HitRadius, height, 8 * scale, def.LeafColor, 5)
end

-- 단풍나무: 붉은 잎
TREE_BUILDERS.Maple = function(model, origin, def, scale)
	local height = 13 * scale
	trunk(model, origin, def.HitRadius, height, def.Color, Enum.Material.Wood)
	broadleaf(model, origin, def.HitRadius, height, 11 * scale, def.LeafColor, 6)
end

-- 흑단나무: 검보라 줄기와 잎, 은은한 빛과 반짝이 (희귀)
TREE_BUILDERS.Ebony = function(model, origin, def, scale)
	local height = 15 * scale
	trunk(model, origin, def.HitRadius, height, def.Color, Enum.Material.Wood)
	broadleaf(model, origin, def.HitRadius, height, 11 * scale, def.LeafColor, 6)
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
local HIT_HEIGHT = 2.5 -- OreDefs.HitHeight와 같게 (줄기 굵기를 재는 높이)

-- 맵에 원래 있던 나무 찾기 (이름에 "tree"가 들어간 모델·부품). 광산·바위·NPC 쪽은 뺀다
local function isTreeName(name: string): boolean
	local lower = string.lower(name)
	-- "Street"(가로등·길)은 나무가 아니다
	return string.find(lower, "tree", 1, true) ~= nil and string.find(lower, "street", 1, true) == nil
end
local function insideTreeModel(instance: Instance): boolean
	local parent = instance.Parent
	while parent and parent ~= workspace do
		if parent:IsA("Model") and isTreeName(parent.Name) then
			return true
		end
		parent = parent.Parent
	end
	return false
end
local excludedRoots = { workspace:FindFirstChild("Ores"), workspace:FindFirstChild("OreSpawns"), workspace:FindFirstChild("NPCs"), workspace:FindFirstChild("ClientEffects") }
local function isExcluded(instance: Instance): boolean
	for _, root in excludedRoots do
		if root and instance:IsDescendantOf(root) then
			return true
		end
	end
	return false
end

-- 모델(또는 부품)의 부품 목록
local function partsOf(instance: Instance): { BasePart }
	local list = {}
	if instance:IsA("BasePart") then
		table.insert(list, instance)
	end
	for _, d in instance:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

-- 줄기 밑동 위치: 가장 아래에 닿은 부품(줄기)의 가운데 x,z + 나무 전체의 가장 낮은 y
local function treeBase(parts: { BasePart }): Vector3
	local minY, lowest, lowestY = math.huge, nil, math.huge
	for _, p in parts do
		local extentY = math.abs(p.CFrame.RightVector.Y) * p.Size.X / 2 + math.abs(p.CFrame.UpVector.Y) * p.Size.Y / 2 + math.abs(p.CFrame.LookVector.Y) * p.Size.Z / 2
		local bottom = p.Position.Y - extentY
		minY = math.min(minY, bottom)
		if bottom < lowestY then
			lowest, lowestY = p, bottom
		end
	end
	return Vector3.new(lowest.Position.X, minY, lowest.Position.Z)
end

-- 줄기 반지름: 타격 높이에서 네 방향으로 줄기를 향해 쏴서 잰다
local function measureRadius(parts: { BasePart }, base: Vector3): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = parts
	local center = base + Vector3.new(0, HIT_HEIGHT, 0)
	local total, count = 0, 0
	for _, dir in { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis } do
		local result = workspace:Raycast(center + dir * 12, -dir * 12, params)
		if result then
			total += (result.Position - center).Magnitude
			count += 1
		end
	end
	return if count > 0 then math.clamp(total / count, 0.4, 3) else 1
end

local mapTrees = {} -- { Instance = 원본, Base = 밑동, Radius = 줄기 반지름 }
for _, d in workspace:GetDescendants() do
	if (d:IsA("Model") or d:IsA("BasePart")) and isTreeName(d.Name) and not insideTreeModel(d) and not isExcluded(d) then
		local parts = partsOf(d)
		if #parts > 0 and d.Archivable then
			local base = treeBase(parts)
			table.insert(mapTrees, { Instance = d, Base = base, Radius = measureRadius(parts, base) })
		end
	end
end

-- 나무 종류별 색: 잎은 LeafColor로, 줄기는 자작나무(흰색)·흑단나무(검보라)만 바꾼다
local RECOLOR_TRUNK = { Birch = true, Ebony = true }
local RECOLOR_LEAF = { Pine = 0.5, Oak = 0, Birch = 0.8, Maple = 1, Ebony = 1 } -- 원래 잎 색에서 LeafColor로 바꾸는 정도
local TYPE_SCALE = { Pine = 1.1, Oak = 1, Birch = 1, Maple = 1.05, Ebony = 1.15 }

local function isLeaf(p: BasePart): boolean
	local c = p.Color
	return p.Material == Enum.Material.Grass or p.Material == Enum.Material.LeafyGrass or (c.G > c.R * 1.05 and c.G > c.B)
end

-- 맵 나무를 그 종류의 템플릿으로 만든다 (복제 → 고정 → 색 → 기준점 = 밑동 → 크기)
local function templateFromMapTree(entry, id: string): Model
	local def = OreDefs[id]
	local source = entry.Instance:Clone()
	local model: Model
	if source:IsA("Model") then
		model = source
	else
		model = Instance.new("Model")
		source.Parent = model
	end
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") then
			d:Destroy()
		end
	end
	for _, p in partsOf(model) do
		p.Anchored = true
		local leaf = isLeaf(p)
		local amount = if leaf then RECOLOR_LEAF[id] else (if RECOLOR_TRUNK[id] then 1 else 0)
		if amount > 0 then
			local target = if leaf then def.LeafColor else def.Color
			p.Color = p.Color:Lerp(target, amount)
			-- 텍스처가 덮여 있으면 색이 안 보이므로 뺀다
			if amount >= 0.8 then
				for _, c in p:GetChildren() do
					if c:IsA("SurfaceAppearance") then
						c:Destroy()
					end
				end
				if p:IsA("MeshPart") then
					pcall(function()
						p.TextureID = ""
					end)
				end
			end
		end
		if leaf then
			p.CanCollide = false
		end
	end
	model.PrimaryPart = nil -- 기준점이 부품 방향을 따라가지 않게
	model.WorldPivot = CFrame.new(entry.Base)
	model:ScaleTo(TYPE_SCALE[id])
	model:SetAttribute("HitRadius", entry.Radius * TYPE_SCALE[id]) -- 잔상 고리·타격 위치용 줄기 반지름
	model:PivotTo(CFrame.new())
	if id == "Ebony" then
		local glow = Instance.new("Attachment")
		glow.Position = Vector3.new(0, model:GetExtentsSize().Y * 0.7, 0)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(190, 120, 255)
		light.Range = 16
		light.Brightness = 1.2
		light.Parent = glow
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Color = ColorSequence.new(Color3.fromRGB(210, 160, 255))
		sparkles.LightEmission = 1
		sparkles.Size = NumberSequence.new(0.5, 0)
		sparkles.Lifetime = NumberRange.new(1.5, 2.5)
		sparkles.Speed = NumberRange.new(0.3, 0.8)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Rate = 4
		sparkles.Parent = glow
		local holder = partsOf(model)[1]
		glow.Parent = holder
		glow.WorldPosition = model:GetPivot().Position + Vector3.new(0, model:GetExtentsSize().Y * 0.7, 0)
	end
	return model
end

-- 템플릿으로 쓸 맵 나무 (이름이 다른 것 우선, 최대 4개)
local sourceTrees = {}
local seenNames = {}
for _, entry in mapTrees do
	if #sourceTrees < 4 and not seenNames[entry.Instance.Name] then
		seenNames[entry.Instance.Name] = true
		table.insert(sourceTrees, entry)
	end
end
for _, entry in mapTrees do
	if #sourceTrees >= 2 then
		break
	end
	if not table.find(sourceTrees, entry) then
		table.insert(sourceTrees, entry)
	end
end

for _, id in TREE_IDS do
	local def = OreDefs[id]
	local old = oreFolder:FindFirstChild(def.TemplateName)
	if old then
		old:Destroy()
	end
	local treeFolder = folder(oreFolder, def.TemplateName)
	if #sourceTrees > 0 then
		for index, entry in sourceTrees do
			local model = templateFromMapTree(entry, id)
			model.Name = `{id}{index}`
			model.Parent = treeFolder
		end
	else
		-- 맵에 나무가 없으면 부품으로 만든 나무를 쓴다
		for index, scale in VARIANT_SCALES do
			local model = Instance.new("Model")
			model.Name = `{id}{index}`
			local origin = CFrame.new(0, 0, 0)
			TREE_BUILDERS[id](model, origin, def, scale)
			model.PrimaryPart = nil -- 기준점 = 줄기 밑동 가운데, 똑바로 선 방향
			model.WorldPivot = origin
			model:SetAttribute("HitRadius", def.HitRadius)
			model.Parent = treeFolder
		end
	end
end
print(`[BuildTreesAndAxes] 맵 나무 {#mapTrees}그루 발견. 나무 5종 템플릿 완료 ({if #sourceTrees > 0 then "맵 나무 모양" else "부품으로 만든 모양"})`)

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

-- 후보 땅 자리를 고루 모은다. 맵 나무가 서 있던 자리가 먼저다 (원본 나무는 지우고 그 자리에 캘 수 있는 나무가 선다)
local candidates = {}
for _, entry in mapTrees do
	table.insert(candidates, entry.Base)
	entry.Instance:Destroy()
end
local MAP_TREES_ENOUGH = 20 -- 맵 나무가 이만큼 있으면 빈 땅에 더 심지 않는다
for _ = 1, if #mapTrees >= MAP_TREES_ENOUGH then 0 else 1500 do
	local angle = random:NextNumber(0, math.pi * 2)
	local distance = math.sqrt(random:NextNumber(SCATTER_MIN ^ 2, SCATTER_MAX ^ 2)) -- 넓이 기준 고르게
	local ground = groundAt(center.X + math.cos(angle) * distance, center.Z + math.sin(angle) * distance)
	if ground then
		table.insert(candidates, ground)
	end
end

local placed = {}
local minSpacing = if #mapTrees >= MAP_TREES_ENOUGH then 4 else MIN_SPACING -- 맵 나무는 원래 간격 그대로 둔다
local function farFromOthers(position: Vector3): boolean
	for _, other in placed do
		if (other - position).Magnitude < minSpacing then
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
local ebonySpacing = if #candidates > 0 then (candidates[1] - center).Magnitude * 0.4 else 0
local ebony = 0
for _, position in candidates do
	if ebony >= EBONY_CANDIDATES then
		break
	end
	local spread = true
	for _, other in placed do
		if (other - position).Magnitude < ebonySpacing then
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
if peak and #mapTrees >= MAP_TREES_ENOUGH then
	-- 맵 나무 자리 중 가장 높은 곳에서 가까운 순서로
	local near = {}
	for _, position in candidates do
		if farFromOthers(position) then
			table.insert(near, position)
		end
	end
	table.sort(near, function(a, b)
		return (a - peak).Magnitude < (b - peak).Magnitude
	end)
	for i = 1, math.min(MAPLE_COUNT, #near) do
		addSpawn(near[i], "Maple")
		maple += 1
	end
elseif peak then
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
local commonCounts = { Pine = 0, Oak = 0, Birch = 0 }
local cursor = 1
if #mapTrees >= MAP_TREES_ENOUGH then
	-- 맵 나무 자리는 남김없이 흔한 나무로 채운다 (비율은 COUNTS)
	local total = COUNTS.Pine + COUNTS.Oak + COUNTS.Birch
	for _, position in candidates do
		if farFromOthers(position) then
			local roll = random:NextNumber(0, total)
			local oreType = if roll < COUNTS.Pine then "Pine" elseif roll < COUNTS.Pine + COUNTS.Oak then "Oak" else "Birch"
			addSpawn(position, oreType)
			commonCounts[oreType] += 1
		end
	end
	cursor = #candidates + 1
end
for oreType, count in COUNTS do
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
	pcall(ChangeHistoryService.FinishRecording, ChangeHistoryService, recording, Enum.FinishRecordingOperation.Commit)
end
print("[BuildTreesAndAxes] 끝. Ctrl+Z로 한 번에 되돌릴 수 있어요.")

return true
