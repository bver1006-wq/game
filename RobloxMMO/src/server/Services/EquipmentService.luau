--!strict
-- 장비: 칸마다 하나씩 끼우고(가방 아이템은 그대로 둔다), 능력치와 전투력을 계산한다.
-- 무기 칸은 지금 손에 든 도구·무기다. 나머지 칸(헬멧·갑옷·신발·장갑·목걸이·팔찌)은 EquipItem으로 끼운다.
-- 클라이언트에 보이는 것: 플레이어 속성 Equip_<칸>(아이템 Id, 없으면 ""), StatAtk·StatDef·StatHp·StatCrit, CombatPower
-- 효과: 최대 체력 = BaseMaxHealth + 체력, 몹 피해 × 100/(100+방어), 무기 데미지 + 공격(무기 칸 제외), 치명타 확률 + 치명타%

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local EquipmentDefs = require(ReplicatedStorage.Shared.EquipmentDefs)
local PickaxeDefs = require(ReplicatedStorage.Shared.PickaxeDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local InventoryService = require(script.Parent.InventoryService)
local NotifyService = require(script.Parent.NotifyService)

export type Stats = { Atk: number, Def: number, Hp: number, Crit: number }

local EquipmentService = {}

local equipped: { [Player]: { [string]: string } } = {} -- 플레이어 → 칸 → 아이템 Id
local gearStats: { [Player]: Stats } = {} -- 무기 칸을 뺀 장비 합

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
	slots[def.Slot] = itemId
	recompute(player)
	NotifyService.send(player, `{def.DisplayName} 착용`, "good")
end

-- 장비 빼기
function EquipmentService.unequip(player: Player, slot: string)
	local slots = equipped[player]
	if slots and slots[slot] then
		slots[slot] = nil
		recompute(player)
	end
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
	local function onPlayerAdded(player: Player)
		equipped[player] = {}
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
		equipped[player] = nil
		gearStats[player] = nil
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
