--!strict
-- 서버가 보낸 가방 내용(아이템 개수, 골드, 칸 수)을 클라이언트에 보관한다. 화면 표시용이며 결정은 서버가 한다.
-- 바뀌면 Changed 이벤트로 가방 UI·상점 UI·빠른 호출 칸에 알린다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDefs = require(ReplicatedStorage.Shared.ItemDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

export type Snapshot = {
	Items: { [string]: number },
	Gold: number,
	Slots: number,
	BagLevel: number,
	MaxStack: number,
}

-- 화면에 그릴 칸 하나 (쌓이는 아이템이 MaxStack을 넘으면 여러 칸으로 나뉜다)
export type SlotEntry = {
	ItemId: string,
	Count: number,
}

local InventoryState = {}

local snapshot: Snapshot = { Items = {}, Gold = 0, Slots = 10, BagLevel = 0, MaxStack = 99 }
local changed = Instance.new("BindableEvent")

-- 가방 내용이 바뀔 때마다 호출된다
InventoryState.Changed = changed.Event

-- 지금 가방 내용
function InventoryState.get(): Snapshot
	return snapshot
end

-- 아이템 개수
function InventoryState.count(itemId: string): number
	return snapshot.Items[itemId] or 0
end

-- 칸 목록 (ItemDefs.Order 순서). category가 있으면 그 분류만
function InventoryState.entries(category: string?): { SlotEntry }
	local list: { SlotEntry } = {}
	for _, itemId in ItemDefs.Order do
		local def = ItemDefs.Items[itemId]
		local count = snapshot.Items[itemId] or 0
		if count > 0 and (category == nil or def.Category == category) then
			if def.Stackable then
				while count > 0 do
					local stack = math.min(count, snapshot.MaxStack)
					table.insert(list, { ItemId = itemId, Count = stack })
					count -= stack
				end
			else
				for _ = 1, count do
					table.insert(list, { ItemId = itemId, Count = 1 })
				end
			end
		end
	end
	return list
end

-- 쓰고 있는 칸 수
function InventoryState.usedSlots(): number
	return #InventoryState.entries(nil)
end

-- 클라이언트 시작 시 한 번 호출
function InventoryState.init()
	Remotes.get(Remotes.Names.InventoryChanged).OnClientEvent:Connect(function(newSnapshot: Snapshot)
		snapshot = newSnapshot
		changed:Fire(snapshot)
	end)
end

return InventoryState
