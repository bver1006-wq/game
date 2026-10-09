--!strict
-- 장비 겉모습: 끼운 헬멧·갑옷·신발·장갑·목걸이·팔찌·화살통(방패 칸, 등에 멘다)을 캐릭터 몸에 부품으로 붙여 모두에게 보이게 한다.
-- 서버가 캐릭터 안 "GearVisuals" 폴더에 부품을 만들고 몸 부위에 Weld로 붙인다 (물리·애니메이션에 영향 없음).
-- 크기·위치는 전부 몸 부위 Size에 대한 비율로 정한다 (아바타 크기가 달라도 맞게). 앞 = -Z, 위 = +Y.
-- R15가 기본이고 R6는 간단한 배치로 지원한다. 조정할 수치는 Config.GearVisual.
-- 무기 칸은 손에 든 도구라 여기서 다루지 않는다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local EquipmentDefs = require(ReplicatedStorage.Shared.EquipmentDefs)
local TierDefs = require(ReplicatedStorage.Shared.TierDefs)

type EquipmentDef = EquipmentDefs.EquipmentDef

local GearVisualService = {}

local FOLDER_NAME = "GearVisuals"
local ORIG_ATTR = "GearOrigTransparency" -- 숨긴 머리카락·모자의 원래 투명도
local VISUAL_SLOTS = { "Helmet", "Armor", "Boots", "Gloves", "Necklace", "Bracelet", "Shield" }

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
	Gem: Color3, -- 보석 빛·볏 색 (4단계 다이아 하늘색, 5 미스릴 파랑, 6 오리하르콘 주황)
	GlowBrightness: number,
	GlowRange: number,
	Sparkle: number, -- 반짝이 입자 (1초에 몇 개, 0이면 없음)
	Wings: boolean, -- 투구 큰 날개·장화 발목 날개 (6단계)
	Shoulder: boolean, -- 어깨 뿔 (6단계)
}

type Ctx = {
	Folder: Folder,
	Character: Model,
	R15: boolean,
	ArmorTier: number, -- 갑옷을 입었으면 단계, 아니면 0 (목걸이 앞쪽 띄우기용)
	Arrows: number, -- 화살통에 꽂혀 보이는 화살 수
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

-- 단계별 재질·색 정하기 (1 가죽·뼈·나무 / 2 구리 / 3 철 / 4 다이아몬드 / 5 미스릴 / 6 오리하르콘)
-- 5단계부터는 Config.GearVisual.HighTiers (표에 없는 더 높은 단계는 가장 높은 아래 단계 값)
local function styleFor(def: EquipmentDef): Style
	local tier = def.Tier
	local base = { Gem = gv().GemColor, GlowBrightness = gv().GlowBrightness, GlowRange = gv().GlowRange }
	local high = if tier >= 5 then TierDefs.pick(gv().HighTiers, tier) else nil
	if high then
		return {
			Main = def.Color, MainMat = Enum.Material.Metal, MainAlpha = 0,
			Trim = high.Trim, TrimMat = high.TrimMat,
			Accent = high.Accent, AccentMat = Enum.Material.Neon, Tier = tier,
			Gem = high.Gem, GlowBrightness = high.GlowBrightness, GlowRange = high.GlowRange,
			Sparkle = high.Sparkle, Wings = high.Wings == true, Shoulder = high.Shoulder == true,
		}
	end
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
		Gem = base.Gem, GlowBrightness = base.GlowBrightness, GlowRange = base.GlowRange,
			Sparkle = 0, Wings = false, Shoulder = false,
		}
	elseif tier == 2 then
		return {
			Main = def.Color, MainMat = Enum.Material.Metal, MainAlpha = 0,
			Trim = C(150, 80, 42), TrimMat = Enum.Material.Metal,
			Accent = C(240, 170, 95), AccentMat = Enum.Material.Metal, Tier = tier,
		Gem = base.Gem, GlowBrightness = base.GlowBrightness, GlowRange = base.GlowRange,
			Sparkle = 0, Wings = false, Shoulder = false,
		}
	elseif tier == 3 then
		return {
			Main = def.Color, MainMat = Enum.Material.Metal, MainAlpha = 0,
			Trim = C(105, 110, 122), TrimMat = Enum.Material.Metal,
			Accent = C(225, 228, 236), AccentMat = Enum.Material.Metal, Tier = tier,
		Gem = base.Gem, GlowBrightness = base.GlowBrightness, GlowRange = base.GlowRange,
			Sparkle = 0, Wings = false, Shoulder = false,
		}
	end
	return {
		Main = def.Color, MainMat = Enum.Material.Glass, MainAlpha = 0.1,
		Trim = C(235, 245, 255), TrimMat = Enum.Material.Metal,
		Accent = gv().GemColor, AccentMat = Enum.Material.Neon, Tier = tier,
		Gem = base.Gem, GlowBrightness = base.GlowBrightness, GlowRange = base.GlowRange,
		Sparkle = 0, Wings = false, Shoulder = false,
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

-- 다이아몬드 이상 장비의 은은한 빛 (색·밝기는 단계 모양 style)
local function glow(p: BasePart, style: Style)
	local light = Instance.new("PointLight")
	light.Color = style.Gem
	light.Brightness = style.GlowBrightness
	light.Range = style.GlowRange
	light.Shadows = false
	light.Parent = p
end

-- 5단계 이상: 보석에서 반짝이 입자가 조금씩 튄다 (style.Sparkle = 1초에 몇 개)
local function sparkle(p: BasePart, style: Style)
	if style.Sparkle <= 0 then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(style.Gem, Color3.new(1, 1, 1))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.18, 0)
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Speed = NumberRange.new(0.3, 1)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = style.Sparkle
	emitter.Parent = p
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
		-- (5단계 미스릴은 파란 볏, 6단계 오리하르콘은 더 큰 주황 볏 + 큰 금빛 날개 두 겹)
		local crestScale = if tier >= 6 then 1.35 else 1
		wedge(ctx, head, "HelmetCrest", Vector3.new(m * 0.09, hy * 0.42 * crestScale, m * 0.6 * crestScale), CFrame.new(0, topY + hy * 0.12 * crestScale, hz * 0.15), style.Gem, Enum.Material.Neon)
		for _, side in { -1, 1 } do
			if style.Wings then
				wedge(
					ctx, head, "HelmetWing", Vector3.new(hx * 0.07, hy * 0.85, hz * 0.85),
					CFrame.new(side * hx * 0.7, hy * 0.6, hz * 0.28) * CFrame.Angles(0, 0, -side * 0.45),
					style.Trim, style.TrimMat
				)
				wedge(
					ctx, head, "HelmetWingInner", Vector3.new(hx * 0.06, hy * 0.6, hz * 0.6),
					CFrame.new(side * hx * 0.66, hy * 0.42, hz * 0.32) * CFrame.Angles(0, 0, -side * 0.75),
					style.Main, style.MainMat
				)
			else
				wedge(
					ctx, head, "HelmetWing", Vector3.new(hx * 0.06, hy * 0.42, hz * 0.5),
					CFrame.new(side * hx * 0.66, hy * 0.42, hz * 0.18) * CFrame.Angles(0, 0, -side * 0.3),
					style.Trim, style.TrimMat
				)
			end
		end
		local g = gem(ctx, head, "HelmetGem", m * gv().GemSize * (if tier >= 5 then 1.7 else 1.4), CFrame.new(0, brimY, -brimD / 2 - hz * 0.02), style)
		glow(g, style)
		sparkle(g, style)
		if tier >= 5 then
			-- 보석 양옆으로 빛나는 줄 (눈썹처럼)
			for _, side in { -1, 1 } do
				piece(ctx, head, "HelmetBrowLine", BLOCK, Vector3.new(m * 0.3, hy * 0.05, hz * 0.05), CFrame.new(side * m * 0.24, brimY + hy * 0.08, -brimD / 2) * CFrame.Angles(0, 0, side * 0.18), style.Gem, Enum.Material.Neon)
			end
		end
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
	local scales = gv().PauldronScale
	local scale = scales[math.clamp(style.Tier - 2, 1, #scales)] or 1.5 -- 3단계 = 첫 값, 단계마다 다음 값
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
			if style.Shoulder then
				-- 6단계: 위로·바깥으로 솟은 금빛 뿔 + 빛나는 끝
				local spikeLen = d * 0.55
				local spike = CFrame.new(side * (a.X * 0.12 + d * 0.18), y + d * 0.42, 0) * CFrame.Angles(0, 0, -side * 0.45)
				piece(ctx, arm, "PauldronSpike", CYLINDER, Vector3.new(spikeLen, d * 0.16, d * 0.16), spike * CFrame.new(0, spikeLen / 2, 0) * AXIS_Y, style.Trim, style.TrimMat)
				local tip = d * 0.16
				piece(ctx, arm, "PauldronSpikeTip", BALL, Vector3.new(tip, tip, tip), spike * CFrame.new(0, spikeLen, 0), style.Accent, Enum.Material.Neon)
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
			local g = gem(ctx, torso, "ChestGem", tx * gv().GemSize * (if tier >= 5 then 2 else 1.6), CFrame.new(0, -ty * 0.12, front - plateT - plateT * 0.4), style)
			glow(g, style)
			sparkle(g, style)
			if tier >= 5 then
				-- 가슴판 위 빛나는 V자 줄 (미스릴 파랑 / 오리하르콘 주황)
				for _, side in { -1, 1 } do
					piece(ctx, torso, "ChestRune", BLOCK, Vector3.new(tx * 0.05, ty * 0.42, plateT * 0.4), CFrame.new(side * tx * 0.2, ty * 0.14, front - plateT - plateT * 0.2) * CFrame.Angles(0, 0, side * 0.4), style.Gem, Enum.Material.Neon)
				end
			end
			if tier == 4 and gv().DiamondSparkles then
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
				if style.Wings then
					-- 6단계: 발목 바깥쪽 작은 날개
					local outward = if side == "Left" then -1 else 1
					wedge(ctx, leg, "BootWing", Vector3.new(l.X * 0.06, l.Y * 0.32, l.Z * 0.7), CFrame.new(outward * d * 0.52, -l.Y * 0.22, l.Z * 0.15) * CFrame.Angles(0, 0, -outward * 0.35), style.Trim, style.TrimMat)
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
	local cordColor = if tier == 1 then C(110, 70, 40) elseif tier == 2 then C(150, 80, 42) elseif tier == 3 then C(95, 100, 110) elseif tier == 4 then C(235, 245, 255) else style.Trim
	local cordMat = if tier == 1 then Enum.Material.Fabric elseif tier >= 5 then style.TrimMat else Enum.Material.Metal

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
		local dd = tx * (if tier == 2 then 0.15 elseif tier == 3 then 0.18 elseif tier == 4 then 0.2 else 0.23)
		local thick = cordT * 1.6
		piece(ctx, torso, "Pendant", CYLINDER, Vector3.new(thick, dd, dd), CFrame.new(0, py, pz) * AXIS_Z, style.Main, if tier >= 4 then Enum.Material.Metal else style.MainMat)
		if tier == 2 then
			piece(ctx, torso, "PendantInner", CYLINDER, Vector3.new(thick * 1.2, dd * 0.55, dd * 0.55), CFrame.new(0, py, pz) * AXIS_Z, style.Accent, style.AccentMat)
		elseif tier == 3 then
			local s = dd * 0.35
			piece(ctx, torso, "PendantStud", BALL, Vector3.new(s, s, s), CFrame.new(0, py, pz - thick * 0.4), style.Accent, style.AccentMat)
		else
			piece(ctx, torso, "PendantFrame", CYLINDER, Vector3.new(thick * 1.1, dd * 0.8, dd * 0.8), CFrame.new(0, py, pz) * AXIS_Z, style.Trim, style.TrimMat)
			local pendantGem = gem(ctx, torso, "PendantGem", dd * 0.5, CFrame.new(0, py, pz - thick * 0.6), style)
			sparkle(pendantGem, style)
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

---------------------------------------------------------------- 화살통 (방패 칸)
-- 몸통 XY 평면 위 두 점을 잇는 띠 조각 (z 고정). 어깨끈·가슴끈용
local function strapSegment(ctx: Ctx, body: BasePart, name: string, a: Vector3, b: Vector3, width: number, thick: number, color: Color3, material: Enum.Material): Part
	local dir = b - a
	local angle = math.atan2(-dir.X, dir.Y)
	return piece(ctx, body, name, BLOCK, Vector3.new(width, dir.Magnitude + width * 0.5, thick), CFrame.new((a + b) / 2) * CFrame.Angles(0, 0, angle), color, material)
end

-- 화살 하나 (frame = 화살통 입구 안쪽의 화살 밑동, 위 = +Y). 나무 화살대 + 두 겹 깃 + 오늬
local function buildArrow(ctx: Ctx, body: BasePart, frame: CFrame, length: number, thick: number, vane: Color3, vane2: Color3)
	piece(ctx, body, "ArrowShaft", CYLINDER, Vector3.new(length, thick, thick), frame * CFrame.new(0, length / 2, 0) * AXIS_Y, C(214, 178, 128), Enum.Material.Wood)
	local fh = length * 0.3
	local fw = thick * 3.2
	local fy = length - fh / 2 - length * 0.06
	piece(ctx, body, "ArrowVane", BLOCK, Vector3.new(fw, fh, thick * 0.3), frame * CFrame.new(0, fy, 0), vane, Enum.Material.Fabric)
	piece(ctx, body, "ArrowVane", BLOCK, Vector3.new(fw, fh, thick * 0.3), frame * CFrame.new(0, fy, 0) * CFrame.Angles(0, math.pi / 2, 0), vane2, Enum.Material.Fabric)
	-- 깃 아래 묶은 실과 끝 오늬
	piece(ctx, body, "ArrowWrap", CYLINDER, Vector3.new(thick * 1.2, thick * 1.35, thick * 1.35), frame * CFrame.new(0, fy - fh / 2, 0) * AXIS_Y, C(60, 40, 30), Enum.Material.Fabric)
	piece(ctx, body, "ArrowNock", CYLINDER, Vector3.new(thick * 1.1, thick * 1.3, thick * 1.3), frame * CFrame.new(0, length + thick * 0.4, 0) * AXIS_Y, C(45, 35, 30), Enum.Material.SmoothPlastic)
end

-- 등에 비스듬히 멘 가죽 화살통 (입구는 오른쪽 어깨 위) + 가슴을 가로지르는 어깨끈·버클 + 꽂힌 화살 ctx.Arrows개
-- 1단계 나무 화살통: 밝은 가죽 + 황동 테 / 3단계 철 화살통: 짙은 가죽 + 철 테·징
local function buildQuiver(ctx: Ctx, def: EquipmentDef)
	local torso = bodyPart(ctx.Character, if ctx.R15 then "UpperTorso" else "Torso")
	if not torso then
		return
	end
	local tier = def.Tier
	local t = torso.Size
	local tx, ty, tz = t.X, t.Y, t.Z
	local armored = ctx.ArmorTier > 0
	local backZ = if armored then tz * gv().ArmorDepth / 2 else tz / 2
	local frontZ = if armored then armorFrontDepth(tz, ctx.ArmorTier) else tz / 2

	local rimColor = if tier >= 5 then C(150, 200, 255) elseif tier >= 3 then C(170, 176, 188) else C(205, 160, 75) -- 5 미스릴 / 3 철 / 1 황동
	local rimMat = Enum.Material.Metal
	local leather = def.Color
	local dark = leather:Lerp(Color3.new(0, 0, 0), 0.35)
	local strapColor = C(78, 48, 30)

	-- 화살통 자리: 등 뒤에 띄우고 위쪽이 오른쪽(+X) 어깨로 가게 기울인다
	local len = ty * (if ctx.R15 then 1.2 else 0.95)
	local dia = tx * 0.3
	local tilt = math.rad(Config.Quiver.Tilt)
	local q = CFrame.new(-tx * 0.05, ty * 0.08, backZ + dia * 0.5 + tz * 0.04) * CFrame.Angles(0, 0, -tilt)

	-- 몸통(가죽 원통)과 바닥 덮개, 위 입구 테, 가운데·아래 띠
	piece(ctx, torso, "QuiverBody", CYLINDER, Vector3.new(len, dia, dia), q * AXIS_Y, leather, Enum.Material.Leather)
	piece(ctx, torso, "QuiverBottom", CYLINDER, Vector3.new(len * 0.08, dia * 1.06, dia * 1.06), q * CFrame.new(0, -len / 2 + len * 0.03, 0) * AXIS_Y, dark, Enum.Material.Leather)
	piece(ctx, torso, "QuiverRim", CYLINDER, Vector3.new(len * 0.07, dia * 1.14, dia * 1.14), q * CFrame.new(0, len / 2 - len * 0.03, 0) * AXIS_Y, rimColor, rimMat)
	for _, y in { 0.12, -0.3 } do
		piece(ctx, torso, "QuiverBand", CYLINDER, Vector3.new(len * 0.035, dia * 1.07, dia * 1.07), q * CFrame.new(0, len * y, 0) * AXIS_Y, if tier >= 3 then rimColor else dark, if tier >= 3 then rimMat else Enum.Material.Leather)
	end
	-- 바깥쪽(뒤, +Z) 바느질 줄과 장식
	local outZ = dia / 2
	piece(ctx, torso, "QuiverStitch", BLOCK, Vector3.new(dia * 0.1, len * 0.78, dia * 0.06), q * CFrame.new(0, -len * 0.04, outZ), C(232, 205, 150), Enum.Material.Fabric)
	if tier >= 3 then
		-- 철 화살통: 띠마다 징 + 가운데 철 문장
		for _, y in { 0.12, -0.3 } do
			local s = dia * 0.14
			piece(ctx, torso, "QuiverStud", BALL, Vector3.new(s, s, s), q * CFrame.new(0, len * y, outZ + dia * 0.03), C(225, 228, 236), rimMat)
		end
		piece(ctx, torso, "QuiverCrest", BLOCK, Vector3.new(dia * 0.38, dia * 0.38, dia * 0.08), q * CFrame.new(0, -len * 0.09, outZ + dia * 0.03) * CFrame.Angles(0, 0, math.pi / 4), rimColor, rimMat)
	else
		-- 나무 화살통: 가운데 금색 잎사귀 장식
		piece(ctx, torso, "QuiverLeaf", BLOCK, Vector3.new(dia * 0.28, dia * 0.42, dia * 0.06), q * CFrame.new(0, -len * 0.09, outZ + dia * 0.03) * CFrame.Angles(0, 0, math.pi / 4), C(225, 185, 95), Enum.Material.SmoothPlastic)
	end

	-- 꽂힌 화살 (입구 둘레에 고르게, 바깥으로 살짝 벌어지게)
	local count = math.clamp(math.floor(ctx.Arrows), 0, Config.Quiver.VisibleArrows)
	local arrowLen = len * 0.5
	local thick = dia * 0.08
	local vaneA = if tier >= 5 then C(90, 170, 255) elseif tier >= 3 then C(70, 130, 230) else C(215, 60, 55)
	local vaneB = C(248, 246, 238)
	local baseY = len / 2 - len * 0.2
	for i = 1, count do
		local px, pz = 0, 0
		if count > 1 then
			local angle = (i - 1) / count * math.pi * 2 + 0.3
			local r = dia * (if i % 2 == 0 then 0.24 else 0.3)
			px, pz = math.cos(angle) * r, math.sin(angle) * r
		end
		local splay = 0.14
		local radius = math.max(math.sqrt(px * px + pz * pz), 1e-3)
		local frame = q * CFrame.new(px, baseY + (i % 3) * len * 0.025, pz) * CFrame.Angles(pz / radius * splay, 0, -px / radius * splay)
		buildArrow(ctx, torso, frame, arrowLen, thick, if i % 2 == 1 then vaneA else vaneB, if i % 2 == 1 then vaneB else vaneA)
	end

	-- 어깨끈: 오른쪽 어깨 위로 넘어와 가슴을 가로질러 왼쪽 옆구리로 (앞뒤 모두)
	local strapW = tx * 0.11
	local strapT = tz * 0.06
	local shoulder = Vector3.new(tx * 0.26, ty * 0.5, 0)
	local hip = Vector3.new(-tx * 0.42, -ty * 0.42, 0)
	local fz = -frontZ - strapT / 2
	local bz = backZ + strapT / 2
	strapSegment(ctx, torso, "QuiverStrap", Vector3.new(shoulder.X, shoulder.Y, fz), Vector3.new(hip.X, hip.Y, fz), strapW, strapT, strapColor, Enum.Material.Leather)
	strapSegment(ctx, torso, "QuiverStrap", Vector3.new(shoulder.X, shoulder.Y, bz), Vector3.new(hip.X, hip.Y, bz), strapW, strapT, strapColor, Enum.Material.Leather)
	piece(ctx, torso, "QuiverStrapTop", BLOCK, Vector3.new(strapW, strapT, frontZ + backZ + strapT * 2), CFrame.new(shoulder.X, shoulder.Y + strapT / 2, (backZ - frontZ) / 2), strapColor, Enum.Material.Leather)
	-- 가슴 버클 (금속 테 + 가운데 가죽)
	local mid = Vector3.new(shoulder.X, shoulder.Y, 0):Lerp(Vector3.new(hip.X, hip.Y, 0), 0.4)
	local angle = math.atan2(-(hip.X - shoulder.X), hip.Y - shoulder.Y)
	local buckle = CFrame.new(mid.X, mid.Y, fz - strapT) * CFrame.Angles(0, 0, angle)
	piece(ctx, torso, "QuiverBuckle", BLOCK, Vector3.new(strapW * 1.6, strapW * 1.3, strapT), buckle, rimColor, rimMat)
	piece(ctx, torso, "QuiverBuckleIn", BLOCK, Vector3.new(strapW * 0.9, strapW * 0.6, strapT * 1.2), buckle, strapColor, Enum.Material.Leather)
	-- 끈 끝 고리 (어깨 쪽 앞)
	local ring = strapW * 0.55
	piece(ctx, torso, "QuiverStrapRing", BALL, Vector3.new(ring, ring, ring), CFrame.new(shoulder.X - strapW * 0.1, shoulder.Y - ty * 0.12, fz - strapT * 0.5), rimColor, rimMat)
end

local BUILDERS: { [string]: (Ctx, EquipmentDef) -> () } = {
	Helmet = buildHelmet,
	Armor = buildArmor,
	Boots = buildBoots,
	Gloves = buildGloves,
	Necklace = buildNecklace,
	Bracelet = buildBracelet,
	Shield = buildQuiver,
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
-- 화살통을 메고 있으면 보이는 화살 수도 넣는다 (화살이 줄면 다시 짓게)
local function makeKey(slots: { [string]: string }, arrows: number): string
	local parts = {}
	for _, slot in VISUAL_SLOTS do
		local itemId = slots[slot]
		local def = if itemId then EquipmentDefs.Items[itemId] else nil
		table.insert(parts, if def and def.Slot == slot then itemId else "")
	end
	if slots.Shield then
		table.insert(parts, tostring(arrows))
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

-- 착용 장비 모양을 캐릭터에 입힌다 (slots: 칸 Id → 아이템 Id, arrows: 화살통에 꽂혀 보이는 화살 수).
-- 이전 모양은 지우고 다시 만든다. 캐릭터가 없으면 아무것도 안 한다
function GearVisualService.apply(player: Player, slots: { [string]: string }, arrows: number?)
	local character = player.Character
	if not character then
		return
	end
	local arrowCount = arrows or 0
	local key = makeKey(slots, arrowCount)
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
		Arrows = arrowCount,
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
