--!strict
-- 골드 경제: 상인에게 광석·괴 팔기, 가방 확장 사기.
-- 클라이언트는 "이 아이템을 몇 개 팔겠다"만 보내고, 거리·보유량·가격은 서버가 확인한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ItemDefs = require(ReplicatedStorage.Shared.ItemDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local InventoryService = require(script.Parent.InventoryService)
local NotifyService = require(script.Parent.NotifyService)
local NpcService = require(script.Parent.NpcService)

local SHOP_ID = "Merchant"

local EconomyService = {}

-- 아이템을 판다. amount가 nil이면 가진 만큼 전부. 판 개수를 돌려준다
local function sell(player: Player, itemId: string, amount: number?): number
	local price = Config.SellPrices[itemId]
	if not price then
		return 0
	end
	local owned = InventoryService.count(player, itemId)
	local selling = math.min(amount or owned, owned)
	if selling <= 0 then
		return 0
	end
	if not InventoryService.remove(player, itemId, selling) then
		return 0
	end
	InventoryService.addGold(player, selling * price)
	return selling
end

-- ShopAction 처리 (상인 것만)
local function onShopAction(player: Player, shopId: unknown, action: unknown, itemArg: unknown, amountArg: unknown)
	if shopId ~= SHOP_ID then
		return
	end
	if not NpcService.isNear(player, SHOP_ID) then
		NotifyService.send(player, "상인에게 더 가까이 가세요.", "bad")
		return
	end

	if action == "Sell" then
		if typeof(itemArg) ~= "string" or not ItemDefs.Items[itemArg] then
			return
		end
		local amount: number? = nil
		if typeof(amountArg) == "number" and amountArg == amountArg and amountArg >= 1 then
			amount = math.floor(amountArg)
		end
		local sold = sell(player, itemArg, amount)
		if sold > 0 then
			local name = ItemDefs.Items[itemArg].DisplayName
			NotifyService.send(player, `{name} {sold}개를 {sold * Config.SellPrices[itemArg]}G에 팔았어요.`, "good")
		end
	elseif action == "Buy" then
		local goods = nil
		for _, entry in Config.MerchantGoods do
			if entry.ItemId == itemArg then
				goods = entry
			end
		end
		if not goods then
			return
		end
		local amount = if typeof(amountArg) == "number" and amountArg == amountArg then math.clamp(math.floor(amountArg), 1, 99) else 1
		local room = InventoryService.roomFor(player, goods.ItemId)
		amount = math.min(amount, room)
		if amount <= 0 then
			NotifyService.send(player, "가방에 빈 칸이 없어요.", "bad")
			return
		end
		if not InventoryService.spendGold(player, goods.Price * amount) then
			NotifyService.send(player, `골드가 모자라요. ({goods.Price * amount}G 필요)`, "bad")
			return
		end
		InventoryService.add(player, goods.ItemId, amount)
		NotifyService.send(player, `{ItemDefs.Items[goods.ItemId].DisplayName} {amount}개를 샀어요.`, "good")
	elseif action == "BuyBag" then
		-- 2026-10-10 사용자 요청: 가방은 우선 못 산다 (Config.Inventory.BagShopEnabled)
		if not Config.Inventory.BagShopEnabled then
			return
		end
		local level = InventoryService.getBagLevel(player)
		local upgrade = Config.Inventory.BagUpgrades[level + 1]
		if not upgrade then
			NotifyService.send(player, "이미 가장 큰 가방이에요.", "info")
			return
		end
		if not InventoryService.spendGold(player, upgrade.Price) then
			NotifyService.send(player, `골드가 모자라요. ({upgrade.Price}G 필요)`, "bad")
			return
		end
		InventoryService.setBagLevel(player, level + 1, upgrade.Slots)
		NotifyService.send(player, `{upgrade.Name}! 가방이 {upgrade.Slots}칸이 됐어요.`, "good")
	elseif action == "SellAll" then
		local earned = 0
		for itemId, price in Config.SellPrices do
			earned += sell(player, itemId, nil) * price
		end
		if earned > 0 then
			NotifyService.send(player, `전부 팔아서 {earned}G를 벌었어요.`, "good")
		else
			NotifyService.send(player, "팔 물건이 없어요.", "info")
		end
	end
end

-- 서버 시작 시 한 번 호출
function EconomyService.init()
	Remotes.get(Remotes.Names.ShopAction).OnServerEvent:Connect(onShopAction)
end

return EconomyService
