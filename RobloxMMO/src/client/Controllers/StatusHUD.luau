--!strict
-- 체력·마나 바(오른쪽 위, 항상 보임. 체력 아래 마나)와 달리기 모드 버튼(오른쪽).
-- 체력은 캐릭터 Humanoid, 마나·달리기는 서버가 정한 플레이어 속성(Mana·MaxMana·Sprinting)을 보여 준다.
-- 버튼은 서버에 "달리기 켜기/끄기"만 보낸다 (SetSprint).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UiKit = require(script.Parent.UiKit)

local BAR_WIDTH = 240
local BAR_HEIGHT = 20
local TOP = 120 -- 오른쪽 위, Roblox 리더보드 아래 (골드 표시는 그 아래로 내렸다)

local HP_COLOR = Color3.fromRGB(225, 70, 70)
local MANA_COLOR = Color3.fromRGB(70, 130, 240)
local SPRINT_ON = Color3.fromRGB(70, 180, 90)

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

-- Roblox 기본 체력바 끄기 (코어 GUI가 늦게 준비될 수 있어 몇 번 시도)
local function disableDefaultHealth()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
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
	local sprintRemote = Remotes.get(Remotes.Names.SetSprint)

	local gui = Instance.new("ScreenGui")
	gui.Name = "StatusGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 14
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	-- 위: 체력, 아래: 마나
	local hpBar = makeBar(gui, TOP, HP_COLOR)
	local manaBar = makeBar(gui, TOP + BAR_HEIGHT + 4, MANA_COLOR)

	-- 달리기 버튼 (오른쪽 가운데)
	local sprintButton = Instance.new("TextButton")
	sprintButton.Name = "SprintButton"
	sprintButton.AnchorPoint = Vector2.new(1, 0.5)
	sprintButton.Position = UDim2.new(1, -16, 0.5, 0)
	sprintButton.Size = UDim2.fromOffset(120, 48)
	sprintButton.AutoButtonColor = true
	sprintButton.Font = Enum.Font.FredokaOne
	sprintButton.TextSize = 18
	sprintButton.TextColor3 = Color3.new(1, 1, 1)
	sprintButton.Parent = gui
	UiKit.corner(sprintButton, 12)
	UiKit.stroke(sprintButton)
	local function renderSprint()
		local on = localPlayer:GetAttribute("Sprinting") == true
		sprintButton.Text = if on then "달리기 ON" else "달리기 OFF"
		sprintButton.BackgroundColor3 = if on then SPRINT_ON else UiKit.Colors.Panel
	end
	sprintButton.Activated:Connect(function()
		sprintRemote:FireServer(localPlayer:GetAttribute("Sprinting") ~= true)
	end)
	localPlayer:GetAttributeChangedSignal("Sprinting"):Connect(renderSprint)
	renderSprint()

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
