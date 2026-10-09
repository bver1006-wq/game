--!strict
-- 체력·마나 바(오른쪽 위, 항상 보임. 체력 아래 마나)와 달리기 모드 버튼(오른쪽).
-- 체력은 캐릭터 Humanoid, 마나는 서버가 정한 플레이어 속성(Mana·MaxMana)을 보여 준다.
-- 2026-10-09: 달리기 버튼은 없앴다(항상 달림). 체력바 왼쪽에 해시계(낮·밤이 얼마나 남았는지)

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UiKit = require(script.Parent.UiKit)

local BAR_WIDTH = 240
local BAR_HEIGHT = 20
local TOP = 8 -- 오른쪽 맨 위 (2026-10-09: Roblox 리더보드를 끄고 위로 올림. 골드 표시는 그 아래)

local HP_COLOR = Color3.fromRGB(225, 70, 70)
local MANA_COLOR = Color3.fromRGB(70, 130, 240)

local localPlayer = Players.LocalPlayer

local StatusHUD = {}

type Bar = { Fill: Frame, Label: TextLabel }

-- 바 하나 (배경 + 채움 + 가운데 글자). 오른쪽 위에서 y만큼 아래
local function makeBar(parent: Instance, y: number, color: Color3): Bar
	local back = Instance.new("Frame")
	back.AnchorPoint = Vector2.new(1, 0)
	back.Position = UDim2.new(1, -16, 0, y)
	back.Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT)
	back.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	back.BackgroundTransparency = 0.2
	back.BorderSizePixel = 0
	back.Parent = parent
	UiKit.corner(back, 9)
	UiKit.stroke(back, Color3.fromRGB(0, 0, 0), 1.5)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = back
	UiKit.corner(fill, 9)
	local gradient = Instance.new("UIGradient") -- 위는 밝게, 아래는 어둡게
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170))
	gradient.Rotation = 90
	gradient.Parent = fill
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 14
	label.TextColor3 = Color3.new(1, 1, 1)
	label.ZIndex = 2
	label.Parent = back
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Parent = label
	return { Fill = fill, Label = label }
end

local function setBar(bar: Bar, name: string, value: number, max: number)
	local ratio = if max > 0 then math.clamp(value / max, 0, 1) else 0
	bar.Fill.Size = UDim2.fromScale(ratio, 1)
	bar.Fill.Visible = ratio > 0
	bar.Label.Text = `{name} {math.floor(value + 0.5)} / {math.floor(max + 0.5)}`
end

-- Roblox 기본 체력바·리더보드 끄기 (코어 GUI가 늦게 준비될 수 있어 몇 번 시도)
-- 리더보드는 오른쪽 위를 가려서 끈다. 골드는 체력·마나 아래 칸에 따로 보인다
local function disableDefaultHealth()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
		end)
		if ok then
			return
		end
		task.wait(0.5)
	end
end

-- 클라이언트 시작 시 한 번 호출
function StatusHUD.init()
	task.spawn(disableDefaultHealth)
	
	local gui = Instance.new("ScreenGui")
	gui.Name = "StatusGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 14
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	-- 위: 체력, 아래: 마나
	local hpBar = makeBar(gui, TOP, HP_COLOR)
	local manaBar = makeBar(gui, TOP + BAR_HEIGHT + 4, MANA_COLOR)

	-- 해시계: 체력바 왼쪽. 낮(노랑)·밤(남색) 바퀴 위를 바늘이 돌고, 아래에 남은 시간
	local dialSize = 58
	local dial = Instance.new("Frame")
	dial.Name = "Sundial"
	dial.AnchorPoint = Vector2.new(1, 0)
	dial.Position = UDim2.new(1, -(16 + BAR_WIDTH + 10), 0, TOP)
	dial.Size = UDim2.fromOffset(dialSize, dialSize)
	dial.BackgroundColor3 = Color3.fromRGB(40, 50, 90)
	dial.Parent = gui
	UiKit.corner(dial, dialSize / 2)
	UiKit.stroke(dial, UiKit.Colors.Border, 2)
	-- 낮 부분: 바퀴를 시각(0~24)으로 보고, 낮 구간을 작은 노란 점들로 칠한다
	local dayNight = Config.DayNight
	for hour = 0, 23.5, 0.5 do
		local isDayHour = hour >= dayNight.DayStart and hour < dayNight.NightStart
		local angle = math.rad(hour / 24 * 360 - 90)
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Size = UDim2.fromOffset(7, 7)
		dot.Position = UDim2.new(0.5, math.cos(angle) * (dialSize / 2 - 7), 0.5, math.sin(angle) * (dialSize / 2 - 7))
		dot.BackgroundColor3 = if isDayHour then Color3.fromRGB(255, 205, 70) else Color3.fromRGB(90, 105, 170)
		dot.BorderSizePixel = 0
		dot.Parent = dial
		UiKit.corner(dot, 4)
	end
	local center = UiKit.label(dial, "☀", UDim2.fromOffset(24, 24), UDim2.new(0.5, -12, 0.5, -12), Color3.new(1, 1, 1), 18)
	center.TextXAlignment = Enum.TextXAlignment.Center
	-- 바늘: 회전은 가운데 기준이라, 다이얼만 한 투명 틀을 돌리고 그 안에 가운데→위로 바늘을 둔다
	local needleHolder = Instance.new("Frame")
	needleHolder.Size = UDim2.fromScale(1, 1)
	needleHolder.BackgroundTransparency = 1
	needleHolder.ZIndex = 2
	needleHolder.Parent = dial
	local needle = Instance.new("Frame")
	needle.AnchorPoint = Vector2.new(0.5, 1)
	needle.Position = UDim2.fromScale(0.5, 0.5)
	needle.Size = UDim2.fromOffset(3, dialSize / 2 - 4)
	needle.BackgroundColor3 = Color3.fromRGB(255, 120, 60)
	needle.BorderSizePixel = 0
	needle.ZIndex = 2
	needle.Parent = needleHolder
	local remainLabel = UiKit.label(gui, "", UDim2.fromOffset(90, 18), UDim2.new(1, -(16 + BAR_WIDTH + 10 + dialSize / 2 + 45), 0, TOP + dialSize + 2), UiKit.Colors.Text, 13)
	remainLabel.TextXAlignment = Enum.TextXAlignment.Center
	local remainStroke = Instance.new("UIStroke")
	remainStroke.Thickness = 1.5
	remainStroke.Parent = remainLabel

	-- 지금 시각에서 낮(또는 밤)이 끝날 때까지 실제 남은 초 (서버와 같은 빠르기로 계산)
	local function secondsLeft(clock: number): (boolean, number)
		local dayHours = dayNight.NightStart - dayNight.DayStart
		local isDay = clock >= dayNight.DayStart and clock < dayNight.NightStart
		if isDay then
			return true, (dayNight.NightStart - clock) / dayHours * dayNight.DaySeconds
		end
		local untilDawn = (dayNight.DayStart - clock) % 24
		return false, untilDawn / (24 - dayHours) * dayNight.NightSeconds
	end
	task.spawn(function()
		while true do
			local clock = Lighting.ClockTime
			needleHolder.Rotation = clock / 24 * 360 -- 바늘 끝이 바퀴의 그 시각을 가리킨다 (0시 = 위, 시계 방향)
			local isDay, left = secondsLeft(clock)
			center.Text = if isDay then "☀" else "🌙"
			local minutes = math.floor(left / 60)
			local seconds = math.floor(left % 60)
			remainLabel.Text = `{if isDay then "밤까지" else "아침까지"} {minutes}:{string.format("%02d", seconds)}`
			task.wait(0.5)
		end
	end)

	-- 매 프레임 체력·마나 반영
	RunService.Heartbeat:Connect(function()
		local character = localPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			setBar(hpBar, "체력", humanoid.Health, humanoid.MaxHealth)
		end
		local mana = localPlayer:GetAttribute("Mana")
		local maxMana = localPlayer:GetAttribute("MaxMana")
		setBar(manaBar, "마나", if typeof(mana) == "number" then mana else 0, if typeof(maxMana) == "number" then maxMana else Config.Mana.Max)
	end)
end

return StatusHUD
