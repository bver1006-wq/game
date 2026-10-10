--!strict
-- 타이밍 판정.
-- 플레이어가 바위를 칠 때마다 그 시각부터 잔상이 줄어든다. 줄어드는 시간은 타격마다 서버가 랜덤으로 정한다.
-- 다음 타격이 "직전 타격 시각 + 그 잔상 시간"에 얼마나 가까운지로 Perfect/Nice/Normal을 정한다.
-- 나무는 잔상 대신 화면 아래 타이밍 막대(2026-10-10): 커서가 좌우로 왕복하고, 휘두른 시각의 커서 위치가
-- 서버가 정한 목표 줄(0~1)에 얼마나 가까운지로 판정한다. 왕복 시간·목표는 타격마다 다시 정한다.
-- 시각은 모두 workspace:GetServerTimeNow() 기준이다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

export type Judgment = "Perfect" | "Nice" | "Normal"

-- 직전 타격 기록
type HitRecord = {
	Time: number, -- 인정된 타격 시각
	GhostDuration: number, -- 이 타격으로 시작된 잔상이 바위 크기가 되기까지 걸리는 시간
}

-- 나무 타이밍 막대 상태: 커서는 StartTime에 왼쪽 끝(0)에서 출발해 Period초마다 반대쪽 끝에 닿는다
export type TreeTiming = {
	StartTime: number,
	Period: number, -- 한쪽 끝에서 반대쪽 끝까지 가는 시간(초)
	Target: number, -- 목표 줄 위치 (0~1)
}

local TimingService = {}

-- 플레이어 → 바위 → 그 바위에 마지막으로 인정된 타격
local lastHits: { [Player]: { [Model]: HitRecord } } = {}
-- 플레이어 → 나무 → 지금 타이밍 막대
local treeTimings: { [Player]: { [Model]: TreeTiming } } = {}
local random = Random.new()

-- 서버 시작 시 한 번 호출
function TimingService.init()
	Players.PlayerRemoving:Connect(function(player)
		lastHits[player] = nil
		treeTimings[player] = nil
	end)
end

-- 시각 t의 커서 위치(0~1)와 움직이는 방향(1 오른쪽, -1 왼쪽). 왕복(핑퐁) 움직임
function TimingService.cursorAt(timing: TreeTiming, t: number): (number, number)
	local phase = ((t - timing.StartTime) / timing.Period) % 2
	if phase <= 1 then
		return phase, 1
	end
	return 2 - phase, -1
end

-- 새 목표 위치를 고른다 (직전 목표에서 MinTargetShift 이상 떨어지게, 몇 번 시도)
local function pickTarget(previous: number?): number
	local config = Config.TreeTiming
	local target = random:NextNumber(config.TargetMin, config.TargetMax)
	if previous then
		for _ = 1, 6 do
			if math.abs(target - previous) >= config.MinTargetShift then
				break
			end
			target = random:NextNumber(config.TargetMin, config.TargetMax)
		end
	end
	return target
end

-- 이 플레이어·나무의 타이밍 막대를 돌려준다. 없으면 now에 왼쪽 끝에서 출발하는 새 막대를 만든다
function TimingService.getTreeTiming(player: Player, tree: Model, now: number): TreeTiming
	local perTree = treeTimings[player]
	if not perTree then
		perTree = {}
		treeTimings[player] = perTree
	end
	local timing = perTree[tree]
	if not timing then
		local config = Config.TreeTiming
		timing = {
			StartTime = now,
			Period = random:NextNumber(config.PeriodMin, config.PeriodMax),
			Target = pickTarget(nil),
		}
		perTree[tree] = timing
	end
	return timing :: TreeTiming
end

-- 나무 타격 판정: 휘두른 시각의 커서 위치와 목표 줄의 거리. 막대가 없었으면(요청 전) 일반
function TimingService.judgeTree(player: Player, tree: Model, swingTime: number, isTouch: boolean): Judgment
	local perTree = treeTimings[player]
	local timing = perTree and perTree[tree]
	if not timing then
		return "Normal"
	end
	local windows = if isTouch then Config.TreeTiming.Windows.Mobile else Config.TreeTiming.Windows.PC
	local position = TimingService.cursorAt(timing, swingTime)
	local err = math.abs(position - timing.Target)
	if err <= windows.Perfect then
		return "Perfect"
	elseif err <= windows.Nice then
		return "Nice"
	end
	return "Normal"
end

-- 나무 타격 뒤: 목표 줄과 왕복 시간을 새로 정한다. 커서는 휘두른 순간의 자리·방향에서 끊기지 않고 이어 간다
function TimingService.rerollTree(player: Player, tree: Model, swingTime: number): TreeTiming
	local config = Config.TreeTiming
	local old = TimingService.getTreeTiming(player, tree, swingTime)
	local position, direction = TimingService.cursorAt(old, swingTime)
	local period = random:NextNumber(config.PeriodMin, config.PeriodMax)
	local phase = if direction > 0 then position else 2 - position
	local timing: TreeTiming = {
		StartTime = swingTime - phase * period,
		Period = period,
		Target = pickTarget(old.Target),
	}
	treeTimings[player][tree] = timing
	return timing
end

-- 클라이언트가 보낸 휘두른 시각을 검증해서 판정에 쓸 시각을 돌려준다.
-- 서버 수신 시각과 지연 허용치 이상 차이 나면(또는 미래 시각이면) 수신 시각을 쓴다
function TimingService.resolveSwingTime(clientTime: number): number
	local now = Workspace:GetServerTimeNow()
	local diff = now - clientTime
	if diff >= -0.02 and diff <= Config.Timing.MaxLatencyTolerance then
		return clientTime
	end
	return now
end

-- 이번 타격의 판정을 계산한다
function TimingService.judge(player: Player, rock: Model, swingTime: number, isTouch: boolean): Judgment
	local perRock = lastHits[player]
	local last = perRock and perRock[rock]
	if not last then
		return "Normal" -- 이 바위의 첫 타격은 잔상이 없으니 항상 일반
	end

	local windows = if isTouch then Config.Timing.Windows.Mobile else Config.Timing.Windows.PC
	local err = math.abs(swingTime - (last.Time + last.GhostDuration))
	if err <= windows.Perfect then
		return "Perfect"
	elseif err <= windows.Nice then
		return "Nice"
	end
	return "Normal"
end

-- 인정된 타격을 기록하고, 이 타격으로 시작되는 잔상 시간을 랜덤으로 정해 돌려준다
function TimingService.recordHit(player: Player, rock: Model, swingTime: number): number
	local perRock = lastHits[player]
	if not perRock then
		perRock = {}
		lastHits[player] = perRock
	end
	local duration = random:NextNumber(Config.Timing.GhostDurationMin, Config.Timing.GhostDurationMax)
	perRock[rock] = { Time = swingTime, GhostDuration = duration }
	return duration
end

-- 바위가 제거될 때 그 바위의 기록을 지운다
function TimingService.clearRock(rock: Model)
	for _, perRock in lastHits do
		perRock[rock] = nil
	end
	for _, perTree in treeTimings do
		perTree[rock] = nil
	end
end

return TimingService
