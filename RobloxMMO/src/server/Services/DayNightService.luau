--!strict
-- 밤낮 (2026-10-09 사용자 요청): 서버가 Lighting.ClockTime을 돌린다 (모두 같은 시각을 본다)
-- 낮(DayStart~NightStart)은 DaySeconds, 밤은 NightSeconds 동안 흐른다. 밝기·안개·소리는 클라 DayNightController가 시각을 보고 정한다

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local DayNightService = {}

-- 지금 시각이 낮인가
local function isDay(clock: number): boolean
	local cfg = Config.DayNight
	return clock >= cfg.DayStart and clock < cfg.NightStart
end

-- 서버 시작 시 한 번 호출
function DayNightService.init()
	local cfg = Config.DayNight
	Lighting.ClockTime = cfg.StartClock
	local dayHours = cfg.NightStart - cfg.DayStart
	local nightHours = 24 - dayHours
	RunService.Heartbeat:Connect(function(dt)
		local clock = Lighting.ClockTime
		-- 낮과 밤은 흐르는 빠르기가 다르다 (시간/초)
		local speed = if isDay(clock) then dayHours / cfg.DaySeconds else nightHours / cfg.NightSeconds
		Lighting.ClockTime = (clock + speed * dt) % 24
	end)
end

return DayNightService
