--!strict
-- 대장장이: 제련(재료 + 수수료 → 괴)과 곡괭이·도끼 조합. 사냥꾼(무기·장비)도 craft를 같이 쓴다.
-- 조합식(Config.Recipes): 1단계는 골드 + 재료로 사고, 2~4단계는 바로 아래 단계 3개 + 재료 + 골드로 만든다 (2026-10-09)
-- 클라이언트는 "이 레시피를 몇 번 / 이 아이템을 만들겠다"만 보내고, 거리·재료·골드·가방 칸은 서버가 확인한다.
-- 모루 타이밍 미니게임으로 직접 만드는 제작은 나중에 추가한다 (지금은 NPC 의뢰 구매만).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local EquipmentDefs = require(ReplicatedStorage.Shared.EquipmentDefs)
local ItemDefs = require(ReplicatedStorage.Shared.ItemDefs)
local PickaxeDefs = require(ReplicatedStorage.Shared.PickaxeDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local EquipmentService = require(script.Parent.EquipmentService)
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

-- 조합 1회: 아래 단계 3개(From) + 재료 + 골드 → 1개. 1단계는 골드 + 재료로 산다. 성공하면 true
-- 실패 이유(알림 문구)를 두 번째 값으로 돌려준다
local function craftOnce(player: Player, itemId: string): (boolean, string?)
	local recipe = Config.Recipes[itemId]
	if not recipe or not ItemDefs.Items[itemId] then
		return false, nil
	end
	local from = recipe.From
	if from then
		local have = InventoryService.count(player, from.Id)
		if have < from.Count then
			return false, `{ItemDefs.Items[from.Id].DisplayName} {from.Count}개가 필요해요. (지금 {have}개)`
		end
	end
	if InventoryService.getGold(player) < recipe.Gold then
		return false, `골드가 모자라요. ({recipe.Gold}G 필요)`
	end
	if not InventoryService.hasAll(player, recipe.Items) then
		local missing: { [string]: number } = {}
		for id, amount in recipe.Items do
			local lack = amount - InventoryService.count(player, id)
			if lack > 0 then
				missing[id] = lack
			end
		end
		return false, `재료가 모자라요. (더 필요: {describeItems(missing)})`
	end
	-- 아래 단계 3개를 쓰면 칸이 비므로 가방 검사는 1단계(살 때)만
	if not from and InventoryService.roomFor(player, itemId) < 1 then
		return false, "가방에 빈 칸이 없어요."
	end

	-- 쓰기 전에: 재료로 쓰는 아래 단계를 끼우고 있거나 손에 들고 있었는지 (다 쓰면 새것을 대신 끼워 준다)
	local wornSlot: string? = nil
	local wasHeld = false
	if from then
		local equipment = EquipmentDefs.Items[from.Id]
		if equipment and player:GetAttribute(`Equip_{equipment.Slot}`) == from.Id then
			wornSlot = equipment.Slot
		end
		local held = PickaxeService.getEquipped(player)
		wasHeld = held ~= nil and held.Id == from.Id
	end

	InventoryService.removeAll(player, recipe.Items)
	InventoryService.spendGold(player, recipe.Gold)
	if from then
		if PickaxeDefs[from.Id] then
			PickaxeService.removeCount(player, from.Id, from.Count) -- 다 없어지면 손에 든 Tool도 없어진다
		else
			InventoryService.remove(player, from.Id, from.Count) -- 끼운 장비가 다 없어지면 EquipmentService가 벗긴다
		end
	end
	local added = if PickaxeDefs[itemId] then PickaxeService.give(player, itemId) else InventoryService.add(player, itemId, 1) >= 1
	if not added then
		-- 들어갈 자리가 없으면(있을 수 없지만) 쓴 것을 전부 돌려준다
		for id, amount in recipe.Items do
			InventoryService.add(player, id, amount)
		end
		InventoryService.addGold(player, recipe.Gold)
		if from then
			for _ = 1, from.Count do
				if PickaxeDefs[from.Id] then
					PickaxeService.give(player, from.Id)
				else
					InventoryService.add(player, from.Id, 1)
				end
			end
		end
		return false, "가방에 빈 칸이 없어요."
	end

	-- 끼우던 장비·들던 도구를 다 썼으면 새로 만든 것을 바로 끼운다(든다)
	if from and InventoryService.count(player, from.Id) <= 0 then
		if wornSlot then
			EquipmentService.equip(player, itemId)
		end
		if wasHeld then
			PickaxeService.hold(player, itemId)
		end
	end
	return true, nil
end

-- 조합(또는 1단계 구매)을 times번까지 한다. 모자라면 거기서 멈추고 알린다
-- 어느 상점에서 무엇을 만들 수 있는지는 부르는 쪽(대장장이·사냥꾼)이 먼저 확인한다
function CraftingService.craft(player: Player, itemId: string, times: number)
	local recipe = Config.Recipes[itemId]
	local def = ItemDefs.Items[itemId]
	if not recipe or not def then
		return
	end
	local made = 0
	local failReason: string? = nil
	for _ = 1, math.clamp(math.floor(times), 1, Config.Crafting.MaxPerRequest) do
		local ok, reason = craftOnce(player, itemId)
		if not ok then
			failReason = reason
			break
		end
		made += 1
	end
	if made > 0 then
		local verb = if recipe.From then "만들었어요" else "샀어요"
		local countText = if made > 1 then ` {made}개` else ""
		local hint = if EquipmentDefs.Items[itemId] and not recipe.From then " 가방에서 더블클릭하면 착용해요." else ""
		NotifyService.send(player, `{def.DisplayName}{countText} {verb}!{hint}`, "good")
		print(`[CraftingService] {player.Name} {def.DisplayName} x{made}`)
	elseif failReason then
		NotifyService.send(player, failReason, "bad")
	end
end

-- 요청 인자에서 만들 개수를 읽는다 (없거나 이상하면 1)
function CraftingService.readTimes(timesArg: unknown): number
	if typeof(timesArg) == "number" and timesArg == timesArg then
		return math.clamp(math.floor(timesArg), 1, Config.Crafting.MaxPerRequest)
	end
	return 1
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
	elseif action == "Craft" then
		-- 대장장이는 곡괭이·도끼만 만든다
		local tool = PickaxeDefs[idArg]
		if tool and (tool.Kind == "Pickaxe" or tool.Kind == "Axe") then
			CraftingService.craft(player, idArg, CraftingService.readTimes(timesArg))
		end
	end
end

-- TODO(임시, 테스트 끝나면 지우기): Studio 테스트용 공짜 지급 (2026-10-10 사용자 요청)
-- 클라 ShopUI가 상점 아이콘을 빨리 3번 누르면 (shopId, itemId)를 보낸다.
-- Studio + Config.Debug.ShopTripleClickFree일 때만, 있는 아이템이고 그 상점 NPC 근처일 때만 준다.
-- 도구·무기는 PickaxeService.give로 1개(Tool도 생김), 쌓이는 아이템은 ShopFreeStackAmount개, 나머지(장비·화살통)는 1개
local function onDebugShopGrant(player: Player, shopId: unknown, itemId: unknown)
	if not (RunService:IsStudio() and Config.Debug.ShopTripleClickFree) then
		return
	end
	if typeof(shopId) ~= "string" or typeof(itemId) ~= "string" then
		return
	end
	local def = ItemDefs.Items[itemId]
	if not def then
		return
	end
	if not NpcService.isNear(player, shopId) then
		NotifyService.send(player, "[테스트] 상인에게 더 가까이 가세요.", "bad")
		return
	end
	local given = 0
	if PickaxeDefs[itemId] then
		given = if PickaxeService.give(player, itemId) then 1 else 0
	else
		local amount = if def.Stackable then Config.Debug.ShopFreeStackAmount else 1
		given = InventoryService.add(player, itemId, amount)
	end
	if given > 0 then
		local countText = if given > 1 then ` {given}개` else ""
		NotifyService.send(player, `[테스트] {def.DisplayName}{countText} 받았어요`, "good")
		print(`[CraftingService] (테스트 지급) {player.Name} {def.DisplayName} x{given}`)
	else
		NotifyService.send(player, "[테스트] 가방에 빈 칸이 없어요.", "bad")
	end
end

-- 서버 시작 시 한 번 호출
function CraftingService.init()
	Remotes.get(Remotes.Names.ShopAction).OnServerEvent:Connect(onShopAction)
	Remotes.get(Remotes.Names.DebugShopGrant).OnServerEvent:Connect(onDebugShopGrant) -- TODO(임시): 테스트 끝나면 지우기
end

return CraftingService
