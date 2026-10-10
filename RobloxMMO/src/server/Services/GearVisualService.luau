--!strict
-- 장비 겉모습: 끼운 헬멧·갑옷·신발·장갑·목걸이·팔찌·화살통(방패 칸, 등에 멘다)을 캐릭터 몸에 부품으로 붙여 모두에게 보이게 한다.
-- 헬멧·갑옷·신발·장갑은 몹 세트(가죽·뼈·케르베로스·사이클롭스·바위 골렘·서리 거인·베헤모스, 2026-10-10)마다 모양이 다르다 (색은 Config.GearVisual.Sets)
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
	ArmorSet: string?, -- 갑옷을 입었으면 그 세트 Id (목걸이·화살통 자리 계산용)
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

-- 장신구(목걸이·팔찌) 단계별 재질·색 정하기 (1 뼈·나무 / 2 구리 / 3 철 / 4 다이아몬드 / 5 미스릴 / 6 오리하르콘)
-- 방어구(헬멧·갑옷·신발·장갑)는 세트별 setStyle (아래 "방어구 세트 공통")
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

---------------------------------------------------------------- 방어구 세트 공통 (2026-10-10)
-- 헬멧·갑옷·신발·장갑은 세트(EquipmentDefs.Set)마다 모양이 다르다. 색·재질은 Config.GearVisual.Sets
-- 1 가죽 = 둥근 모자·조끼 / 2 뼈 = 해골 투구·갈비뼈·정강이뼈·손가락 뼈 / 3 케르베로스 = 늑대 두건·털 목도리·송곳니·발톱
-- 4 사이클롭스 = 큰 외눈 투구·덧댄 거대 가죽·둥근 큰 어깨 / 5 바위 골렘 = 네모난 돌 투구·돌판·빛나는 금과 핵·돌 주먹
-- 6 서리 거인 = 하얀 털·얼음 수정 왕관·얼음 가슴판·수정 어깨 / 7 베헤모스 = 큰 뿔 투구·검붉은 비늘·용암 틈·등 가시

-- 세트 색·재질 (Config.GearVisual.Sets 한 줄)
type SetStyle = {
	Main: Color3,
	MainMat: Enum.Material,
	Trim: Color3,
	TrimMat: Enum.Material,
	Accent: Color3,
	AccentMat: Enum.Material,
	Gem: Color3,
	Glow: number,
	GlowRange: number,
	Sparkle: number,
	Patch: Color3?,
}

-- 몸 부위 하나의 기준 (R15는 그 부위, R6는 큰 부위 안의 한 구역)
type Anchor = {
	Body: BasePart,
	Origin: CFrame, -- 부위 중심에서 이 구역 중심까지
	Size: Vector3, -- 이 구역 크기
}

-- 세트마다 몸통 덮개 크기(Bulk)와 가슴 장식이 덮개 앞으로 나오는 정도(Front, 몸통 두께 대비). 목걸이·화살통 자리 계산에도 쓴다
local SET_SHAPE: { [string]: { Bulk: number, Front: number } } = {
	Leather = { Bulk = 1, Front = 0.03 },
	Bone = { Bulk = 1, Front = 0.13 },
	Cerberus = { Bulk = 1.04, Front = 0.12 },
	Cyclops = { Bulk = 1.14, Front = 0.1 },
	Golem = { Bulk = 1.12, Front = 0.2 },
	Frost = { Bulk = 1.05, Front = 0.15 },
	Behemoth = { Bulk = 1.06, Front = 0.16 },
}

local function setShape(setId: string?): { Bulk: number, Front: number }
	return SET_SHAPE[setId or ""] or SET_SHAPE.Leather
end

-- 세트 색·재질 (없는 세트는 가죽)
local function setStyle(def: EquipmentDef): SetStyle
	local sets = gv().Sets
	return (sets[def.Set or "Leather"] or sets.Leather) :: SetStyle
end

-- 갑옷 앞면이 몸통 중심에서 얼마나 앞에 있는지 (목걸이를 그 앞에 띄우려고)
local function armorFrontDepth(tz: number, setId: string): number
	local shape = setShape(setId)
	return tz * gv().ArmorDepth * shape.Bulk / 2 + tz * shape.Front
end

-- 구역 기준 부품 (offset은 구역 중심 기준)
local function ap(ctx: Ctx, a: Anchor, name: string, shape: Enum.PartType, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, alpha: number?): Part
	return piece(ctx, a.Body, name, shape, size, a.Origin * offset, color, material, alpha)
end

local function aring(ctx: Ctx, a: Anchor, name: string, h: number, d: number, y: number, color: Color3, material: Enum.Material, alpha: number?): Part
	return ap(ctx, a, name, CYLINDER, Vector3.new(h, d, d), CFrame.new(0, y, 0) * AXIS_Y, color, material, alpha)
end

local function aball(ctx: Ctx, a: Anchor, name: string, dia: number, offset: CFrame, color: Color3, material: Enum.Material): Part
	return ap(ctx, a, name, BALL, Vector3.new(dia, dia, dia), offset, color, material)
end

-- 뾰족한 삼각 가시 (쐐기 두 개). base 기준 +Y로 length만큼 뻗고, 삼각형은 base의 YZ 평면 (너비 width, 두께 thick은 X)
-- 앞에서 삼각형이 보이게 하려면 base 끝에 CFrame.Angles(0, math.pi / 2, 0)
local function aspike(ctx: Ctx, a: Anchor, name: string, base: CFrame, length: number, width: number, thick: number, color: Color3, material: Enum.Material)
	local half = width / 2
	local size = Vector3.new(thick, length, half)
	wedge(ctx, a.Body, name, size, a.Origin * base * CFrame.new(0, length / 2, -half / 2), color, material)
	wedge(ctx, a.Body, name, size, a.Origin * base * CFrame.new(0, length / 2, half / 2) * CFrame.Angles(0, math.pi, 0), color, material)
end

-- 얼음·보석 수정 (마름모 기둥 + 끝 조각). base 기준 +Y로 뻗는다
local function acrystal(ctx: Ctx, a: Anchor, name: string, base: CFrame, length: number, width: number, color: Color3, material: Enum.Material, tipColor: Color3, tipMat: Enum.Material)
	ap(ctx, a, name, BLOCK, Vector3.new(width, length, width), base * CFrame.new(0, length / 2, 0) * CFrame.Angles(0, math.pi / 4, 0), color, material, 0.15)
	local tip = width * 0.72
	ap(ctx, a, name .. "Tip", BLOCK, Vector3.new(tip, tip, tip), base * CFrame.new(0, length, 0) * CFrame.Angles(math.pi / 4, 0, math.pi / 4), tipColor, tipMat)
end

-- 휘어진 뿔 (원기둥 n마디, 끝으로 갈수록 가늘게). base 기준 +Y로 뻗고, 마디마다 bend만큼 돈다
local function ahorn(ctx: Ctx, a: Anchor, name: string, base: CFrame, length: number, thick: number, segments: number, bend: CFrame, color: Color3, material: Enum.Material)
	local cf = base
	local segLen = length / segments
	for i = 1, segments do
		local w = thick * (1 - (i - 1) / segments * 0.72)
		ap(ctx, a, name, CYLINDER, Vector3.new(segLen * 1.12, w, w), cf * CFrame.new(0, segLen / 2, 0) * AXIS_Y, color, material)
		cf = cf * CFrame.new(0, segLen, 0) * bend
	end
end

-- 두 점(구역 기준, 같은 z)을 잇는 띠
local function asegment(ctx: Ctx, a: Anchor, name: string, p1: Vector3, p2: Vector3, width: number, thick: number, color: Color3, material: Enum.Material): Part
	local dir = p2 - p1
	local angle = math.atan2(-dir.X, dir.Y)
	return ap(ctx, a, name, BLOCK, Vector3.new(width, dir.Magnitude + width * 0.5, thick), CFrame.new((p1 + p2) / 2) * CFrame.Angles(0, 0, angle), color, material)
end

-- 빛 (세트 Glow가 0이면 없음)
local function setGlow(p: BasePart, s: SetStyle)
	if s.Glow <= 0 then
		return
	end
	local light = Instance.new("PointLight")
	light.Color = s.Gem
	light.Brightness = s.Glow
	light.Range = s.GlowRange
	light.Shadows = false
	light.Parent = p
end

-- 입자 (세트 Sparkle이 0이면 없음). rise > 0 이면 불티처럼 위로, < 0 이면 눈송이처럼 아래로
local function setParticles(p: BasePart, s: SetStyle, rise: number)
	if s.Sparkle <= 0 then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(s.Gem, if rise > 0 then Color3.fromRGB(255, 220, 120) else Color3.new(1, 1, 1))
	emitter.LightEmission = if rise > 0 then 1 else 0.6
	emitter.Size = NumberSequence.new(0.16, 0)
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.Speed = NumberRange.new(0.2, 0.8)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, rise, 0)
	emitter.Rate = s.Sparkle
	emitter.Parent = p
end

-- 밝게·어둡게 섞은 색
local function lighten(c: Color3, f: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), f)
end
local function darken(c: Color3, f: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), f)
end

-- 앞에서 보이는 방향으로 돌리기 (가시 삼각형이 앞을 보게)
local FACE_FRONT = CFrame.Angles(0, math.pi / 2, 0)
local POINT_DOWN = CFrame.Angles(0, 0, math.pi)

---------------------------------------------------------------- 구역 찾기 (R15 / R6)
local function headAnchor(ctx: Ctx): Anchor?
	local head = bodyPart(ctx.Character, "Head")
	if not head then
		return nil
	end
	-- R6 머리는 Size(2,1,1)지만 보이는 모양은 약 1.25배 정육면체
	local size = if ctx.R15 then head.Size else Vector3.new(head.Size.Y * 1.25, head.Size.Y * 1.25, head.Size.Z * 1.25)
	return { Body = head, Origin = CFrame.identity, Size = size }
end

local function torsoAnchor(ctx: Ctx): Anchor?
	local torso = bodyPart(ctx.Character, if ctx.R15 then "UpperTorso" else "Torso")
	if not torso then
		return nil
	end
	if ctx.R15 then
		return { Body = torso, Origin = CFrame.identity, Size = torso.Size }
	end
	local t = torso.Size
	return { Body = torso, Origin = CFrame.new(0, t.Y * 0.12, 0), Size = Vector3.new(t.X, t.Y * 0.76, t.Z) }
end

local function beltAnchor(ctx: Ctx): Anchor?
	if ctx.R15 then
		local lower = bodyPart(ctx.Character, "LowerTorso")
		return if lower then { Body = lower, Origin = CFrame.identity, Size = lower.Size } else nil
	end
	local torso = bodyPart(ctx.Character, "Torso")
	if not torso then
		return nil
	end
	local t = torso.Size
	return { Body = torso, Origin = CFrame.new(0, -t.Y * 0.38, 0), Size = Vector3.new(t.X, t.Y * 0.22, t.Z) }
end

-- 팔다리 구역: kind = "UpperArm" | "LowerArm" | "Hand" | "LowerLeg" | "Foot", side = "Left" | "Right"
local R6_LIMB: { [string]: { Part: string, Y: number, H: number } } = {
	UpperArm = { Part = "Arm", Y = 0.25, H = 0.5 },
	LowerArm = { Part = "Arm", Y = -0.1, H = 0.45 },
	Hand = { Part = "Arm", Y = -0.4, H = 0.2 },
	LowerLeg = { Part = "Leg", Y = -0.15, H = 0.45 },
	Foot = { Part = "Leg", Y = -0.43, H = 0.13 },
}
local function limbAnchor(ctx: Ctx, side: string, kind: string): Anchor?
	if ctx.R15 then
		local p = bodyPart(ctx.Character, side .. kind)
		return if p then { Body = p, Origin = CFrame.identity, Size = p.Size } else nil
	end
	local info = R6_LIMB[kind]
	local p = bodyPart(ctx.Character, side .. " " .. info.Part)
	if not p then
		return nil
	end
	local s = p.Size
	return { Body = p, Origin = CFrame.new(0, s.Y * info.Y, 0), Size = Vector3.new(s.X, s.Y * info.H, s.Z) }
end

---------------------------------------------------------------- 헬멧
-- 둥근 껍데기 치수: 머리 너비 m, 껍데기 지름 d, 중심 높이 cy·앞뒤 cz
type HelmetDims = { hx: number, hy: number, hz: number, m: number, d: number, cy: number, cz: number, top: number }
local function helmetDims(a: Anchor, scale: number): HelmetDims
	local hs = a.Size
	local m = math.max(hs.X, hs.Z)
	local d = m * gv().HelmetScale * scale
	local cy = hs.Y * 0.34
	return { hx = hs.X, hy = hs.Y, hz = hs.Z, m = m, d = d, cy = cy, cz = hs.Z * 0.08, top = cy + d / 2 }
end

-- 껍데기 앞면의 z (높이 y에서). 장식을 껍데기 겉에 붙일 때
local function domeFront(h: HelmetDims, y: number): number
	local r = h.d / 2
	local dy = y - h.cy
	return h.cz - math.sqrt(math.max(r * r - dy * dy, r * r * 0.15))
end

local function dome(ctx: Ctx, a: Anchor, h: HelmetDims, color: Color3, material: Enum.Material): Part
	return aball(ctx, a, "HelmetDome", h.d, CFrame.new(0, h.cy, h.cz), color, material)
end

-- 1 가죽 모자: 둥근 껍데기 + 넓은 챙 + 꼭지
local function helmetLeather(ctx: Ctx, a: Anchor, s: SetStyle)
	local h = helmetDims(a, 1)
	dome(ctx, a, h, s.Main, s.MainMat)
	aring(ctx, a, "HelmetBrim", h.hy * 0.07, h.m * 1.3, h.hy * 0.2, s.Trim, s.TrimMat)
	aball(ctx, a, "HelmetKnob", h.m * 0.2, CFrame.new(0, h.top - h.m * 0.04, h.cz), s.Trim, s.TrimMat)
end

-- 2 해골 투구: 하얀 해골 + 까만 눈구멍(초록 눈빛) + 코 구멍 + 이마 위 이빨 줄
local function helmetBone(ctx: Ctx, a: Anchor, s: SetStyle)
	local h = helmetDims(a, 1.06)
	dome(ctx, a, h, s.Main, s.MainMat)
	local eyeY = h.cy + h.hy * 0.1
	for _, side in { -1, 1 } do
		local z = domeFront(h, eyeY)
		aball(ctx, a, "SkullSocket", h.m * 0.25, CFrame.new(side * h.m * 0.19, eyeY, z + h.m * 0.06), s.Accent, s.AccentMat)
		local pupil = aball(ctx, a, "SkullEye", h.m * 0.08, CFrame.new(side * h.m * 0.19, eyeY, z - h.m * 0.04), s.Gem, Enum.Material.Neon)
		if side == 1 then
			setGlow(pupil, s)
		end
	end
	local noseY = h.cy - h.hy * 0.04
	ap(ctx, a, "SkullNose", BLOCK, Vector3.new(h.m * 0.1, h.m * 0.1, h.m * 0.05), CFrame.new(0, noseY, domeFront(h, noseY) + h.m * 0.01) * CFrame.Angles(0, 0, math.pi / 4), s.Accent, s.AccentMat)
	-- 이빨 줄 (윗니가 이마를 덮는 모양)
	local teethY = h.hy * 0.19
	local tz = domeFront(h, teethY) - h.m * 0.01
	ap(ctx, a, "SkullJaw", BLOCK, Vector3.new(h.m * 0.56, h.hy * 0.07, h.m * 0.06), CFrame.new(0, teethY, tz + h.m * 0.02), s.Accent, s.AccentMat)
	for i = -2, 1 do
		ap(ctx, a, "SkullTooth", BLOCK, Vector3.new(h.m * 0.1, h.hy * 0.1, h.m * 0.06), CFrame.new((i + 0.5) * h.m * 0.13, teethY - h.hy * 0.01, tz), s.Main, s.MainMat)
	end
end

-- 3 케르베로스 늑대 두건: 털 두건 + 앞으로 나온 늑대 주둥이(빨간 눈·까만 코·송곳니) + 뾰족 귀 + 뒷목 털
local function helmetCerberus(ctx: Ctx, a: Anchor, s: SetStyle)
	local h = helmetDims(a, 1.05)
	dome(ctx, a, h, s.Main, s.MainMat)
	ap(ctx, a, "HoodBack", BLOCK, Vector3.new(h.m * 0.92, h.hy * 0.72, h.hz * 0.2), CFrame.new(0, -h.hy * 0.08, h.hz * 0.56), s.Main, s.MainMat)
	-- 주둥이 (이마 위로 앞으로)
	local snoutY = h.cy + h.hy * 0.14
	local snoutLen = h.hz * 0.44
	local snoutZ = domeFront(h, snoutY) - snoutLen * 0.3
	ap(ctx, a, "HoodSnout", BLOCK, Vector3.new(h.m * 0.36, h.hy * 0.22, snoutLen), CFrame.new(0, snoutY, snoutZ), s.Main, s.MainMat)
	local snoutFront = snoutZ - snoutLen / 2
	aball(ctx, a, "HoodNose", h.m * 0.13, CFrame.new(0, snoutY + h.hy * 0.06, snoutFront), C(25, 20, 22), Enum.Material.SmoothPlastic)
	for _, side in { -1, 1 } do
		local eyeY = snoutY + h.hy * 0.12
		local eye = aball(ctx, a, "HoodEye", h.m * 0.085, CFrame.new(side * h.m * 0.13, eyeY, domeFront(h, eyeY) - h.m * 0.03), s.Gem, Enum.Material.Neon)
		if side == 1 then
			setGlow(eye, s)
		end
		-- 송곳니 (주둥이 아래로)
		aspike(ctx, a, "HoodFang", CFrame.new(side * h.m * 0.12, snoutY - h.hy * 0.1, snoutFront + h.hz * 0.05) * POINT_DOWN * FACE_FRONT, h.hy * 0.17, h.m * 0.08, h.m * 0.05, s.Accent, s.AccentMat)
		-- 뾰족 귀
		aspike(ctx, a, "HoodEar", CFrame.new(side * h.m * 0.27, h.top - h.hy * 0.14, h.cz + h.hz * 0.04) * CFrame.Angles(0, 0, -side * 0.28) * FACE_FRONT, h.hy * 0.4, h.m * 0.24, h.m * 0.07, s.Main, s.MainMat)
	end
end

-- 4 사이클롭스 외눈 투구: 두꺼운 기운 가죽 + 이마의 큰 외눈 문양(주황 눈빛) + 짧은 뿔 + 덧댄 조각·바느질
local function helmetCyclops(ctx: Ctx, a: Anchor, s: SetStyle)
	local h = helmetDims(a, 1.1)
	local patch = s.Patch or lighten(s.Main, 0.15)
	dome(ctx, a, h, s.Main, s.MainMat)
	aring(ctx, a, "HelmetBrim", h.hy * 0.13, h.m * 1.3, h.hy * 0.18, s.Trim, s.TrimMat)
	for _, side in { -1, 1 } do
		ap(ctx, a, "HidePatch", BLOCK, Vector3.new(h.m * 0.07, h.hy * 0.32, h.m * 0.36), CFrame.new(side * h.d * 0.46, h.cy + h.hy * 0.06, h.cz + h.hz * 0.06) * CFrame.Angles(side * 0.22, 0, side * 0.12), patch, s.MainMat)
	end
	-- 정수리 바느질 줄
	ap(ctx, a, "HideSeam", BLOCK, Vector3.new(h.m * 0.05, h.hy * 0.05, h.d * 0.62), CFrame.new(0, h.top - h.hy * 0.03, h.cz + h.hz * 0.06), s.Accent, s.AccentMat)
	for i = -1, 1 do
		ap(ctx, a, "HideStitch", BLOCK, Vector3.new(h.m * 0.2, h.hy * 0.045, h.m * 0.04), CFrame.new(0, h.top - h.hy * 0.035, h.cz + h.hz * 0.06 + i * h.d * 0.2), s.Accent, s.AccentMat)
	end
	-- 큰 외눈
	local eyeY = h.cy + h.hy * 0.08
	local ez = domeFront(h, eyeY)
	aball(ctx, a, "CyclopsEyeWhite", h.m * 0.4, CFrame.new(0, eyeY, ez + h.m * 0.06), C(250, 248, 238), Enum.Material.SmoothPlastic)
	local iris = aball(ctx, a, "CyclopsIris", h.m * 0.23, CFrame.new(0, eyeY, ez - h.m * 0.07), s.Gem, Enum.Material.Neon)
	setGlow(iris, s)
	aball(ctx, a, "CyclopsPupil", h.m * 0.11, CFrame.new(0, eyeY, ez - h.m * 0.16), C(20, 15, 18), Enum.Material.SmoothPlastic)
	-- 짧은 뿔
	ap(ctx, a, "CyclopsHorn", CYLINDER, Vector3.new(h.hy * 0.22, h.m * 0.16, h.m * 0.16), CFrame.new(0, h.top + h.hy * 0.06, h.cz - h.hz * 0.08) * AXIS_Y, s.Trim, s.TrimMat)
	aball(ctx, a, "CyclopsHornTip", h.m * 0.11, CFrame.new(0, h.top + h.hy * 0.18, h.cz - h.hz * 0.08), s.Accent, Enum.Material.SmoothPlastic)
end

-- 5 바위 골렘 투구: 네모난 돌 상자 + 이마 돌판 + 볼 돌판 + 이끼 + 빛나는 금·핵
local function helmetGolem(ctx: Ctx, a: Anchor, s: SetStyle)
	local hs = a.Size
	local hx, hy, hz = hs.X, hs.Y, hs.Z
	local m = math.max(hx, hz)
	local boxY = hy * 0.42
	local box = Vector3.new(hx * 1.24, hy * 0.62, hz * 1.24)
	local boxZ = hz * 0.05
	local front = boxZ - box.Z / 2
	ap(ctx, a, "GolemBox", BLOCK, box, CFrame.new(0, boxY, boxZ) * CFrame.Angles(0, 0, 0.03), s.Main, s.MainMat)
	ap(ctx, a, "GolemBrow", BLOCK, Vector3.new(hx * 1.32, hy * 0.14, hz * 0.22), CFrame.new(0, boxY - box.Y / 2 + hy * 0.03, front + hz * 0.04), s.Trim, s.TrimMat)
	for _, side in { -1, 1 } do
		ap(ctx, a, "GolemCheek", BLOCK, Vector3.new(hx * 0.15, hy * 0.56, hz * 0.82), CFrame.new(side * hx * 0.63, -hy * 0.04, hz * 0.04) * CFrame.Angles(side * 0.05, 0, 0), s.Trim, s.TrimMat)
	end
	ap(ctx, a, "GolemMoss", BLOCK, Vector3.new(hx * 0.72, hy * 0.08, hz * 0.62), CFrame.new(hx * 0.12, boxY + box.Y / 2 + hy * 0.02, hz * 0.12), s.Accent, s.AccentMat)
	-- 빛나는 금 (앞면 지그재그)
	local cz = front - hz * 0.01
	ap(ctx, a, "GolemCrack", BLOCK, Vector3.new(m * 0.035, hy * 0.26, hz * 0.03), CFrame.new(-hx * 0.3, boxY + hy * 0.06, cz) * CFrame.Angles(0, 0, 0.5), s.Gem, Enum.Material.Neon)
	ap(ctx, a, "GolemCrack", BLOCK, Vector3.new(m * 0.035, hy * 0.2, hz * 0.03), CFrame.new(-hx * 0.4, boxY - hy * 0.08, cz) * CFrame.Angles(0, 0, -0.45), s.Gem, Enum.Material.Neon)
	ap(ctx, a, "GolemCrack", BLOCK, Vector3.new(m * 0.035, hy * 0.24, hz * 0.03), CFrame.new(hx * 0.34, boxY + hy * 0.02, cz) * CFrame.Angles(0, 0, -0.6), s.Gem, Enum.Material.Neon)
	-- 이마 핵
	local core = ap(ctx, a, "GolemCore", BLOCK, Vector3.new(m * 0.2, m * 0.2, m * 0.1), CFrame.new(0, boxY + hy * 0.04, front - m * 0.03) * CFrame.Angles(0, 0, math.pi / 4), s.Gem, Enum.Material.Neon)
	setGlow(core, s)
end

-- 6 서리 거인 투구: 하얀 털 껍데기 + 폭신한 털 챙 + 푸른 빛 띠 + 얼음 수정 왕관 5개 + 눈송이
local function helmetFrost(ctx: Ctx, a: Anchor, s: SetStyle)
	local h = helmetDims(a, 1.04)
	dome(ctx, a, h, s.Main, s.MainMat)
	aring(ctx, a, "FurBrim", h.hy * 0.16, h.m * 1.32, h.hy * 0.19, lighten(s.Main, 0.3), s.MainMat)
	local band = aring(ctx, a, "FrostBand", h.hy * 0.045, h.m * 1.35, h.hy * 0.28, s.Gem, Enum.Material.Neon)
	setGlow(band, s)
	setParticles(band, s, -1.2)
	local r = h.d / 2
	for k = -2, 2 do
		local theta = k * 0.5
		local len = h.hy * (if k == 0 then 0.62 elseif math.abs(k) == 1 then 0.46 else 0.32)
		local base = CFrame.new(math.sin(theta) * r * 0.62, h.cy + r * 0.62, h.cz - math.cos(theta) * r * 0.62)
			* CFrame.Angles(-math.cos(theta) * 0.35, 0, -math.sin(theta) * 0.45)
		acrystal(ctx, a, "IceCrown", base, len, h.m * 0.12, s.Trim, s.TrimMat, s.Accent, s.AccentMat)
	end
end

-- 7 베헤모스 뿔 투구: 검붉은 비늘 껍데기 + 용암 이마 띠 + 화난 불빛 눈 + 정수리 가시 줄 + 양옆 크게 휜 뿔 + 불티
local function helmetBehemoth(ctx: Ctx, a: Anchor, s: SetStyle)
	local h = helmetDims(a, 1.05)
	dome(ctx, a, h, s.Main, s.MainMat)
	aring(ctx, a, "LavaBrow", h.hy * 0.12, h.m * 1.26, h.hy * 0.22, s.Trim, s.TrimMat)
	local eyeY = h.hy * 0.33
	local glowEye: Part? = nil
	for _, side in { -1, 1 } do
		local eye = ap(ctx, a, "EmberEye", BLOCK, Vector3.new(h.m * 0.22, h.hy * 0.045, h.m * 0.05), CFrame.new(side * h.m * 0.17, eyeY, domeFront(h, eyeY) - h.m * 0.01) * CFrame.Angles(0, 0, side * 0.28), s.Gem, Enum.Material.Neon)
		glowEye = glowEye or eye
		-- 큰 뿔: 옆으로 나가다 위·앞으로 휜다
		ahorn(ctx, a, "BehemothHorn", CFrame.new(side * h.hx * 0.5, h.cy + h.hy * 0.04, h.cz) * CFrame.Angles(0, 0, -side * 1.25), h.hy * 1.15, h.m * 0.27, 4, CFrame.Angles(-0.1, 0, side * 0.42), s.Accent, s.AccentMat)
	end
	if glowEye then
		setGlow(glowEye, s)
		setParticles(glowEye, s, 2)
	end
	-- 정수리 가시 줄 (옆에서 보이는 삼각형)
	local r = h.d / 2
	for i, f in { -0.45, 0, 0.45 } do
		local y = h.cy + math.sqrt(math.max(r * r - (f * r) ^ 2, 0)) - h.hy * 0.04
		local len = h.hy * (if i == 2 then 0.36 else 0.27)
		aspike(ctx, a, "BehemothRidge", CFrame.new(0, y, h.cz + f * r) * CFrame.Angles(f * 0.6, 0, 0), len, h.m * 0.24, h.m * 0.06, s.Trim, Enum.Material.Slate)
	end
end

local HELMETS: { [string]: (Ctx, Anchor, SetStyle) -> () } = {
	Leather = helmetLeather,
	Bone = helmetBone,
	Cerberus = helmetCerberus,
	Cyclops = helmetCyclops,
	Golem = helmetGolem,
	Frost = helmetFrost,
	Behemoth = helmetBehemoth,
}

local function buildHelmet(ctx: Ctx, def: EquipmentDef)
	local a = headAnchor(ctx)
	if not a then
		return
	end
	local builder = HELMETS[def.Set or "Leather"] or helmetLeather
	builder(ctx, a, setStyle(def))
end

---------------------------------------------------------------- 갑옷
type Torso = {
	A: Anchor,
	Belt: Anchor?,
	Arms: { [number]: Anchor }, -- [-1] 왼팔(바깥 -X), [1] 오른팔
	tx: number,
	ty: number,
	tz: number,
	depth: number, -- 덮개 앞뒤 두께
	front: number, -- 덮개 앞면 z (음수)
	plateT: number,
}

local function torsoInfo(ctx: Ctx, setId: string): Torso?
	local a = torsoAnchor(ctx)
	if not a then
		return nil
	end
	local t = a.Size
	local bulk = setShape(setId).Bulk
	local depth = t.Z * gv().ArmorDepth * bulk
	local arms: { [number]: Anchor } = {}
	local left = limbAnchor(ctx, "Left", "UpperArm")
	local right = limbAnchor(ctx, "Right", "UpperArm")
	if left then
		arms[-1] = left
	end
	if right then
		arms[1] = right
	end
	return {
		A = a, Belt = beltAnchor(ctx), Arms = arms,
		tx = t.X, ty = t.Y, tz = t.Z, depth = depth, front = -depth / 2, plateT = t.Z * gv().PlateThickness,
	}
end

-- 몸통 덮개 (세트 Bulk만큼 크게)
local function armorBody(ctx: Ctx, T: Torso, setId: string, color: Color3, material: Enum.Material, alpha: number?): Part
	local bulk = setShape(setId).Bulk
	return ap(ctx, T.A, "ArmorBody", BLOCK, Vector3.new(T.tx * gv().Padding * bulk, T.ty * 0.9, T.depth), CFrame.new(0, -T.ty * 0.03, 0), color, material, alpha)
end

-- 허리띠 + 버클 자리 (버클은 세트마다). 반환: 띠 높이, 띠 앞면 z
local function armorBelt(ctx: Ctx, T: Torso, bulk: number, color: Color3, material: Enum.Material): (number, number)
	local b = T.Belt
	if not b then
		return 0, 0
	end
	local l = b.Size
	local h = l.Y * 0.55
	local d = l.Z * gv().ArmorDepth * 1.03 * bulk
	ap(ctx, b, "Belt", BLOCK, Vector3.new(l.X * gv().Padding * 1.02 * bulk, h, d), CFrame.identity, color, material)
	return h, -d / 2
end

-- 어깨 공 (팔 굵기 × scale). 반환: 팔 구역·공 지름·높이 (없으면 nil)
local function shoulderBall(ctx: Ctx, T: Torso, side: number, scale: number, color: Color3, material: Enum.Material): (Anchor?, number, number)
	local arm = T.Arms[side]
	if not arm then
		return nil, 0, 0
	end
	local s = arm.Size
	local d = math.max(s.X, s.Z) * scale
	local y = s.Y * 0.3
	aball(ctx, arm, "Pauldron", d, CFrame.new(side * s.X * 0.12, y, 0), color, material)
	return arm, d, y
end

-- 1 가죽 조끼: 덮개 + 여밈 줄 + 단추 두 개 + 허리띠
local function armorLeather(ctx: Ctx, T: Torso, s: SetStyle)
	armorBody(ctx, T, "Leather", s.Main, s.MainMat)
	ap(ctx, T.A, "VestSeam", BLOCK, Vector3.new(T.tx * 0.05, T.ty * 0.84, T.tz * 0.04), CFrame.new(0, -T.ty * 0.03, T.front - T.tz * 0.01), s.Trim, s.TrimMat)
	for _, y in { 0.15, -0.15 } do
		aball(ctx, T.A, "VestButton", T.tx * 0.08, CFrame.new(T.tx * 0.07, T.ty * y, T.front), s.Accent, s.AccentMat)
	end
	local h, bz = armorBelt(ctx, T, 1, s.Trim, s.TrimMat)
	if T.Belt and h > 0 then
		ap(ctx, T.Belt, "Buckle", BLOCK, Vector3.new(T.Belt.Size.X * 0.16, h * 0.9, T.tz * 0.06), CFrame.new(0, 0, bz - T.tz * 0.03), s.Accent, s.AccentMat)
	end
end

-- 2 갈비뼈 갑옷: 짙은 가죽 바탕 + 앞 가슴뼈·갈비뼈 4쌍 + 등뼈 + 어깨 위 뼈다귀 + 해골 버클
local function armorBone(ctx: Ctx, T: Torso, s: SetStyle)
	armorBody(ctx, T, "Bone", s.Trim, s.TrimMat)
	local z = T.front - T.plateT / 2
	ap(ctx, T.A, "Sternum", BLOCK, Vector3.new(T.tx * 0.1, T.ty * 0.62, T.plateT), CFrame.new(0, T.ty * 0.05, z), s.Main, s.MainMat)
	for i = 1, 4 do
		local y = T.ty * (0.27 - (i - 1) * 0.145)
		local len = T.tx * (0.36 - i * 0.02)
		for _, side in { -1, 1 } do
			ap(ctx, T.A, "Rib", BLOCK, Vector3.new(len, T.ty * 0.065, T.plateT * 0.8), CFrame.new(side * (T.tx * 0.05 + len / 2), y, z + T.plateT * 0.1) * CFrame.Angles(0, 0, -side * 0.3), s.Main, s.MainMat)
		end
	end
	for i = 1, 4 do
		aball(ctx, T.A, "Spine", T.tx * 0.12, CFrame.new(0, T.ty * (0.32 - (i - 1) * 0.2), T.depth / 2), s.Main, s.MainMat)
	end
	-- 어깨 위에 가로놓인 뼈다귀 (앞뒤로)
	for _, side in { -1, 1 } do
		local x, y = side * T.tx * 0.36, T.ty * 0.47
		ap(ctx, T.A, "ShoulderBone", CYLINDER, Vector3.new(T.depth * 1.02, T.tx * 0.09, T.tx * 0.09), CFrame.new(x, y, 0) * AXIS_Z, s.Main, s.MainMat)
		for _, e in { -1, 1 } do
			aball(ctx, T.A, "ShoulderBoneEnd", T.tx * 0.13, CFrame.new(x, y, e * T.depth * 0.52), s.Main, s.MainMat)
		end
	end
	local h, bz = armorBelt(ctx, T, 1, darken(s.Trim, 0.2), s.TrimMat)
	if T.Belt and h > 0 then
		local sk = h * 1.15
		aball(ctx, T.Belt, "SkullBuckle", sk, CFrame.new(0, 0, bz - sk * 0.2), s.Main, s.MainMat)
		for _, side in { -1, 1 } do
			aball(ctx, T.Belt, "SkullBuckleEye", sk * 0.3, CFrame.new(side * sk * 0.18, sk * 0.08, bz - sk * 0.58), s.Accent, s.AccentMat)
		end
	end
end

-- 3 케르베로스 가죽갑옷: 짙은 털 + 폭신한 털 목도리 + X자 가죽 끈 + 목도리에 매단 송곳니 + 송곳니 박힌 털 어깨
local function armorCerberus(ctx: Ctx, T: Torso, s: SetStyle)
	armorBody(ctx, T, "Cerberus", s.Main, s.MainMat)
	ap(ctx, T.A, "FurCollar", CYLINDER, Vector3.new(T.ty * 0.18, T.tx * 0.78, T.tx * 0.78), CFrame.new(0, T.ty * 0.44, 0) * AXIS_Y, lighten(s.Main, 0.15), s.MainMat)
	local zs = T.front - T.plateT * 0.25
	for _, side in { -1, 1 } do
		asegment(ctx, T.A, "Harness", Vector3.new(side * T.tx * 0.3, T.ty * 0.42, zs), Vector3.new(-side * T.tx * 0.36, -T.ty * 0.4, zs), T.tx * 0.1, T.plateT * 0.5, s.Trim, s.TrimMat)
	end
	-- 목도리 앞 송곳니 5개
	for i = -2, 2 do
		local len = T.ty * (if i == 0 then 0.2 else 0.14)
		aspike(ctx, T.A, "CollarFang", CFrame.new(i * T.tx * 0.11, T.ty * 0.37, T.front - T.plateT * 0.6) * POINT_DOWN * FACE_FRONT, len, T.tx * 0.075, T.plateT * 0.45, s.Accent, s.AccentMat)
	end
	for _, side in { -1, 1 } do
		local arm, d, y = shoulderBall(ctx, T, side, 1.6, s.Main, s.MainMat)
		if arm then
			for _, f in { -0.2, 0.2 } do
				aspike(ctx, arm, "ShoulderFang", CFrame.new(side * arm.Size.X * 0.2, y + d * 0.36, f * d) * CFrame.Angles(0, 0, -side * 0.55) * FACE_FRONT, d * 0.45, d * 0.2, d * 0.08, s.Accent, s.AccentMat)
			end
		end
	end
	local h, bz = armorBelt(ctx, T, 1.04, s.Trim, s.TrimMat)
	if T.Belt and h > 0 then
		aspike(ctx, T.Belt, "BeltFang", CFrame.new(0, h * 0.3, bz - T.tz * 0.03) * POINT_DOWN * FACE_FRONT, h * 1.3, h * 0.7, T.tz * 0.05, s.Accent, s.AccentMat)
	end
end

-- 4 사이클롭스 거대가죽갑옷: 두툼하게 큰 몸통 + 덧댄 가죽 조각(X 바느질) + 아주 큰 둥근 어깨 + 굵은 끈 허리띠 + 둥근 뼈 버클
local function armorCyclops(ctx: Ctx, T: Torso, s: SetStyle)
	local patch = s.Patch or lighten(s.Main, 0.15)
	armorBody(ctx, T, "Cyclops", s.Main, s.MainMat)
	local z = T.front - T.plateT * 0.3
	for i, info in { { -0.2, 0.16, 0.12 }, { 0.22, -0.12, -0.15 } } do
		local x, y, rot = T.tx * info[1], T.ty * info[2], info[3]
		local w = T.tx * (if i == 1 then 0.36 else 0.3)
		ap(ctx, T.A, "HidePatch", BLOCK, Vector3.new(w, w * 0.85, T.plateT * 0.6), CFrame.new(x, y, z) * CFrame.Angles(0, 0, rot), patch, s.MainMat)
		for _, cross in { 0.75, -0.75 } do
			ap(ctx, T.A, "HideStitch", BLOCK, Vector3.new(w * 0.5, T.ty * 0.035, T.plateT * 0.3), CFrame.new(x, y, z - T.plateT * 0.32) * CFrame.Angles(0, 0, rot + cross), s.Accent, s.AccentMat)
		end
	end
	for _, side in { -1, 1 } do
		local arm, d, y = shoulderBall(ctx, T, side, 1.95, s.Main, s.MainMat)
		if arm then
			aring(ctx, arm, "PauldronRim", arm.Size.Y * 0.1, d * 0.98, y - d * 0.2, s.Trim, s.TrimMat)
			ap(ctx, arm, "PauldronPatch", BLOCK, Vector3.new(d * 0.1, d * 0.34, d * 0.4), CFrame.new(side * (arm.Size.X * 0.12 + d * 0.46), y + d * 0.06, 0) * CFrame.Angles(0.2, 0, 0), patch, s.MainMat)
		end
	end
	local h, bz = armorBelt(ctx, T, 1.14, s.Trim, s.TrimMat)
	if T.Belt and h > 0 then
		ap(ctx, T.Belt, "BoneBuckle", CYLINDER, Vector3.new(T.tz * 0.08, h * 1.25, h * 1.25), CFrame.new(0, 0, bz - T.tz * 0.03) * AXIS_Z, s.Accent, Enum.Material.SmoothPlastic)
	end
end

-- 5 바위 골렘 갑옷: 돌 몸통 + 가슴 돌판 4장 + 가운데 빛나는 핵 + 핵에서 뻗은 금 + 어깨 바위(이끼) + 돌 허리띠
local function armorGolem(ctx: Ctx, T: Torso, s: SetStyle)
	armorBody(ctx, T, "Golem", darken(s.Main, 0.15), s.MainMat)
	local slabT = T.plateT * 1.3
	local z = T.front - slabT / 2
	for i, info in { { -0.21, 0.22, 0.05 }, { 0.21, 0.24, -0.04 }, { -0.2, -0.14, -0.06 }, { 0.22, -0.12, 0.07 } } do
		ap(ctx, T.A, "StoneSlab", BLOCK, Vector3.new(T.tx * 0.38, T.ty * 0.32, slabT), CFrame.new(T.tx * info[1], T.ty * info[2], z) * CFrame.Angles(0, 0, info[3]), if i % 2 == 0 then s.Main else lighten(s.Main, 0.08), s.MainMat)
	end
	local coreZ = T.front - slabT - T.tz * 0.03
	local core = ap(ctx, T.A, "GolemCore", BLOCK, Vector3.new(T.tx * 0.17, T.tx * 0.17, T.tz * 0.12), CFrame.new(0, T.ty * 0.05, coreZ) * CFrame.Angles(0, 0, math.pi / 4), s.Gem, Enum.Material.Neon)
	setGlow(core, s)
	for _, angle in { 0.6, 2.5, 4.2 } do
		local len = T.ty * 0.26
		local dir = Vector3.new(-math.sin(angle), math.cos(angle), 0)
		ap(ctx, T.A, "GolemCrack", BLOCK, Vector3.new(T.tx * 0.03, len, T.tz * 0.03), CFrame.new(Vector3.new(0, T.ty * 0.05, T.front - slabT - T.tz * 0.005) + dir * (len / 2 + T.tx * 0.06)) * CFrame.Angles(0, 0, angle), s.Gem, Enum.Material.Neon)
	end
	for _, side in { -1, 1 } do
		local arm = T.Arms[side]
		if arm then
			local a = arm.Size
			local d = math.max(a.X, a.Z) * 1.65
			local y = a.Y * 0.3
			ap(ctx, arm, "Boulder", BLOCK, Vector3.new(d, d * 0.8, d), CFrame.new(side * a.X * 0.15, y, 0) * CFrame.Angles(0.25, side * 0.5, side * 0.15), s.Main, s.MainMat)
			ap(ctx, arm, "BoulderMoss", BLOCK, Vector3.new(d * 0.62, d * 0.14, d * 0.6), CFrame.new(side * a.X * 0.15, y + d * 0.44, 0) * CFrame.Angles(0, side * 0.5, 0), s.Accent, s.AccentMat)
		end
	end
	armorBelt(ctx, T, 1.12, s.Trim, s.TrimMat)
end

-- 6 서리 거인 갑옷: 하얀 털 + 반투명 얼음 가슴판 + 털 목도리 + 푸른 빛 보석(눈송이) + 어깨마다 얼음 수정 3개 + 얼음 띠
local function armorFrost(ctx: Ctx, T: Torso, s: SetStyle)
	armorBody(ctx, T, "Frost", s.Main, s.MainMat)
	ap(ctx, T.A, "IcePlate", BLOCK, Vector3.new(T.tx * 0.8, T.ty * 0.58, T.plateT), CFrame.new(0, T.ty * 0.08, T.front - T.plateT / 2), s.Trim, s.TrimMat, 0.2)
	ap(ctx, T.A, "FurCollar", CYLINDER, Vector3.new(T.ty * 0.2, T.tx * 0.8, T.tx * 0.8), CFrame.new(0, T.ty * 0.45, 0) * AXIS_Y, lighten(s.Main, 0.4), s.MainMat)
	local g = ap(ctx, T.A, "FrostGem", BLOCK, Vector3.new(T.tx * 0.16, T.tx * 0.16, T.plateT * 0.8), CFrame.new(0, T.ty * 0.04, T.front - T.plateT * 1.2) * CFrame.Angles(0, 0, math.pi / 4), s.Gem, Enum.Material.Neon)
	setGlow(g, s)
	setParticles(g, s, -1.2)
	for _, side in { -1, 1 } do
		local arm, d, y = shoulderBall(ctx, T, side, 1.6, lighten(s.Main, 0.2), s.MainMat)
		if arm then
			for k, len in { 0.75, 0.55, 0.45 } do
				local tilt = 0.15 + (k - 1) * 0.35
				local zoff = (if k == 3 then 0.22 elseif k == 2 then -0.22 else 0) * d
				acrystal(ctx, arm, "ShoulderIce", CFrame.new(side * (arm.Size.X * 0.12 + (k - 1) * d * 0.12), y + d * 0.28, zoff) * CFrame.Angles(0, 0, -side * tilt), d * len, d * 0.2, s.Trim, s.TrimMat, s.Accent, s.AccentMat)
			end
		end
	end
	armorBelt(ctx, T, 1.05, s.Trim, s.TrimMat)
end

-- 7 베헤모스 비늘 갑옷: 검붉은 비늘 몸통 + 가슴 비늘 2줄 + 용암 가운데 줄 + 불빛 핵(불티) + 휜 뿔 달린 어깨 + 등 가시 3개
local function armorBehemoth(ctx: Ctx, T: Torso, s: SetStyle)
	armorBody(ctx, T, "Behemoth", s.Main, s.MainMat)
	local z = T.front - T.plateT * 0.4
	for row, y in { 0.24, 0.04 } do
		for i = -1, 1 do
			if not (row == 2 and i == 0) then
				local sz = T.tx * 0.2
				ap(ctx, T.A, "Scale", BLOCK, Vector3.new(sz, sz, T.plateT * 0.8), CFrame.new(i * T.tx * 0.25, T.ty * y, z) * CFrame.Angles(0, 0, math.pi / 4), lighten(s.Main, 0.12), s.MainMat)
			end
		end
	end
	ap(ctx, T.A, "LavaSeam", BLOCK, Vector3.new(T.tx * 0.08, T.ty * 0.8, T.plateT * 0.5), CFrame.new(0, -T.ty * 0.02, T.front - T.plateT * 0.15), s.Trim, s.TrimMat)
	local core = ap(ctx, T.A, "EmberCore", BALL, Vector3.new(T.tx * 0.17, T.tx * 0.17, T.tx * 0.17), CFrame.new(0, -T.ty * 0.02, T.front - T.plateT * 0.6), s.Gem, Enum.Material.Neon)
	setGlow(core, s)
	setParticles(core, s, 2)
	for _, side in { -1, 1 } do
		local arm, d, y = shoulderBall(ctx, T, side, 1.85, s.Main, s.MainMat)
		if arm then
			aring(ctx, arm, "PauldronRim", arm.Size.Y * 0.09, d * 0.98, y - d * 0.2, s.Trim, s.TrimMat)
			ahorn(ctx, arm, "ShoulderHorn", CFrame.new(side * (arm.Size.X * 0.12 + d * 0.15), y + d * 0.35, 0) * CFrame.Angles(0, 0, -side * 0.6), d * 0.75, d * 0.24, 3, CFrame.Angles(0, 0, side * 0.35), s.Accent, s.AccentMat)
		end
	end
	for i = 1, 3 do
		aspike(ctx, T.A, "BackSpike", CFrame.new(0, T.ty * (0.3 - (i - 1) * 0.26), T.depth / 2 - T.tz * 0.02) * CFrame.Angles(math.pi / 2 - 0.5, 0, 0), T.tz * (0.42 - i * 0.06), T.tx * 0.18, T.tx * 0.05, s.Trim, Enum.Material.Slate)
	end
	local h, bz = armorBelt(ctx, T, 1.06, s.Trim, s.TrimMat)
	if T.Belt and h > 0 then
		ap(ctx, T.Belt, "EmberBuckle", BLOCK, Vector3.new(h * 0.8, h * 0.8, T.tz * 0.06), CFrame.new(0, 0, bz - T.tz * 0.03) * CFrame.Angles(0, 0, math.pi / 4), s.Gem, Enum.Material.Neon)
	end
end

local ARMORS: { [string]: (Ctx, Torso, SetStyle) -> () } = {
	Leather = armorLeather,
	Bone = armorBone,
	Cerberus = armorCerberus,
	Cyclops = armorCyclops,
	Golem = armorGolem,
	Frost = armorFrost,
	Behemoth = armorBehemoth,
}

local function buildArmor(ctx: Ctx, def: EquipmentDef)
	local setId = def.Set or "Leather"
	local T = torsoInfo(ctx, setId)
	if not T then
		return
	end
	local builder = ARMORS[setId] or armorLeather
	builder(ctx, T, setStyle(def))
end

---------------------------------------------------------------- 장화
-- 발 덮개 (발 크기 × scale). 반환: 덮개 크기, 덮개 중심
local function bootCover(ctx: Ctx, foot: Anchor, scale: number, color: Color3, material: Enum.Material): (Vector3, CFrame)
	local f = foot.Size
	local pad = gv().Padding
	local cover = Vector3.new(f.X * pad * 1.08 * scale, f.Y * 1.5 * scale, f.Z * pad * 1.1 * scale)
	local center = CFrame.new(0, f.Y * 0.28 * scale, -f.Z * 0.06)
	ap(ctx, foot, "Boot", BLOCK, cover, center, color, material)
	return cover, center
end

local function bootSole(ctx: Ctx, foot: Anchor, cover: Vector3, center: CFrame, thick: number, color: Color3, material: Enum.Material)
	local h = foot.Size.Y * 0.3 * thick
	ap(ctx, foot, "BootSole", BLOCK, Vector3.new(cover.X * 1.04, h, cover.Z * 1.04), center * CFrame.new(0, -cover.Y / 2, 0), color, material)
end

-- 정강이 목 고리. 반환: 지름
local function bootCuff(ctx: Ctx, shin: Anchor, scale: number, color: Color3, material: Enum.Material): number
	local l = shin.Size
	local d = math.max(l.X, l.Z) * gv().CuffScale * scale
	aring(ctx, shin, "BootCuff", l.Y * 0.35, d, -l.Y * 0.3, color, material)
	return d
end

local function buildBoots(ctx: Ctx, def: EquipmentDef)
	local s = setStyle(def)
	local setId = def.Set or "Leather"
	for i, side in { "Left", "Right" } do
		local outward = if i == 1 then -1 else 1
		local foot = limbAnchor(ctx, side, "Foot")
		local shin = limbAnchor(ctx, side, "LowerLeg")
		if setId == "Bone" then
			-- 가죽 장화 + 뼈 앞코 + 정강이 앞 뼈(양끝 동그라미) + 묶은 끈 2개
			if foot then
				local cover, center = bootCover(ctx, foot, 1, s.Trim, s.TrimMat)
				bootSole(ctx, foot, cover, center, 1, darken(s.Trim, 0.3), s.TrimMat)
				ap(ctx, foot, "BoneToe", BLOCK, Vector3.new(cover.X * 1.04, cover.Y * 0.7, foot.Size.Z * 0.26), center * CFrame.new(0, -cover.Y * 0.1, -cover.Z / 2 + foot.Size.Z * 0.1), s.Main, s.MainMat)
			end
			if shin then
				local l = shin.Size
				local d = bootCuff(ctx, shin, 1, s.Trim, s.TrimMat)
				local z = -math.max(d / 2, l.Z * 0.55)
				ap(ctx, shin, "ShinBone", CYLINDER, Vector3.new(l.Y * 0.72, l.X * 0.24, l.X * 0.24), CFrame.new(0, 0, z) * AXIS_Y, s.Main, s.MainMat)
				for _, e in { -1, 1 } do
					for _, k in { -1, 1 } do
						aball(ctx, shin, "ShinBoneEnd", l.X * 0.24, CFrame.new(k * l.X * 0.1, e * l.Y * 0.36, z), s.Main, s.MainMat)
					end
				end
				for _, y in { 0.18, -0.12 } do
					aring(ctx, shin, "BoneStrap", l.Y * 0.05, math.max(l.X, l.Z) * 1.28, l.Y * y, darken(s.Trim, 0.3), s.TrimMat)
				end
			end
		elseif setId == "Cerberus" then
			-- 털 장화 + 아주 폭신한 털 목 + 앞코 하얀 발톱 2개
			if foot then
				local cover, center = bootCover(ctx, foot, 1.04, s.Main, s.MainMat)
				bootSole(ctx, foot, cover, center, 1, s.Trim, s.TrimMat)
				for _, k in { -0.22, 0.22 } do
					aspike(ctx, foot, "ToeClaw", center * CFrame.new(k * cover.X, -cover.Y * 0.32, -cover.Z / 2 + foot.Size.Z * 0.02) * CFrame.Angles(-math.pi / 2, 0, 0) * FACE_FRONT, foot.Size.Z * 0.3, cover.X * 0.22, cover.Y * 0.12, s.Accent, s.AccentMat)
				end
			end
			if shin then
				local d = bootCuff(ctx, shin, 1.05, s.Main, s.MainMat)
				aring(ctx, shin, "FurCuff", shin.Size.Y * 0.16, d * 1.22, -shin.Size.Y * 0.08, lighten(s.Main, 0.15), s.MainMat)
			end
		elseif setId == "Cyclops" then
			-- 크고 투박한 장화 + 두꺼운 밑창 + 감은 가죽 끈 2줄 + 앞코 덧댄 조각
			if foot then
				local cover, center = bootCover(ctx, foot, 1.18, s.Main, s.MainMat)
				bootSole(ctx, foot, cover, center, 1.6, s.Trim, s.TrimMat)
				ap(ctx, foot, "ToePatch", BLOCK, Vector3.new(cover.X * 0.6, cover.Y * 0.5, foot.Size.Z * 0.1), center * CFrame.new(0, cover.Y * 0.05, -cover.Z / 2) * CFrame.Angles(0, 0, 0.15), s.Patch or lighten(s.Main, 0.15), s.MainMat)
			end
			if shin then
				local d = bootCuff(ctx, shin, 1.15, s.Main, s.MainMat)
				for _, y in { -0.38, -0.2 } do
					aring(ctx, shin, "HideWrap", shin.Size.Y * 0.06, d * 1.06, shin.Size.Y * y, s.Trim, s.TrimMat)
				end
			end
		elseif setId == "Golem" then
			-- 네모난 돌 장화 + 두꺼운 돌 밑창 + 정강이 돌판(빛나는 금)
			if foot then
				local cover, center = bootCover(ctx, foot, 1.15, s.Main, s.MainMat)
				bootSole(ctx, foot, cover, center, 1.8, s.Trim, s.TrimMat)
			end
			if shin then
				local l = shin.Size
				local d = bootCuff(ctx, shin, 1.12, s.Trim, s.TrimMat)
				local z = -math.max(d / 2, l.Z * 0.55)
				ap(ctx, shin, "ShinSlab", BLOCK, Vector3.new(l.X * 0.85, l.Y * 0.62, l.Z * 0.22), CFrame.new(0, -l.Y * 0.02, z) * CFrame.Angles(0.06, 0, outward * 0.04), s.Main, s.MainMat)
				ap(ctx, shin, "ShinCrack", BLOCK, Vector3.new(l.X * 0.06, l.Y * 0.36, l.Z * 0.04), CFrame.new(l.X * 0.08, 0, z - l.Z * 0.12) * CFrame.Angles(0, 0, 0.35), s.Gem, Enum.Material.Neon)
			end
		elseif setId == "Frost" then
			-- 하얀 털 장화 + 아주 큰 털 목 + 얼음 밑창 + 정강이 앞 얼음 가시 2개
			if foot then
				local cover, center = bootCover(ctx, foot, 1.06, s.Main, s.MainMat)
				bootSole(ctx, foot, cover, center, 1.2, s.Trim, s.TrimMat)
			end
			if shin then
				local l = shin.Size
				local d = bootCuff(ctx, shin, 1.08, s.Main, s.MainMat)
				aring(ctx, shin, "FurCuff", l.Y * 0.18, d * 1.25, -l.Y * 0.06, lighten(s.Main, 0.4), s.MainMat)
				for k, len in { 0.42, 0.3 } do
					acrystal(ctx, shin, "ShinIce", CFrame.new((k - 1.5) * l.X * 0.3, l.Y * 0.04, -d * 0.55) * CFrame.Angles(-0.55, 0, (k - 1.5) * 0.4), l.Y * len, l.X * 0.18, s.Trim, s.TrimMat, s.Accent, s.AccentMat)
				end
			end
		elseif setId == "Behemoth" then
			-- 비늘 장화 + 용암 밑창 + 앞코 상아 발톱 2개 + 정강이 뒤로 솟은 가시
			if foot then
				local cover, center = bootCover(ctx, foot, 1.08, s.Main, s.MainMat)
				bootSole(ctx, foot, cover, center, 1.3, s.Trim, s.TrimMat)
				for _, k in { -0.24, 0.24 } do
					aspike(ctx, foot, "ToeClaw", center * CFrame.new(k * cover.X, -cover.Y * 0.28, -cover.Z / 2 + foot.Size.Z * 0.02) * CFrame.Angles(-math.pi / 2 + 0.25, 0, 0) * FACE_FRONT, foot.Size.Z * 0.42, cover.X * 0.26, cover.Y * 0.14, s.Accent, s.AccentMat)
				end
			end
			if shin then
				local l = shin.Size
				local d = bootCuff(ctx, shin, 1.08, s.Main, s.MainMat)
				aring(ctx, shin, "LavaRim", l.Y * 0.07, d * 1.08, -l.Y * 0.11, s.Trim, s.TrimMat)
				aspike(ctx, shin, "ShinSpike", CFrame.new(outward * d * 0.3, -l.Y * 0.1, -d * 0.45) * CFrame.Angles(-0.35, 0, -outward * 0.35) * FACE_FRONT, l.Y * 0.42, l.X * 0.32, l.X * 0.1, s.Accent, s.AccentMat)
			end
		else
			-- 1 가죽 장화: 덮개 + 밑창 + 목 고리 + 목 테두리
			if foot then
				local cover, center = bootCover(ctx, foot, 1, s.Main, s.MainMat)
				bootSole(ctx, foot, cover, center, 1, s.Trim, s.TrimMat)
			end
			if shin then
				local d = bootCuff(ctx, shin, 1, s.Main, s.MainMat)
				aring(ctx, shin, "BootCuffRim", shin.Size.Y * 0.08, d * 1.08, -shin.Size.Y * 0.11, s.Trim, s.TrimMat)
			end
		end
	end
end

---------------------------------------------------------------- 장갑
-- 손 덮개 (손 크기 × scale). 반환: 덮개 크기
local function gloveCover(ctx: Ctx, hand: Anchor, scale: number, color: Color3, material: Enum.Material): Vector3
	local h = hand.Size
	local pad = gv().Padding
	local cover = Vector3.new(h.X * pad * 1.08 * scale, h.Y * 1.08 * scale, h.Z * pad * 1.08 * scale)
	ap(ctx, hand, "Glove", BLOCK, cover, CFrame.new(0, -h.Y * 0.03, 0), color, material)
	return cover
end

-- 아래팔 끝 목 고리. 반환: 지름
local function gloveCuff(ctx: Ctx, arm: Anchor, scale: number, color: Color3, material: Enum.Material): number
	local a = arm.Size
	local d = math.max(a.X, a.Z) * gv().CuffScale * scale
	aring(ctx, arm, "GloveCuff", a.Y * 0.28, d, -a.Y * 0.36, color, material)
	return d
end

-- 손등(바깥쪽)에서 바깥으로 뻗는 가시의 기준
local function outwardBase(outward: number, x: number, y: number, z: number): CFrame
	return CFrame.new(outward * x, y, z) * CFrame.Angles(0, 0, -outward * math.pi / 2) * FACE_FRONT
end

local function buildGloves(ctx: Ctx, def: EquipmentDef)
	local s = setStyle(def)
	local setId = def.Set or "Leather"
	for i, side in { "Left", "Right" } do
		local outward = if i == 1 then -1 else 1
		local hand = limbAnchor(ctx, side, "Hand")
		local arm = limbAnchor(ctx, side, "LowerArm")
		if setId == "Bone" then
			-- 가죽 장갑 + 손가락 마디 뼈 4개 + 아래팔 바깥쪽 뼈 두 줄
			if hand then
				local cover = gloveCover(ctx, hand, 1, s.Trim, s.TrimMat)
				for k = 0, 3 do
					aball(ctx, hand, "KnuckleBone", hand.Size.X * 0.32, CFrame.new(outward * cover.X * 0.32, -hand.Size.Y * 0.3, (k - 1.5) * cover.Z * 0.26), s.Main, s.MainMat)
				end
			end
			if arm then
				local d = gloveCuff(ctx, arm, 1, s.Trim, s.TrimMat)
				for _, k in { -0.2, 0.2 } do
					ap(ctx, arm, "ArmBone", CYLINDER, Vector3.new(arm.Size.Y * 0.6, arm.Size.X * 0.18, arm.Size.X * 0.18), CFrame.new(outward * d * 0.5, -arm.Size.Y * 0.12, k * arm.Size.Z) * AXIS_Y, s.Main, s.MainMat)
				end
			end
		elseif setId == "Cerberus" then
			-- 털 장갑 + 손끝 하얀 발톱 3개 + 털 목
			if hand then
				local cover = gloveCover(ctx, hand, 1.04, s.Main, s.MainMat)
				for k = -1, 1 do
					aspike(ctx, hand, "Claw", CFrame.new(outward * cover.X * 0.12, -hand.Size.Y * 0.03 - cover.Y / 2 + hand.Size.Y * 0.04, k * cover.Z * 0.3) * POINT_DOWN * FACE_FRONT, hand.Size.Y * 0.45, cover.Z * 0.2, cover.X * 0.18, s.Accent, s.AccentMat)
				end
			end
			if arm then
				local d = gloveCuff(ctx, arm, 1.05, s.Main, s.MainMat)
				aring(ctx, arm, "FurCuff", arm.Size.Y * 0.14, d * 1.2, -arm.Size.Y * 0.2, lighten(s.Main, 0.15), s.MainMat)
			end
		elseif setId == "Cyclops" then
			-- 커다란 가죽 벙어리장갑 + 두꺼운 감은 목 + 손등 덧댄 조각(X 바느질)
			if hand then
				local cover = gloveCover(ctx, hand, 1.22, s.Main, s.MainMat)
				local px = outward * cover.X / 2
				ap(ctx, hand, "HidePatch", BLOCK, Vector3.new(cover.X * 0.08, cover.Y * 0.45, cover.Z * 0.55), CFrame.new(px, 0, 0) * CFrame.Angles(0.2, 0, 0), s.Patch or lighten(s.Main, 0.15), s.MainMat)
				for _, cross in { 0.75, -0.75 } do
					ap(ctx, hand, "HideStitch", BLOCK, Vector3.new(cover.X * 0.05, cover.Y * 0.32, cover.Z * 0.05), CFrame.new(px + outward * cover.X * 0.05, 0, 0) * CFrame.Angles(cross, 0, 0), s.Accent, s.AccentMat)
				end
			end
			if arm then
				local d = gloveCuff(ctx, arm, 1.2, s.Main, s.MainMat)
				aring(ctx, arm, "HideWrap", arm.Size.Y * 0.07, d * 1.06, -arm.Size.Y * 0.28, s.Trim, s.TrimMat)
			end
		elseif setId == "Golem" then
			-- 커다란 돌 주먹 + 주먹 돌판 + 손등 빛나는 핵 + 아래팔 돌 토시
			if hand then
				local cover = gloveCover(ctx, hand, 1.35, s.Main, s.MainMat)
				ap(ctx, hand, "KnuckleSlab", BLOCK, Vector3.new(cover.X * 1.06, cover.Y * 0.3, cover.Z * 1.08), CFrame.new(0, -cover.Y * 0.32, 0), s.Trim, s.TrimMat)
				local core = ap(ctx, hand, "FistCore", BLOCK, Vector3.new(cover.Z * 0.1, cover.Z * 0.26, cover.Z * 0.26), CFrame.new(outward * cover.X * 0.52, cover.Y * 0.08, 0) * CFrame.Angles(math.pi / 4, 0, 0), s.Gem, Enum.Material.Neon)
				if i == 2 then
					setGlow(core, s)
				end
			end
			if arm then
				local a = arm.Size
				ap(ctx, arm, "StoneBracer", BLOCK, Vector3.new(a.X * 1.45, a.Y * 0.42, a.Z * 1.45), CFrame.new(0, -a.Y * 0.28, 0) * CFrame.Angles(0, 0.1 * outward, 0), s.Main, s.MainMat)
			end
		elseif setId == "Frost" then
			-- 하얀 털 장갑 + 얼음 주먹판 + 손등 얼음 가시 2개 + 폭신한 털 목
			if hand then
				local cover = gloveCover(ctx, hand, 1.06, s.Main, s.MainMat)
				ap(ctx, hand, "IceKnuckles", BLOCK, Vector3.new(cover.X * 1.06, hand.Size.Y * 0.28, cover.Z * 1.06), CFrame.new(0, -hand.Size.Y * 0.24, 0), s.Trim, s.TrimMat, 0.2)
				for k, len in { 0.5, 0.36 } do
					acrystal(ctx, hand, "HandIce", CFrame.new(outward * cover.X * 0.45, hand.Size.Y * 0.05, (k - 1.5) * cover.Z * 0.4) * CFrame.Angles(0, 0, -outward * (math.pi / 2 - 0.5)), hand.Size.Y * len, cover.Z * 0.16, s.Trim, s.TrimMat, s.Accent, s.AccentMat)
				end
			end
			if arm then
				local d = gloveCuff(ctx, arm, 1.05, s.Main, s.MainMat)
				aring(ctx, arm, "FurCuff", arm.Size.Y * 0.16, d * 1.25, -arm.Size.Y * 0.2, lighten(s.Main, 0.4), s.MainMat)
			end
		elseif setId == "Behemoth" then
			-- 비늘 건틀릿 + 주먹 상아 가시 3개 + 용암 목 + 손등 불빛
			if hand then
				local cover = gloveCover(ctx, hand, 1.1, s.Main, s.MainMat)
				for k = -1, 1 do
					aspike(ctx, hand, "KnuckleSpike", outwardBase(outward, cover.X * 0.45, -hand.Size.Y * 0.28, k * cover.Z * 0.3), hand.Size.X * 0.55, cover.Z * 0.22, cover.Z * 0.08, s.Accent, s.AccentMat)
				end
				local ember = ap(ctx, hand, "HandEmber", BLOCK, Vector3.new(cover.X * 0.06, cover.Z * 0.24, cover.Z * 0.24), CFrame.new(outward * cover.X * 0.5, hand.Size.Y * 0.12, 0) * CFrame.Angles(math.pi / 4, 0, 0), s.Gem, Enum.Material.Neon)
				if i == 2 then
					setGlow(ember, s)
				end
			end
			if arm then
				local d = gloveCuff(ctx, arm, 1.1, s.Main, s.MainMat)
				aring(ctx, arm, "LavaRim", arm.Size.Y * 0.08, d * 1.08, -arm.Size.Y * 0.2, s.Trim, s.TrimMat)
			end
		else
			-- 1 가죽 장갑: 덮개 + 목 고리
			if hand then
				gloveCover(ctx, hand, 1, s.Main, s.MainMat)
			end
			if arm then
				gloveCuff(ctx, arm, 1, s.Main, s.MainMat)
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
	local front = if ctx.ArmorSet then armorFrontDepth(tz, ctx.ArmorSet) else tz / 2
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
	local armorSet = ctx.ArmorSet
	local backZ = if armorSet then tz * gv().ArmorDepth * setShape(armorSet).Bulk / 2 else tz / 2
	local frontZ = if armorSet then armorFrontDepth(tz, armorSet) else tz / 2

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
		ArmorSet = if armorDef and armorDef.Slot == "Armor" then (armorDef.Set or "Leather") else nil,
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
