--!strict
-- 차징(모으기) 연출 (클라이언트). 얼마나 모았는지와 강타 판정은 서버(ChargeService)가 정한다.
-- 활: 화면 아래 차징 게이지가 찬다 (다 차면 금색)
-- 나머지 도구·무기: 휘두르기 직전 자세로 멈추고, 도구에서 은은한 빛이 점점 커지며 깜빡이다가
--   다 모이면 깜빡임이 멈추고 선명한 테두리와 반짝임이 생긴다

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local PickaxeDefs = require(ReplicatedStorage.Shared.PickaxeDefs)
local HitFeelController = require(script.Parent.HitFeelController)
local SwingAnimation = require(script.Parent.SwingAnimation)
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
	current = { Def = def, Start = os.clock(), Holding = false, Full = false, Light = nil, Sparkles = nil, Highlight = nil, Anchor = nil }
	if def.Kind == "Bow" then
		gaugeFill.Size = UDim2.fromScale(0, 1)
		gaugeFill.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
		gaugeFrame.Visible = true
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
	local held = os.clock() - session.Start
	local ratio = if held < Config.Charge.TapThreshold then 0 else math.clamp(held / Config.Charge.Time, 0, 1)
	return held, ratio
end

-- 휘두르지 않고 취소 (도구를 내려놓음)
function ChargeController.cancel()
	if current and current.Holding then
		SwingAnimation.cancelHold()
	end
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
	if session.Def.Kind == "Bow" then
		gaugeFill.Size = UDim2.fromScale(ratio, 1)
	else
		if not session.Holding and held >= Config.Charge.TapThreshold then
			session.Holding = true
			SwingAnimation.hold()
			startGlow(session)
		end
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
