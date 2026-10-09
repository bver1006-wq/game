--!strict
-- 무기로 몹 공격: 요청 검증, 데미지(치명타 포함), 연출 알림. 사냥꾼 상점의 무기 구매도 여기서 받는다.
-- 클라이언트는 "이 몹을 공격했다"만 보낸다. 들고 있는 무기·거리·쿨다운·데미지는 전부 서버가 정한다.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PickaxeDefs = require(ReplicatedStorage.Shared.PickaxeDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local CraftingService = require(script.Parent.CraftingService)
local FeverService = require(script.Parent.FeverService)
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

	-- 거리 (몹 몸 크기만큼 봐준다)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local flat = (state.Position - root.Position) * Vector3.new(1, 0, 1)
	if flat.Magnitude > config.Range + state.Radius + Config.Combat.RangeTolerance then
		return
	end
	lastAttack[player] = now

	-- 데미지: 기본 × (1 ± 흔들림), 치명타면 배수
	local combat = Config.Combat
	local damage = config.Damage * (1 + random:NextNumber(-combat.DamageSpread, combat.DamageSpread))
	local isCrit = random:NextNumber() < combat.CritChance
	if isCrit then
		damage *= combat.CritMultiplier
	end
	damage = math.max(math.round(damage), 1)

	local direction = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zAxis
	local hitPosition = state.Position + Vector3.new(0, state.Height * 0.5, 0) - direction * state.Radius * 0.6
	local fromPosition = root.Position + Vector3.new(0, 1, 0)
	fireNearby(state.Position, mob, damage, isCrit, weapon.Kind, weapon.Tier, player.UserId, fromPosition, hitPosition)
	MobService.damage(mob, player, damage, direction, config.Knockback)
end

-- 사냥꾼 상점: 무기 구매
local function onShopAction(player: Player, shopId: unknown, action: unknown, idArg: unknown)
	if shopId ~= SHOP_ID or action ~= "BuyWeapon" or typeof(idArg) ~= "string" then
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
