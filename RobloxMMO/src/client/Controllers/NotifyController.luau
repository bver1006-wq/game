--!strict
-- 화면 위쪽 알림 ("가방이 가득 찼어요", "구리괴 3개를 만들었어요" 같은 서버 안내).
-- 여러 개가 오면 아래로 쌓였다가 잠시 뒤 사라진다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UiKit = require(script.Parent.UiKit)

local SHOW_TIME = 2.5 -- 알림이 떠 있는 시간(초)
local MAX_VISIBLE = 4

local KIND_COLOR = {
	good = UiKit.Colors.Good,
	bad = UiKit.Colors.Bad,
	info = UiKit.Colors.Gold,
}

local NotifyController = {}

local container: Frame
local nextOrder = 0 -- 오래된 알림이 위에 오도록 순서 번호

-- 알림 하나를 띄운다
function NotifyController.show(message: string, kind: string?)
	local toasts = {}
	for _, child in container:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	table.sort(toasts, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	if #toasts >= MAX_VISIBLE then
		toasts[1]:Destroy()
	end

	nextOrder += 1
	local toast = Instance.new("Frame")
	toast.LayoutOrder = nextOrder
	toast.Size = UDim2.new(1, 0, 0, 40)
	toast.BackgroundColor3 = UiKit.Colors.Panel
	toast.BackgroundTransparency = 0.1
	toast.BorderSizePixel = 0
	toast.Parent = container
	UiKit.corner(toast, 10)
	UiKit.stroke(toast, KIND_COLOR[kind or "info"] or UiKit.Colors.Gold, 2)
	local label = UiKit.label(toast, message, UDim2.new(1, -20, 1, 0), UDim2.fromOffset(10, 0), UiKit.Colors.Text, 16)
	label.TextXAlignment = Enum.TextXAlignment.Center

	task.delay(SHOW_TIME, function()
		if not toast.Parent then
			return
		end
		local fade = TweenInfo.new(0.3)
		TweenService:Create(toast, fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
		local stroke = toast:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
		end
		task.wait(0.3)
		toast:Destroy()
	end)
end

-- 클라이언트 시작 시 한 번 호출
function NotifyController.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "NotifyGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 70)
	frame.Size = UDim2.new(0.4, 0, 0, 200)
	frame.BackgroundTransparency = 1
	frame.Parent = gui
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(280, 0)
	constraint.MaxSize = Vector2.new(520, math.huge)
	constraint.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	container = frame

	Remotes.get(Remotes.Names.Notify).OnClientEvent:Connect(NotifyController.show)
end

return NotifyController
