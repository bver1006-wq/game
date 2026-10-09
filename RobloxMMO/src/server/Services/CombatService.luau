--!strict
-- 무기로 몹 공격: 요청 검증, 데미지(치명타 포함), 연출 알림. 사냥꾼 상점의 무기 구매도 여기서 받는다.
-- 클라이언트는 "이 몹을 공격했다"만 보낸다. 들고 있는 무기·거리·쿨다운·데미지는 전부 서버가 정한다.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local EquipmentDefs = require(ReplicatedStorage.Shared.EquipmentDefs)
local ItemDefs = require(ReplicatedStorage.Shared.ItemDefs)
local PickaxeDefs = require(ReplicatedStorage.Shared.PickaxeDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local ChargeService = require(script.Parent.ChargeService)
local CraftingService = require(script.Parent.CraftingService)
local EquipmentService = require(script.Parent.EquipmentService)
local InventoryService = require(script.Parent.InventoryService)
local FeverService = require(script.Parent.FeverService)
local ManaService = require(script.Parent.ManaService)
local MobService = require(script.Parent.MobService)
local NotifyService = require(script.Parent.NotifyService)
local NpcService = require(script.Parent.NpcService)
local PickaxeService = require(script.Parent.PickaxeService)

local SHOP_ID = "Hunter"
local WEAPON_KINDS: { [string]: boolean } = { Sword = true, Bow = true, Club = true }

local CombatService = {}

local random = Random.new()
local effectRemote: RemoteEvent
local lastAttack: { [Player]: number } = {}

-- 위치 근처의 플레이어에게 이벤트를 보낸다
local function fireNearby(position: Vector3, ...: any)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - position).Magnitude <= Config.Combat.MobBroadcastRange then
			effectRemote:FireClient(player, ...)
		end
	end
end

-- AttackRequest 처리. 인자는 전부 의심하고 검사한다
local function onAttack(player: Player, mobArg: unknown)
	-- 모은 정도는 요청이 오면 무조건 꺼낸다 (거절돼도 느린 걸음이 남지 않게)
	local charge, held = ChargeService.consume(player)
	if typeof(mobArg) ~= "Instance" or not (mobArg :: Instance):IsA("Model") then
		return
	end
	local mob = mobArg :: Model
	if not CollectionService:HasTag(mob, MobService.Tag) then
		return
	end
	local state = MobService.getState(mob)
	if not state or FeverService.isActive(player) then
		return
	end

	-- 무기를 들고 있는가
	local weapon = PickaxeService.getEquipped(player)
	if not weapon or not WEAPON_KINDS[weapon.Kind] then
		return
	end
	local config = Config.Weapons[weapon.Id]
	if not config then
		return
	end

	-- 쿨다운
	local now = os.clock()
	if now - (lastAttack[player] or -math.huge) < config.Cooldown - Config.Combat.CooldownTolerance then
		return
	end

	-- 모은 정도: 활은 짧게 쏘면 사거리·데미지가 줄고, 나머지는 다 모으면 마나를 써서 강타
	local chargeConfig = Config.Charge
	local range = config.Range
	local chargeMultiplier = 1
	local charged = false
	if weapon.Kind == "Bow" then
		range *= chargeConfig.BowTapRange + (1 - chargeConfig.BowTapRange) * charge
		chargeMultiplier = chargeConfig.BowTapDamage + (1 - chargeConfig.BowTapDamage) * charge
	end

	-- 거리 (몹 몸 크기만큼 봐준다)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local flat = (state.Position - root.Position) * Vector3.new(1, 0, 1)
	if flat.Magnitude > range + state.Radius + Config.Combat.RangeTolerance then
		return
	end
	lastAttack[player] = now
	if weapon.Kind ~= "Bow" and charge >= 1 and ManaService.spend(player, chargeConfig.ManaCost) then
		chargeMultiplier = chargeConfig.Multiplier
		charged = true
	elseif weapon.Kind == "Bow" and held >= chargeConfig.Time + chargeConfig.BowOverTime and ManaService.spend(player, chargeConfig.ManaCost) then
		-- 활 추가 차징(마나가 모인 2단계)까지 다 모았으면 강타
		chargeMultiplier = chargeConfig.BowOverMultiplier
		charged = true
	end

	-- 데미지: 기본 × (1 ± 흔들림), 치명타면 배수
	local combat = Config.Combat
	-- 장비 공격은 무기 데미지에 더하고, 장비 치명타는 확률에 더한다
	local gear = EquipmentService.getGearStats(player)
	local damage = (config.Damage + gear.Atk) * chargeMultiplier * (1 + random:NextNumber(-combat.DamageSpread, combat.DamageSpread))
	local isCrit = random:NextNumber() < combat.CritChance + gear.Crit / 100
	if isCrit then
		damage *= combat.CritMultiplier
	end
	damage = math.max(math.round(damage), 1)

	local direction = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zAxis
	local hitPosition = state.Position + Vector3.new(0, state.Height * 0.5, 0) - direction * state.Radius * 0.6
	local fromPosition = root.Position + Vector3.new(0, 1, 0)
	fireNearby(state.Position, mob, damage, isCrit, weapon.Kind, weapon.Tier, player.UserId, fromPosition, hitPosition, charged)
	MobService.damage(mob, player, damage, direction, config.Knockback)
end

-- 사냥꾼 상점: 장비 구매 (같은 장비는 하나만)
local function buyEquipment(player: Player, itemId: string)
	local def = EquipmentDefs.Items[itemId]
	if not def then
		return
	end
	if InventoryService.count(player, itemId) > 0 then
		NotifyService.send(player, "이미 가지고 있는 장비예요.", "info")
		return
	end
	local price = Config.Equipment.Prices[def.Tier]
	if InventoryService.getGold(player) < price.Gold then
		NotifyService.send(player, `골드가 모자라요. ({price.Gold}G 필요)`, "bad")
		return
	end
	if not InventoryService.hasAll(player, price.Items) then
		local parts = {}
		for id, amount in price.Items do
			table.insert(parts, `{ItemDefs.Items[id].DisplayName} {amount}`)
		end
		NotifyService.send(player, `재료가 모자라요. (필요: {table.concat(parts, ", ")})`, "bad")
		return
	end
	if InventoryService.freeSlots(player) < 1 then
		NotifyService.send(player, "가방에 빈 칸이 없어요.", "bad")
		return
	end
	InventoryService.removeAll(player, price.Items)
	InventoryService.spendGold(player, price.Gold)
	InventoryService.add(player, itemId, 1)
	NotifyService.send(player, `{def.DisplayName} 구매 완료! 가방에서 더블클릭하면 착용해요.`, "good")
end

-- 사냥꾼 상점: 무기·장비 구매
local function onShopAction(player: Player, shopId: unknown, action: unknown, idArg: unknown)
	if shopId ~= SHOP_ID or typeof(idArg) ~= "string" then
		return
	end
	if action == "BuyEquipment" then
		if NpcService.isNear(player, SHOP_ID) then
			buyEquipment(player, idArg)
		else
			NotifyService.send(player, "사냥꾼에게 더 가까이 가세요.", "bad")
		end
		return
	end
	if action ~= "BuyWeapon" then
		return
	end
	local def = PickaxeDefs[idArg]
	if not def or not WEAPON_KINDS[def.Kind] then
		return
	end
	if not NpcService.isNear(player, SHOP_ID) then
		NotifyService.send(player, "사냥꾼에게 더 가까이 가세요.", "bad")
		return
	end
	CraftingService.buyTool(player, idArg, def.Kind)
end

-- 서버 시작 시 한 번 호출 (MobService.init 이후)
function CombatService.init()
	effectRemote = Remotes.get(Remotes.Names.CombatEffect)
	Remotes.get(Remotes.Names.AttackRequest).OnServerEvent:Connect(onAttack)
	Remotes.get(Remotes.Names.ShopAction).OnServerEvent:Connect(onShopAction)
	Players.PlayerRemoving:Connect(function(player)
		lastAttack[player] = nil
	end)
end

return CombatService
