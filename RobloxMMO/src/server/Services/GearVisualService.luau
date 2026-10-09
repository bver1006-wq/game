--!strict
-- 장비 겉모습: 끼운 헬멧·갑옷·신발·장갑·목걸이·팔찌를 캐릭터 몸에 부품으로 붙여 모두에게 보이게 한다.
-- 서버가 캐릭터 안 "GearVisuals" 폴더에 부품을 만들고 몸 부위에 Weld로 붙인다 (물리·애니메이션에 영향 없음).
-- 크기·위치는 전부 몸 부위 Size에 대한 비율로 정한다 (아바타 크기가 달라도 맞게). 앞 = -Z, 위 = +Y.
-- R15가 기본이고 R6는 간단한 배치로 지원한다. 조정할 수치는 Config.GearVisual.
-- 무기 칸은 손에 든 도구라 여기서 다루지 않는다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local EquipmentDefs = require(ReplicatedStorage.Shared.EquipmentDefs)

type EquipmentDef = EquipmentDefs.EquipmentDef

local GearVisualService = {}

local FOLDER_NAME = "GearVisuals"
local ORIG_ATTR = "GearOrigTransparency" -- 숨긴 머리카락·모자의 원래 투명도
local VISUAL_SLOTS = { "Helmet", "Armor", "Boots", "Gloves", "Necklace", "Bracelet" }

local C = Color3.fromRGB
local BLOCK = Enum.PartType.Block
local BALL = Enum.PartType.Ball
local CYLINDER = Enum.PartType.Cylinder
local AXIS_Y = CFrame.Angles(0, 0, math.pi / 2) -- 원기둥 축(X)을 위(Y)로 세움
local AXIS_Z = CFrame.Angles(0, math.pi / 2, 0) -- 원기둥 축(X)을 앞(Z)으로 돌림 (앞을 보는 원판)

-- 단계별 겉모습 (주 재질 색은 장비 정의 Color, 나머지는 테두리·장식)
type Style = {
	Main: Color3,
	MainMat: Enum.Material,
	MainAlpha: number,
	Trim: Color3,
	TrimMat: Enum.Material,
	Accent: Color3, -- 단추·버클·징 같은 작은 장식
	AccentMat: Enum.Material,
	Tier: number,
}

type Ctx = {
	Folder: Folder,
	Character: Model,
	R15: boolean,
	ArmorTier: number, -- 갑옷을 입었으면 단계, 아니면 0 (목걸이 앞쪽 띄우기용)
}

type CharState = {
	Key: string,
	Folder: Folder?,
	HairHidden: boolean,
	Conns: { RBXScriptConnection },
}

-- 캐릭터마다 지금 만들어 둔 것 (같은 장비로 다시 부르면 아무것도 안 한다)
local states: { [Model]: CharState } = setmetatable({}, { __mode = "k" }) :: any

local function gv(): any
	return Config.GearVisual :: any
end

-- 단계별 재질·색 정하기 (1 가죽·뼈·나무 / 2 구리 / 3 철 / 4 다이아몬드)
local function styleFor(def: EquipmentDef): Style
	local tier = def.Tier
	if tier <= 1 then
		local mat = Enum.Material.Leather
		if def.Slot == "Bracelet" then
			mat = Enum.Material.Wood
		elseif def.Slot == "Necklace" then
			mat = Enum.Material.Fabric
		end
		return {
			Main = def.Color, MainMat = mat, MainAlpha = 0,
			Trim = C(95, 62, 38), TrimMat = Enum.Material.Fabric,
			Accent = C(225, 185, 95), AccentMat = Enum.Material.SmoothPlastic, Tier = tier,
		}
	elseif tier == 2 then
		return {
			Main = def.Color, MainMat = Enum.Material.Metal, MainAlpha = 0,
			Trim = C(150, 80, 42), TrimMat = Enum.Material.Metal,
			Accent = C(240, 170, 95), AccentMat = Enum.Material.Metal, Tier = tier,
		}
	elseif tier == 3 then
		return {
			Main = def.Color, MainMat = Enum.Material.Metal, MainAlpha = 0,
			Trim = C(105, 110, 122), TrimMat = Enum.Material.Metal,
			Accent = C(225, 228, 236), AccentMat = Enum.Material.Metal, Tier = tier,
		}
	end
	return {
		Main = def.Color, MainMat = Enum.Material.Glass, MainAlpha = 0.1,
		Trim = C(235, 245, 255), TrimMat = Enum.Material.Metal,
		Accent = gv().GemColor, AccentMat = Enum.Material.Neon, Tier = tier,
	}
end

-- 캐릭터에서 이름으로 몸 부위 찾기 (없으면 nil)
local function bodyPart(character: Model, name: string): BasePart?
	local p = character:FindFirstChild(name)
	if p and p:IsA("BasePart") then
		return p
	end
	return nil
end

-- 부품 하나를 만들어 몸 부위 기준 offset 자리에 놓고 Weld로 붙인다
local function piece(
	ctx: Ctx,
	body: BasePart,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material,
	transparency: number?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = material
	p.Transparency = transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.CFrame = body.CFrame * offset
	local w = Instance.new("Weld")
	w.Part0 = body
	w.Part1 = p
	w.C0 = offset
	w.C1 = CFrame.identity
	w.Parent = p
	p.Parent = ctx.Folder
	return p
end

-- 쐐기 부품 (볏·날개용). 높은 쪽이 +Z(뒤)
local function wedge(ctx: Ctx, body: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): WedgePart
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.CFrame = body.CFrame * offset
	local w = Instance.new("Weld")
	w.Part0 = body
	w.Part1 = p
	w.C0 = offset
	w.Parent = p
	p.Parent = ctx.Folder
	return p
end

-- 세운 원기둥 (팔찌·장갑 목·장화 목 고리). 지름 d, 높이 h, 부위 중심에서 위로 y
local function ringY(ctx: Ctx, body: BasePart, name: string, h: number, d: number, y: number, color: Color3, material: Enum.Material, alpha: number?): Part
	return piece(ctx, body, name, CYLINDER, Vector3.new(h, d, d), CFrame.new(0, y, 0) * AXIS_Y, color, material, alpha)
end

-- 마름모 모양 보석 (앞을 보게). 4단계면 빛나는 Neon
local function gem(ctx: Ctx, body: BasePart, name: string, size: number, offset: CFrame, style: Style): Part
	local mat = if style.Tier >= 4 then Enum.Material.Neon else style.AccentMat
	return piece(ctx, body, name, BLOCK, Vector3.new(size, size, size * 0.5), offset * CFrame.Angles(0, 0, math.pi / 4), style.Accent, mat)
end

-- 다이아몬드 장비의 은은한 빛
local function glow(p: BasePart)
	local light = Instance.new("PointLight")
	light.Color = gv().GemColor
	light.Brightness = gv().GlowBrightness
	light.Range = gv().GlowRange
	light.Shadows = false
	light.Parent = p
end

---------------------------------------------------------------- 헬멧
-- 머리 위·뒤를 덮는 둥근 껍데기 + 챙. 3단계부터 코 가리개·볼 가리개, 4단계는 볏·날개·보석
local function buildHelmet(ctx: Ctx, def: EquipmentDef)
	local head = bodyPart(ctx.Character, "Head")
	if not head then
		return
	end
	local style = styleFor(def)
	-- R6 머리는 Size(2,1,1)지만 보이는 모양은 약 1.25배 정육면체
	local hs = if ctx.R15 then head.Size else Vector3.new(head.Size.Y * 1.25, head.Size.Y * 1.25, head.Size.Z * 1.25)
	local hx, hy, hz = hs.X, hs.Y, hs.Z
	local m = math.max(hx, hz)
	local d = m * gv().HelmetScale
	local tier = style.Tier

	-- 껍데기: 위·뒤로 밀어 올려 얼굴은 보이게
	local domeY = hy * 0.34
	piece(ctx, head, "HelmetDome", BALL, Vector3.new(d, d, d), CFrame.new(0, domeY, hz * 0.08), style.Main, style.MainMat, style.MainAlpha)
	-- 챙(테두리)
	local brimY = hy * 0.2
	local brimD = m * (if tier == 1 then 1.3 else 1.22)
	local brimH = hy * (if tier == 1 then 0.07 else 0.1)
	ringY(ctx, head, "HelmetBrim", brimH, brimD, brimY, style.Trim, style.TrimMat)

	local topY = domeY + d / 2
	if tier == 1 then
		-- 가죽 모자: 꼭대기 동그란 꼭지
		local k = m * 0.2
		piece(ctx, head, "HelmetKnob", BALL, Vector3.new(k, k, k), CFrame.new(0, topY - k * 0.2, hz * 0.08), style.Trim, style.TrimMat)
		return
	end

	-- 2단계부터: 뒷목 가리개
	piece(ctx, head, "HelmetNeckGuard", BLOCK, Vector3.new(m * 0.95, hy * 0.45, hz * 0.14), CFrame.new(0, -hy * 0.05, hz * 0.58), style.Main, style.MainMat, style.MainAlpha)

	if tier == 2 then
		-- 구리 투구: 꼭대기 작은 뿔
		piece(ctx, head, "HelmetSpike", CYLINDER, Vector3.new(hy * 0.24, m * 0.13, m * 0.13), CFrame.new(0, topY, hz * 0.08) * AXIS_Y, style.Trim, style.TrimMat)
		return
	end

	-- 3단계부터: 코 가리개, 볼 가리개, 정수리 줄
	piece(ctx, head, "HelmetNoseGuard", BLOCK, Vector3.new(m * 0.11, hy * 0.42, hz * 0.08), CFrame.new(0, hy * 0.02, -hz * 0.56), style.Trim, style.TrimMat)
	for _, side in { -1, 1 } do
		piece(ctx, head, "HelmetCheek", BLOCK, Vector3.new(hx * 0.1, hy * 0.5, hz * 0.55), CFrame.new(side * hx * 0.56, -hy * 0.02, -hz * 0.1), style.Main, style.MainMat, style.MainAlpha)
	end
	piece(ctx, head, "HelmetRidge", BLOCK, Vector3.new(m * 0.11, hy * 0.14, m * 0.8), CFrame.new(0, topY - hy * 0.1, hz * 0.08), style.Trim, style.TrimMat)

	if tier >= 4 then
		-- 다이아몬드 투구: 빛나는 볏, 양옆 작은 날개, 이마 보석
		wedge(ctx, head, "HelmetCrest", Vector3.new(m * 0.09, hy * 0.42, m * 0.6), CFrame.new(0, topY + hy * 0.12, hz * 0.15), gv().GemColor, Enum.Material.Neon)
		for _, side in { -1, 1 } do
			wedge(
				ctx, head, "HelmetWing", Vector3.new(hx * 0.06, hy * 0.42, hz * 0.5),
				CFrame.new(side * hx * 0.66, hy * 0.42, hz * 0.18) * CFrame.Angles(0, 0, -side * 0.3),
				style.Trim, style.TrimMat
			)
		end
		local g = gem(ctx, head, "HelmetGem", m * gv().GemSize * 1.4, CFrame.new(0, brimY, -brimD / 2 - hz * 0.02), style)
		glow(g)
	end
end

---------------------------------------------------------------- 갑옷
-- 갑옷 앞면이 몸통 중심에서 얼마나 앞에 있는지 (목걸이를 그 앞에 띄우려고)
local function armorFrontDepth(tz: number, tier: number): number
	local front = tz * gv().ArmorDepth / 2
	if tier >= 2 then
		front += tz * gv().PlateThickness
	end
	return front
end

-- 어깨 보호대 (3단계 이상)
local function buildPauldrons(ctx: Ctx, style: Style)
	local names = if ctx.R15 then { "LeftUpperArm", "RightUpperArm" } else { "Left Arm", "Right Arm" }
	local scale = gv().PauldronScale[if style.Tier >= 4 then 2 else 1] or 1.5
	for i, name in names do
		local arm = bodyPart(ctx.Character, name)
		if arm then
			local side = if i == 1 then -1 else 1 -- 왼팔은 바깥이 -X
			local a = arm.Size
			local d = math.max(a.X, a.Z) * scale
			local y = a.Y * (if ctx.R15 then 0.3 else 0.38)
			piece(ctx, arm, "Pauldron", BALL, Vector3.new(d, d, d), CFrame.new(side * a.X * 0.12, y, 0), style.Main, style.MainMat, style.MainAlpha)
			-- 아래 테두리 띠
			ringY(ctx, arm, "PauldronRim", a.Y * 0.08, d * 0.98, y - d * 0.18, style.Trim, style.TrimMat)
			if style.Tier >= 4 then
				-- 바깥쪽 빛나는 징
				local g = d * 0.22
				piece(ctx, arm, "PauldronStud", BALL, Vector3.new(g, g, g), CFrame.new(side * (a.X * 0.12 + d * 0.48), y + d * 0.05, 0), style.Accent, Enum.Material.Neon)
			end
		end
	end
end

-- 몸통 덮개 + 허리띠. 1 조끼 / 2 가슴판 / 3 가슴판 + 어깨 / 4 큰 어깨 + 보석
local function buildArmor(ctx: Ctx, def: EquipmentDef)
	local torso = bodyPart(ctx.Character, if ctx.R15 then "UpperTorso" else "Torso")
	if not torso then
		return
	end
	local style = styleFor(def)
	local tier = style.Tier
	local t = torso.Size
	local tx, ty, tz = t.X, t.Y, t.Z
	local pad = gv().Padding
	local depth = tz * gv().ArmorDepth
	local plateT = tz * gv().PlateThickness
	local front = -depth / 2

	-- 몸통 덮개 (조금 더 크게)
	piece(ctx, torso, "ArmorBody", BLOCK, Vector3.new(tx * pad, ty * 0.9, depth), CFrame.new(0, -ty * 0.03, 0), style.Main, style.MainMat, style.MainAlpha)

	if tier == 1 then
		-- 가죽 조끼: 가운데 여밈 줄 + 단추 두 개
		piece(ctx, torso, "VestSeam", BLOCK, Vector3.new(tx * 0.05, ty * 0.84, tz * 0.04), CFrame.new(0, -ty * 0.03, front - tz * 0.01), style.Trim, style.TrimMat)
		for _, y in { 0.15, -0.15 } do
			local b = tx * 0.08
			piece(ctx, torso, "VestButton", BALL, Vector3.new(b, b, b), CFrame.new(tx * 0.07, ty * y, front), style.Accent, style.AccentMat)
		end
	else
		-- 가슴판
		piece(ctx, torso, "ChestPlate", BLOCK, Vector3.new(tx * 0.8, ty * 0.58, plateT), CFrame.new(0, ty * 0.1, front - plateT / 2), style.Main, style.MainMat, style.MainAlpha)
		-- 아래 테두리
		piece(ctx, torso, "ArmorHem", BLOCK, Vector3.new(tx * pad * 1.03, ty * 0.1, depth * 1.04), CFrame.new(0, -ty * 0.43, 0), style.Trim, style.TrimMat)
		if tier >= 3 then
			-- 가슴판 가운데 세로 줄
			piece(ctx, torso, "ChestRidge", BLOCK, Vector3.new(tx * 0.07, ty * 0.56, plateT * 0.6), CFrame.new(0, ty * 0.1, front - plateT - plateT * 0.25), style.Trim, style.TrimMat)
			buildPauldrons(ctx, style)
		end
		if tier >= 4 then
			-- 가슴 보석 (빛)
			local g = gem(ctx, torso, "ChestGem", tx * gv().GemSize * 1.6, CFrame.new(0, -ty * 0.12, front - plateT - plateT * 0.4), style)
			glow(g)
			if gv().DiamondSparkles then
				local s = Instance.new("Sparkles")
				s.SparkleColor = gv().GemColor
				s.Parent = g
			end
		end
	end

	-- 허리띠 (R15는 LowerTorso, R6는 Torso 아래)
	local lower = if ctx.R15 then bodyPart(ctx.Character, "LowerTorso") else torso
	if lower then
		local l = lower.Size
		local beltY = if ctx.R15 then 0 else -ty * 0.42
		local beltH = if ctx.R15 then l.Y * 0.55 else ty * 0.12
		local beltDepth = (if ctx.R15 then l.Z else tz) * gv().ArmorDepth * 1.03
		piece(ctx, lower, "Belt", BLOCK, Vector3.new(l.X * pad * 1.02, beltH, beltDepth), CFrame.new(0, beltY, 0), style.Trim, style.TrimMat)
		local buckle = Vector3.new(l.X * 0.16, beltH * 0.9, tz * 0.06)
		if tier >= 4 then
			gem(ctx, lower, "BeltGem", beltH * 0.8, CFrame.new(0, beltY, -beltDepth / 2 - tz * 0.02), style)
		else
			piece(ctx, lower, "Buckle", BLOCK, buckle, CFrame.new(0, beltY, -beltDepth / 2 - buckle.Z / 2), style.Accent, style.AccentMat)
		end
	end
end

---------------------------------------------------------------- 장화
-- 발 덮개 + 정강이 아래 목 고리 + 밑창. 2단계 앞코 덮개, 3단계 정강이판, 4단계 보석
local function buildBoots(ctx: Ctx, def: EquipmentDef)
	local style = styleFor(def)
	local tier = style.Tier
	local pad = gv().Padding
	for _, side in { "Left", "Right" } do
		if ctx.R15 then
			local foot = bodyPart(ctx.Character, side .. "Foot")
			if foot then
				local f = foot.Size
				local cover = Vector3.new(f.X * pad * 1.08, f.Y * 1.5, f.Z * pad * 1.1)
				local cy = f.Y * 0.28
				piece(ctx, foot, "Boot", BLOCK, cover, CFrame.new(0, cy, -f.Z * 0.06), style.Main, style.MainMat, style.MainAlpha)
				piece(ctx, foot, "BootSole", BLOCK, Vector3.new(cover.X * 1.03, f.Y * 0.3, cover.Z * 1.03), CFrame.new(0, cy - cover.Y / 2, -f.Z * 0.06), style.Trim, style.TrimMat)
				if tier >= 2 then
					piece(ctx, foot, "BootToe", BLOCK, Vector3.new(cover.X * 1.04, cover.Y * 0.75, f.Z * 0.28), CFrame.new(0, cy - cover.Y * 0.1, -f.Z * 0.06 - cover.Z / 2 + f.Z * 0.1), style.Trim, style.TrimMat)
				end
			end
			local leg = bodyPart(ctx.Character, side .. "LowerLeg")
			if leg then
				local l = leg.Size
				local d = math.max(l.X, l.Z) * gv().CuffScale
				ringY(ctx, leg, "BootCuff", l.Y * 0.35, d, -l.Y * 0.3, style.Main, style.MainMat, style.MainAlpha)
				ringY(ctx, leg, "BootCuffRim", l.Y * 0.08, d * 1.08, -l.Y * 0.11, style.Trim, style.TrimMat)
				if tier >= 3 then
					piece(ctx, leg, "ShinPlate", BLOCK, Vector3.new(l.X * 0.6, l.Y * 0.32, l.Z * 0.12), CFrame.new(0, l.Y * 0.08, -l.Z * 0.55), style.Main, style.MainMat, style.MainAlpha)
				end
				if tier >= 4 then
					gem(ctx, leg, "BootGem", l.X * gv().GemSize * 2, CFrame.new(0, -l.Y * 0.3, -d / 2 - l.Z * 0.02), style)
				end
			end
		else
			local leg = bodyPart(ctx.Character, side .. " Leg")
			if leg then
				local l = leg.Size
				local cover = Vector3.new(l.X * pad * 1.05, l.Y * 0.2, l.Z * pad * 1.15)
				local footY = -l.Y * 0.4
				piece(ctx, leg, "Boot", BLOCK, cover, CFrame.new(0, footY, -l.Z * 0.08), style.Main, style.MainMat, style.MainAlpha)
				piece(ctx, leg, "BootSole", BLOCK, Vector3.new(cover.X * 1.03, l.Y * 0.04, cover.Z * 1.03), CFrame.new(0, footY - cover.Y / 2, -l.Z * 0.08), style.Trim, style.TrimMat)
				local d = math.max(l.X, l.Z) * gv().CuffScale
				ringY(ctx, leg, "BootCuff", l.Y * 0.16, d, -l.Y * 0.24, style.Main, style.MainMat, style.MainAlpha)
				ringY(ctx, leg, "BootCuffRim", l.Y * 0.04, d * 1.08, -l.Y * 0.15, style.Trim, style.TrimMat)
				if tier >= 2 then
					piece(ctx, leg, "BootToe", BLOCK, Vector3.new(cover.X * 1.04, cover.Y * 0.75, l.Z * 0.25), CFrame.new(0, footY, -l.Z * 0.08 - cover.Z / 2 + l.Z * 0.1), style.Trim, style.TrimMat)
				end
				if tier >= 3 then
					piece(ctx, leg, "ShinPlate", BLOCK, Vector3.new(l.X * 0.6, l.Y * 0.18, l.Z * 0.12), CFrame.new(0, -l.Y * 0.05, -l.Z * 0.55), style.Main, style.MainMat, style.MainAlpha)
				end
				if tier >= 4 then
					gem(ctx, leg, "BootGem", l.X * gv().GemSize * 2, CFrame.new(0, -l.Y * 0.24, -d / 2 - l.Z * 0.02), style)
				end
			end
		end
	end
end

---------------------------------------------------------------- 장갑
-- 손 덮개 + 아래팔 끝 목 고리. 2단계 주먹 띠, 3단계 목 테두리, 4단계 바깥쪽 보석
local function buildGloves(ctx: Ctx, def: EquipmentDef)
	local style = styleFor(def)
	local tier = style.Tier
	local pad = gv().Padding
	for i, side in { "Left", "Right" } do
		local outward = if i == 1 then -1 else 1
		if ctx.R15 then
			local hand = bodyPart(ctx.Character, side .. "Hand")
			if hand then
				local h = hand.Size
				local cover = Vector3.new(h.X * pad * 1.08, h.Y * 1.08, h.Z * pad * 1.08)
				piece(ctx, hand, "Glove", BLOCK, cover, CFrame.new(0, -h.Y * 0.03, 0), style.Main, style.MainMat, style.MainAlpha)
				if tier >= 2 then
					piece(ctx, hand, "GloveKnuckles", BLOCK, Vector3.new(cover.X * 1.05, h.Y * 0.28, cover.Z * 1.05), CFrame.new(0, -h.Y * 0.22, 0), style.Trim, style.TrimMat)
				end
			end
			local arm = bodyPart(ctx.Character, side .. "LowerArm")
			if arm then
				local a = arm.Size
				local d = math.max(a.X, a.Z) * gv().CuffScale
				ringY(ctx, arm, "GloveCuff", a.Y * 0.28, d, -a.Y * 0.36, style.Main, style.MainMat, style.MainAlpha)
				if tier >= 3 then
					ringY(ctx, arm, "GloveCuffRim", a.Y * 0.07, d * 1.08, -a.Y * 0.22, style.Trim, style.TrimMat)
				end
				if tier >= 4 then
					gem(ctx, arm, "GloveGem", a.Z * gv().GemSize * 2, CFrame.new(outward * (d / 2 + a.X * 0.02), -a.Y * 0.36, 0) * CFrame.Angles(0, math.pi / 2, 0), style)
				end
			end
		else
			local arm = bodyPart(ctx.Character, side .. " Arm")
			if arm then
				local a = arm.Size
				piece(ctx, arm, "Glove", BLOCK, Vector3.new(a.X * pad, a.Y * 0.2, a.Z * pad), CFrame.new(0, -a.Y * 0.4, 0), style.Main, style.MainMat, style.MainAlpha)
				local d = math.max(a.X, a.Z) * gv().CuffScale
				ringY(ctx, arm, "GloveCuff", a.Y * 0.1, d, -a.Y * 0.26, style.Main, style.MainMat, style.MainAlpha)
				if tier >= 2 then
					piece(ctx, arm, "GloveKnuckles", BLOCK, Vector3.new(a.X * pad * 1.05, a.Y * 0.06, a.Z * pad * 1.05), CFrame.new(0, -a.Y * 0.44, 0), style.Trim, style.TrimMat)
				end
				if tier >= 3 then
					ringY(ctx, arm, "GloveCuffRim", a.Y * 0.03, d * 1.08, -a.Y * 0.2, style.Trim, style.TrimMat)
				end
				if tier >= 4 then
					gem(ctx, arm, "GloveGem", a.Z * gv().GemSize * 2, CFrame.new(outward * (d / 2 + a.X * 0.02), -a.Y * 0.26, 0) * CFrame.Angles(0, math.pi / 2, 0), style)
				end
			end
		end
	end
end

---------------------------------------------------------------- 목걸이
-- 두 점 사이를 잇는 가는 줄 조각 (몸통 앞 XY 평면 위)
local function cordSegment(ctx: Ctx, body: BasePart, a: Vector3, b: Vector3, width: number, thick: number, color: Color3, material: Enum.Material)
	local dir = b - a
	local angle = math.atan2(-dir.X, dir.Y)
	local mid = (a + b) / 2
	piece(ctx, body, "NecklaceCord", BLOCK, Vector3.new(width, dir.Magnitude + width, thick), CFrame.new(mid) * CFrame.Angles(0, 0, angle), color, material)
end

-- 목둘레 줄(어깨 위로 뒤까지) + 가슴의 V자 줄 + 펜던트. 갑옷을 입었으면 그 앞에 띄운다
local function buildNecklace(ctx: Ctx, def: EquipmentDef)
	local torso = bodyPart(ctx.Character, if ctx.R15 then "UpperTorso" else "Torso")
	if not torso then
		return
	end
	local style = styleFor(def)
	local tier = style.Tier
	local t = torso.Size
	local tx, ty, tz = t.X, t.Y, t.Z
	local front = if ctx.ArmorTier > 0 then armorFrontDepth(tz, ctx.ArmorTier) else tz / 2
	front += tz * gv().NecklaceGap
	local cordW = tx * 0.035
	local cordT = tz * 0.05
	local z = -front - cordT / 2
	local cordColor = if tier == 1 then C(110, 70, 40) elseif tier == 2 then C(150, 80, 42) elseif tier == 3 then C(95, 100, 110) else C(235, 245, 255)
	local cordMat = if tier == 1 then Enum.Material.Fabric else Enum.Material.Metal

	-- 어깨 위 줄 (앞에서 뒤까지)과 뒷목 줄
	local topY = ty * 0.5 + cordT / 2
	local sx = tx * 0.17
	for _, side in { -1, 1 } do
		piece(ctx, torso, "NecklaceCord", BLOCK, Vector3.new(cordW, cordT, front * 2 + cordT), CFrame.new(side * sx, topY, 0), cordColor, cordMat)
	end
	piece(ctx, torso, "NecklaceCord", BLOCK, Vector3.new(sx * 2 + cordW, cordT, cordW), CFrame.new(0, topY, front), cordColor, cordMat)

	-- 가슴 V자 줄
	local bottom = Vector3.new(0, ty * 0.12, z)
	for _, side in { -1, 1 } do
		local top = Vector3.new(side * sx, topY, z)
		cordSegment(ctx, torso, top, bottom, cordW, cordT, cordColor, cordMat)
		if tier == 1 then
			-- 뼈 구슬 두 개씩
			for _, f in { 0.35, 0.7 } do
				local p = top:Lerp(bottom, f)
				local s = tx * 0.06
				piece(ctx, torso, "BoneBead", BLOCK, Vector3.new(s, s * 1.3, s), CFrame.new(p) * CFrame.Angles(0, 0, side * 0.6), C(240, 232, 210), Enum.Material.SmoothPlastic)
			end
		end
	end

	-- 펜던트
	local py = bottom.Y - ty * 0.06
	local pz = z - cordT
	if tier == 1 then
		-- 만화 같은 뼈다귀 (가운데 막대 + 양끝 동그라미 두 개씩)
		local bone = C(245, 238, 218)
		local w = tx * 0.18
		local r = tx * 0.065
		piece(ctx, torso, "BonePendant", BLOCK, Vector3.new(w, r * 0.9, r * 0.9), CFrame.new(0, py, pz), bone, Enum.Material.SmoothPlastic)
		for _, sx2 in { -1, 1 } do
			for _, sy in { -1, 1 } do
				piece(ctx, torso, "BonePendantEnd", BALL, Vector3.new(r, r, r), CFrame.new(sx2 * w / 2, py + sy * r * 0.4, pz), bone, Enum.Material.SmoothPlastic)
			end
		end
	else
		-- 동그란 메달 (앞을 보는 원판)
		local dd = tx * (if tier == 2 then 0.15 elseif tier == 3 then 0.18 else 0.2)
		local thick = cordT * 1.6
		piece(ctx, torso, "Pendant", CYLINDER, Vector3.new(thick, dd, dd), CFrame.new(0, py, pz) * AXIS_Z, style.Main, if tier >= 4 then Enum.Material.Metal else style.MainMat)
		if tier == 2 then
			piece(ctx, torso, "PendantInner", CYLINDER, Vector3.new(thick * 1.2, dd * 0.55, dd * 0.55), CFrame.new(0, py, pz) * AXIS_Z, style.Accent, style.AccentMat)
		elseif tier == 3 then
			local s = dd * 0.35
			piece(ctx, torso, "PendantStud", BALL, Vector3.new(s, s, s), CFrame.new(0, py, pz - thick * 0.4), style.Accent, style.AccentMat)
		else
			piece(ctx, torso, "PendantFrame", CYLINDER, Vector3.new(thick * 1.1, dd * 0.8, dd * 0.8), CFrame.new(0, py, pz) * AXIS_Z, style.Trim, style.TrimMat)
			gem(ctx, torso, "PendantGem", dd * 0.5, CFrame.new(0, py, pz - thick * 0.6), style)
		end
	end
end

---------------------------------------------------------------- 팔찌
-- 왼쪽 손목 고리 (장갑 목 고리보다 커서 바깥에 보인다). 1 나무 구슬 / 2 구리 띠 / 3 은 징 / 4 보석
local function buildBracelet(ctx: Ctx, def: EquipmentDef)
	local arm = bodyPart(ctx.Character, if ctx.R15 then "LeftLowerArm" else "Left Arm")
	if not arm then
		return
	end
	local style = styleFor(def)
	local tier = style.Tier
	local a = arm.Size
	local d = math.max(a.X, a.Z) * gv().BraceletScale
	local y = -a.Y * (if ctx.R15 then 0.3 else 0.24)
	local h = a.Y * (if ctx.R15 then 0.13 else 0.06)
	ringY(ctx, arm, "Bracelet", h, d, y, style.Main, style.MainMat, style.MainAlpha)
	if tier >= 2 then
		-- 가운데 금속 띠 (살짝 더 넓게)
		ringY(ctx, arm, "BraceletBand", h * 0.4, d * 1.05, y, style.Trim, style.TrimMat)
	end
	-- 바깥(-X)·앞·뒤로 구슬·징·보석
	local r = d / 2
	if tier == 1 then
		for _, ang in { math.pi, math.pi * 0.75, math.pi * 1.25 } do
			local s = h * 1.3
			piece(ctx, arm, "BraceletBead", BALL, Vector3.new(s, s, s), CFrame.new(math.cos(ang) * r, y, math.sin(ang) * r), C(190, 140, 90), Enum.Material.Wood)
		end
	elseif tier == 3 then
		for _, ang in { math.pi * 0.75, math.pi * 1.25 } do
			local s = h * 0.9
			piece(ctx, arm, "BraceletStud", BLOCK, Vector3.new(s, s, s), CFrame.new(math.cos(ang) * r * 1.02, y, math.sin(ang) * r * 1.02), style.Accent, style.AccentMat)
		end
	elseif tier >= 4 then
		gem(ctx, arm, "BraceletGem", h * 1.4, CFrame.new(-r * 1.03, y, 0) * CFrame.Angles(0, math.pi / 2, 0), style)
	end
end

local BUILDERS: { [string]: (Ctx, EquipmentDef) -> () } = {
	Helmet = buildHelmet,
	Armor = buildArmor,
	Boots = buildBoots,
	Gloves = buildGloves,
	Necklace = buildNecklace,
	Bracelet = buildBracelet,
}

---------------------------------------------------------------- 머리카락·모자 숨기기
-- 머리카락·모자 액세서리인지 (투구와 겹치는 것만. 얼굴 장식은 건드리지 않는다)
local function isHeadwear(accessory: Accessory): boolean
	local kind = accessory.AccessoryType
	if kind == Enum.AccessoryType.Hair or kind == Enum.AccessoryType.Hat then
		return true
	end
	local handle = accessory:FindFirstChild("Handle")
	if handle then
		return handle:FindFirstChild("HairAttachment") ~= nil or handle:FindFirstChild("HatAttachment") ~= nil
	end
	return false
end

-- 액세서리 하나 숨기거나 되돌리기 (원래 투명도는 Handle 속성에 보관)
local function setAccessoryHidden(accessory: Accessory, hidden: boolean)
	if not isHeadwear(accessory) then
		return
	end
	local handle = accessory:FindFirstChild("Handle")
	if not (handle and handle:IsA("BasePart")) then
		return
	end
	local orig = handle:GetAttribute(ORIG_ATTR)
	if hidden then
		if typeof(orig) ~= "number" then
			handle:SetAttribute(ORIG_ATTR, handle.Transparency)
		end
		handle.Transparency = 1
	elseif typeof(orig) == "number" then
		handle.Transparency = orig
		handle:SetAttribute(ORIG_ATTR, nil)
	end
end

-- 캐릭터의 머리카락·모자 전부 숨기거나 되돌리기
local function setHairHidden(character: Model, hidden: boolean)
	for _, child in character:GetChildren() do
		if child:IsA("Accessory") then
			setAccessoryHidden(child, hidden)
		end
	end
end

---------------------------------------------------------------- 공개 함수
-- 겉모습에 쓰는 칸만 모아 비교용 문자열로 (무기 칸·모르는 아이템은 뺀다)
local function makeKey(slots: { [string]: string }): string
	local parts = {}
	for _, slot in VISUAL_SLOTS do
		local itemId = slots[slot]
		local def = if itemId then EquipmentDefs.Items[itemId] else nil
		table.insert(parts, if def and def.Slot == slot then itemId else "")
	end
	return table.concat(parts, ";")
end

-- 캐릭터 상태 만들기 (나중에 붙는 머리카락도 투구를 쓰고 있으면 숨기고, 캐릭터가 없어지면 정리)
local function getState(character: Model): CharState
	local st = states[character]
	if st then
		return st
	end
	local newState: CharState = { Key = "", Folder = nil, HairHidden = false, Conns = {} }
	states[character] = newState
	table.insert(newState.Conns, character.ChildAdded:Connect(function(child: Instance)
		if newState.HairHidden and child:IsA("Accessory") then
			task.defer(setAccessoryHidden, child, true) -- Handle이 막 붙는 중일 수 있어 한 박자 뒤
		end
	end))
	table.insert(newState.Conns, character.Destroying:Connect(function()
		for _, c in newState.Conns do
			c:Disconnect()
		end
		states[character] = nil
	end))
	return newState
end

-- 다음 apply 때 같은 장비여도 다시 짓게 한다 (캐릭터 외형·몸 부품이 늦게 다 들어왔을 때)
function GearVisualService.invalidate(character: Model)
	local st = states[character]
	if st then
		st.Key = "\0"
	end
end

-- 착용 장비 모양을 캐릭터에 입힌다 (slots: 칸 Id → 아이템 Id). 이전 모양은 지우고 다시 만든다. 캐릭터가 없으면 아무것도 안 한다
function GearVisualService.apply(player: Player, slots: { [string]: string })
	local character = player.Character
	if not character then
		return
	end
	local key = makeKey(slots)
	local st = getState(character)
	if st.Key == key and st.Folder and st.Folder.Parent == character then
		return -- 같은 장비: 할 일 없음
	end

	-- 옛 모양 지우기
	if st.Folder then
		st.Folder:Destroy()
	end
	for _, child in character:GetChildren() do
		if child.Name == FOLDER_NAME then
			child:Destroy()
		end
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local r15 = if humanoid then humanoid.RigType == Enum.HumanoidRigType.R15 else character:FindFirstChild("UpperTorso") ~= nil
	local armorDef = EquipmentDefs.Items[slots.Armor or ""]
	local ctx: Ctx = {
		Folder = folder,
		Character = character,
		R15 = r15,
		ArmorTier = if armorDef and armorDef.Slot == "Armor" then armorDef.Tier else 0,
	}

	local helmetWorn = false
	for _, slot in VISUAL_SLOTS do
		local itemId = slots[slot]
		local def = if itemId then EquipmentDefs.Items[itemId] else nil
		local builder = BUILDERS[slot]
		if def and def.Slot == slot and builder then
			local ok, err = pcall(builder, ctx, def)
			if not ok then
				warn("[GearVisualService] " .. slot .. " 모양 만들기 실패: " .. tostring(err))
			end
			if slot == "Helmet" then
				helmetWorn = true
			end
		end
	end
	folder.Parent = character

	-- 투구를 쓰면 머리카락·모자 숨김, 벗으면 되돌림
	local hide = helmetWorn and gv().HideHairWithHelmet == true
	setHairHidden(character, hide)
	st.HairHidden = hide
	st.Folder = folder
	st.Key = key
end

return GearVisualService
