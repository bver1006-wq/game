--!strict
-- 장비: 칸마다 하나씩 끼우고(가방 아이템은 그대로 둔다), 능력치와 전투력을 계산한다.
-- 무기 칸은 지금 손에 든 도구·무기다. 나머지 칸(헬멧·갑옷·신발·장갑·목걸이·팔찌)은 EquipItem으로 끼운다.
-- 클라이언트에 보이는 것: 플레이어 속성 Equip_<칸>(아이템 Id, 없으면 ""), StatAtk·StatDef·StatHp·StatCrit, CombatPower
-- 효과: 최대 체력 = BaseMaxHealth + 체력, 몹 피해 × 100/(100+방어), 무기 데미지 + 공격(무기 칸 제외), 치명타 확률 + 치명타%
-- 방패 칸의 화살통: 끼운 화살통의 남은 화살 수를 서버가 센다 (플레이어 속성 Arrows). 활 한 발에 1개 (CombatService가 useArrow)
--   0이 되면 화살통이 가방에서 사라지고, 가방에 다른 화살통이 있으면 바꿔 낀다
--   화살통은 개수로만 세는 아이템이라 "덜 쓴 화살통"은 종류마다 하나만 있을 수 있다 (내려놓으면 stash에 남은 수를 기억)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local EquipmentDefs = require(ReplicatedStorage.Shared.EquipmentDefs)
local PickaxeDefs = require(ReplicatedStorage.Shared.PickaxeDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local DataService = require(script.Parent.DataService)
local GearVisualService = require(script.Parent.GearVisualService)
local InventoryService = require(script.Parent.InventoryService)
local NotifyService = require(script.Parent.NotifyService)

export type Stats = { Atk: number, Def: number, Hp: number, Crit: number }

local EquipmentService = {}

local equipped: { [Player]: { [string]: string } } = {} -- 플레이어 → 칸 → 아이템 Id
local gearStats: { [Player]: Stats } = {} -- 무기 칸을 뺀 장비 합
local arrows: { [Player]: number } = {} -- 끼운 화살통에 남은 화살 수
local stash: { [Player]: { [string]: number } } = {} -- 내려놓은 덜 쓴 화살통: 화살통 Id → 남은 화살 수
local lastArrowNotice: { [Player]: number } = {}

local function emptyStats(): Stats
	return { Atk = 0, Def = 0, Hp = 0, Crit = 0 }
end

-- 장비 아이템 하나의 능력치
function EquipmentService.itemStats(itemId: string): Stats
	local stats = emptyStats()
	local def = EquipmentDefs.Items[itemId]
	if def then
		local base = (Config.Equipment.Base :: any)[def.Slot] or {}
		local multiplier = Config.Equipment.TierMultiplier[def.Tier] or 1
		for key in stats do
			stats[key] = math.round((base[key] or 0) * multiplier * 10) / 10
		end
		return stats
	end
	-- 무기·도구: 공격만
	local tool = PickaxeDefs[itemId]
	if tool then
		local weapon = Config.Weapons[itemId]
		local pickaxe = Config.Pickaxes[itemId]
		stats.Atk = if weapon then weapon.Damage elseif pickaxe then pickaxe.Power * Config.Equipment.ToolAtkPerPower else 0
	end
	return stats
end

-- 화살통 하나에 든 화살 수 (화살통이 아니면 0)
local function quiverCapacity(itemId: string): number
	local quiver = (Config.Quiver.Items :: any)[itemId]
	return if quiver then quiver.Arrows else 0
end

-- 등의 화살통에 꽂혀 보이는 화살 수
local function visibleArrows(player: Player): number
	return math.min(arrows[player] or 0, Config.Quiver.VisibleArrows)
end

-- 남은 화살 수를 바꾸고 클라이언트에 알린다 (속성 Arrows)
local function setArrows(player: Player, count: number)
	arrows[player] = count
	player:SetAttribute("Arrows", count)
end

-- 끼운 화살통을 내려놓는다: 덜 쓴 것이면 남은 수를 기억해 둔다 (다시 끼우면 그 수로)
local function stashQuiver(player: Player, itemId: string)
	local left = arrows[player] or 0
	local saved = stash[player]
	if saved and left > 0 and left < quiverCapacity(itemId) then
		saved[itemId] = left
	end
	setArrows(player, 0)
end

-- 화살통을 칸에 넣는다: 덜 쓴 같은 화살통이 있으면 그것부터, 아니면 새것(가득)
local function loadQuiver(player: Player, itemId: string)
	local saved = stash[player]
	local left = saved and saved[itemId]
	if saved then
		saved[itemId] = nil
	end
	setArrows(player, left or quiverCapacity(itemId))
end

-- 가방에 남은 화살통 중 다음에 낄 것 (덜 쓴 것 먼저, 그다음 QuiverOrder 순서)
local function nextQuiver(player: Player): string?
	local saved = stash[player]
	if saved then
		for itemId in saved do
			if InventoryService.count(player, itemId) > 0 then
				return itemId
			end
		end
	end
	for _, itemId in EquipmentDefs.QuiverOrder do
		if InventoryService.count(player, itemId) > 0 then
			return itemId
		end
	end
	return nil
end

-- 손에 든 도구·무기 Id
local function heldItem(player: Player): string?
	local character = player.Character
	local tool = character and character:FindFirstChildWhichIsA("Tool")
	local id = tool and tool:GetAttribute("PickaxeId")
	return if typeof(id) == "string" and InventoryService.count(player, id) > 0 then id else nil
end

-- 능력치·전투력 다시 계산해서 속성과 최대 체력에 반영
local function recompute(player: Player)
	local slots = equipped[player] or {}
	local gear = emptyStats()
	for _, itemId in slots do
		local s = EquipmentService.itemStats(itemId)
		for key, value in s do
			gear[key] += value
		end
	end
	gearStats[player] = gear

	local total = table.clone(gear)
	local held = heldItem(player)
	if held then
		total.Atk += EquipmentService.itemStats(held).Atk
	end
	local weights = Config.Equipment.PowerWeights
	local power = math.round(total.Atk * weights.Atk + total.Def * weights.Def + total.Hp * weights.Hp + total.Crit * weights.Crit)

	for _, slot in EquipmentDefs.Slots do
		local id = if slot.Id == "Weapon" then held else slots[slot.Id]
		player:SetAttribute(`Equip_{slot.Id}`, id or "")
	end
	player:SetAttribute("StatAtk", total.Atk)
	player:SetAttribute("StatDef", total.Def)
	player:SetAttribute("StatHp", total.Hp)
	player:SetAttribute("StatCrit", total.Crit)
	player:SetAttribute("CombatPower", power)

	-- 착용 장비를 캐릭터 모양으로 (같은 장비면 아무것도 안 한다)
	GearVisualService.apply(player, slots, visibleArrows(player))

	-- 최대 체력: 비율은 유지
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local maxHealth = Config.Equipment.BaseMaxHealth + total.Hp
		if humanoid.MaxHealth ~= maxHealth then
			local ratio = if humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 1
			humanoid.MaxHealth = maxHealth
			humanoid.Health = math.min(maxHealth, maxHealth * ratio)
		end
	end
end

-- 장비 끼우기 (같은 칸에 있던 것은 빠진다)
function EquipmentService.equip(player: Player, itemId: string)
	local def = EquipmentDefs.Items[itemId]
	if not def or InventoryService.count(player, itemId) <= 0 then
		return
	end
	local slots = equipped[player] or {}
	equipped[player] = slots
	if def.Slot == "Shield" then
		if slots.Shield == itemId then
			return -- 이미 끼운 화살통 (다시 끼워서 화살을 채우는 일이 없게)
		end
		if slots.Shield then
			stashQuiver(player, slots.Shield)
		end
		slots.Shield = itemId
		loadQuiver(player, itemId)
		recompute(player)
		NotifyService.send(player, `{def.DisplayName} 착용 (화살 {arrows[player] or 0}개)`, "good")
		return
	end
	slots[def.Slot] = itemId
	recompute(player)
	NotifyService.send(player, `{def.DisplayName} 착용`, "good")
end

-- 장비 빼기
function EquipmentService.unequip(player: Player, slot: string)
	local slots = equipped[player]
	if slots and slots[slot] then
		if slot == "Shield" then
			stashQuiver(player, slots[slot])
		end
		slots[slot] = nil
		recompute(player)
	end
end

-- 끼운 화살통에 남은 화살 수
function EquipmentService.getArrows(player: Player): number
	return arrows[player] or 0
end

-- 활 한 발: 화살 1개를 쓴다. 화살이 없으면 알림 후 false
-- 0이 되면 화살통을 가방에서 지우고, 다른 화살통이 있으면 바꿔 낀다
function EquipmentService.useArrow(player: Player): boolean
	local slots = equipped[player]
	local quiver = slots and slots.Shield
	if not slots or not quiver or (arrows[player] or 0) <= 0 then
		local now = os.clock()
		if now - (lastArrowNotice[player] or -math.huge) >= Config.Quiver.NoticeInterval then
			lastArrowNotice[player] = now
			local message = if quiver then "화살이 없어요!" else "화살통이 필요해요! 사냥꾼에게 사서 방패 칸에 끼우세요."
			NotifyService.send(player, message, "bad")
		end
		return false
	end
	local shownBefore = visibleArrows(player)
	setArrows(player, (arrows[player] or 0) - 1)
	if (arrows[player] or 0) > 0 then
		-- 7개 아래로 줄면 등에 꽂힌 화살도 하나씩 줄어든다
		if visibleArrows(player) ~= shownBefore then
			GearVisualService.apply(player, slots, visibleArrows(player))
		end
		return true
	end

	-- 다 썼다: 칸에서 먼저 빼고 가방에서 지운다
	local name = EquipmentDefs.Items[quiver].DisplayName
	slots.Shield = nil
	setArrows(player, 0)
	InventoryService.remove(player, quiver, 1)
	NotifyService.send(player, `화살을 다 썼어요! {name}이 사라졌어요.`, "bad")
	local nextId = nextQuiver(player)
	if nextId then
		slots.Shield = nextId
		loadQuiver(player, nextId)
		NotifyService.send(player, `{EquipmentDefs.Items[nextId].DisplayName}로 바꿔 꼈어요. (화살 {arrows[player] or 0}개)`, "good")
	end
	recompute(player)
	return true
end

-- 무기 칸을 뺀 장비 능력치 (CombatService가 공격·치명타에 더한다)
function EquipmentService.getGearStats(player: Player): Stats
	return gearStats[player] or emptyStats()
end

-- 몹에게 받는 피해를 방어로 줄인다
function EquipmentService.reduceDamage(player: Player, damage: number): number
	local def = player:GetAttribute("StatDef")
	local defense = if typeof(def) == "number" then def else 0
	return math.max(1, math.round(damage * 100 / (100 + defense)))
end

-- 서버 시작 시 한 번 호출 (InventoryService.init 이후)
function EquipmentService.init()
	-- 저장할 칸: 끼운 장비 (칸 → 아이템 Id)
	DataService.register("Equipped", function(player: Player)
		local slots = equipped[player]
		return if slots then table.clone(slots) else nil
	end)
	-- 저장할 칸: 끼운 화살통의 남은 화살 수 + 내려놓은 덜 쓴 화살통
	DataService.register("Quivers", function(player: Player)
		local saved = stash[player]
		if not saved then
			return nil
		end
		return { Arrows = arrows[player] or 0, Stash = table.clone(saved) }
	end)

	local function onPlayerAdded(player: Player)
		equipped[player] = {}
		stash[player] = {}
		setArrows(player, 0)
		-- 저장된 장비를 다시 끼운다 (가방에 있고 칸이 맞는 것만)
		if InventoryService.waitLoaded(player) then
			local saved = DataService.load(player).Equipped
			if typeof(saved) == "table" then
				for slot, itemId in saved do
					local def = typeof(itemId) == "string" and EquipmentDefs.Items[itemId]
					if def and def.Slot == slot and InventoryService.count(player, itemId) > 0 then
						equipped[player][slot] = itemId
					end
				end
			end
			-- 화살통: 덜 쓴 화살통과 끼운 화살통의 남은 화살 수 (가진 개수·화살통 크기 안에서만)
			local quivers = DataService.load(player).Quivers
			local worn = equipped[player].Shield
			if typeof(quivers) == "table" then
				if typeof(quivers.Stash) == "table" then
					for itemId, left in quivers.Stash do
						local spare = if typeof(itemId) == "string" then InventoryService.count(player, itemId) - (if worn == itemId then 1 else 0) else 0
						if spare > 0 and typeof(left) == "number" then
							local capacity = quiverCapacity(itemId)
							if left >= 1 and left < capacity then
								stash[player][itemId] = math.floor(left)
							end
						end
					end
				end
				if worn and typeof(quivers.Arrows) == "number" and quivers.Arrows >= 1 then
					setArrows(player, math.min(math.floor(quivers.Arrows), quiverCapacity(worn)))
				elseif worn then
					setArrows(player, quiverCapacity(worn))
				end
			elseif worn then
				setArrows(player, quiverCapacity(worn))
			end
		end
		if not player.Parent then
			return
		end
		local function watchCharacter(character: Model)
			-- 손에 드는 도구가 바뀌면 무기 칸·전투력 다시 계산
			character.ChildAdded:Connect(function(child)
				if child:IsA("Tool") then
					recompute(player)
				end
			end)
			character.ChildRemoved:Connect(function(child)
				if child:IsA("Tool") then
					recompute(player)
				end
			end)
			task.defer(recompute, player)
			-- 아바타 외형(몸 부품 크기·머리카락)이 다 들어오면 장비 모양을 다시 맞춘다
			task.spawn(function()
				if not player:HasAppearanceLoaded() then
					player.CharacterAppearanceLoaded:Wait()
				end
				if character.Parent then
					GearVisualService.invalidate(character)
					recompute(player)
				end
			end)
		end
		player.CharacterAdded:Connect(watchCharacter)
		if player.Character then
			watchCharacter(player.Character)
		end
		recompute(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		-- DataService가 나갈 때 장비를 모아 저장할 수 있게 조금 뒤에 지운다
		task.delay(Config.Save.CleanupDelay, function()
			equipped[player] = nil
			gearStats[player] = nil
			arrows[player] = nil
			stash[player] = nil
			lastArrowNotice[player] = nil
		end)
	end)

	-- 가방에서 사라진 장비는 벗긴다 (판매 등)
	InventoryService.Changed:Connect(function(player: Player)
		local slots = equipped[player]
		if not slots then
			return
		end
		local changed = false
		for slot, itemId in slots do
			if InventoryService.count(player, itemId) <= 0 then
				slots[slot] = nil
				changed = true
				if slot == "Shield" then
					setArrows(player, 0)
				end
			end
		end
		-- 덜 쓴 화살통 기록도 가방에 남은 것만
		local saved = stash[player]
		if saved then
			for itemId in saved do
				local spare = InventoryService.count(player, itemId) - (if slots.Shield == itemId then 1 else 0)
				if spare <= 0 then
					saved[itemId] = nil
				end
			end
		end
		if changed then
			recompute(player)
		end
	end)

	Remotes.get(Remotes.Names.EquipItem).OnServerEvent:Connect(function(player, itemId)
		if typeof(itemId) == "string" then
			EquipmentService.equip(player, itemId)
		end
	end)
	Remotes.get(Remotes.Names.UnequipSlot).OnServerEvent:Connect(function(player, slot)
		if typeof(slot) == "string" then
			EquipmentService.unequip(player, slot)
		end
	end)
end

return EquipmentService
