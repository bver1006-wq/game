--!strict
-- 차징(모으기) 연출 (클라이언트). 얼마나 모았는지와 강타 판정은 서버(ChargeService)가 정한다.
-- 활: 화면 아래 차징 게이지가 찬다 (다 차면 금색)
-- 나머지 도구·무기: 머리 위 뒤로 들어 올린 자세(PoseController.windUp)로, 도구에서 은은한 빛이 점점 커지며 깜빡이다가
--   다 모이면 깜빡임이 멈추고 선명한 테두리와 반짝임이 생긴다
-- 공통: 기운이 차오르는 소리, 주변에서 작은 마나 입자가 도구로 빨려 들어온다. 활은 시위를 당기는 자세(PoseController.bowDraw)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local PickaxeDefs = require(ReplicatedStorage.Shared.PickaxeDefs)
local Workspace = game:GetService("Workspace")

local HitFeelController = require(script.Parent.HitFeelController)
local PoseController = require(script.Parent.PoseController)
local UiKit = require(script.Parent.UiKit)

local localPlayer = Players.LocalPlayer

local ChargeController = {}

type Session = {
	Def: PickaxeDefs.PickaxeDef,
	Start: number,
	Holding: boolean, -- 자세를 잡았는지 (TapThreshold가 지난 뒤)
	Full: boolean,
	Light: PointLight?,
	Sparkles: ParticleEmitter?,
	Highlight: Highlight?,
	Anchor: Attachment?,
	Gather: BasePart?, -- 마나 입자가 모여드는 투명 공 (도구 가운데를 따라다닌다)
	GatherEmitter: ParticleEmitter?,
	Sound: Sound?,
}

local current: Session? = nil
local gaugeFrame: Frame
local gaugeFill: Frame

-- 들고 있는 Tool
local function heldTool(): Tool?
	local character = localPlayer.Character
	return character and character:FindFirstChildWhichIsA("Tool") or nil
end

-- 도구에서 보이는 부품들의 가운데 (빛을 둘 자리)
local function toolCenter(tool: Tool): (BasePart?, Vector3?)
	local handle = tool:FindFirstChild("Handle")
	local sum, count = Vector3.zero, 0
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			sum += d.Position
			count += 1
		end
	end
	if not handle or not handle:IsA("BasePart") then
		return nil, nil
	end
	return handle, if count > 0 then sum / count else handle.Position
end

-- 도구 빛을 만든다 (처음엔 꺼진 상태에서 점점 커진다)
local function startGlow(session: Session)
	local tool = heldTool()
	if not tool then
		return
	end
	local handle, center = toolCenter(tool)
	if not handle or not center then
		return
	end
	local anchor = Instance.new("Attachment")
	anchor.Name = "ChargeGlow"
	anchor.Parent = handle
	anchor.WorldPosition = center
	local light = Instance.new("PointLight")
	light.Color = Config.Charge.GlowColor
	light.Brightness = 0
	light.Range = 2
	light.Parent = anchor
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(Config.Charge.GlowColor)
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new(0.25, 0)
	sparkles.Lifetime = NumberRange.new(0.3, 0.6)
	sparkles.Speed = NumberRange.new(0.5, 1.5)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Rate = 0
	sparkles.Parent = anchor
	local highlight = Instance.new("Highlight")
	highlight.Adornee = tool
	highlight.FillColor = Config.Charge.GlowColor
	highlight.FillTransparency = 1
	highlight.OutlineColor = Config.Charge.FullColor
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = tool
	session.Anchor = anchor
	session.Light = light
	session.Sparkles = sparkles
	session.Highlight = highlight
end

-- 기운 모으기 시작: 차오르는 소리 + 주변에서 마나 입자가 빨려 들어오는 공
-- (ParticleEmitter 모양 Sphere + Inward: 공 표면에서 생겨 가운데로 날아든다)
local function startGather(session: Session)
	local gather = Instance.new("Part")
	gather.Name = "ChargeGather"
	gather.Shape = Enum.PartType.Ball
	gather.Size = Vector3.new(9, 9, 9)
	gather.Transparency = 1
	gather.Anchored = true
	gather.CanCollide = false
	gather.CanQuery = false
	gather.CanTouch = false
	gather.CastShadow = false
	gather.Parent = Workspace
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(120, 200, 255), Color3.fromRGB(200, 240, 255))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(0.7, 0.22), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new(0.2, 0.6)
	emitter.Lifetime = NumberRange.new(0.6, 0.7)
	emitter.Speed = NumberRange.new(6, 7)
	emitter.Shape = Enum.ParticleEmitterShape.Sphere
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	emitter.Rate = 0
	emitter.Parent = gather
	session.Gather = gather
	session.GatherEmitter = emitter

	local sound = Instance.new("Sound")
	sound.SoundId = Config.Sounds.ChargeUp
	sound.Volume = 0.35
	sound.PlaybackSpeed = 0.8
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	sound.Parent = root or Workspace
	sound:Play()
	session.Sound = sound
end

-- 다 모였을 때: 깜빡임이 멈추고 선명해진다 (+ 반짝 소리)
local function onFull(session: Session)
	session.Full = true
	local tool = heldTool()
	local center: Vector3? = nil
	if tool then
		local _, c = toolCenter(tool)
		center = c
	end
	HitFeelController.playSound(Config.Sounds.JudgmentPop, center, 1.7, 0.6)
	if session.GatherEmitter then
		session.GatherEmitter:Emit(25) -- 마지막으로 한 번 더 확 모인다
		session.GatherEmitter.Rate = 8
	end
	if session.Def.Kind == "Bow" then
		gaugeFill.BackgroundColor3 = UiKit.Colors.Gold
		return
	end
	if session.Light then
		session.Light.Brightness = 2.5
		session.Light.Range = 9
		session.Light.Color = Config.Charge.FullColor
	end
	if session.Highlight then
		session.Highlight.FillTransparency = 0.82
		session.Highlight.OutlineTransparency = 0
	end
	if session.Sparkles then
		session.Sparkles.Rate = 6
		session.Sparkles:Emit(20)
	end
end

-- 모으기 시작 (InputController가 누르는 순간 부른다)
function ChargeController.start(def: PickaxeDefs.PickaxeDef)
	ChargeController.stop()
	current = { Def = def, Start = os.clock(), Holding = false, Full = false, Light = nil, Sparkles = nil, Highlight = nil, Anchor = nil, Gather = nil, GatherEmitter = nil, Sound = nil }
	if def.Kind == "Bow" then
		gaugeFill.Size = UDim2.fromScale(0, 1)
		gaugeFill.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
		gaugeFrame.Visible = true
		local tool = heldTool()
		if tool then
			PoseController.bowDraw(tool) -- 활은 누르는 순간부터 시위를 당긴다
		end
	end
end

-- 모으기 끝 (놓을 때). 누르고 있던 시간과 모은 정도(0~1)를 돌려준다
function ChargeController.stop(): (number, number)
	local session = current
	current = nil
	gaugeFrame.Visible = false
	if not session then
		return 0, 0
	end
	if session.Anchor then
		local anchor = session.Anchor
		local light = session.Light
		if light then
			TweenService:Create(light, TweenInfo.new(0.2), { Brightness = 0 }):Play()
		end
		task.delay(0.25, function()
			anchor:Destroy()
		end)
	end
	if session.Highlight then
		session.Highlight:Destroy()
	end
	if session.Gather then
		local gather = session.Gather
		if session.GatherEmitter then
			session.GatherEmitter.Rate = 0
		end
		task.delay(0.8, function()
			gather:Destroy()
		end)
	end
	if session.Sound then
		session.Sound:Destroy()
	end
	PoseController.release() -- 휘두르기 애니메이션과 함께 자세가 내려온다 (활은 시위가 튕겨 돌아온다)
	local held = os.clock() - session.Start
	local ratio = if held < Config.Charge.TapThreshold then 0 else math.clamp(held / Config.Charge.Time, 0, 1)
	return held, ratio
end

-- 휘두르지 않고 취소 (도구를 내려놓음)
function ChargeController.cancel()
	ChargeController.stop()
end

-- 지금 모으는 중인지
function ChargeController.isCharging(): boolean
	return current ~= nil
end

-- 매 프레임: 게이지·빛 키우기
local function update()
	local session = current
	if not session then
		return
	end
	local held = os.clock() - session.Start
	local ratio = math.clamp(held / Config.Charge.Time, 0, 1)
	-- 짧게 누르는 것보다 길어지면 기운을 모으기 시작한다
	if not session.Holding and held >= Config.Charge.TapThreshold then
		session.Holding = true
		startGather(session)
		if session.Def.Kind ~= "Bow" then
			PoseController.windUp()
			startGlow(session)
		end
	end
	-- 마나 입자 공은 도구 가운데를 따라다니고, 모일수록 많아진다. 소리도 점점 높아진다
	if session.Gather then
		local tool = heldTool()
		if tool then
			local _, center = toolCenter(tool)
			if center then
				session.Gather.CFrame = CFrame.new(center)
			end
		end
		if not session.Full then
			if session.GatherEmitter then
				session.GatherEmitter.Rate = 10 + ratio * 50
			end
			if session.Sound then
				session.Sound.PlaybackSpeed = 0.8 + ratio * 0.5
			end
		end
	end
	if session.Def.Kind == "Bow" then
		gaugeFill.Size = UDim2.fromScale(ratio, 1)
	else
		if session.Holding and not session.Full then
			-- 은은하게 깜빡이며 점점 커진다
			local pulse = 0.75 + 0.25 * math.sin(held * 14)
			if session.Light then
				session.Light.Brightness = ratio * 2 * pulse
				session.Light.Range = 2 + ratio * 6
			end
			if session.Highlight then
				session.Highlight.FillTransparency = 1 - ratio * 0.25 * pulse
			end
			if session.Sparkles then
				session.Sparkles.Rate = ratio * 12
			end
		end
	end
	if ratio >= 1 and not session.Full then
		onFull(session)
	end
end

-- 클라이언트 시작 시 한 번 호출
function ChargeController.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ChargeGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 13
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	-- 활 차징 게이지: 빠른 칸 바로 위 가운데
	gaugeFrame = Instance.new("Frame")
	gaugeFrame.AnchorPoint = Vector2.new(0.5, 1)
	gaugeFrame.Position = UDim2.new(0.5, 0, 1, -100)
	gaugeFrame.Size = UDim2.fromOffset(180, 12)
	gaugeFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	gaugeFrame.BackgroundTransparency = 0.2
	gaugeFrame.BorderSizePixel = 0
	gaugeFrame.Visible = false
	gaugeFrame.Parent = gui
	UiKit.corner(gaugeFrame, 6)
	UiKit.stroke(gaugeFrame, Color3.new(0, 0, 0), 1.5)
	gaugeFill = Instance.new("Frame")
	gaugeFill.Size = UDim2.fromScale(0, 1)
	gaugeFill.BorderSizePixel = 0
	gaugeFill.Parent = gaugeFrame
	UiKit.corner(gaugeFill, 6)
	RunService.RenderStepped:Connect(update)
end

return ChargeController
