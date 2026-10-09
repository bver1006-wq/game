--!strict
-- NPC 상점 UI. NPC의 ProximityPrompt(속성 ShopId)를 누르면 그 상점 창을 연다.
-- 위쪽 탭은 큰 그림 버튼(대표 아이템 3D 아이콘 + 아래 짧은 이름, ShopDefs의 Icon). 누르면 그 목록이 보인다 (2026-10-09)
-- 도구·무기·장비 줄: 결과 아이콘·이름·별 + 조합식 그림(아래 단계 3개·재료·골드, 가진 수/필요 수 초록·빨강) + 만들기/사기 버튼
-- 아이콘을 한 번 누르면 아이템 상세 창(ItemDetailUI)이 뜬다
-- 창 바깥을 누르거나 NPC에서 멀어지면 닫힌다.
-- 버튼은 서버에 "무엇을 하겠다"만 보내고(ShopAction), 결과는 가방 변화와 알림으로 돌아온다.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local EquipmentDefs = require(ReplicatedStorage.Shared.EquipmentDefs)
local ItemDefs = require(ReplicatedStorage.Shared.ItemDefs)
local PickaxeDefs = require(ReplicatedStorage.Shared.PickaxeDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ShopDefs = require(ReplicatedStorage.Shared.ShopDefs)
local InventoryState = require(script.Parent.InventoryState)
local ItemDetailUI = require(script.Parent.ItemDetailUI)
local ItemIcon = require(script.Parent.ItemIcon)
local RecipeView = require(script.Parent.RecipeView)
local UiKit = require(script.Parent.UiKit)

-- 탭별 종류: 도구·무기 탭은 PickaxeDefs의 Kind, 장비 탭은 EquipmentDefs의 칸
local TOOL_TABS: { [string]: boolean } = { Pickaxe = true, Axe = true, Sword = true, Bow = true, Club = true }
local EQUIPMENT_TABS: { [string]: { string } } = {
	Helmet = { "Helmet" },
	Armor = { "Armor" },
	Boots = { "Boots" },
	Gloves = { "Gloves" },
	Accessory = { "Necklace", "Bracelet" },
}
-- 종류별 티어 속성 (서버 PickaxeService가 기록)
local TIER_ATTRIBUTE: { [string]: string } = { Pickaxe = "PickaxeTier", Axe = "AxeTier", Sword = "SwordTier", Bow = "BowTier", Club = "ClubTier" }
-- 탭 버튼 크기 (넓은 창 / 좁은 창)
type TabSize = { Width: number, Height: number, Icon: number }
local TAB_SIZE: TabSize = { Width = 76, Height = 86, Icon = 56 }
local TAB_SIZE_COMPACT: TabSize = { Width = 62, Height = 66, Icon = 42 }
local COMPACT_HEIGHT = 430 -- 창 높이가 이보다 작으면 인사말을 숨기고 탭을 줄인다 (휴대폰 가로 화면)
local FIRST_TIER_BULK = 3 -- 1단계는 "3개" 버튼으로 한 번에 (조합에 3개가 필요하니까)
local CLOSE_DISTANCE_MARGIN = 4 -- 상호작용 거리보다 이만큼 멀어지면 창을 닫는다
local ROW_ICON = 64 -- 목록 줄 결과 아이콘 크기
local BUTTON_WIDTH = 96
local WIDE_ROW = 470 -- 목록 너비가 이보다 넓으면 조합식 그림을 이름 옆에, 좁으면 아래 줄 전체에

local localPlayer = Players.LocalPlayer

local ShopUI = {}

local shopRemote: RemoteEvent
local panel: Frame
local backdrop: TextButton
local titleLabel: TextLabel
local greetingLabel: TextLabel
local tabBar: ScrollingFrame
local content: ScrollingFrame

local currentShop: ShopDefs.ShopDef? = nil
local currentTab: ShopDefs.ShopTab? = nil
local currentPrompt: ProximityPrompt? = nil
local compact = false
local wideRows = false

-- 서버에 상점 요청을 보낸다
local function send(action: string, ...: any)
	if currentShop then
		shopRemote:FireServer(currentShop.Id, action, ...)
	end
end

-- 아이콘 상자 (itemId가 nil이면 가방 그림). 아이템이면 누르면 상세 창이 뜬다
local function iconBox(row: GuiObject, itemId: string?, size: number, position: UDim2?): GuiObject
	local box = Instance.new("TextButton")
	box.Text = ""
	box.AutoButtonColor = itemId ~= nil
	box.Size = UDim2.fromOffset(size, size)
	box.Position = position or UDim2.new(0, 8, 0.5, -size / 2)
	box.BackgroundColor3 = UiKit.Colors.Panel
	box.BorderSizePixel = 0
	box.Parent = row
	UiKit.corner(box, 8)
	local inner = Instance.new("Frame")
	inner.Size = UDim2.new(1, -6, 1, -6)
	inner.Position = UDim2.fromOffset(3, 3)
	inner.BackgroundTransparency = 1
	inner.Parent = box
	if itemId then
		ItemIcon.create(inner, itemId)
		local id = itemId
		box.Activated:Connect(function()
			ItemDetailUI.open(id)
		end)
	else
		UiKit.bagIcon(inner)
	end
	return box
end

-- 아이콘 오른쪽 아래 가진 개수 ("x2")
local function countBadge(icon: GuiObject, count: number)
	if count <= 0 then
		return
	end
	local badge = UiKit.label(icon, `x{count}`, UDim2.new(1, -4, 0, 18), UDim2.new(0, 0, 1, -19), Color3.new(1, 1, 1), 15)
	badge.TextXAlignment = Enum.TextXAlignment.Right
	badge.ZIndex = 3
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = badge
end

-- 키가 저절로 늘어나는 목록 줄 (height는 최소 높이)
local function autoRow(order: number, height: number): Frame
	local row = UiKit.row(content, height, order)
	row.AutomaticSize = Enum.AutomaticSize.Y
	local padding = Instance.new("UIPadding")
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = row
	return row
end

-- 목록 영역을 비운다
local function clearContent()
	for _, child in content:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- 목록 안 작은 제목 줄
local function sectionHeader(text: string, order: number)
	local header = UiKit.row(content, 30, order)
	header.BackgroundTransparency = 1
	UiKit.label(header, text, UDim2.new(1, -10, 1, 0), UDim2.fromOffset(6, 0), UiKit.Colors.Gold, 15)
end

-- 조합식 한 줄. 넓은 창: [결과 아이콘] 이름 ★ + 조합식 그림 | 오른쪽 버튼
-- 좁은 창(휴대폰): 위 [아이콘] 이름, 가운데 조합식 그림(줄 전체), 아래 버튼
-- buttons: { 글자, 누르면 할 일, 누를 수 있는지 } 목록 (첫 번째가 큰 버튼)
type RowButton = { Text: string, OnClick: () -> (), Enabled: boolean }
local function recipeRow(order: number, itemId: string, title: string, recipe: RecipeView.RecipeLike, buttons: { RowButton }, note: string?)
	local wide = content.AbsoluteSize.X >= WIDE_ROW
	local row = autoRow(order, ROW_ICON + 16)
	-- 이름·설명은 아이콘 오른쪽
	local function header(parent: GuiObject, rightMargin: number)
		local icon = iconBox(parent, itemId, ROW_ICON, UDim2.fromOffset(8, 8))
		countBadge(icon, InventoryState.count(itemId))
		local width = UDim2.new(1, -(ROW_ICON + 18 + rightMargin), 0, 24)
		local nameLabel = UiKit.label(parent, title, width, UDim2.fromOffset(ROW_ICON + 18, 6), UiKit.Colors.Text, 17)
		nameLabel.TextScaled = true
		local nameLimit = Instance.new("UITextSizeConstraint")
		nameLimit.MaxTextSize = 17
		nameLimit.Parent = nameLabel
		if note then
			UiKit.label(parent, note, width, UDim2.fromOffset(ROW_ICON + 18, 30), UiKit.Colors.SubText, 12)
		end
	end

	if wide then
		local rightMargin = BUTTON_WIDTH + 16
		header(row, rightMargin)
		RecipeView.chips(row, recipe, UDim2.fromOffset(ROW_ICON + 18, if note then 50 else 34), UDim.new(1, -(ROW_ICON + 18 + rightMargin)), ItemDetailUI.open)
		-- 버튼: 오른쪽 위에 세로로
		local y = 8
		for index, info in buttons do
			local height = if index == 1 then 44 else 34
			local button = UiKit.button(row, info.Text, UDim2.fromOffset(BUTTON_WIDTH, height), UDim2.new(1, -(BUTTON_WIDTH + 8), 0, y), info.OnClick, info.Enabled)
			button.TextSize = if index == 1 then 17 else 14
			y += height + 6
		end
		-- 버튼이 조합식 그림보다 길면 줄 높이를 버튼에 맞춘다
		local spacer = Instance.new("Frame")
		spacer.BackgroundTransparency = 1
		spacer.Size = UDim2.fromOffset(1, 1)
		spacer.Position = UDim2.fromOffset(0, y - 7)
		spacer.Parent = row
		return
	end

	-- 좁은 창: 위에서 아래로 쌓는다
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = row
	local top = Instance.new("Frame")
	top.BackgroundTransparency = 1
	top.Size = UDim2.new(1, 0, 0, ROW_ICON + 12)
	top.LayoutOrder = 1
	top.Parent = row
	header(top, 8)
	local middle = Instance.new("Frame")
	middle.BackgroundTransparency = 1
	middle.Size = UDim2.new(1, 0, 0, 0)
	middle.AutomaticSize = Enum.AutomaticSize.Y
	middle.LayoutOrder = 2
	middle.Parent = row
	RecipeView.chips(middle, recipe, UDim2.fromOffset(8, 0), UDim.new(1, -16), ItemDetailUI.open)
	local bottom = Instance.new("Frame")
	bottom.BackgroundTransparency = 1
	bottom.Size = UDim2.new(1, -16, 0, 44)
	bottom.LayoutOrder = 3
	bottom.Parent = row
	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	buttonLayout.Padding = UDim.new(0, 8)
	buttonLayout.SortOrder = Enum.SortOrder.LayoutOrder
	buttonLayout.Parent = bottom
	for index, info in buttons do
		local button = UiKit.button(bottom, info.Text, UDim2.fromOffset(BUTTON_WIDTH + (if index == 1 then 10 else 0), 44), nil, info.OnClick, info.Enabled)
		button.TextSize = if index == 1 then 17 else 14
		button.LayoutOrder = index
	end
end

-- 별 글자 ("★★☆☆")
local function stars(tier: number): string
	return string.rep("★", tier) .. string.rep("☆", 4 - tier)
end

-- 조합식 줄 하나 (도구·무기·장비 공통). 1단계는 사기(1개·3개), 2단계부터 만들기
local function craftRow(order: number, itemId: string, tier: number)
	local recipe = Config.Recipes[itemId]
	if not recipe then
		return
	end
	local def = ItemDefs.Items[itemId]
	local title = `{def.DisplayName}  {stars(tier)}`
	local buttons: { RowButton }
	if recipe.From then
		local can = RecipeView.canAfford(recipe)
		buttons = {
			{ Text = if can then "만들기" else "부족", OnClick = function()
				send("Craft", itemId, 1)
			end, Enabled = can },
		}
	else
		local times = RecipeView.timesAffordable(recipe, FIRST_TIER_BULK)
		buttons = {
			{ Text = if times >= 1 then "사기" else "부족", OnClick = function()
				send("Craft", itemId, 1)
			end, Enabled = times >= 1 },
			{ Text = `{FIRST_TIER_BULK}개 사기`, OnClick = function()
				send("Craft", itemId, FIRST_TIER_BULK)
			end, Enabled = times >= FIRST_TIER_BULK },
		}
	end
	local note = if recipe.From then `{ItemDefs.Items[recipe.From.Id].DisplayName} {recipe.From.Count}개로 만들어요` else nil
	recipeRow(order, itemId, title, recipe, buttons, note)
end

-- 도구·무기 탭: 그 종류 1~4단계
local function drawTools(kind: string)
	local list: { PickaxeDefs.PickaxeDef } = {}
	for _, def in PickaxeDefs do
		if def.Kind == kind then
			table.insert(list, def)
		end
	end
	table.sort(list, function(a, b)
		return a.Tier < b.Tier
	end)
	for order, def in list do
		craftRow(order, def.Id, def.Tier)
	end
end

-- 장비 탭: 칸 목록(slots)의 장비를 칸·단계 순서로
local function drawEquipment(slots: { string })
	local order = 0
	for _, slot in slots do
		if #slots > 1 then
			order += 1
			for _, info in EquipmentDefs.Slots do
				if info.Id == slot then
					sectionHeader(info.Title, order)
				end
			end
		end
		for _, itemId in EquipmentDefs.Order do
			local def = EquipmentDefs.Items[itemId]
			if def.Slot == slot then
				order += 1
				craftRow(order, itemId, def.Tier)
			end
		end
	end
end

-- 활 탭 아래: 화살통 (방패 칸, 등에 멘다). 화살을 다 쓰면 사라져서 여러 개 살 수 있다
local function drawQuivers(startOrder: number)
	sectionHeader("화살통 — 활은 화살이 있어야 쏴요", startOrder)
	for index, itemId in EquipmentDefs.QuiverOrder do
		local def = EquipmentDefs.Items[itemId]
		local quiver = (Config.Quiver.Items :: any)[itemId]
		if quiver then
			local recipe: RecipeView.RecipeLike = { Items = quiver.Price.Items, Gold = quiver.Price.Gold }
			local can = RecipeView.canAfford(recipe)
			recipeRow(startOrder + index, itemId, def.DisplayName, recipe, {
				{ Text = if can then "사기" else "부족", OnClick = function()
					send("BuyQuiver", itemId)
				end, Enabled = can },
			}, `화살 {quiver.Arrows}개`)
		end
	end
end

-- 제련 탭: 레시피마다 재료·수수료 그림과 "1개 / 최대" 버튼
local function drawSmelt()
	for order, recipeId in Config.Smelting.Order do
		local smelt = Config.Smelting.Recipes[recipeId]
		local recipe: RecipeView.RecipeLike = { Items = smelt.Inputs :: any, Gold = smelt.Fee }
		local possible = RecipeView.timesAffordable(recipe, 999)
		recipeRow(order, recipeId, ItemDefs.Items[recipeId].DisplayName, recipe, {
			{ Text = "1개", OnClick = function()
				send("Smelt", recipeId, 1)
			end, Enabled = possible >= 1 },
			{ Text = if possible >= 1 then `최대 {possible}` else "최대", OnClick = function()
				send("Smelt", recipeId, possible)
			end, Enabled = possible >= 1 },
		})
	end
end

-- 팔기 탭: 가진 광석·괴와 가격, "1개 / 모두" 버튼
local function drawSell()
	local order = 1
	local sellableTotal = 0
	for _, itemId in ItemDefs.Order do
		local count = InventoryState.count(itemId)
		local price = Config.SellPrices[itemId]
		if count > 0 and price then
			order += 1
			sellableTotal += count * price
			local def = ItemDefs.Items[itemId]
			local row = UiKit.row(content, 56, order)
			iconBox(row, itemId, 44)
			UiKit.label(row, `{def.DisplayName} x{count}`, UDim2.new(1, -270, 1, 0), UDim2.fromOffset(60, 0), UiKit.Colors.Text, 16)
			UiKit.label(row, `개당 {price}G`, UDim2.fromOffset(70, 56), UDim2.new(1, -240, 0, 0), UiKit.Colors.Gold, 14)
			UiKit.button(row, "1개", UDim2.fromOffset(64, 34), UDim2.new(1, -160, 0, 7), function()
				send("Sell", itemId, 1)
			end)
			UiKit.button(row, "모두", UDim2.fromOffset(84, 34), UDim2.new(1, -90, 0, 7), function()
				send("Sell", itemId, nil)
			end)
		end
	end

	local header = UiKit.row(content, 48, 1)
	header.BackgroundTransparency = 1
	UiKit.button(header, if sellableTotal > 0 then `전부 팔기 (+{sellableTotal}G)` else "팔 물건이 없어요", UDim2.new(1, 0, 0, 40), UDim2.fromOffset(0, 4), function()
		send("SellAll")
	end, sellableTotal > 0)
end

-- 잡화 탭: 상인이 파는 물건 (귀환 주문서 등)
local function drawBuy()
	local gold = InventoryState.get().Gold
	for order, goods in Config.MerchantGoods do
		local def = ItemDefs.Items[goods.ItemId]
		local row = UiKit.row(content, 64, order)
		iconBox(row, goods.ItemId, 52)
		UiKit.label(row, def.DisplayName, UDim2.new(1, -280, 0, 24), UDim2.fromOffset(68, 8), UiKit.Colors.Text, 16)
		UiKit.label(row, `{goods.Price}G  ·  가진 개수 {InventoryState.count(goods.ItemId)}`, UDim2.new(1, -280, 0, 22), UDim2.fromOffset(68, 32), UiKit.Colors.SubText, 13)
		UiKit.button(row, "1개", UDim2.fromOffset(64, 38), UDim2.new(1, -160, 0, 9), function()
			send("Buy", goods.ItemId, 1)
		end, gold >= goods.Price)
		UiKit.button(row, "5개", UDim2.fromOffset(84, 38), UDim2.new(1, -90, 0, 9), function()
			send("Buy", goods.ItemId, 5)
		end, gold >= goods.Price * 5)
	end
end

-- 가방 탭: 다음 가방 확장과 가격
local function drawBag()
	local snapshot = InventoryState.get()
	local row = UiKit.row(content, 64, 1)
	UiKit.label(row, `지금 가방: {snapshot.Slots}칸`, UDim2.new(1, -20, 1, 0), UDim2.fromOffset(12, 0), UiKit.Colors.Text, 17)
	for order, upgrade in Config.Inventory.BagUpgrades do
		local level = order
		local owned = snapshot.BagLevel >= level
		local isNext = snapshot.BagLevel + 1 == level
		local upgradeRow = UiKit.row(content, 68, order + 1)
		iconBox(upgradeRow, nil, 54)
		UiKit.label(upgradeRow, upgrade.Name, UDim2.new(1, -200, 0, 24), UDim2.fromOffset(70, 8), UiKit.Colors.Text, 17)
		UiKit.label(upgradeRow, `{upgrade.Slots}칸  ·  {upgrade.Price}G`, UDim2.new(1, -200, 0, 30), UDim2.fromOffset(70, 32), UiKit.Colors.SubText, 13)
		local status = if owned then "보유 중" elseif not isNext then "이전 가방 먼저" elseif snapshot.Gold >= upgrade.Price then "구매" else "골드 부족"
		UiKit.button(upgradeRow, status, UDim2.fromOffset(110, 40), UDim2.new(1, -120, 0, 12), function()
			send("BuyBag")
		end, isNext and snapshot.Gold >= upgrade.Price)
	end
end

-- 준비 중 탭
local function drawComingSoon(tab: ShopDefs.ShopTab)
	local row = UiKit.row(content, 90, 1)
	local label = UiKit.label(row, tab.Note or "준비 중이에요.", UDim2.new(1, -20, 1, 0), UDim2.fromOffset(10, 0), UiKit.Colors.SubText, 16)
	label.TextXAlignment = Enum.TextXAlignment.Center
end

-- 지금 탭 내용을 다시 그린다 (가방이 바뀌면 다시 호출). 스크롤 위치는 그대로 둔다
local function redraw()
	if not currentShop or not currentTab then
		return
	end
	local scroll = content.CanvasPosition
	clearContent()
	local tabId = currentTab.Id
	if tabId == "Smelt" then
		drawSmelt()
	elseif TOOL_TABS[tabId] then
		drawTools(tabId)
		if tabId == "Bow" then
			drawQuivers(100)
		end
	elseif EQUIPMENT_TABS[tabId] then
		drawEquipment(EQUIPMENT_TABS[tabId])
	elseif tabId == "Sell" then
		drawSell()
	elseif tabId == "Bag" then
		drawBag()
	elseif tabId == "Buy" then
		drawBuy()
	else
		drawComingSoon(currentTab)
	end
	content.CanvasPosition = scroll
end

-- 탭 그림 (아이템 아이콘, "@Bag" 가방, "@Coin" 금화)
local function drawTabIcon(holder: Frame, icon: string)
	if icon == "@Bag" then
		UiKit.bagIcon(holder)
	elseif icon == "@Coin" then
		UiKit.coinIcon(holder)
	else
		ItemIcon.create(holder, icon)
	end
end

-- 탭 버튼을 그린다: 큰 그림 + 아래 짧은 이름. 고른 탭은 밝은 바탕 + 금색 테두리 + 살짝 크게
local function drawTabs()
	for _, child in tabBar:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local shop = currentShop
	if not shop then
		return
	end
	local size = if compact then TAB_SIZE_COMPACT else TAB_SIZE
	for index, tab in shop.Tabs do
		local selected = tab == currentTab
		local button = Instance.new("TextButton")
		button.Name = tab.Id
		button.Text = ""
		button.AutoButtonColor = not selected
		button.LayoutOrder = index
		button.Size = UDim2.fromOffset(size.Width, size.Height)
		button.BackgroundColor3 = if selected then UiKit.Colors.Button else UiKit.Colors.PanelLight
		button.BorderSizePixel = 0
		button.Parent = tabBar
		UiKit.corner(button, 10)
		if selected then
			UiKit.stroke(button, UiKit.Colors.Gold, 3)
		end
		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.fromOffset(size.Icon, size.Icon)
		holder.Position = UDim2.new(0.5, -size.Icon / 2, 0, 3)
		holder.Parent = button
		drawTabIcon(holder, tab.Icon)
		local label = UiKit.label(button, tab.Title, UDim2.new(1, -4, 0, 18), UDim2.new(0, 2, 1, -20), if selected then Color3.new(1, 1, 1) else UiKit.Colors.Text, 14)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextWrapped = false
		label.TextScaled = true
		local labelLimit = Instance.new("UITextSizeConstraint")
		labelLimit.MaxTextSize = 14
		labelLimit.Parent = label
		button.Activated:Connect(function()
			if currentTab ~= tab then
				currentTab = tab
				content.CanvasPosition = Vector2.zero
				drawTabs()
				redraw()
			end
		end)
	end
end

-- 창 크기에 맞춰 인사말·탭 크기·목록 위치를 정한다 (작은 화면이면 촘촘하게)
local function applyLayout()
	local nextCompact = panel.AbsoluteSize.Y < COMPACT_HEIGHT
	local size = if nextCompact then TAB_SIZE_COMPACT else TAB_SIZE
	greetingLabel.Visible = not nextCompact
	local tabTop = if nextCompact then 44 else 84
	tabBar.Position = UDim2.fromOffset(10, tabTop)
	tabBar.Size = UDim2.new(1, -20, 0, size.Height + 10)
	local contentTop = tabTop + size.Height + 16
	content.Position = UDim2.fromOffset(14, contentTop)
	content.Size = UDim2.new(1, -24, 1, -(contentTop + 10))
	if nextCompact ~= compact then
		compact = nextCompact
		drawTabs()
	end
	-- 목록 너비가 기준을 넘나들면 줄 모양(넓은·좁은)을 바꿔 다시 그린다
	local nextWide = content.AbsoluteSize.X >= WIDE_ROW
	if nextWide ~= wideRows then
		wideRows = nextWide
		redraw()
	end
end

-- 상점 창을 닫는다
function ShopUI.close()
	panel.Visible = false
	backdrop.Visible = false
	currentShop = nil
	currentTab = nil
	currentPrompt = nil
	ItemDetailUI.close()
end

-- 상점 창을 연다
function ShopUI.open(shopId: string, prompt: ProximityPrompt?)
	local shop = ShopDefs[shopId]
	if not shop then
		return
	end
	currentShop = shop
	currentTab = shop.Tabs[1]
	currentPrompt = prompt
	titleLabel.Text = shop.NpcName
	greetingLabel.Text = shop.Greeting
	panel.Visible = true
	backdrop.Visible = true
	content.CanvasPosition = Vector2.zero
	tabBar.CanvasPosition = Vector2.zero
	applyLayout()
	drawTabs()
	redraw()
end

-- NPC에서 멀어지면 창을 닫는다
local function checkDistance()
	local prompt = currentPrompt
	if not panel.Visible or not prompt then
		return
	end
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local promptPart = prompt.Parent
	if not root or not root:IsA("BasePart") or not promptPart or not promptPart:IsA("BasePart") then
		ShopUI.close()
		return
	end
	if (root.Position - promptPart.Position).Magnitude > Config.Npc.InteractDistance + CLOSE_DISTANCE_MARGIN then
		ShopUI.close()
	end
end

-- 클라이언트 시작 시 한 번 호출
function ShopUI.init()
	shopRemote = Remotes.get(Remotes.Names.ShopAction)

	local gui = Instance.new("ScreenGui")
	gui.Name = "ShopGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

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
	backdrop.Activated:Connect(ShopUI.close)

	panel = UiKit.panel(gui, UDim2.fromScale(0.92, 0.86), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	panel.ZIndex = 1
	panel.Visible = false
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(320, 280)
	constraint.MaxSize = Vector2.new(620, 600)
	constraint.Parent = panel

	titleLabel = UiKit.label(panel, "", UDim2.new(1, -70, 0, 34), UDim2.fromOffset(16, 6), UiKit.Colors.Gold, 22)
	local closeButton = UiKit.button(panel, "X", UDim2.fromOffset(40, 40), UDim2.new(1, -48, 0, 6), ShopUI.close)
	closeButton.TextSize = 20
	greetingLabel = UiKit.label(panel, "", UDim2.new(1, -32, 0, 38), UDim2.fromOffset(16, 42), UiKit.Colors.SubText, 13)

	-- 탭 줄: 넘치면 옆으로 밀어서 본다
	tabBar = Instance.new("ScrollingFrame")
	tabBar.Name = "Tabs"
	tabBar.BackgroundTransparency = 1
	tabBar.BorderSizePixel = 0
	tabBar.ScrollBarThickness = 4
	tabBar.ScrollingDirection = Enum.ScrollingDirection.X
	tabBar.AutomaticCanvasSize = Enum.AutomaticSize.X
	tabBar.CanvasSize = UDim2.new()
	tabBar.Parent = panel
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tabLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabBar
	local tabPadding = Instance.new("UIPadding")
	tabPadding.PaddingTop = UDim.new(0, 3)
	tabPadding.PaddingLeft = UDim.new(0, 3)
	tabPadding.PaddingRight = UDim.new(0, 3)
	tabPadding.Parent = tabBar

	content = UiKit.list(panel, UDim2.new(1, -24, 1, -200), UDim2.fromOffset(14, 190))
	applyLayout()
	panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local shopId = prompt:GetAttribute("ShopId")
		if typeof(shopId) == "string" then
			ShopUI.open(shopId, prompt)
		end
	end)
	InventoryState.Changed:Connect(redraw)
	for _, attribute in TIER_ATTRIBUTE do
		localPlayer:GetAttributeChangedSignal(attribute):Connect(redraw)
	end
	RunService.Heartbeat:Connect(checkDistance)
end

return ShopUI
