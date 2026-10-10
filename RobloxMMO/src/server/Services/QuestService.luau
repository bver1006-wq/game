--!strict
-- 시작 퀘스트 (2026-10-10 사용자 요청): 처음 하는 사람을 차례로 안내한다.
-- 슬라임 잡기 → 곡괭이 → 돌 캐기 → 도끼 → 소나무 베기 → 구리 검 → 스켈레톤 → 뼈 갑옷 → 뼈 신발 (단계 목록 Config.Quest.Steps)
-- 서버가 진행을 센다: MobService(처치)·MiningService(캐기·베기)·CraftingService(만들기)가 QuestService.report를 부른다.
-- 진행 상황은 플레이어 속성 QuestStep(지금 단계 번호, 다 끝나면 단계 수 + 1)·QuestProgress(센 수)로 클라 QuestHUD에 보이고,
-- 단계를 마치면 보상을 주고 QuestComplete 리모트로 축하 창을 띄운다. 저장은 DataService 칸 "Quest" = { Step, Progress }

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local ItemDefs = require(ReplicatedStorage.Shared.ItemDefs)
local PickaxeDefs = require(ReplicatedStorage.Shared.PickaxeDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local NotifyService = require(script.Parent.NotifyService)
local PickaxeService = require(script.Parent.PickaxeService)

type Progress = { Step: number, Progress: number }

local QuestService = {}

local progressByPlayer: { [Player]: Progress } = {}
local completeRemote: RemoteEvent

-- 단계 수
local function stepCount(): number
	return #Config.Quest.Steps
end

-- 속성으로 클라에 알린다
local function publish(player: Player, state: Progress)
	player:SetAttribute("QuestStep", state.Step)
	player:SetAttribute("QuestProgress", state.Progress)
end

-- 목록에 이 값이 있는지
local function hasTarget(targets: { string }, value: string): boolean
	return table.find(targets, value) ~= nil
end

-- 만들기 단계: 이미 가지고 있는지 (도구·무기는 같은 종류 더 높은 단계도 인정, 장비는 가방에 있으면)
local function alreadyOwns(player: Player, itemId: string): boolean
	local tool = PickaxeDefs[itemId]
	if tool then
		return PickaxeService.getTier(player, tool.Kind) >= tool.Tier
	end
	return InventoryService.count(player, itemId) > 0
end

-- 보상을 주고 알림 문구를 돌려준다 ("+10G, 빵 3")
local function giveReward(player: Player, reward: { Gold: number, Items: { [string]: number }? }): string
	local parts = {}
	if reward.Gold > 0 then
		InventoryService.addGold(player, reward.Gold)
		table.insert(parts, `+{reward.Gold}G`)
	end
	if reward.Items then
		for itemId, amount in reward.Items do
			local def = ItemDefs.Items[itemId]
			if def then
				local got = InventoryService.add(player, itemId, amount)
				if got > 0 then
					table.insert(parts, `{def.DisplayName} {got}`)
				end
				if got < amount then
					NotifyService.send(player, "가방이 가득 차서 보상 일부를 못 받았어요.", "bad")
				end
			end
		end
	end
	return table.concat(parts, ", ")
end

-- 지금 단계를 끝내고 다음 단계로. 다음이 만들기 단계인데 이미 가지고 있으면 그것도 바로 끝낸다
local function advance(player: Player, state: Progress)
	while state.Step <= stepCount() do
		local step = Config.Quest.Steps[state.Step]
		local done = state.Progress >= step.Count
		if not done and step.Kind == "Craft" then
			for _, target in step.Targets do
				if alreadyOwns(player, target) then
					done = true
					break
				end
			end
		end
		if not done then
			break
		end
		local rewardText = giveReward(player, step.Reward)
		local finishedIndex = state.Step
		state.Step += 1
		state.Progress = 0
		completeRemote:FireClient(player, finishedIndex, rewardText)
		print(`[QuestService] {player.Name} 퀘스트 {finishedIndex}단계 완료: {step.Title} ({rewardText})`)
	end
	publish(player, state)
end

-- 진행 보고: kind "Kill"(몹 종류) / "Gather"(광석·통나무 Id) / "Craft"(만든 아이템 Id), amount만큼 센다
function QuestService.report(player: Player, kind: string, target: string, amount: number)
	local state = progressByPlayer[player]
	if not state or state.Step > stepCount() or amount <= 0 then
		return
	end
	local step = Config.Quest.Steps[state.Step]
	if step.Kind ~= kind or not hasTarget(step.Targets, target) then
		return
	end
	state.Progress = math.min(state.Progress + math.floor(amount), step.Count)
	advance(player, state)
end

-- 서버 시작 시 한 번 호출 (InventoryService·PickaxeService 다음)
function QuestService.init()
	completeRemote = Remotes.get(Remotes.Names.QuestComplete)

	DataService.register("Quest", function(player: Player)
		local state = progressByPlayer[player]
		return if state then { Step = state.Step, Progress = state.Progress } else nil
	end)

	local function onPlayerAdded(player: Player)
		if not InventoryService.waitLoaded(player) then
			return
		end
		local saved = DataService.load(player).Quest
		local state: Progress = { Step = 1, Progress = 0 }
		if typeof(saved) == "table" and typeof(saved.Step) == "number" then
			state.Step = math.clamp(math.floor(saved.Step), 1, stepCount() + 1)
			state.Progress = if typeof(saved.Progress) == "number" then math.max(0, math.floor(saved.Progress)) else 0
		end
		progressByPlayer[player] = state
		-- 시작 도구가 생길 때까지 잠깐 기다린 뒤 "이미 가진 것" 확인 (PickaxeService도 waitLoaded 뒤에 준다)
		task.defer(function()
			if player.Parent and progressByPlayer[player] == state then
				advance(player, state)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		-- 저장(DataService)이 먼저 모아 가도록 조금 뒤에 지운다
		task.delay(Config.Save.CleanupDelay, function()
			progressByPlayer[player] = nil
		end)
	end)
end

return QuestService
