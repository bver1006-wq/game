--!strict
-- 소모품 쓰기 (빠른 호출 칸에서 누름). 귀환 주문서와 음식(체력·마나 회복, Config.Foods).
-- 귀환 주문서: CastTime초 동안 캐릭터 주변에 빛이 돌고, 끝나면 1장을 쓰고 마을(태그 TownArrival)로 옮긴다.
-- 그사이 움직이거나 다시 누르면 취소된다. 주문서는 다 쓴 다음에만 줄어든다.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ItemDefs = require(ReplicatedStorage.Shared.ItemDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local FeverService = require(script.Parent.FeverService)
local InventoryService = require(script.Parent.InventoryService)
local ManaService = require(script.Parent.ManaService)
local NotifyService = require(script.Parent.NotifyService)

local TOWN_TAG = "TownArrival"

local ItemUseService = {}

local casting: { [Player]: number } = {} -- 플레이어 → 진행 중인 귀환의 번호 (취소 판별용)
local castCounter = 0
local lastEat: { [Player]: { [string]: number } } = {} -- 플레이어 → 음식 Id → 마지막으로 먹은 시각
local cooldownRemote: RemoteEvent

-- 음식 먹기: 체력·마나를 채운다. 둘 다 가득이면 먹지 않는다
local function eat(player: Player, itemId: string)
	local food = Config.Foods[itemId]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not food or not humanoid or humanoid.Health <= 0 then
		return
	end
	local now = os.clock()
	local eaten = lastEat[player] or {}
	lastEat[player] = eaten
	if now - (eaten[itemId] or -math.huge) < Config.FoodCooldown then
		NotifyService.send(player, `{ItemDefs.Items[itemId].DisplayName}: 조금 있다가 다시 먹을 수 있어요.`, "info")
		return
	end
	local needsHp = (food.Hp or 0) > 0 and humanoid.Health < humanoid.MaxHealth
	local needsMana = (food.Mana or 0) > 0 and not ManaService.isFull(player)
	if not needsHp and not needsMana then
		NotifyService.send(player, "체력과 마나가 이미 가득해요.", "info")
		return
	end
	if not InventoryService.remove(player, itemId, 1) then
		return
	end
	eaten[itemId] = now
	cooldownRemote:FireClient(player, itemId, Config.FoodCooldown)
	local parts = {}
	if food.Hp then
		local before = humanoid.Health
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + food.Hp)
		table.insert(parts, `체력 +{math.floor(humanoid.Health - before + 0.5)}`)
	end
	if food.Mana then
		table.insert(parts, `마나 +{math.floor(ManaService.add(player, food.Mana) + 0.5)}`)
	end
	NotifyService.send(player, `{ItemDefs.Items[itemId].DisplayName}: {table.concat(parts, ", ")}`, "good")
end

-- 캐릭터에 귀환 빛 효과를 붙인다 (서버에서 만들어 모두에게 보인다)
local function attachCastEffect(root: BasePart): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = "ReturnCastEffect"
	attachment.Parent = root
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(150, 220, 255))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.5, 0)
	emitter.Lifetime = NumberRange.new(0.6, 1)
	emitter.Rate = 40
	emitter.Speed = NumberRange.new(2, 4)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 6, 0)
	emitter.Parent = attachment
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(150, 220, 255)
	light.Range = 10
	light.Brightness = 2
	light.Parent = attachment
	return attachment
end

-- 마을 도착 지점
local function findTown(): BasePart?
	for _, part in CollectionService:GetTagged(TOWN_TAG) do
		if part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

-- 귀환 주문서 사용
local function useReturnScroll(player: Player)
	if casting[player] then
		casting[player] = nil -- 다시 누르면 취소
		NotifyService.send(player, "귀환을 취소했어요.", "info")
		return
	end
	if FeverService.isActive(player) then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local town = findTown()
	if not root or not root:IsA("BasePart") or not town then
		return
	end

	castCounter += 1
	local castId = castCounter
	casting[player] = castId
	local startPosition = root.Position
	local effect = attachCastEffect(root)
	NotifyService.send(player, `귀환 중... ({Config.ReturnScroll.CastTime}초, 움직이면 취소)`, "info")

	local elapsed = 0
	while elapsed < Config.ReturnScroll.CastTime do
		elapsed += task.wait(0.1)
		local moved = root.Parent and (root.Position - startPosition).Magnitude > Config.ReturnScroll.CancelMoveDistance
		if casting[player] ~= castId or not root.Parent or moved then
			if casting[player] == castId then
				casting[player] = nil
				NotifyService.send(player, "움직여서 귀환이 취소됐어요.", "bad")
			end
			effect:Destroy()
			return
		end
	end
	casting[player] = nil
	effect:Destroy()

	if not InventoryService.remove(player, "ReturnScroll", 1) then
		return
	end
	local target = town.CFrame + Vector3.new(0, 3, 0)
	pcall(function()
		player:RequestStreamAroundAsync(target.Position)
	end)
	if character and character.Parent then
		character:PivotTo(target)
		NotifyService.send(player, "마을로 돌아왔어요.", "good")
	end
end

-- UseItem 처리
local function onUseItem(player: Player, itemArg: unknown)
	if typeof(itemArg) ~= "string" then
		return
	end
	local def = ItemDefs.Items[itemArg]
	if not def or not def.Usable or InventoryService.count(player, itemArg) <= 0 then
		return
	end
	if itemArg == "ReturnScroll" then
		task.spawn(useReturnScroll, player)
	elseif Config.Foods[itemArg] then
		eat(player, itemArg)
	end
end

-- 서버 시작 시 한 번 호출
function ItemUseService.init()
	cooldownRemote = Remotes.get(Remotes.Names.ItemCooldown)
	Remotes.get(Remotes.Names.UseItem).OnServerEvent:Connect(onUseItem)
	Players.PlayerRemoving:Connect(function(player)
		casting[player] = nil
		lastEat[player] = nil
	end)
end

return ItemUseService
