--!strict
-- 모바일 화면 조작 (2026-10-09 사용자 요청): 왼쪽 아래 이동 패드, 오른쪽 아래 큰 공격 버튼
--   이동 패드: Roblox 기본 고정 조이스틱 (서버가 플레이어 DevTouchMovementMode = Thumbstick으로 정한다)
--   공격 버튼: 누르고 있으면 모으고, 떼면 휘두른다 (InputController와 같은 흐름). 도구·무기를 안 들었으면 흐리게
--   점프 버튼은 공격 버튼 왼쪽 위로 옮긴다
-- 터치 화면이 아니면 아무것도 만들지 않는다

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local InputController = require(script.Parent.InputController)
local UiKit = require(script.Parent.UiKit)

local localPlayer = Players.LocalPlayer

local MobileControls = {}

-- 기본 점프 버튼을 공격 버튼 왼쪽 위로 옮긴다 (TouchGui는 늦게 생길 수 있어 기다린다)
local function moveJumpButton()
	local layout = Config.MobileControls
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local touchGui = playerGui:WaitForChild("TouchGui", 20)
	local frame = touchGui and touchGui:WaitForChild("TouchControlFrame", 10)
	local jump = frame and frame:WaitForChild("JumpButton", 10)
	if jump and jump:IsA("GuiObject") then
		local function place()
			jump.AnchorPoint = Vector2.new(1, 1)
			jump.Position = UDim2.new(1, -(layout.Margin + layout.AttackSize + layout.Gap), 1, -(layout.Margin + layout.AttackSize * 0.55))
		end
		place()
		-- 화면 크기가 바뀌면 Roblox가 다시 배치하므로 그때마다 되돌린다
		jump:GetPropertyChangedSignal("Position"):Connect(function()
			task.defer(place)
		end)
	end
end

-- 클라이언트 시작 시 한 번 호출
function MobileControls.init()
	if not UserInputService.TouchEnabled then
		return
	end
	local layout = Config.MobileControls

	local gui = Instance.new("ScreenGui")
	gui.Name = "MobileControls"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	local button = Instance.new("TextButton")
	button.Name = "AttackButton"
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.new(1, -layout.Margin, 1, -layout.Margin)
	button.Size = UDim2.fromOffset(layout.AttackSize, layout.AttackSize)
	button.BackgroundColor3 = Color3.fromRGB(230, 90, 70)
	button.BackgroundTransparency = 0.15
	button.AutoButtonColor = false
	button.Font = Enum.Font.FredokaOne
	button.Text = "⚔"
	button.TextScaled = true
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Parent = gui
	UiKit.corner(button, layout.AttackSize / 2)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.2, 0)
	padding.PaddingBottom = UDim.new(0.2, 0)
	padding.Parent = button

	-- 누르면 모으기 시작, 떼면 휘두르기 (손가락이 버튼 밖으로 나가도 뗄 때까지 유지)
	local activeInput: InputObject? = nil
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and not activeInput then
			activeInput = input
			button.Size = UDim2.fromOffset(layout.AttackSize * 0.92, layout.AttackSize * 0.92)
			InputController.pressAttack()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input == activeInput then
			activeInput = nil
			button.Size = UDim2.fromOffset(layout.AttackSize, layout.AttackSize)
			InputController.releaseAttack()
		end
	end)

	-- 도구·무기를 들었을 때만 선명하게
	RunService.Heartbeat:Connect(function()
		local ready = InputController.canAttack()
		button.BackgroundTransparency = if ready then 0.15 else 0.6
		button.TextTransparency = if ready then 0 else 0.5
	end)

	task.spawn(moveJumpButton)
end

return MobileControls
