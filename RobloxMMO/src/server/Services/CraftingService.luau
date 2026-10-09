--!strict
-- 대장장이: 제련(재료 + 수수료 → 괴)과 곡괭이·도끼 판매.
-- 클라이언트는 "이 레시피를 몇 번 / 이 곡괭이(도끼)를 사겠다"만 보내고, 거리·재료·골드는 서버가 확인한다.
-- 모루 타이밍 미니게임으로 직접 만드는 제작은 나중에 추가한다 (지금은 NPC 의뢰 구매만).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ItemDefs = require(ReplicatedStorage.Shared.ItemDefs)
local PickaxeDefs = require(ReplicatedStorage.Shared.PickaxeDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local InventoryService = require(script.Parent.InventoryService)
local NotifyService = require(script.Parent.NotifyService)
local NpcService = require(script.Parent.NpcService)
local PickaxeService = require(script.Parent.PickaxeService)

local SHOP_ID = "Blacksmith"
local MAX_SMELT_PER_REQUEST = 50

local CraftingService = {}

-- 재료 목록을 사람이 읽는 글자로 ("구리 2, 석탄 1")
local function describeItems(items: { [string]: number }): string
	local parts = {}
	for itemId, amount in items do
		local def = ItemDefs.Items[itemId]
		table.insert(parts, `{if def then def.DisplayName else itemId} {amount}`)
	end
	return table.concat(parts, ", ")
end

-- 제련 1회 (재료·수수료 확인 → 빼기 → 결과 넣기). 성공하면 true
local function smeltOnce(player: Player, recipeId: string): (boolean, string?)
	local recipe = Config.Smelting.Recipes[recipeId]
	if not InventoryService.hasAll(player, recipe.Inputs) then
		return false, `재료가 모자라요. (필요: {describeItems(recipe.Inputs)})`
	end
	if InventoryService.getGold(player) < recipe.Fee then
		return false, `수수료 {recipe.Fee}G가 모자라요.`
	end
	InventoryService.removeAll(player, recipe.Inputs)
	if InventoryService.add(player, recipeId, 1) < 1 then
		-- 결과물이 들어갈 칸이 없으면 재료를 돌려준다
		for itemId, amount in recipe.Inputs do
			InventoryService.add(player, itemId, amount)
		end
		return false, "가방에 빈 칸이 없어요."
	end
	InventoryService.spendGold(player, recipe.Fee)
	return true, nil
end

-- 곡괭이·도끼 구매. 종류(Kind)마다 따로 단계를 밟는다 (곡괭이 티어와 도끼 티어는 별개)
local function buyTool(player: Player, toolId: string, kind: PickaxeDefs.ToolKind)
	local def = PickaxeDefs[toolId]
	local config = Config.Pickaxes[toolId]
	if not def or def.Kind ~= kind or not config or not config.Price then
		return
	end
	local kindName = if kind == "Axe" then "도끼" else "곡괭이"
	local currentTier = PickaxeService.getTier(player, kind)
	if InventoryService.count(player, toolId) > 0 or def.Tier <= currentTier then
		NotifyService.send(player, `이미 이 {kindName}나 더 좋은 {kindName}를 가지고 있어요.`, "info")
		return
	end
	if def.Tier > currentTier + 1 then
		NotifyService.send(player, `바로 아래 단계 {kindName}부터 사야 해요.`, "bad")
		return
	end
	local price = config.Price
	if InventoryService.getGold(player) < price.Gold then
		NotifyService.send(player, `골드가 모자라요. ({price.Gold}G 필요)`, "bad")
		return
	end
	if not InventoryService.hasAll(player, price.Items) then
		NotifyService.send(player, `재료가 모자라요. (필요: {describeItems(price.Items)})`, "bad")
		return
	end
	if InventoryService.freeSlots(player) < 1 then
		NotifyService.send(player, "가방에 빈 칸이 없어요.", "bad")
		return
	end
	InventoryService.removeAll(player, price.Items)
	InventoryService.spendGold(player, price.Gold)
	PickaxeService.give(player, toolId)
	NotifyService.send(player, `{def.DisplayName} 구매 완료!`, "good")
	print(`[CraftingService] {player.Name} {def.DisplayName} 구매`)
end

-- ShopAction 처리 (대장장이 것만)
local function onShopAction(player: Player, shopId: unknown, action: unknown, idArg: unknown, timesArg: unknown)
	if shopId ~= SHOP_ID then
		return
	end
	if not NpcService.isNear(player, SHOP_ID) then
		NotifyService.send(player, "대장장이에게 더 가까이 가세요.", "bad")
		return
	end
	if typeof(idArg) ~= "string" then
		return
	end

	if action == "Smelt" then
		if not Config.Smelting.Recipes[idArg] then
			return
		end
		local times = if typeof(timesArg) == "number" and timesArg == timesArg then math.clamp(math.floor(timesArg), 1, MAX_SMELT_PER_REQUEST) else 1
		local made = 0
		local failReason: string? = nil
		for _ = 1, times do
			local ok, reason = smeltOnce(player, idArg)
			if not ok then
				failReason = reason
				break
			end
			made += 1
		end
		local name = ItemDefs.Items[idArg].DisplayName
		if made > 0 then
			NotifyService.send(player, `{name} {made}개를 만들었어요.`, "good")
		elseif failReason then
			NotifyService.send(player, failReason, "bad")
		end
	elseif action == "BuyPickaxe" then
		buyTool(player, idArg, "Pickaxe")
	elseif action == "BuyAxe" then
		buyTool(player, idArg, "Axe")
	end
end

-- 서버 시작 시 한 번 호출
function CraftingService.init()
	Remotes.get(Remotes.Names.ShopAction).OnServerEvent:Connect(onShopAction)
end

return CraftingService
