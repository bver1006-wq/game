--!strict
-- 횃불 켜고 끄기 (2026-10-09): Workspace/Torches(제작 스크립트 studio/BuildTorches)의 불을 밤에만 켠다.
-- 해 지기 Config.Torches.LightBefore시간 전부터 해 뜨고 LightAfter시간 뒤까지 (시각은 Lighting.ClockTime, Config.DayNight).
-- 1초마다 시각만 보고, 켜짐이 바뀌거나 횃불을 새로 지었을 때(폴더 속성 BuildId)만 부품을 돈다.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local TorchService = {}

-- 지금 횃불을 켜야 하는가
local function wantOn(clock: number): boolean
	local day = Config.DayNight
	local cfg = Config.Torches
	return clock >= day.NightStart - cfg.LightBefore or clock < day.DayStart + cfg.LightAfter
end

-- 폴더 안 불빛·불 효과·불꽃 부품을 켜거나 끈다
local function apply(folder: Instance, on: boolean)
	for _, d in folder:GetDescendants() do
		if d:IsA("Light") then
			d.Enabled = on
		elseif d:IsA("Fire") or d:IsA("ParticleEmitter") then
			d.Enabled = on
		elseif d:IsA("BasePart") and d:GetAttribute("TorchFlame") then
			local onTransparency = d:GetAttribute("OnTransparency")
			d.Transparency = if on then (if typeof(onTransparency) == "number" then onTransparency else 0) else 1
		end
	end
	folder:SetAttribute("LightsOn", on)
end

-- 서버 시작 시 한 번 호출
function TorchService.init()
	local lastOn: boolean? = nil
	local lastBuild: any = nil
	task.spawn(function()
		while true do
			local folder = workspace:FindFirstChild("Torches")
			if folder then
				local on = wantOn(Lighting.ClockTime)
				local build = folder:GetAttribute("BuildId")
				if on ~= lastOn or build ~= lastBuild then
					apply(folder, on)
					lastOn, lastBuild = on, build
				end
			end
			task.wait(1)
		end
	end)
end

return TorchService
