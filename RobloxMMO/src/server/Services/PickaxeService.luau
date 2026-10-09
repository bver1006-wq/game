--!strict
-- 손에 드는 도구(곡괭이·도끼·무기) 지급·조회.
-- 도구는 가방 아이템(도구 칸)이면서 실제 Tool로도 Backpack·StarterGear에 들어간다.
-- 산 도구는 기존 도구에 더해지고, 하단 빠른 호출 칸에서 골라 든다. 같은 도구를 여러 개 가질 수 있다 (조합 재료, 실제 Tool은 종류마다 하나).
-- 가진 도구 중 가장 높은 티어를 종류별로 플레이어 속성에 기록한다 (층 입장·상점 표시용)
--   곡괭이: "PickaxeTier", 도끼: "AxeTier", 칼: "SwordTier", 활: "BowTier", 방망이: "ClubTier"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local EquipmentDefs = require(ReplicatedStorage.Shared.EquipmentDefs)
local PickaxeDefs = require(ReplicatedStorage.Shared.PickaxeDefs)

local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)

-- 테스트 지급(Config.Debug.GiveAllPickaxes)용 모든 도구: 종류 → 단계 순 (단계가 늘어도 PickaxeDefs만 고치면 된다)
local KIND_ORDER: { [string]: number } = { Pickaxe = 1, Axe = 2, Sword = 3, Bow = 4, Club = 5 }
local ALL_TOOLS: { string } = {}
for id in PickaxeDefs do
	table.insert(ALL_TOOLS, id)
end
table.sort(ALL_TOOLS, function(a: string, b: string): boolean
	local da, db = PickaxeDefs[a], PickaxeDefs[b]
	local ka, kb = KIND_ORDER[da.Kind] or 9, KIND_ORDER[db.Kind] or 9
	if ka ~= kb then
		return ka < kb
	end
	return da.Tier < db.Tier
end)

-- 종류별 티어 속성 이름
local TIER_ATTRIBUTE: { [string]: string } = {
	Pickaxe = "PickaxeTier",
	Axe = "AxeTier",
	Sword = "SwordTier",
	Bow = "BowTier",
	Club = "ClubTier",
}

-- 종류 이름 (알림 문구용)
local KIND_NAMES: { [string]: string } = { Pickaxe = "곡괭이", Axe = "도끼", Sword = "칼", Bow = "활", Club = "방망이" }

local PickaxeService = {}

-- 템플릿에서 도구 Tool을 하나 만든다
local function makeTool(def: PickaxeDefs.PickaxeDef): Tool?
	local template = ServerStorage.Templates.Pickaxes:FindFirstChild(def.ToolName)
	if not template or not template:IsA("Tool") then
		warn(`[PickaxeService] 도구 템플릿 없음: Templates/Pickaxes/{def.ToolName}`)
		return nil
	end
	local tool = template:Clone()
	tool:SetAttribute("PickaxeId", def.Id)
	tool.CanBeDropped = false
	return tool
end

-- 가진 도구 중 가장 높은 티어를 종류별로 속성에 기록한다
local function updateTier(player: Player)
	local best: { [string]: number } = {}
	for kind in TIER_ATTRIBUTE do
		best[kind] = 0
	end
	for id, def in PickaxeDefs do
		if InventoryService.count(player, id) > 0 then
			best[def.Kind] = math.max(best[def.Kind], def.Tier)
		end
	end
	for kind, attribute in TIER_ATTRIBUTE do
		player:SetAttribute(attribute, best[kind])
	end
end

-- 가방에 있는 도구의 실제 Tool을 StarterGear(리스폰용)와 지금 가방(Backpack)에 넣는다
local function placeTool(player: Player, def: PickaxeDefs.PickaxeDef)
	local starterGear = player:WaitForChild("StarterGear")
	local gearTool = makeTool(def)
	if gearTool then
		gearTool.Parent = starterGear
	end
	-- 이미 캐릭터가 나와 있으면 이번 생에는 StarterGear가 복사되지 않으므로 가방에도 직접 넣는다
	if player.Character then
		local backpack = player:FindFirstChildOfClass("Backpack")
		local bagTool = makeTool(def)
		if backpack and bagTool then
			bagTool.Parent = backpack
		end
	end
end

-- 실제 Tool(가방·StarterGear·손)을 모두 없앤다. 가방 아이템 개수는 건드리지 않는다
local function destroyTools(player: Player, pickaxeId: string)
	local containers: { Instance? } = { player:FindFirstChildOfClass("Backpack"), player:FindFirstChild("StarterGear"), player.Character }
	for _, container in containers do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute("PickaxeId") == pickaxeId then
					child:Destroy()
				end
			end
		end
	end
end

-- 도구를 1개 지급한다 (가방 칸이 있어야 한다). 성공하면 true
-- 같은 도구를 여러 개 가질 수 있다 (조합식 재료, 2026-10-09). 개수는 가방 아이템으로만 세고,
-- 실제 Tool은 도구 종류마다 하나만 둔다 (같은 도구는 똑같으니 하나를 들면 된다)
-- StarterGear에 넣어 두면 리스폰 때 자동으로 다시 들어온다
function PickaxeService.give(player: Player, pickaxeId: string): boolean
	local def = PickaxeDefs[pickaxeId]
	if not def then
		return false
	end
	local hadOne = InventoryService.count(player, pickaxeId) > 0
	if InventoryService.add(player, pickaxeId, 1) < 1 then
		return false
	end
	if not hadOne then
		placeTool(player, def)
	end
	updateTier(player)
	return true
end

-- 아직 없을 때만 1개 지급한다 (시작 도구·테스트 지급용). 줬으면 true
function PickaxeService.giveIfMissing(player: Player, pickaxeId: string): boolean
	if InventoryService.count(player, pickaxeId) > 0 then
		return false
	end
	return PickaxeService.give(player, pickaxeId)
end

-- 도구를 amount개 없앤다. 다 없어지면 실제 Tool도 없앤다 (손에 들고 있어도). 모자라면 아무것도 안 하고 false
function PickaxeService.removeCount(player: Player, pickaxeId: string, amount: number): boolean
	if not PickaxeDefs[pickaxeId] or amount <= 0 or not InventoryService.remove(player, pickaxeId, amount) then
		return false
	end
	if InventoryService.count(player, pickaxeId) <= 0 then
		destroyTools(player, pickaxeId)
	end
	updateTier(player)
	return true
end

-- 도구를 모두 없앤다 (가방 아이템 + 실제 Tool 모두). 없앴으면 true
function PickaxeService.remove(player: Player, pickaxeId: string): boolean
	return PickaxeService.removeCount(player, pickaxeId, InventoryService.count(player, pickaxeId))
end

-- 가방(Backpack)에 있는 이 도구를 손에 들린다 (만든 새 도구를 바로 들 때). 들었으면 true
function PickaxeService.hold(player: Player, pickaxeId: string): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not humanoid or not backpack then
		return false
	end
	for _, child in backpack:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("PickaxeId") == pickaxeId then
			humanoid:EquipTool(child)
			return true
		end
	end
	return false
end

-- 그 종류 도구 중 가장 높은 티어 (없으면 0). 종류를 안 주면 곡괭이
function PickaxeService.getTier(player: Player, kind: PickaxeDefs.ToolKind?): number
	local tier = player:GetAttribute(TIER_ATTRIBUTE[kind or "Pickaxe"])
	return if typeof(tier) == "number" then tier else 0
end

-- 그 종류·티어 도구 이름 ("구리 곡괭이", "철 도끼")
function PickaxeService.nameFor(kind: PickaxeDefs.ToolKind, tier: number): string
	for _, def in PickaxeDefs do
		if def.Kind == kind and def.Tier == tier then
			return def.DisplayName
		end
	end
	return `T{tier} {KIND_NAMES[kind] or "도구"}`
end

-- 종류 이름 ("곡괭이", "칼" ...)
function PickaxeService.kindName(kind: PickaxeDefs.ToolKind): string
	return KIND_NAMES[kind] or "도구"
end

-- 손에 들고 있는 도구 정의. 안 들고 있으면 nil
function PickaxeService.getEquipped(player: Player): PickaxeDefs.PickaxeDef?
	local character = player.Character
	local tool = character and character:FindFirstChildWhichIsA("Tool")
	if not tool then
		return nil
	end
	local id = tool:GetAttribute("PickaxeId")
	if typeof(id) ~= "string" then
		return nil
	end
	-- 가방에 없는 도구(복제 등)는 인정하지 않는다
	if InventoryService.count(player, id) <= 0 then
		return nil
	end
	return PickaxeDefs[id]
end

-- 도구 데미지 배수
function PickaxeService.getPower(def: PickaxeDefs.PickaxeDef): number
	local config = Config.Pickaxes[def.Id]
	return if config then config.Power else 1
end

-- 서버 시작 시 한 번 호출. 들어오는 플레이어에게 시작 곡괭이·도끼를 준다
function PickaxeService.init()
	local function onPlayerAdded(player: Player)
		-- 저장된 가방을 먼저 불러온다. 저장된 도구는 실제 Tool로 다시 만든다
		if not InventoryService.waitLoaded(player) then
			return
		end
		for id, def in PickaxeDefs do
			if InventoryService.count(player, id) > 0 then
				placeTool(player, def)
			end
		end
		-- 시작 도구: 그 종류 도구가 하나도 없을 때만 준다 (조합에 써서 더 좋은 도구가 있으면 안 준다)
		updateTier(player)
		for _, id in Config.StarterTools do
			if PickaxeService.getTier(player, PickaxeDefs[id].Kind) == 0 then
				PickaxeService.giveIfMissing(player, id)
			end
		end
		if RunService:IsStudio() and Config.Debug.GiveAllPickaxes then
			for _, id in ALL_TOOLS do
				PickaxeService.giveIfMissing(player, id)
			end
		end
		-- 아래 테스트 지급(Studio에서만)은 처음 들어왔을 때만 (저장된 게 계속 불어나지 않게)
		local firstTime = DataService.isNew(player)
		-- 테스트용 장비 전부 (Studio에서만)
		if firstTime and RunService:IsStudio() and Config.Debug.GiveAllEquipment then
			for _, equipmentId in EquipmentDefs.Order do
				InventoryService.add(player, equipmentId, 1)
			end
		end
		-- 테스트용 화살통 (Studio에서만)
		if firstTime and RunService:IsStudio() and Config.Debug.GiveQuivers > 0 then
			for _, quiverId in EquipmentDefs.QuiverOrder do
				InventoryService.add(player, quiverId, Config.Debug.GiveQuivers)
			end
		end
		-- 테스트용 음식 (Studio에서만)
		if firstTime and RunService:IsStudio() and Config.Debug.GiveFoods > 0 then
			for foodId in Config.Foods do
				InventoryService.add(player, foodId, Config.Debug.GiveFoods)
			end
		end
		updateTier(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- 테스트용 지급 통로 (Studio에서만): ServerStorage.DebugGive:Fire(플레이어 이름, 아이템 Id, 개수)
	-- 개수가 음수면 그만큼 뺀다. 아이템 Id가 "Gold"면 골드를 더하거나 뺀다
	-- Studio 명령 줄에서 실행 중인 게임의 가방에 아이템을 넣을 때 쓴다
	if RunService:IsStudio() then
		local debugGive = Instance.new("BindableEvent")
		debugGive.Name = "DebugGive"
		debugGive.Parent = ServerStorage
		debugGive.Event:Connect(function(playerName: string, itemId: string, amount: number?)
			local player = Players:FindFirstChild(playerName)
			if not player or not player:IsA("Player") then
				return
			end
			if itemId == "Gold" then
				local value = math.floor(amount or 0)
				if value >= 0 then
					InventoryService.addGold(player, value)
				else
					InventoryService.spendGold(player, math.min(-value, InventoryService.getGold(player)))
				end
				print(`[PickaxeService] 테스트 골드 {value} → {player.Name} (지금 {InventoryService.getGold(player)}G)`)
			elseif amount and amount < 0 then
				local ok = if PickaxeDefs[itemId]
					then PickaxeService.removeCount(player, itemId, math.min(-amount, InventoryService.count(player, itemId)))
					else InventoryService.remove(player, itemId, math.min(-amount, InventoryService.count(player, itemId)))
				print(`[PickaxeService] 테스트 회수 {itemId} ← {player.Name}: {if ok then "성공" else "실패"}`)
			elseif PickaxeDefs[itemId] then
				local given = 0
				for _ = 1, math.max(math.floor(amount or 1), 1) do
					if PickaxeService.give(player, itemId) then
						given += 1
					end
				end
				print(`[PickaxeService] 테스트 지급 {itemId} x{given} → {player.Name}`)
			else
				local added = InventoryService.add(player, itemId, amount or 1)
				print(`[PickaxeService] 테스트 지급 {itemId} x{added} → {player.Name}`)
			end
		end)
	end
end

return PickaxeService
