--!strict
-- 나무 베기 화면 아래 판 (2026-10-10 사용자 요청): 나무 이름 + 체력바 + 작은 타이밍 막대.
-- 막대 안에서 커서가 좌우로 왕복하고, 금색 세로줄(목표)에 커서가 있을 때 치면 Perfect, 근처 하늘색 구역이면 Nice.
-- 커서 시작 시각·왕복 시간·목표 위치는 서버(TimingService)가 TreeTiming으로 보내 준 값만 쓴다 (GetServerTimeNow 기준).
-- 판정도 서버가 한다. 여기서는 보여 주기만 한다.
-- 바위는 그대로 잔상(TimingGhostController) + 바위 위 체력바(RockHUD)를 쓴다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local PickaxeDefs = require(ReplicatedStorage.Shared.PickaxeDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local TargetController = require(script.Parent.TargetController)

local localPlayer = Players.LocalPlayer

local WEAPON_KINDS: { [string]: boolean } = { Sword = true, Bow = true, Club = true }
local REQUEST_RETRY = 1 -- 막대 값을 못 받았으면 이 간격(초)으로 다시 요청
local FLASH_TIME = 0.25 -- 타격 판정 색으로 막대 테두리가 번쩍이는 시간(초)

-- 판정별 테두리 번쩍임 색
local JUDGMENT_COLORS: { [string]: Color3 } = {
	Perfect = Config.TreeTiming.TargetColor,
	Nice = Config.TreeTiming.NiceColor,
}

type Timing = { StartTime: number, Period: number, Target: number }

local TreeTimingHUD = {}

local timingRemote: RemoteEvent
local timings: { [Model]: Timing } = {} -- 나무 → 서버가 보낸 막대 값 (내 것만)

local panel: Frame
local nameLabel: TextLabel
local hpFill: Frame
local barRow: Frame
local barStroke: UIStroke
local niceZone: Frame
local perfectZone: Frame
local targetLine: Frame
local cursor: Frame

local currentTree: Model? = nil
local shownHp = -1
local requestedTree: Model? = nil
local requestedAt = 0

-- 지금 손에 든 도구 정의 (없으면 nil)
local function heldDef(): PickaxeDefs.PickaxeDef?
	local character = localPlayer.Character
	local tool = character and character:FindFirstChildWhichIsA("Tool")
	local id = tool and tool:GetAttribute("PickaxeId")
	return if typeof(id) == "string" then PickaxeDefs[id] else nil
end

-- 판정 범위: 모바일(터치만 되는 기기)은 넓게. 서버도 같은 기준(SwingRequest isTouch)으로 판정한다
local function windows(): { Perfect: number, Nice: number }
	local isTouch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	return if isTouch then Config.TreeTiming.Windows.Mobile else Config.TreeTiming.Windows.PC
end

-- 시각 t의 커서 위치(0~1). 서버 TimingService.cursorAt과 같은 왕복 계산
local function cursorAt(timing: Timing, t: number): number
	local phase = ((t - timing.StartTime) / timing.Period) % 2
	return if phase <= 1 then phase else 2 - phase
end

-- 구역 칸 하나 (막대 안 가로 위치 left~right, 0~1)
local function placeZone(frame: Frame, center: number, half: number)
	local left = math.clamp(center - half, 0, 1)
	local right = math.clamp(center + half, 0, 1)
	frame.Position = UDim2.fromScale(left, 0)
	frame.Size = UDim2.fromScale(right - left, 1)
end

-- 둥근 모서리 붙이기
local function round(parent: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

-- 화면 아래 판을 만든다 (하나 만들어 두고 대상 나무만 바꿔 쓴다)
local function createPanel()
	local config = Config.TreeTiming
	local gui = Instance.new("ScreenGui")
	gui.Name = "TreeTimingHUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 5

	local nameHeight = 20
	local gap = 4
	local height = nameHeight + gap + config.HpBarHeight + gap + 2 + config.TimingBarHeight + 6

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -config.BottomOffset)
	frame.Size = UDim2.new(1, -32, 0, height) -- 좁은 화면에서는 양옆 16픽셀씩 남기고 줄어든다
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = gui
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(config.PanelWidth, height)
	limit.Parent = frame
	panel = frame

	-- 나무 이름
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, nameHeight)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = frame
	local labelStroke = Instance.new("UIStroke")
	labelStroke.Thickness = 1.5
	labelStroke.Parent = label
	nameLabel = label

	-- 체력바
	local hpBack = Instance.new("Frame")
	hpBack.Position = UDim2.fromOffset(0, nameHeight + gap)
	hpBack.Size = UDim2.new(1, 0, 0, config.HpBarHeight)
	hpBack.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	hpBack.BackgroundTransparency = 0.2
	hpBack.BorderSizePixel = 0
	hpBack.Parent = frame
	round(hpBack, config.HpBarHeight // 2)
	local hpStroke = Instance.new("UIStroke")
	hpStroke.Thickness = 1.5
	hpStroke.Parent = hpBack
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(110, 220, 90)
	fill.BorderSizePixel = 0
	fill.Parent = hpBack
	round(fill, config.HpBarHeight // 2)
	hpFill = fill

	-- 타이밍 막대 (가운데 70% 너비)
	local bar = Instance.new("Frame")
	bar.Name = "TimingBar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, nameHeight + gap + config.HpBarHeight + gap + 2)
	bar.Size = UDim2.new(0.7, 0, 0, config.TimingBarHeight)
	bar.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	bar.BackgroundTransparency = 0.15
	bar.BorderSizePixel = 0
	bar.ClipsDescendants = false
	bar.Parent = frame
	round(bar, 4)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Parent = bar
	barStroke = stroke
	barRow = bar

	-- 구역: Nice(하늘색, 넓게) 위에 Perfect(금색, 좁게)를 은은하게
	local function zone(color: Color3, z: number): Frame
		local f = Instance.new("Frame")
		f.BackgroundColor3 = color
		f.BackgroundTransparency = config.ZoneTransparency
		f.BorderSizePixel = 0
		f.ZIndex = z
		f.Parent = bar
		return f
	end
	niceZone = zone(config.NiceColor, 2)
	perfectZone = zone(config.TargetColor, 3)

	-- 목표 세로줄 (금색, 막대보다 조금 길게)
	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Size = UDim2.new(0, 3, 1, 6)
	line.BackgroundColor3 = config.TargetColor
	line.BorderSizePixel = 0
	line.ZIndex = 4
	line.Parent = bar
	targetLine = line

	-- 커서 (흰색, 검은 테두리)
	local mark = Instance.new("Frame")
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Size = UDim2.new(0, config.CursorWidth, 1, 10)
	mark.BackgroundColor3 = config.CursorColor
	mark.BorderSizePixel = 0
	mark.ZIndex = 5
	mark.Visible = false
	mark.Parent = bar
	round(mark, 2)
	local markStroke = Instance.new("UIStroke")
	markStroke.Thickness = 1
	markStroke.Parent = mark
	cursor = mark

	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

-- 서버에 이 나무의 막대 값을 요청한다 (서버가 도끼·거리·주인을 다시 확인한다)
local function request(tree: Model)
	requestedTree = tree
	requestedAt = os.clock()
	timingRemote:FireServer(tree)
end

-- 매 프레임: 가까운 나무로 판을 옮기고 체력·커서를 그린다
local function update()
	local def = heldDef()
	local holdingWeapon = def ~= nil and WEAPON_KINDS[def.Kind] == true
	local holdingAxe = def ~= nil and def.Kind == "Axe"
	local node = if holdingWeapon then nil else TargetController.getNearestRock(Config.HitFeel.HpBarRange)
	local nodeDef = node and TargetController.getDef(node)
	local tree = if node and nodeDef and nodeDef.Kind == "Tree" then node else nil

	-- 사라진 나무 기록 정리
	for model in timings do
		if not model.Parent then
			timings[model] = nil
		end
	end

	if tree ~= currentTree then
		currentTree = tree
		shownHp = -1
		if tree and nodeDef then
			local isBoss = tree:GetAttribute("Boss") == true
			nameLabel.Text = if isBoss then `👑 보스 {nodeDef.DisplayName}` else nodeDef.DisplayName
			nameLabel.TextColor3 = if isBoss then Color3.fromRGB(255, 210, 80) else Color3.new(1, 1, 1)
		end
	end
	panel.Visible = tree ~= nil
	if not tree then
		requestedTree = nil
		return
	end

	-- 체력
	local hp = tree:GetAttribute("Hp")
	local maxHp = tree:GetAttribute("MaxHp")
	if typeof(hp) == "number" and typeof(maxHp) == "number" and maxHp > 0 and hp ~= shownHp then
		local ratio = math.clamp(hp / maxHp, 0, 1)
		local tweenTime = if shownHp < 0 then 0 else 0.12
		shownHp = hp
		TweenService:Create(hpFill, TweenInfo.new(tweenTime, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(ratio, 1) }):Play()
		hpFill.BackgroundColor3 = Color3.fromRGB(230, 70, 60):Lerp(Color3.fromRGB(110, 220, 90), ratio)
	end

	-- 타이밍 막대: 도끼를 들었을 때만 (곡괭이 등으로는 나무를 못 벤다)
	barRow.Visible = holdingAxe
	if not holdingAxe then
		requestedTree = nil
		return
	end
	local timing = timings[tree]
	if not timing and (requestedTree ~= tree or os.clock() - requestedAt >= REQUEST_RETRY) then
		request(tree)
	end
	if not timing then
		cursor.Visible = false
		niceZone.Visible = false
		perfectZone.Visible = false
		targetLine.Visible = false
		return
	end

	local w = windows()
	niceZone.Visible = true
	perfectZone.Visible = true
	targetLine.Visible = true
	cursor.Visible = true
	placeZone(niceZone, timing.Target, w.Nice)
	placeZone(perfectZone, timing.Target, w.Perfect)
	targetLine.Position = UDim2.fromScale(timing.Target, 0.5)
	cursor.Position = UDim2.fromScale(cursorAt(timing, Workspace:GetServerTimeNow()), 0.5)
end

-- 서버가 보낸 막대 값 저장
local function onTreeTiming(tree: unknown, startTime: unknown, period: unknown, target: unknown)
	if typeof(tree) ~= "Instance" or not (tree :: Instance):IsA("Model") then
		return
	end
	if typeof(startTime) ~= "number" or typeof(period) ~= "number" or typeof(target) ~= "number" or period <= 0 then
		return
	end
	timings[tree :: Model] = { StartTime = startTime, Period = period, Target = target }
end

-- 내 타격이 이 나무에 맞으면 막대 테두리를 판정 색으로 잠깐 번쩍인다
local function onHitEffect(rock: Model?, judgment: string, _hitPosition: Vector3, attackerUserId: number)
	if attackerUserId ~= localPlayer.UserId or rock == nil or rock ~= currentTree then
		return
	end
	local color = JUDGMENT_COLORS[judgment]
	if not color then
		return
	end
	barStroke.Color = color
	barStroke.Thickness = 3
	TweenService:Create(barStroke, TweenInfo.new(FLASH_TIME), { Color = Color3.fromRGB(0, 0, 0), Thickness = 2 }):Play()
end

-- 클라이언트 시작 시 한 번 호출 (RockHUD.init에서 부른다)
function TreeTimingHUD.init()
	createPanel()
	timingRemote = Remotes.get(Remotes.Names.TreeTiming)
	timingRemote.OnClientEvent:Connect(onTreeTiming)
	Remotes.get(Remotes.Names.HitEffect).OnClientEvent:Connect(onHitEffect)
	RunService.RenderStepped:Connect(update)
end

return TreeTimingHUD
