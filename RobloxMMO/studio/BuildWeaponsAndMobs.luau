--!nocheck
-- Studio 제작 스크립트 2: 무기 12종·몹 5종 모델, 아이콘, 몹 생성 자리.
-- Rojo가 ServerStorage/StudioTools/BuildWeaponsAndMobs(ModuleScript)로 넣고, 서버(Main.server)가 게임을 시작할 때마다 실행한다.
-- 편집 상태에서 직접 실행하려면 명령 모음에: require(game.ServerStorage.StudioTools.BuildWeaponsAndMobs:Clone())
--
-- 만드는 것
--   1. 무기 Tool 12종 → ServerStorage/Templates/Pickaxes/<무기 Id> (곡괭이·도끼와 같은 폴더, PickaxeService가 지급)
--      돌 곡괭이 Tool의 쥐는 각도(Grip)를 그대로 쓰고 모양은 숨긴 뒤, 부품으로 칼·활·방망이를 짓는다.
--      좌표: x = 앞(곡괭이 머리 방향), y = 자루를 따라 위, 원점 = 손이 쥐는 점
--   2. 몹 모델 5종 → ServerStorage/Templates/Mobs/<몹> (고정된 Root 부품 + 용접된 몸, 앞 = -Z, 기준점 = 발밑)
--   3. 아이콘 → ReplicatedStorage/ItemIcons (무기 12종 + 전리품 5종 + 음식 3종)
--   4. 몹 생성 자리 → Workspace/MobSpawns (속성 MobType). 마을(TownArrival)에서 Config.Mobs의 거리 띠 안 땅에 고른다

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local EquipmentDefs = require(ReplicatedStorage.Shared.EquipmentDefs)
local MobDefs = require(ReplicatedStorage.Shared.MobDefs)

local GENERATED = "BuildWeaponsAndMobs"
local random = Random.new()
local V = Vector2.new

---------------------------------------------------------------- 공용
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

local function folder(parent: Instance, name: string): Folder
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

-- 세 점으로 삼각형 판 (쐐기 두 개)
local function triangle(parent: Instance, a: Vector3, b: Vector3, c: Vector3, thickness: number, color: Color3, material: Enum.Material, weldTo: BasePart?, anchored: boolean?)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	if ac:Cross(ab).Magnitude < 1e-4 then
		return
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
				ClassName = "WedgePart", Name = "Plate", Size = w.Size, CFrame = w.CFrame, Color = color, Material = material,
				Anchored = anchored == true, CanCollide = false, CanQuery = false, CanTouch = false, Massless = true,
			}, parent)
			if weldTo then
				weld(weldTo, wedge)
			end
		end
	end
end

local templates = folder(ServerStorage, "Templates")
local toolFolder = folder(templates, "Pickaxes")
local mobFolder = folder(templates, "Mobs")
local iconFolder = folder(ReplicatedStorage, "ItemIcons")

---------------------------------------------------------------- 1. 무기
local WOOD = Enum.Material.Wood
local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon
local GLASS = Enum.Material.Glass
local LEATHER = Enum.Material.Leather
local C = Color3.fromRGB
local GOLD = C(225, 180, 75)

-- 곡괭이가 없을 때 쓸 기본 Tool
local function fallbackTool(): Tool
	local tool = Instance.new("Tool")
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	part({ Name = "Handle", Size = Vector3.new(0.3, 1, 0.3), Transparency = 1, Anchored = false, CanCollide = false }, tool)
	tool.Grip = CFrame.new()
	warn("[BuildWeaponsAndMobs] 돌 곡괭이 템플릿이 없어 기본 손잡이로 만들었어요. 쥐는 각도를 확인하세요.")
	return tool
end

-- 돌 곡괭이 Tool을 복제해 쥐는 점·자루 방향·앞 방향을 읽고 모양은 숨긴다
local function baseTool(): (Tool, Vector3, Vector3, Vector3)
	local source = toolFolder:FindFirstChild("StonePickaxe")
	if not (source and source:IsA("Tool") and source:FindFirstChild("Handle")) then
		local tool = fallbackTool()
		local h = tool.Handle
		return tool, h.Position, h.CFrame.UpVector, h.CFrame.LookVector
	end
	local tool = source:Clone()
	local handle = tool.Handle :: BasePart
	local grip = handle.CFrame:PointToWorldSpace(tool.Grip.Position)
	-- 머리 = 쥐는 점에서 먼 쪽 부품 무리 (도끼 제작 스크립트와 같은 방법)
	local farthest = 0
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			farthest = math.max(farthest, (d.Position - grip).Magnitude)
		end
	end
	local weighted, total, headPart, biggest = Vector3.zero, 0, handle, -1
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") and (d.Position - grip).Magnitude >= farthest * 0.75 then
			local volume = d.Size.X * d.Size.Y * d.Size.Z
			weighted += d.Position * volume
			total += volume
			if volume > biggest then
				headPart, biggest = d, volume
			end
		end
	end
	local center = if total > 0 then weighted / total else headPart.Position
	local up = (center - grip).Unit
	local best, bestSize = nil, -1
	for _, pair in { { headPart.CFrame.RightVector, headPart.Size.X }, { headPart.CFrame.UpVector, headPart.Size.Y }, { headPart.CFrame.LookVector, headPart.Size.Z } } do
		if math.abs(pair[1]:Dot(up)) < 0.7 and pair[2] > bestSize then
			best, bestSize = pair[1], pair[2]
		end
	end
	local axis = best or up:Cross(Vector3.yAxis)
	local forward = (axis - up * axis:Dot(up)).Unit
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 1
			d.CanCollide = false
		elseif d:IsA("Decal") or d:IsA("Texture") or d:IsA("Trail") or d:IsA("ParticleEmitter") or d:IsA("Light") then
			d:Destroy()
		end
	end
	return tool, grip, up, forward
end

-- 무기 하나를 짓는 도구 상자
local function newWeapon(id: string)
	local tool, grip, up, forward = baseTool()
	tool.Name = id
	tool:SetAttribute("PickaxeId", nil)
	tool:SetAttribute("GeneratedBy", GENERATED)
	local handle = tool.Handle :: BasePart
	local frame = CFrame.fromMatrix(grip, forward, up) -- x 앞, y 위(자루), z 두께
	local kit = { Tool = tool, Handle = handle, Frame = frame }

	function kit.at(x: number, y: number, z: number?): Vector3
		return frame:PointToWorldSpace(Vector3.new(x, y, z or 0))
	end
	-- 볼록 다각형 판 (fr: 다른 좌표계로 돌려 쓸 때)
	function kit.plate(points: { Vector2 }, thickness: number, color: Color3, material: Enum.Material, fr: CFrame?)
		local f = fr or frame
		local world = {}
		for _, p in points do
			table.insert(world, f:PointToWorldSpace(Vector3.new(p.X, p.Y, 0)))
		end
		for i = 2, #world - 1 do
			triangle(tool, world[1], world[i], world[i + 1], thickness, color, material, handle)
		end
	end
	-- 머리 좌표의 부품 (회전은 frame 기준)
	function kit.block(name: string, x: number, y: number, size: Vector3, color: Color3, material: Enum.Material, shape: Enum.PartType?, rotation: CFrame?, z: number?)
		local p = part({
			Name = name, Shape = shape or Enum.PartType.Block, Size = size, Color = color, Material = material,
			CFrame = (frame + (kit.at(x, y, z) - frame.Position)) * (rotation or CFrame.new()),
			Anchored = false, CanCollide = false, CanQuery = false, CanTouch = false, Massless = true,
		}, tool)
		weld(handle, p)
		return p
	end
	-- 자루를 따라 세운 원통 (y0~y1)
	function kit.rod(name: string, y0: number, y1: number, diameter: number, color: Color3, material: Enum.Material, x: number?)
		local mid = kit.at(x or 0, (y0 + y1) / 2)
		local p = part({
			Name = name, Shape = Enum.PartType.Cylinder, Size = Vector3.new(math.abs(y1 - y0), diameter, diameter), Color = color, Material = material,
			CFrame = CFrame.fromMatrix(mid, forward, up) * CFrame.Angles(0, 0, math.rad(90)),
			Anchored = false, CanCollide = false, CanQuery = false, CanTouch = false, Massless = true,
		}, tool)
		weld(handle, p)
		return p
	end
	-- 두 점(머리 좌표) 사이 원통
	function kit.segment(name: string, a: Vector2, b: Vector2, diameter: number, color: Color3, material: Enum.Material)
		local pa, pb = kit.at(a.X, a.Y), kit.at(b.X, b.Y)
		local length = (pb - pa).Magnitude
		if length < 0.01 then
			return
		end
		local p = part({
			Name = name, Shape = Enum.PartType.Cylinder, Size = Vector3.new(length + diameter * 0.5, diameter, diameter), Color = color, Material = material,
			CFrame = CFrame.lookAt((pa + pb) / 2, pb) * CFrame.Angles(0, math.rad(90), 0),
			Anchored = false, CanCollide = false, CanQuery = false, CanTouch = false, Massless = true,
		}, tool)
		weld(handle, p)
	end
	-- 휘두를 때 궤적 (SwingAnimation이 휘두르는 동안만 켠다)
	function kit.trail(top: Vector3, bottom: Vector3, color: Color3, lifetime: number)
		local a0 = Instance.new("Attachment")
		a0.Name = "TrailTop"
		a0.Parent = handle
		a0.WorldPosition = top
		local a1 = Instance.new("Attachment")
		a1.Name = "TrailBottom"
		a1.Parent = handle
		a1.WorldPosition = bottom
		local t = Instance.new("Trail")
		t.Attachment0 = a0
		t.Attachment1 = a1
		t.Color = ColorSequence.new(color)
		t.Transparency = NumberSequence.new(0.25, 1)
		t.Lifetime = lifetime
		t.LightEmission = 0.8
		t.Enabled = false
		t.Parent = handle
	end
	-- 다이아몬드 무기: 은은한 빛과 반짝이
	function kit.glow(position: Vector3, color: Color3)
		local a = Instance.new("Attachment")
		a.Name = "Glow"
		a.Parent = handle
		a.WorldPosition = position
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 8
		light.Brightness = 1.4
		light.Parent = a
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Color = ColorSequence.new(color)
		sparkles.LightEmission = 1
		sparkles.Size = NumberSequence.new(0.3, 0)
		sparkles.Lifetime = NumberRange.new(0.4, 0.9)
		sparkles.Rate = 6
		sparkles.Speed = NumberRange.new(0.4, 1)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Parent = a
	end
	return kit
end

-- 좌우 대칭 점 목록 (x를 뒤집는다)
local function mirror(points: { Vector2 }): { Vector2 }
	local out = {}
	for i, p in points do
		out[i] = V(-p.X, p.Y)
	end
	return out
end

local WEAPONS = {}

-- 칼 ----------------------------------------------------------------
WEAPONS.WoodenSword = function(k)
	k.rod("Grip", -0.45, 0.45, 0.24, C(95, 65, 40), WOOD)
	k.block("Pommel", 0, -0.55, Vector3.new(0.32, 0.32, 0.32), C(120, 85, 50), WOOD, Enum.PartType.Ball)
	k.block("Guard", 0, 0.52, Vector3.new(1.0, 0.16, 0.28), C(120, 85, 50), WOOD)
	k.plate({ V(-0.2, 0.58), V(0.2, 0.58), V(0.2, 2.7), V(0, 3.1), V(-0.2, 2.7) }, 0.14, C(200, 160, 110), WOOD)
end
WEAPONS.CopperSword = function(k)
	k.rod("Grip", -0.5, 0.48, 0.24, C(90, 55, 35), LEATHER)
	for i = 0, 3 do
		k.rod("Wrap", -0.4 + i * 0.25, -0.4 + i * 0.25 + 0.08, 0.28, C(200, 120, 60), METAL)
	end
	k.block("Pommel", 0, -0.6, Vector3.new(0.36, 0.36, 0.36), C(205, 115, 60), METAL, Enum.PartType.Ball)
	k.plate({ V(-0.7, 0.62), V(0.7, 0.62), V(0.45, 0.48), V(-0.45, 0.48) }, 0.3, C(225, 160, 80), METAL) -- 휜 코등이
	k.plate({ V(-0.24, 0.62), V(0.24, 0.62), V(0.34, 1.9), V(0, 3.0), V(-0.34, 1.9) }, 0.15, C(205, 115, 60), METAL)
	k.plate({ V(-0.05, 0.75), V(0.05, 0.75), V(0.05, 2.4), V(-0.05, 2.4) }, 0.18, C(255, 170, 90), NEON) -- 가운데 빛나는 홈
	k.trail(k.at(0, 3.0), k.at(0, 0.8), C(255, 150, 70), 0.14)
end
WEAPONS.IronSword = function(k)
	k.rod("Grip", -0.75, 0.48, 0.24, C(45, 40, 40), LEATHER)
	k.block("Pommel", 0, -0.85, Vector3.new(0.4, 0.4, 0.4), C(170, 170, 178), METAL, Enum.PartType.Ball)
	k.block("Guard", 0, 0.55, Vector3.new(1.5, 0.18, 0.3), C(150, 152, 160), METAL)
	k.block("GuardEnd", 0.75, 0.55, Vector3.new(0.3, 0.3, 0.3), C(150, 152, 160), METAL, Enum.PartType.Ball)
	k.block("GuardEnd", -0.75, 0.55, Vector3.new(0.3, 0.3, 0.3), C(150, 152, 160), METAL, Enum.PartType.Ball)
	k.plate({ V(-0.17, 0.62), V(0.17, 0.62), V(0.17, 3.4), V(0, 3.95), V(-0.17, 3.4) }, 0.13, C(205, 208, 215), METAL)
	k.plate({ V(-0.04, 0.8), V(0.04, 0.8), V(0.04, 3.2), V(-0.04, 3.2) }, 0.15, C(110, 112, 120), METAL) -- 홈
	k.trail(k.at(0, 3.9), k.at(0, 0.9), C(230, 235, 255), 0.18)
end
WEAPONS.DiamondSword = function(k)
	k.rod("Grip", -0.9, 0.55, 0.28, C(30, 25, 40), LEATHER)
	for i = 0, 3 do
		k.rod("Band", -0.8 + i * 0.4, -0.8 + i * 0.4 + 0.07, 0.32, GOLD, METAL)
	end
	k.plate({ V(0, -0.85), V(0.25, -1.1), V(0, -1.4), V(-0.25, -1.1) }, 0.25, C(150, 240, 255), NEON) -- 빛나는 다이아 손잡이 끝
	k.plate({ V(0.4, 0.75), V(1.15, 1.05), V(0.4, 0.52) }, 0.3, GOLD, METAL) -- 금 날개 코등이
	k.plate(mirror({ V(0.4, 0.75), V(1.15, 1.05), V(0.4, 0.52) }), 0.3, GOLD, METAL)
	k.block("Guard", 0, 0.62, Vector3.new(0.85, 0.24, 0.34), GOLD, METAL)
	k.plate({ V(-0.4, 0.72), V(0.4, 0.72), V(0.45, 3.6), V(0, 4.6), V(-0.45, 3.6) }, 0.17, C(95, 205, 245), GLASS)
	for _, side in { 1, -1 } do
		for i = 0, 2 do
			local y = 1.3 + i * 0.75
			k.plate({ V(0.4 * side, y), V(0.66 * side, y + 0.3), V(0.42 * side, y + 0.5) }, 0.15, C(210, 250, 255), GLASS) -- 톱니
		end
	end
	k.plate({ V(-0.07, 0.9), V(0.07, 0.9), V(0.07, 3.8), V(-0.07, 3.8) }, 0.22, C(170, 240, 255), NEON)
	k.trail(k.at(0, 4.6), k.at(0, 1.0), C(110, 235, 255), 0.26)
	k.glow(k.at(0, 2.6), C(120, 230, 255))
end

-- 방망이 -------------------------------------------------------------
-- 아래에서 위로 굵어지는 원통 마디들
local function taper(k, y0: number, y1: number, d0: number, d1: number, segments: number, color: Color3, material: Enum.Material)
	for i = 0, segments - 1 do
		local a = y0 + (y1 - y0) * i / segments
		local b = y0 + (y1 - y0) * (i + 1) / segments
		local d = d0 + (d1 - d0) * (i + 0.5) / segments
		k.rod("Body", a, b + 0.02, d, color, material)
	end
end
WEAPONS.BaseballBat = function(k)
	taper(k, -0.55, 3.2, 0.22, 0.58, 7, C(215, 180, 130), WOOD)
	k.block("Cap", 0, 3.2, Vector3.new(0.58, 0.58, 0.58), C(215, 180, 130), WOOD, Enum.PartType.Ball)
	k.rod("Knob", -0.68, -0.55, 0.36, C(190, 155, 110), WOOD)
	for i = 0, 3 do
		k.rod("Tape", -0.45 + i * 0.2, -0.45 + i * 0.2 + 0.12, 0.26, C(30, 30, 35), Enum.Material.Fabric)
	end
	k.rod("Logo", 2.0, 2.15, 0.5, C(200, 40, 40), Enum.Material.SmoothPlastic)
end
WEAPONS.GoblinClub = function(k) -- 도깨비방망이: 울퉁불퉁 굵은 몽둥이에 금 돌기
	taper(k, -0.6, 2.9, 0.3, 0.85, 7, C(120, 75, 45), WOOD)
	k.block("Top", 0, 2.95, Vector3.new(0.95, 0.95, 0.95), C(120, 75, 45), WOOD, Enum.PartType.Ball)
	k.rod("Rope", -0.1, 0.12, 0.38, C(200, 40, 50), Enum.Material.Fabric)
	k.rod("Rope", 0.2, 0.32, 0.4, C(40, 90, 200), Enum.Material.Fabric)
	for ring = 0, 2 do
		local y = 1.6 + ring * 0.5
		local r = (0.3 + (0.85 - 0.3) * (y + 0.6) / 3.5) / 2
		for i = 0, 5 do
			local angle = i / 6 * math.pi * 2 + ring * 0.5
			k.block("Stud", math.cos(angle) * r, y, Vector3.new(0.24, 0.24, 0.24), GOLD, METAL, Enum.PartType.Ball, nil, math.sin(angle) * r)
		end
	end
	k.trail(k.at(0, 3.3), k.at(0, 1.5), C(255, 150, 70), 0.14)
end
WEAPONS.MorningStar = function(k) -- 쇠 자루 끝에 가시 철구
	k.rod("Shaft", -0.7, 2.3, 0.22, C(80, 82, 90), METAL)
	k.rod("Grip", -0.6, 0.4, 0.27, C(70, 45, 30), LEATHER)
	k.rod("Collar", 2.2, 2.35, 0.36, C(150, 152, 160), METAL)
	local ballY = 2.85
	k.block("Ball", 0, ballY, Vector3.new(1.1, 1.1, 1.1), C(95, 97, 105), METAL, Enum.PartType.Ball)
	-- 가시: 공 표면에 고르게 (피보나치 구)
	local count = 16
	for i = 0, count - 1 do
		local y = 1 - (i + 0.5) / count * 2
		local r = math.sqrt(1 - y * y)
		local theta = i * 2.39996
		local dir = Vector3.new(math.cos(theta) * r, y, math.sin(theta) * r)
		local center = k.at(0, ballY) + k.Frame:VectorToWorldSpace(dir) * 0.62
		local p = part({
			Name = "Spike", Size = Vector3.new(0.16, 0.16, 0.5), Color = C(200, 202, 210), Material = METAL,
			CFrame = CFrame.lookAt(center, center + k.Frame:VectorToWorldSpace(dir)),
			Anchored = false, CanCollide = false, CanQuery = false, CanTouch = false, Massless = true,
		}, k.Tool)
		weld(k.Handle, p)
	end
	k.trail(k.at(0, 3.4), k.at(0, 2.3), C(230, 235, 255), 0.18)
end
WEAPONS.DiamondMace = function(k) -- 다이아 철퇴: 빛나는 핵 + 날개 6장
	k.rod("Shaft", -0.8, 2.3, 0.26, C(30, 25, 40), METAL)
	for i = 0, 4 do
		k.rod("Band", -0.7 + i * 0.6, -0.7 + i * 0.6 + 0.08, 0.3, GOLD, METAL)
	end
	k.block("Pommel", 0, -0.9, Vector3.new(0.4, 0.4, 0.4), C(150, 240, 255), NEON, Enum.PartType.Ball)
	k.block("Core", 0, 2.75, Vector3.new(0.7, 0.7, 0.7), C(150, 240, 255), NEON, Enum.PartType.Ball)
	for i = 0, 5 do
		local fr = k.Frame * CFrame.Angles(0, i / 6 * math.pi * 2, 0)
		k.plate({ V(0.25, 2.15), V(0.82, 2.45), V(0.9, 3.05), V(0.25, 3.35) }, 0.14, C(95, 205, 245), GLASS, fr)
	end
	k.plate({ V(0, 3.2), V(0.18, 3.55), V(0, 4.0), V(-0.18, 3.55) }, 0.2, C(210, 250, 255), GLASS) -- 위 가시
	k.rod("Collar", 2.0, 2.18, 0.42, GOLD, METAL)
	k.trail(k.at(0, 3.9), k.at(0, 2.2), C(110, 235, 255), 0.26)
	k.glow(k.at(0, 2.75), C(120, 230, 255))
end

-- 활 ----------------------------------------------------------------
-- 활대: y = -half~half, 끝이 뒤(-x)로 휜다. recurve > 0이면 끝이 다시 앞으로 말린다
local function bowLimbs(k, half: number, bend: number, recurve: number, d0: number, d1: number, color: Color3, material: Enum.Material): (Vector2, Vector2)
	local function point(t: number): Vector2 -- t = -1~1
		local a = math.abs(t)
		local x = -bend * a * a + recurve * math.max(a - 0.75, 0) ^ 2 * 16
		return V(x, t * half)
	end
	local steps = 8
	for side = -1, 1, 2 do
		for i = 0, steps - 1 do
			local t0, t1 = side * i / steps, side * (i + 1) / steps
			local d = d0 + (d1 - d0) * (i + 0.5) / steps
			k.segment("Limb", point(t0), point(t1), d, color, material)
		end
	end
	return point(1), point(-1)
end
local function bowString(k, top: Vector2, bottom: Vector2, color: Color3)
	local inset = 0.06
	k.segment("String", V(top.X - inset, top.Y), V(bottom.X - inset, bottom.Y), 0.04, color, Enum.Material.SmoothPlastic)
end
WEAPONS.WoodenBow = function(k)
	local top, bottom = bowLimbs(k, 1.8, 0.55, 0, 0.2, 0.12, C(150, 105, 60), WOOD)
	k.rod("Grip", -0.25, 0.25, 0.26, C(90, 60, 35), LEATHER)
	bowString(k, top, bottom, C(240, 235, 220))
end
WEAPONS.CopperBow = function(k) -- 끝이 다시 앞으로 말린 리커브
	local top, bottom = bowLimbs(k, 1.9, 0.6, 0.35, 0.22, 0.13, C(110, 70, 40), WOOD)
	k.rod("Grip", -0.28, 0.28, 0.28, C(205, 115, 60), METAL)
	for _, y in { 1, -1 } do
		k.block("Tip", top.X, 1.9 * y, Vector3.new(0.2, 0.2, 0.2), C(225, 150, 80), METAL, Enum.PartType.Ball)
	end
	bowString(k, top, bottom, C(250, 200, 140))
end
WEAPONS.IronBow = function(k) -- 크고 곧은 장궁, 쇠 마구리
	local top, bottom = bowLimbs(k, 2.5, 0.5, 0, 0.22, 0.14, C(85, 60, 45), WOOD)
	k.rod("Grip", -0.3, 0.3, 0.29, C(45, 40, 40), LEATHER)
	k.rod("Ring", 0.32, 0.42, 0.3, C(170, 172, 180), METAL)
	k.rod("Ring", -0.42, -0.32, 0.3, C(170, 172, 180), METAL)
	for _, y in { 1, -1 } do
		k.block("Cap", (if y > 0 then top.X else bottom.X), 2.5 * y, Vector3.new(0.24, 0.24, 0.24), C(200, 202, 210), METAL, Enum.PartType.Ball)
	end
	bowString(k, top, bottom, C(230, 230, 235))
end
WEAPONS.DiamondBow = function(k) -- 빛나는 수정 활대 + 날개 장식. 다른 활보다 20% 크게 (2026-10-09 사용자 요청)
	local S = 1.2
	local top, bottom = bowLimbs(k, 2.2 * S, 0.6 * S, 0.25 * S, 0.2 * S, 0.12 * S, C(120, 230, 255), NEON)
	k.rod("Grip", -0.3 * S, 0.3 * S, 0.3 * S, GOLD, METAL)
	for _, y in { 1, -1 } do
		k.plate({ V(-0.05 * S, 0.4 * y * S), V(0.45 * S, 0.9 * y * S), V(-0.15 * S, 1.3 * y * S) }, 0.12 * S, C(95, 205, 245), GLASS)
	end
	k.plate({ V(0.12 * S, 0), V(0.32 * S, 0.2 * S), V(0.12 * S, 0.4 * S), V(0.0, 0.2 * S) }, 0.2 * S, C(210, 250, 255), NEON)
	bowString(k, top, bottom, C(200, 245, 255))
	k.glow(k.at(0, 0), C(120, 230, 255))
end

-- 도구를 아이콘용 모델로 (보이는 부품만)
local function iconFromTool(tool: Tool, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	for _, d in tool:GetChildren() do
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

local weaponCount = 0
for id, build in WEAPONS do
	local old = toolFolder:FindFirstChild(id)
	if old then
		old:Destroy()
	end
	local k = newWeapon(id)
	build(k)
	k.Tool.Parent = toolFolder
	local oldIcon = iconFolder:FindFirstChild(id)
	if oldIcon then
		oldIcon:Destroy()
	end
	iconFromTool(k.Tool, id).Parent = iconFolder
	weaponCount += 1
end
print(`[BuildWeaponsAndMobs] 무기 {weaponCount}종 완료`)

---------------------------------------------------------------- 2. 몹
-- 몹 모델 도구 상자: 좌표는 발밑 원점, 앞 = -Z
local function newMob(name: string)
	local model = Instance.new("Model")
	model.Name = name
	local root = part({ Name = "Root", Size = Vector3.new(1.5, 0.2, 1.5), CFrame = CFrame.new(0, 0.1, 0), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false }, model)
	root.PivotOffset = CFrame.new(0, -0.1, 0) -- 기준점 = 발밑
	model.PrimaryPart = root
	local kit = { Model = model, Root = root }
	local function add(p: BasePart)
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		weld(root, p)
		return p
	end
	-- 말랑한 타원체 (SpecialMesh 구)
	function kit.blob(partName: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material?, transparency: number?, rotation: CFrame?)
		local p = part({ Name = partName, Size = size, CFrame = CFrame.new(position) * (rotation or CFrame.new()), Color = color, Material = material or Enum.Material.SmoothPlastic, Transparency = transparency or 0 }, model)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
		return add(p)
	end
	function kit.box(partName: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?)
		return add(part({ Name = partName, Size = size, CFrame = cframe, Color = color, Material = material or Enum.Material.SmoothPlastic }, model))
	end
	function kit.ball(partName: string, diameter: number, position: Vector3, color: Color3, material: Enum.Material?)
		return add(part({ Name = partName, Shape = Enum.PartType.Ball, Size = Vector3.new(diameter, diameter, diameter), CFrame = CFrame.new(position), Color = color, Material = material or Enum.Material.SmoothPlastic }, model))
	end
	-- 두 점 사이 원통 (팔다리)
	function kit.limb(partName: string, a: Vector3, b: Vector3, diameter: number, color: Color3, material: Enum.Material?)
		local length = (b - a).Magnitude
		return add(part({
			Name = partName, Shape = Enum.PartType.Cylinder, Size = Vector3.new(length + diameter * 0.4, diameter, diameter),
			CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0), Color = color, Material = material or Enum.Material.SmoothPlastic,
		}, model))
	end
	-- 귀여운 눈 한 쌍 (검은 눈동자 + 하얀 반짝임). z는 얼굴 앞면
	function kit.eyes(x: number, y: number, z: number, size: number)
		for _, side in { 1, -1 } do
			kit.ball("Eye", size, Vector3.new(x * side, y, z), C(25, 20, 30))
			kit.ball("Shine", size * 0.35, Vector3.new(x * side + size * 0.15, y + size * 0.18, z - size * 0.4), C(255, 255, 255), NEON)
		end
	end
	function kit.blush(x: number, y: number, z: number, size: number)
		for _, side in { 1, -1 } do
			kit.blob("Blush", Vector3.new(size, size * 0.5, 0.1), Vector3.new(x * side, y, z), C(255, 140, 160))
		end
	end
	return kit
end

local MOBS = {}

MOBS.Slime = function(k)
	local green = C(110, 225, 160)
	k.blob("Body", Vector3.new(3.2, 2.4, 3.2), Vector3.new(0, 1.2, 0), green, Enum.Material.Glass, 0.15)
	k.blob("Core", Vector3.new(1.4, 1.0, 1.4), Vector3.new(0, 1.0, 0.2), C(70, 180, 120), Enum.Material.SmoothPlastic, 0.3)
	k.eyes(0.55, 1.45, -1.42, 0.45)
	k.blush(0.95, 1.1, -1.38, 0.45)
	k.blob("Mouth", Vector3.new(0.35, 0.15, 0.1), Vector3.new(0, 1.0, -1.55), C(40, 90, 60))
	k.limb("Sprout", Vector3.new(0, 2.3, 0), Vector3.new(0.1, 2.8, 0), 0.1, C(80, 150, 60))
	k.blob("Leaf", Vector3.new(0.6, 0.12, 0.35), Vector3.new(0.35, 2.85, 0), C(100, 200, 80), nil, nil, CFrame.Angles(0, 0, math.rad(20)))
end

MOBS.Skeleton = function(k)
	local bone = C(240, 235, 220)
	local dark = C(60, 55, 65)
	k.ball("Skull", 2.2, Vector3.new(0, 3.0, 0), bone)
	for _, side in { 1, -1 } do
		k.ball("Socket", 0.65, Vector3.new(0.45 * side, 3.05, -0.85), dark)
		k.ball("Glint", 0.18, Vector3.new(0.5 * side, 3.12, -1.12), C(120, 220, 255), NEON)
	end
	k.blob("Nose", Vector3.new(0.25, 0.2, 0.1), Vector3.new(0, 2.7, -1.07), dark)
	k.box("Jaw", Vector3.new(1.1, 0.35, 0.9), CFrame.new(0, 2.1, -0.3), bone)
	for i = -2, 2 do
		k.box("Tooth", Vector3.new(0.12, 0.12, 0.05), CFrame.new(i * 0.18, 2.3, -0.76), C(255, 255, 255))
	end
	k.box("Ribs", Vector3.new(1.1, 1.0, 0.6), CFrame.new(0, 1.55, 0), bone)
	for _, y in { 1.35, 1.55, 1.75 } do
		k.box("RibGap", Vector3.new(1.12, 0.07, 0.62), CFrame.new(0, y, 0), dark)
	end
	k.box("Pelvis", Vector3.new(0.9, 0.28, 0.5), CFrame.new(0, 0.95, 0), bone)
	for _, side in { 1, -1 } do
		k.limb("Leg", Vector3.new(0.3 * side, 0.9, 0), Vector3.new(0.32 * side, 0.15, 0), 0.22, bone)
		k.ball("Foot", 0.32, Vector3.new(0.32 * side, 0.12, -0.12), bone)
		k.limb("Arm", Vector3.new(0.65 * side, 1.9, 0), Vector3.new(0.85 * side, 1.15, -0.25), 0.18, bone)
		k.ball("Hand", 0.28, Vector3.new(0.87 * side, 1.1, -0.28), bone)
	end
	k.box("Bandana", Vector3.new(2.25, 0.3, 2.25), CFrame.new(0, 3.55, 0), C(200, 50, 60)) -- 빨간 두건
end

MOBS.Zombie = function(k)
	local skin = C(140, 200, 120)
	k.ball("Head", 2.0, Vector3.new(0, 2.9, 0), skin)
	k.box("Hair", Vector3.new(1.6, 0.35, 1.4), CFrame.new(0.1, 3.85, 0.1) * CFrame.Angles(0, 0, math.rad(8)), C(60, 90, 50))
	k.ball("EyeWhite", 0.6, Vector3.new(0.42, 2.95, -0.82), C(255, 255, 255))
	k.ball("Pupil", 0.25, Vector3.new(0.42, 2.95, -1.1), C(25, 20, 30))
	for _, angle in { 45, -45 } do -- X자로 꿰맨 눈
		k.box("Stitch", Vector3.new(0.45, 0.08, 0.05), CFrame.new(-0.42, 2.95, -0.98) * CFrame.Angles(0, 0, math.rad(angle)), C(50, 40, 40))
	end
	k.blob("Mouth", Vector3.new(0.6, 0.18, 0.1), Vector3.new(0, 2.4, -0.95), C(70, 40, 50))
	k.box("Tooth", Vector3.new(0.12, 0.14, 0.05), CFrame.new(0.12, 2.37, -1.0), C(255, 255, 240))
	k.box("Scar", Vector3.new(0.6, 0.06, 0.05), CFrame.new(-0.3, 3.5, -0.78) * CFrame.Angles(0, 0, math.rad(-15)), C(80, 60, 60))
	k.blush(0.7, 2.6, -0.85, 0.35)
	k.box("Shirt", Vector3.new(1.3, 1.1, 0.8), CFrame.new(0, 1.5, 0), C(90, 110, 150), Enum.Material.Fabric)
	k.box("Patch", Vector3.new(0.35, 0.35, 0.05), CFrame.new(0.3, 1.6, -0.42), C(200, 170, 90), Enum.Material.Fabric)
	for _, side in { 1, -1 } do
		k.box("Arm", Vector3.new(0.35, 0.35, 1.3), CFrame.new(0.62 * side, 1.8, -0.75), skin) -- 앞으로 뻗은 팔
		k.box("Leg", Vector3.new(0.45, 0.95, 0.5), CFrame.new(0.32 * side, 0.48, 0), C(110, 80, 60), Enum.Material.Fabric)
	end
end

MOBS.Cerberus = function(k)
	local fur = C(70, 55, 60)
	local light = C(120, 100, 105)
	k.blob("Body", Vector3.new(2.2, 1.6, 3.0), Vector3.new(0, 1.4, 0.2), fur)
	for _, x in { 0.65, -0.65 } do
		for _, z in { -0.8, 1.1 } do
			k.limb("Leg", Vector3.new(x, 1.0, z), Vector3.new(x, 0.15, z), 0.45, fur)
			k.ball("Paw", 0.5, Vector3.new(x, 0.2, z - 0.1), light)
		end
	end
	-- 머리 셋
	for i, x in { -1.0, 0, 1.0 } do
		local y = if x == 0 then 2.65 else 2.35
		local z = -1.5
		k.ball("Head", 1.3, Vector3.new(x, y, z), fur)
		k.blob("Snout", Vector3.new(0.7, 0.5, 0.6), Vector3.new(x, y - 0.2, z - 0.6), light)
		k.ball("Nose", 0.22, Vector3.new(x, y - 0.05, z - 0.9), C(25, 20, 25))
		k.eyes(0.25, y + 0.2, z - 0.58, 0.28)
		for _, side in { 1, -1 } do
			k.box("Ear", Vector3.new(0.3, 0.55, 0.2), CFrame.new(x + 0.38 * side, y + 0.6, z + 0.1) * CFrame.Angles(0, 0, math.rad(-20 * side)), fur)
		end
		if i == 2 then
			k.blob("Tongue", Vector3.new(0.25, 0.1, 0.35), Vector3.new(0, y - 0.5, z - 0.75), C(255, 120, 150))
		end
	end
	k.blob("Collar", Vector3.new(2.4, 0.4, 1.4), Vector3.new(0, 2.0, -1.0), C(200, 40, 50))
	for _, x in { -0.8, 0, 0.8 } do
		k.ball("Stud", 0.2, Vector3.new(x, 2.0, -1.68), GOLD, METAL)
	end
	k.limb("Tail", Vector3.new(0, 1.8, 1.6), Vector3.new(0, 2.6, 2.1), 0.25, fur)
	k.ball("TailFlame", 0.5, Vector3.new(0, 2.75, 2.2), C(255, 140, 50), NEON)
end

MOBS.Bugbear = function(k)
	local fur = C(150, 100, 65)
	local belly = C(225, 190, 140)
	k.blob("Body", Vector3.new(2.6, 2.6, 2.2), Vector3.new(0, 1.7, 0), fur, Enum.Material.Fabric)
	k.blob("Belly", Vector3.new(1.8, 1.8, 0.4), Vector3.new(0, 1.6, -1.0), belly, Enum.Material.Fabric)
	k.blob("Head", Vector3.new(1.9, 1.7, 1.7), Vector3.new(0, 3.5, -0.2), fur, Enum.Material.Fabric)
	k.blob("Muzzle", Vector3.new(0.9, 0.6, 0.5), Vector3.new(0, 3.25, -1.0), belly)
	k.ball("Nose", 0.3, Vector3.new(0, 3.4, -1.25), C(30, 25, 25))
	k.eyes(0.42, 3.75, -0.95, 0.3)
	k.blush(0.7, 3.35, -0.95, 0.35)
	for _, side in { 1, -1 } do
		k.ball("Ear", 0.6, Vector3.new(0.75 * side, 4.25, -0.1), fur)
		k.ball("EarInner", 0.3, Vector3.new(0.75 * side, 4.25, -0.32), C(255, 170, 170))
		k.box("Tusk", Vector3.new(0.12, 0.25, 0.12), CFrame.new(0.22 * side, 3.0, -1.18), C(255, 250, 235))
		k.limb("Arm", Vector3.new(1.2 * side, 2.3, 0), Vector3.new(1.45 * side, 1.3, -0.4), 0.6, fur, Enum.Material.Fabric)
		k.ball("Paw", 0.65, Vector3.new(1.47 * side, 1.2, -0.45), belly)
		k.limb("Leg", Vector3.new(0.6 * side, 0.7, 0), Vector3.new(0.65 * side, 0.2, -0.1), 0.7, fur, Enum.Material.Fabric)
	end
	-- 손에 든 작은 나무 몽둥이
	k.limb("Club", Vector3.new(1.5, 1.1, -0.5), Vector3.new(1.75, 2.6, -1.2), 0.3, C(120, 80, 45), WOOD)
	k.ball("ClubHead", 0.6, Vector3.new(1.8, 2.8, -1.3), C(120, 80, 45), WOOD)
end

local mobCount = 0
for id, build in MOBS do
	local def = MobDefs[id]
	local config = Config.Mobs[id]
	local old = mobFolder:FindFirstChild(def.TemplateName)
	if old then
		old:Destroy()
	end
	local k = newMob(def.TemplateName)
	build(k)
	if config and config.Scale and config.Scale ~= 1 then
		k.Model:ScaleTo(config.Scale)
	end
	k.Model:SetAttribute("GeneratedBy", GENERATED)
	k.Model.Parent = mobFolder
	mobCount += 1
end
print(`[BuildWeaponsAndMobs] 몹 {mobCount}종 완료`)

---------------------------------------------------------------- 3. 전리품·음식 아이콘
local LOOT_ICONS = {
	SlimeJelly = function(m)
		local p = part({ Name = "Jelly", Size = Vector3.new(1.2, 0.9, 1.2), Color = C(110, 225, 160), Material = GLASS, Transparency = 0.2 }, m)
		Instance.new("SpecialMesh", p).MeshType = Enum.MeshType.Sphere
	end,
	Bone = function(m)
		part({ Name = "Shaft", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.8, 0.35, 0.35), Color = C(240, 235, 220) }, m)
		for _, x in { 0.9, -0.9 } do
			for _, z in { 0.18, -0.18 } do
				part({ Name = "Knob", Shape = Enum.PartType.Ball, Size = Vector3.new(0.45, 0.45, 0.45), CFrame = CFrame.new(x, 0, z), Color = C(240, 235, 220) }, m)
			end
		end
	end,
	OldCloth = function(m)
		part({ Name = "Cloth", Size = Vector3.new(1.4, 0.15, 1.1), CFrame = CFrame.Angles(0, 0, math.rad(8)), Color = C(90, 110, 150), Material = Enum.Material.Fabric }, m)
		part({ Name = "Patch", Size = Vector3.new(0.45, 0.17, 0.4), CFrame = CFrame.new(0.3, 0.03, 0.1) * CFrame.Angles(0, 0, math.rad(8)), Color = C(200, 170, 90), Material = Enum.Material.Fabric }, m)
	end,
	CerberusFang = function(m)
		triangle(m, Vector3.new(-0.3, 0, 0), Vector3.new(0.3, 0, 0), Vector3.new(0.05, -1.4, 0), 0.3, C(250, 245, 230), Enum.Material.SmoothPlastic, nil, true)
		part({ Name = "Root", Size = Vector3.new(0.65, 0.25, 0.35), CFrame = CFrame.new(0, 0.1, 0), Color = C(200, 60, 70) }, m)
	end,
	-- 음식
	Bread = function(m)
		local loaf = part({ Name = "Loaf", Size = Vector3.new(1.6, 0.9, 1.0), Color = C(210, 160, 90) }, m)
		Instance.new("SpecialMesh", loaf).MeshType = Enum.MeshType.Sphere
		for i = -1, 1 do
			part({ Name = "Cut", Size = Vector3.new(0.08, 0.12, 0.7), CFrame = CFrame.new(i * 0.4, 0.42, 0) * CFrame.Angles(0, math.rad(20), 0), Color = C(245, 215, 150) }, m)
		end
	end,
	ManaBerry = function(m)
		for i, offset in { Vector3.new(0, 0, 0), Vector3.new(0.45, 0.1, 0.1), Vector3.new(-0.4, 0.05, 0.15), Vector3.new(0.05, 0.4, 0.05) } do
			part({ Name = "Berry", Shape = Enum.PartType.Ball, Size = Vector3.new(0.55, 0.55, 0.55), CFrame = CFrame.new(offset), Color = C(90, 130, 255), Material = if i == 4 then Enum.Material.Neon else Enum.Material.SmoothPlastic }, m)
		end
		part({ Name = "Leaf", Size = Vector3.new(0.5, 0.06, 0.25), CFrame = CFrame.new(0.1, 0.7, 0) * CFrame.Angles(0, 0, math.rad(25)), Color = C(90, 180, 80) }, m)
	end,
	LunchBox = function(m)
		part({ Name = "Box", Size = Vector3.new(1.5, 0.7, 1.0), Color = C(220, 70, 70) }, m)
		part({ Name = "Lid", Size = Vector3.new(1.55, 0.2, 1.05), CFrame = CFrame.new(0, 0.42, 0), Color = C(245, 240, 230) }, m)
		part({ Name = "Band", Size = Vector3.new(0.2, 0.75, 1.07), CFrame = CFrame.new(0, 0.05, 0), Color = C(250, 200, 60) }, m)
	end,
	BugbearFur = function(m)
		for i = 0, 4 do
			local p = part({ Name = "Tuft", Size = Vector3.new(0.5, 1.1, 0.5), CFrame = CFrame.new((i - 2) * 0.28, 0, 0) * CFrame.Angles(0, 0, math.rad((i - 2) * 12)), Color = C(150, 100, 65):Lerp(C(225, 190, 140), i % 2 * 0.3), Material = Enum.Material.Fabric }, m)
			Instance.new("SpecialMesh", p).MeshType = Enum.MeshType.Sphere
		end
	end,
}
for id, build in LOOT_ICONS do
	local old = iconFolder:FindFirstChild(id)
	if old then
		old:Destroy()
	end
	local m = Instance.new("Model")
	m.Name = id
	build(m)
	m:SetAttribute("GeneratedBy", GENERATED)
	m.Parent = iconFolder
end

---------------------------------------------------------------- 3-2. 장비 아이콘 (칸마다 모양, 단계마다 색)
local EQUIPMENT_ICONS = {
	Helmet = function(m, color, accent)
		local dome = part({ Name = "Dome", Size = Vector3.new(1.6, 1.3, 1.6), Color = color, Material = METAL }, m)
		Instance.new("SpecialMesh", dome).MeshType = Enum.MeshType.Sphere
		part({ Name = "Brim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 1.75, 1.75), CFrame = CFrame.new(0, -0.35, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = accent, Material = METAL }, m)
		part({ Name = "Crest", Size = Vector3.new(0.15, 0.5, 1.1), CFrame = CFrame.new(0, 0.6, 0), Color = accent, Material = METAL }, m)
	end,
	Armor = function(m, color, accent)
		part({ Name = "Chest", Size = Vector3.new(1.6, 1.7, 0.6), Color = color, Material = METAL }, m)
		for _, x in { 0.95, -0.95 } do
			local pad = part({ Name = "Shoulder", Size = Vector3.new(0.7, 0.45, 0.8), CFrame = CFrame.new(x, 0.7, 0), Color = accent, Material = METAL }, m)
			Instance.new("SpecialMesh", pad).MeshType = Enum.MeshType.Sphere
		end
		part({ Name = "Belt", Size = Vector3.new(1.65, 0.22, 0.65), CFrame = CFrame.new(0, -0.55, 0), Color = Color3.fromRGB(90, 60, 35), Material = Enum.Material.Leather }, m)
	end,
	Boots = function(m, color, accent)
		for _, x in { 0.45, -0.45 } do
			part({ Name = "Leg", Size = Vector3.new(0.55, 1.0, 0.6), CFrame = CFrame.new(x, 0.3, 0.1), Color = color, Material = METAL }, m)
			part({ Name = "Foot", Size = Vector3.new(0.6, 0.4, 1.0), CFrame = CFrame.new(x, -0.3, -0.15), Color = accent, Material = METAL }, m)
		end
	end,
	Gloves = function(m, color, accent)
		part({ Name = "Palm", Size = Vector3.new(0.9, 1.0, 0.4), Color = color, Material = Enum.Material.Leather }, m)
		for i = -1, 2 do
			part({ Name = "Finger", Size = Vector3.new(0.2, 0.5, 0.3), CFrame = CFrame.new(-0.3 + i * 0.22, 0.7, 0), Color = color, Material = Enum.Material.Leather }, m)
		end
		part({ Name = "Cuff", Size = Vector3.new(1.0, 0.35, 0.5), CFrame = CFrame.new(0, -0.6, 0), Color = accent, Material = METAL }, m)
	end,
	Necklace = function(m, color, accent)
		for i = 0, 11 do
			local angle = i / 12 * math.pi * 2
			part({ Name = "Bead", Shape = Enum.PartType.Ball, Size = Vector3.new(0.22, 0.22, 0.22), CFrame = CFrame.new(math.cos(angle) * 0.8, math.sin(angle) * 0.8 + 0.3, 0), Color = accent, Material = METAL }, m)
		end
		part({ Name = "Pendant", Size = Vector3.new(0.5, 0.65, 0.25), CFrame = CFrame.new(0, -0.65, 0) * CFrame.Angles(0, 0, math.rad(45)), Color = color, Material = Enum.Material.Neon }, m)
	end,
	Bracelet = function(m, color, accent)
		for i = 0, 13 do
			local angle = i / 14 * math.pi * 2
			part({ Name = "Link", Size = Vector3.new(0.3, 0.3, 0.45), CFrame = CFrame.new(math.cos(angle) * 0.7, math.sin(angle) * 0.7, 0) * CFrame.Angles(0, 0, angle), Color = if i % 3 == 0 then accent else color, Material = METAL }, m)
		end
	end,
}
for _, id in EquipmentDefs.Order do
	local def = EquipmentDefs.Items[id]
	local old = iconFolder:FindFirstChild(id)
	if old then
		old:Destroy()
	end
	local m = Instance.new("Model")
	m.Name = id
	local accent = if def.Tier >= 3 then GOLD else def.Color:Lerp(Color3.new(0, 0, 0), 0.3)
	EQUIPMENT_ICONS[def.Slot](m, def.Color, accent)
	m:SetAttribute("GeneratedBy", GENERATED)
	m.Parent = iconFolder
end

---------------------------------------------------------------- 4. 몹 생성 자리
local spawns = folder(workspace, "MobSpawns")
for _, child in spawns:GetChildren() do
	if child:GetAttribute("GeneratedBy") == GENERATED then
		child:Destroy()
	end
end

local town = CollectionService:GetTagged("TownArrival")[1]
local center = if town and town:IsA("BasePart") then town.Position elseif town and town:IsA("Model") then town:GetPivot().Position else Vector3.zero

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
params.FilterDescendantsInstances = { spawns, workspace:FindFirstChild("Ores"), workspace:FindFirstChild("OreSpawns"), workspace:FindFirstChild("Mobs") }

-- 몹이 설 수 있는 땅 (평평하고, 물·광산·마을 시설에서 떨어진 곳)
local function groundAt(x: number, z: number): Vector3?
	local result = workspace:Raycast(Vector3.new(x, center.Y + 400, z), Vector3.new(0, -800, 0), params)
	if not result or result.Normal.Y < 0.8 or result.Material == Enum.Material.Water then
		return nil
	end
	if not result.Instance:IsA("Terrain") and not (result.Instance:IsA("BasePart") and result.Instance.Size.X > 30 and result.Instance.Size.Z > 30) then
		return nil -- 지붕·가구 위
	end
	for _, zone in zones do
		if zone:IsA("BasePart") then
			local p = zone.CFrame:PointToObjectSpace(result.Position)
			local half = zone.Size / 2 + Vector3.new(6, 6, 6)
			if math.abs(p.X) < half.X and math.abs(p.Y) < half.Y and math.abs(p.Z) < half.Z then
				return nil
			end
		end
	end
	for _, position in avoid do
		if (position - result.Position).Magnitude < 25 then
			return nil
		end
	end
	return result.Position
end

local placed = {}
local summary = {}
for mobType, config in Config.Mobs do
	local made = 0
	for _ = 1, 400 do
		if made >= config.Count then
			break
		end
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = math.sqrt(random:NextNumber(config.MinDistance ^ 2, config.MaxDistance ^ 2))
		local ground = groundAt(center.X + math.cos(angle) * distance, center.Z + math.sin(angle) * distance)
		local free = ground ~= nil
		if ground then
			for _, other in placed do
				if (other - ground).Magnitude < 10 then
					free = false
					break
				end
			end
		end
		if free and ground then
			local p = part({ Name = `{mobType}Spawn`, Size = Vector3.new(2, 1, 2), CFrame = CFrame.new(ground + Vector3.new(0, 1, 0)), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false }, spawns)
			p:SetAttribute("MobType", mobType)
			p:SetAttribute("GeneratedBy", GENERATED)
			table.insert(placed, ground)
			made += 1
		end
	end
	table.insert(summary, `{mobType} {made}`)
end
print(`[BuildWeaponsAndMobs] 몹 생성 자리: {table.concat(summary, ", ")}`)

return true
