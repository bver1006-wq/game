--!strict
-- 가방(칸 단위)과 골드. 서버 메모리에만 두고, 바뀔 때마다 클라이언트에 전체 내용을 보낸다.
-- 칸 계산: 쌓이는 아이템은 MaxStack개마다 1칸, 쌓이지 않는 아이템(도구)은 1개마다 1칸.
-- 처음엔 StartSlots칸이고, 상인에게 가방을 사면 늘어난다.
-- MVP-1 저장(DataService) 전이라 나갔다 들어오면 초기화된다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ItemDefs = require(ReplicatedStorage.Shared.ItemDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

type Bag = {
	Items: { [string]: number },
	Gold: number,
	Slots: number, -- 지금 가방 칸 수
	BagLevel: number, -- 산 가방 확장 단계 (0 = 기본)
}

local InventoryService = {}

local bags: { [Player]: Bag } = {}
local changedRemote: RemoteEvent

-- 아이템 하나가 차지하는 칸 수
local function slotsFor(itemId: string, count: number): number
	if count <= 0 then
		return 0
	end
	local def = ItemDefs.Items[itemId]
	if def and def.Stackable then
		return math.ceil(count / Config.Inventory.MaxStack)
	end
	return count
end

-- 가방이 쓰고 있는 칸 수
local function usedSlots(bag: Bag): number
	local used = 0
	for itemId, count in bag.Items do
		used += slotsFor(itemId, count)
	end
	return used
end

-- 리더보드에 골드를 보여준다
local function updateLeaderstats(player: Player, gold: number)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end
	local goldValue = leaderstats:FindFirstChild("골드")
	if not goldValue then
		goldValue = Instance.new("IntValue")
		goldValue.Name = "골드"
		goldValue.Parent = leaderstats
	end
	(goldValue :: IntValue).Value = gold
end

-- 클라이언트에 가방 전체 내용을 보낸다
local function push(player: Player)
	local bag = bags[player]
	if not bag then
		return
	end
	updateLeaderstats(player, bag.Gold)
	changedRemote:FireClient(player, {
		Items = table.clone(bag.Items),
		Gold = bag.Gold,
		Slots = bag.Slots,
		BagLevel = bag.BagLevel,
		MaxStack = Config.Inventory.MaxStack,
	})
end

-- 플레이어의 가방을 가져온다 (없으면 새로 만든다)
local function getBag(player: Player): Bag
	local bag = bags[player]
	if not bag then
		bag = { Items = {}, Gold = 0, Slots = Config.Inventory.StartSlots, BagLevel = 0 }
		bags[player] = bag
	end
	return bag
end

-- 서버 시작 시 한 번 호출
function InventoryService.init()
	changedRemote = Remotes.get(Remotes.Names.InventoryChanged)
	local function onPlayerAdded(player: Player)
		getBag(player)
		push(player)
		-- 클라이언트 UI가 늦게 준비될 수 있어 캐릭터가 나올 때마다 한 번 더 보낸다
		player.CharacterAdded:Connect(function()
			task.wait(1)
			push(player)
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		bags[player] = nil
	end)
end

-- 아이템 개수
function InventoryService.count(player: Player, itemId: string): number
	return getBag(player).Items[itemId] or 0
end

-- 빈 칸 수
function InventoryService.freeSlots(player: Player): number
	local bag = getBag(player)
	return math.max(bag.Slots - usedSlots(bag), 0)
end

-- 이 아이템을 몇 개 더 넣을 수 있는지 (쌓이는 아이템은 기존 칸의 남은 자리도 센다)
function InventoryService.roomFor(player: Player, itemId: string): number
	local def = ItemDefs.Items[itemId]
	if not def then
		return 0
	end
	local free = InventoryService.freeSlots(player)
	if not def.Stackable then
		return free
	end
	local count = InventoryService.count(player, itemId)
	local maxStack = Config.Inventory.MaxStack
	local partialRoom = if count > 0 then slotsFor(itemId, count) * maxStack - count else 0
	return partialRoom + free * maxStack
end

-- 아이템을 넣는다. 가방이 차면 들어갈 만큼만 넣고, 실제로 넣은 개수를 돌려준다
function InventoryService.add(player: Player, itemId: string, amount: number): number
	if not ItemDefs.Items[itemId] or amount <= 0 then
		return 0
	end
	local bag = getBag(player)
	local added = math.min(math.floor(amount), InventoryService.roomFor(player, itemId))
	if added > 0 then
		bag.Items[itemId] = (bag.Items[itemId] or 0) + added
		push(player)
	end
	return added
end

-- 여러 아이템을 한 번에 가지고 있는지
function InventoryService.hasAll(player: Player, items: { [string]: number }): boolean
	for itemId, amount in items do
		if InventoryService.count(player, itemId) < amount then
			return false
		end
	end
	return true
end

-- 아이템을 뺀다. 모자라면 아무것도 빼지 않고 false
function InventoryService.remove(player: Player, itemId: string, amount: number): boolean
	return InventoryService.removeAll(player, { [itemId] = amount })
end

-- 여러 아이템을 한 번에 뺀다. 하나라도 모자라면 아무것도 빼지 않고 false
function InventoryService.removeAll(player: Player, items: { [string]: number }): boolean
	if not InventoryService.hasAll(player, items) then
		return false
	end
	local bag = getBag(player)
	for itemId, amount in items do
		local left = (bag.Items[itemId] or 0) - amount
		bag.Items[itemId] = if left > 0 then left else nil
	end
	push(player)
	return true
end

-- 골드
function InventoryService.getGold(player: Player): number
	return getBag(player).Gold
end

-- 골드를 더한다
function InventoryService.addGold(player: Player, amount: number)
	local bag = getBag(player)
	bag.Gold += math.floor(amount)
	push(player)
end

-- 골드를 쓴다. 모자라면 쓰지 않고 false
function InventoryService.spendGold(player: Player, amount: number): boolean
	local bag = getBag(player)
	if bag.Gold < amount then
		return false
	end
	bag.Gold -= amount
	push(player)
	return true
end

-- 지금 가방 확장 단계 (0 = 기본)
function InventoryService.getBagLevel(player: Player): number
	return getBag(player).BagLevel
end

-- 가방 확장을 적용한다 (가격 확인은 호출하는 쪽에서)
function InventoryService.setBagLevel(player: Player, level: number, slots: number)
	local bag = getBag(player)
	bag.BagLevel = level
	bag.Slots = slots
	push(player)
end

return InventoryService
