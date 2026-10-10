--!strict
-- 가방(칸 단위)과 골드. 서버 메모리에만 두고, 바뀔 때마다 클라이언트에 전체 내용을 보낸다.
-- 칸 계산: 쌓이는 아이템은 MaxStack개마다 1칸, 쌓이지 않는 아이템(도구)은 1개마다 1칸.
-- 처음엔 StartSlots칸이고, 상인에게 가방을 사면 늘어난다.
-- 들어올 때 DataService에서 불러오고, 저장할 때 "Inventory" 칸으로 내보낸다 (2026-10-09 저장 추가)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local EquipmentDefs = require(ReplicatedStorage.Shared.EquipmentDefs)
local ItemDefs = require(ReplicatedStorage.Shared.ItemDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local DataService = require(script.Parent.DataService)

type Bag = {
	Items: { [string]: number },
	Gold: number,
	Slots: number, -- 지금 가방 칸 수
	BagLevel: number, -- 산 가방 확장 단계 (0 = 기본)
	Unknown: { [string]: number }, -- 저장에는 있는데 지금 정의가 없는 아이템 (지우지 않고 그대로 다시 저장한다)
}

local InventoryService = {}

-- 가방이 바뀔 때마다 (player) — 장비가 가방에서 사라지면 벗기는 데 쓴다 (EquipmentService)
local changedEvent = Instance.new("BindableEvent")
InventoryService.Changed = changedEvent.Event

local bags: { [Player]: Bag } = {}
local loaded: { [Player]: BindableEvent | true } = {} -- 불러오기를 기다리는 중이면 BindableEvent, 끝났으면 true
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
	changedEvent:Fire(player)
	changedRemote:FireClient(player, {
		Items = table.clone(bag.Items),
		Gold = bag.Gold,
		Slots = bag.Slots,
		BagLevel = bag.BagLevel,
		MaxStack = Config.Inventory.MaxStack,
	})
end

-- 새 가방
local function newBag(): Bag
	-- Studio에서 도구·무기를 전부 받는 테스트를 할 때는 가방을 넉넉하게
	local testSlots = RunService:IsStudio() and Config.Debug.GiveAllPickaxes and Config.Debug.StartSlots or nil
	return { Items = {}, Gold = 0, Slots = testSlots or Config.Inventory.StartSlots, BagLevel = 0, Unknown = {} }
end

-- 저장된 표에서 가방을 만든다 (이상한 값은 버린다)
local function bagFromSave(saved: any): Bag
	local bag = newBag()
	if typeof(saved) ~= "table" then
		return bag
	end
	if typeof(saved.Gold) == "number" and saved.Gold == saved.Gold then
		bag.Gold = math.max(math.floor(saved.Gold), 0)
	end
	if typeof(saved.Slots) == "number" and saved.Slots == saved.Slots then
		bag.Slots = math.max(math.floor(saved.Slots), bag.Slots)
	end
	if typeof(saved.BagLevel) == "number" and saved.BagLevel == saved.BagLevel then
		bag.BagLevel = math.max(math.floor(saved.BagLevel), 0)
	end
	for _, field in { "Items", "Unknown" } do
		local list = saved[field]
		if typeof(list) == "table" then
			for itemId, count in list do
				if typeof(itemId) == "string" and typeof(count) == "number" and count == count and count >= 1 then
					-- 예전 금속 방어구(구리·철·다이아·미스릴·오리하르콘 투구 등)는 같은 단계 몹 세트로 바꿔 준다 (2026-10-10)
					local renamed = EquipmentDefs.Renamed[itemId]
					if renamed and ItemDefs.Items[renamed] then
						itemId = renamed
					end
					local target = if ItemDefs.Items[itemId] then bag.Items else bag.Unknown
					target[itemId] = (target[itemId] or 0) + math.floor(count)
				end
			end
		end
	end
	return bag
end

-- 플레이어의 가방을 가져온다. 아직 불러오는 중이면 임시 빈 가방 (여기 넣은 것은 남지 않는다)
local function getBag(player: Player): Bag
	return bags[player] or newBag()
end

-- 서버 시작 시 한 번 호출
function InventoryService.init()
	changedRemote = Remotes.get(Remotes.Names.InventoryChanged)
	-- 저장할 칸: 가방 전체
	DataService.register("Inventory", function(player: Player)
		local bag = bags[player]
		if not bag then
			return nil
		end
		return {
			Items = table.clone(bag.Items),
			Unknown = table.clone(bag.Unknown),
			Gold = bag.Gold,
			Slots = bag.Slots,
			BagLevel = bag.BagLevel,
		}
	end)

	local function onPlayerAdded(player: Player)
		local waiting = Instance.new("BindableEvent")
		loaded[player] = waiting
		local data = DataService.load(player)
		if not player.Parent then
			loaded[player] = nil
			waiting:Fire()
			return
		end
		bags[player] = bagFromSave(data.Inventory)
		loaded[player] = true
		waiting:Fire()
		push(player)
		-- 클라이언트 UI가 늦게 준비될 수 있어 캐릭터가 나올 때마다 한 번 더 보낸다
		player.CharacterAdded:Connect(function()
			task.wait(1)
			push(player)
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		-- DataService가 나갈 때 가방을 모아 저장할 수 있게 조금 뒤에 지운다
		task.delay(Config.Save.CleanupDelay, function()
			bags[player] = nil
			loaded[player] = nil
		end)
	end)
end

-- 저장된 가방을 다 불러올 때까지 기다린다 (도구 지급·장비 복구 전에 부른다). 불러왔으면 true
function InventoryService.waitLoaded(player: Player): boolean
	local state = loaded[player]
	if state == nil then
		-- 아직 onPlayerAdded가 안 돌았을 수 있다: 잠깐 기다린다
		local started = os.clock()
		while loaded[player] == nil and player.Parent and os.clock() - started < 5 do
			task.wait()
		end
		state = loaded[player]
	end
	if typeof(state) == "Instance" then
		(state :: BindableEvent).Event:Wait()
	end
	return loaded[player] == true and player.Parent ~= nil
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
