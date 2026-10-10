--!strict
-- 무기로 몹 공격: 요청 검증, 데미지(치명타 포함), 연출 알림. 사냥꾼 상점의 무기 구매도 여기서 받는다.
-- 클라이언트는 "이 몹을 공격했다"만 보낸다. 들고 있는 무기·거리·쿨다운·데미지는 전부 서버가 정한다.
-- 활은 끼운 화살통의 화살을 한 발에 1개 쓴다 (EquipmentService.useArrow). 빗나간 화살(몹 없이 쏨)은 몹 없이 AttackRequest(nil)로 와서 화살만 쓴다.

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
local MobDefs = require(ReplicatedStorage.Shared.MobDefs)
local NotifyService = require(script.Parent.NotifyService)
local NpcService = require(script.Parent.NpcService)
local OwnershipService = require(script.Parent.OwnershipService)
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

-- 활을 몹 없이 쏨 (빗나간 화살): 활을 들고 쿨다운이 지났으면 화살 1개만 쓴다
local function shootAtNothing(player: Player)
	if FeverService.isActive(player) then
		return
	end
	local weapon = PickaxeService.getEquipped(player)
	if not weapon or weapon.Kind ~= "Bow" then
		return
	end
	local config = Config.Weapons[weapon.Id]
	if not config then
		return
	end
	local now = os.clock()
	if now - (lastAttack[player] or -math.huge) < config.Cooldown - Config.Combat.CooldownTolerance then
		return
	end
	if EquipmentService.useArrow(player) then
		lastAttack[player] = now
	end
end

-- 몹 하나에 무기 타격을 적용한다: 데미지(장비 공격·치명타·흔들림) → 장비 벽 → 연출 알림 → 피해.
-- 검증(무기·거리·쿨다운·주인·화살)은 부르는 쪽이 끝낸 뒤 부른다. 실제로 준 데미지를 돌려준다 (장비 벽에 막히면 0)
-- fromSkill: 스킬(연사·내려찍기)로 친 것. 활이면 내 화면에서도 화살을 그린다 (보통 공격은 쏠 때 이미 그림)
local function applyHit(
	player: Player,
	weapon: PickaxeDefs.PickaxeDef,
	config: any,
	mob: Model,
	state: MobService.MobState,
	root: BasePart,
	chargeMultiplier: number,
	charged: boolean,
	knockback: number?,
	fromSkill: boolean
): number
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

	-- 장비 벽: 무기 단계가 몹보다 많이 낮으면 데미지가 안 들어가고, 1단계 낮으면 줄어든다
	local mobDef = MobDefs[state.Type]
	local gap = (if mobDef then mobDef.Tier else 1) - weapon.Tier
	local blocked = gap >= Config.TierWall.BlockGap
	if blocked then
		damage = 0
		isCrit = false
		charged = false
	elseif gap == 1 then
		damage = math.max(math.round(damage * Config.TierWall.OneTierLowMultiplier), 1)
	end

	local flat = (state.Position - root.Position) * Vector3.new(1, 0, 1)
	local direction = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zAxis
	local hitPosition = state.Position + Vector3.new(0, state.Height * 0.5, 0) - direction * state.Radius * 0.6
	local fromPosition = root.Position + Vector3.new(0, 1, 0)
	fireNearby(state.Position, mob, damage, isCrit, weapon.Kind, weapon.Tier, player.UserId, fromPosition, hitPosition, charged, blocked, fromSkill)
	-- 흠집도 안 나면 몹 위 "흠집도 안 나!" 문구만 (알림 창은 안 띄운다, 2026-10-09)
	MobService.damage(mob, player, damage, direction, if blocked then nil else knockback)
	return damage
end

-- AttackRequest 처리. 인자는 전부 의심하고 검사한다
local function onAttack(player: Player, mobArg: unknown)
	-- 모은 정도는 요청이 오면 무조건 꺼낸다 (거절돼도 느린 걸음이 남지 않게)
	local charge, held = ChargeService.consume(player)
	if mobArg == nil then
		shootAtNothing(player)
		return
	end
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
	-- 다른 사람이 사냥 중인 몹은 못 친다
	if not OwnershipService.canHit(state, player) then
		OwnershipService.notifyBlocked(player, "다른 사람이 사냥 중인 몹이에요.")
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
	-- 물 속 몹(바다 생물)은 위아래 거리도 본다: 물가에 서서 깊은 바닥의 물고기를 칼로 칠 수는 없다 (2026-10-09)
	if state.Swim then
		local dy = math.abs(state.Position.Y + state.Height / 2 - root.Position.Y)
		if dy > range + state.Height / 2 + Config.Combat.RangeTolerance then
			return
		end
	end
	-- 활: 화살이 있어야 쏜다 (한 발에 1개)
	if weapon.Kind == "Bow" and not EquipmentService.useArrow(player) then
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

	applyHit(player, weapon, config, mob, state, root, chargeMultiplier, charged, config.Knockback, false)
end

-- 사냥꾼 상점: 화살통 구매 (여러 개 가질 수 있다. 가격은 Config.Quiver.Items)
local function buyQuiver(player: Player, itemId: string)
	local def = EquipmentDefs.Items[itemId]
	local quiver = (Config.Quiver.Items :: any)[itemId]
	if not def or def.Slot ~= "Shield" or not quiver then
		return
	end
	local price = quiver.Price
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
	local worn = player:GetAttribute("Equip_Shield")
	if worn == nil or worn == "" then
		-- 화살통을 안 끼고 있으면 바로 끼워 준다
		EquipmentService.equip(player, itemId)
	elseif typeof(worn) == "string" and not (Config.Quiver.Items :: any)[worn] then
		-- 방패를 차고 있으면 그대로 둔다 (2026-10-10). 활을 쓸 때 가방에서 화살통을 끼우면 된다
		NotifyService.send(player, `{def.DisplayName} 구매 완료! (화살 {quiver.Arrows}개) 활을 쓸 땐 방패 대신 가방에서 끼우세요.`, "good")
	else
		NotifyService.send(player, `{def.DisplayName} 구매 완료! (화살 {quiver.Arrows}개) 지금 화살통을 다 쓰면 저절로 바꿔 껴요.`, "good")
	end
end

-- 사냥꾼 상점: 무기·장비 조합(1단계는 구매), 화살통 구매
-- 조합식은 Config.Recipes (아래 단계 3개 + 재료 + 골드, CraftingService.craft)
local function onShopAction(player: Player, shopId: unknown, action: unknown, idArg: unknown, timesArg: unknown)
	if shopId ~= SHOP_ID or typeof(idArg) ~= "string" then
		return
	end
	if action ~= "BuyQuiver" and action ~= "Craft" then
		return
	end
	if not NpcService.isNear(player, SHOP_ID) then
		NotifyService.send(player, "사냥꾼에게 더 가까이 가세요.", "bad")
		return
	end
	if action == "BuyQuiver" then
		buyQuiver(player, idArg)
		return
	end
	-- 사냥꾼은 칼·활·방망이와 장비(방패 포함, 화살통은 BuyQuiver)만 만든다
	local weapon = PickaxeDefs[idArg]
	local equipment = EquipmentDefs.Items[idArg]
	if (weapon and WEAPON_KINDS[weapon.Kind]) or (equipment and not equipment.Quiver) then
		CraftingService.craft(player, idArg, CraftingService.readTimes(timesArg))
	end
end

-- 스킬 타격 (SkillService: 활 연사·방망이 내려찍기). 들고 있는 무기로 몹 하나를 multiplier배로 친다
-- 주인·무기 확인은 여기서도 하고, 거리·마나·쿨다운·화살은 SkillService가 확인한다. 실제로 준 데미지 (못 쳤으면 0)
function CombatService.skillHit(player: Player, mob: Model, multiplier: number, knockback: number?): number
	local state = MobService.getState(mob)
	if not state or FeverService.isActive(player) or not OwnershipService.canHit(state, player) then
		return 0
	end
	local weapon = PickaxeService.getEquipped(player)
	local config = weapon and Config.Weapons[weapon.Id]
	if not weapon or not config or not WEAPON_KINDS[weapon.Kind] then
		return 0
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return 0
	end
	return applyHit(player, weapon, config, mob, state, root, multiplier, false, knockback, true)
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
