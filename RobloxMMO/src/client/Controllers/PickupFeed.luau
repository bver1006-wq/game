--!strict
-- 획득 알림: 화면 왼쪽에 [아이템 그림] +7 구리 (가방 37) 를 크게 띄운다.
-- 같은 아이템을 연달아 얻으면 한 줄에 숫자만 늘어나고 통 튀어 오른다. 몇 초 뒤 사라진다.
-- 아이템 조각이 실제로 빨려 들어왔을 때(HitFeelController·CombatController) 부른다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ItemDefs = require(ReplicatedStorage.Shared.ItemDefs)
local InventoryState = require(script.Parent.InventoryState)
local ItemIcon = require(script.Parent.ItemIcon)
local UiKit = require(script.Parent.UiKit)

local SHOW_TIME = 3 -- 한 줄이 떠 있는 시간(초)
local MAX_ROWS = 4

local PickupFeed = {}

type Row = { ItemId: string, Amount: number, Frame: Frame, Label: TextLabel, Sub: TextLabel, Scale: UIScale, Token: number }

local list: Frame
local rows: { Row } = {}
local orderCounter = 0

-- 한 줄 글자 갱신
local function render(row: Row)
	if row.ItemId == "Gold" then
		row.Label.Text = `+{row.Amount} 골드`
		row.Sub.Text = `가진 골드 {InventoryState.get().Gold}`
	else
		local def = ItemDefs.Items[row.ItemId]
		row.Label.Text = `+{row.Amount} {if def then def.DisplayName else row.ItemId}`
		row.Sub.Text = `가방 {InventoryState.count(row.ItemId)}개`
	end
end

-- 줄을 몇 초 뒤 사라지게 예약 (새로 얻으면 다시 미룬다)
local function scheduleHide(row: Row)
	row.Token += 1
	local token = row.Token
	task.delay(SHOW_TIME, function()
		if row.Token ~= token or not row.Frame.Parent then
			return
		end
		TweenService:Create(row.Frame, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(row.Scale, TweenInfo.new(0.3), { Scale = 0.6 }):Play()
		task.delay(0.3, function()
			if row.Token == token then
				row.Frame:Destroy()
				local index = table.find(rows, row)
				if index then
					table.remove(rows, index)
				end
			end
		end)
	end)
end

-- 획득 알림을 띄운다. itemId가 "Gold"면 골드
function PickupFeed.show(itemId: string, amount: number)
	if amount <= 0 then
		return
	end
	for _, row in rows do
		if row.ItemId == itemId and row.Frame.Parent then
			row.Amount += amount
			render(row)
			row.Scale.Scale = 1.25 -- 통 튀어 오른다
			TweenService:Create(row.Scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			scheduleHide(row)
			return
		end
	end
	if #rows >= MAX_ROWS then
		local oldest = table.remove(rows, 1)
		if oldest then
			oldest.Frame:Destroy()
		end
	end

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(250, 56)
	frame.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	orderCounter += 1
	frame.LayoutOrder = orderCounter
	frame.Parent = list
	UiKit.corner(frame, 12)
	UiKit.stroke(frame, Color3.fromRGB(255, 215, 90), 1.5)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = frame

	local iconBox = Instance.new("Frame")
	iconBox.Size = UDim2.fromOffset(48, 48)
	iconBox.Position = UDim2.fromOffset(4, 4)
	iconBox.BackgroundTransparency = 1
	iconBox.Parent = frame
	if itemId == "Gold" then
		UiKit.swatch(iconBox, UiKit.Colors.Gold, 34, UDim2.fromOffset(7, 7))
	else
		ItemIcon.create(iconBox, itemId)
	end
	local label = UiKit.label(frame, "", UDim2.new(1, -62, 0, 30), UDim2.fromOffset(58, 3), Color3.fromRGB(255, 240, 170), 22)
	label.Font = Enum.Font.FredokaOne
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Parent = label
	local sub = UiKit.label(frame, "", UDim2.new(1, -62, 0, 18), UDim2.fromOffset(58, 33), UiKit.Colors.SubText, 13)

	local row: Row = { ItemId = itemId, Amount = amount, Frame = frame, Label = label, Sub = sub, Scale = scale, Token = 0 }
	table.insert(rows, row)
	render(row)
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	scheduleHide(row)
end

-- 클라이언트 시작 시 한 번 호출
function PickupFeed.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "PickupFeedGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 12
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	list = Instance.new("Frame")
	list.AnchorPoint = Vector2.new(0, 0.5)
	list.Position = UDim2.new(0, 16, 0.55, 0)
	list.Size = UDim2.fromOffset(260, MAX_ROWS * 62)
	list.BackgroundTransparency = 1
	list.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Parent = list
end

return PickupFeed
