--!strict
-- 타이밍 판정.
-- 플레이어가 바위를 칠 때마다 그 시각부터 잔상이 줄어든다. 줄어드는 시간은 타격마다 서버가 랜덤으로 정한다.
-- 다음 타격이 "직전 타격 시각 + 그 잔상 시간"에 얼마나 가까운지로 Perfect/Nice/Normal을 정한다.
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

local TimingService = {}

-- 플레이어 → 바위 → 그 바위에 마지막으로 인정된 타격
local lastHits: { [Player]: { [Model]: HitRecord } } = {}
local random = Random.new()

-- 서버 시작 시 한 번 호출
function TimingService.init()
	Players.PlayerRemoving:Connect(function(player)
		lastHits[player] = nil
	end)
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
end

return TimingService
