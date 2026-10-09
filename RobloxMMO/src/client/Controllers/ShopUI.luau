--!strict
-- NPC 상점 UI. NPC의 ProximityPrompt(속성 ShopId)를 누르면 그 상점 창을 연다.
-- 탭: 제련(대장장이), 곡괭이(대장장이), 팔기·가방(상인), 준비 중(사냥꾼·물약).
-- 창 바깥을 누르거나 NPC에서 멀어지면 닫힌다.
-- 버튼은 서버에 "무엇을 하겠다"만 보내고(ShopAction), 결과는 가방 변화와 알림으로 돌아온다.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local ItemDefs = require(ReplicatedStorage.Shared.ItemDefs)
local PickaxeDefs = require(ReplicatedStorage.Shared.PickaxeDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ShopDefs = require(ReplicatedStorage.Shared.ShopDefs)
local InventoryState = require(script.Parent.InventoryState)
local ItemIcon = require(script.Parent.ItemIcon)
local UiKit = require(script.Parent.UiKit)

local PICKAXE_ORDER = { "CopperPickaxe", "IronPickaxe", "SteelPickaxe" }
local CLOSE_DISTANCE_MARGIN = 4 -- 상호작용 거리보다 이만큼 멀어지면 창을 닫는다

local localPlayer = Players.LocalPlayer

local ShopUI = {}

local shopRemote: RemoteEvent
local panel: Frame
local backdrop: TextButton
local titleLabel: TextLabel
local greetingLabel: TextLabel
local tabBar: Frame
local content: ScrollingFrame

local currentShop: ShopDefs.ShopDef? = nil
local currentTab: ShopDefs.ShopTab? = nil
local currentPrompt: ProximityPrompt? = nil

-- 아이템 목록을 글자로 ("구리 2, 석탄 1")
local function describeItems(items: { [string]: number }): string
	local parts = {}
	for itemId, amount in items do
		local def = ItemDefs.Items[itemId]
		table.insert(parts, `{if def then def.DisplayName else itemId} {amount}`)
	end
	return table.concat(parts, ", ")
end

-- 행 왼쪽에 아이템 아이콘 상자 (itemId가 nil이면 가방 그림)
local function iconBox(row: Frame, itemId: string?, size: number)
	local box = Instance.new("Frame")
	box.Size = UDim2.fromOffset(size, size)
	box.Position = UDim2.new(0, 8, 0.5, -size / 2)
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
	else
		UiKit.bagIcon(inner)
	end
end

-- 목록 영역을 비운다
local function clearContent()
	for _, child in content:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- 서버에 상점 요청을 보낸다
local function send(action: string, ...: any)
	if currentShop then
		shopRemote:FireServer(currentShop.Id, action, ...)
	end
end

-- 제련 탭: 레시피마다 재료·수수료와 "1개 / 최대" 버튼
local function drawSmelt()
	local gold = InventoryState.get().Gold
	for order, recipeId in Config.Smelting.Order do
		local recipe = Config.Smelting.Recipes[recipeId]
		local result = ItemDefs.Items[recipeId]
		-- 지금 재료와 골드로 몇 번 만들 수 있는지
		local possible = if recipe.Fee > 0 then math.floor(gold / recipe.Fee) else math.huge
		for itemId, amount in recipe.Inputs do
			possible = math.min(possible, math.floor(InventoryState.count(itemId) / amount))
		end

		local row = UiKit.row(content, 68, order)
		iconBox(row, recipeId, 54)
		UiKit.label(row, result.DisplayName, UDim2.new(1, -250, 0, 24), UDim2.fromOffset(70, 8), UiKit.Colors.Text, 17)
		UiKit.label(row, `{describeItems(recipe.Inputs)} + 수수료 {recipe.Fee}G`, UDim2.new(1, -250, 0, 30), UDim2.fromOffset(70, 32), UiKit.Colors.SubText, 13)
		UiKit.button(row, "1개", UDim2.fromOffset(70, 40), UDim2.new(1, -170, 0, 12), function()
			send("Smelt", recipeId, 1)
		end, possible >= 1)
		UiKit.button(row, if possible >= 1 then `최대 {possible}` else "최대", UDim2.fromOffset(84, 40), UDim2.new(1, -92, 0, 12), function()
			send("Smelt", recipeId, possible)
		end, possible >= 1)
	end
end

-- 곡괭이 탭: 단계별 곡괭이와 가격, 구매 버튼
local function drawPickaxe()
	local tierAttribute = localPlayer:GetAttribute("PickaxeTier")
	local ownedTier = if typeof(tierAttribute) == "number" then tierAttribute else 0
	local gold = InventoryState.get().Gold

	for order, pickaxeId in PICKAXE_ORDER do
		local def = PickaxeDefs[pickaxeId]
		local config = Config.Pickaxes[pickaxeId]
		local price = config.Price
		local priceText = `{price.Gold}G`
		if next(price.Items) then
			priceText ..= ` + {describeItems(price.Items)}`
		end
		local canAfford = gold >= price.Gold
		for itemId, amount in price.Items do
			if InventoryState.count(itemId) < amount then
				canAfford = false
			end
		end

		local status: string
		local enabled = false
		if InventoryState.count(pickaxeId) > 0 or def.Tier <= ownedTier then
			status = "보유 중"
		elseif def.Tier > ownedTier + 1 then
			status = "이전 단계 먼저"
		elseif canAfford then
			status = "구매"
			enabled = true
		else
			status = "부족"
		end

		local row = UiKit.row(content, 68, order)
		iconBox(row, pickaxeId, 54)
		UiKit.label(row, `T{def.Tier} {def.DisplayName}`, UDim2.new(1, -200, 0, 24), UDim2.fromOffset(70, 8), UiKit.Colors.Text, 17)
		UiKit.label(row, `힘 x{config.Power}  ·  {priceText}`, UDim2.new(1, -200, 0, 30), UDim2.fromOffset(70, 32), UiKit.Colors.SubText, 13)
		UiKit.button(row, status, UDim2.fromOffset(110, 40), UDim2.new(1, -120, 0, 12), function()
			send("BuyPickaxe", pickaxeId)
		end, enabled)
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

-- 지금 탭 내용을 다시 그린다 (가방이 바뀌면 다시 호출)
local function redraw()
	if not currentShop or not currentTab then
		return
	end
	clearContent()
	local tabId = currentTab.Id
	if tabId == "Smelt" then
		drawSmelt()
	elseif tabId == "Pickaxe" then
		drawPickaxe()
	elseif tabId == "Sell" then
		drawSell()
	elseif tabId == "Bag" then
		drawBag()
	elseif tabId == "Buy" then
		drawBuy()
	else
		drawComingSoon(currentTab)
	end
end

-- 탭 버튼을 그린다
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
	local count = #shop.Tabs
	for index, tab in shop.Tabs do
		local button = UiKit.button(tabBar, tab.Title, UDim2.new(1 / count, -6, 1, 0), UDim2.new((index - 1) / count, 3, 0, 0), function()
			currentTab = tab
			drawTabs()
			redraw()
		end)
		if tab ~= currentTab then
			button.BackgroundColor3 = UiKit.Colors.PanelLight
		end
	end
end

-- 상점 창을 닫는다
function ShopUI.close()
	panel.Visible = false
	backdrop.Visible = false
	currentShop = nil
	currentTab = nil
	currentPrompt = nil
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

	panel = UiKit.panel(gui, UDim2.new(0.5, 0, 0.65, 0), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	panel.ZIndex = 1
	panel.Visible = false
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(330, 320)
	constraint.MaxSize = Vector2.new(560, 520)
	constraint.Parent = panel

	titleLabel = UiKit.label(panel, "", UDim2.new(1, -70, 0, 34), UDim2.fromOffset(16, 8), UiKit.Colors.Gold, 22)
	UiKit.button(panel, "X", UDim2.fromOffset(34, 34), UDim2.new(1, -44, 0, 8), ShopUI.close)
	greetingLabel = UiKit.label(panel, "", UDim2.new(1, -32, 0, 40), UDim2.fromOffset(16, 42), UiKit.Colors.SubText, 14)

	tabBar = Instance.new("Frame")
	tabBar.Size = UDim2.new(1, -26, 0, 36)
	tabBar.Position = UDim2.fromOffset(13, 86)
	tabBar.BackgroundTransparency = 1
	tabBar.Parent = panel

	content = UiKit.list(panel, UDim2.new(1, -24, 1, -140), UDim2.fromOffset(14, 130))

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local shopId = prompt:GetAttribute("ShopId")
		if typeof(shopId) == "string" then
			ShopUI.open(shopId, prompt)
		end
	end)
	InventoryState.Changed:Connect(redraw)
	localPlayer:GetAttributeChangedSignal("PickaxeTier"):Connect(redraw)
	RunService.Heartbeat:Connect(checkDistance)
end

return ShopUI
