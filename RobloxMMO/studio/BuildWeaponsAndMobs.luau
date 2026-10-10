--!nocheck
-- Studio 제작 스크립트 2: 무기 18종(5·6단계 미스릴·오리하르콘 포함, 2026-10-09)·몹 5종 모델(슬라임·스켈레톤·좀비·케르베로스·사이클롭스),
-- 스켈레톤 궁수·거대 몬스터 3종(바위 골렘·서리 거인·베헤모스, 2026-10-10),
-- 바다 생물 3종(낙지·해파리·상어, 2026-10-09. 물고기·복어·황금 물고기는 2026-10-10 삭제), 아이콘, 몹 구역·생성 자리.
-- Rojo가 ServerStorage/StudioTools/BuildWeaponsAndMobs(ModuleScript)로 넣고, 서버(Main.server)가 게임을 시작할 때마다 실행한다.
-- 편집 상태에서 직접 실행하려면 명령 모음에: require(game.ServerStorage.StudioTools.BuildWeaponsAndMobs:Clone())
--
-- 만드는 것
--   1. 무기 Tool 18종 → ServerStorage/Templates/Pickaxes/<무기 Id> (곡괭이·도끼와 같은 폴더, PickaxeService가 지급)
--      돌 곡괭이 Tool의 쥐는 각도(Grip)를 그대로 쓰고 모양은 숨긴 뒤, 부품으로 칼·활·방망이를 짓는다.
--      좌표: x = 앞(곡괭이 머리 방향), y = 자루를 따라 위, 원점 = 손이 쥐는 점
--   2. 몹 모델 9종 + 바다 생물 3종 →ServerStorage/Templates/Mobs/<몹> (고정된 Root 부품 + 용접된 몸, 앞 = -Z, 기준점 = 발밑)
--   (2026-10-10: 몹 모델을 진짜처럼 다시 디자인 + 원소 장식 자리 Slot 속성, 원소 무기 4종·원소의 돌 아이콘 4종)
--   3. 아이콘 → ReplicatedStorage/ItemIcons (무기 18종 + 전리품 8종 + 바다 전리품·음식 8종 + 미스릴·오리하르콘괴 + 음식 3종 + 장비 40종 = 방어구 세트 7 × 4칸 + 장신구 12)
--   4. 몹 생성 자리 → Workspace/MobSpawns (속성 MobType·Zone·BossSpot). Config.MobZones의 구역(마을 둘레 부채꼴)마다
--      주인 몹 + Mix 확률로 이웃 단계 몹 + Extras(따로 두는 몹, 스켈레톤 궁수). 마을에서 멀수록 센 몹, 띠끼리 거리가 조금 겹친다.
--      땅이 모자라면(맵 끝 너머) Config.MobZoneLayout.FallbackShrink 배율로 거리를 당겨 다시 찾는다 (먼 거대 몬스터 구역)
--      마을 안전지대(TownArrival·ShopNPC 둘레 Config.MobAI.SafeZoneRadius) 바깥에만 둔다
--   5. 바다 생물 생성 자리 → Workspace/MobSpawns (속성 MobType·Zone·SwimDepth·Habitat, 떼는 School). 지형 물을 광선으로 찾아
--      Config.SeaZones 구역(낙지 바위·깊은 바다)마다 둔다. 물이 없으면 Output에 경고

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
-- 5·6단계 색 (2026-10-09): 미스릴 = 은빛 파랑 금속 + 파란 빛 / 오리하르콘 = 금빛 금속 + 주황 빛
local MITHRIL = C(175, 205, 240)
local MITHRIL_DARK = C(40, 50, 78)
local MITHRIL_GLOW = C(110, 185, 255)
local ORI = C(240, 182, 58)
local ORI_LIGHT = C(255, 222, 130)
local ORI_DARK = C(85, 35, 25)
local EMBER = C(255, 130, 30)

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
	-- range·brightness·rate는 안 주면 다이아몬드 값 (5·6단계는 더 밝게, 2026-10-10)
	function kit.glow(position: Vector3, color: Color3, range: number?, brightness: number?, rate: number?)
		local a = Instance.new("Attachment")
		a.Name = "Glow"
		a.Parent = handle
		a.WorldPosition = position
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = range or 8
		light.Brightness = brightness or 1.4
		light.Parent = a
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Color = ColorSequence.new(color)
		sparkles.LightEmission = 1
		sparkles.Size = NumberSequence.new(0.3, 0)
		sparkles.Lifetime = NumberRange.new(0.4, 0.9)
		sparkles.Rate = rate or 6
		sparkles.Speed = NumberRange.new(0.4, 1)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Parent = a
	end
	-- 오리하르콘 무기: 위로 날아오르는 불티 (2026-10-09)
	function kit.embers(position: Vector3, color: Color3, color2: Color3)
		local a = Instance.new("Attachment")
		a.Name = "Embers"
		a.Parent = handle
		a.WorldPosition = position
		local embers = Instance.new("ParticleEmitter")
		embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		embers.Color = ColorSequence.new(color, color2)
		embers.LightEmission = 1
		embers.Size = NumberSequence.new(0.25, 0)
		embers.Lifetime = NumberRange.new(0.5, 1)
		embers.Rate = 10
		embers.Speed = NumberRange.new(0.5, 1.5)
		embers.SpreadAngle = Vector2.new(180, 180)
		embers.Acceleration = Vector3.new(0, 4, 0)
		embers.Parent = a
	end
	-- 5·6단계 무기 둘레 기운 (2026-10-10): "Frost" = 미스릴, 천천히 떨어지는 파란 서리 반짝이 / "Flame" = 오리하르콘, 작은 금빛 불꽃 / "Earth"·"Wind" = 원소 무기
	-- spread: 날·머리를 따라 퍼지게 하는 길이(스터드, 자루 방향). 자루를 따라 긴 상자(Box) 모양으로 뿜는다
	function kit.aura(position: Vector3, style: string, spread: number?)
		local a = Instance.new("Attachment")
		a.Name = "Aura"
		a.Parent = handle
		a.WorldCFrame = CFrame.fromMatrix(position, forward, up)
		local e = Instance.new("ParticleEmitter")
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.LightEmission = 1
		e.SpreadAngle = Vector2.new(25, 25)
		if style == "Flame" then
			e.Texture = "rbxasset://textures/particles/fire_main.dds"
			e.Color = ColorSequence.new(C(255, 215, 110), C(255, 110, 25))
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
			e.Transparency = NumberSequence.new(0.35, 1)
			e.Lifetime = NumberRange.new(0.25, 0.5)
			e.Rate = 18
			e.Speed = NumberRange.new(0.6, 1.4)
			e.Acceleration = Vector3.new(0, 3, 0)
		elseif style == "Earth" then -- 대지의 망치 (2026-10-10): 흩날리는 흙먼지
			e.Texture = "rbxasset://textures/particles/smoke_main.dds"
			e.LightEmission = 0
			e.Color = ColorSequence.new(C(170, 135, 95), C(120, 95, 70))
			e.Size = NumberSequence.new(0.25, 0.6)
			e.Transparency = NumberSequence.new(0.55, 1)
			e.Lifetime = NumberRange.new(0.6, 1.1)
			e.Rate = 8
			e.Speed = NumberRange.new(0.2, 0.6)
			e.Acceleration = Vector3.new(0, -1.5, 0)
		elseif style == "Wind" then -- 질풍 검 (2026-10-10): 빠르게 휘도는 연둣빛 바람 조각
			e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			e.Color = ColorSequence.new(C(230, 255, 235), C(150, 255, 180))
			e.Size = NumberSequence.new(0.2, 0)
			e.Transparency = NumberSequence.new(0.2, 1)
			e.Lifetime = NumberRange.new(0.3, 0.6)
			e.Rate = 16
			e.Speed = NumberRange.new(2, 4)
			e.SpreadAngle = Vector2.new(180, 20)
			e.RotSpeed = NumberRange.new(200, 400)
		else
			e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			e.Color = ColorSequence.new(C(200, 235, 255), MITHRIL_GLOW)
			e.Size = NumberSequence.new(0.22, 0)
			e.Lifetime = NumberRange.new(0.7, 1.3)
			e.Rate = 10
			e.Speed = NumberRange.new(0.1, 0.4)
			e.Acceleration = Vector3.new(0, -1.2, 0)
		end
		e.Parent = a
		-- 상자 크기는 Attachment가 아니라 부모 부품 크기를 따르므로, 퍼질 길이만큼 투명한 작은 부품을 따로 둔다
		if spread and spread > 0 then
			local holder = part({
				Name = "AuraArea", Size = Vector3.new(0.3, spread, 0.3), Transparency = 1,
				CFrame = CFrame.fromMatrix(position, forward, up),
				Anchored = false, CanCollide = false, CanQuery = false, CanTouch = false, Massless = true,
			}, tool)
			weld(handle, holder)
			e.Parent = holder
			a:Destroy()
		end
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
-- 두 점(머리 좌표) 사이 가는 띠 판 (빛나는 날 테두리·룬 선, 2026-10-10)
local function strip(k, a: Vector2, b: Vector2, width: number, thickness: number, color: Color3, material: Enum.Material)
	local dir = (b - a).Unit
	local n = V(-dir.Y, dir.X) * (width / 2)
	k.plate({ a - n, b - n, b + n, a + n }, thickness, color, material)
end
-- 작은 마름모 (보석·룬)
local function diamond(k, center: Vector2, w: number, h: number, thickness: number, color: Color3, material: Enum.Material, fr: CFrame?)
	k.plate({ center + V(0, h), center + V(w, 0), center + V(0, -h), center + V(-w, 0) }, thickness, color, material, fr)
end

-- 미스릴 달빛 검 (2026-10-10 새로, 다이아몬드 대검의 약 1.25배): 길고 곧은 은빛 날 + 양쪽 파랗게 빛나는 날 테두리·가운데 룬 홈,
-- 위로 휜 초승달 코등이 두 겹(끝에 빛 구슬), 큰 파란 보석, 날 밑 작은 가시, 빛나는 마름모 손잡이 끝. 둘레에 서리 반짝이
WEAPONS.MithrilSword = function(k)
	k.rod("Grip", -1.1, 0.65, 0.3, MITHRIL_DARK, LEATHER)
	for i = 0, 4 do
		k.rod("Rune", -1.0 + i * 0.36, -1.0 + i * 0.36 + 0.06, 0.34, MITHRIL_GLOW, NEON)
	end
	k.rod("PommelCap", -1.3, -1.1, 0.4, MITHRIL, METAL)
	diamond(k, V(0, -1.6), 0.3, 0.38, 0.28, MITHRIL_GLOW, NEON)
	-- 코등이
	k.block("Guard", 0, 0.72, Vector3.new(0.8, 0.28, 0.38), MITHRIL, METAL)
	k.block("GuardGem", 0, 0.72, Vector3.new(0.46, 0.46, 0.46), MITHRIL_GLOW, NEON, Enum.PartType.Ball)
	for _, side in { 1, -1 } do
		local function f(list: { Vector2 }): { Vector2 }
			return if side > 0 then list else mirror(list)
		end
		k.plate(f({ V(0.25, 0.85), V(1.1, 1.05), V(1.3, 0.8), V(0.25, 0.6) }), 0.24, MITHRIL, METAL) -- 초승달 뿔
		k.plate(f({ V(1.1, 1.05), V(1.55, 1.6), V(1.3, 0.8) }), 0.2, MITHRIL, METAL)
		k.plate(f({ V(0.25, 0.64), V(1.05, 0.28), V(0.25, 0.5) }), 0.2, C(150, 180, 220), METAL) -- 아래 작은 뿔
		strip(k, V(1.12 * side, 1.08), V(1.55 * side, 1.6), 0.07, 0.26, MITHRIL_GLOW, NEON) -- 뿔 위 빛줄
		k.block("HornTip", 1.55 * side, 1.6, Vector3.new(0.2, 0.2, 0.2), MITHRIL_GLOW, NEON, Enum.PartType.Ball)
		k.plate(f({ V(0.28, 1.0), V(0.62, 1.25), V(0.29, 1.5) }), 0.12, MITHRIL, METAL) -- 날 밑 가시
	end
	-- 날
	k.plate({ V(-0.28, 0.85), V(0.28, 0.85), V(0.3, 4.7), V(0, 5.9), V(-0.3, 4.7) }, 0.13, C(205, 222, 245), METAL)
	for _, side in { 1, -1 } do
		strip(k, V(0.29 * side, 0.95), V(0.3 * side, 4.7), 0.07, 0.15, MITHRIL_GLOW, NEON)
		strip(k, V(0.3 * side, 4.7), V(0, 5.9), 0.07, 0.15, MITHRIL_GLOW, NEON)
	end
	k.plate({ V(-0.06, 1.0), V(0.06, 1.0), V(0.06, 4.6), V(-0.06, 4.6) }, 0.17, MITHRIL_GLOW, NEON) -- 룬 홈
	for _, y in { 1.6, 2.6, 3.6 } do
		diamond(k, V(0, y), 0.13, 0.2, 0.22, C(215, 240, 255), NEON) -- 홈 위 룬
	end
	k.trail(k.at(0, 5.9), k.at(0, 1.0), C(130, 200, 255), 0.32)
	k.glow(k.at(0, 3.2), C(130, 200, 255), 11, 2, 10)
	k.aura(k.at(0, 3.3), "Frost", 4.4)
end
-- 오리하르콘 태양 성검 (2026-10-10 새로, 다이아몬드 대검의 약 1.45배): 넓은 금빛 날 위에 한 겹 더 솟은 밝은 금 날 + 주황 불꽃 핵,
-- 빛나는 금 테두리, 불꽃 톱니 5쌍, 두 겹 날개 코등이(끝에 빛나는 불꽃 뿔), 가운데 햇살 원반·주황 태양 보석, 가시 달린 손잡이 끝. 금빛 불꽃·불티
WEAPONS.OrichalcumSword = function(k)
	local FLAME_GOLD = C(255, 205, 90)
	k.rod("Grip", -1.3, 0.75, 0.36, ORI_DARK, LEATHER)
	for i = 0, 4 do
		k.rod("Band", -1.2 + i * 0.42, -1.2 + i * 0.42 + 0.09, 0.4, ORI_LIGHT, METAL)
	end
	k.block("Pommel", 0, -1.5, Vector3.new(0.52, 0.52, 0.52), EMBER, NEON, Enum.PartType.Ball)
	k.plate({ V(-0.13, -1.68), V(0, -2.15), V(0.13, -1.68) }, 0.2, ORI_LIGHT, METAL) -- 손잡이 끝 가시
	for _, side in { 1, -1 } do
		k.plate({ V(0.2 * side, -1.4), V(0.58 * side, -1.52), V(0.2 * side, -1.62) }, 0.18, ORI_LIGHT, METAL)
	end
	-- 코등이: 가운데 받침 + 햇살 원반(앞뒤) + 두 겹 날개
	k.block("Guard", 0, 0.85, Vector3.new(1.1, 0.36, 0.46), ORI, METAL)
	k.block("Sun", 0, 0.85, Vector3.new(0.6, 0.6, 0.6), EMBER, NEON, Enum.PartType.Ball)
	for _, z in { 0.25, -0.25 } do
		k.block("SunDisk", 0, 0.85, Vector3.new(0.08, 0.95, 0.95), ORI_LIGHT, METAL, Enum.PartType.Cylinder, CFrame.Angles(0, math.rad(90), 0), z)
		local fr = k.Frame * CFrame.new(0, 0.85, z * 1.15)
		for i = 0, 5 do
			local a = i / 6 * math.pi * 2 + math.pi / 6
			local dir, side = V(math.cos(a), math.sin(a)), V(-math.sin(a), math.cos(a))
			k.plate({ dir * 0.44 + side * 0.08, dir * 0.72, dir * 0.44 - side * 0.08 }, 0.05, FLAME_GOLD, NEON, fr) -- 햇살
		end
	end
	for _, side in { 1, -1 } do
		local function f(list: { Vector2 }): { Vector2 }
			return if side > 0 then list else mirror(list)
		end
		k.plate(f({ V(0.4, 1.0), V(1.7, 1.6), V(1.95, 1.15), V(0.4, 0.7) }), 0.32, ORI, METAL) -- 위 날개
		k.plate(f({ V(0.4, 0.8), V(1.35, 0.55), V(1.5, 0.3), V(0.4, 0.58) }), 0.28, ORI_LIGHT, METAL) -- 아래 날개
		k.plate(f({ V(1.6, 1.45), V(2.0, 2.15), V(1.95, 1.2) }), 0.2, FLAME_GOLD, NEON) -- 날개 끝 불꽃 뿔
		strip(k, V(0.5 * side, 1.02), V(1.7 * side, 1.6), 0.07, 0.36, EMBER, NEON) -- 날개 위 빛줄
	end
	-- 날: 넓은 금 날 + 한 겹 더 솟은 밝은 금 날 + 주황 핵
	k.plate({ V(-0.62, 1.0), V(0.62, 1.0), V(0.66, 5.2), V(0, 6.7), V(-0.66, 5.2) }, 0.22, C(250, 205, 95), METAL)
	k.plate({ V(-0.36, 1.1), V(0.36, 1.1), V(0.38, 5.0), V(0, 6.1), V(-0.38, 5.0) }, 0.3, ORI_LIGHT, METAL)
	k.plate({ V(-0.08, 1.2), V(0.08, 1.2), V(0.08, 5.0), V(-0.08, 5.0) }, 0.36, EMBER, NEON)
	for _, side in { 1, -1 } do
		strip(k, V(0.63 * side, 1.1), V(0.66 * side, 5.2), 0.08, 0.24, FLAME_GOLD, NEON)
		strip(k, V(0.66 * side, 5.2), V(0, 6.7), 0.08, 0.24, FLAME_GOLD, NEON)
		for i = 0, 4 do
			local y = 1.3 + i * 0.75
			k.plate({ V(0.62 * side, y), V(1.0 * side, y + 0.35), V(0.64 * side, y + 0.6) }, 0.18, C(255, 175, 60), METAL) -- 불꽃 톱니
		end
	end
	k.trail(k.at(0, 6.7), k.at(0, 1.1), C(255, 190, 80), 0.36)
	k.glow(k.at(0, 3.4), C(255, 170, 70), 12, 2.2, 12)
	k.embers(k.at(0, 3.6), EMBER, ORI_LIGHT)
	k.aura(k.at(0, 3.8), "Flame", 5)
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
-- 미스릴 룬 전투망치 (2026-10-10 새로, 다이아몬드 철퇴의 약 1.25배): 가는 쇠 자루에 빛나는 룬 고리, 양 끝이 파랗게 빛나는 망치 머리 + 테,
-- 앞뒤 파란 보석, 위 창끝(빛나는 심), 머리 밑 날개 4장, 빛나는 손잡이 끝. 서리 반짝이
WEAPONS.MithrilHammer = function(k)
	k.rod("Shaft", -1.0, 3.0, 0.26, MITHRIL_DARK, METAL)
	k.rod("Grip", -0.9, 0.4, 0.32, MITHRIL_DARK:Lerp(C(0, 0, 0), 0.2), LEATHER)
	for _, y in { 1.2, 1.9, 2.6 } do
		k.rod("Rune", y, y + 0.07, 0.32, MITHRIL_GLOW, NEON)
	end
	k.rod("PommelCap", -1.15, -1.0, 0.36, MITHRIL, METAL)
	k.block("Pommel", 0, -1.3, Vector3.new(0.4, 0.4, 0.4), MITHRIL_GLOW, NEON, Enum.PartType.Ball)
	local hy = 3.4 -- 머리 가운데 높이
	k.block("HammerHead", 0, hy, Vector3.new(1.9, 0.8, 0.8), MITHRIL, METAL)
	k.block("Socket", 0, hy, Vector3.new(0.55, 1.05, 0.95), MITHRIL_DARK, METAL)
	for _, side in { 1, -1 } do
		k.block("Face", 1.0 * side, hy, Vector3.new(0.18, 1.0, 1.0), MITHRIL_GLOW, NEON) -- 빛나는 망치 면
		k.block("Band", 0.7 * side, hy, Vector3.new(0.1, 0.88, 0.88), C(150, 180, 220), METAL)
		k.block("Gem", 0, hy, Vector3.new(0.36, 0.36, 0.36), MITHRIL_GLOW, NEON, Enum.PartType.Ball, nil, 0.48 * side)
	end
	k.plate({ V(0, hy + 0.45), V(0.2, hy + 0.9), V(0, hy + 1.6), V(-0.2, hy + 0.9) }, 0.2, C(205, 222, 245), METAL) -- 위 창끝
	diamond(k, V(0, hy + 0.95), 0.08, 0.35, 0.26, MITHRIL_GLOW, NEON)
	for i = 0, 3 do
		local fr = k.Frame * CFrame.Angles(0, i / 4 * math.pi * 2 + math.pi / 4, 0)
		k.plate({ V(0.2, hy - 0.85), V(0.62, hy - 0.6), V(0.5, hy - 0.4), V(0.2, hy - 0.45) }, 0.1, MITHRIL, METAL, fr) -- 머리 밑 날개
	end
	k.trail(k.at(1.0, hy + 0.5), k.at(1.0, hy - 0.5), C(130, 200, 255), 0.3)
	k.glow(k.at(0, hy), C(130, 200, 255), 11, 2, 10)
	k.aura(k.at(0, hy), "Frost", 1.2)
end
-- 오리하르콘 태양 거인망치 (2026-10-10 새로, 다이아몬드 철퇴의 약 1.45배): 굵은 금 고리 자루, 커다란 금빛 머리 + 밝은 금 끝 판 + 주황 빛 면,
-- 앞뒤 햇살 원반·태양 보석, 머리 위 왕관 가시 5개(끝마다 불씨 보석), 가시 달린 손잡이 끝. 금빛 불꽃·불티
WEAPONS.OrichalcumHammer = function(k)
	local FLAME_GOLD = C(255, 205, 90)
	k.rod("Shaft", -1.2, 3.4, 0.36, ORI_DARK, METAL)
	k.rod("Grip", -1.1, 0.4, 0.42, ORI_DARK:Lerp(C(0, 0, 0), 0.2), LEATHER)
	for i = 0, 5 do
		local y = -1.0 + i * 0.6
		k.rod("Band", y, y + 0.1, 0.46, ORI_LIGHT, METAL)
	end
	k.block("Pommel", 0, -1.45, Vector3.new(0.58, 0.58, 0.58), EMBER, NEON, Enum.PartType.Ball)
	k.plate({ V(-0.14, -1.65), V(0, -2.1), V(0.14, -1.65) }, 0.22, ORI_LIGHT, METAL) -- 손잡이 끝 가시
	k.rod("Collar", 3.0, 3.25, 0.7, ORI_LIGHT, METAL)
	local hy = 3.95 -- 머리 가운데 높이
	k.block("HammerHead", 0, hy, Vector3.new(2.6, 1.3, 1.3), ORI, METAL)
	for _, side in { 1, -1 } do
		k.block("Cap", 1.35 * side, hy, Vector3.new(0.26, 1.55, 1.55), ORI_LIGHT, METAL)
		k.block("Face", 1.5 * side, hy, Vector3.new(0.08, 1.0, 1.0), EMBER, NEON) -- 주황으로 빛나는 망치 면
		k.block("Rim", 0.85 * side, hy, Vector3.new(0.12, 1.38, 1.38), ORI_DARK, METAL)
		-- 옆면(앞뒤) 햇살 원반 + 태양 보석
		k.block("SunDisk", 0, hy, Vector3.new(0.08, 1.0, 1.0), ORI_LIGHT, METAL, Enum.PartType.Cylinder, CFrame.Angles(0, math.rad(90), 0), 0.66 * side)
		k.block("Sun", 0, hy, Vector3.new(0.56, 0.56, 0.56), EMBER, NEON, Enum.PartType.Ball, nil, 0.68 * side)
		local fr = k.Frame * CFrame.new(0, hy, 0.72 * side)
		for i = 0, 5 do
			local a = i / 6 * math.pi * 2
			local dir, across = V(math.cos(a), math.sin(a)), V(-math.sin(a), math.cos(a))
			k.plate({ dir * 0.34 + across * 0.07, dir * 0.6, dir * 0.34 - across * 0.07 }, 0.04, FLAME_GOLD, NEON, fr) -- 햇살
		end
	end
	for _, x in { -0.9, -0.45, 0, 0.45, 0.9 } do
		local h = if x == 0 then 0.85 elseif math.abs(x) < 0.5 then 0.6 else 0.45
		k.plate({ V(x - 0.17, hy + 0.62), V(x, hy + 0.62 + h), V(x + 0.17, hy + 0.62) }, 0.34, ORI_LIGHT, METAL) -- 왕관 가시
		k.block("CrownGem", x, hy + 0.62 + h, Vector3.new(0.16, 0.16, 0.16), EMBER, NEON, Enum.PartType.Ball)
	end
	k.trail(k.at(1.45, hy + 0.7), k.at(1.45, hy - 0.7), C(255, 190, 80), 0.34)
	k.glow(k.at(0, hy), C(255, 170, 70), 13, 2.4, 12)
	k.embers(k.at(0, hy + 0.6), EMBER, ORI_LIGHT)
	k.aura(k.at(0, hy), "Flame", 1.4)
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
-- 활대와 같은 곡선을 앞(+x)으로 dx만큼 옮겨 가는 원통으로 긋는다 (빛나는 활대 줄, 2026-10-10). t0~t1 = 가운데(0)~끝(1) 중 그릴 구간
local function bowLine(k, half: number, bend: number, recurve: number, dx: number, d: number, color: Color3, material: Enum.Material, t0: number, t1: number)
	local function point(t: number): Vector2
		local a = math.abs(t)
		return V(-bend * a * a + recurve * math.max(a - 0.75, 0) ^ 2 * 16 + dx, t * half)
	end
	local steps = 6
	for side = -1, 1, 2 do
		for i = 0, steps - 1 do
			local a0 = t0 + (t1 - t0) * i / steps
			local a1 = t0 + (t1 - t0) * (i + 1) / steps
			k.segment("LimbGlow", point(side * a0), point(side * a1), d, color, material)
		end
	end
end
-- 미스릴 달빛 활 (2026-10-10 새로, 다이아몬드 활의 약 1.25배): 길고 가는 은빛 리커브 + 앞면을 따라 파랗게 빛나는 줄,
-- 손잡이 앞 빛나는 초승달, 두 겹 잎 날개, 활 끝 빛나는 작은 칼날·구슬, 룬 고리. 서리 반짝이
WEAPONS.MithrilBow = function(k)
	local S = 1.5
	local half, bend, recurve = 2.2 * S, 0.55 * S, 0.3 * S
	local top, bottom = bowLimbs(k, half, bend, recurve, 0.15 * S, 0.09 * S, MITHRIL, METAL)
	bowLine(k, half, bend, recurve, 0.09 * S, 0.05 * S, MITHRIL_GLOW, NEON, 0.12, 0.88)
	k.rod("Grip", -0.3 * S, 0.3 * S, 0.27 * S, MITHRIL_DARK, LEATHER)
	k.rod("Rune", 0.33 * S, 0.38 * S, 0.24 * S, MITHRIL_GLOW, NEON)
	k.rod("Rune", -0.38 * S, -0.33 * S, 0.24 * S, MITHRIL_GLOW, NEON)
	for _, y in { 1, -1 } do
		k.plate({ V(0, 0.42 * y * S), V(0.45 * S, 0.85 * y * S), V(-0.1 * S, 1.2 * y * S) }, 0.1 * S, C(205, 222, 245), METAL) -- 잎 날개
		k.plate({ V(-0.12 * S, 1.05 * y * S), V(0.28 * S, 1.45 * y * S), V(-0.22 * S, 1.65 * y * S) }, 0.08 * S, C(150, 180, 220), METAL) -- 작은 잎 날개
		local tip = if y > 0 then top else bottom
		k.plate({ tip + V(-0.04 * S, -0.12 * y * S), tip + V(0.42 * S, 0.22 * y * S), tip + V(0.05 * S, 0.22 * y * S) }, 0.06 * S, MITHRIL_GLOW, NEON) -- 끝 칼날
		k.block("Tip", tip.X, tip.Y, Vector3.new(0.16, 0.16, 0.16) * S, MITHRIL_GLOW, NEON, Enum.PartType.Ball)
	end
	-- 손잡이 앞 초승달
	local steps = 4
	for i = 0, steps - 1 do
		local a0, a1 = math.rad(-70 + 140 * i / steps), math.rad(-70 + 140 * (i + 1) / steps)
		local function outer(a: number): Vector2
			return V(0.05 + 0.55 * math.cos(a), 0.55 * math.sin(a)) * S
		end
		local function inner(a: number): Vector2
			return V(0.2 + 0.35 * math.cos(a), 0.42 * math.sin(a)) * S
		end
		k.plate({ inner(a0), outer(a0), outer(a1), inner(a1) }, 0.08 * S, MITHRIL_GLOW, NEON)
	end
	bowString(k, top, bottom, C(150, 215, 255))
	k.glow(k.at(0, 0), C(130, 200, 255), 11, 2, 10)
	k.aura(k.at(0, 0), "Frost", 2 * half * 0.8)
end
-- 오리하르콘 태양궁 (2026-10-10 새로, 다이아몬드 활의 약 1.45배): 굵은 금빛 리커브 + 앞면 주황 불꽃 줄, 두 겹 금 날개,
-- 앞에 햇살 8갈래가 뻗은 태양 원반·주황 보석, 활 끝 불꽃 뿔·불씨 보석. 금빛 불꽃·불티
WEAPONS.OrichalcumBow = function(k)
	local S = 1.7
	local FLAME_GOLD = C(255, 205, 90)
	local half, bend, recurve = 2.2 * S, 0.62 * S, 0.3 * S
	local top, bottom = bowLimbs(k, half, bend, recurve, 0.17 * S, 0.09 * S, ORI, METAL)
	bowLine(k, half, bend, recurve, 0.1 * S, 0.05 * S, EMBER, NEON, 0.12, 0.9)
	k.rod("Grip", -0.3 * S, 0.3 * S, 0.3 * S, ORI_DARK, LEATHER)
	k.rod("Ring", 0.32 * S, 0.38 * S, 0.33 * S, ORI_LIGHT, METAL)
	k.rod("Ring", -0.38 * S, -0.32 * S, 0.33 * S, ORI_LIGHT, METAL)
	for _, y in { 1, -1 } do
		k.plate({ V(-0.05 * S, 0.35 * y * S), V(0.6 * S, 0.8 * y * S), V(0.35 * S, 1.25 * y * S), V(-0.2 * S, 1.0 * y * S) }, 0.12 * S, ORI_LIGHT, METAL) -- 큰 날개
		k.plate({ V(-0.18 * S, 1.1 * y * S), V(0.4 * S, 1.45 * y * S), V(0.15 * S, 1.8 * y * S), V(-0.3 * S, 1.6 * y * S) }, 0.1 * S, ORI, METAL) -- 위 날개
		local tip = if y > 0 then top else bottom
		k.plate({ tip + V(-0.1 * S, 0), tip + V(0.12 * S, 0), tip + V(0.06 * S, 0.45 * y * S) }, 0.08 * S, FLAME_GOLD, NEON) -- 불꽃 뿔
		k.block("Tip", tip.X, tip.Y, Vector3.new(0.17, 0.17, 0.17) * S, EMBER, NEON, Enum.PartType.Ball)
	end
	-- 앞의 태양 원반 + 햇살 (원반은 앞을 본다: 햇살 판은 자루·두께 방향 평면)
	k.block("SunRing", 0.28 * S, 0, Vector3.new(0.12, 0.8, 0.8) * S, ORI_LIGHT, METAL, Enum.PartType.Cylinder)
	k.block("Sun", 0.32 * S, 0, Vector3.new(0.44, 0.44, 0.44) * S, EMBER, NEON, Enum.PartType.Ball)
	local fr = k.Frame * CFrame.new(0.3 * S, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local dir, across = V(math.cos(a), math.sin(a)), V(-math.sin(a), math.cos(a))
		k.plate({ (dir * 0.38 + across * 0.06) * S, dir * 0.72 * S, (dir * 0.38 - across * 0.06) * S }, 0.05 * S, FLAME_GOLD, NEON, fr)
	end
	bowString(k, top, bottom, C(255, 220, 150))
	k.glow(k.at(0.3 * S, 0), C(255, 170, 70), 13, 2.4, 12)
	k.embers(k.at(0.3 * S, 0), EMBER, ORI_LIGHT)
	k.aura(k.at(0, 0), "Flame", 2 * half * 0.8)
end

-- 원소 무기 4종 (2026-10-10): 원소 보스만 아주 가끔 준다 (Config.MobBoss.ElementLoot). 5단계 크기, 원소 빛·입자
-- 불꽃 검: 검게 그을린 강철 날 + 녹아 빛나는 심 + 양쪽 물결 불꽃 톱니(달아오른 날끝), 불꽃 갈래 코등이·빨간 보석. 불꽃·불티
WEAPONS.FlameSword = function(k)
	local STEEL = C(48, 36, 34)
	local MOLTEN = C(255, 110, 30)
	local HOT = C(255, 200, 90)
	k.rod("Grip", -1.05, 0.62, 0.3, C(40, 20, 15), LEATHER)
	for i = 0, 3 do
		k.rod("Wrap", -0.95 + i * 0.42, -0.95 + i * 0.42 + 0.07, 0.34, C(150, 40, 25), METAL)
	end
	k.block("Pommel", 0, -1.25, Vector3.new(0.44, 0.44, 0.44), MOLTEN, NEON, Enum.PartType.Ball)
	k.plate({ V(-0.12, -1.42), V(0, -1.85), V(0.12, -1.42) }, 0.18, STEEL, METAL)
	k.block("Guard", 0, 0.72, Vector3.new(0.95, 0.3, 0.42), STEEL, METAL)
	k.block("Gem", 0, 0.72, Vector3.new(0.4, 0.4, 0.4), C(255, 60, 30), NEON, Enum.PartType.Ball)
	for _, side in { 1, -1 } do
		local function f(list: { Vector2 }): { Vector2 }
			return if side > 0 then list else mirror(list)
		end
		k.plate(f({ V(0.4, 0.85), V(1.15, 1.35), V(0.9, 0.75), V(0.4, 0.6) }), 0.26, STEEL, METAL)
		k.plate(f({ V(0.9, 0.95), V(1.3, 1.75), V(1.12, 0.95) }), 0.2, MOLTEN, NEON) -- 코등이 끝 불꽃
		k.plate(f({ V(0.4, 0.62), V(0.95, 0.35), V(0.4, 0.5) }), 0.2, STEEL, METAL)
	end
	k.plate({ V(-0.34, 0.85), V(0.34, 0.85), V(0.3, 4.9), V(0, 5.9), V(-0.3, 4.9) }, 0.14, STEEL, METAL)
	k.plate({ V(-0.07, 0.95), V(0.07, 0.95), V(0.06, 4.8), V(0, 5.3), V(-0.06, 4.8) }, 0.2, MOLTEN, NEON) -- 녹아 빛나는 심
	for _, side in { 1, -1 } do
		for i = 0, 5 do
			local y = 1.0 + i * 0.66
			k.plate({ V(0.32 * side, y), V(0.62 * side, y + 0.42), V(0.3 * side, y + 0.62) }, 0.12, STEEL, METAL) -- 물결 불꽃 톱니
			strip(k, V(0.34 * side, y + 0.06), V(0.6 * side, y + 0.42), 0.05, 0.16, HOT, NEON) -- 달아오른 날끝
		end
	end
	k.trail(k.at(0, 5.9), k.at(0, 1.0), C(255, 120, 40), 0.32)
	k.glow(k.at(0, 3.2), C(255, 110, 40), 12, 2.2, 12)
	k.embers(k.at(0, 3.4), MOLTEN, HOT)
	k.aura(k.at(0, 3.3), "Flame", 4.6)
end
-- 서리 활: 얼음 리커브 활대 + 앞면 하늘색 빛 줄, 위아래 얼음 수정 날개, 활 끝·손잡이 앞 빛나는 수정. 서리 반짝이 (S 1.5)
WEAPONS.FrostBow = function(k)
	local S = 1.5
	local half = 2.2 * S
	local ICE_C = C(170, 225, 250)
	local GLOW_C = C(150, 230, 255)
	local top, bottom = bowLimbs(k, half, 0.55 * S, 0.3 * S, 0.2 * S, 0.1 * S, ICE_C, Enum.Material.Ice)
	bowLine(k, half, 0.55 * S, 0.3 * S, 0.07 * S, 0.05 * S, GLOW_C, NEON, 0.1, 0.95)
	k.rod("Grip", -0.3 * S, 0.3 * S, 0.3 * S, C(70, 130, 190), LEATHER)
	for _, y in { 0.32, -0.38 } do
		k.rod("Ring", y * S, (y + 0.06) * S, 0.34 * S, C(220, 240, 255), METAL)
	end
	for _, y in { 1, -1 } do
		k.plate({ V(0, 0.45 * y * S), V(0.55 * S, 0.75 * y * S), V(0.05 * S, 1.05 * y * S) }, 0.1 * S, C(200, 240, 255), GLASS)
		k.plate({ V(-0.1 * S, 1.15 * y * S), V(0.35 * S, 1.55 * y * S), V(-0.15 * S, 1.6 * y * S) }, 0.08 * S, ICE_C, GLASS)
		local tip = if y > 0 then top else bottom
		diamond(k, tip + V(0, 0.15 * y * S), 0.08 * S, 0.22 * S, 0.1 * S, GLOW_C, NEON)
	end
	diamond(k, V(0.2 * S, 0), 0.12 * S, 0.2 * S, 0.18 * S, GLOW_C, NEON) -- 손잡이 앞 수정
	bowString(k, top, bottom, C(210, 245, 255))
	k.glow(k.at(0.2 * S, 0), C(150, 220, 255), 11, 2, 10)
	k.aura(k.at(0, 0), "Frost", 2 * half * 0.8)
end
-- 대지의 망치: 거친 바위 머리(덧붙은 돌덩이) + 현무암 양 면 + 청동 띠, 앞뒤 호박빛 금·보석, 위 돌 가시, 청동 띠 나무 자루. 흙먼지
WEAPONS.EarthHammer = function(k)
	local ROCK_C = C(115, 88, 62)
	local DARK_R = C(70, 55, 42)
	local BRONZE = C(170, 120, 60)
	local AMBER = C(255, 170, 60)
	k.rod("Shaft", -1.1, 3.2, 0.32, C(80, 55, 35), WOOD)
	k.rod("Grip", -1.0, 0.4, 0.38, C(60, 40, 28), LEATHER)
	for _, y in { 0.9, 1.7, 2.5 } do
		k.rod("Band", y, y + 0.1, 0.38, BRONZE, METAL)
	end
	k.block("Pommel", 0, -1.3, Vector3.new(0.5, 0.42, 0.5), DARK_R, Enum.Material.Slate)
	local hy = 3.7
	k.block("Head", 0, hy, Vector3.new(2.3, 1.15, 1.15), ROCK_C, Enum.Material.Slate)
	k.block("Chunk", 0.55, hy + 0.45, Vector3.new(0.8, 0.5, 0.9), DARK_R, Enum.Material.Slate, nil, CFrame.Angles(0.3, 0.2, 0.4))
	k.block("Chunk", -0.6, hy - 0.4, Vector3.new(0.7, 0.5, 0.8), DARK_R, Enum.Material.Slate, nil, CFrame.Angles(-0.2, 0.5, -0.3))
	for _, side in { 1, -1 } do
		k.block("Face", 1.2 * side, hy, Vector3.new(0.22, 1.25, 1.25), DARK_R, Enum.Material.Basalt)
		k.block("Band", 0.75 * side, hy, Vector3.new(0.14, 1.25, 1.25), BRONZE, METAL)
		k.block("Crack", 0.3 * side, hy, Vector3.new(0.7, 0.07, 0.07), AMBER, NEON, nil, CFrame.Angles(0, 0, math.rad(25 * side)), 0.59)
		k.block("Crack", -0.2 * side, hy + 0.1, Vector3.new(0.5, 0.06, 0.06), AMBER, NEON, nil, CFrame.Angles(0, 0, math.rad(-35 * side)), -0.59)
		k.block("Gem", 0, hy, Vector3.new(0.34, 0.34, 0.34), AMBER, NEON, Enum.PartType.Ball, nil, 0.6 * side)
	end
	k.plate({ V(-0.25, hy + 0.55), V(0, hy + 1.25), V(0.25, hy + 0.55) }, 0.4, DARK_R, Enum.Material.Slate) -- 위 돌 가시
	k.trail(k.at(1.2, hy + 0.6), k.at(1.2, hy - 0.6), C(230, 170, 90), 0.3)
	k.glow(k.at(0, hy), AMBER, 11, 1.8, 6)
	k.aura(k.at(0, hy), "Earth", 1.4)
end
-- 질풍 검: 뒤로 휜 가늘고 긴 은빛 곡도(마디 8개) + 연둣빛 날끝, 깃털 날개 코등이, 옥빛 손잡이·빛 구슬·술. 휘도는 바람
WEAPONS.WindSword = function(k)
	local SILVER = C(215, 235, 225)
	local JADE = C(70, 170, 120)
	local GLOW_C = C(160, 255, 190)
	k.rod("Grip", -1.0, 0.6, 0.26, C(40, 70, 55), LEATHER)
	for i = 0, 4 do
		k.rod("Wrap", -0.92 + i * 0.34, -0.92 + i * 0.34 + 0.05, 0.3, JADE, METAL)
	end
	k.block("Pommel", 0, -1.18, Vector3.new(0.3, 0.3, 0.3), GLOW_C, NEON, Enum.PartType.Ball)
	k.segment("Tassel", V(0, -1.25), V(-0.25, -1.9), 0.06, GLOW_C, Enum.Material.Fabric)
	k.block("Guard", 0, 0.68, Vector3.new(0.6, 0.22, 0.32), JADE, METAL)
	for _, side in { 1, -1 } do
		local function f(list: { Vector2 }): { Vector2 }
			return if side > 0 then list else mirror(list)
		end
		for i = 0, 2 do
			k.plate(f({ V(0.25, 0.7 - i * 0.05), V(0.85 + i * 0.18, 0.95 - i * 0.25), V(0.75 + i * 0.15, 0.62 - i * 0.2) }), 0.1, if i == 0 then SILVER else JADE, METAL) -- 깃털 날개
		end
	end
	local function edge(t: number): (number, number) -- 날 가운데 (x 오프셋, y), t = 0 밑동 ~ 1 끝
		return -0.55 * t * t, 0.8 + t * 4.6
	end
	local w0 = 0.26
	for i = 0, 7 do
		local t0, t1 = i / 8, (i + 1) / 8
		local x0, y0 = edge(t0)
		local x1, y1 = edge(t1)
		local wa, wb = w0 * (1 - t0 * 0.35), w0 * (1 - t1 * 0.35)
		k.plate({ V(x0 - wa * 0.5, y0), V(x0 + wa * 0.5, y0), V(x1 + wb * 0.5, y1), V(x1 - wb * 0.5, y1) }, 0.1, SILVER, METAL)
		strip(k, V(x0 + wa * 0.5, y0), V(x1 + wb * 0.5, y1), 0.05, 0.13, GLOW_C, NEON) -- 바람 날끝
	end
	local xe, ye = edge(1)
	k.plate({ V(xe - w0 * 0.33, ye), V(xe + w0 * 0.33, ye), V(xe - 0.25, ye + 0.7) }, 0.1, SILVER, METAL) -- 끝
	k.trail(k.at(xe, ye + 0.6), k.at(0, 1.0), C(170, 255, 200), 0.3)
	k.glow(k.at(-0.2, 3.0), GLOW_C, 10, 1.8, 8)
	k.aura(k.at(-0.2, 3.0), "Wind", 4.4)
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
-- 2026-10-10 다시 디자인 (사용자 요청 "싸 보이고 귀여움 → 진짜처럼"): 큰 눈·볼터치를 빼고 관절·근육·이빨·발톱·갑옷 조각을 더했다.
-- 부품 속성 Slot = 원소 보스 장식 자리 (서버 MobService.decorateElement): Head 머리 / Weapon 무기·주먹 / Core 빛나는 몸 / Armor 장식 붙일 몸통·어깨 / Eye 눈
-- 부품 속성 BossOnly = true면 보스일 때만 남는다 (케르베로스 셋째 머리). kit.group(태그, 함수) 안에서 만든 부품에 태그가 붙는다
local SLATE = Enum.Material.Slate
local FABRIC = Enum.Material.Fabric
local SMOOTH = Enum.Material.SmoothPlastic
local LIMESTONE = Enum.Material.Limestone
local CORRODED = Enum.Material.CorrodedMetal
local BASALT = Enum.Material.Basalt
local ICE = Enum.Material.Ice
local function newMob(name: string)
	local model = Instance.new("Model")
	model.Name = name
	local root = part({ Name = "Root", Size = Vector3.new(1.5, 0.2, 1.5), CFrame = CFrame.new(0, 0.1, 0), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false }, model)
	root.PivotOffset = CFrame.new(0, -0.1, 0) -- 기준점 = 발밑
	model.PrimaryPart = root
	local kit = { Model = model, Root = root, Tags = nil }
	local function tag(p: Instance)
		if kit.Tags then
			for key, value in kit.Tags do
				p:SetAttribute(key, value)
			end
		end
	end
	local function add(p: BasePart)
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		weld(root, p)
		tag(p)
		return p
	end
	-- 둥근 타원체 (SpecialMesh 구): 근육·살·바위 덩어리
	function kit.blob(partName: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material?, transparency: number?, rotation: CFrame?)
		local p = part({ Name = partName, Size = size, CFrame = CFrame.new(position) * (rotation or CFrame.new()), Color = color, Material = material or SMOOTH, Transparency = transparency or 0 }, model)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
		return add(p)
	end
	function kit.box(partName: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?)
		return add(part({ Name = partName, Size = size, CFrame = cframe, Color = color, Material = material or SMOOTH }, model))
	end
	function kit.ball(partName: string, diameter: number, position: Vector3, color: Color3, material: Enum.Material?)
		return add(part({ Name = partName, Shape = Enum.PartType.Ball, Size = Vector3.new(diameter, diameter, diameter), CFrame = CFrame.new(position), Color = color, Material = material or SMOOTH }, model))
	end
	-- 두 점 사이 원통 (팔다리·뼈)
	function kit.limb(partName: string, a: Vector3, b: Vector3, diameter: number, color: Color3, material: Enum.Material?)
		local length = (b - a).Magnitude
		return add(part({
			Name = partName, Shape = Enum.PartType.Cylinder, Size = Vector3.new(length + diameter * 0.4, diameter, diameter),
			CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0), Color = color, Material = material or SMOOTH,
		}, model))
	end
	-- 납작한 원판 (원통, cframe의 X축이 판의 축)
	function kit.disc(partName: string, thickness: number, diameter: number, cframe: CFrame, color: Color3, material: Enum.Material?)
		return add(part({ Name = partName, Shape = Enum.PartType.Cylinder, Size = Vector3.new(thickness, diameter, diameter), CFrame = cframe, Color = color, Material = material or SMOOTH }, model))
	end
	-- 세 점 삼각형 판 (쐐기 두 개). 태그도 붙인다
	function kit.tri(a: Vector3, b: Vector3, c: Vector3, thickness: number, color: Color3, material: Enum.Material?)
		local before = {}
		for _, child in model:GetChildren() do
			before[child] = true
		end
		triangle(model, a, b, c, thickness, color, material or SMOOTH, root)
		for _, child in model:GetChildren() do
			if not before[child] then
				tag(child)
			end
		end
	end
	-- 뾰족한 가시·이빨·발톱: 밑동 base → 끝 tip, 밑동 너비 width. side = 너비 방향(안 주면 알아서), cross면 십자로 두 장(입체)
	function kit.spike(base: Vector3, tip: Vector3, width: number, color: Color3, material: Enum.Material?, cross: boolean?, side: Vector3?)
		local dir = tip - base
		if dir.Magnitude < 0.01 then
			return
		end
		dir = dir.Unit
		local s1: Vector3
		if side then
			s1 = side - dir * side:Dot(dir)
		else
			s1 = dir:Cross(if math.abs(dir.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis)
		end
		if s1.Magnitude < 0.01 then
			s1 = dir:Cross(Vector3.zAxis)
		end
		s1 = s1.Unit
		local thick = math.max(width * 0.3, 0.03)
		kit.tri(base - s1 * width / 2, base + s1 * width / 2, tip, thick, color, material)
		if cross then
			local s2 = dir:Cross(s1).Unit
			kit.tri(base - s2 * width / 2, base + s2 * width / 2, tip, thick, color, material)
		end
	end
	-- 원소 보스 장식 자리 표시
	function kit.slot(p: BasePart, slotName: string): BasePart
		p:SetAttribute("Slot", slotName)
		return p
	end
	-- 이 안에서 만든 부품에 태그(속성)를 붙인다 (예: { BossOnly = true })
	function kit.group(tags: { [string]: any }, build: () -> ())
		local previous = kit.Tags
		kit.Tags = tags
		build()
		kit.Tags = previous
	end
	return kit
end

local MOBS = {}

-- 슬라임: 녹아내리는 독성 점액 덩어리. 반투명 몸 속에 녹다 만 해골·뼈·녹슨 칼날·동전·기포, 울퉁불퉁한 혹,
-- 바닥에 퍼진 점액 웅덩이·흘러내리는 방울, 몸 깊숙이 비대칭으로 빛나는 작은 눈 두 점, 벌어진 입 구멍 (높이 약 2.5 × Scale 0.9)
MOBS.Slime = function(k)
	local ooze = C(100, 185, 70)
	local deep = C(55, 120, 45)
	local bone = C(200, 190, 160)
	k.slot(k.blob("Body", Vector3.new(3.1, 2.2, 3.0), Vector3.new(0, 1.15, 0), ooze, GLASS, 0.35), "Core")
	k.blob("Lump", Vector3.new(1.6, 1.3, 1.5), Vector3.new(0.7, 1.75, 0.35), ooze, GLASS, 0.35)
	k.blob("Lump", Vector3.new(1.4, 1.1, 1.3), Vector3.new(-0.8, 1.55, 0.5), ooze, GLASS, 0.35)
	k.blob("Lump", Vector3.new(1.2, 0.9, 1.2), Vector3.new(0.1, 2.05, -0.35), ooze, GLASS, 0.35)
	k.blob("Puddle", Vector3.new(4.0, 0.35, 3.8), Vector3.new(0, 0.15, 0.05), deep, GLASS, 0.3)
	k.blob("Nucleus", Vector3.new(1.3, 1.0, 1.2), Vector3.new(0.1, 1.15, 0.3), C(40, 90, 35), SMOOTH, 0.25)
	-- 몸 속에 녹다 만 것들
	k.ball("SkullBit", 0.55, Vector3.new(-0.55, 0.9, 0.35), bone)
	for _, x in { -0.64, -0.46 } do
		k.ball("SkullHole", 0.15, Vector3.new(x, 0.95, 0.1), C(40, 40, 30))
	end
	k.limb("BoneBit", Vector3.new(0.3, 0.6, 0.6), Vector3.new(0.95, 0.85, 0.1), 0.12, bone)
	k.limb("BoneBit", Vector3.new(-0.2, 1.5, 0.7), Vector3.new(0.35, 1.3, 0.9), 0.09, bone)
	k.disc("Coin", 0.05, 0.3, CFrame.new(0.6, 1.3, 0.55) * CFrame.Angles(0.5, 0.3, 1.1), C(150, 120, 60), CORRODED)
	k.box("RustBlade", Vector3.new(0.08, 0.7, 0.18), CFrame.new(-0.3, 1.6, -0.1) * CFrame.Angles(0.4, 0.2, 0.9), C(110, 80, 60), CORRODED)
	for i, p in { Vector3.new(0.4, 1.9, -0.6), Vector3.new(-0.9, 1.2, -0.5), Vector3.new(0.9, 1.0, -0.3), Vector3.new(-0.2, 0.55, -0.9), Vector3.new(0.5, 2.3, 0.2), Vector3.new(-0.6, 2.0, -0.1) } do
		local bubble = k.ball("Bubble", 0.1 + (i % 3) * 0.06, p, C(205, 255, 185), GLASS)
		bubble.Transparency = 0.4
	end
	-- 비대칭 작은 눈 (깊은 곳에서 노랗게) + 벌어진 입 구멍
	k.slot(k.ball("Eye", 0.2, Vector3.new(0.38, 1.55, -1.25), C(230, 255, 90), NEON), "Eye")
	k.slot(k.ball("Eye", 0.14, Vector3.new(-0.32, 1.47, -1.3), C(230, 255, 90), NEON), "Eye")
	k.blob("Maw", Vector3.new(0.8, 0.35, 0.3), Vector3.new(0, 0.95, -1.42), C(25, 50, 20), SMOOTH)
	-- 흘러내리는 방울
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2 + 0.4
		k.blob("Drip", Vector3.new(0.35, 0.6, 0.35), Vector3.new(math.cos(a) * 1.45, 0.5, math.sin(a) * 1.4), ooze, GLASS, 0.3)
	end
end

-- 뼈 (스켈레톤·궁수 공통)
local BONE = C(214, 204, 178)
local BONE_DARK = C(150, 138, 112)
local HOLE = C(30, 25, 25)
-- 뼈 몸: 해골(광대·위아래 턱·이빨·깊은 눈구멍 속 작은 눈빛) + 목뼈 + 등뼈 + 갈비뼈 4쌍·복장뼈 + 쇄골 + 골반 + 다리뼈(넓적다리·무릎·정강이·종아리·발가락)
-- 키 약 4.75. 사람처럼 늘씬하게 (예전 큰 머리 2.2 → 0.9)
local function skeletonBody(k, eyeColor: Color3)
	k.slot(k.blob("Skull", Vector3.new(0.82, 0.88, 0.95), Vector3.new(0, 4.3, -0.12), BONE, LIMESTONE), "Head")
	k.blob("Cranium", Vector3.new(0.86, 0.8, 0.9), Vector3.new(0, 4.42, 0.02), BONE, LIMESTONE)
	k.box("Brow", Vector3.new(0.74, 0.1, 0.18), CFrame.new(0, 4.34, -0.5), BONE_DARK, LIMESTONE)
	for _, side in { 1, -1 } do
		k.ball("Socket", 0.26, Vector3.new(0.18 * side, 4.22, -0.5), HOLE)
		k.slot(k.ball("Eye", 0.07, Vector3.new(0.18 * side, 4.22, -0.61), eyeColor, NEON), "Eye")
		k.box("Cheek", Vector3.new(0.16, 0.13, 0.32), CFrame.new(0.3 * side, 4.06, -0.4) * CFrame.Angles(0, math.rad(-15 * side), 0), BONE, LIMESTONE)
	end
	k.box("NoseHole", Vector3.new(0.1, 0.13, 0.06), CFrame.new(0, 4.07, -0.6), HOLE)
	k.box("Maxilla", Vector3.new(0.5, 0.12, 0.36), CFrame.new(0, 3.95, -0.38), BONE, LIMESTONE)
	for i = -3, 3 do
		k.box("Tooth", Vector3.new(0.055, 0.09, 0.05), CFrame.new(i * 0.065, 3.87, -0.56 + math.abs(i) * 0.015), C(232, 222, 195))
	end
	k.box("Jaw", Vector3.new(0.5, 0.09, 0.42), CFrame.new(0, 3.72, -0.33) * CFrame.Angles(math.rad(12), 0, 0), BONE, LIMESTONE)
	for i = -2, 2 do
		k.box("Tooth", Vector3.new(0.05, 0.08, 0.05), CFrame.new(i * 0.07, 3.79, -0.5 + math.abs(i) * 0.015), C(220, 210, 180))
	end
	-- 목뼈·등뼈
	k.limb("Neck", Vector3.new(0, 3.55, 0.02), Vector3.new(0, 3.95, -0.06), 0.12, BONE_DARK)
	k.limb("Spine", Vector3.new(0, 2.35, 0.12), Vector3.new(0, 3.55, 0.06), 0.12, BONE_DARK)
	for i = 0, 4 do
		k.box("Vertebra", Vector3.new(0.2, 0.1, 0.16), CFrame.new(0, 2.5 + i * 0.25, 0.2), BONE, LIMESTONE)
	end
	-- 갈비뼈 4쌍 + 복장뼈
	k.slot(k.box("Sternum", Vector3.new(0.12, 0.62, 0.07), CFrame.new(0, 3.18, -0.33) * CFrame.Angles(math.rad(-8), 0, 0), BONE), "Armor")
	for i = 0, 3 do
		local y = 3.45 - i * 0.19
		local w = 0.44 - i * 0.03
		for _, side in { 1, -1 } do
			local back = Vector3.new(0.06 * side, y, 0.14)
			local mid = Vector3.new(w * side, y - 0.05, -0.04)
			local front = Vector3.new(0.12 * side, y - 0.16, -0.31)
			k.limb("Rib", back, mid, 0.065, BONE)
			k.limb("Rib", mid, front, 0.06, BONE)
		end
	end
	-- 쇄골·골반
	for _, side in { 1, -1 } do
		k.limb("Clavicle", Vector3.new(0.08 * side, 3.58, -0.22), Vector3.new(0.6 * side, 3.62, -0.04), 0.075, BONE)
		k.blob("Ilium", Vector3.new(0.3, 0.36, 0.14), Vector3.new(0.27 * side, 2.45, 0.06), BONE, LIMESTONE, nil, CFrame.Angles(0, 0, math.rad(20 * side)))
	end
	k.slot(k.box("Pelvis", Vector3.new(0.62, 0.18, 0.28), CFrame.new(0, 2.3, 0.06), BONE, LIMESTONE), "Armor")
	-- 다리
	for _, side in { 1, -1 } do
		local hip = Vector3.new(0.22 * side, 2.2, 0.02)
		local knee = Vector3.new(0.26 * side, 1.25, -0.1)
		local ankle = Vector3.new(0.26 * side, 0.25, 0.02)
		k.ball("Hip", 0.17, hip, BONE)
		k.limb("Femur", hip, knee, 0.12, BONE)
		k.ball("Knee", 0.17, knee, BONE)
		k.ball("Kneecap", 0.1, knee + Vector3.new(0, 0.02, -0.09), BONE_DARK)
		k.limb("Tibia", knee, ankle, 0.1, BONE)
		k.limb("Fibula", knee + Vector3.new(0.06 * side, -0.1, 0.05), ankle + Vector3.new(0.05 * side, 0.05, 0.03), 0.05, BONE_DARK)
		k.box("Foot", Vector3.new(0.22, 0.09, 0.42), CFrame.new(ankle.X, 0.06, -0.12), BONE)
		for toe = -1, 1 do
			k.box("Toe", Vector3.new(0.05, 0.06, 0.14), CFrame.new(ankle.X + toe * 0.07, 0.04, -0.38), BONE_DARK)
		end
	end
end
-- 뼈 팔: 어깨 → 위팔뼈 → 팔꿈치 → 아래팔 두 뼈 → 손뼈 + 손가락 둘. 손 부품을 돌려준다
local function boneArm(k, shoulder: Vector3, elbow: Vector3, wrist: Vector3): BasePart
	k.ball("Shoulder", 0.17, shoulder, BONE)
	k.limb("Humerus", shoulder, elbow, 0.1, BONE)
	k.ball("Elbow", 0.14, elbow, BONE)
	local dir = (wrist - elbow).Unit
	local across = dir:Cross(Vector3.yAxis)
	across = if across.Magnitude > 0.01 then across.Unit * 0.035 else Vector3.new(0.035, 0, 0)
	k.limb("Radius", elbow + across, wrist + across, 0.06, BONE)
	k.limb("Ulna", elbow - across, wrist - across, 0.05, BONE_DARK)
	local hand = k.box("Hand", Vector3.new(0.13, 0.15, 0.16), CFrame.lookAt(wrist + dir * 0.08, wrist + dir), BONE)
	for _, f in { 1, -1 } do
		k.limb("Finger", wrist + dir * 0.14 + across * f * 1.2, wrist + dir * 0.3 + across * f * 1.4 - Vector3.new(0, 0.05, 0), 0.035, BONE_DARK)
	end
	return hand
end

-- 스켈레톤 (2026-10-10 다시 디자인): 사람 크기 해골 전사. 녹슨 투구(코 가리개)·한쪽 어깨 녹슨 견갑·낡은 허리 천,
-- 오른손 이 빠진 녹슨 장검을 앞으로 겨누고 왼팔에 갈라진 나무 방패. 눈구멍 깊은 곳에 파란 불씨 (키 약 4.8)
MOBS.Skeleton = function(k)
	skeletonBody(k, C(120, 210, 255))
	local rust = C(105, 85, 72)
	-- 녹슨 투구 + 코 가리개
	k.blob("Helmet", Vector3.new(0.96, 0.52, 1.02), Vector3.new(0, 4.62, -0.06), rust, CORRODED)
	k.blob("HelmetRim", Vector3.new(1.08, 0.07, 1.12), Vector3.new(0, 4.43, -0.06), C(85, 70, 60), CORRODED)
	k.box("NoseGuard", Vector3.new(0.07, 0.3, 0.05), CFrame.new(0, 4.3, -0.62), C(85, 70, 60), CORRODED)
	-- 왼쪽 어깨 견갑 + 가슴 끈, 허리 천
	k.slot(k.blob("Pauldron", Vector3.new(0.52, 0.28, 0.56), Vector3.new(-0.68, 3.74, 0), rust, CORRODED, nil, CFrame.Angles(0, 0, math.rad(18))), "Armor")
	k.box("Strap", Vector3.new(0.1, 1.15, 0.05), CFrame.new(-0.25, 3.25, -0.36) * CFrame.Angles(0, 0, math.rad(-38)), C(70, 50, 35), LEATHER)
	k.box("Loincloth", Vector3.new(0.55, 0.65, 0.04), CFrame.new(0, 1.98, -0.25) * CFrame.Angles(math.rad(4), 0, math.rad(3)), C(70, 58, 48), FABRIC)
	k.box("Loincloth", Vector3.new(0.5, 0.55, 0.04), CFrame.new(0, 2.02, 0.32), C(62, 52, 44), FABRIC)
	-- 오른팔 + 녹슨 장검 (앞으로 겨눔)
	local rElbow, rWrist = Vector3.new(0.8, 2.95, -0.18), Vector3.new(0.72, 2.6, -0.6)
	boneArm(k, Vector3.new(0.66, 3.58, 0), rElbow, rWrist)
	local grip = rWrist + (rWrist - rElbow).Unit * 0.1
	local dir = Vector3.new(0.05, 0.55, -0.83).Unit
	local steel = C(150, 145, 140)
	k.limb("SwordGrip", grip - dir * 0.2, grip + dir * 0.15, 0.07, C(55, 40, 30), LEATHER)
	k.ball("SwordPommel", 0.13, grip - dir * 0.24, rust, CORRODED)
	k.box("SwordGuard", Vector3.new(0.42, 0.06, 0.08), CFrame.lookAt(grip + dir * 0.18, grip + dir), rust, CORRODED)
	local bladeCenter = grip + dir * 1.05
	local bladeFrame = CFrame.lookAt(bladeCenter, bladeCenter + dir)
	k.slot(k.box("Blade", Vector3.new(0.13, 0.035, 1.7), bladeFrame, steel, CORRODED), "Weapon")
	k.box("Rust", Vector3.new(0.09, 0.045, 0.6), bladeFrame * CFrame.new(-0.01, 0, 0.35), C(125, 70, 40), CORRODED)
	k.box("Notch", Vector3.new(0.05, 0.05, 0.1), bladeFrame * CFrame.new(0.06, 0, -0.2), HOLE)
	k.spike(bladeCenter + dir * 0.85, bladeCenter + dir * 1.15, 0.13, steel, CORRODED, false, bladeFrame.XVector)
	-- 왼팔 + 갈라진 나무 방패
	local lWrist = Vector3.new(-0.72, 2.75, -0.5)
	boneArm(k, Vector3.new(-0.66, 3.58, 0), Vector3.new(-0.86, 3.0, -0.12), lWrist)
	local shieldFrame = CFrame.new(-0.78, 2.85, -0.7) * CFrame.Angles(0, math.rad(90 - 12), 0)
	k.disc("Shield", 0.1, 1.15, shieldFrame, C(95, 70, 45), WOOD)
	k.disc("ShieldRim", 0.06, 1.24, shieldFrame * CFrame.new(-0.03, 0, 0), C(85, 70, 60), CORRODED)
	k.ball("ShieldBoss", 0.26, shieldFrame:PointToWorldSpace(Vector3.new(0.07, 0, 0)), rust, CORRODED)
	k.box("ShieldCrack", Vector3.new(0.03, 0.5, 0.04), shieldFrame * CFrame.new(0.06, 0.28, 0.15) * CFrame.Angles(math.rad(20), 0, 0), HOLE)
end

-- 스켈레톤 궁수 (2026-10-10 다시 디자인): 같은 해골 몸 + 해진 짙은 초록 두건·망토, 왼손 활(화살을 건 채)·오른손이 시위를 당긴다,
-- 등에 낡은 가죽 화살통(검은 깃 화살). 눈빛은 주황 (키 약 4.8)
MOBS.SkeletonArcher = function(k)
	skeletonBody(k, C(255, 150, 60))
	local cloth = C(45, 60, 40)
	local leather = C(95, 62, 40)
	local wood = C(80, 55, 35)
	-- 두건 (얼굴은 앞으로 드러남) + 뒤로 처진 끝 + 목도리 + 해진 망토
	k.slot(k.blob("Hood", Vector3.new(1.05, 1.02, 1.12), Vector3.new(0, 4.4, 0.1), cloth, FABRIC), "Armor")
	k.blob("HoodTip", Vector3.new(0.45, 0.5, 0.6), Vector3.new(0, 4.5, 0.6), cloth, FABRIC, nil, CFrame.Angles(math.rad(35), 0, 0))
	k.blob("Scarf", Vector3.new(0.72, 0.22, 0.62), Vector3.new(0, 3.62, 0), cloth:Lerp(C(0, 0, 0), 0.2), FABRIC)
	k.box("Cape", Vector3.new(0.95, 1.3, 0.05), CFrame.new(0, 3.0, 0.38) * CFrame.Angles(math.rad(8), 0, 0), cloth, FABRIC)
	k.tri(Vector3.new(-0.47, 2.36, 0.47), Vector3.new(-0.1, 2.36, 0.47), Vector3.new(-0.3, 2.05, 0.5), 0.05, cloth, FABRIC) -- 해진 끝
	-- 왼팔: 앞으로 뻗어 활을 쥔다 / 오른팔: 몸 앞을 가로질러 시위를 당긴다
	local grip = Vector3.new(-0.75, 3.45, -1.0)
	boneArm(k, Vector3.new(-0.66, 3.58, 0), Vector3.new(-0.72, 3.5, -0.5), grip + Vector3.new(0, 0, 0.1))
	local pull = Vector3.new(-0.62, 3.47, -0.32)
	boneArm(k, Vector3.new(0.66, 3.58, 0), Vector3.new(0.25, 3.45, -0.1), pull)
	-- 활: 손잡이가 앞, 양끝이 뒤로 휘었다가 끝이 다시 앞으로 (리커브) + 시위 + 건 화살
	local bowPoints = { Vector3.new(-0.75, 4.4, -0.85), Vector3.new(-0.75, 4.25, -0.72), Vector3.new(-0.75, 3.9, -0.98), grip + Vector3.new(0, 0, -0.1), Vector3.new(-0.75, 3.0, -0.98), Vector3.new(-0.75, 2.65, -0.72), Vector3.new(-0.75, 2.5, -0.85) }
	for i = 1, #bowPoints - 1 do
		k.slot(k.limb("Bow", bowPoints[i], bowPoints[i + 1], if i == 3 or i == 4 then 0.11 else 0.08, wood, WOOD), "Weapon")
	end
	k.limb("BowWrap", grip + Vector3.new(0, 0.12, -0.1), grip + Vector3.new(0, -0.12, -0.1), 0.13, leather, LEATHER)
	k.limb("String", bowPoints[2], pull, 0.025, C(210, 205, 190))
	k.limb("String", pull, bowPoints[6], 0.025, C(210, 205, 190))
	local arrowTip = Vector3.new(-0.75, 3.47, -1.5)
	k.limb("Arrow", pull, arrowTip, 0.045, C(150, 115, 75), WOOD)
	k.spike(arrowTip, arrowTip + Vector3.new(0, 0, -0.22), 0.1, C(120, 120, 125), METAL, false, Vector3.xAxis)
	k.box("Fletch", Vector3.new(0.02, 0.12, 0.2), CFrame.new(pull + Vector3.new(0, 0.05, -0.08)), C(25, 25, 25), FABRIC)
	-- 등에 비스듬히 멘 화살통 + 검은 깃 화살 + 가슴을 가로지르는 끈
	local quiverBottom, quiverTop = Vector3.new(0.4, 2.3, 0.5), Vector3.new(-0.3, 3.7, 0.55)
	local up = (quiverTop - quiverBottom).Unit
	k.limb("Quiver", quiverBottom, quiverTop, 0.42, leather, LEATHER)
	k.limb("QuiverRim", quiverTop, quiverTop + up * 0.1, 0.48, C(85, 70, 60), CORRODED)
	k.limb("QuiverBand", quiverBottom + up * 0.4, quiverBottom + up * 0.48, 0.46, C(85, 70, 60), CORRODED)
	for _, offset in { Vector3.new(0.08, 0, 0), Vector3.new(-0.1, 0.05, 0.06), Vector3.new(0, 0.02, -0.09) } do
		local tip = quiverTop + up * 0.5 + offset
		k.limb("QuiverArrow", quiverTop + offset, tip, 0.04, C(150, 115, 75), WOOD)
		k.box("Fletch", Vector3.new(0.03, 0.2, 0.14), CFrame.new(tip), C(25, 25, 25), FABRIC)
	end
	k.box("Strap", Vector3.new(0.1, 1.3, 0.05), CFrame.new(0.05, 3.2, -0.36) * CFrame.Angles(0, 0, math.rad(-38)), leather, LEATHER)
end

-- 좀비 (2026-10-10 다시 디자인): 썩어 가는 사람. 앞으로 굽은 몸, 오른팔은 앞으로 뻗고 왼팔은 축 늘어짐(팔뚝 뼈가 드러남),
-- 찢어진 셔츠·바지, 셔츠 틈 갈비뼈·꿰맨 상처, 움푹 꺼진 눈 속 흐린 노란 눈빛(한쪽은 처짐), 빠진 아래턱·누런 이빨,
-- 썩어 뚫린 볼, 듬성듬성한 머리카락, 맨발 (키 약 4.5)
MOBS.Zombie = function(k)
	local skin = C(118, 138, 96)
	local rot = C(78, 88, 60)
	local wound = C(85, 28, 28)
	local shirt = C(92, 88, 78)
	local pants = C(55, 60, 75)
	local teeth = C(200, 188, 140)
	-- 다리 (바지, 오른쪽 아랫다리는 찢어져 맨살)
	for _, side in { 1, -1 } do
		local hip = Vector3.new(0.3 * side, 2.2, 0.08)
		local knee = Vector3.new(0.33 * side, 1.22, -0.04)
		local ankle = Vector3.new(0.32 * side, 0.25, 0.08)
		local bare = side > 0
		k.limb("Thigh", hip, knee, 0.4, pants, FABRIC)
		k.ball("Knee", 0.36, knee, if bare then skin else pants, if bare then SMOOTH else FABRIC)
		k.limb("Shin", knee, ankle, 0.31, if bare then skin else pants, if bare then SMOOTH else FABRIC)
		k.blob("Foot", Vector3.new(0.34, 0.22, 0.62), Vector3.new(ankle.X, 0.11, -0.12), skin)
	end
	k.box("PantTear", Vector3.new(0.44, 0.16, 0.44), CFrame.new(0.33, 1.05, -0.04) * CFrame.Angles(0, 0, math.rad(15)), pants, FABRIC)
	k.limb("ShinWound", Vector3.new(0.4, 0.8, -0.12), Vector3.new(0.38, 0.5, -0.1), 0.1, wound)
	-- 골반·허리띠
	k.box("Hips", Vector3.new(0.95, 0.45, 0.58), CFrame.new(0, 2.32, 0.08), pants, FABRIC)
	k.box("Belt", Vector3.new(0.98, 0.1, 0.6), CFrame.new(0, 2.5, 0.08), C(50, 35, 25), LEATHER)
	-- 몸통: 허리에서 앞으로 굽음
	local lean = CFrame.new(0, 2.55, 0.1) * CFrame.Angles(math.rad(-22), 0, 0)
	local leanRot = lean.Rotation
	local function L(x: number, y: number, z: number): Vector3
		return lean:PointToWorldSpace(Vector3.new(x, y, z))
	end
	k.slot(k.blob("Torso", Vector3.new(1.15, 1.3, 0.68), L(0, 0.62, 0), shirt, FABRIC, nil, leanRot), "Armor")
	k.blob("Belly", Vector3.new(0.55, 0.45, 0.2), L(0.15, 0.3, -0.28), skin, SMOOTH, nil, leanRot)
	k.blob("RibHole", Vector3.new(0.38, 0.44, 0.08), L(-0.22, 0.66, -0.31), C(60, 25, 25), SMOOTH, nil, leanRot)
	for i = 0, 2 do
		k.box("Rib", Vector3.new(0.3, 0.04, 0.05), CFrame.new(L(-0.22, 0.78 - i * 0.12, -0.35)) * leanRot * CFrame.Angles(0, 0, math.rad(-10)), BONE)
	end
	local scar = CFrame.new(L(0.27, 0.85, -0.34)) * leanRot * CFrame.Angles(0, 0, math.rad(30))
	k.box("Scar", Vector3.new(0.5, 0.04, 0.03), scar, wound)
	for i = -2, 1 do
		k.box("Stitch", Vector3.new(0.025, 0.14, 0.03), scar * CFrame.new(i * 0.12 + 0.06, 0, -0.005), C(30, 25, 20))
	end
	k.box("ShirtFlap", Vector3.new(0.3, 0.35, 0.03), CFrame.new(L(0.42, 0.12, -0.3)) * leanRot * CFrame.Angles(0, 0, math.rad(12)), shirt, FABRIC)
	k.blob("Shoulders", Vector3.new(1.45, 0.45, 0.7), L(0, 1.18, 0.02), shirt, FABRIC, nil, leanRot)
	-- 목·머리 (앞으로 쭉 빠지고 고개가 기울어짐)
	local headPos = Vector3.new(0.08, 3.9, -0.62)
	local headRot = CFrame.Angles(math.rad(-10), 0, math.rad(12))
	local hf = CFrame.new(headPos) * headRot
	local function H(x: number, y: number, z: number): Vector3
		return hf:PointToWorldSpace(Vector3.new(x, y, z))
	end
	k.limb("Neck", L(0, 1.32, -0.05), H(0, -0.32, 0.12), 0.26, skin)
	k.slot(k.blob("Head", Vector3.new(0.8, 0.92, 0.88), headPos, skin, SMOOTH, nil, headRot), "Head")
	k.blob("Brow", Vector3.new(0.72, 0.18, 0.3), H(0, 0.16, -0.32), rot, SMOOTH, nil, headRot)
	for _, side in { 1, -1 } do
		k.ball("Socket", 0.22, H(0.17 * side, 0.03, -0.37), C(35, 30, 30))
		local droop = if side < 0 then -0.04 else 0
		k.slot(k.ball("Eye", if side < 0 then 0.06 else 0.08, H(0.17 * side, 0.03 + droop, -0.46), C(220, 215, 120), NEON), "Eye")
	end
	k.blob("Nose", Vector3.new(0.14, 0.2, 0.14), H(0, -0.1, -0.44), rot, SMOOTH, nil, headRot)
	k.blob("RotCheek", Vector3.new(0.22, 0.18, 0.08), H(-0.27, -0.13, -0.35), C(70, 30, 30), SMOOTH, nil, headRot)
	k.blob("Mouth", Vector3.new(0.42, 0.16, 0.1), H(0, -0.33, -0.37), C(40, 15, 15), SMOOTH, nil, headRot)
	for i, x in { -0.14, -0.06, 0.03, 0.12 } do
		k.box("Tooth", Vector3.new(0.05, 0.06 + (i % 2) * 0.03, 0.04), CFrame.new(H(x, -0.27, -0.41)) * headRot, teeth)
	end
	k.box("Jaw", Vector3.new(0.5, 0.14, 0.4), CFrame.new(H(0.02, -0.47, -0.2)) * headRot * CFrame.Angles(math.rad(18), 0, 0), skin)
	for _, x in { -0.1, 0.02, 0.1 } do
		k.box("Tooth", Vector3.new(0.05, 0.07, 0.04), CFrame.new(H(x, -0.4, -0.37)) * headRot, teeth)
	end
	k.blob("Hair", Vector3.new(0.5, 0.12, 0.45), H(-0.12, 0.44, 0.05), C(45, 40, 30), FABRIC, nil, headRot)
	k.blob("Hair", Vector3.new(0.3, 0.1, 0.32), H(0.22, 0.4, 0.2), C(45, 40, 30), FABRIC, nil, headRot)
	k.limb("HairStrand", H(0.3, 0.3, -0.1), H(0.4, -0.12, -0.25), 0.05, C(45, 40, 30), FABRIC)
	k.blob("Ear", Vector3.new(0.1, 0.22, 0.16), H(0.42, 0, 0), skin, SMOOTH, nil, headRot)
	-- 오른팔: 앞으로 뻗어 움켜쥐려는 손 (손톱 검게)
	local rs, re, rw = L(0.68, 1.1, 0), Vector3.new(0.85, 3.25, -0.95), Vector3.new(0.8, 3.15, -1.65)
	k.ball("Shoulder", 0.42, rs, shirt, FABRIC)
	k.limb("Sleeve", rs, rs:Lerp(re, 0.6), 0.36, shirt, FABRIC)
	k.limb("UpperArm", rs, re, 0.27, skin)
	k.ball("Elbow", 0.26, re, skin)
	k.limb("Forearm", re, rw, 0.23, skin)
	k.slot(k.blob("Hand", Vector3.new(0.26, 0.12, 0.3), rw + Vector3.new(0, -0.03, -0.12), skin), "Weapon")
	for f = -1, 1 do
		local tip = rw + Vector3.new(f * 0.09, -0.14, -0.48)
		k.limb("Finger", rw + Vector3.new(f * 0.08, -0.04, -0.25), tip, 0.06, skin)
		k.ball("Nail", 0.06, tip, C(45, 40, 35))
	end
	-- 왼팔: 축 늘어짐, 찢어진 소매, 팔뚝 살이 떨어져 뼈가 드러남
	local ls, le, lw = L(-0.68, 1.1, 0), Vector3.new(-0.9, 2.55, -0.3), Vector3.new(-0.82, 1.85, -0.5)
	k.ball("Shoulder", 0.42, ls, shirt, FABRIC)
	k.limb("Sleeve", ls, ls:Lerp(le, 0.45), 0.36, shirt, FABRIC)
	k.limb("UpperArm", ls, le, 0.26, skin)
	k.ball("Elbow", 0.25, le, skin)
	k.limb("Forearm", le, le:Lerp(lw, 0.45), 0.22, skin)
	k.limb("BoneOut", le:Lerp(lw, 0.4), lw, 0.08, BONE)
	k.limb("Flesh", le:Lerp(lw, 0.82), lw, 0.2, rot)
	k.blob("Hand", Vector3.new(0.24, 0.3, 0.14), lw + Vector3.new(0, -0.2, -0.04), skin)
	for f = -1, 1 do
		k.limb("Finger", lw + Vector3.new(f * 0.07, -0.32, -0.05), lw + Vector3.new(f * 0.08, -0.55, -0.1), 0.055, skin)
	end
	k.box("BloodDrip", Vector3.new(0.05, 0.25, 0.04), CFrame.new(L(0.3, 0.55, -0.36)) * leanRot, wound)
end

-- 케르베로스 (2026-10-10 다시 디자인): 근육질 지옥 사냥개. 검붉은 짧은 털, 넓은 가슴·잘록한 배·엉덩이, 관절이 있는 다리와 발톱,
-- 어깨 갈기·등뼈를 따라 솟은 가시, 채찍 같은 꼬리 끝 가시. 머리마다 긴 주둥이·벌린 턱·송곳니·뒤로 젖힌 귀·불씨 눈·가시 목걸이
-- 보통은 머리 2개, 보스는 가운데 셋째 머리(속성 BossOnly)가 더 있다 (2026-10-10 사용자 요청). 몸길이 약 4.7, 높이 약 3.2 × Scale 1.1
MOBS.Cerberus = function(k)
	local fur = C(52, 38, 40)
	local furDark = C(32, 24, 26)
	local lip = C(95, 55, 55)
	local fang = C(235, 225, 200)
	local ember = C(255, 120, 40)
	local iron = C(70, 65, 65)
	-- 몸통
	k.slot(k.blob("Chest", Vector3.new(1.55, 1.55, 1.6), Vector3.new(0, 2.0, -0.75), fur, FABRIC), "Armor")
	k.blob("Ribcage", Vector3.new(1.25, 1.15, 1.6), Vector3.new(0, 1.98, 0.3), fur, FABRIC)
	k.blob("Belly", Vector3.new(0.9, 0.6, 1.3), Vector3.new(0, 1.5, 0.2), furDark, FABRIC)
	k.slot(k.blob("Haunch", Vector3.new(1.25, 1.25, 1.15), Vector3.new(0, 2.0, 1.2), fur, FABRIC), "Armor")
	k.blob("Mane", Vector3.new(1.7, 0.95, 1.0), Vector3.new(0, 2.55, -0.95), furDark, FABRIC)
	-- 등 가시 (뒤로 누운 뼈 가시)
	for _, info in { { -0.45, 2.72 }, { 0.05, 2.55 }, { 0.55, 2.5 }, { 1.05, 2.57 } } do
		local z, y = info[1], info[2]
		k.spike(Vector3.new(0, y - 0.1, z), Vector3.new(0, y + 0.32, z + 0.25), 0.22, C(70, 50, 45), SLATE, false, Vector3.zAxis)
	end
	-- 앞다리 (어깨 → 팔꿈치 → 발목 → 발, 발톱 2개)
	for _, side in { 1, -1 } do
		local x = 0.55 * side
		k.blob("Shoulder", Vector3.new(0.5, 0.95, 0.75), Vector3.new(x, 1.85, -0.85), fur, FABRIC)
		local elbow = Vector3.new(x * 1.05, 1.15, -0.72)
		local wrist = Vector3.new(x * 1.05, 0.35, -0.95)
		k.limb("Foreleg", Vector3.new(x, 1.6, -0.85), elbow, 0.36, fur, FABRIC)
		k.limb("Forearm", elbow, wrist, 0.26, fur, FABRIC)
		k.blob("Paw", Vector3.new(0.36, 0.22, 0.5), Vector3.new(wrist.X, 0.11, wrist.Z - 0.12), furDark, FABRIC)
		for _, c in { -0.08, 0.08 } do
			k.spike(Vector3.new(wrist.X + c, 0.1, wrist.Z - 0.34), Vector3.new(wrist.X + c * 1.3, 0.02, wrist.Z - 0.55), 0.07, fang, SMOOTH, false, Vector3.xAxis)
		end
	end
	-- 뒷다리 (개 다리: 허벅지 → 뒤로 꺾인 발목)
	for _, side in { 1, -1 } do
		local x = 0.5 * side
		k.blob("Thigh", Vector3.new(0.5, 1.05, 0.85), Vector3.new(x, 1.75, 1.3), fur, FABRIC)
		local knee = Vector3.new(x * 1.05, 1.25, 1.2)
		local hock = Vector3.new(x * 1.05, 0.7, 1.62)
		local foot = Vector3.new(x * 1.05, 0.2, 1.45)
		k.limb("Shank", knee, hock, 0.28, fur, FABRIC)
		k.limb("Hock", hock, foot, 0.22, fur, FABRIC)
		k.blob("Paw", Vector3.new(0.32, 0.2, 0.45), Vector3.new(foot.X, 0.1, foot.Z - 0.12), furDark, FABRIC)
	end
	-- 꼬리 (채찍처럼 가늘어지다 끝에 가시)
	local tail = { Vector3.new(0, 2.25, 1.7), Vector3.new(0, 2.45, 2.15), Vector3.new(0, 2.3, 2.6), Vector3.new(0, 1.95, 2.9) }
	for i = 1, #tail - 1 do
		k.limb("Tail", tail[i], tail[i + 1], 0.24 - i * 0.05, fur, FABRIC)
	end
	k.spike(tail[4], Vector3.new(0, 1.65, 3.2), 0.2, C(70, 50, 45), SLATE, true)
	-- 머리 하나 (center = 머리 가운데, yaw = 바깥으로 돌린 각도)
	local function head(center: Vector3, yaw: number)
		local hf = CFrame.new(center) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(-8), 0, 0)
		local rot = hf.Rotation
		local function P(x: number, y: number, z: number): Vector3
			return hf:PointToWorldSpace(Vector3.new(x, y, z))
		end
		k.limb("Neck", Vector3.new(center.X * 0.45, 2.25, -1.05), P(0, -0.05, 0.25), 0.5, fur, FABRIC)
		k.slot(k.blob("Skull", Vector3.new(0.66, 0.6, 0.72), center, fur, FABRIC, nil, rot), "Head")
		k.blob("Brow", Vector3.new(0.6, 0.16, 0.25), P(0, 0.2, -0.28), furDark, FABRIC, nil, rot)
		k.blob("Muzzle", Vector3.new(0.38, 0.3, 0.62), P(0, -0.06, -0.55), fur, FABRIC, nil, rot)
		k.blob("Lip", Vector3.new(0.4, 0.12, 0.55), P(0, -0.2, -0.55), lip, SMOOTH, nil, rot)
		k.ball("Nose", 0.15, P(0, 0.03, -0.86), C(20, 15, 15))
		k.box("Jaw", Vector3.new(0.3, 0.09, 0.5), CFrame.new(P(0, -0.33, -0.45)) * rot * CFrame.Angles(math.rad(18), 0, 0), furDark, FABRIC)
		k.box("Tongue", Vector3.new(0.18, 0.04, 0.35), CFrame.new(P(0, -0.3, -0.5)) * rot * CFrame.Angles(math.rad(14), 0, 0), C(150, 50, 60))
		for _, side in { 1, -1 } do
			k.spike(P(0.12 * side, -0.2, -0.72), P(0.12 * side, -0.42, -0.74), 0.07, fang, SMOOTH, false, hf.XVector) -- 위 송곳니
			k.spike(P(0.1 * side, -0.34, -0.62), P(0.1 * side, -0.19, -0.66), 0.06, fang, SMOOTH, false, hf.XVector) -- 아래 송곳니
			k.slot(k.ball("Eye", 0.09, P(0.17 * side, 0.1, -0.36), ember, NEON), "Eye")
			k.tri(P(0.2 * side, 0.22, -0.05), P(0.3 * side, 0.2, 0.15), P(0.28 * side, 0.55, 0.32), 0.06, furDark, FABRIC) -- 뒤로 젖힌 귀
		end
		k.disc("Collar", 0.14, 0.62, CFrame.new(P(0, -0.12, 0.3)) * rot * CFrame.Angles(0, math.rad(90), 0), iron, CORRODED)
		k.spike(P(0, 0.15, 0.3), P(0, 0.4, 0.34), 0.11, iron, METAL, false, hf.ZVector)
	end
	head(Vector3.new(0.52, 2.62, -1.62), math.rad(-14)) -- 오른쪽 머리 (바깥 = +X)
	head(Vector3.new(-0.52, 2.62, -1.62), math.rad(14)) -- 왼쪽 머리
	k.group({ BossOnly = true }, function()
		head(Vector3.new(0, 2.88, -1.88), 0) -- 보스만: 가운데 앞으로 나온 셋째 머리
	end)
end

-- 사이클롭스 (2026-10-10 다시 디자인): 구부정한 근육 거인. 회녹색 가죽 피부·가슴·배·승모근·이두근, 부은 눈두덩 아래 핏줄 선 누런 외눈(세로 동공),
-- 두꺼운 눈썹 뼈·넓은 코·아래로 튀어나온 엄니, 머리 흉터, 가죽 끈·해골 버클·털 허리 가리개, 왼쪽 어깨 가시 쇠 견갑(해골 장식),
-- 손목 가죽 보호대, 오른손 쇠띠·대못 박힌 통나무 몽둥이 (높이 약 7 × Scale 1.4)
MOBS.Cyclops = function(k)
	local skin = C(138, 135, 104)
	local shade = C(104, 102, 78)
	local cloth = C(90, 65, 45)
	local leather = C(70, 48, 32)
	local bone = C(225, 215, 190)
	local iron = C(80, 76, 72)
	-- 다리·발
	for _, side in { 1, -1 } do
		local hip, knee, ankle = Vector3.new(0.75 * side, 2.7, 0), Vector3.new(0.8 * side, 1.4, -0.15), Vector3.new(0.82 * side, 0.4, 0)
		k.limb("Thigh", hip, knee, 1.0, skin)
		k.ball("Knee", 0.85, knee, shade)
		k.blob("Calf", Vector3.new(0.85, 1.1, 0.9), Vector3.new(0.8 * side, 0.95, 0.08), skin)
		k.limb("Shin", knee, ankle, 0.75, skin)
		k.limb("Wrap", ankle + Vector3.new(0, 0.25, 0), ankle + Vector3.new(0, 0.55, 0), 0.8, leather, LEATHER)
		k.blob("Foot", Vector3.new(0.95, 0.5, 1.4), Vector3.new(0.82 * side, 0.25, -0.25), shade)
		for t = -1, 1 do
			k.ball("Toe", 0.3, Vector3.new(0.82 * side + t * 0.27, 0.17, -0.92), skin)
		end
	end
	-- 허리: 털 가리개 앞뒤 + 가죽 벨트 + 해골 버클
	k.box("Loincloth", Vector3.new(1.3, 1.1, 0.1), CFrame.new(0, 2.35, -0.95) * CFrame.Angles(math.rad(-6), 0, 0), cloth, FABRIC)
	k.box("Loincloth", Vector3.new(1.6, 1.0, 0.1), CFrame.new(0, 2.4, 0.95) * CFrame.Angles(math.rad(6), 0, 0), cloth, FABRIC)
	k.box("Belt", Vector3.new(2.5, 0.3, 1.95), CFrame.new(0, 3.0, 0), leather, LEATHER)
	k.ball("BuckleSkull", 0.42, Vector3.new(0, 3.0, -1.0), bone)
	for _, x in { -0.08, 0.08 } do
		k.ball("BuckleEye", 0.1, Vector3.new(x, 3.03, -1.18), C(30, 25, 25))
	end
	-- 몸통: 배·가슴·가슴 근육·승모근·등 혹, 가슴 흉터
	k.slot(k.blob("Belly", Vector3.new(2.4, 1.8, 1.9), Vector3.new(0, 3.6, -0.05), skin), "Armor")
	k.blob("Chest", Vector3.new(2.9, 1.7, 2.0), Vector3.new(0, 4.5, 0.05), skin)
	for _, side in { 1, -1 } do
		k.blob("Pec", Vector3.new(1.2, 0.8, 0.5), Vector3.new(0.6 * side, 4.55, -0.85), skin, SMOOTH, nil, CFrame.Angles(0, 0, math.rad(-8 * side)))
	end
	k.blob("Traps", Vector3.new(2.0, 0.8, 1.3), Vector3.new(0, 5.1, 0.3), shade)
	k.blob("Hump", Vector3.new(2.2, 1.3, 1.0), Vector3.new(0, 4.8, 0.85), skin)
	k.box("ChestScar", Vector3.new(0.9, 0.06, 0.05), CFrame.new(0.35, 4.3, -1.1) * CFrame.Angles(0, 0, math.rad(35)), C(170, 140, 115))
	k.box("Strap", Vector3.new(0.25, 2.6, 0.08), CFrame.new(-0.2, 4.2, -1.0) * CFrame.Angles(math.rad(-6), 0, math.rad(-40)), leather, LEATHER)
	-- 머리 (앞으로 숙임)
	k.slot(k.blob("Head", Vector3.new(1.75, 1.85, 1.75), Vector3.new(0, 5.95, -0.45), skin), "Head")
	k.blob("Jaw", Vector3.new(1.5, 0.75, 1.35), Vector3.new(0, 5.35, -0.6), shade)
	k.blob("BrowRidge", Vector3.new(1.5, 0.45, 0.6), Vector3.new(0, 6.38, -1.05), shade)
	k.blob("Socket", Vector3.new(0.95, 0.8, 0.3), Vector3.new(0, 6.0, -1.15), C(60, 50, 40))
	k.ball("Eyeball", 0.75, Vector3.new(0, 6.0, -1.12), C(225, 215, 175))
	k.slot(k.ball("Iris", 0.38, Vector3.new(0, 6.0, -1.43), C(200, 120, 25)), "Eye")
	k.box("Pupil", Vector3.new(0.07, 0.24, 0.05), CFrame.new(0, 6.0, -1.6), C(15, 10, 10))
	for i, angle in { 20, 160, 230 } do
		local a = math.rad(angle)
		k.box("Vein", Vector3.new(0.22, 0.025, 0.03), CFrame.new(math.cos(a) * 0.27, 6.0 + math.sin(a) * 0.25, -1.43 + i * 0.02) * CFrame.Angles(0, 0, a), C(190, 50, 45))
	end
	k.blob("Lid", Vector3.new(0.9, 0.26, 0.42), Vector3.new(0, 6.28, -1.25), skin, SMOOTH, nil, CFrame.Angles(math.rad(-12), 0, 0)) -- 무겁게 내려온 눈꺼풀
	k.blob("Nose", Vector3.new(0.48, 0.42, 0.5), Vector3.new(0, 5.6, -1.32), shade)
	for _, side in { 1, -1 } do
		k.ball("Nostril", 0.12, Vector3.new(0.12 * side, 5.48, -1.52), C(40, 30, 25))
		k.spike(Vector3.new(0.36 * side, 5.22, -1.18), Vector3.new(0.42 * side, 5.68, -1.27), 0.16, bone, SMOOTH, true) -- 아래 엄니
		k.blob("Ear", Vector3.new(0.25, 0.5, 0.35), Vector3.new(0.88 * side, 5.95, -0.4), shade, SMOOTH, nil, CFrame.Angles(0, 0, math.rad(-20 * side)))
	end
	k.box("Mouth", Vector3.new(0.9, 0.07, 0.1), CFrame.new(0, 5.3, -1.24), C(50, 25, 25))
	for _, x in { -0.18, 0, 0.18 } do
		k.box("Tooth", Vector3.new(0.09, 0.1, 0.06), CFrame.new(x, 5.36, -1.25), C(205, 195, 160))
	end
	k.box("HeadScar", Vector3.new(0.05, 0.6, 0.05), CFrame.new(0.4, 6.6, -0.95) * CFrame.Angles(math.rad(-30), 0, math.rad(15)), C(170, 140, 115))
	-- 팔 (어깨 → 이두근 → 팔꿈치 → 팔뚝 → 손목 보호대 → 손)
	for _, side in { 1, -1 } do
		local shoulder, elbow, wrist = Vector3.new(1.6 * side, 4.85, 0), Vector3.new(1.95 * side, 3.55, -0.25), Vector3.new(2.0 * side, 2.55, -0.7)
		k.blob("Shoulder", Vector3.new(1.1, 1.1, 1.1), Vector3.new(1.55 * side, 4.95, 0), skin)
		k.limb("UpperArm", shoulder, elbow, 0.85, skin)
		k.blob("Bicep", Vector3.new(0.75, 0.9, 0.75), shoulder:Lerp(elbow, 0.5) + Vector3.new(0, 0, -0.25), skin)
		k.ball("Elbow", 0.72, elbow, shade)
		k.limb("Forearm", elbow, wrist, 0.78, skin)
		k.limb("Bracer", elbow:Lerp(wrist, 0.6), wrist, 0.86, leather, LEATHER)
		k.limb("BracerBand", elbow:Lerp(wrist, 0.7), elbow:Lerp(wrist, 0.76), 0.9, iron, CORRODED)
		k.blob("Hand", Vector3.new(0.8, 0.9, 0.8), Vector3.new(2.0 * side, 2.35, -0.8), shade)
		if side < 0 then
			for f = -1, 1 do
				k.limb("Finger", Vector3.new(-2.0 + f * 0.22, 2.1, -1.05), Vector3.new(-2.0 + f * 0.24, 1.85, -1.12), 0.2, shade)
			end
		end
	end
	-- 왼쪽 어깨 가시 쇠 견갑 + 해골 장식
	k.slot(k.blob("Pauldron", Vector3.new(1.35, 0.55, 1.35), Vector3.new(-1.62, 5.45, 0), iron, CORRODED, nil, CFrame.Angles(0, 0, math.rad(14))), "Armor")
	for _, offset in { Vector3.new(-0.2, 0, -0.35), Vector3.new(-0.35, 0, 0.1), Vector3.new(-0.1, 0, 0.45) } do
		local base = Vector3.new(-1.62, 5.62, 0) + offset
		k.spike(base, base + Vector3.new(-0.25, 0.55, 0), 0.22, C(150, 145, 135), METAL, true)
	end
	k.ball("ShoulderSkull", 0.48, Vector3.new(-1.75, 5.2, -0.68), bone)
	-- 오른손 몽둥이: 통나무 + 쇠띠 2 + 대못
	local wood = C(95, 65, 38)
	local hand = Vector3.new(2.0, 2.35, -0.8)
	local tip = Vector3.new(2.38, 4.85, -2.15)
	local dir = (tip - hand).Unit
	k.slot(k.limb("Club", hand - dir * 0.4, tip - dir * 0.6, 0.42, wood, WOOD), "Weapon")
	k.slot(k.blob("ClubHead", Vector3.new(1.05, 1.8, 1.05), tip, wood, WOOD, nil, CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(math.rad(-90), 0, 0)), "Weapon")
	for _, t in { -0.45, 0.35 } do
		k.limb("ClubBand", tip + dir * (t - 0.06), tip + dir * (t + 0.06), 1.0, iron, CORRODED)
	end
	local s1 = dir:Cross(Vector3.yAxis).Unit
	local s2 = dir:Cross(s1).Unit
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		local out = s1 * math.cos(a) + s2 * math.sin(a)
		local base = tip + dir * ((i % 2) * 0.5 - 0.1) + out * 0.45
		k.spike(base, base + out * 0.42, 0.13, C(150, 145, 140), METAL)
	end
end

-- 바위 골렘 (2026-10-10 다시 디자인): 각진 바위 덩어리를 쌓은 고릴라 같은 거인. 짧은 다리·땅에 닿을 듯 긴 팔·커다란 돌 주먹,
-- 몸에 반쯤 묻힌 작은 머리(눈썹 바위 아래 가는 초록 눈빛), 가슴의 마나 핵에서 갈라진 빛나는 금, 어깨 이끼, 등에 솟은 수정 (높이 약 7.5 × Scale 1.6)
MOBS.StoneGolem = function(k)
	local rock = C(118, 114, 108)
	local dark = C(84, 80, 76)
	local moss = C(80, 110, 60)
	local glow = C(80, 255, 170)
	-- 다리·발
	for _, side in { 1, -1 } do
		k.box("Thigh", Vector3.new(1.3, 1.4, 1.4), CFrame.new(1.0 * side, 1.95, 0.2) * CFrame.Angles(math.rad(8), math.rad(6 * side), math.rad(-4 * side)), dark, SLATE)
		k.box("Shin", Vector3.new(1.2, 1.3, 1.3), CFrame.new(1.05 * side, 0.85, 0.05) * CFrame.Angles(math.rad(-5), math.rad(-8 * side), 0), rock, SLATE)
		k.box("Foot", Vector3.new(1.7, 0.5, 2.0), CFrame.new(1.05 * side, 0.25, -0.2) * CFrame.Angles(0, math.rad(5 * side), 0), dark, BASALT)
		for _, x in { -0.4, 0.35 } do
			k.box("ToeRock", Vector3.new(0.5, 0.4, 0.45), CFrame.new(1.05 * side + x, 0.3, -1.15) * CFrame.Angles(math.rad(10), math.rad(20 * x), 0), rock, SLATE)
		end
	end
	-- 골반·배·가슴 (앞으로 숙인 커다란 바위) + 가슴 판
	k.box("Pelvis", Vector3.new(2.6, 1.0, 1.6), CFrame.new(0, 2.85, 0.2), dark, SLATE)
	k.box("Waist", Vector3.new(3.0, 1.4, 2.2), CFrame.new(0, 3.75, 0.2) * CFrame.Angles(math.rad(-6), math.rad(4), 0), rock, SLATE)
	k.slot(k.box("Chest", Vector3.new(4.0, 1.9, 2.6), CFrame.new(0, 5.15, 0.15) * CFrame.Angles(math.rad(-12), 0, math.rad(2)), rock, SLATE), "Armor")
	for _, info in { { -0.95, 5.25, 12 }, { 0.95, 5.3, -10 }, { 0, 3.85, 4 } } do
		k.box("ChestPlate", Vector3.new(1.5, 1.1, 0.35), CFrame.new(info[1], info[2], -1.2) * CFrame.Angles(math.rad(-14), 0, math.rad(info[3])), dark, BASALT)
	end
	-- 마나 핵 + 빛나는 금
	local core = k.slot(k.ball("Core", 0.85, Vector3.new(0, 4.6, -1.2), glow, NEON), "Core")
	for _, angle in { 25, 100, 160, 215, 320 } do
		local a = math.rad(angle)
		k.box("Crack", Vector3.new(0.85, 0.07, 0.07), CFrame.new(math.cos(a) * 0.75, 4.6 + math.sin(a) * 0.75, -1.3) * CFrame.Angles(0, 0, a), glow, NEON)
	end
	local light = Instance.new("PointLight")
	light.Color = glow
	light.Range = 10
	light.Brightness = 1.2
	light.Parent = core
	-- 등 바위 + 수정
	for i, info in { { -0.9, 6.0, 1.0 }, { 0.8, 6.1, 0.9 }, { 0, 5.7, 1.35 } } do
		k.box("BackRock", Vector3.new(1.1, 0.9, 1.0), CFrame.new(info[1], info[2], info[3]) * CFrame.Angles(math.rad(i * 25), math.rad(i * 40), math.rad(i * 15)), dark, SLATE)
		local base = Vector3.new(info[1] * 0.8, info[2] + 0.3, info[3])
		k.spike(base, base + Vector3.new(info[1] * 0.2, 0.9 - i * 0.12, 0.25), 0.32, C(120, 255, 200), GLASS, true)
	end
	-- 머리: 몸에 반쯤 묻힌 각진 돌 + 튀어나온 눈썹 바위 + 가는 눈빛 + 턱 바위
	k.slot(k.box("Head", Vector3.new(1.3, 1.1, 1.3), CFrame.new(0, 6.15, -0.8) * CFrame.Angles(math.rad(-8), math.rad(6), 0), rock, SLATE), "Head")
	k.box("Brow", Vector3.new(1.55, 0.35, 0.6), CFrame.new(0, 6.5, -1.38) * CFrame.Angles(math.rad(12), 0, 0), dark, BASALT)
	for _, side in { 1, -1 } do
		k.slot(k.box("Eye", Vector3.new(0.34, 0.08, 0.06), CFrame.new(0.3 * side, 6.27, -1.47) * CFrame.Angles(0, 0, math.rad(-12 * side)), glow, NEON), "Eye")
	end
	k.box("Jaw", Vector3.new(1.1, 0.4, 0.9), CFrame.new(0, 5.72, -1.15) * CFrame.Angles(math.rad(6), 0, 0), dark, SLATE)
	-- 어깨 바위 + 이끼, 팔, 주먹
	for _, side in { 1, -1 } do
		k.slot(k.box("Shoulder", Vector3.new(1.8, 1.6, 1.8), CFrame.new(2.35 * side, 5.65, 0.1) * CFrame.Angles(math.rad(10), math.rad(25 * side), math.rad(-15 * side)), dark, SLATE), "Armor")
		k.blob("Moss", Vector3.new(1.5, 0.3, 1.3), Vector3.new(2.3 * side, 6.45, 0.1), moss, Enum.Material.Grass)
		k.box("UpperArm", Vector3.new(1.2, 1.8, 1.2), CFrame.new(2.6 * side, 4.35, -0.1) * CFrame.Angles(math.rad(-8), 0, math.rad(-6 * side)), rock, SLATE)
		k.box("Elbow", Vector3.new(0.9, 0.8, 0.9), CFrame.new(2.72 * side, 3.4, -0.25) * CFrame.Angles(math.rad(30), math.rad(30), math.rad(20)), dark, SLATE)
		k.box("Forearm", Vector3.new(1.5, 2.0, 1.5), CFrame.new(2.8 * side, 2.6, -0.45) * CFrame.Angles(math.rad(-10), math.rad(8 * side), 0), rock, SLATE)
		k.box("ArmCrack", Vector3.new(0.06, 1.2, 0.06), CFrame.new(2.8 * side - 0.2 * side, 2.7, -1.22) * CFrame.Angles(0, 0, math.rad(15 * side)), glow, NEON)
		k.slot(k.box("Fist", Vector3.new(1.9, 1.5, 1.9), CFrame.new(2.85 * side, 1.15, -0.6) * CFrame.Angles(math.rad(5), math.rad(10 * side), 0), dark, BASALT), "Weapon")
		for i = -1, 1 do
			k.box("Knuckle", Vector3.new(0.5, 0.5, 0.45), CFrame.new(2.85 * side + i * 0.55, 1.55, -1.55) * CFrame.Angles(math.rad(20), math.rad(i * 10), 0), rock, SLATE)
		end
	end
	-- 몸에 붙은 작은 돌 조각
	for i, p in { Vector3.new(1.3, 4.0, -0.9), Vector3.new(-1.4, 3.7, -0.8), Vector3.new(-1.6, 5.9, -0.7), Vector3.new(1.5, 6.0, -0.6) } do
		k.box("Pebble", Vector3.new(0.45, 0.35, 0.4), CFrame.new(p) * CFrame.Angles(i, i * 2, i * 0.5), dark, SLATE)
	end
end

-- 서리 거인 (2026-10-10 다시 디자인): 창백한 푸른 피부의 요툰. 긴 흰 수염(얼음 구슬 땋은 두 갈래)·뒤로 넘긴 흰 머리,
-- 깊은 눈두덩 속 차가운 하늘색 눈빛, 털가죽 망토, 가죽 치마·얼음 버클, 얼음 견갑에 자라난 수정, 얼음 왕관,
-- 털 장화·손목 털, 오른손 얼음 날 도끼 (높이 약 8.6 × Scale 1.8)
MOBS.FrostGiant = function(k)
	local skin = C(150, 175, 195)
	local shade = C(110, 135, 160)
	local fur = C(225, 228, 232)
	local furShade = C(180, 185, 192)
	local leather = C(70, 60, 55)
	local ice = C(185, 230, 255)
	local eye = C(150, 235, 255)
	-- 다리: 허벅지 맨살 → 털 장화
	for _, side in { 1, -1 } do
		local hip, knee = Vector3.new(0.95 * side, 3.1, 0), Vector3.new(1.0 * side, 1.6, -0.12)
		k.limb("Thigh", hip, knee, 1.15, skin)
		k.ball("Knee", 0.95, knee, shade)
		k.limb("Shin", knee, Vector3.new(1.0 * side, 0.8, 0), 0.95, skin)
		k.blob("Boot", Vector3.new(1.3, 1.35, 1.75), Vector3.new(1.0 * side, 0.6, -0.15), fur, FABRIC)
		k.limb("BootStrap", Vector3.new(1.0 * side, 0.95, 0), Vector3.new(1.0 * side, 1.08, 0), 1.25, leather, LEATHER)
	end
	-- 가죽 치마 + 벨트 + 얼음 버클
	k.box("Kilt", Vector3.new(2.9, 1.2, 0.12), CFrame.new(0, 2.75, -1.25) * CFrame.Angles(math.rad(-8), 0, 0), leather, LEATHER)
	k.box("Kilt", Vector3.new(3.1, 1.3, 0.12), CFrame.new(0, 2.75, 1.25) * CFrame.Angles(math.rad(8), 0, 0), leather, LEATHER)
	k.box("Belt", Vector3.new(3.3, 0.4, 2.65), CFrame.new(0, 3.35, 0), C(45, 38, 35), LEATHER)
	k.box("Buckle", Vector3.new(0.6, 0.5, 0.15), CFrame.new(0, 3.35, -1.36) * CFrame.Angles(0, 0, math.rad(45)), ice, GLASS)
	-- 몸통: 배·가슴·가슴 근육 + 털가죽 망토(어깨·등)
	k.blob("Belly", Vector3.new(2.7, 2.0, 2.3), Vector3.new(0, 4.1, -0.05), skin)
	k.slot(k.blob("Chest", Vector3.new(3.4, 2.0, 2.4), Vector3.new(0, 5.1, 0.05), skin), "Armor")
	for _, side in { 1, -1 } do
		k.blob("Pec", Vector3.new(1.35, 0.85, 0.5), Vector3.new(0.7 * side, 5.15, -1.0), skin, SMOOTH, nil, CFrame.Angles(0, 0, math.rad(-8 * side)))
	end
	k.blob("Pelt", Vector3.new(3.8, 1.0, 2.7), Vector3.new(0, 5.95, 0.2), fur, FABRIC)
	k.box("Cloak", Vector3.new(3.2, 3.0, 0.3), CFrame.new(0, 4.4, 1.3) * CFrame.Angles(math.rad(6), 0, 0), furShade, FABRIC)
	k.ball("PeltClasp", 0.4, Vector3.new(0, 5.9, -1.15), ice, GLASS)
	-- 머리: 피부 + 깊은 눈두덩 + 하늘색 눈빛 + 큰 코 + 흰 수염·콧수염·땋은 수염 + 뒤 머리 + 얼음 왕관
	k.slot(k.blob("Head", Vector3.new(1.6, 1.8, 1.6), Vector3.new(0, 6.95, -0.3), skin), "Head")
	k.blob("Brow", Vector3.new(1.45, 0.4, 0.55), Vector3.new(0, 7.3, -0.95), shade)
	for _, side in { 1, -1 } do
		k.ball("Socket", 0.36, Vector3.new(0.32 * side, 7.08, -0.98), C(45, 60, 80))
		k.slot(k.ball("Eye", 0.14, Vector3.new(0.32 * side, 7.08, -1.13), eye, NEON), "Eye")
		k.blob("Moustache", Vector3.new(0.6, 0.22, 0.3), Vector3.new(0.28 * side, 6.55, -1.1), fur, FABRIC, nil, CFrame.Angles(0, 0, math.rad(-18 * side)))
		local braidTop, braidBottom = Vector3.new(0.35 * side, 5.75, -0.98), Vector3.new(0.4 * side, 4.95, -1.05)
		k.limb("Braid", braidTop, braidBottom, 0.26, fur, FABRIC)
		k.ball("IceBead", 0.26, braidBottom, ice, GLASS)
		k.blob("Ear", Vector3.new(0.22, 0.45, 0.3), Vector3.new(0.82 * side, 6.95, -0.3), shade)
	end
	k.blob("Nose", Vector3.new(0.42, 0.55, 0.45), Vector3.new(0, 6.82, -1.12), shade)
	k.blob("Beard", Vector3.new(1.6, 1.5, 0.95), Vector3.new(0, 6.05, -0.85), fur, FABRIC)
	k.blob("BeardTip", Vector3.new(0.9, 0.9, 0.6), Vector3.new(0, 5.35, -0.95), furShade, FABRIC)
	k.blob("Hair", Vector3.new(1.75, 1.7, 1.3), Vector3.new(0, 7.1, 0.25), fur, FABRIC)
	k.blob("HairTail", Vector3.new(0.8, 1.4, 0.6), Vector3.new(0, 6.2, 0.85), furShade, FABRIC)
	k.disc("CrownBand", 0.2, 1.7, CFrame.new(0, 7.62, -0.25) * CFrame.Angles(0, 0, math.rad(90)), C(150, 200, 230), ICE)
	for i, x in { -0.62, -0.32, 0, 0.32, 0.62 } do
		local base = Vector3.new(x, 7.65, -0.25 - (0.65 - math.abs(x)) * 0.6)
		local height = if i == 3 then 1.0 else 0.6 - math.abs(x) * 0.2
		k.spike(base, base + Vector3.new(x * 0.25, height, 0), 0.26, ice, GLASS, true)
	end
	-- 팔: 맨살 + 얼음 견갑(수정이 자람) + 손목 털 + 큰 손
	for _, side in { 1, -1 } do
		local shoulder, elbow, wrist = Vector3.new(1.9 * side, 5.5, 0), Vector3.new(2.35 * side, 3.85, -0.2), Vector3.new(2.5 * side, 2.55, -0.65)
		k.blob("Shoulder", Vector3.new(1.3, 1.3, 1.3), Vector3.new(1.85 * side, 5.6, 0), skin)
		k.slot(k.blob("IcePauldron", Vector3.new(1.5, 0.6, 1.5), Vector3.new(1.9 * side, 6.2, 0.05), ice, GLASS, 0.15, CFrame.Angles(0, 0, math.rad(-15 * side))), "Armor")
		for j, offset in { Vector3.new(0, 0, -0.3), Vector3.new(0.25 * side, 0, 0.3) } do
			local base = Vector3.new(1.95 * side, 6.4, 0.05) + offset
			k.spike(base, base + Vector3.new(0.3 * side, 0.9 - j * 0.2, 0.1), 0.3, ice, GLASS, true)
		end
		k.limb("UpperArm", shoulder, elbow, 1.0, skin)
		k.blob("Bicep", Vector3.new(0.85, 1.0, 0.85), shoulder:Lerp(elbow, 0.5) + Vector3.new(0, 0, -0.25), skin)
		k.ball("Elbow", 0.85, elbow, shade)
		k.limb("Forearm", elbow, wrist, 0.92, skin)
		k.limb("Cuff", elbow:Lerp(wrist, 0.65), wrist, 1.08, fur, FABRIC)
		k.blob("Hand", Vector3.new(0.95, 1.0, 0.95), Vector3.new(2.52 * side, 2.3, -0.75), shade)
	end
	-- 오른손 얼음 도끼: 검은 나무 자루 + 얼음 날 두 장 + 얼음 핵
	local hand = Vector3.new(2.52, 2.3, -0.75)
	local dir = Vector3.new(0.1, 0.85, -0.5).Unit
	local top = hand + dir * 2.6
	k.limb("AxeHandle", hand - dir * 0.6, top + dir * 0.3, 0.3, C(55, 45, 40), WOOD)
	k.slot(k.box("AxeCore", Vector3.new(0.5, 0.8, 0.5), CFrame.lookAt(top, top + Vector3.new(0, 0, -1)) * CFrame.new(0, 0, 0), ice, GLASS), "Weapon")
	local side = Vector3.new(0, 0, -1) -- 날은 앞(-Z)으로
	local up = dir
	k.tri(top + up * 0.4 + side * 0.2, top - up * 0.4 + side * 0.2, top + side * 1.3 + up * 0.75, 0.16, ice, GLASS)
	k.tri(top - up * 0.4 + side * 0.2, top + side * 1.3 + up * 0.75, top + side * 1.25 - up * 0.85, 0.16, ice, GLASS)
	k.spike(top + up * 0.35, top + up * 1.0, 0.25, ice, GLASS, true)
	local glow = Instance.new("PointLight")
	glow.Color = ice
	glow.Range = 12
	glow.Brightness = 0.8
	glow.Parent = k.Model:FindFirstChild("Head")
end

-- 베헤모스 (2026-10-10 다시 디자인): 네발 거대 짐승. 검붉은 두꺼운 가죽, 등을 덮은 겹친 돌 비늘판·뼈 가시, 옆구리 용암 틈,
-- 기둥 같은 다리·발굽·발톱, 가시 철퇴 꼬리, 뒤로 휘었다 앞으로 감기는 큰 뿔, 엄니·이빨 줄, 깊은 눈썹 판 아래 작은 붉은 눈 (뿔 끝 높이 약 8.4 × Scale 2)
MOBS.Behemoth = function(k)
	local hide = C(72, 50, 54)
	local belly = C(110, 80, 75)
	local plate = C(55, 42, 46)
	local ivory = C(215, 200, 170)
	local lava = C(255, 90, 30)
	-- 몸통: 가슴·몸통·엉덩이 + 배
	k.slot(k.blob("Chest", Vector3.new(4.0, 3.7, 2.8), Vector3.new(0, 3.8, -2.0), hide, LEATHER), "Armor")
	k.blob("Body", Vector3.new(4.2, 3.5, 6.0), Vector3.new(0, 3.6, 0.4), hide, LEATHER)
	k.slot(k.blob("Hips", Vector3.new(3.8, 3.3, 2.4), Vector3.new(0, 3.75, 2.8), hide, LEATHER), "Armor")
	k.blob("Belly", Vector3.new(3.2, 1.6, 5.2), Vector3.new(0, 2.35, 0.3), belly, LEATHER)
	-- 등 돌 비늘판 5장 + 뼈 가시
	for i = 0, 4 do
		local z = -2.4 + i * 1.25
		local y = 5.45 - math.abs(i - 1.5) * 0.12
		k.box("BackPlate", Vector3.new(2.7, 0.45, 1.5), CFrame.new(0, y, z) * CFrame.Angles(math.rad(-12), 0, 0), plate, SLATE)
		local h = 1.4 - math.abs(i - 1.5) * 0.25
		k.spike(Vector3.new(0, y + 0.1, z + 0.2), Vector3.new(0, y + h, z + 0.65), 0.55, ivory, LIMESTONE, false, Vector3.zAxis)
	end
	-- 옆구리 비늘판 + 용암 틈
	for _, side in { 1, -1 } do
		for j, info in { { -1.6, 4.3 }, { 0.2, 4.1 }, { 2.2, 4.4 } } do
			k.box("SidePlate", Vector3.new(0.3, 1.0, 1.4), CFrame.new(1.95 * side, info[2], info[1]) * CFrame.Angles(0, 0, math.rad(-20 * side)), plate, SLATE)
			k.box("LavaCrack", Vector3.new(0.12, 0.08, 1.1), CFrame.new(2.05 * side, info[2] - 0.75, info[1] + 0.3) * CFrame.Angles(math.rad(j * 15 - 30), 0, math.rad(-15 * side)), lava, NEON)
		end
	end
	local heat = Instance.new("PointLight")
	heat.Color = lava
	heat.Range = 14
	heat.Brightness = 0.9
	heat.Parent = k.Model:FindFirstChild("Body")
	-- 다리 넷: 윗다리 근육 → 기둥 다리 → 무릎 → 아랫다리 → 발굽 + 발톱 2
	for _, x in { 1.6, -1.6 } do
		for _, z in { -1.8, 2.5 } do
			k.blob("UpperLeg", Vector3.new(1.6, 2.1, 1.8), Vector3.new(x, 3.3, z), hide, LEATHER)
			local knee = Vector3.new(x * 1.06, 1.7, z + (if z < 0 then -0.1 else 0.15))
			k.limb("Leg", Vector3.new(x, 2.9, z), knee, 1.4, hide, LEATHER)
			k.ball("Knee", 1.3, knee, plate, SLATE)
			k.limb("Shin", knee, Vector3.new(x * 1.06, 0.55, z), 1.2, hide, LEATHER)
			k.disc("Hoof", 0.6, 1.6, CFrame.new(x * 1.06, 0.3, z - 0.05) * CFrame.Angles(0, 0, math.rad(90)), C(40, 32, 30), BASALT)
			for _, c in { -0.35, 0.35 } do
				local base = Vector3.new(x * 1.06 + c, 0.25, z - 0.75)
				k.spike(base, base + Vector3.new(c * 0.2, -0.15, -0.5), 0.3, ivory, LIMESTONE, false, Vector3.xAxis)
			end
		end
	end
	-- 꼬리 + 가시 철퇴
	local tail = { Vector3.new(0, 4.0, 3.7), Vector3.new(0, 3.6, 4.6), Vector3.new(0, 3.1, 5.3) }
	for i = 1, #tail - 1 do
		k.limb("Tail", tail[i], tail[i + 1], 0.9 - i * 0.2, hide, LEATHER)
	end
	local club = Vector3.new(0, 3.0, 5.6)
	k.slot(k.blob("TailClub", Vector3.new(1.1, 0.9, 1.2), club, plate, SLATE), "Weapon")
	for _, out in { Vector3.new(1, 0.2, 0), Vector3.new(-1, 0.2, 0), Vector3.new(0, 1, 0.2), Vector3.new(0, -0.2, 1) } do
		local d = out.Unit
		k.spike(club + d * 0.45, club + d * 1.0, 0.3, ivory, LIMESTONE)
	end
	-- 머리: 큰 머리 + 주둥이 + 아래턱 + 눈썹 판 + 이마 판 + 붉은 눈 + 콧구멍 + 엄니·이빨 + 귀 + 큰 뿔
	k.slot(k.blob("Head", Vector3.new(2.8, 2.4, 2.6), Vector3.new(0, 4.4, -3.6), hide, LEATHER), "Head")
	k.blob("Snout", Vector3.new(2.0, 1.4, 1.8), Vector3.new(0, 3.9, -4.75), belly, LEATHER)
	k.blob("Jaw", Vector3.new(1.8, 0.7, 1.6), Vector3.new(0, 3.2, -4.5), hide, LEATHER, nil, CFrame.Angles(math.rad(8), 0, 0))
	k.box("BrowPlate", Vector3.new(2.6, 0.55, 1.0), CFrame.new(0, 5.1, -4.3) * CFrame.Angles(math.rad(15), 0, 0), plate, SLATE)
	k.box("ForeheadPlate", Vector3.new(1.4, 0.4, 1.3), CFrame.new(0, 5.5, -3.6) * CFrame.Angles(math.rad(-10), 0, 0), plate, SLATE)
	for _, side in { 1, -1 } do
		k.ball("Socket", 0.45, Vector3.new(0.78 * side, 4.72, -4.62), C(25, 15, 15))
		k.slot(k.ball("Eye", 0.24, Vector3.new(0.78 * side, 4.72, -4.8), C(255, 60, 40), NEON), "Eye")
		k.ball("Nostril", 0.3, Vector3.new(0.42 * side, 4.15, -5.58), C(30, 20, 20))
		k.spike(Vector3.new(0.72 * side, 3.4, -5.15), Vector3.new(0.92 * side, 4.25, -5.65), 0.32, ivory, LIMESTONE, true) -- 아래 엄니
		for t = 0, 1 do
			local base = Vector3.new((0.25 + t * 0.25) * side, 3.48, -5.45 + t * 0.2)
			k.spike(base, base + Vector3.new(0, 0.3, 0), 0.14, ivory, LIMESTONE, false, Vector3.xAxis) -- 아래 이빨
		end
		k.blob("Ear", Vector3.new(0.3, 0.6, 0.8), Vector3.new(1.45 * side, 5.0, -3.1), hide, LEATHER, nil, CFrame.Angles(0, 0, math.rad(-30 * side)))
		-- 뿔: 머리 옆에서 뒤·위로 휘었다가 앞으로 감긴다 (마디가 점점 가늘어짐)
		local horn = { Vector3.new(1.15 * side, 5.3, -3.4), Vector3.new(1.85 * side, 6.0, -3.0), Vector3.new(2.35 * side, 7.0, -3.2), Vector3.new(2.3 * side, 7.9, -3.8), Vector3.new(1.95 * side, 8.35, -4.4) }
		for i = 1, #horn - 1 do
			local hornPart = k.limb("Horn", horn[i], horn[i + 1], 0.95 - i * 0.17, if i % 2 == 0 then ivory else ivory:Lerp(C(150, 130, 100), 0.3), LIMESTONE)
			if i >= 3 then
				k.slot(hornPart, "Weapon")
			end
		end
		k.spike(horn[5], horn[5] + (horn[5] - horn[4]).Unit * 0.5, 0.25, ivory, LIMESTONE)
	end
	k.box("Mouth", Vector3.new(1.3, 0.12, 0.15), CFrame.new(0, 3.55, -5.55), C(35, 15, 15))
end

-- 바다 생물 (2026-10-09): 기준점 = 몸 아래, 앞 = -Z. 서버 MobService가 물 속에서 헤엄치게 옮긴다
-- (물고기·황금 물고기·복어 모델은 2026-10-10 사용자 요청으로 삭제. 남은 템플릿·아이콘은 아래에서 지운다)
-- 낙지 (2026-10-10 다시 디자인): 진짜 문어처럼 뒤로 처진 주머니 몸통(얼룩무늬), 눈 혹 위 가로 막대 동공의 금색 눈,
-- 옆 물총 구멍, 다리 사이 막, 끝으로 갈수록 가늘게 말리는 다리 8개(아래 빨판)
MOBS.Octopus = function(k)
	local red = C(160, 70, 60)
	local dark = C(105, 40, 38)
	local pale = C(225, 175, 160)
	k.slot(k.blob("Mantle", Vector3.new(1.5, 2.0, 1.7), Vector3.new(0, 2.25, 0.5), red, SMOOTH, nil, CFrame.Angles(math.rad(28), 0, 0)), "Head")
	k.slot(k.blob("HeadBase", Vector3.new(1.6, 1.0, 1.45), Vector3.new(0, 1.45, -0.1), red), "Armor")
	for i, p in { Vector3.new(0.4, 2.6, 0.2), Vector3.new(-0.35, 2.3, 0.0), Vector3.new(0.1, 2.95, 0.75), Vector3.new(-0.45, 2.85, 0.6), Vector3.new(0.55, 2.1, 0.9) } do
		k.blob("Spot", Vector3.new(0.3, 0.22, 0.08), p + Vector3.new(0, 0, -0.62 + i * 0.05), dark, SMOOTH, nil, CFrame.Angles(math.rad(28), 0, 0))
	end
	for _, side in { 1, -1 } do
		k.blob("EyeBump", Vector3.new(0.45, 0.42, 0.45), Vector3.new(0.55 * side, 1.78, -0.5), red)
		k.ball("Eyeball", 0.3, Vector3.new(0.6 * side, 1.8, -0.64), C(210, 170, 60))
		k.slot(k.box("Pupil", Vector3.new(0.18, 0.05, 0.04), CFrame.new(0.62 * side, 1.8, -0.79), C(15, 10, 10)), "Eye")
		k.blob("Lid", Vector3.new(0.4, 0.14, 0.3), Vector3.new(0.6 * side, 1.95, -0.62), dark)
	end
	k.limb("Siphon", Vector3.new(0.65, 1.4, 0.1), Vector3.new(0.95, 1.3, 0.25), 0.22, dark)
	k.blob("Web", Vector3.new(2.1, 0.25, 2.1), Vector3.new(0, 1.05, -0.05), dark)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2 + math.pi / 8
		local function at(r: number, y: number, twist: number): Vector3
			return Vector3.new(math.cos(a + twist) * r, y, math.sin(a + twist) * r - 0.05)
		end
		local points = { at(0.5, 1.15, 0), at(0.95, 0.65, 0.05), at(1.35, 0.3, 0.15), at(1.7, 0.25, 0.35), at(1.85, 0.45, 0.6), at(1.7, 0.7, 0.85) }
		for j = 1, #points - 1 do
			k.limb("Arm", points[j], points[j + 1], 0.36 - j * 0.06, red)
		end
		for j = 2, 3 do
			k.ball("Sucker", 0.13, points[j] - Vector3.new(0, 0.12, 0), pale)
		end
	end
end

-- 해파리 (2026-10-10 다시 디자인): 눈·입 없이 반투명 갓 + 안쪽 갓, 네 잎 생식선(빛), 갓 위 방사 수관, 갓 가장자리 주름,
-- 주름진 입 팔 4개, 가늘고 긴 촉수 12개 (빛)
MOBS.Jellyfish = function(k)
	local bell = C(195, 170, 240)
	local glow = C(240, 150, 220)
	k.slot(k.blob("Bell", Vector3.new(2.2, 1.3, 2.2), Vector3.new(0, 2.35, 0), bell, GLASS, 0.45), "Core")
	k.blob("InnerBell", Vector3.new(1.7, 0.85, 1.7), Vector3.new(0, 2.25, 0), C(220, 200, 255), NEON, 0.75)
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + math.pi / 4
		k.blob("Gonad", Vector3.new(0.5, 0.18, 0.28), Vector3.new(math.cos(a) * 0.38, 2.4, math.sin(a) * 0.38), glow, NEON, 0.2, CFrame.Angles(0, -a, 0))
	end
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		k.limb("Canal", Vector3.new(math.cos(a) * 0.15, 2.98, math.sin(a) * 0.15), Vector3.new(math.cos(a) * 1.0, 2.35, math.sin(a) * 1.0), 0.035, glow, NEON)
	end
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		k.blob("Rim", Vector3.new(0.5, 0.18, 0.3), Vector3.new(math.cos(a) * 1.0, 1.8, math.sin(a) * 1.0), bell, GLASS, 0.4, CFrame.Angles(0, -a, 0))
	end
	-- 주름진 입 팔 4개 (마디마다 좌우로 흔들려 내려감)
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2
		for j = 0, 4 do
			local wobble = math.sin(j * 1.3 + i) * 0.12
			local r = 0.2 + j * 0.05
			k.blob("OralArm", Vector3.new(0.3 - j * 0.03, 0.35, 0.14), Vector3.new(math.cos(a + wobble) * r, 1.6 - j * 0.3, math.sin(a + wobble) * r), C(230, 190, 255), GLASS, 0.3, CFrame.Angles(0, -a, math.rad(20 * (if j % 2 == 0 then 1 else -1))))
		end
	end
	-- 가는 촉수 12개
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2 + 0.13
		local top = Vector3.new(math.cos(a) * 0.95, 1.75, math.sin(a) * 0.95)
		local mid = Vector3.new(math.cos(a + 0.25) * 1.05, 1.0, math.sin(a + 0.25) * 1.05)
		local bottom = Vector3.new(math.cos(a) * 0.9, 0.15, math.sin(a) * 0.9)
		k.limb("Tentacle", top, mid, 0.045, C(225, 195, 255), NEON)
		k.limb("Tentacle", mid, bottom, 0.035, C(225, 195, 255), NEON)
	end
	local light = Instance.new("PointLight")
	light.Color = C(220, 180, 255)
	light.Range = 8
	light.Brightness = 0.6
	light.Parent = k.Model:FindFirstChild("InnerBell")
end

-- 상어 (2026-10-10 다시 디자인): 백상아리처럼 어뢰 몸통(마디로 가늘어짐)·회색 등 + 흰 배, 뾰족한 주둥이, 작고 까만 눈,
-- 아가미 틈 5줄, 넓게 뒤로 젖힌 가슴지느러미, 높은 등지느러미 + 작은 둘째 등지느러미, 위가 긴 초승달 꼬리,
-- 살짝 벌린 입 속 잇몸과 톱니 이빨 줄, 옆구리 흉터 (Config.Mobs.Shark.Scale배)
MOBS.Shark = function(k)
	local grey = C(98, 112, 125)
	local dark = C(70, 80, 92)
	local white = C(232, 234, 236)
	local y = 0.95
	k.blob("Snout", Vector3.new(0.75, 0.62, 1.1), Vector3.new(0, y + 0.08, -2.05), grey)
	k.slot(k.blob("Head", Vector3.new(1.2, 1.25, 1.6), Vector3.new(0, y, -1.25), grey), "Head")
	k.slot(k.blob("Body", Vector3.new(1.42, 1.5, 2.3), Vector3.new(0, y, -0.05), grey), "Armor")
	k.blob("Rear", Vector3.new(1.0, 1.05, 1.7), Vector3.new(0, y + 0.05, 1.35), grey)
	k.blob("Tail", Vector3.new(0.45, 0.6, 1.2), Vector3.new(0, y + 0.1, 2.3), dark)
	for _, info in { { -1.25, 1.1, 1.35 }, { -0.05, 1.3, 2.1 }, { 1.3, 0.9, 1.5 } } do
		k.blob("Belly", Vector3.new(info[2], 0.7, info[3]), Vector3.new(0, y - 0.35, info[1]), white)
	end
	-- 지느러미 (세모 판)
	k.tri(Vector3.new(0, y + 0.62, 0.35), Vector3.new(0, y + 0.62, -0.6), Vector3.new(0, y + 1.85, 0.55), 0.14, dark) -- 등지느러미
	k.tri(Vector3.new(0, y + 0.45, 1.75), Vector3.new(0, y + 0.45, 1.45), Vector3.new(0, y + 0.8, 1.85), 0.08, dark) -- 둘째 등지느러미
	k.tri(Vector3.new(0, y + 0.15, 2.7), Vector3.new(0, y - 0.05, 2.9), Vector3.new(0, y + 1.35, 3.45), 0.12, dark) -- 꼬리 위
	k.tri(Vector3.new(0, y + 0.05, 2.75), Vector3.new(0, y + 0.15, 2.95), Vector3.new(0, y - 0.7, 3.25), 0.12, dark) -- 꼬리 아래
	for _, side in { 1, -1 } do
		k.tri(Vector3.new(side * 0.5, y - 0.35, -0.85), Vector3.new(side * 0.5, y - 0.4, -0.15), Vector3.new(side * 1.55, y - 0.85, 0.3), 0.1, grey) -- 가슴지느러미
		k.tri(Vector3.new(side * 0.25, y - 0.4, 1.3), Vector3.new(side * 0.25, y - 0.38, 1.6), Vector3.new(side * 0.55, y - 0.65, 1.75), 0.06, grey) -- 배지느러미
		for i = 0, 4 do
			k.box("Gill", Vector3.new(0.04, 0.42 - i * 0.03, 0.05), CFrame.new(side * 0.6, y + 0.02, -0.98 + i * 0.13) * CFrame.Angles(0, 0, math.rad(8 * side)), C(45, 52, 60))
		end
		k.slot(k.ball("Eye", 0.13, Vector3.new(side * 0.46, y + 0.22, -1.8), C(10, 10, 12)), "Eye")
	end
	k.box("Scar", Vector3.new(0.04, 0.05, 0.6), CFrame.new(0.71, y + 0.25, 0.2) * CFrame.Angles(math.rad(10), 0, 0), C(160, 165, 170))
	-- 살짝 벌린 입 + 잇몸 + 톱니 이빨 (위 7, 아래 5)
	k.blob("Mouth", Vector3.new(0.85, 0.3, 0.55), Vector3.new(0, y - 0.25, -2.05), C(55, 20, 25))
	k.blob("Gum", Vector3.new(0.8, 0.1, 0.5), Vector3.new(0, y - 0.13, -2.05), C(170, 70, 80))
	for i = -3, 3 do
		local base = Vector3.new(i * 0.1, y - 0.14, -2.27 + math.abs(i) * 0.05)
		k.spike(base, base + Vector3.new(0, -0.16, -0.01), 0.09, C(250, 248, 238), SMOOTH, false, Vector3.xAxis)
	end
	for i = -2, 2 do
		local base = Vector3.new(i * 0.1, y - 0.38, -2.22 + math.abs(i) * 0.05)
		k.spike(base, base + Vector3.new(0, 0.14, -0.01), 0.08, C(240, 238, 225), SMOOTH, false, Vector3.xAxis)
	end
end

-- 예전 버그베어 템플릿·아이콘은 사이클롭스로 바뀌어서 지운다
-- 물고기·황금 물고기·복어 템플릿과 복어 가시·황금 비늘 아이콘도 지운다 (2026-10-10 삭제)
for _, name in { "Bugbear", "Fish", "GoldenFish", "Pufferfish" } do
	local stale = mobFolder:FindFirstChild(name)
	if stale then
		stale:Destroy()
	end
end
for _, name in { "BugbearFur", "PufferSpine", "GoldenScale" } do
	local stale = iconFolder:FindFirstChild(name)
	if stale then
		stale:Destroy()
	end
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
-- 괴 모양 아이콘 (아래 넓은 판 + 위 좁은 판 + 도장). 미스릴·오리하르콘괴 (2026-10-09)
local function ingotIcon(m: Model, color: Color3, stamp: Color3, round: boolean)
	part({ Name = "Base", Size = Vector3.new(1.6, 0.32, 0.8), Color = color, Material = METAL }, m)
	part({ Name = "Top", Size = Vector3.new(1.3, 0.26, 0.58), CFrame = CFrame.new(0, 0.29, 0), Color = color:Lerp(C(255, 255, 255), 0.15), Material = METAL }, m)
	if round then
		part({ Name = "Stamp", Shape = Enum.PartType.Ball, Size = Vector3.new(0.26, 0.26, 0.26), CFrame = CFrame.new(0, 0.44, 0), Color = stamp, Material = NEON }, m)
	else
		for _, angle in { 25, -25 } do
			part({ Name = "Rune", Size = Vector3.new(0.7, 0.05, 0.07), CFrame = CFrame.new(0, 0.43, 0) * CFrame.Angles(0, math.rad(angle), 0), Color = stamp, Material = NEON }, m)
		end
	end
end

-- 원소의 돌 아이콘 (2026-10-10): 거친 돌 받침에 박힌 원소 결정 셋 (가운데 빛나는 큰 결정) + 원소마다 장식
local function elementStoneIcon(m: Model, color: Color3, glow: Color3, style: string)
	local base = if style == "Earth" then C(120, 90, 60) else C(72, 66, 62)
	part({ Name = "Rock", Size = Vector3.new(1.3, 0.55, 1.0), CFrame = CFrame.new(0, -0.45, 0) * CFrame.Angles(0, math.rad(15), math.rad(4)), Color = base, Material = Enum.Material.Slate }, m)
	part({ Name = "Rock", Size = Vector3.new(0.6, 0.45, 0.6), CFrame = CFrame.new(0.5, -0.25, 0.15) * CFrame.Angles(0.3, 0.5, 0.2), Color = base:Lerp(C(0, 0, 0), 0.2), Material = Enum.Material.Slate }, m)
	for i, info in { { 0, 1.25, 0, 0 }, { -0.38, 0.75, -20, 0.1 }, { 0.35, 0.65, 25, -0.1 } } do
		local width = if i == 1 then 0.42 else 0.34
		part({
			Name = "Crystal", Size = Vector3.new(width, info[2], width), CFrame = CFrame.new(info[1], -0.2 + info[2] / 2, info[4]) * CFrame.Angles(0, math.rad(45), math.rad(info[3])),
			Color = if i == 1 then glow else color, Material = if i == 1 then NEON else GLASS, Transparency = if i == 1 then 0.05 else 0.15,
		}, m)
	end
	if style == "Fire" then
		for _, x in { -0.25, 0.28 } do
			triangle(m, Vector3.new(x - 0.12, 0.6, -0.25), Vector3.new(x + 0.12, 0.6, -0.25), Vector3.new(x, 1.05, -0.25), 0.05, C(255, 160, 50), NEON, nil, true) -- 불꽃
		end
	elseif style == "Frost" then
		part({ Name = "Snow", Size = Vector3.new(1.2, 0.12, 0.9), CFrame = CFrame.new(0, -0.15, 0) * CFrame.Angles(0, math.rad(15), 0), Color = C(240, 248, 255), Material = Enum.Material.Snow }, m)
	elseif style == "Earth" then
		part({ Name = "Band", Size = Vector3.new(1.32, 0.08, 1.02), CFrame = CFrame.new(0, -0.35, 0) * CFrame.Angles(0, math.rad(15), math.rad(4)), Color = C(255, 170, 60), Material = NEON }, m)
	else
		part({ Name = "Gust", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.05, 1.3, 1.3), CFrame = CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(80)) * CFrame.Angles(math.rad(20), 0, 0), Color = glow, Material = NEON, Transparency = 0.3 }, m)
	end
end

local LOOT_ICONS = {
	-- 원소의 돌 (2026-10-10): 원소 보스 전리품
	FireStone = function(m)
		elementStoneIcon(m, C(255, 95, 25), C(255, 190, 80), "Fire")
	end,
	FrostStone = function(m)
		elementStoneIcon(m, C(120, 210, 255), C(200, 245, 255), "Frost")
	end,
	EarthStone = function(m)
		elementStoneIcon(m, C(200, 130, 55), C(255, 190, 80), "Earth")
	end,
	WindStone = function(m)
		elementStoneIcon(m, C(120, 230, 150), C(200, 255, 215), "Wind")
	end,
	-- 바다 생물 전리품·음식 (2026-10-09)
	FishMeat = function(m) -- 생선: 분홍 살 + 하얀 줄 + 은빛 껍질
		part({ Name = "Skin", Size = Vector3.new(1.7, 0.3, 0.95), CFrame = CFrame.new(0, -0.12, 0), Color = C(150, 175, 200), Material = METAL }, m)
		part({ Name = "Flesh", Size = Vector3.new(1.6, 0.3, 0.85), CFrame = CFrame.new(0, 0.12, 0), Color = C(240, 150, 130) }, m)
		for i = -2, 2 do
			part({ Name = "Line", Size = Vector3.new(0.06, 0.04, 0.8), CFrame = CFrame.new(i * 0.3, 0.28, 0) * CFrame.Angles(0, math.rad(20), 0), Color = C(255, 230, 220) }, m)
		end
	end,
	OctopusLeg = function(m) -- 낙지 다리: 돌돌 말린 분홍 다리 + 빨판
		for i = 0, 6 do
			local a = i * 0.8
			local r = 0.75 - i * 0.08
			local position = Vector3.new(math.cos(a) * r, i * 0.06, math.sin(a) * r)
			part({ Name = "Leg", Shape = Enum.PartType.Ball, Size = Vector3.one * (0.55 - i * 0.05), CFrame = CFrame.new(position), Color = C(230, 110, 120) }, m)
			part({ Name = "Sucker", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.16, CFrame = CFrame.new(position + Vector3.new(0, -0.2, 0)), Color = C(255, 195, 200) }, m)
		end
	end,
	-- 거대 몬스터 전리품 (2026-10-10): 방어구 재료
	GolemPlate = function(m) -- 골렘 돌판: 두꺼운 회색 돌판 + 금 + 이끼 + 초록 빛 금
		part({ Name = "Plate", Size = Vector3.new(1.6, 0.35, 1.2), CFrame = CFrame.Angles(0, 0, math.rad(5)), Color = C(135, 130, 125), Material = Enum.Material.Slate }, m)
		part({ Name = "Edge", Size = Vector3.new(1.4, 0.2, 1.0), CFrame = CFrame.new(0.05, 0.22, 0.03) * CFrame.Angles(0, math.rad(8), math.rad(5)), Color = C(110, 106, 100), Material = Enum.Material.Slate }, m)
		part({ Name = "Moss", Size = Vector3.new(0.5, 0.08, 0.35), CFrame = CFrame.new(-0.45, 0.35, 0.3), Color = C(95, 140, 70), Material = Enum.Material.Grass }, m)
		part({ Name = "Crack", Size = Vector3.new(0.9, 0.06, 0.06), CFrame = CFrame.new(0.15, 0.34, -0.15) * CFrame.Angles(0, math.rad(30), 0), Color = C(80, 255, 170), Material = NEON }, m)
	end,
	GolemCore = function(m) -- 골렘 핵: 빛나는 초록 보석 + 돌 테두리
		local gem = part({ Name = "Gem", Size = Vector3.new(0.9, 0.9, 0.9), CFrame = CFrame.Angles(math.rad(45), math.rad(45), 0), Color = C(80, 255, 170), Material = NEON }, m)
		gem.Transparency = 0.1
		for i = 0, 3 do
			local a = i / 4 * math.pi * 2
			part({ Name = "Rock", Size = Vector3.new(0.45, 0.45, 0.45), CFrame = CFrame.new(math.cos(a) * 0.7, math.sin(a) * 0.7, 0.1) * CFrame.Angles(a, a, 0), Color = C(120, 115, 110), Material = Enum.Material.Slate }, m)
		end
	end,
	FrostHide = function(m) -- 서리 거인 가죽: 하얀 털 가죽 + 푸른 줄무늬 + 얼음 조각
		part({ Name = "Pelt", Size = Vector3.new(1.7, 0.16, 1.2), CFrame = CFrame.Angles(0, 0, math.rad(6)), Color = C(232, 240, 250), Material = Enum.Material.Fabric }, m)
		for _, z in { -0.3, 0.1, 0.45 } do
			part({ Name = "Stripe", Size = Vector3.new(1.2, 0.18, 0.1), CFrame = CFrame.new(0, 0.02, z) * CFrame.Angles(0, math.rad(10), math.rad(6)), Color = C(150, 205, 245), Material = Enum.Material.Fabric }, m)
		end
		part({ Name = "Ice", Size = Vector3.new(0.3, 0.5, 0.3), CFrame = CFrame.new(0.7, 0.3, -0.4) * CFrame.Angles(0, math.rad(45), math.rad(20)), Color = C(175, 230, 255), Material = Enum.Material.Glass }, m)
	end,
	FrostCrystal = function(m) -- 서리 수정: 뾰족한 하늘색 얼음 수정 세 개
		for i, info in { { 0, 1.4, 0 }, { -0.35, 0.9, -25 }, { 0.35, 1.0, 25 } } do
			local crystal = part({ Name = "Crystal", Size = Vector3.new(0.38, info[2], 0.38), CFrame = CFrame.new(info[1], info[2] / 2 - 0.5, 0) * CFrame.Angles(0, math.rad(45), math.rad(info[3])), Color = if i == 1 then C(200, 240, 255) else C(150, 220, 255), Material = if i == 1 then NEON else Enum.Material.Glass }, m)
			crystal.Transparency = if i == 1 then 0.1 else 0.2
		end
		part({ Name = "Base", Size = Vector3.new(1.0, 0.2, 0.6), CFrame = CFrame.new(0, -0.55, 0), Color = C(230, 240, 250), Material = Enum.Material.Snow }, m)
	end,
	BehemothScale = function(m) -- 베헤모스 비늘: 검보라 비늘 판 + 붉은 테 + 결
		local face = CFrame.Angles(0, math.rad(90), 0)
		part({ Name = "Scale", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.18, 1.4, 1.4), CFrame = face, Color = C(110, 70, 95), Material = Enum.Material.Slate }, m)
		part({ Name = "Rim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.14, 1.55, 1.55), CFrame = CFrame.new(0, 0, 0.03) * face, Color = C(190, 60, 70), Material = METAL }, m)
		for i = -1, 1 do
			part({ Name = "Ridge", Size = Vector3.new(0.07, 1.0 - math.abs(i) * 0.3, 0.08), CFrame = CFrame.new(i * 0.32, 0, -0.1), Color = C(150, 100, 130), Material = METAL }, m)
		end
	end,
	BehemothHorn = function(m) -- 베헤모스 뿔: 휘어진 상아색 뿔 (마디가 점점 가늘어짐) + 붉은 끝
		local points = { Vector3.new(-0.6, -0.6, 0), Vector3.new(-0.3, 0, 0), Vector3.new(0.1, 0.45, 0), Vector3.new(0.55, 0.7, 0) }
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			local d = 0.5 - i * 0.11
			part({ Name = "Horn", Shape = Enum.PartType.Cylinder, Size = Vector3.new((b - a).Magnitude + d * 0.4, d, d), CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0), Color = C(240, 225, 190) }, m)
		end
		part({ Name = "Tip", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.2, CFrame = CFrame.new(points[4]), Color = C(200, 60, 70), Material = NEON }, m)
		part({ Name = "Band", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 0.55, 0.55), CFrame = CFrame.lookAt(points[1], points[2]) * CFrame.new(0, 0, -0.15) * CFrame.Angles(0, math.rad(90), 0), Color = C(110, 70, 95), Material = METAL }, m)
	end,
	InkSac = function(m) -- 먹물 주머니: 검보라 주머니 + 묶은 끈 + 먹물 방울
		local sac = part({ Name = "Sac", Size = Vector3.new(1.1, 1.3, 1.1), Color = C(45, 40, 60), Material = Enum.Material.SmoothPlastic }, m)
		Instance.new("SpecialMesh", sac).MeshType = Enum.MeshType.Sphere
		part({ Name = "Neck", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.35, 0.4, 0.4), CFrame = CFrame.new(0, 0.75, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = C(45, 40, 60) }, m)
		part({ Name = "Tie", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 0.5, 0.5), CFrame = CFrame.new(0, 0.7, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = C(230, 110, 120) }, m)
		part({ Name = "Drop", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.3, CFrame = CFrame.new(0.5, -0.65, -0.2), Color = C(25, 20, 35), Material = GLASS }, m)
		part({ Name = "Shine", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.18, CFrame = CFrame.new(-0.25, 0.3, -0.48), Color = C(200, 190, 230), Material = NEON }, m)
	end,
	JellyfishJelly = function(m) -- 해파리 젤리: 반투명 보라 젤리
		local jelly = part({ Name = "Jelly", Size = Vector3.new(1.3, 0.8, 1.3), Color = C(205, 175, 255), Material = GLASS, Transparency = 0.25 }, m)
		Instance.new("SpecialMesh", jelly).MeshType = Enum.MeshType.Sphere
		part({ Name = "Core", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.45, Color = C(240, 170, 230), Material = NEON }, m)
	end,
	SharkTooth = function(m) -- 상어 이빨: 하얀 세모 이빨 + 톱니
		triangle(m, Vector3.new(-0.5, 0, 0), Vector3.new(0.5, 0, 0), Vector3.new(0, 1.3, 0), 0.25, C(250, 248, 235), Enum.Material.SmoothPlastic, nil, true)
		part({ Name = "Root", Size = Vector3.new(1.1, 0.25, 0.32), CFrame = CFrame.new(0, -0.1, 0), Color = C(220, 200, 180) }, m)
	end,
	SharkSkin = function(m) -- 상어 가죽: 회색 가죽 한 장(아래 흰 면) + 지느러미 조각
		part({ Name = "Hide", Size = Vector3.new(1.7, 0.14, 1.1), CFrame = CFrame.Angles(0, 0, math.rad(6)), Color = C(120, 140, 165), Material = Enum.Material.Leather }, m)
		part({ Name = "Under", Size = Vector3.new(1.6, 0.08, 1.0), CFrame = CFrame.new(0, -0.1, 0) * CFrame.Angles(0, 0, math.rad(6)), Color = C(235, 238, 242), Material = Enum.Material.Leather }, m)
		triangle(m, Vector3.new(-0.2, 0.08, 0), Vector3.new(0.4, 0.1, 0), Vector3.new(0.3, 0.75, 0), 0.1, C(105, 125, 150), Enum.Material.Leather, nil, true)
	end,
	-- 두 번째 전리품·보스 전리품 (2026-10-09)
	CerberusHide = function(m) -- 케르베로스 털가죽: 검붉은 털 가죽 한 장 + 꼬리 불꽃
		local fur = C(85, 65, 72)
		part({ Name = "Pelt", Size = Vector3.new(1.6, 0.14, 1.2), CFrame = CFrame.Angles(0, 0, math.rad(6)), Color = fur, Material = Enum.Material.Fabric }, m)
		part({ Name = "Belly", Size = Vector3.new(0.9, 0.16, 0.6), CFrame = CFrame.new(0, 0.03, 0) * CFrame.Angles(0, 0, math.rad(6)), Color = C(130, 105, 112), Material = Enum.Material.Fabric }, m)
		for _, x in { 0.8, -0.8 } do
			for _, z in { 0.5, -0.5 } do
				part({ Name = "Leg", Size = Vector3.new(0.35, 0.1, 0.35), CFrame = CFrame.new(x * 1.05, x * 0.08, z * 1.15) * CFrame.Angles(0, math.rad(x * z * 40), 0), Color = fur, Material = Enum.Material.Fabric }, m)
			end
		end
		part({ Name = "Flame", Shape = Enum.PartType.Ball, Size = Vector3.new(0.32, 0.32, 0.32), CFrame = CFrame.new(-1.0, 0, 0), Color = C(255, 140, 50), Material = NEON }, m)
	end,
	CyclopsHide = function(m) -- 사이클롭스 가죽: 둘둘 만 두꺼운 가죽 + 끈 + 눈 도장
		local hide = C(165, 170, 115)
		part({ Name = "Roll", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 0.7, 0.7), Color = hide, Material = Enum.Material.Leather }, m)
		part({ Name = "Flap", Size = Vector3.new(1.5, 0.08, 0.55), CFrame = CFrame.new(0, -0.3, -0.45) * CFrame.Angles(math.rad(-20), 0, 0), Color = hide:Lerp(C(0, 0, 0), 0.1), Material = Enum.Material.Leather }, m)
		for _, x in { 0.5, -0.5 } do
			part({ Name = "Tie", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 0.74, 0.74), CFrame = CFrame.new(x, 0, 0), Color = C(90, 60, 35), Material = Enum.Material.Leather }, m)
		end
		part({ Name = "EyeMark", Shape = Enum.PartType.Ball, Size = Vector3.new(0.22, 0.22, 0.22), CFrame = CFrame.new(0, 0.05, -0.33), Color = C(230, 120, 30) }, m)
	end,
	BossToken = function(m) -- 보스의 증표: 금 메달 + 왕관 + 빨간 보석 + 리본
		local face = CFrame.Angles(0, math.rad(90), 0) -- 원판이 앞(카메라 쪽)을 본다
		part({ Name = "Ribbon", Size = Vector3.new(0.3, 0.9, 0.05), CFrame = CFrame.new(-0.25, -0.75, 0.08) * CFrame.Angles(0, 0, math.rad(-12)), Color = C(200, 40, 50), Material = Enum.Material.Fabric }, m)
		part({ Name = "Ribbon", Size = Vector3.new(0.3, 0.9, 0.05), CFrame = CFrame.new(0.25, -0.75, 0.08) * CFrame.Angles(0, 0, math.rad(12)), Color = C(200, 40, 50), Material = Enum.Material.Fabric }, m)
		part({ Name = "Coin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 1.4, 1.4), CFrame = face, Color = C(240, 190, 60), Material = METAL }, m)
		part({ Name = "Rim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.24, 1.15, 1.15), CFrame = face, Color = C(255, 220, 120), Material = METAL }, m)
		part({ Name = "Inner", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.28, 0.95, 0.95), CFrame = face, Color = C(230, 175, 50), Material = METAL }, m)
		for i, x in { -0.25, 0, 0.25 } do
			part({ Name = "Crown", Size = Vector3.new(0.14, if i == 2 then 0.36 else 0.26, 0.06), CFrame = CFrame.new(x, 0.12, -0.16), Color = C(255, 225, 130), Material = METAL }, m)
		end
		part({ Name = "CrownBase", Size = Vector3.new(0.66, 0.12, 0.06), CFrame = CFrame.new(0, -0.05, -0.16), Color = C(255, 225, 130), Material = METAL }, m)
		part({ Name = "Gem", Shape = Enum.PartType.Ball, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(0, -0.28, -0.16), Color = C(255, 60, 70), Material = NEON }, m)
	end,
	MithrilIngot = function(m)
		ingotIcon(m, C(175, 205, 240), C(90, 170, 255), false)
	end,
	OrichalcumIngot = function(m)
		ingotIcon(m, C(240, 182, 58), C(255, 130, 30), true)
	end,
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
	CyclopsEye = function(m)
		part({ Name = "White", Shape = Enum.PartType.Ball, Size = Vector3.new(1.3, 1.3, 1.3), Color = C(250, 250, 245) }, m)
		part({ Name = "Iris", Shape = Enum.PartType.Ball, Size = Vector3.new(0.75, 0.75, 0.75), CFrame = CFrame.new(0, 0, -0.42), Color = C(230, 120, 30) }, m)
		part({ Name = "Pupil", Shape = Enum.PartType.Ball, Size = Vector3.new(0.38, 0.38, 0.38), CFrame = CFrame.new(0, 0, -0.7), Color = C(20, 15, 20) }, m)
		part({ Name = "Shine", Shape = Enum.PartType.Ball, Size = Vector3.new(0.16, 0.16, 0.16), CFrame = CFrame.new(0.15, 0.15, -0.82), Color = C(255, 255, 255), Material = NEON }, m)
		for i = 0, 2 do -- 빨간 핏줄
			part({ Name = "Vein", Size = Vector3.new(0.04, 0.35, 0.04), CFrame = CFrame.new(0.5 * math.cos(i * 2.1), 0.5 * math.sin(i * 2.1), -0.45) * CFrame.Angles(0, 0, i * 2.1), Color = C(220, 60, 60) }, m)
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

---------------------------------------------------------------- 3-2. 장비 아이콘 (장신구는 칸마다 모양·단계마다 색, 방어구는 세트마다 모양 2026-10-10)
local EQUIPMENT_ICONS = { -- 장신구 (목걸이·팔찌). 방어구 4칸은 아래 ARMOR_ICONS
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
-- 방어구 세트 아이콘 (2026-10-10): 헬멧·갑옷·신발·장갑은 세트(EquipmentDefs.Set)마다 모양을 다르게 짓는다
-- 색·재질은 캐릭터 겉모습과 같은 Config.GearVisual.Sets. 아이콘 카메라는 +Z 쪽에서 보므로 얼굴·앞 장식은 +Z
local ICON_SETS = Config.GearVisual.Sets
local BALL = Enum.PartType.Ball
local CYL = Enum.PartType.Cylinder
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- 원기둥 축을 위로
local function iball(m, name, d, cf, color, mat)
	return part({ Name = name, Shape = BALL, Size = Vector3.new(d, d, d), CFrame = cf, Color = color, Material = mat }, m)
end
local function iblock(m, name, size, cf, color, mat, alpha)
	return part({ Name = name, Size = size, CFrame = cf, Color = color, Material = mat, Transparency = alpha or 0 }, m)
end
-- 가시: 밑동 가운데 base에서 dir 쪽으로 length, 밑동 너비 width (앞 +Z에서 보이는 삼각형)
local function ispike(m, base, dir, length, width, color, mat)
	local side = dir:Cross(Vector3.new(0, 0, 1))
	if side.Magnitude < 1e-3 then
		side = Vector3.new(1, 0, 0)
	end
	side = side.Unit * width / 2
	triangle(m, base - side, base + side, base + dir.Unit * length, 0.08, color, mat, nil, true)
end
-- 얼음 수정 (마름모 기둥)
local function icrystal(m, base, tilt, length, width, s)
	iblock(m, "Crystal", Vector3.new(width, length, width), base * tilt * CFrame.new(0, length / 2, 0) * CFrame.Angles(0, math.rad(45), 0), s.Trim, s.TrimMat, 0.15)
end
-- 휜 뿔 (원기둥 마디)
local function ihorn(m, base, length, thick, segments, bend, color, mat)
	local cf = base
	local seg = length / segments
	for i = 1, segments do
		local w = thick * (1 - (i - 1) / segments * 0.7)
		part({ Name = "Horn", Shape = CYL, Size = Vector3.new(seg * 1.15, w, w), CFrame = cf * CFrame.new(0, seg / 2, 0) * UPRIGHT, Color = color, Material = mat }, m)
		cf = cf * CFrame.new(0, seg, 0) * bend
	end
end

local ARMOR_ICONS = {
	Helmet = function(m, set, s)
		if set == "Golem" then
			-- 네모난 돌 투구 + 이마 돌판 + 이끼 + 빛나는 금·핵
			iblock(m, "Box", Vector3.new(1.7, 1.15, 1.7), CFrame.Angles(0, 0, math.rad(2)), s.Main, s.MainMat)
			iblock(m, "Brow", Vector3.new(1.85, 0.25, 0.3), CFrame.new(0, -0.45, 0.8), s.Trim, s.TrimMat)
			iblock(m, "Moss", Vector3.new(1.0, 0.12, 0.9), CFrame.new(0.2, 0.62, 0.1), s.Accent, s.AccentMat)
			iblock(m, "Crack", Vector3.new(0.06, 0.5, 0.05), CFrame.new(-0.45, 0.15, 0.86) * CFrame.Angles(0, 0, 0.5), s.Gem, NEON)
			iblock(m, "Crack", Vector3.new(0.06, 0.45, 0.05), CFrame.new(0.5, 0.05, 0.86) * CFrame.Angles(0, 0, -0.6), s.Gem, NEON)
			iblock(m, "Core", Vector3.new(0.32, 0.32, 0.15), CFrame.new(0, 0.1, 0.88) * CFrame.Angles(0, 0, math.rad(45)), s.Gem, NEON)
			return
		end
		local dome = iblock(m, "Dome", Vector3.new(1.6, 1.3, 1.6), CFrame.identity, s.Main, s.MainMat)
		Instance.new("SpecialMesh", dome).MeshType = Enum.MeshType.Sphere
		part({ Name = "Brim", Shape = CYL, Size = Vector3.new(0.2, 1.75, 1.75), CFrame = CFrame.new(0, -0.35, 0) * UPRIGHT, Color = if set == "Frost" then s.Main:Lerp(Color3.new(1, 1, 1), 0.3) else s.Trim, Material = if set == "Frost" then s.MainMat else s.TrimMat }, m)
		if set == "Leather" then
			iball(m, "Knob", 0.3, CFrame.new(0, 0.66, 0), s.Trim, s.TrimMat)
		elseif set == "Bone" then
			for _, x in { -0.32, 0.32 } do
				iball(m, "Socket", 0.42, CFrame.new(x, 0.12, 0.6), s.Accent, s.AccentMat)
				iball(m, "Eye", 0.14, CFrame.new(x, 0.12, 0.82), s.Gem, NEON)
			end
			for i = -2, 1 do
				iblock(m, "Tooth", Vector3.new(0.15, 0.18, 0.1), CFrame.new((i + 0.5) * 0.2, -0.22, 0.74), s.Main, s.MainMat)
			end
		elseif set == "Cerberus" then
			iblock(m, "Snout", Vector3.new(0.55, 0.35, 0.6), CFrame.new(0, 0.12, 0.85), s.Main, s.MainMat)
			iball(m, "Nose", 0.2, CFrame.new(0, 0.24, 1.15), C(25, 20, 22), Enum.Material.SmoothPlastic)
			for _, x in { -1, 1 } do
				iball(m, "Eye", 0.15, CFrame.new(x * 0.26, 0.36, 0.7), s.Gem, NEON)
				ispike(m, Vector3.new(x * 0.18, -0.05, 1.12), Vector3.new(0, -1, 0), 0.28, 0.12, s.Accent, s.AccentMat)
				ispike(m, Vector3.new(x * 0.42, 0.45, 0.05), Vector3.new(x * 0.35, 1, 0), 0.6, 0.4, s.Main, s.MainMat)
			end
		elseif set == "Cyclops" then
			iball(m, "EyeWhite", 0.7, CFrame.new(0, 0.12, 0.58), C(250, 248, 238), Enum.Material.SmoothPlastic)
			iball(m, "Iris", 0.4, CFrame.new(0, 0.12, 0.84), s.Gem, NEON)
			iball(m, "Pupil", 0.2, CFrame.new(0, 0.12, 1.0), C(20, 15, 18), Enum.Material.SmoothPlastic)
			part({ Name = "Horn", Shape = CYL, Size = Vector3.new(0.35, 0.25, 0.25), CFrame = CFrame.new(0, 0.78, 0) * UPRIGHT, Color = s.Trim, Material = s.TrimMat }, m)
			iblock(m, "Patch", Vector3.new(0.1, 0.5, 0.55), CFrame.new(0.78, 0.15, 0) * CFrame.Angles(0.2, 0, 0.1), s.Patch or s.Main, s.MainMat)
		elseif set == "Frost" then
			part({ Name = "Band", Shape = CYL, Size = Vector3.new(0.07, 1.8, 1.8), CFrame = CFrame.new(0, -0.22, 0) * UPRIGHT, Color = s.Gem, Material = NEON }, m)
			for k = -2, 2 do
				local theta = k * 0.5
				icrystal(m, CFrame.new(math.sin(theta) * 0.5, 0.42, math.cos(theta) * 0.5), CFrame.Angles(math.cos(theta) * 0.35, 0, -math.sin(theta) * 0.45), if k == 0 then 0.9 elseif math.abs(k) == 1 then 0.65 else 0.45, 0.18, s)
			end
		elseif set == "Behemoth" then
			part({ Name = "Brow", Shape = CYL, Size = Vector3.new(0.2, 1.78, 1.78), CFrame = CFrame.new(0, -0.2, 0) * UPRIGHT, Color = s.Trim, Material = s.TrimMat }, m)
			for _, x in { -1, 1 } do
				iblock(m, "EmberEye", Vector3.new(0.32, 0.07, 0.07), CFrame.new(x * 0.26, 0.0, 0.76) * CFrame.Angles(0, 0, x * -0.28), s.Gem, NEON)
				ihorn(m, CFrame.new(x * 0.7, 0.1, 0) * CFrame.Angles(0, 0, -x * 1.25), 1.4, 0.36, 4, CFrame.Angles(0.1, 0, x * 0.42), s.Accent, s.AccentMat)
			end
			for _, z in { -0.4, 0, 0.4 } do
				ispike(m, Vector3.new(0, 0.6, z), Vector3.new(0, 1, z * 0.6), 0.35, 0.3, s.Trim, Enum.Material.Slate)
			end
		end
	end,
	Armor = function(m, set, s)
		local bulk = if set == "Cyclops" or set == "Golem" then 1.12 else 1
		iblock(m, "Chest", Vector3.new(1.6 * bulk, 1.7, 0.6 * bulk), CFrame.identity, if set == "Bone" then s.Trim elseif set == "Golem" then s.Main:Lerp(Color3.new(0, 0, 0), 0.15) else s.Main, if set == "Bone" then s.TrimMat else s.MainMat)
		local fz = 0.3 * bulk + 0.04
		local shoulderScale = if set == "Cyclops" then 1.35 else 1
		for _, x in { -1, 1 } do
			if set == "Golem" then
				iblock(m, "Boulder", Vector3.new(0.65, 0.5, 0.65), CFrame.new(x * 1.0, 0.72, 0) * CFrame.Angles(0.25, x * 0.5, x * 0.15), s.Main, s.MainMat)
				iblock(m, "Moss", Vector3.new(0.4, 0.1, 0.4), CFrame.new(x * 1.0, 1.0, 0), s.Accent, s.AccentMat)
			elseif set == "Bone" then
				part({ Name = "ShoulderBone", Shape = CYL, Size = Vector3.new(0.8, 0.14, 0.14), CFrame = CFrame.new(x * 0.58, 0.88, 0) * CFrame.Angles(0, math.rad(90), 0), Color = s.Main, Material = s.MainMat }, m)
				for _, z in { -0.4, 0.4 } do
					iball(m, "BoneEnd", 0.2, CFrame.new(x * 0.58, 0.88, z), s.Main, s.MainMat)
				end
			else
				local pad = iblock(m, "Shoulder", Vector3.new(0.7, 0.45, 0.8) * shoulderScale, CFrame.new(x * 0.95 * (if set == "Cyclops" then 1.1 else 1), 0.7, 0), if set == "Frost" then s.Main:Lerp(Color3.new(1, 1, 1), 0.2) else s.Main, s.MainMat)
				Instance.new("SpecialMesh", pad).MeshType = Enum.MeshType.Sphere
			end
		end
		iblock(m, "Belt", Vector3.new(1.65 * bulk, 0.22, 0.65 * bulk), CFrame.new(0, -0.55, 0), if set == "Bone" then s.Trim:Lerp(Color3.new(0, 0, 0), 0.3) else s.Trim, s.TrimMat)
		if set == "Leather" then
			for _, y in { 0.25, -0.15 } do
				iball(m, "Button", 0.14, CFrame.new(0.1, y, fz), s.Accent, s.AccentMat)
			end
		elseif set == "Bone" then
			iblock(m, "Sternum", Vector3.new(0.16, 1.1, 0.1), CFrame.new(0, 0.1, fz), s.Main, s.MainMat)
			for i = 1, 4 do
				local y = 0.5 - (i - 1) * 0.25
				for _, x in { -1, 1 } do
					iblock(m, "Rib", Vector3.new(0.55, 0.1, 0.08), CFrame.new(x * 0.36, y, fz) * CFrame.Angles(0, 0, -x * 0.3), s.Main, s.MainMat)
				end
			end
		elseif set == "Cerberus" then
			part({ Name = "Collar", Shape = CYL, Size = Vector3.new(0.3, 1.3, 1.3), CFrame = CFrame.new(0, 0.78, 0) * UPRIGHT, Color = s.Main:Lerp(Color3.new(1, 1, 1), 0.15), Material = s.MainMat }, m)
			for i = -2, 2 do
				ispike(m, Vector3.new(i * 0.2, 0.62, fz + 0.06), Vector3.new(0, -1, 0), if i == 0 then 0.38 else 0.28, 0.13, s.Accent, s.AccentMat)
			end
			for _, x in { -1, 1 } do
				ispike(m, Vector3.new(x * 1.0, 0.85, 0.1), Vector3.new(x * 0.6, 1, 0), 0.38, 0.18, s.Accent, s.AccentMat)
			end
		elseif set == "Cyclops" then
			for _, info in { { -0.35, 0.3, 0.12, 0.6 }, { 0.38, -0.2, -0.15, 0.5 } } do
				local cf = CFrame.new(info[1], info[2], fz) * CFrame.Angles(0, 0, info[3])
				iblock(m, "Patch", Vector3.new(info[4], info[4] * 0.85, 0.06), cf, s.Patch or s.Main, s.MainMat)
				for _, cross in { 0.75, -0.75 } do
					iblock(m, "Stitch", Vector3.new(info[4] * 0.55, 0.05, 0.04), cf * CFrame.new(0, 0, 0.04) * CFrame.Angles(0, 0, cross), s.Accent, s.AccentMat)
				end
			end
		elseif set == "Golem" then
			for i, info in { { -0.4, 0.38, 0.05 }, { 0.4, 0.4, -0.04 }, { -0.38, -0.18, -0.06 }, { 0.4, -0.16, 0.07 } } do
				iblock(m, "Slab", Vector3.new(0.7, 0.55, 0.12), CFrame.new(info[1], info[2], fz) * CFrame.Angles(0, 0, info[3]), if i % 2 == 0 then s.Main else s.Main:Lerp(Color3.new(1, 1, 1), 0.08), s.MainMat)
			end
			iblock(m, "Core", Vector3.new(0.32, 0.32, 0.14), CFrame.new(0, 0.1, fz + 0.1) * CFrame.Angles(0, 0, math.rad(45)), s.Gem, NEON)
			for _, angle in { 0.6, 2.5, 4.2 } do
				local dir = Vector3.new(-math.sin(angle), math.cos(angle), 0)
				iblock(m, "Crack", Vector3.new(0.05, 0.42, 0.04), CFrame.new(Vector3.new(0, 0.1, fz + 0.08) + dir * 0.32) * CFrame.Angles(0, 0, angle), s.Gem, NEON)
			end
		elseif set == "Frost" then
			iblock(m, "IcePlate", Vector3.new(1.3, 1.0, 0.1), CFrame.new(0, 0.15, fz), s.Trim, s.TrimMat, 0.2)
			iblock(m, "Gem", Vector3.new(0.28, 0.28, 0.12), CFrame.new(0, 0.1, fz + 0.08) * CFrame.Angles(0, 0, math.rad(45)), s.Gem, NEON)
			for _, x in { -1, 1 } do
				for k, len in { 0.7, 0.5, 0.42 } do
					icrystal(m, CFrame.new(x * (0.95 + (k - 1) * 0.08), 0.85, (k - 2) * 0.15), CFrame.Angles(0, 0, -x * (0.15 + (k - 1) * 0.35)), len, 0.16, s)
				end
			end
		elseif set == "Behemoth" then
			iblock(m, "LavaSeam", Vector3.new(0.14, 1.4, 0.06), CFrame.new(0, 0, fz), s.Trim, s.TrimMat)
			for _, y in { 0.45, 0.1 } do
				for _, x in { -0.45, 0.45 } do
					iblock(m, "Scale", Vector3.new(0.34, 0.34, 0.08), CFrame.new(x, y, fz) * CFrame.Angles(0, 0, math.rad(45)), s.Main:Lerp(Color3.new(1, 1, 1), 0.12), s.MainMat)
				end
			end
			iball(m, "EmberCore", 0.3, CFrame.new(0, -0.2, fz + 0.06), s.Gem, NEON)
			for _, x in { -1, 1 } do
				ihorn(m, CFrame.new(x * 1.05, 0.85, 0) * CFrame.Angles(0, 0, -x * 0.6), 0.75, 0.22, 3, CFrame.Angles(0, 0, x * 0.35), s.Accent, s.AccentMat)
			end
		end
	end,
	Boots = function(m, set, s)
		local big = if set == "Cyclops" or set == "Golem" then 1.15 else 1
		for _, x in { 0.45, -0.45 } do
			iblock(m, "Leg", Vector3.new(0.55, 1.0, 0.6) * big, CFrame.new(x * big, 0.3, -0.1), if set == "Bone" then s.Trim else s.Main, if set == "Bone" then s.TrimMat else s.MainMat)
			iblock(m, "Foot", Vector3.new(0.6, 0.4, 1.0) * big, CFrame.new(x * big, -0.3, 0.15), if set == "Bone" then s.Trim else s.Main, if set == "Bone" then s.TrimMat else s.MainMat)
			iblock(m, "Sole", Vector3.new(0.64, if set == "Golem" or set == "Cyclops" then 0.2 else 0.12, 1.04) * big, CFrame.new(x * big, -0.52 * big, 0.15), s.Trim, s.TrimMat)
			if set == "Bone" then
				part({ Name = "ShinBone", Shape = CYL, Size = Vector3.new(0.75, 0.16, 0.16), CFrame = CFrame.new(x, 0.35, 0.24) * UPRIGHT, Color = s.Main, Material = s.MainMat }, m)
				for _, y in { -0.02, 0.72 } do
					iball(m, "BoneEnd", 0.2, CFrame.new(x, y, 0.24), s.Main, s.MainMat)
				end
				iblock(m, "Toe", Vector3.new(0.62, 0.3, 0.2), CFrame.new(x, -0.3, 0.6), s.Main, s.MainMat)
			elseif set == "Cerberus" or set == "Frost" then
				part({ Name = "FurCuff", Shape = CYL, Size = Vector3.new(0.28, 0.85, 0.85), CFrame = CFrame.new(x, 0.75, -0.1) * UPRIGHT, Color = s.Main:Lerp(Color3.new(1, 1, 1), if set == "Frost" then 0.4 else 0.15), Material = s.MainMat }, m)
				if set == "Cerberus" then
					for _, k in { -0.15, 0.15 } do
						ispike(m, Vector3.new(x + k, -0.4, 0.62), Vector3.new(0, 0, 1), 0.3, 0.14, s.Accent, s.AccentMat)
					end
				else
					icrystal(m, CFrame.new(x, 0.3, 0.22), CFrame.Angles(-0.55, 0, 0), 0.5, 0.15, s)
				end
			elseif set == "Cyclops" then
				for _, y in { 0.1, 0.4 } do
					iblock(m, "Wrap", Vector3.new(0.66, 0.08, 0.72), CFrame.new(x * big, y, -0.1), s.Trim, s.TrimMat)
				end
			elseif set == "Golem" then
				iblock(m, "Crack", Vector3.new(0.06, 0.45, 0.04), CFrame.new(x * big, 0.35, 0.26), s.Gem, NEON)
			elseif set == "Behemoth" then
				for _, k in { -0.16, 0.16 } do
					ispike(m, Vector3.new(x + k, -0.35, 0.64), Vector3.new(0, 0.2, 1), 0.38, 0.16, s.Accent, s.AccentMat)
				end
				ispike(m, Vector3.new(x, 0.55, 0.2), Vector3.new(0, 0.6, 1), 0.4, 0.22, s.Accent, s.AccentMat)
			end
		end
	end,
	Gloves = function(m, set, s)
		local scale = if set == "Golem" then 1.3 elseif set == "Cyclops" then 1.2 else 1
		local main = if set == "Bone" then s.Trim else s.Main
		local mainMat = if set == "Bone" then s.TrimMat else s.MainMat
		iblock(m, "Palm", Vector3.new(0.9, 1.0, 0.4) * scale, CFrame.identity, main, mainMat)
		if set == "Cyclops" or set == "Golem" then
			-- 벙어리장갑·돌 주먹: 손가락 대신 한 덩어리
			iblock(m, "Mitt", Vector3.new(0.95, 0.5, 0.42) * scale, CFrame.new(0, 0.7 * scale, 0), main, mainMat)
		else
			for i = -1, 2 do
				iblock(m, "Finger", Vector3.new(0.2, 0.5, 0.3), CFrame.new(-0.3 + i * 0.22, 0.7, 0), main, mainMat)
			end
		end
		iblock(m, "Cuff", Vector3.new(1.0, 0.35, 0.5) * scale, CFrame.new(0, -0.6 * scale, 0), if set == "Cerberus" or set == "Frost" then s.Main:Lerp(Color3.new(1, 1, 1), 0.3) else s.Trim, if set == "Cerberus" or set == "Frost" then s.MainMat else s.TrimMat)
		if set == "Bone" then
			for i = -1, 2 do
				iball(m, "Knuckle", 0.2, CFrame.new(-0.3 + i * 0.22, 0.42, 0.22), s.Main, s.MainMat)
			end
		elseif set == "Cerberus" then
			for i = -1, 2 do
				ispike(m, Vector3.new(-0.3 + i * 0.22, 0.95, 0.05), Vector3.new(0, 1, 0), 0.25, 0.14, s.Accent, s.AccentMat)
			end
		elseif set == "Cyclops" then
			local cf = CFrame.new(0, 0.05, 0.25)
			iblock(m, "Patch", Vector3.new(0.55, 0.5, 0.05), cf * CFrame.Angles(0, 0, 0.15), s.Patch or s.Main, s.MainMat)
			for _, cross in { 0.75, -0.75 } do
				iblock(m, "Stitch", Vector3.new(0.4, 0.05, 0.04), cf * CFrame.new(0, 0, 0.04) * CFrame.Angles(0, 0, cross), s.Accent, s.AccentMat)
			end
		elseif set == "Golem" then
			iblock(m, "KnuckleSlab", Vector3.new(1.25, 0.25, 0.6), CFrame.new(0, 0.95, 0), s.Trim, s.TrimMat)
			iblock(m, "Core", Vector3.new(0.3, 0.3, 0.12), CFrame.new(0, 0.1, 0.3) * CFrame.Angles(0, 0, math.rad(45)), s.Gem, NEON)
		elseif set == "Frost" then
			iblock(m, "IceKnuckles", Vector3.new(0.95, 0.22, 0.45), CFrame.new(0, 0.45, 0), s.Trim, s.TrimMat, 0.2)
			for _, x in { -0.2, 0.2 } do
				icrystal(m, CFrame.new(x, 0.1, 0.2), CFrame.Angles(-0.9, 0, x), 0.5, 0.14, s)
			end
		elseif set == "Behemoth" then
			for i = -1, 1 do
				ispike(m, Vector3.new(i * 0.28, 0.45, 0.2), Vector3.new(0, 0.3, 1), 0.32, 0.16, s.Accent, s.AccentMat)
			end
			iblock(m, "Ember", Vector3.new(0.26, 0.26, 0.06), CFrame.new(0, 0.05, 0.22) * CFrame.Angles(0, 0, math.rad(45)), s.Gem, NEON)
		end
	end,
	-- 방패 (2026-10-10): 캐릭터 왼팔 방패(GearVisualService buildShield)와 같은 모양. 앞면 = +Z
	Shield = function(m, set, s)
		local FACE = CFrame.Angles(0, math.pi / 2, 0) -- 원기둥 축(X)을 앞(Z)으로
		local function disc(name, d, thick, z, color, mat, alpha)
			part({ Name = name, Shape = CYL, Size = Vector3.new(thick, d, d), CFrame = CFrame.new(0, 0, z) * FACE, Color = color, Material = mat, Transparency = alpha or 0 }, m)
		end
		local function kite(name, h, w, thick, z, color, mat, alpha)
			iblock(m, name, Vector3.new(w, h * 0.5, thick), CFrame.new(0, h * 0.25, z), color, mat, alpha)
			triangle(m, Vector3.new(-w / 2, 0, z), Vector3.new(w / 2, 0, z), Vector3.new(0, -h * 0.5, z), thick, color, mat, nil, true)
		end
		if set == "Leather" then
			-- 나무 둥근 방패: 판자·쇠 테·가운데 쇠 혹·못
			local wood = C(160, 112, 66)
			disc("Rim", 2.1, 0.16, -0.02, C(120, 112, 105), METAL)
			disc("Body", 2.0, 0.2, 0.02, wood, Enum.Material.WoodPlanks)
			for i = -1, 1 do
				iblock(m, "Plank", Vector3.new(0.04, 1.85 * math.sqrt(1 - (i * 0.25) ^ 2), 0.05), CFrame.new(i * 0.45, 0, 0.12), wood:Lerp(Color3.new(0, 0, 0), 0.4), Enum.Material.Wood)
			end
			iball(m, "Boss", 0.5, CFrame.new(0, 0, 0.12), C(150, 145, 140), METAL)
			for k = 0, 5 do
				local a = k / 6 * math.pi * 2
				iball(m, "Nail", 0.1, CFrame.new(math.cos(a) * 0.82, math.sin(a) * 0.82, 0.13), C(170, 165, 160), METAL)
			end
		elseif set == "Bone" then
			-- 뼈 둥근 방패: 가죽 판 + 갈비뼈 살 + 해골
			disc("Rim", 2.1, 0.14, -0.03, s.Main, s.MainMat)
			disc("Body", 2.0, 0.2, 0, s.Trim, s.TrimMat)
			for i = -2, 2 do
				part({ Name = "Rib", Shape = CYL, Size = Vector3.new(1.7 * math.sqrt(1 - (i * 0.18) ^ 2), 0.15, 0.15), CFrame = CFrame.new(i * 0.35, 0, 0.12) * UPRIGHT, Color = s.Main, Material = s.MainMat }, m)
			end
			iball(m, "Skull", 0.8, CFrame.new(0, 0.08, 0.2), s.Main, s.MainMat)
			for _, x in { -0.17, 0.17 } do
				iball(m, "Socket", 0.24, CFrame.new(x, 0.16, 0.5), s.Accent, s.AccentMat)
				iball(m, "Eye", 0.1, CFrame.new(x, 0.16, 0.6), s.Gem, NEON)
			end
		elseif set == "Cerberus" then
			-- 케르베로스 연 모양: 털가죽 + 늑대 얼굴(빨간 눈·귀) + 아래 송곳니
			kite("Rim", 2.3, 1.68, 0.12, -0.03, s.Trim, s.TrimMat)
			kite("Body", 2.15, 1.5, 0.2, 0, s.Main, s.MainMat)
			local fur = s.Main:Lerp(Color3.new(0, 0, 0), 0.25)
			iball(m, "Wolf", 0.62, CFrame.new(0, 0.25, 0.18), fur, s.MainMat)
			iblock(m, "Snout", Vector3.new(0.28, 0.2, 0.3), CFrame.new(0, 0.08, 0.42), fur:Lerp(Color3.new(0, 0, 0), 0.15), s.MainMat)
			for _, x in { -0.15, 0.15 } do
				iball(m, "Eye", 0.11, CFrame.new(x, 0.34, 0.45), s.Gem, NEON)
				ispike(m, Vector3.new(x * 1.4, 0.48, 0.15), Vector3.new(x, 1, 0), 0.3, 0.2, fur, s.MainMat)
			end
			for i = -1, 1 do
				ispike(m, Vector3.new(i * 0.28, -0.1 - math.abs(i) * 0.08, 0.14), Vector3.new(0, -1, 0), 0.38, 0.14, s.Accent, s.AccentMat)
			end
		elseif set == "Cyclops" then
			-- 사이클롭스 큰 둥근 가죽: 덧댄 조각·바느질 + 가운데 큰 외눈
			disc("Rim", 2.3, 0.16, -0.03, s.Trim, s.TrimMat)
			disc("Body", 2.2, 0.24, 0, s.Main, s.MainMat)
			local patch = s.Patch or s.Main
			iblock(m, "Patch", Vector3.new(0.5, 0.55, 0.06), CFrame.new(-0.45, 0.6, 0.13) * CFrame.Angles(0, 0, 0.3), patch, s.MainMat)
			iblock(m, "Patch", Vector3.new(0.55, 0.45, 0.06), CFrame.new(0.4, -0.65, 0.13) * CFrame.Angles(0, 0, -0.25), patch, s.MainMat)
			for _, a in { 0.8, -0.8 } do
				iblock(m, "Stitch", Vector3.new(0.05, 0.36, 0.05), CFrame.new(-0.45, 0.6, 0.17) * CFrame.Angles(0, 0, a), s.Accent, s.AccentMat)
			end
			iball(m, "EyeWhite", 0.8, CFrame.new(0, 0, 0.08), C(250, 248, 240), Enum.Material.SmoothPlastic)
			iball(m, "Iris", 0.44, CFrame.new(0, 0, 0.3), s.Gem, NEON)
			iball(m, "Pupil", 0.22, CFrame.new(0, 0, 0.45), C(20, 15, 20), Enum.Material.SmoothPlastic)
			iblock(m, "Lid", Vector3.new(0.9, 0.12, 0.22), CFrame.new(0, 0.44, 0.15), s.Trim, s.TrimMat)
		elseif set == "Golem" then
			-- 바위 골렘 네모 큰 방패: 돌판·둘레 돌·빛나는 금·핵·이끼
			iblock(m, "Body", Vector3.new(1.75, 2.5, 0.3), CFrame.identity, s.Main, s.MainMat)
			iblock(m, "Trim", Vector3.new(1.9, 0.32, 0.36), CFrame.new(0, 1.1, 0.02), s.Trim, s.TrimMat)
			iblock(m, "Trim", Vector3.new(1.85, 0.28, 0.36), CFrame.new(0, -1.12, 0.02), s.Trim, s.TrimMat)
			iblock(m, "Moss", Vector3.new(1.2, 0.1, 0.25), CFrame.new(0.1, 1.3, 0), s.Accent, s.AccentMat)
			for _, c in { { -0.4, 0.5, 0.6 }, { 0.4, -0.5, -0.5 }, { 0.5, 0.15, 0.9 } } do
				iblock(m, "Crack", Vector3.new(0.07, 0.6, 0.05), CFrame.new(c[1], c[2], 0.17) * CFrame.Angles(0, 0, c[3]), s.Gem, NEON)
			end
			iblock(m, "Core", Vector3.new(0.4, 0.4, 0.14), CFrame.new(0, 0, 0.2) * CFrame.Angles(0, 0, math.rad(45)), s.Gem, NEON)
		elseif set == "Frost" then
			-- 서리 거인 얼음 연 모양: 하얀 털 테 + 반투명 얼음 + 위 수정 가시 + 푸른 수정
			kite("Rim", 2.5, 1.85, 0.14, -0.03, s.Main, s.MainMat)
			kite("Body", 2.3, 1.62, 0.22, 0, s.Trim, s.TrimMat, 0.2)
			for i = -1, 1 do
				icrystal(m, CFrame.new(i * 0.55, 1.1, 0), CFrame.Angles(0, 0, -i * 0.35), if i == 0 then 0.75 else 0.5, 0.18, s)
			end
			iblock(m, "Gem", Vector3.new(0.42, 0.42, 0.14), CFrame.new(0, 0.2, 0.15) * CFrame.Angles(0, 0, math.rad(45)), s.Gem, NEON)
		else
			-- 베헤모스 가시 큰 방패: 검붉은 비늘 + 용암 테 + 두 뿔 + 둘레 가시 + 불빛 핵
			disc("Rim", 2.6, 0.18, -0.04, s.Trim, s.TrimMat)
			disc("Body", 2.45, 0.28, 0, s.Main, s.MainMat)
			for k = 0, 7 do
				local a = k / 8 * math.pi * 2
				iblock(m, "Scale", Vector3.new(0.34, 0.34, 0.08), CFrame.new(math.cos(a) * 0.72, math.sin(a) * 0.72, 0.16) * CFrame.Angles(0, 0, math.rad(45)), s.Main:Lerp(Color3.new(0, 0, 0), 0.25), s.MainMat)
				if k % 2 == 1 then
					local dir = Vector3.new(math.cos(a), math.sin(a), 0)
					ispike(m, dir * 1.22, dir, 0.4, 0.2, s.Accent, s.AccentMat)
				end
			end
			for _, x in { -1, 1 } do
				ihorn(m, CFrame.new(x * 0.7, 0.95, 0.05) * CFrame.Angles(0, 0, -x * 0.5), 1.0, 0.24, 4, CFrame.Angles(0, 0, x * 0.3), s.Accent, s.AccentMat)
			end
			iball(m, "Core", 0.46, CFrame.new(0, 0, 0.2), s.Gem, NEON)
		end
	end,
}
-- 단계별 장식 색: 1~2 몸 색을 어둡게 / 3~4 금 / 5 미스릴 파란 빛 / 6 오리하르콘 주황 빛 (5단계부터 장식이 빛난다, 2026-10-09)
local HIGH_ACCENTS = { [5] = MITHRIL_GLOW, [6] = EMBER }
for _, id in EquipmentDefs.Order do
	local def = EquipmentDefs.Items[id]
	local old = iconFolder:FindFirstChild(id)
	if old then
		old:Destroy()
	end
	local m = Instance.new("Model")
	m.Name = id
	local high = HIGH_ACCENTS[math.min(def.Tier, 6)]
	local accent = if def.Tier >= 5 and high then high elseif def.Tier >= 3 then GOLD else def.Color:Lerp(Color3.new(0, 0, 0), 0.3)
	local armorIcon = def.Set and ARMOR_ICONS[def.Slot]
	if armorIcon then
		armorIcon(m, def.Set, ICON_SETS[def.Set] or ICON_SETS.Leather)
	else
		EQUIPMENT_ICONS[def.Slot](m, def.Color, accent)
	end
	if def.Tier >= 5 and not armorIcon then
		-- 장식 부품(장식 색)을 빛나게
		for _, p in m:GetChildren() do
			if p:IsA("BasePart") and math.abs(p.Color.R - accent.R) + math.abs(p.Color.G - accent.G) + math.abs(p.Color.B - accent.B) < 0.02 then
				p.Material = NEON
			end
		end
	end
	m:SetAttribute("GeneratedBy", GENERATED)
	m.Parent = iconFolder
end

---------------------------------------------------------------- 4. 몹 구역과 생성 자리
-- 구역(Config.MobZones) = 마을을 둘러싼 고리의 한 조각(부채꼴). 마을에서 멀수록 센 몹이고, 띠끼리 거리가 조금 겹친다 (2026-10-09).
-- 자리마다 Mix 확률로 이웃 단계 몹이 대신 선다. 맵이 좁으면 Config.WorldTiers 비율로 거리를 줄인다.
-- 마을 안전지대(TownArrival·ShopNPC 둘레 Config.MobAI.SafeZoneRadius + SafeZoneSpawnMargin) 안에는 자리를 두지 않는다.
local spawns = folder(workspace, "MobSpawns")
for _, child in spawns:GetChildren() do
	if child:GetAttribute("GeneratedBy") == GENERATED then
		child:Destroy()
	end
end

local town = CollectionService:GetTagged("TownArrival")[1]
local center = if town and town:IsA("BasePart") then town.Position elseif town and town:IsA("Model") then town:GetPivot().Position else Vector3.zero

-- 인스턴스 위치 (모델이면 기준점)
local function positionOf(instance: Instance): Vector3?
	if instance:IsA("Model") then
		return instance:GetPivot().Position
	elseif instance:IsA("BasePart") then
		return instance.Position
	end
	return nil
end

local safePoints = {} -- 마을 안전지대 가운데들
for _, tag in { "TownArrival", "ShopNPC" } do
	for _, instance in CollectionService:GetTagged(tag) do
		local position = positionOf(instance)
		if position then
			table.insert(safePoints, position)
		end
	end
end
local obstacles = {} -- 광산 입구 같은 시설
for _, instance in CollectionService:GetTagged("MinePortal") do
	local position = positionOf(instance)
	if position then
		table.insert(obstacles, position)
	end
end
local safeRadius = Config.MobAI.SafeZoneRadius + Config.MobAI.SafeZoneSpawnMargin
local layout = Config.MobZoneLayout

-- 나무·바위 생성 자리 (지상). 몹이 나무 줄기 속에 서지 않게 피한다
local nodeSpots = {}
local oreSpawns = workspace:FindFirstChild("OreSpawns")
if oreSpawns then
	for _, child in oreSpawns:GetChildren() do
		local floor = child:GetAttribute("Floor")
		if child:IsA("BasePart") and (floor == nil or floor == 0) then
			table.insert(nodeSpots, child.Position)
		end
	end
end

-- 안전지대(여유 extra 포함) 안인지. 높이는 무시한다
local function nearTown(position: Vector3, extra: number): boolean
	for _, point in safePoints do
		if Vector3.new(position.X - point.X, 0, position.Z - point.Z).Magnitude < safeRadius + extra then
			return true
		end
	end
	return false
end

local zones = CollectionService:GetTagged("MineZone")
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = { spawns, workspace:FindFirstChild("Ores"), workspace:FindFirstChild("OreSpawns"), workspace:FindFirstChild("Mobs") }

local function insideMineZone(position: Vector3): boolean
	for _, zone in zones do
		if zone:IsA("BasePart") then
			local p = zone.CFrame:PointToObjectSpace(position)
			local half = zone.Size / 2 + Vector3.new(6, 6, 6)
			if math.abs(p.X) < half.X and math.abs(p.Y) < half.Y and math.abs(p.Z) < half.Z then
				return true
			end
		end
	end
	return false
end

-- 몹이 설 수 있는 땅 (평평하고, 물·광산·마을·시설·나무에서 떨어진 곳)
local function groundAt(x: number, z: number): Vector3?
	local result = workspace:Raycast(Vector3.new(x, center.Y + 400, z), Vector3.new(0, -800, 0), params)
	if not result or result.Normal.Y < 0.8 or result.Material == Enum.Material.Water then
		return nil
	end
	if not result.Instance:IsA("Terrain") and not (result.Instance:IsA("BasePart") and result.Instance.Size.X > 30 and result.Instance.Size.Z > 30) then
		return nil -- 지붕·가구 위
	end
	if insideMineZone(result.Position) or nearTown(result.Position, 0) then
		return nil
	end
	for _, position in obstacles do
		if (position - result.Position).Magnitude < layout.ObstacleGap then
			return nil
		end
	end
	for _, position in nodeSpots do
		if (position - result.Position).Magnitude < layout.NodeGap then
			return nil
		end
	end
	return result.Position
end

-- 맵의 땅 반경 재기 (BuildTreesAndAxes와 같은 방법): 36방향으로 걸어 나가며 마지막으로 땅이 있던 거리, 그중 60% 지점 값
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
local tiers = Config.WorldTiers
local landRadius = measureLandRadius()
local scale = math.clamp(landRadius / tiers.MapRadius, tiers.MinScale, 1)

local TWO_PI = math.pi * 2
-- 부채꼴 안의 무작위 점 (넓이 기준 고르게). angle = 가운데 방향, arc = 폭(라디안)
local function sectorPoint(angle: number, arc: number, lo: number, hi: number): (number, number)
	local a = angle + random:NextNumber(-arc / 2, arc / 2)
	local r = math.sqrt(random:NextNumber(lo * lo, hi * hi))
	return center.X + math.cos(a) * r, center.Z + math.sin(a) * r
end
-- 두 구역이 같은 띠인지 (거리 가운데가 가까우면 같은 띠 → 방향이 겹치면 안 된다)
local function sameBand(a, b): boolean
	local midA, midB = (a.Distance[1] + a.Distance[2]) / 2, (b.Distance[1] + b.Distance[2]) / 2
	local widthA, widthB = a.Distance[2] - a.Distance[1], b.Distance[2] - b.Distance[1]
	return math.abs(midA - midB) < (widthA + widthB) / 4
end
local function angleDiff(a: number, b: number): number
	local d = (a - b) % TWO_PI
	return math.min(d, TWO_PI - d)
end

-- 구역 방향 고르기: 같은 띠 구역과 겹치지 않는 방향 중 땅이 가장 많은 쪽. 못 찾으면 겹침을 조금씩 허용
local chosenZones = {} -- { Zone, Angle }
local function pickZoneAngle(zone, shrink: number?): number?
	local lo, hi = zone.Distance[1] * scale * (shrink or 1), zone.Distance[2] * scale * (shrink or 1)
	local arc = math.rad(zone.Arc)
	for pass, gapScale in { 1, 0.5, 0 } do
		local bestAngle, bestScore = nil, 0
		for _ = 1, 40 do
			local angle = random:NextNumber(0, TWO_PI)
			local free = true
			for _, other in chosenZones do
				if sameBand(zone, other.Zone) then
					local need = ((arc + math.rad(other.Zone.Arc)) / 2 + math.rad(layout.ArcGap)) * gapScale
					if angleDiff(angle, other.Angle) < need then
						free = false
						break
					end
				end
			end
			if free then
				local ok = 0
				for _ = 1, 12 do
					local x, z = sectorPoint(angle, arc, lo, hi)
					if groundAt(x, z) then
						ok += 1
					end
				end
				if ok > bestScore then
					bestAngle, bestScore = angle, ok
				end
				if ok >= 10 then
					break
				end
			end
		end
		if bestAngle and (bestScore >= 4 or pass == 3) then
			return bestAngle
		end
	end
	return nil
end

-- 자리마다 Mix 확률로 이웃 단계 몹
local function rollMobType(zone): string
	local mix = zone.Mix
	if mix then
		local ids = {}
		for id in mix do
			table.insert(ids, id)
		end
		table.sort(ids)
		local roll = random:NextNumber()
		for _, id in ids do
			roll -= mix[id]
			if roll < 0 then
				if MobDefs[id] and Config.Mobs[id] then
					return id
				end
				break
			end
		end
	end
	return zone.MobType
end

-- 구역 주인 몹의 MobDefs.Tier로 묶는다 (5~7단계 거대 몬스터 = 아주 먼 띠, 2026-10-10)
local BAND_NAMES = { [1] = "가까운 띠", [2] = "중간 띠", [3] = "먼 띠", [4] = "먼 띠", [5] = "아주 먼 띠", [6] = "아주 먼 띠", [7] = "아주 먼 띠" }
local bandOrder = { "가까운 띠", "중간 띠", "먼 띠", "아주 먼 띠" }
local BAND_MOB_ORDER = { "Slime", "Skeleton", "SkeletonArcher", "Zombie", "Cerberus", "Cyclops", "StoneGolem", "FrostGiant", "Behemoth" } -- 요약 출력 순서
local bandTotals = {} -- 띠 이름 → { 몹 → 마리 }
local bandRanges = {} -- 띠 이름 → { 가까운, 먼 } (실제 거리)
local placed = {}
local summary = {}
for index, zone in Config.MobZones do
	-- 구역 주인 몹 Count마리 + Extras(따로 두는 몹, 2026-10-10 스켈레톤 궁수). 다 못 채우면(맵 끝 너머) 거리를 FallbackShrink 배율로 당겨 다시 (먼 거대 몬스터 구역)
	local extraIds = {}
	local extraTotal = 0
	for id, count in zone.Extras or {} do
		if MobDefs[id] and Config.Mobs[id] then
			table.insert(extraIds, id)
			extraTotal += count
		end
	end
	table.sort(extraIds)
	local want = zone.Count + extraTotal
	local made, mixed, bosses = 0, 0, 0
	local angle: number? = nil
	local lastAngle: number? = nil -- 마지막으로 쓴 방향 (요약 출력용)
	local lo, hi = 0, 0
	local band = "먼 띠"
	local extraMade = {}
	for _, shrink in { 1, table.unpack(layout.FallbackShrink or {}) } do
		if made >= want then
			break
		end
		angle = pickZoneAngle(zone, shrink)
		if not angle then
			continue
		end
		lastAngle = angle
		table.insert(chosenZones, { Zone = zone, Angle = angle })
		lo, hi = zone.Distance[1] * scale * shrink, zone.Distance[2] * scale * shrink
		local arc = math.rad(zone.Arc)
		local mainDef = MobDefs[zone.MobType]
		band = BAND_NAMES[mainDef and mainDef.Tier or 1] or "먼 띠"
		bandTotals[band] = bandTotals[band] or {}
		local range = bandRanges[band] or { math.huge, 0 }
		bandRanges[band] = { math.min(range[1], lo), math.max(range[2], hi) }
		for _ = 1, want * 60 do
			if made >= want then
				break
			end
			local x, z = sectorPoint(angle, arc, lo, hi)
			local ground = groundAt(x, z)
			local free = ground ~= nil
			if ground then
				for _, other in placed do
					if (other - ground).Magnitude < layout.SpawnGap then
						free = false
						break
					end
				end
			end
			if free and ground then
				-- 주인 몹(Mix 섞임 포함)을 먼저 채우고, 그다음 Extras를 차례로
				local mobType: string
				local isExtra = false
				if made < zone.Count then
					mobType = rollMobType(zone)
				else
					mobType = zone.MobType
					for _, id in extraIds do
						if (extraMade[id] or 0) < zone.Extras[id] then
							mobType = id
							isExtra = true
							extraMade[id] = (extraMade[id] or 0) + 1
							break
						end
					end
				end
				local p = part({ Name = `{mobType}Spawn`, Size = Vector3.new(2, 1, 2), CFrame = CFrame.new(ground + Vector3.new(0, 1, 0)), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false }, spawns)
				p:SetAttribute("MobType", mobType)
				p:SetAttribute("Zone", zone.Name)
				p:SetAttribute("ZoneIndex", index)
				if mobType == zone.MobType and bosses < (zone.BossSpots or 0) then
					p:SetAttribute("BossSpot", true) -- 보스가 잘 나오는 자리 (Config.MobBoss.SpotChance)
					bosses += 1
				end
				if mobType ~= zone.MobType and not isExtra then
					mixed += 1
				end
				p:SetAttribute("GeneratedBy", GENERATED)
				table.insert(placed, ground)
				made += 1
				bandTotals[band][mobType] = (bandTotals[band][mobType] or 0) + 1
			end
		end
		-- 모자라면 다음 배율(더 가까이)에서 방향부터 다시 고른다. 이미 놓은 자리는 그대로 둔다
	end
	if made == 0 then
		table.insert(summary, `{zone.Name} 자리 없음`)
		continue
	end
	local direction = if lastAngle then math.floor(math.deg(lastAngle) + 0.5) % 360 else -1
	local extraText = if extraTotal > 0 then ` +따로 {extraTotal}` else ""
	table.insert(summary, `{zone.Name} {made}마리(섞임 {mixed}{extraText}) {math.floor(lo)}~{math.floor(hi)} 방향 {direction}°`)
end
print(`[BuildWeaponsAndMobs] 몹 구역 (땅 반경 약 {landRadius}, 거리 배율 x{string.format("%.2f", scale)}): {table.concat(summary, ", ")}`)
for _, band in bandOrder do
	local counts = bandTotals[band]
	if counts then
		local parts, total = {}, 0
		for _, id in BAND_MOB_ORDER do
			if counts[id] then
				table.insert(parts, `{MobDefs[id] and MobDefs[id].DisplayName or id} {counts[id]}`)
				total += counts[id]
			end
		end
		for id, count in counts do
			if not table.find(BAND_MOB_ORDER, id) then
				table.insert(parts, `{id} {count}`)
				total += count
			end
		end
		local range = bandRanges[band]
		print(`[BuildWeaponsAndMobs]   {band}({math.floor(range[1])}~{math.floor(range[2])}): {total}마리 - {table.concat(parts, " / ")}`)
	end
end

---------------------------------------------------------------- 5. 바다 생물 생성 자리 (2026-10-09)
-- 물 찾기: 마을 둘레(Config.SeaSpawn.ScanRadius)를 ScanStep 격자로 지형만 보는 광선을 아래로 쏜다.
--   물을 무시하지 않는 광선이 지형 물(Material Water)에 맞으면 그 높이가 수면, 물을 무시하는 두 번째 광선이 닿는 곳이 바닥.
--   마을 안전지대·광산 구역·너무 얕은 물(MinDepth)은 뺀다.
-- 구역(Config.SeaZones)마다 가운데를 고른다: 깊이(Depth)가 맞는 물 칸 중 둘레(Radius)에 물 칸이 가장 많고, 마을 거리(Distance) 범위에 가까운 곳.
--   다른 바다 구역 가운데와는 ZoneGap 떨어뜨린다. 깊이가 맞는 곳이 없으면 깊이 조건을 풀고 다시.
-- 생성 자리 = 투명 파트 (속성 MobType·Zone·SwimDepth(그 자리 물 깊이)·Habitat="Water", 물고기 떼는 School). 높이는 수면과 바닥 사이 무작위
local seaConfig = Config.SeaSpawn
local terrainWater = RaycastParams.new()
terrainWater.FilterType = Enum.RaycastFilterType.Include
terrainWater.FilterDescendantsInstances = { workspace.Terrain }
terrainWater.IgnoreWater = false
local terrainFloor = RaycastParams.new()
terrainFloor.FilterType = Enum.RaycastFilterType.Include
terrainFloor.FilterDescendantsInstances = { workspace.Terrain }
terrainFloor.IgnoreWater = true

local seaStep = seaConfig.ScanStep
local cells = {} -- 칸 번호(cellKey) → { X, Z, Surface, Floor, Depth, Distance, GX, GZ }
local cellList = {}
local scanCells = math.floor(seaConfig.ScanRadius / seaStep)
local function cellKey(gx: number, gz: number): number
	return (gx + 4096) * 8192 + (gz + 4096)
end
for gx = -scanCells, scanCells do
	for gz = -scanCells, scanCells do
		if gx * gx + gz * gz <= scanCells * scanCells then
			local x, z = center.X + gx * seaStep, center.Z + gz * seaStep
			local hit = workspace:Raycast(Vector3.new(x, center.Y + seaConfig.ScanTop, z), Vector3.new(0, -seaConfig.ScanTop * 2, 0), terrainWater)
			if hit and hit.Material == Enum.Material.Water and hit.Position.Y > Config.Minimap.SurfaceMinY then
				local floorHit = workspace:Raycast(hit.Position, Vector3.new(0, -seaConfig.MaxDepth, 0), terrainFloor)
				local floorY = if floorHit then floorHit.Position.Y else hit.Position.Y - seaConfig.MaxDepth
				local depth = hit.Position.Y - floorY
				local position = Vector3.new(x, hit.Position.Y, z)
				if depth >= seaConfig.MinDepth and not nearTown(position, 0) and not insideMineZone(position) then
					local cell = { X = x, Z = z, Surface = hit.Position.Y, Floor = floorY, Depth = depth, Distance = Vector3.new(gx, 0, gz).Magnitude * seaStep, GX = gx, GZ = gz }
					cells[cellKey(gx, gz)] = cell
					table.insert(cellList, cell)
				end
			end
		end
	end
end

-- 칸 둘레 radius 안의 물 칸 (깊이 조건 depth를 맞는 것만)
local function cellsAround(cell, radius: number, depth): { any }
	local list = {}
	local reach = math.ceil(radius / seaStep)
	for dx = -reach, reach do
		for dz = -reach, reach do
			if dx * dx + dz * dz <= reach * reach then
				local other = cells[cellKey(cell.GX + dx, cell.GZ + dz)]
				if other and other.Depth >= depth[1] and other.Depth <= depth[2] then
					table.insert(list, other)
				end
			end
		end
	end
	return list
end

-- 생성 자리 하나 (물 칸 cell, 그 안에서 조금 흩뜨린 x·z, 높이는 수면과 바닥 사이)
local seaTotals = {}
local function seaSpawn(cell, offset: Vector3, mobType: string, zone, extra: { [string]: any }?)
	local margin = math.min(1.5, cell.Depth * 0.25)
	local y = random:NextNumber(cell.Floor + margin, cell.Surface - margin)
	local p = part({ Name = `{mobType}Spawn`, Size = Vector3.new(2, 1, 2), CFrame = CFrame.new(cell.X + offset.X, y, cell.Z + offset.Z), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false }, spawns)
	p:SetAttribute("MobType", mobType)
	p:SetAttribute("Zone", zone.Name)
	p:SetAttribute("Habitat", "Water")
	p:SetAttribute("SwimDepth", math.floor(cell.Depth * 10 + 0.5) / 10)
	for key, value in extra or {} do
		p:SetAttribute(key, value)
	end
	p:SetAttribute("GeneratedBy", GENERATED)
	seaTotals[mobType] = (seaTotals[mobType] or 0) + 1
	return p
end

local seaSummary = {}
local seaCenters = {}
local seaPlaced = {} -- 이미 쓴 칸 (자리끼리 SpotGap)
if #cellList == 0 then
	warn(`[BuildWeaponsAndMobs] 바다 생물: 마을 둘레 {seaConfig.ScanRadius}스터드 안에서 헤엄칠 만한 지형 물(깊이 {seaConfig.MinDepth} 이상)을 못 찾았어요. 낙지·해파리·상어가 안 나와요. (Terrain 물인지, 마을 안전지대 밖인지 확인)`)
else
	for zoneIndex, zone in Config.SeaZones do
		-- 구역 가운데 고르기 (1: 깊이 맞음, 2: 깊이 조건 풀기)
		-- 물 칸이 아주 많으면(넓은 바다) 후보는 무작위 MaxCandidates개만 본다
		local candidates = cellList
		if #cellList > seaConfig.MaxCandidates then
			candidates = {}
			for _ = 1, seaConfig.MaxCandidates do
				table.insert(candidates, cellList[random:NextInteger(1, #cellList)])
			end
		end
		local best, bestScore = nil, -math.huge
		for _, depth in { zone.Depth, { seaConfig.MinDepth, math.huge } } do
			for _, cell in candidates do
				if cell.Depth >= depth[1] and cell.Depth <= depth[2] then
					local far = true
					for _, other in seaCenters do
						if Vector3.new(other.X - cell.X, 0, other.Z - cell.Z).Magnitude < seaConfig.ZoneGap then
							far = false
							break
						end
					end
					if far then
						local around = #cellsAround(cell, zone.Radius, depth)
						if around >= seaConfig.MinCells then
							local lo, hi = zone.Distance[1], zone.Distance[2]
							local outside = if cell.Distance < lo then lo - cell.Distance elseif cell.Distance > hi then cell.Distance - hi else 0
							local score = math.min(around, 30) - outside / 8 + random:NextNumber(0, 2)
							if score > bestScore then
								best, bestScore = cell, score
							end
						end
					end
				end
			end
			if best then
				break
			end
		end
		if not best then
			table.insert(seaSummary, `{zone.Name} 자리 없음`)
			continue
		end
		table.insert(seaCenters, best)
		-- 구역 안의 물 칸 (깊이 조건이 맞으면 그것만, 아니면 아무 물)
		local pool = cellsAround(best, zone.Radius, zone.Depth)
		if #pool < 3 then
			pool = cellsAround(best, zone.Radius, { seaConfig.MinDepth, math.huge })
		end
		-- 아직 안 쓴 칸 하나 (다른 자리와 SpotGap)
		local function freeCell()
			for _ = 1, 40 do
				local cell = pool[random:NextInteger(1, #pool)]
				local ok = true
				for _, used in seaPlaced do
					if Vector3.new(used.X - cell.X, 0, used.Z - cell.Z).Magnitude < seaConfig.SpotGap then
						ok = false
						break
					end
				end
				if ok then
					table.insert(seaPlaced, cell)
					return cell
				end
			end
			return nil
		end
		local made = 0
		local bosses = 0
		-- 주인 몹: 떼(Schools)거나 한 마리씩(Count)
		if zone.Schools then
			for schoolIndex = 1, zone.Schools do
				local cell = freeCell()
				if cell then
					local size = random:NextInteger(zone.SchoolSize[1], zone.SchoolSize[2])
					for _ = 1, size do
						local spread = seaConfig.SchoolSpread
						seaSpawn(cell, Vector3.new(random:NextNumber(-spread, spread), 0, random:NextNumber(-spread, spread)), zone.MobType, zone, { School = `{zone.Name}#{schoolIndex}`, ZoneIndex = 100 + zoneIndex })
						made += 1
					end
				end
			end
		else
			for _ = 1, zone.Count or 0 do
				local cell = freeCell()
				if cell then
					local extra = { ZoneIndex = 100 + zoneIndex }
					if bosses < (zone.BossSpots or 0) then
						extra.BossSpot = true -- 보스가 잘 나오는 자리 (Config.MobBoss.SpotChance)
						bosses += 1
					end
					seaSpawn(cell, Vector3.zero, zone.MobType, zone, extra)
					made += 1
				end
			end
		end
		-- 같은 구역에 따로 두는 몹 (해파리·낙지…)
		local extrasText = {}
		local extraIds = {}
		for id in zone.Extras or {} do
			table.insert(extraIds, id)
		end
		table.sort(extraIds)
		for _, id in extraIds do
			if MobDefs[id] and Config.Mobs[id] then
				local count = 0
				for _ = 1, zone.Extras[id] do
					local cell = freeCell()
					if cell then
						seaSpawn(cell, Vector3.zero, id, zone, { ZoneIndex = 100 + zoneIndex })
						count += 1
						made += 1
					end
				end
				table.insert(extrasText, `{MobDefs[id].DisplayName} {count}`)
			end
		end
		local direction = math.floor(math.deg(math.atan2(best.Z - center.Z, best.X - center.X)) + 0.5) % 360
		table.insert(seaSummary, `{zone.Name} {made}마리(+{table.concat(extrasText, "·")}) 거리 {math.floor(best.Distance)} 깊이 {math.floor(best.Depth)} 방향 {direction}°`)
	end
	local totalParts, total = {}, 0
	for _, id in { "Octopus", "Jellyfish", "Shark" } do
		if seaTotals[id] then
			table.insert(totalParts, `{MobDefs[id].DisplayName} {seaTotals[id]}`)
			total += seaTotals[id]
		end
	end
	print(`[BuildWeaponsAndMobs] 바다 생물 (물 칸 {#cellList}개): {table.concat(seaSummary, ", ")}`)
	print(`[BuildWeaponsAndMobs]   바다 합계 {total}마리 - {table.concat(totalParts, " / ")}`)
end

return true
