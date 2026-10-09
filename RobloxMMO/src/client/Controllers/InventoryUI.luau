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
local EquipmentDefs = require(ReplicatedStorage.Shared.EquipmentDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ItemIcon = require(script.Parent.ItemIcon)
local UiKit = require(script.Parent.UiKit)

local TOGGLE_KEY = Enum.KeyCode.B
local CELL_SIZE = 66 -- 칸 너비
local localPlayer = Players.LocalPlayer
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
local equipPanel: Frame
local equipRows: { [string]: { Icon: Frame, Name: TextLabel } } = {}
local powerLabel: TextLabel
local statsLabel: TextLabel
local lastClickId: string? = nil
local lastClickTime = 0
local DOUBLE_CLICK = 0.4 -- 이 시간 안에 두 번 누르면 더블클릭(초)

-- 이 아이템을 지금 끼우고 있는지 (장비 칸 또는 손에 든 도구·무기)
local function isEquipped(itemId: string): boolean
	for _, slot in EquipmentDefs.Slots do
		if localPlayer:GetAttribute(`Equip_{slot.Id}`) == itemId then
			return true
		end
	end
	return false
end

-- 더블클릭: 장비는 끼우고(이미 끼웠으면 뺀다), 도구·무기는 손에 든다
local function activate(itemId: string)
	local def = ItemDefs.Items[itemId]
	local equipment = EquipmentDefs.Items[itemId]
	if equipment then
		if localPlayer:GetAttribute(`Equip_{equipment.Slot}`) == itemId then
			Remotes.get(Remotes.Names.UnequipSlot):FireServer(equipment.Slot)
		else
			Remotes.get(Remotes.Names.EquipItem):FireServer(itemId)
		end
	elseif def and (def.Category == "Tool" or def.Category == "Weapon") and not def.Usable then
		HotbarController.useItem(itemId)
	end
end

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
	-- 끼우고 있는 장비·들고 있는 도구는 금색 테두리 + "E"
	if isEquipped(entry.ItemId) then
		UiKit.stroke(cell, UiKit.Colors.Gold, 2.5)
		local badge = UiKit.label(cell, "E", UDim2.fromOffset(16, 16), UDim2.fromOffset(3, 2), UiKit.Colors.Gold, 13)
		badge.ZIndex = 4
	end

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
		-- 장착 아이템은 더블클릭해야 장착된다 (소모품은 실수로 쓰지 않게 빠른 칸에서만 쓴다)
		local now = os.clock()
		if lastClickId == itemId and now - lastClickTime <= DOUBLE_CLICK then
			lastClickId = nil
			activate(itemId)
		else
			lastClickId = itemId
			lastClickTime = now
			if EquipmentDefs.Items[itemId] or def.Category == "Tool" or def.Category == "Weapon" then
				infoLabel.Text ..= "  ·  더블클릭: 장착"
			end
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

-- 장비 창을 다시 그린다 (속성 Equip_<칸>·Stat*·CombatPower)
local function refreshEquipment()
	if not equipPanel then
		return
	end
	for slotId, row in equipRows do
		for _, child in row.Icon:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local itemId = localPlayer:GetAttribute(`Equip_{slotId}`)
		if typeof(itemId) == "string" and itemId ~= "" and ItemDefs.Items[itemId] then
			ItemIcon.create(row.Icon, itemId)
			row.Name.Text = ItemDefs.Items[itemId].DisplayName
			if slotId == "Shield" then
				-- 화살통: 남은 화살 수 (서버가 센 속성 Arrows)
				local arrows = localPlayer:GetAttribute("Arrows")
				row.Name.Text ..= `  🏹{if typeof(arrows) == "number" then arrows else 0}`
			end
		else
			row.Name.Text = "-"
		end
	end
	local function stat(name: string): number
		local value = localPlayer:GetAttribute(name)
		return if typeof(value) == "number" then value else 0
	end
	powerLabel.Text = `전투력 {stat("CombatPower")}`
	statsLabel.Text = `공격 {stat("StatAtk")}  방어 {stat("StatDef")}\n체력 +{stat("StatHp")}  치명타 +{stat("StatCrit")}%`
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
	equipPanel.Visible = open
	backdrop.Visible = open
	if open then
		infoLabel.Text = "칸을 끌어서 아래 빠른 칸에 놓으세요. 도구·무기·장비는 더블클릭하면 장착해요."
		refreshEquipment()
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

	-- 장비 창 (가방 창 왼쪽): 칸 8개(EquipmentDefs.Slots), 전투력, 능력치. 장비 칸을 더블클릭하면 뺀다
	-- 칸 수에 맞춰 높이를 정한다 (8칸이면 한 칸 42px 간격)
	local bagWidth = 5 * (CELL_SIZE + 6) + 34
	local ROW_STEP = 42
	local ROW_HEIGHT = 39
	local slotCount = #EquipmentDefs.Slots
	equipPanel = UiKit.panel(gui, UDim2.fromOffset(200, 58 + slotCount * ROW_STEP + 42), UDim2.new(0.5, -bagWidth / 2 - 8, 0, 56), Vector2.new(1, 0))
	equipPanel.ZIndex = 1
	equipPanel.Visible = false
	UiKit.label(equipPanel, "장비", UDim2.new(1, -20, 0, 26), UDim2.fromOffset(12, 6), UiKit.Colors.Gold, 18)
	powerLabel = UiKit.label(equipPanel, "전투력 0", UDim2.new(1, -20, 0, 22), UDim2.fromOffset(12, 32), Color3.fromRGB(255, 220, 120), 16)
	for index, slot in EquipmentDefs.Slots do
		local row = Instance.new("TextButton")
		row.Text = ""
		row.AutoButtonColor = false
		row.Size = UDim2.new(1, -16, 0, ROW_HEIGHT)
		row.Position = UDim2.fromOffset(8, 58 + (index - 1) * ROW_STEP)
		row.BackgroundColor3 = UiKit.Colors.PanelLight
		row.BorderSizePixel = 0
		row.Parent = equipPanel
		UiKit.corner(row, 8)
		local icon = Instance.new("Frame")
		icon.Size = UDim2.fromOffset(ROW_HEIGHT - 6, ROW_HEIGHT - 6)
		icon.Position = UDim2.fromOffset(3, 3)
		icon.BackgroundColor3 = UiKit.Colors.Panel
		icon.BorderSizePixel = 0
		icon.Parent = row
		UiKit.corner(icon, 6)
		UiKit.label(row, slot.Title, UDim2.new(1, -46, 0, 15), UDim2.fromOffset(42, 2), UiKit.Colors.SubText, 11)
		local name = UiKit.label(row, "-", UDim2.new(1, -46, 0, 19), UDim2.fromOffset(42, 17), UiKit.Colors.Text, 13)
		name.TextScaled = true
		local nameSize = Instance.new("UITextSizeConstraint")
		nameSize.MaxTextSize = 13
		nameSize.Parent = name
		equipRows[slot.Id] = { Icon = icon, Name = name }
		local slotId = slot.Id
		local lastRowClick = 0
		row.Activated:Connect(function()
			local now = os.clock()
			if now - lastRowClick <= DOUBLE_CLICK and slotId ~= "Weapon" then
				Remotes.get(Remotes.Names.UnequipSlot):FireServer(slotId)
			end
			lastRowClick = now
		end)
	end
	statsLabel = UiKit.label(equipPanel, "", UDim2.new(1, -16, 0, 34), UDim2.new(0, 8, 1, -40), UiKit.Colors.SubText, 12)
	statsLabel.TextWrapped = true

	drawTabs()
	InventoryState.Changed:Connect(InventoryUI.refresh)
	-- 장비가 바뀌면 장비 창과 가방 테두리(E 표시)를 다시 그린다
	localPlayer.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, 6) == "Equip_" then
			refreshEquipment()
			InventoryUI.refresh()
		elseif string.sub(name, 1, 4) == "Stat" or name == "CombatPower" or name == "Arrows" then
			refreshEquipment()
		end
	end)
	refreshEquipment()
	InventoryUI.refresh()

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == TOGGLE_KEY then
			InventoryUI.toggle()
		end
	end)
end

return InventoryUI
