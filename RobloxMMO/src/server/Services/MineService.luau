--!strict
-- 광산 층 이동. Studio에서 배치한 이동 입구(태그 "MinePortal", 속성 TargetFloor)를 지나가면
-- 곡괭이 티어를 확인한 뒤 그 층의 도착 지점(태그 "MineArrival", 속성 Floor)으로 옮긴다.
--   속성 WalkIn = true: 까만 갱도 안으로 걸어 들어가면(닿으면) 이동
--   그 외: ProximityPrompt를 눌러서 이동
-- 조건이 안 맞으면 알림을 띄우고 갱도 밖으로 살짝 밀어낸다.
-- 층 정보(이름, 필요 티어, 잠김)는 Config.Mine.Floors에 있다.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PickaxeDefs = require(ReplicatedStorage.Shared.PickaxeDefs)

local NotifyService = require(script.Parent.NotifyService)
local PickaxeService = require(script.Parent.PickaxeService)

local PORTAL_TAG = "MinePortal"
local ARRIVAL_TAG = "MineArrival"
local TRAVEL_COOLDOWN = 1.5 -- 연속 이동·연속 알림 방지(초)
local PUSH_BACK_DISTANCE = 5 -- 못 들어갈 때 밀어내는 거리(스터드)

local MineService = {}

local lastTravel: { [Player]: number } = {}

-- 티어 번호에 맞는 곡괭이 이름 ("구리 곡괭이")
local function pickaxeNameForTier(tier: number): string
	for _, def in PickaxeDefs do
		if def.Kind == "Pickaxe" and def.Tier == tier then
			return def.DisplayName
		end
	end
	return `T{tier} 곡괭이`
end

-- 그 층의 도착 지점
local function findArrival(floor: number): BasePart?
	for _, part in CollectionService:GetTagged(ARRIVAL_TAG) do
		if part:IsA("BasePart") and part:GetAttribute("Floor") == floor then
			return part
		end
	end
	return nil
end

-- 갱도 밖으로 밀어낸다 (입구 중심에서 캐릭터 쪽으로)
local function pushBack(character: Model, portal: BasePart)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local away = (root.Position - portal.Position) * Vector3.new(1, 0, 1)
	-- 입구 앞쪽 방향(속성 Facing)이 있으면 그쪽으로 민다
	local facing = portal:GetAttribute("Facing")
	if typeof(facing) == "Vector3" then
		away = facing
	end
	away = if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis
	character:PivotTo(character:GetPivot() + away * PUSH_BACK_DISTANCE)
end

-- 입구를 지났을 때: 잠김·티어 확인 후 이동
local function travel(player: Player, floor: number, portal: BasePart)
	local now = os.clock()
	if lastTravel[player] and now - lastTravel[player] < TRAVEL_COOLDOWN then
		return
	end
	lastTravel[player] = now -- 실패해도 기록해서 알림이 연달아 뜨지 않게
	local info = Config.Mine.Floors[floor]
	local character = player.Character
	if not info or not character then
		return
	end
	if info.Locked then
		NotifyService.send(player, `{info.Name}은 공사 중이에요.`, "info")
		pushBack(character, portal)
		return
	end
	if PickaxeService.getTier(player) < info.RequiredTier then
		NotifyService.send(player, `{info.Name}에 들어가려면 {pickaxeNameForTier(info.RequiredTier)}가 필요해요.`, "bad")
		pushBack(character, portal)
		return
	end
	local arrival = findArrival(floor)
	if not arrival then
		warn(`[MineService] {floor}층 도착 지점 없음`)
		return
	end
	local target = arrival.CFrame + Vector3.new(0, 3, 0)
	-- 스트리밍이 켜져 있어서 먼 층은 클라이언트에 아직 없을 수 있다. 도착 지점 주변을 먼저 받게 한다
	pcall(function()
		player:RequestStreamAroundAsync(target.Position)
	end)
	if not character.Parent then
		return
	end
	character:PivotTo(target)
	NotifyService.send(player, info.Name, "info")
end

-- 이동 입구 하나를 준비한다
local function setupPortal(portal: Instance)
	if not portal:IsA("BasePart") then
		return
	end
	local floor = portal:GetAttribute("TargetFloor")
	local info = if typeof(floor) == "number" then Config.Mine.Floors[floor] else nil
	if not info then
		warn(`[MineService] TargetFloor가 잘못된 입구: {portal:GetFullName()}`)
		return
	end

	if portal:GetAttribute("WalkIn") then
		-- 걸어 들어가면 이동
		portal.CanTouch = true
		portal.Touched:Connect(function(hit)
			local model = hit:FindFirstAncestorOfClass("Model")
			local player = model and Players:GetPlayerFromCharacter(model)
			if player then
				travel(player, floor :: number, portal)
			end
		end)
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = info.Name
	prompt.ActionText = if info.Locked
		then "공사 중"
		elseif info.RequiredTier > 1 then `이동 ({pickaxeNameForTier(info.RequiredTier)} 필요)`
		else "이동"
	prompt.MaxActivationDistance = Config.Mine.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = portal
	prompt.Triggered:Connect(function(player)
		travel(player, floor :: number, portal)
	end)
end

-- 서버 시작 시 한 번 호출
function MineService.init()
	for _, portal in CollectionService:GetTagged(PORTAL_TAG) do
		setupPortal(portal)
	end
	CollectionService:GetInstanceAddedSignal(PORTAL_TAG):Connect(setupPortal)
	Players.PlayerRemoving:Connect(function(player)
		lastTravel[player] = nil
	end)
end

return MineService
