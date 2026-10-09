--!strict
-- 조합식 그림 줄: 재료마다 아이콘 + "가진 수/필요 수"(모자라면 빨강, 넉넉하면 초록) + 골드 동전.
-- 상점 목록(ShopUI)과 아이템 상세 창(ItemDetailUI)이 같이 쓴다. 화면 표시용이며 결정은 서버가 한다.
-- 조합식 숫자는 Config.Recipes(도구·무기·장비), Config.Smelting(제련), Config.Quiver(화살통)에 있다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ItemDefs = require(ReplicatedStorage.Shared.ItemDefs)
local InventoryState = require(script.Parent.InventoryState)
local ItemIcon = require(script.Parent.ItemIcon)
local UiKit = require(script.Parent.UiKit)

-- 조합식 모양 (Config.Recipes 한 줄. 제련·화살통도 이 모양으로 바꿔서 넘긴다)
export type RecipeLike = {
	From: { Id: string, Count: number }?,
	Items: { [string]: number },
	Gold: number,
}

-- 필요한 것 한 칸 (ItemId가 nil이면 골드)
export type Need = { ItemId: string?, Count: number }

local CHIP_WIDTH = 54
local CHIP_HEIGHT = 58

local RecipeView = {}

-- 아이템 Id를 가방 순서(ItemDefs.Order)대로 정렬하는 비교 함수
local function byOrder(a: string, b: string): boolean
	local ia = table.find(ItemDefs.Order, a) or math.huge
	local ib = table.find(ItemDefs.Order, b) or math.huge
	if ia == ib then
		return a < b
	end
	return ia < ib
end

-- 필요한 것 목록: 아래 단계 아이템 → 재료(가방 순서) → 골드
function RecipeView.needs(recipe: RecipeLike): { Need }
	local list: { Need } = {}
	if recipe.From then
		table.insert(list, { ItemId = recipe.From.Id, Count = recipe.From.Count })
	end
	local ids: { string } = {}
	for id in recipe.Items do
		table.insert(ids, id)
	end
	table.sort(ids, byOrder)
	for _, id in ids do
		table.insert(list, { ItemId = id, Count = recipe.Items[id] })
	end
	if recipe.Gold > 0 then
		table.insert(list, { ItemId = nil, Count = recipe.Gold })
	end
	return list
end

-- 지금 가방으로 만들 수 있는지 (전부 넉넉하면 true)
function RecipeView.canAfford(recipe: RecipeLike): boolean
	for _, need in RecipeView.needs(recipe) do
		local have = if need.ItemId then InventoryState.count(need.ItemId) else InventoryState.get().Gold
		if have < need.Count then
			return false
		end
	end
	return true
end

-- 지금 가방으로 몇 번 만들 수 있는지 (최대 limit)
function RecipeView.timesAffordable(recipe: RecipeLike, limit: number): number
	local times = limit
	for _, need in RecipeView.needs(recipe) do
		local have = if need.ItemId then InventoryState.count(need.ItemId) else InventoryState.get().Gold
		times = math.min(times, math.floor(have / need.Count))
	end
	return math.max(times, 0)
end

-- 조합식 그림 줄을 만든다. 칸이 모자라면 다음 줄로 넘어간다 (높이는 저절로 늘어남)
-- onItemClick이 있으면 재료 아이콘을 눌렀을 때 그 아이템 Id로 부른다 (상세 창 열기)
function RecipeView.chips(parent: Instance, recipe: RecipeLike, position: UDim2, width: UDim, onItemClick: ((string) -> ())?): Frame
	local container = Instance.new("Frame")
	container.Name = "Recipe"
	container.BackgroundTransparency = 1
	container.Position = position
	container.Size = UDim2.new(width, UDim.new(0, CHIP_HEIGHT))
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.Parent = parent
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CHIP_WIDTH, CHIP_HEIGHT)
	layout.CellPadding = UDim2.fromOffset(4, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = container

	for order, need in RecipeView.needs(recipe) do
		local chip = Instance.new("TextButton")
		chip.Text = ""
		chip.AutoButtonColor = need.ItemId ~= nil and onItemClick ~= nil
		chip.BackgroundColor3 = UiKit.Colors.Panel
		chip.BorderSizePixel = 0
		chip.LayoutOrder = order
		chip.Parent = container
		UiKit.corner(chip, 6)

		local iconHolder = Instance.new("Frame")
		iconHolder.BackgroundTransparency = 1
		iconHolder.Size = UDim2.fromOffset(38, 38)
		iconHolder.Position = UDim2.new(0.5, -19, 0, 2)
		iconHolder.Parent = chip

		local have: number
		local text: string
		if need.ItemId then
			ItemIcon.create(iconHolder, need.ItemId)
			have = InventoryState.count(need.ItemId)
			text = `{have}/{need.Count}`
			-- 아래 단계 도구·장비는 테두리를 금색으로 (무엇을 3개 모아야 하는지 눈에 띄게)
			if recipe.From and need.ItemId == recipe.From.Id then
				UiKit.stroke(chip, UiKit.Colors.Gold, 2)
			end
		else
			UiKit.coinIcon(iconHolder)
			have = InventoryState.get().Gold
			text = `{need.Count}G`
		end
		local enough = have >= need.Count
		local label = UiKit.label(chip, text, UDim2.new(1, -2, 0, 16), UDim2.new(0, 1, 1, -17), if enough then UiKit.Colors.Good else UiKit.Colors.Bad, 13)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextWrapped = false
		label.TextScaled = true
		local sizeLimit = Instance.new("UITextSizeConstraint")
		sizeLimit.MaxTextSize = 13
		sizeLimit.Parent = label

		local itemId = need.ItemId
		if itemId and onItemClick then
			chip.Activated:Connect(function()
				onItemClick(itemId)
			end)
		end
	end
	return container
end

-- 이 아이템이 재료로 쓰이는 곳 (만들어지는 아이템 Id 목록, 가방 순서)
function RecipeView.usedIn(itemId: string): { string }
	local results: { string } = {}
	local function addResult(id: string)
		if not table.find(results, id) then
			table.insert(results, id)
		end
	end
	for resultId, recipe in Config.Recipes do
		if (recipe.From and recipe.From.Id == itemId) or recipe.Items[itemId] then
			addResult(resultId)
		end
	end
	for resultId, recipe in Config.Smelting.Recipes do
		if (recipe.Inputs :: { [string]: number })[itemId] then
			addResult(resultId)
		end
	end
	for resultId, quiver in (Config.Quiver.Items :: { [string]: any }) do
		if quiver.Price.Items[itemId] then
			addResult(resultId)
		end
	end
	table.sort(results, byOrder)
	return results
end

-- 이 아이템을 만드는(사는) 법. 없으면 nil. 두 번째 값은 어디서 만드는지 설명
function RecipeView.recipeFor(itemId: string): (RecipeLike?, string?)
	local recipe = Config.Recipes[itemId]
	if recipe then
		return recipe, nil
	end
	local smelt = (Config.Smelting.Recipes :: { [string]: any })[itemId]
	if smelt then
		return { Items = smelt.Inputs, Gold = smelt.Fee }, "대장장이 제련"
	end
	local quiver = (Config.Quiver.Items :: { [string]: any })[itemId]
	if quiver then
		return { Items = quiver.Price.Items, Gold = quiver.Price.Gold }, "사냥꾼 활 탭"
	end
	for _, goods in Config.MerchantGoods do
		if goods.ItemId == itemId then
			return { Items = {}, Gold = goods.Price }, "상인 잡화"
		end
	end
	return nil, nil
end

return RecipeView
