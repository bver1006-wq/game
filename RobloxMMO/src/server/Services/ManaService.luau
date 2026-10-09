--!strict
-- 마나·이동 속도·마을 회복.
-- 마나는 플레이어 속성 Mana·MaxMana로 클라이언트에 보인다. 스킬·차징 강타·구르기에 쓴다.
-- 2026-10-09: 달리기 버튼을 없애고 항상 달린다(Movement.RunSpeed). 체력·마나는 마을(안전지대) 안에서만 서서히 찬다
--   마을 밖에서는 음식으로만 회복. 플레이어 속성 InTown으로 클라에 알린다

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local ManaService = {}

local lastSpend: { [Player]: number } = {}

local function getMana(player: Player): number
	local mana = player:GetAttribute("Mana")
	return if typeof(mana) == "number" then mana else 0
end

local function setMana(player: Player, value: number)
	local clamped = math.clamp(value, 0, Config.Mana.Max)
	-- 속성 복제를 줄이려고 소수 첫째 자리까지만
	player:SetAttribute("Mana", math.floor(clamped * 10 + 0.5) / 10)
end

-- 지금 마나
function ManaService.get(player: Player): number
	return getMana(player)
end

-- 마나를 쓴다. 모자라면 쓰지 않고 false (스킬·차징 스매시용)
function ManaService.spend(player: Player, amount: number): boolean
	if getMana(player) < amount then
		return false
	end
	setMana(player, getMana(player) - amount)
	lastSpend[player] = os.clock()
	return true
end

-- 마나를 채운다 (음식 등). 실제로 채운 양을 돌려준다
function ManaService.add(player: Player, amount: number): number
	local before = getMana(player)
	setMana(player, before + amount)
	return getMana(player) - before
end

-- 마나가 가득 찼는지
function ManaService.isFull(player: Player): boolean
	return getMana(player) >= Config.Mana.Max
end

-- 마을(안전지대) 중심들. TownArrival 부품과 상점 NPC 위치 (몇 초마다 다시 찾는다)
local townCenters: { Vector3 } = {}
local lastTownScan = -math.huge

local function refreshTownCenters()
	local centers: { Vector3 } = {}
	for _, part in CollectionService:GetTagged("TownArrival") do
		if part:IsA("BasePart") then
			table.insert(centers, part.Position)
		end
	end
	for _, npc in CollectionService:GetTagged("ShopNPC") do
		if npc:IsA("Model") then
			table.insert(centers, npc:GetPivot().Position)
		end
	end
	townCenters = centers
end

-- 이 위치가 마을 안인가 (몹 안전지대와 같은 반경)
function ManaService.isInTown(position: Vector3): boolean
	local radius = Config.MobAI.SafeZoneRadius
	for _, center in townCenters do
		if ((center - position) * Vector3.new(1, 0, 1)).Magnitude <= radius then
			return true
		end
	end
	return false
end

-- 매 프레임: 항상 달리는 속도(모으는 중엔 천천히), 마을 안에서만 체력·마나가 찬다 (2026-10-09 사용자 요청)
local function step(dt: number)
	local now = os.clock()
	if now - lastTownScan > 3 then
		lastTownScan = now
		refreshTownCenters()
	end
	local movement = Config.Movement
	local regen = Config.TownRegen
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and root and root:IsA("BasePart") and humanoid.Health > 0 then
			local charging = player:GetAttribute("Charging") == true
			local speed = if charging then Config.Charge.WalkSpeed else movement.RunSpeed
			if humanoid.WalkSpeed ~= speed then
				humanoid.WalkSpeed = speed
			end
			local inTown = ManaService.isInTown(root.Position)
			if player:GetAttribute("InTown") ~= inTown then
				player:SetAttribute("InTown", inTown)
			end
			if inTown then
				if now - (lastSpend[player] or 0) >= Config.Mana.RegenDelay and not ManaService.isFull(player) then
					setMana(player, getMana(player) + regen.ManaPerSecond * dt)
				end
				if humanoid.Health < humanoid.MaxHealth then
					humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + regen.HpPerSecond * dt)
				end
			end
		end
	end
end

-- 서버 시작 시 한 번 호출
function ManaService.init()
	local function onPlayerAdded(player: Player)
		player:SetAttribute("MaxMana", Config.Mana.Max)
		player:SetAttribute("Mana", Config.Mana.Max)
		-- 다시 태어나면 마나를 채운다. Roblox 기본 체력 회복 스크립트(Health)는 지운다 (마을에서만 차게)
		player.CharacterAdded:Connect(function(character)
			player:SetAttribute("Mana", Config.Mana.Max)
			local healthScript = character:WaitForChild("Health", 5)
			if healthScript and healthScript:IsA("Script") then
				healthScript:Destroy()
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastSpend[player] = nil
	end)
	RunService.Heartbeat:Connect(step)
end

return ManaService
