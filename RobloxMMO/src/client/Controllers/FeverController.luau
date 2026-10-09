--!strict
-- 피버 연출과 연타 입력.
-- 1 멈춤 → 2 카메라 반 바퀴 + 균열에서 빛 → 3 "FEVER!" → 4 연타(게이지) → 5 폭발과 보너스 표시.
-- 각 단계 시각은 서버가 FeverStart로 알려준 시작 시각(GetServerTimeNow 기준)에 맞춘다.
-- 탭 수와 보너스는 서버가 센다. 여기 게이지는 보여주기용 로컬 카운트다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local HitFeelController = require(script.Parent.HitFeelController)
local SwingAnimation = require(script.Parent.SwingAnimation)
local TimingGhostController = require(script.Parent.TimingGhostController)

local localPlayer = Players.LocalPlayer

local LIGHT_COLOR = Color3.fromRGB(255, 220, 120)
local RAY_COUNT = 8
local RAY_LENGTH = 6
local GAUGE_MAX_TAPS = 46 -- 게이지가 가득 차는 탭 수 (마지막 보너스 기준보다 조금 크게)
local TAP_INPUTS = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.Touch] = true,
}
local TAP_KEYS = {
	[Enum.KeyCode.ButtonR2] = true,
	[Enum.KeyCode.ButtonA] = true,
	[Enum.KeyCode.Space] = true,
}

-- 진행 중인 피버의 로컬 상태
type Session = {
	Rock: Model,
	RockPosition: Vector3,
	StartTime: number,
	TapStart: number,
	TapEnd: number,
	LocalTaps: number,
	LastTapClock: number,
	Root: BasePart?,
	Effects: Folder,
	Light: PointLight,
	Rays: { BasePart },
	Gui: ScreenGui,
	GaugeFill: Frame,
	MultiplierLabel: TextLabel,
	Connections: { RBXScriptConnection },
	Finished: boolean,
}

local FeverController = {}

local session: Session? = nil
local tapRemote: RemoteEvent

-- 피버 중인지 (InputController가 휘두르기 대신 연타로 처리하려고 확인한다)
function FeverController.isActive(): boolean
	return session ~= nil
end

-- 탭 수에 맞는 보너스 개수 (서버와 같은 표를 쓴다. 표시용)
local function bonusFor(taps: number): number
	for _, tier in Config.Fever.Tiers do
		if taps >= tier.MinTaps then
			return tier.Bonus
		end
	end
	return 0
end

-- 서버 시각으로 target까지 기다린다 (중간에 피버가 끝나면 false)
local function waitUntil(current: Session, target: number): boolean
	while Workspace:GetServerTimeNow() < target do
		if session ~= current then
			return false
		end
		RunService.RenderStepped:Wait()
	end
	return session == current
end

-- 큰 글자 하나를 화면 가운데에 띄운다
local function makeBigText(parent: Instance, text: string, color: Color3, y: number): TextLabel
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, y)
	label.Size = UDim2.fromScale(0.8, 0.2)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = color
	label.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 5
	stroke.Color = Color3.fromRGB(90, 30, 0)
	stroke.Parent = label
	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	return label
end

-- 연타 게이지 UI를 만든다
local function createGui(): (ScreenGui, Frame, TextLabel)
	local gui = Instance.new("ScreenGui")
	gui.Name = "FeverGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10

	local gauge = Instance.new("Frame")
	gauge.AnchorPoint = Vector2.new(0.5, 1)
	gauge.Position = UDim2.fromScale(0.5, 0.88)
	gauge.Size = UDim2.fromScale(0.5, 0.045)
	gauge.BackgroundColor3 = Color3.fromRGB(30, 20, 20)
	gauge.BorderSizePixel = 0
	gauge.Visible = false
	gauge.Name = "Gauge"
	gauge.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = gauge
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(255, 240, 200)
	stroke.Parent = gauge

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(255, 150, 40)
	fill.BorderSizePixel = 0
	fill.Parent = gauge
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill

	-- 보너스가 바뀌는 탭 수 위치에 눈금
	for _, tier in Config.Fever.Tiers do
		if tier.MinTaps > 0 then
			local mark = Instance.new("Frame")
			mark.AnchorPoint = Vector2.new(0.5, 0)
			mark.Position = UDim2.fromScale(tier.MinTaps / GAUGE_MAX_TAPS, 0)
			mark.Size = UDim2.new(0, 3, 1, 0)
			mark.BackgroundColor3 = Color3.new(1, 1, 1)
			mark.BorderSizePixel = 0
			mark.ZIndex = 2
			mark.Parent = gauge
			local markLabel = Instance.new("TextLabel")
			markLabel.AnchorPoint = Vector2.new(0.5, 1)
			markLabel.Position = UDim2.fromScale(0.5, 0)
			markLabel.Size = UDim2.new(0, 40, 1.2, 0)
			markLabel.BackgroundTransparency = 1
			markLabel.Font = Enum.Font.FredokaOne
			markLabel.Text = `+{tier.Bonus}`
			markLabel.TextScaled = true
			markLabel.TextColor3 = Color3.new(1, 1, 1)
			markLabel.Parent = mark
		end
	end

	local multiplier = Instance.new("TextLabel")
	multiplier.AnchorPoint = Vector2.new(0.5, 1)
	multiplier.Position = UDim2.fromScale(0.5, 0.8)
	multiplier.Size = UDim2.fromScale(0.3, 0.1)
	multiplier.BackgroundTransparency = 1
	multiplier.Font = Enum.Font.FredokaOne
	multiplier.Text = ""
	multiplier.TextScaled = true
	multiplier.TextColor3 = Color3.fromRGB(255, 230, 120)
	multiplier.Parent = gui
	local multiplierStroke = Instance.new("UIStroke")
	multiplierStroke.Thickness = 4
	multiplierStroke.Color = Color3.fromRGB(90, 30, 0)
	multiplierStroke.Parent = multiplier

	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	return gui, fill, multiplier
end

-- 균열에서 뿜어지는 빛: 바위 중심의 PointLight와 사방으로 뻗는 빛줄기
local function createLightEffects(position: Vector3, effects: Folder): (PointLight, { BasePart })
	local core = Instance.new("Part")
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.Transparency = 1
	core.Size = Vector3.new(0.2, 0.2, 0.2)
	core.Position = position
	core.Parent = effects

	local light = Instance.new("PointLight")
	light.Color = LIGHT_COLOR
	light.Brightness = 0
	light.Range = 16
	light.Shadows = false
	light.Parent = core

	local rays: { BasePart } = {}
	local random = Random.new()
	for i = 1, RAY_COUNT do
		local ray = Instance.new("Part")
		ray.Anchored = true
		ray.CanCollide = false
		ray.CanQuery = false
		ray.CanTouch = false
		ray.CastShadow = false
		ray.Material = Enum.Material.Neon
		ray.Color = LIGHT_COLOR
		ray.Transparency = 0.2
		ray.Size = Vector3.new(0.12, 0.12, 0.01)
		-- 위쪽 반구로 고르게 퍼지는 방향
		local yaw = (i / RAY_COUNT) * math.pi * 2 + random:NextNumber(-0.2, 0.2)
		local pitch = random:NextNumber(0.15, 1.1)
		local direction = Vector3.new(math.cos(yaw) * math.cos(pitch), math.sin(pitch), math.sin(yaw) * math.cos(pitch))
		ray:SetAttribute("Direction", direction)
		ray.CFrame = CFrame.lookAt(position, position + direction)
		ray.Parent = effects
		table.insert(rays, ray)
	end
	return light, rays
end

-- 빛줄기 길이를 정한다 (0~1)
local function setRayLength(current: Session, ratio: number)
	for _, ray in current.Rays do
		local direction = ray:GetAttribute("Direction") :: Vector3
		local length = math.max(RAY_LENGTH * ratio, 0.01)
		ray.Size = Vector3.new(0.12 + 0.1 * ratio, 0.12 + 0.1 * ratio, length)
		ray.CFrame = CFrame.lookAt(current.RockPosition, current.RockPosition + direction) * CFrame.new(0, 0, -length / 2)
	end
end

-- 피버를 끝내고 카메라·캐릭터·UI를 원래대로 돌린다
local function cleanup(current: Session)
	if current.Finished then
		return
	end
	current.Finished = true
	if session == current then
		session = nil
	end
	for _, connection in current.Connections do
		connection:Disconnect()
	end
	current.Effects:Destroy()
	current.Gui:Destroy()
	HitFeelController.setSfxVolume(1)
	if current.Root then
		current.Root.Anchored = false
	end
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
end

-- 연타 1회 (로컬에서도 초당 MaxTapsPerSecond로 제한해서 서버와 비슷하게 센다)
local function onTap(current: Session)
	local now = Workspace:GetServerTimeNow()
	if now < current.TapStart or now > current.TapEnd then
		return
	end
	local clockNow = os.clock()
	if clockNow - current.LastTapClock < 1 / Config.Fever.MaxTapsPerSecond then
		return
	end
	current.LastTapClock = clockNow
	current.LocalTaps += 1
	tapRemote:FireServer()

	HitFeelController.shakeRock(current.Rock, 1.8)
	HitFeelController.emitDebris(current.RockPosition + Vector3.new(0, 1, 0), LIGHT_COLOR, 5, 0.8)
	local fever = Config.Fever
	local progress = math.min(current.LocalTaps / GAUGE_MAX_TAPS, 1)
	local pitch = fever.TapPitchStart
		+ (fever.TapPitchEnd - fever.TapPitchStart) * progress
		+ (math.random() * 2 - 1) * fever.TapPitchJitter
	HitFeelController.playSound(Config.Sounds.FeverTap, nil, pitch, fever.TapVolume)
	HitFeelController.playSound(Config.Sounds.FeverTapSparkle, nil, pitch, fever.TapSparkleVolume)
	HitFeelController.cameraShake(0.08, 0.06)

	local ratio = math.min(current.LocalTaps / GAUGE_MAX_TAPS, 1)
	TweenService:Create(current.GaugeFill, TweenInfo.new(0.06), { Size = UDim2.fromScale(ratio, 1) }):Play()
	current.MultiplierLabel.Text = `+{bonusFor(current.LocalTaps)}`
	current.Light.Brightness = 3 + ratio * 7
	setRayLength(current, 0.5 + ratio * 0.5)
end

-- 피버 연출 전체 흐름 (FeverStart를 받으면 실행)
local function runFever(rock: Model, startTime: number)
	if session then
		cleanup(session)
	end
	TimingGhostController.clear()

	local fever = Config.Fever
	local rockPosition = HitFeelController.getRestPivot(rock).Position
	local effects = Instance.new("Folder")
	effects.Name = "FeverEffects"
	effects.Parent = Workspace
	local light, rays = createLightEffects(rockPosition, effects)
	local gui, gaugeFill, multiplierLabel = createGui()

	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local current: Session = {
		Rock = rock,
		RockPosition = rockPosition,
		StartTime = startTime,
		TapStart = startTime + fever.FreezeDuration + fever.OrbitDuration + fever.TitleDuration,
		TapEnd = startTime + fever.FreezeDuration + fever.OrbitDuration + fever.TitleDuration + fever.TapDuration,
		LocalTaps = 0,
		LastTapClock = 0,
		Root = if root and root:IsA("BasePart") then root else nil,
		Effects = effects,
		Light = light,
		Rays = rays,
		Gui = gui,
		GaugeFill = gaugeFill,
		MultiplierLabel = multiplierLabel,
		Connections = {},
		Finished = false,
	}
	session = current
	setRayLength(current, 0)

	-- 연타 입력: 클릭·터치·패드 어디든 (게임 UI가 먹은 입력도 센다)
	table.insert(current.Connections, UserInputService.InputBegan:Connect(function(input)
		if TAP_INPUTS[input.UserInputType] or TAP_KEYS[input.KeyCode] then
			onTap(current)
		end
	end))

	-- 혹시 결과가 안 오면 알아서 정리
	task.delay(fever.FreezeDuration + fever.OrbitDuration + fever.TitleDuration + fever.TapDuration + fever.BurstDuration + 3, function()
		cleanup(current)
	end)

	-- 캐릭터를 그 자리에 묶는다 (피버 중 이동 금지)
	if current.Root then
		current.Root.Anchored = true
	end

	-- 1. 멈춤: 애니메이션·소리 정지, 카메라 고정
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	local frozenCamera = camera.CFrame
	SwingAnimation.freezeAll(fever.FreezeDuration)
	HitFeelController.setSfxVolume(0)
	table.insert(current.Connections, RunService.RenderStepped:Connect(function()
		if Workspace:GetServerTimeNow() < startTime + fever.FreezeDuration then
			camera.CFrame = frozenCamera
		end
	end))
	if not waitUntil(current, startTime + fever.FreezeDuration) then
		return
	end
	HitFeelController.setSfxVolume(1)
	HitFeelController.playSound(Config.Sounds.FeverStart, nil, 1, 0.7)

	-- 2. 카메라가 바위 주위를 반 바퀴 돌고, 균열에서 빛이 뿜어진다
	local orbitStart = startTime + fever.FreezeDuration
	local flat = (frozenCamera.Position - rockPosition) * Vector3.new(1, 0, 1)
	local startAngle = if flat.Magnitude > 0.01 then math.atan2(flat.Z, flat.X) else 0
	local function orbitCFrame(angle: number): CFrame
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * fever.CameraDistance + Vector3.new(0, fever.CameraHeight, 0)
		return CFrame.lookAt(rockPosition + offset, rockPosition + Vector3.new(0, 0.5, 0))
	end
	TweenService:Create(light, TweenInfo.new(fever.OrbitDuration), { Brightness = 6 }):Play()
	table.insert(current.Connections, RunService.RenderStepped:Connect(function()
		local now = Workspace:GetServerTimeNow()
		if now < orbitStart then
			return
		end
		local t = math.clamp((now - orbitStart) / fever.OrbitDuration, 0, 1)
		local eased = (1 - math.cos(t * math.pi)) / 2 -- 부드럽게 출발·정지
		local angle = if fever.CameraOrbit then startAngle + math.pi * eased else startAngle
		camera.CFrame = orbitCFrame(angle)
		if t < 1 then
			setRayLength(current, eased * 0.6)
		end
	end))
	if not waitUntil(current, orbitStart + fever.OrbitDuration) then
		return
	end

	-- 3. "FEVER!" 문구
	local title = makeBigText(gui, "FEVER!", Color3.fromRGB(255, 200, 40), 0.35)
	HitFeelController.cameraShake(0.3, 0.3)
	if not waitUntil(current, current.TapStart) then
		return
	end
	title:Destroy()

	-- 4. 연타: 게이지와 보너스 표시
	local gauge = gui:FindFirstChild("Gauge") :: Frame
	gauge.Visible = true
	multiplierLabel.Text = `+{bonusFor(0)}`
	local hint = makeBigText(gui, "연타!", Color3.new(1, 1, 1), 0.2)
	hint.Size = UDim2.fromScale(0.3, 0.08)
	if not waitUntil(current, current.TapEnd) then
		return
	end
	hint:Destroy()
	-- 결과(FeverResult)를 기다린다. 5단계는 onFeverResult에서 진행
end

-- 서버의 FeverResult: 최종 보너스 표시 후 폭발, 정리
local function onFeverResult(_rock: Model?, bonus: number, _taps: number)
	local current = session
	if not current then
		return
	end
	local gauge = current.Gui:FindFirstChild("Gauge")
	if gauge then
		gauge:Destroy()
	end
	current.MultiplierLabel.Text = ""
	makeBigText(current.Gui, `+{bonus}개!`, Color3.fromRGB(255, 230, 120), 0.4)

	-- 5. 폭발: 빛이 확 터졌다가 사라진다
	HitFeelController.playSound(Config.Sounds.FeverBurst, current.RockPosition, 1, 0.8)
	HitFeelController.cameraShake(0.6, 0.4)
	HitFeelController.emitDebris(current.RockPosition, LIGHT_COLOR, 50, 2)
	setRayLength(current, 1.6)
	current.Light.Brightness = 15
	TweenService:Create(current.Light, TweenInfo.new(Config.Fever.BurstDuration), { Brightness = 0 }):Play()
	for _, ray in current.Rays do
		TweenService:Create(ray, TweenInfo.new(Config.Fever.BurstDuration), { Transparency = 1 }):Play()
	end

	-- 바위가 깨지고(RockBroken) 획득량이 뜨는 걸 잠깐 보여준 뒤 카메라를 돌려준다
	task.delay(Config.Fever.BurstDuration + 0.8, function()
		cleanup(current)
	end)
end

-- 클라이언트 시작 시 한 번 호출
function FeverController.init()
	tapRemote = Remotes.get(Remotes.Names.FeverTap)
	Remotes.get(Remotes.Names.FeverStart).OnClientEvent:Connect(function(rock: Model, startTime: number)
		task.spawn(runFever, rock, startTime)
	end)
	Remotes.get(Remotes.Names.FeverResult).OnClientEvent:Connect(onFeverResult)
	-- 피버 중에 죽거나 리스폰하면 정리
	localPlayer.CharacterRemoving:Connect(function()
		if session then
			cleanup(session)
		end
	end)
end

return FeverController
