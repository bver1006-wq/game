--!strict
-- 가방 UI: 오른쪽 위 골드, 왼쪽 위 가방 그림 버튼(모바일에서 누르기 쉽게), 누르면 아이콘 칸 가방 창.
-- 칸마다 아이콘 아래에 아이템 이름을 쓴다.
-- 위쪽 탭(전체/무기/방어구/도구/기타)으로 분류해서 보고, 칸을 끌어서 하단 빠른 호출 칸에 놓는다.
-- 도구 칸을 누르면 바로 든다. 창 바깥을 누르거나 B 키로 닫는다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local ItemDefs = require(ReplicatedStorage.Shared.ItemDefs)
local DragController = require(script.Parent.DragController)
local HotbarController = require(script.Parent.HotbarController)
local InventoryState = require(script.Parent.InventoryState)
local CooldownController = require(script.Parent.CooldownController)
local ItemIcon = require(script.Parent.ItemIcon)
local UiKit = require(script.Parent.UiKit)

local TOGGLE_KEY = Enum.KeyCode.B
local CELL_SIZE = 66 -- 칸 너비
local CELL_HEIGHT = 84 -- 칸 높이 (아래 이름 줄 포함)
local NAME_HEIGHT = 20

local InventoryUI = {}

local goldLabel: TextLabel
local bagButton: TextButton
local bagCountLabel: TextLabel
local backdrop: TextButton
local bagPanel: Frame
local titleLabel: TextLabel
local tabBar: Frame
local grid: ScrollingFrame
local infoLabel: TextLabel
local currentTabIndex = 1

-- 칸 하나를 그린다 (entry가 nil이면 빈 칸)
local function drawCell(order: number, entry: InventoryState.SlotEntry?)
	local cell = Instance.new("TextButton")
	cell.Text = ""
	cell.AutoButtonColor = false
	cell.LayoutOrder = order
	cell.BackgroundColor3 = UiKit.Colors.PanelLight
	cell.BorderSizePixel = 0
	cell.Parent = grid
	UiKit.corner(cell, 8)
	if not entry then
		cell.BackgroundTransparency = 0.5
		return
	end

	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(1, -8, 1, -NAME_HEIGHT - 6)
	holder.Position = UDim2.fromOffset(4, 4)
	holder.BackgroundTransparency = 1
	holder.Parent = cell
	ItemIcon.create(holder, entry.ItemId)
	CooldownController.attach(cell, entry.ItemId)

	local def = ItemDefs.Items[entry.ItemId]
	-- 아이콘 아래 이름
	local nameLabel = UiKit.label(cell, def.DisplayName, UDim2.new(1, -4, 0, NAME_HEIGHT), UDim2.new(0, 2, 1, -NAME_HEIGHT - 1), UiKit.Colors.Text, 11)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.TextWrapped = false
	nameLabel.TextScaled = true
	local nameSize = Instance.new("UITextSizeConstraint")
	nameSize.MaxTextSize = 12
	nameSize.Parent = nameLabel
	if def.Stackable then
		local countLabel = UiKit.label(cell, tostring(entry.Count), UDim2.new(1, -6, 0, 16), UDim2.new(0, 0, 1, -NAME_HEIGHT - 18), Color3.new(1, 1, 1), 13)
		countLabel.TextXAlignment = Enum.TextXAlignment.Right
		countLabel.ZIndex = 3
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1.5
		stroke.Parent = countLabel
	end

	local itemId = entry.ItemId
	DragController.attach(cell, function()
		return itemId
	end, function()
		-- 누르면 이름·정보 표시, 도구면 바로 든다
		local price = Config.SellPrices[itemId]
		infoLabel.Text = `{def.DisplayName}  x{InventoryState.count(itemId)}` .. (if price then `  ·  개당 {price}G` else "")
		-- 곡괭이는 누르면 바로 든다 (소모품은 실수로 쓰지 않게 빠른 칸에서만 쓴다)
		if (def.Category == "Tool" or def.Category == "Weapon") and not def.Usable then
			HotbarController.useItem(itemId)
		end
	end, function(position, draggedId)
		local slot = HotbarController.slotAt(position)
		if slot then
			HotbarController.assign(slot, draggedId)
		end
	end)
end

-- 탭 버튼을 그린다
local function drawTabs()
	for _, child in tabBar:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local count = #ItemDefs.Tabs
	for index, tab in ItemDefs.Tabs do
		local button = UiKit.button(tabBar, tab.Title, UDim2.new(1 / count, -4, 1, 0), UDim2.new((index - 1) / count, 2, 0, 0), function()
			currentTabIndex = index
			drawTabs()
			InventoryUI.refresh()
		end)
		button.TextSize = 14
		if index ~= currentTabIndex then
			button.BackgroundColor3 = UiKit.Colors.PanelLight
		end
	end
end

-- 가방 내용을 다시 그린다
function InventoryUI.refresh()
	local snapshot = InventoryState.get()
	local used = InventoryState.usedSlots()
	goldLabel.Text = `{snapshot.Gold} G`
	bagCountLabel.Text = `{used}/{snapshot.Slots}`
	bagCountLabel.TextColor3 = if used >= snapshot.Slots then UiKit.Colors.Bad else Color3.new(1, 1, 1)
	titleLabel.Text = `가방  {used}/{snapshot.Slots}칸`

	for _, child in grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local tab = ItemDefs.Tabs[currentTabIndex]
	local entries = InventoryState.entries(tab.Category)
	for order, entry in entries do
		drawCell(order, entry)
	end
	-- 전체 탭에서는 남은 빈 칸도 보여준다
	if tab.Category == nil then
		for order = #entries + 1, snapshot.Slots do
			drawCell(order, nil)
		end
	elseif #entries == 0 then
		local empty = UiKit.label(grid, "이 분류에는 아이템이 없어요.", UDim2.new(1, 0, 0, 30), nil, UiKit.Colors.SubText, 14)
		empty.TextXAlignment = Enum.TextXAlignment.Center
	end
end

-- 가방 창 열고 닫기
function InventoryUI.setOpen(open: boolean)
	bagPanel.Visible = open
	backdrop.Visible = open
	if open then
		infoLabel.Text = "칸을 끌어서 아래 빠른 칸에 놓으세요. 도구는 누르면 바로 들어요."
		InventoryUI.refresh()
	end
end

-- 가방 창 토글
function InventoryUI.toggle()
	InventoryUI.setOpen(not bagPanel.Visible)
end

-- 클라이언트 시작 시 한 번 호출
function InventoryUI.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "InventoryGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- 창 바깥을 누르면 닫히게 하는 투명 배경 (창보다 아래)
	backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.6
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = 0
	backdrop.Visible = false
	backdrop.Parent = gui
	backdrop.Activated:Connect(function()
		InventoryUI.setOpen(false)
	end)

	-- 골드 (오른쪽 위, 체력·마나 바 아래)
	local goldPanel = UiKit.panel(gui, UDim2.fromOffset(150, 40), UDim2.new(1, -16, 0, 172), Vector2.new(1, 0))
	UiKit.swatch(goldPanel, UiKit.Colors.Gold, 20, UDim2.fromOffset(12, 10))
	goldLabel = UiKit.label(goldPanel, "0 G", UDim2.new(1, -46, 1, 0), UDim2.fromOffset(40, 0), UiKit.Colors.Gold, 18)

	-- 가방 버튼 (왼쪽 위, 네모 테두리 없이 가방 그림만 + 아래 칸 수). Roblox 상단 메뉴 바로 아래
	bagButton = Instance.new("TextButton")
	bagButton.Name = "BagButton"
	bagButton.Text = ""
	bagButton.AutoButtonColor = false
	bagButton.BackgroundTransparency = 1
	bagButton.Size = UDim2.fromOffset(72, 84)
	bagButton.Position = UDim2.fromOffset(16, 12)
	bagButton.ZIndex = 2
	bagButton.Parent = gui
	local bagArt = Instance.new("Frame")
	bagArt.BackgroundTransparency = 1
	bagArt.Size = UDim2.fromOffset(64, 60)
	bagArt.Position = UDim2.fromOffset(4, 0)
	bagArt.Parent = bagButton
	UiKit.bagIcon(bagArt)
	bagCountLabel = UiKit.label(bagButton, "", UDim2.new(1, 0, 0, 22), UDim2.new(0, 0, 1, -24), Color3.new(1, 1, 1), 15)
	bagCountLabel.TextXAlignment = Enum.TextXAlignment.Center
	local countStroke = Instance.new("UIStroke") -- 테두리가 없어도 글자가 잘 보이게
	countStroke.Thickness = 2
	countStroke.Parent = bagCountLabel
	-- 마우스를 올리면 살짝 커진다
	local bagScale = Instance.new("UIScale")
	bagScale.Parent = bagButton
	bagButton.MouseEnter:Connect(function()
		bagScale.Scale = 1.08
	end)
	bagButton.MouseLeave:Connect(function()
		bagScale.Scale = 1
	end)
	bagButton.Activated:Connect(InventoryUI.toggle)

	-- 가방 창 (가운데 위쪽). 화면이 작으면 높이를 줄여서 하단 빠른 칸을 가리지 않게
	bagPanel = UiKit.panel(gui, UDim2.new(0, 5 * (CELL_SIZE + 6) + 34, 1, -210), UDim2.new(0.5, 0, 0, 56), Vector2.new(0.5, 0))
	bagPanel.ZIndex = 1
	bagPanel.Visible = false
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(math.huge, 430)
	constraint.Parent = bagPanel
	titleLabel = UiKit.label(bagPanel, "가방", UDim2.new(1, -60, 0, 32), UDim2.fromOffset(14, 6), UiKit.Colors.Gold, 19)
	UiKit.button(bagPanel, "X", UDim2.fromOffset(30, 30), UDim2.new(1, -38, 0, 7), function()
		InventoryUI.setOpen(false)
	end)

	tabBar = Instance.new("Frame")
	tabBar.Size = UDim2.new(1, -20, 0, 30)
	tabBar.Position = UDim2.fromOffset(10, 44)
	tabBar.BackgroundTransparency = 1
	tabBar.Parent = bagPanel

	grid = Instance.new("ScrollingFrame")
	grid.Size = UDim2.new(1, -16, 1, -128)
	grid.Position = UDim2.fromOffset(10, 82)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 6
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.Parent = bagPanel
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CELL_SIZE, CELL_HEIGHT)
	layout.CellPadding = UDim2.fromOffset(6, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	infoLabel = UiKit.label(bagPanel, "", UDim2.new(1, -24, 0, 36), UDim2.new(0, 12, 1, -42), UiKit.Colors.SubText, 13)

	drawTabs()
	InventoryState.Changed:Connect(InventoryUI.refresh)
	InventoryUI.refresh()

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == TOGGLE_KEY then
			InventoryUI.toggle()
		end
	end)
end

return InventoryUI
