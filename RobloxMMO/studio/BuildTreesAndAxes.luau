--!nocheck
-- Studio 제작 스크립트. Rojo가 ServerStorage/StudioTools/BuildTreesAndAxes(ModuleScript)로 넣어 준다.
-- 게임 중에는 아무도 require하지 않으므로 실행되지 않는다. 편집 상태에서 명령 모음에 아래 한 줄을 넣고 Enter:
--   require(game.ServerStorage.StudioTools.BuildTreesAndAxes:Clone())
-- (:Clone()을 붙여야 두 번째부터도 다시 실행된다.) 다시 실행하면 전에 만든 것을 지우고 새로 만든다.
-- 서버(Main.server)가 게임을 시작할 때마다 실행한다 (그때 만든 건 저장되지 않는다).
--
-- 만드는 것
--   1. 도끼 Tool 6종  → ServerStorage/Templates/Pickaxes/{StoneAxe, CopperAxe, IronAxe, DiamondAxe, MithrilAxe, OrichalcumAxe}
--      같은 티어 곡괭이 Tool을 복제해 쥐는 각도(Grip)는 그대로 쓰고, 곡괭이 모양은 숨긴 뒤 곡괭이 머리 방향에 맞춰
--      단계마다 다른 도끼를 부품으로 짓는다: 돌 한날 손도끼 / 구리 바이킹 수염 도끼 / 철 양날 전투도끼 / 다이아 대형 양날 도끼
--      / 미스릴 초승달 도끼 / 오리하르콘 태양 도끼 (2026-10-09)
--   1-2. 5·6단계 곡괭이 → Templates/Pickaxes/{MithrilPickaxe, OrichalcumPickaxe}: 다이아몬드 곡괭이(SteelPickaxe) Tool을 복제해
--      머리·자루 색과 재질을 바꾸고 빛·반짝이를 붙인 뒤 조금 키운다 (+ 아이콘)
--   2. 나무 템플릿 5종 → ServerStorage/Templates/Ores/{Pine, Oak, Birch, Maple, Ebony}/
--      맵에 원래 있는 나무(이름에 "Tree")를 본떠 종류별로 잎·줄기 색만 바꾼다. 맵 나무가 없으면 부품으로 만든다.
--      기준점(Pivot)은 줄기 밑동 가운데, 잰 줄기 반지름은 속성 HitRadius (잔상 고리가 줄기에 딱 맞게).
--   3. 아이콘           → ReplicatedStorage/ItemIcons/{통나무 5종, 도끼 6종, 5·6단계 곡괭이}
--   4. 스폰 자리        → Workspace/OreSpawns (속성 OreType)
--      맵 나무가 서 있던 자리를 그대로 쓰고(원본 나무는 지운다, 속성 MapTreeSpot), 빈 풀밭에 더 심어 Config.WorldTiers.TreeDensity만큼 늘린다.
--      나무 종류는 마을 거리로 정한다 (Config.WorldTiers.Trees: 가까이 소나무·참나무, 조금 멀면 자작나무, 멀면 단풍나무. 띠끼리 겹쳐 서서히 바뀜)
--      흑단나무는 먼 곳 중 마을에서 가장 먼 후보 자리들(속성 RandomPool = "Ebony", 그중 Config.RandomPools.Ebony.Active개만 선다)
--      지상 돌이 마을 근처에 모자라면 Config.WorldTiers.Stone만큼 채운다
--      편집 상태에서 다시 실행하면 맵 나무는 이미 지워졌으므로, 전에 만든 MapTreeSpot 자리와 맵 나무 모양 템플릿(속성 FromMapTree)을 그대로 쓴다
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
local KEEP_AWAY = 22 -- NPC·광산 입구·마을 도착점에서 이만큼 떨어뜨린다 (스터드)
local GROUND_MATERIALS = { -- 나무를 심어도 되는 땅
	[Enum.Material.Grass] = true, [Enum.Material.LeafyGrass] = true, [Enum.Material.Ground] = true,
	[Enum.Material.Mud] = true, [Enum.Material.Sand] = false,
}
local GRASS_ONLY = { [Enum.Material.Grass] = true, [Enum.Material.LeafyGrass] = true } -- 새로 심는 자리는 먼저 풀밭만 (흙길 피하기)

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
-- Design: 모양 (Hatchet 한날 손도끼 / Bearded 바이킹 수염 / Great 계단식 대형 양날 / Battle 창끝 양날 전투도끼)
-- 철 = Great, 다이아 = Battle (2026-10-09 사용자 요청으로 서로 바꿈)
-- Scale: 머리 크기 배수, Reach: 자루 길이 배수(곡괭이 기준), Shaft: 자루 굵기
local METAL = Enum.Material.Metal
local AXES = {
	{
		Id = "StoneAxe", From = "StonePickaxe", Design = "Hatchet", Scale = 1.0, Reach = 1.0, Shaft = 0.26,
		Head = Color3.fromRGB(120, 118, 115), Edge = Color3.fromRGB(200, 198, 192), Material = Enum.Material.Slate,
		ShaftColor = Color3.fromRGB(150, 105, 65), ShaftMaterial = Enum.Material.Wood,
	},
	{
		Id = "CopperAxe", From = "CopperPickaxe", Design = "Bearded", Scale = 1.2, Reach = 1.08, Shaft = 0.28,
		Head = Color3.fromRGB(196, 112, 58), Edge = Color3.fromRGB(245, 185, 125), Material = METAL,
		ShaftColor = Color3.fromRGB(80, 55, 40), ShaftMaterial = Enum.Material.Wood,
		Trail = Color3.fromRGB(255, 150, 70), TrailLife = 0.16,
	},
	{
		Id = "IronAxe", From = "IronPickaxe", Design = "Great", Scale = 1.215, Reach = 1.035, Shaft = 0.27, -- 곡괭이보다 너무 커서 10% 줄임 (2026-10-09)
		Head = Color3.fromRGB(150, 152, 158), Edge = Color3.fromRGB(235, 238, 245), Material = METAL,
		ShaftColor = Color3.fromRGB(70, 72, 78), ShaftMaterial = METAL, Gold = Color3.fromRGB(215, 170, 70),
		Trail = Color3.fromRGB(230, 235, 255), TrailLife = 0.2,
	},
	{
		Id = "DiamondAxe", From = "SteelPickaxe", Design = "Battle", Scale = 1.6, Reach = 1.25, Shaft = 0.34,
		Head = Color3.fromRGB(95, 205, 245), Edge = Color3.fromRGB(215, 250, 255), Material = Enum.Material.Glass,
		ShaftColor = Color3.fromRGB(35, 30, 45), ShaftMaterial = METAL, Gold = Color3.fromRGB(230, 185, 80),
		Trail = Color3.fromRGB(110, 235, 255), TrailLife = 0.28, Glow = true,
	},
	-- 5단계 미스릴: 은빛 파랑, 가볍고 날렵한 초승달 날 하나 + 파랗게 빛나는 룬 (2026-10-09)
	{
		Id = "MithrilAxe", From = "SteelPickaxe", Design = "Crescent", Scale = 1.45, Reach = 1.2, Shaft = 0.26,
		Head = Color3.fromRGB(175, 205, 240), Edge = Color3.fromRGB(120, 195, 255), Material = METAL,
		ShaftColor = Color3.fromRGB(40, 50, 78), ShaftMaterial = METAL, Rune = Color3.fromRGB(90, 170, 255),
		Trail = Color3.fromRGB(120, 190, 255), TrailLife = 0.3, Glow = true,
	},
	-- 6단계 오리하르콘: 금빛, 묵직하고 화려한 두 겹 양날 + 햇살 가시 + 주황 보석 핵, 불티 (2026-10-09)
	{
		Id = "OrichalcumAxe", From = "SteelPickaxe", Design = "Sun", Scale = 1.7, Reach = 1.3, Shaft = 0.36,
		Head = Color3.fromRGB(240, 180, 55), Edge = Color3.fromRGB(255, 225, 140), Material = METAL,
		ShaftColor = Color3.fromRGB(70, 35, 25), ShaftMaterial = METAL, Gold = Color3.fromRGB(255, 215, 110), Ember = Color3.fromRGB(255, 130, 30),
		Trail = Color3.fromRGB(255, 185, 70), TrailLife = 0.32, Glow = true,
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

	if spec.Design == "Hatchet" then
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
	elseif spec.Design == "Bearded" then
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
	elseif spec.Design == "Battle" then
		-- Battle: 양날 전투도끼: 넓은 날개 두 장, 위에 창끝, 금 장식, 쇠 자루와 고리
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
	elseif spec.Design == "Crescent" then
		-- 미스릴 초승달 도끼: 가는 쇠 자루에 빛나는 룬 고리, 크게 휜 초승달 날 하나, 뒤 가시·위 가시
		shaftPiece("Shaft", -1.1, top, d, spec.ShaftColor, spec.ShaftMaterial)
		for _, y in { -0.75, -0.35, 0.05 } do
			shaftPiece("Rune", y, y + 0.06, d + 0.05, spec.Rune, Enum.Material.Neon)
		end
		shaftPiece("Pommel", -1.3, -1.1, d + 0.12, spec.Edge, Enum.Material.Neon)
		block("Socket", 0, 0, Vector3.new(0.5, 0.9, 0.44), spec.ShaftColor, METAL)
		-- 초승달 날: 바깥 호와 안쪽 호 사이를 작은 사각형으로 이어 붙인다 (볼록한 판만 만들 수 있어서)
		local outer, inner = {}, {}
		local steps = 6
		for i = 0, steps do
			local a = math.rad(-68 + 136 * i / steps)
			table.insert(outer, V(0.05 + 1.5 * math.cos(a), 1.5 * math.sin(a)))
			table.insert(inner, V(0.3 + 0.75 * math.cos(a), 1.05 * math.sin(a)))
		end
		for i = 1, steps do
			plate({ inner[i], outer[i], outer[i + 1], inner[i + 1] }, 0.14, spec.Head, spec.Material)
		end
		plate({ V(0.22, 0.3), V(1.0, 0.36), V(1.0, -0.36), V(0.22, -0.3) }, 0.18, spec.Head:Lerp(Color3.new(0, 0, 0), 0.2), spec.Material) -- 날과 자루를 잇는 목
		edgeStrip(outer, 0.12, 0.17)
		-- 날 위 빛나는 룬 (마름모 셋)
		for _, i in { 2, 4, 6 } do
			local mid = (inner[i] + outer[i]) / 2
			plate({ mid + V(0, 0.09), mid + V(0.06, 0), mid + V(0, -0.09), mid + V(-0.06, 0) }, 0.18, spec.Rune, Enum.Material.Neon)
		end
		plate({ V(-0.22, 0.2), V(-0.95, 0), V(-0.22, -0.2) }, 0.16, spec.Head, spec.Material) -- 뒤 가시
		plate({ V(-0.12, 0.45), V(0, 1.15), V(0.12, 0.45) }, 0.14, spec.Head, spec.Material) -- 위 가시
		trailTop, trailBottom = at(outer[steps + 1].X, outer[steps + 1].Y), at(outer[1].X, outer[1].Y)
	elseif spec.Design == "Sun" then
		-- 오리하르콘 태양 도끼: 금 고리 감은 굵은 자루, 두 겹 금빛 양날, 날 끝 햇살 가시, 가운데 주황 보석 핵, 창끝
		shaftPiece("Shaft", -1.25, top, d, spec.ShaftColor, spec.ShaftMaterial)
		for i = 0, 5 do
			local y = -1.05 + i * 0.4
			if y < reach - 0.95 * s then
				shaftPiece("GoldBand", y, y + 0.09, d + 0.07, spec.Gold, METAL)
			end
		end
		shaftPiece("Pommel", -1.5, -1.25, d + 0.22, spec.Ember, Enum.Material.Neon)
		for _, side in { 1, -1 } do
			local function flip(list: { Vector2 }): { Vector2 }
				for i, p in list do
					list[i] = V(p.X * side, p.Y)
				end
				return list
			end
			plate(flip({ V(0.3, 0.45), V(1.2, 1.3), V(1.8, 0.45), V(1.8, -0.45), V(1.2, -1.3), V(0.3, -0.45) }), 0.16, spec.Head, spec.Material)
			plate(flip({ V(0.3, 0.3), V(0.95, 0.75), V(1.3, 0), V(0.95, -0.75), V(0.3, -0.3) }), 0.26, spec.Head:Lerp(Color3.new(0, 0, 0), 0.25), spec.Material)
			edgeStrip(flip({ V(1.2, 1.3), V(1.8, 0.45), V(1.8, -0.45), V(1.2, -1.3) }), 0.14, 0.2)
			-- 날 끝 햇살 가시 (빛남)
			for _, y in { 0.75, 0, -0.75 } do
				local baseX = if y == 0 then 1.78 else 1.56
				plate(flip({ V(baseX, y + 0.13), V(baseX + 0.38, y), V(baseX, y - 0.13) }), 0.12, spec.Edge, Enum.Material.Neon)
			end
			block("WingGem", 0.8 * side, 0, Vector3.new(0.26, 0.26, 0.26), spec.Ember, Enum.Material.Neon, Enum.PartType.Ball)
		end
		block("Socket", 0, 0, Vector3.new(0.52, 1.05, 0.5), spec.ShaftColor, METAL)
		block("Core", 0, 0, Vector3.new(0.62, 0.62, 0.62), spec.Ember, Enum.Material.Neon, Enum.PartType.Ball)
		plate({ V(0, 0.5), V(0.24, 1.1), V(0, 1.95), V(-0.24, 1.1) }, 0.16, spec.Edge, METAL) -- 창끝
		block("SpearGem", 0, 1.1, Vector3.new(0.2, 0.2, 0.2), spec.Ember, Enum.Material.Neon, Enum.PartType.Ball)
		block("Collar", 0, 0.55, Vector3.new(0.46, 0.15, 0.46), spec.Gold, METAL)
		block("Collar", 0, -0.55, Vector3.new(0.46, 0.15, 0.46), spec.Gold, METAL)
		trailTop, trailBottom = at(1.2, 1.3), at(1.2, -1.3)
	else
		-- Great: 대형 양날 도끼: 계단식 날개, 가운데 빛나는 마름모, 금 고리 감은 검은 자루
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
		-- 오리하르콘: 위로 날아오르는 불티
		if spec.Ember then
			local embers = Instance.new("ParticleEmitter")
			embers.Name = "Embers"
			embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			embers.Color = ColorSequence.new(spec.Ember, spec.Edge)
			embers.LightEmission = 1
			embers.Size = NumberSequence.new(0.25, 0)
			embers.Lifetime = NumberRange.new(0.5, 1)
			embers.Rate = 10
			embers.Speed = NumberRange.new(0.5, 1.5)
			embers.SpreadAngle = Vector2.new(180, 180)
			embers.Acceleration = Vector3.new(0, 4, 0)
			embers.Parent = glow
		end
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
print(`[BuildTreesAndAxes] (버전 13) 도끼 {#AXES}종 완료`)

-- 곡괭이 크기 조정 (Studio에서 만든 곡괭이 Tool을 손잡이 기준으로 키운다). 도끼를 다 만든 뒤에 해야 도끼 크기에 영향이 없다
-- 이미 키운 Tool은 속성 ScaledBy로 표시해서 두 번 키우지 않는다
local PICKAXE_SCALES = { SteelPickaxe = 1.1 } -- 다이아몬드 곡괭이 10% 크게 (2026-10-09 사용자 요청)

local function scaleTool(tool: Tool, factor: number)
	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return
	end
	local origin = handle.CFrame
	-- 용접을 잠시 끄고 부품을 손잡이 기준으로 옮긴 뒤 다시 켠다 (켜질 때 새 위치로 다시 붙는다)
	local welds = {}
	for _, d in tool:GetDescendants() do
		if d:IsA("WeldConstraint") and d.Enabled then
			d.Enabled = false
			table.insert(welds, d)
		end
	end
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			local relative = origin:ToObjectSpace(d.CFrame)
			d.Size *= factor
			d.CFrame = origin * (relative - relative.Position + relative.Position * factor)
		elseif d:IsA("SpecialMesh") then
			d.Scale *= factor
			d.Offset *= factor
		elseif d:IsA("Attachment") then
			d.Position *= factor
		elseif d:IsA("JointInstance") then
			d.C0 = d.C0 - d.C0.Position + d.C0.Position * factor
			d.C1 = d.C1 - d.C1.Position + d.C1.Position * factor
		end
	end
	for _, weld in welds do
		weld.Enabled = true
	end
	tool.Grip = tool.Grip - tool.Grip.Position + tool.Grip.Position * factor
end

for id, factor in PICKAXE_SCALES do
	local tool = pickaxeFolder:FindFirstChild(id)
	if tool and tool:IsA("Tool") and tool:GetAttribute("ScaledBy") ~= factor then
		scaleTool(tool, factor / (tool:GetAttribute("ScaledBy") or 1))
		tool:SetAttribute("ScaledBy", factor)
		print(`[BuildTreesAndAxes] {id} 크기 x{factor}`)
	end
end

---------------------------------------------------------------- 1-2. 5·6단계 곡괭이 (2026-10-09)
-- Studio에서 만든 다이아몬드 곡괭이(SteelPickaxe)를 복제해 색·재질을 바꾼다 (모양은 같고 색·빛·크기가 다르다).
-- 머리 = 쥐는 점에서 먼 부품. 원래 Neon인 작은 부품(빛나는 장식)은 Edge 빛 색, 나머지 머리는 Head 금속, 자루는 Shaft
-- Scale: 다이아몬드 곡괭이(이미 PICKAXE_SCALES로 키운 것) 기준 배수
local HIGH_PICKAXES = {
	{
		Id = "MithrilPickaxe", From = "SteelPickaxe", Scale = 1.06,
		Head = Color3.fromRGB(175, 205, 240), Edge = Color3.fromRGB(90, 170, 255), Shaft = Color3.fromRGB(40, 50, 78),
		Trail = Color3.fromRGB(120, 190, 255), Light = Color3.fromRGB(110, 180, 255), Sparkle = Color3.fromRGB(170, 220, 255), SparkleRate = 6,
	},
	{
		Id = "OrichalcumPickaxe", From = "SteelPickaxe", Scale = 1.15,
		Head = Color3.fromRGB(240, 180, 55), Edge = Color3.fromRGB(255, 130, 30), Shaft = Color3.fromRGB(70, 35, 25),
		Trail = Color3.fromRGB(255, 185, 70), Light = Color3.fromRGB(255, 160, 60), Sparkle = Color3.fromRGB(255, 215, 120), SparkleRate = 12,
		Ember = Color3.fromRGB(255, 130, 30),
	},
}

-- 도구를 아이콘용 모델로 (모델 안에 묶인 부품까지 전부, 보이는 것만)
local function iconFromToolDeep(tool: Tool, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
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

local function buildHighPickaxe(spec): Tool?
	local source = pickaxeFolder:FindFirstChild(spec.From)
	if not (source and source:IsA("Tool") and source:FindFirstChild("Handle")) then
		warn(`[BuildTreesAndAxes] {spec.From} 곡괭이 템플릿이 없어 {spec.Id}를 못 만들었어요.`)
		return nil
	end
	local tool = source:Clone()
	tool.Name = spec.Id
	tool:SetAttribute("PickaxeId", nil)
	tool:SetAttribute("ScaledBy", nil)
	tool:SetAttribute("GeneratedBy", GENERATED)
	local handle = tool.Handle :: BasePart
	local gripWorld = handle.CFrame:PointToWorldSpace(tool.Grip.Position)

	-- 보이는 부품 중 쥐는 점에서 가장 먼 거리, 가장 큰 머리 부품 부피
	local parts: { BasePart } = {}
	local farthest = 0
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			table.insert(parts, d)
			farthest = math.max(farthest, (d.Position - gripWorld).Magnitude)
		end
	end
	local function volume(p: BasePart): number
		return p.Size.X * p.Size.Y * p.Size.Z
	end
	local biggestHead = 0
	for _, p in parts do
		if (p.Position - gripWorld).Magnitude >= farthest * 0.6 then
			biggestHead = math.max(biggestHead, volume(p))
		end
	end

	-- 색·재질 바꾸기
	local weighted, total = Vector3.zero, 0
	for _, p in parts do
		local isHead = (p.Position - gripWorld).Magnitude >= farthest * 0.6
		local accent = p.Material == Enum.Material.Neon and volume(p) < biggestHead * 0.25 -- 작은 빛 장식
		if accent then
			p.Color = spec.Edge
			p.Material = Enum.Material.Neon
		elseif isHead then
			p.Color = spec.Head
			p.Material = METAL
		else
			p.Color = spec.Shaft
			p.Material = METAL
		end
		if isHead then
			weighted += p.Position * volume(p)
			total += volume(p)
		end
		if p:IsA("MeshPart") then
			pcall(function()
				(p :: any).TextureID = ""
			end)
		end
	end
	for _, d in tool:GetDescendants() do
		if d:IsA("SpecialMesh") then
			d.TextureId = ""
		elseif d:IsA("SurfaceAppearance") or d:IsA("Decal") or d:IsA("Texture") then
			d:Destroy()
		elseif d:IsA("Trail") then
			d.Color = ColorSequence.new(spec.Trail)
			d.LightEmission = 1
			d.Lifetime = math.max(d.Lifetime, 0.3)
		elseif d:IsA("Light") then
			d.Color = spec.Light
		elseif d:IsA("ParticleEmitter") then
			d.Color = ColorSequence.new(spec.Sparkle)
		end
	end

	-- 머리 가운데에 빛 + 반짝이 (+ 오리하르콘은 불티)
	local center = if total > 0 then weighted / total else handle.Position
	local glowPoint = Instance.new("Attachment")
	glowPoint.Name = "TierGlow"
	glowPoint.Parent = handle
	glowPoint.WorldPosition = center
	local light = Instance.new("PointLight")
	light.Color = spec.Light
	light.Range = 9
	light.Brightness = 1.6
	light.Parent = glowPoint
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(spec.Sparkle)
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new(0.35, 0)
	sparkles.Lifetime = NumberRange.new(0.4, 0.9)
	sparkles.Rate = spec.SparkleRate
	sparkles.Speed = NumberRange.new(0.5, 1.2)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Parent = glowPoint
	if spec.Ember then
		local embers = Instance.new("ParticleEmitter")
		embers.Name = "Embers"
		embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		embers.Color = ColorSequence.new(spec.Ember, spec.Head)
		embers.LightEmission = 1
		embers.Size = NumberSequence.new(0.25, 0)
		embers.Lifetime = NumberRange.new(0.5, 1)
		embers.Rate = 10
		embers.Speed = NumberRange.new(0.5, 1.5)
		embers.SpreadAngle = Vector2.new(180, 180)
		embers.Acceleration = Vector3.new(0, 4, 0)
		embers.Parent = glowPoint
	end

	if spec.Scale and spec.Scale ~= 1 then
		scaleTool(tool, spec.Scale)
	end
	return tool
end

local highCount = 0
for _, spec in HIGH_PICKAXES do
	local old = pickaxeFolder:FindFirstChild(spec.Id)
	if old then
		old:Destroy()
	end
	local tool = buildHighPickaxe(spec)
	if tool then
		tool.Parent = pickaxeFolder
		local oldIcon = iconFolder:FindFirstChild(spec.Id)
		if oldIcon then
			oldIcon:Destroy()
		end
		iconFromToolDeep(tool, spec.Id).Parent = iconFolder
		highCount += 1
	end
end
print(`[BuildTreesAndAxes] 5·6단계 곡괭이 {highCount}종 완료`)

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
	model:SetAttribute("FromMapTree", true) -- 다시 실행할 때 맵 나무가 없으면 이 템플릿을 그대로 둔다
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

-- 맵 나무 모양 템플릿이 이미 있는지 (편집 상태에서 두 번째 실행하면 맵 나무는 이미 지워져 있다)
local function hasMapTreeTemplate(treeFolder: Instance?): boolean
	if not treeFolder then
		return false
	end
	for _, child in treeFolder:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("FromMapTree") == true then
			return true
		end
	end
	return false
end

local keptTemplates = 0
for _, id in TREE_IDS do
	local def = OreDefs[id]
	local old = oreFolder:FindFirstChild(def.TemplateName)
	if #sourceTrees == 0 and hasMapTreeTemplate(old) then
		keptTemplates += 1
		continue -- 전에 맵 나무로 만든 모양을 그대로 쓴다
	end
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
print(`[BuildTreesAndAxes] 맵 나무 {#mapTrees}그루 발견. 나무 5종 템플릿 완료 ({if #sourceTrees > 0 then "맵 나무 모양" elseif keptTemplates > 0 then "전에 만든 맵 나무 모양 유지" else "부품으로 만든 모양"})`)

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
-- 맵 나무 자리 + 빈 풀밭에 더 심은 자리. 종류는 마을 거리로 정한다 (Config.WorldTiers, 2026-10-09)
local tiers = Config.WorldTiers
local density = tiers.TreeDensity
local spawns = folder(workspace, "OreSpawns")

-- 전에 만든 맵 나무 자리를 기억해 둔다 (편집 상태에서 다시 실행하면 맵 나무는 이미 지워져 없다)
local rememberedMapSpots = {}
for _, child in spawns:GetChildren() do
	if child:IsA("BasePart") and child:GetAttribute("GeneratedBy") == GENERATED and child:GetAttribute("MapTreeSpot") == true then
		table.insert(rememberedMapSpots, child.Position - Vector3.new(0, 1, 0))
	end
end
clearGenerated(spawns)

local town = CollectionService:GetTagged("TownArrival")[1]
local center = if town and town:IsA("BasePart") then town.Position elseif town and town:IsA("Model") then town:GetPivot().Position else Vector3.zero
if not town then
	warn("[BuildTreesAndAxes] TownArrival 태그가 없어 (0, 0, 0) 둘레에 심었어요.")
end

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
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- 피해야 할 곳: NPC, 광산 입구, 마을 도착점
local avoid = {}
for _, tag in { "ShopNPC", "MinePortal", "TownArrival" } do
	for _, instance in CollectionService:GetTagged(tag) do
		local position = positionOf(instance)
		if position then
			table.insert(avoid, position)
		end
	end
end
-- 마을 안전지대 가운데 (새로 심는 나무·돌은 이 안에 안 둔다)
local safePoints = {}
for _, tag in { "TownArrival", "ShopNPC" } do
	for _, instance in CollectionService:GetTagged(tag) do
		local position = positionOf(instance)
		if position then
			table.insert(safePoints, position)
		end
	end
end
local zones = CollectionService:GetTagged("MineZone")

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = { spawns, workspace:FindFirstChild("Ores") }

-- 위에서 아래로 쏴서 materials 표에 있는 땅(지형) 또는 넓은 잔디 부품이면 맞은 결과를 돌려준다
local function landAt(x: number, z: number, materials): RaycastResult?
	local result = workspace:Raycast(Vector3.new(x, center.Y + 400, z), Vector3.new(0, -800, 0), params)
	if not result or result.Normal.Y < 0.8 then
		return nil -- 땅이 없거나 너무 가파름
	end
	local hit = result.Instance
	local isGround = (hit:IsA("Terrain") and materials[result.Material] == true)
		or (hit:IsA("BasePart") and hit.Material == Enum.Material.Grass and hit.Size.X > 30)
	if not isGround then
		return nil -- 건물·길·물 위
	end
	return result
end

local function insideMineZone(position: Vector3): boolean
	for _, zone in zones do
		if zone:IsA("BasePart") then
			local localPos = zone.CFrame:PointToObjectSpace(position)
			local half = zone.Size / 2 + Vector3.new(4, 4, 4)
			if math.abs(localPos.X) < half.X and math.abs(localPos.Y) < half.Y and math.abs(localPos.Z) < half.Z then
				return true
			end
		end
	end
	return false
end

-- 이 수평 위치에 나무를 심을 수 있으면 땅 위치를 돌려준다
local function groundAt(x: number, z: number, materials): Vector3?
	local result = landAt(x, z, materials or GROUND_MATERIALS)
	if not result or insideMineZone(result.Position) then
		return nil
	end
	for _, position in avoid do
		if (position - result.Position).Magnitude < KEEP_AWAY then
			return nil
		end
	end
	return result.Position
end

-- 새로 심을 자리: groundAt + 마을 안전지대 밖 + 둘레(ClearRadius)도 모두 같은 땅이고 평평함 (길·건물·물 가장자리 피하기)
local function newSpotAt(x: number, z: number, materials): Vector3?
	local ground = groundAt(x, z, materials)
	if not ground then
		return nil
	end
	for _, point in safePoints do
		if flatDistance(point, ground) < Config.MobAI.SafeZoneRadius then
			return nil
		end
	end
	local r = density.ClearRadius
	for _, offset in { Vector3.new(r, 0, 0), Vector3.new(-r, 0, 0), Vector3.new(0, 0, r), Vector3.new(0, 0, -r) } do
		local around = landAt(x + offset.X, z + offset.Z, materials)
		if not around or math.abs(around.Position.Y - ground.Y) > 2.5 then
			return nil
		end
	end
	return ground
end

-- 맵의 땅 반경 재기: 36방향으로 걸어 나가며 마지막으로 땅(물이 아닌 지형·넓은 부품)이 있던 거리, 그중 60% 지점 값
local function measureLandRadius(): number
	local farthest = {}
	for i = 0, 35 do
		local angle = i / 36 * math.pi * 2
		local last = 0
		for distance = 20, 600, 10 do
			local x, z = center.X + math.cos(angle) * distance, center.Z + math.sin(angle) * distance
			local result = workspace:Raycast(Vector3.new(x, center.Y + 400, z), Vector3.new(0, -800, 0), params)
			if result then
				local hit = result.Instance
				local land = (hit:IsA("Terrain") and result.Material ~= Enum.Material.Water)
					or (hit:IsA("BasePart") and hit.Size.X > 30 and hit.Size.Z > 30)
				if land and not insideMineZone(result.Position) then
					last = distance
				end
			end
		end
		table.insert(farthest, last)
	end
	table.sort(farthest)
	return farthest[math.ceil(#farthest * 0.6)]
end
local landRadius = measureLandRadius()
local scale = math.clamp(landRadius / tiers.MapRadius, tiers.MinScale, 1) -- 맵이 좁으면 모든 거리를 줄인다
-- Config 기준 거리 (실제 거리 / 배율)
local function refDistance(position: Vector3): number
	return flatDistance(position, center) / scale
end

-- 거리 d에서 띠마다 얼마나 그 띠인지(0~1). 이웃 띠와 겹친 구간에서는 한쪽이 줄고 다른 쪽이 늘어 합이 1이 된다
local function bandMemberships(bands, d: number): { number }
	local list, total = {}, 0
	for i, band in bands do
		local lo, hi = band.Distance[1], band.Distance[2]
		local m = 0
		if d >= lo and d <= hi then
			m = 1
			local prev, nextBand = bands[i - 1], bands[i + 1]
			local leftWidth = if prev then prev.Distance[2] - lo else 0
			local rightWidth = if nextBand then hi - nextBand.Distance[1] else 0
			if leftWidth > 0 then
				m = math.min(m, (d - lo) / leftWidth)
			end
			if rightWidth > 0 then
				m = math.min(m, (hi - d) / rightWidth)
			end
		end
		list[i] = m
		total += m
	end
	if total <= 0 then
		-- 띠 사이 빈 곳이면 가장 가까운 띠
		local best, bestGap = 1, math.huge
		for i, band in bands do
			local gap = math.max(band.Distance[1] - d, d - band.Distance[2], 0)
			if gap < bestGap then
				best, bestGap = i, gap
			end
		end
		list[best] = 1
	end
	return list
end

-- 거리 d에 맞는 나무 종류를 가중치로 뽑는다. 둘째 값 = 가장 비중이 큰 띠 번호 (요약용)
local function pickTreeType(d: number): (string, number)
	local bands = tiers.Trees
	local memberships = bandMemberships(bands, d)
	local weights, total = {}, 0
	local mainBand, mainM = 1, -1
	for i, band in bands do
		local m = memberships[i]
		if m > mainM then
			mainBand, mainM = i, m
		end
		if m > 0 then
			local bandTotal = 0
			for _, w in band.Weights do
				bandTotal += w
			end
			for id, w in band.Weights do
				local add = m * w / math.max(bandTotal, 1e-6) -- 띠마다 비율로 바꿔 섞는다
				weights[id] = (weights[id] or 0) + add
				total += add
			end
		end
	end
	local roll = random:NextNumber(0, total)
	local ids = {}
	for id in weights do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		roll -= weights[id]
		if roll <= 0 then
			return id, mainBand
		end
	end
	return ids[#ids] or "Pine", mainBand
end

-- 직접 놓은 자리(지상)는 간격 계산에 넣고, 지상 돌은 센다
local occupied = {} -- 간격을 지켜야 할 자리들
local handStones = {} -- Studio에서 직접 놓은 지상 돌 자리
for _, child in spawns:GetChildren() do
	local floor = child:GetAttribute("Floor")
	if child:IsA("BasePart") and (floor == nil or floor == 0) then
		table.insert(occupied, child.Position)
		if child:GetAttribute("OreType") == "Stone" then
			table.insert(handStones, child.Position)
		end
	end
end

local function farFrom(position: Vector3, gap: number): boolean
	for _, other in occupied do
		if (other - position).Magnitude < gap then
			return false
		end
	end
	return true
end

-- 맵 나무 자리 (원본 나무는 지우고 그 자리에 캘 수 있는 나무가 선다)
local spots = {} -- { Position, MapTree }
local mapSpotSource = {}
for _, entry in mapTrees do
	table.insert(mapSpotSource, entry.Base)
	entry.Instance:Destroy()
end
if #mapSpotSource == 0 then
	mapSpotSource = rememberedMapSpots
end
for _, position in mapSpotSource do
	if farFrom(position, density.MapTreeSpacing) then
		table.insert(spots, { Position = position, MapTree = true })
		table.insert(occupied, position)
	end
end
local mapSpotCount = #spots

-- 빈 풀밭에 더 심는다. 거리는 넓이가 아니라 반지름 기준으로 고르게 뽑아서 마을 가까이가 조금 더 빽빽하다
local target = math.clamp(math.round(mapSpotCount * density.Multiplier), density.MinCount, density.MaxCount)
target = math.max(target, mapSpotCount)
local scatterMin = density.ScatterMin * scale
local scatterMax = math.max(scatterMin + 20, math.min(landRadius, tiers.MapRadius))
local extra = 0
for pass, materials in { GRASS_ONLY, GROUND_MATERIALS } do
	-- 풀밭만으로 절반도 못 채우면 흙땅도 쓴다
	if pass == 2 and extra >= (target - mapSpotCount) * 0.5 then
		break
	end
	for _ = 1, math.max(target - mapSpotCount, 0) * 30 do
		if #spots >= target then
			break
		end
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(scatterMin, scatterMax)
		local ground = newSpotAt(center.X + math.cos(angle) * distance, center.Z + math.sin(angle) * distance, materials)
		if ground and farFrom(ground, density.Spacing) then
			table.insert(spots, { Position = ground, MapTree = false })
			table.insert(occupied, ground)
			extra += 1
		end
	end
end

local function addSpawn(position: Vector3, oreType: string, pool: string?, mapTree: boolean?, band: string?)
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
	if mapTree then
		p:SetAttribute("MapTreeSpot", true) -- 맵 나무가 서 있던 자리 (다시 실행할 때 기억용)
	end
	if band then
		p:SetAttribute("Band", band)
	end
end

-- 흑단나무: 먼 곳(Ebony.MinDistance 밖) 중 마을에서 가장 먼 자리들, 서로 멀리
table.sort(spots, function(a, b)
	return flatDistance(a.Position, center) > flatDistance(b.Position, center)
end)
local farSpots = {}
for _, spot in spots do
	if refDistance(spot.Position) >= tiers.Ebony.MinDistance then
		table.insert(farSpots, spot)
	end
end
if #farSpots < tiers.Ebony.Candidates then
	farSpots = spots -- 먼 곳이 모자라면 가장 먼 자리부터
end
local ebonyChosen = {}
local ebonySpacing = if #farSpots > 0 then flatDistance(farSpots[1].Position, center) * 0.4 else 0
for _, spacing in { ebonySpacing, ebonySpacing * 0.5, 0 } do
	for _, spot in farSpots do
		if #ebonyChosen >= tiers.Ebony.Candidates then
			break
		end
		local spread = not spot.Ebony
		for _, other in ebonyChosen do
			if spread and (other.Position - spot.Position).Magnitude < spacing then
				spread = false
			end
		end
		if spread then
			spot.Ebony = true
			table.insert(ebonyChosen, spot)
		end
	end
end

-- 나머지 자리: 마을 거리로 종류를 뽑는다
local bandCounts = {} -- 띠 번호 → { 종류 → 개수 }
for i = 1, #tiers.Trees do
	bandCounts[i] = {}
end
for _, spot in spots do
	if spot.Ebony then
		addSpawn(spot.Position, "Ebony", "Ebony", spot.MapTree, "Ebony")
	else
		local oreType, bandIndex = pickTreeType(refDistance(spot.Position))
		addSpawn(spot.Position, oreType, nil, spot.MapTree, tiers.Trees[bandIndex].Name)
		bandCounts[bandIndex][oreType] = (bandCounts[bandIndex][oreType] or 0) + 1
	end
end

-- 지상 돌: 마을 근처(Stone.Distance)에 MinCount개가 되도록 채운다
local stoneConfig = tiers.Stone
local nearStones = 0
for _, position in handStones do
	local d = refDistance(position)
	if d >= stoneConfig.Distance[1] and d <= stoneConfig.Distance[2] then
		nearStones += 1
	end
end
local newStones = 0
for _ = 1, math.max(stoneConfig.MinCount - nearStones, 0) * 60 do
	if nearStones + newStones >= stoneConfig.MinCount then
		break
	end
	local angle = random:NextNumber(0, math.pi * 2)
	local distance = random:NextNumber(stoneConfig.Distance[1], stoneConfig.Distance[2]) * scale
	local ground = newSpotAt(center.X + math.cos(angle) * distance, center.Z + math.sin(angle) * distance, GROUND_MATERIALS)
	if ground and farFrom(ground, density.Spacing) then
		addSpawn(ground, "Stone", nil, false, "마을 근처")
		table.insert(occupied, ground)
		newStones += 1
	end
end

-- 요약 (띠마다)
print(
	`[BuildTreesAndAxes] 나무 자리 {#spots}곳 = 맵 나무 자리 {mapSpotCount} + 새로 심은 {extra} (목표 {target}).`
		.. ` 땅 반경 약 {landRadius} → 거리 배율 x{string.format("%.2f", scale)}`
)
for i, band in tiers.Trees do
	local parts = {}
	local total = 0
	for _, id in TREE_IDS do
		local count = bandCounts[i][id]
		if count then
			table.insert(parts, `{OreDefs[id].DisplayName} {count}`)
			total += count
		end
	end
	local hi = if band.Distance[2] >= 9999 then "끝" else tostring(math.floor(band.Distance[2] * scale))
	print(`[BuildTreesAndAxes]   {band.Name}({math.floor(band.Distance[1] * scale)}~{hi}): {total}그루 - {table.concat(parts, " / ")}`)
end
print(
	`[BuildTreesAndAxes]   흑단나무 후보 {#ebonyChosen}곳 (동시에 {Config.RandomPools.Ebony.Active}그루). 마을 근처 돌: 직접 놓은 {nearStones} + 새로 {newStones}`
		.. ` (지상 돌 전체 직접 놓은 {#handStones})`
)
if #spots == 0 then
	warn("[BuildTreesAndAxes] 심을 땅을 못 찾았어요. GROUND_MATERIALS나 Config.WorldTiers.TreeDensity를 맵에 맞게 바꿔 보세요.")
end

if recording then
	pcall(ChangeHistoryService.FinishRecording, ChangeHistoryService, recording, Enum.FinishRecordingOperation.Commit)
end
print("[BuildTreesAndAxes] 끝. Ctrl+Z로 한 번에 되돌릴 수 있어요.")

return true
