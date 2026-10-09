--!strict
-- 밤낮·먼 곳 안개 (2026-10-09 사용자 요청)
--   서버가 돌리는 Lighting.ClockTime을 보고 밝기·주변광·안개 색을 낮 ↔ 밤 사이로 천천히 바꾼다 (밤은 더 깜깜)
--   마을(TownArrival)에서 멀어질수록 안개가 짙어져 먼 곳이 잘 안 보인다 ("미지의 세계")
--   밤에는 가끔 부엉이 울음 (Config.DayNight.OwlSound)
--   광산 안에서는 MineAtmosphereController가 조명을 맡으므로 손대지 않는다

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local MineAtmosphereController = require(script.Parent.MineAtmosphereController)

local localPlayer = Players.LocalPlayer

local DayNightController = {}

local atmosphere: Atmosphere
local random = Random.new()
local smoothedFar = 0 -- 마을에서 먼 정도 (0~1, 천천히 따라간다)
local resumeAt = 0 -- 광산에서 나온 뒤 광산 조명 전환이 끝날 때까지 기다린다

-- 낮 정도 (0 = 한밤, 1 = 한낮). 해 뜨고 지는 동안 부드럽게
local function daylight(clock: number): number
	local cfg = Config.DayNight
	local t = cfg.TwilightHours
	if clock >= cfg.DayStart + t and clock <= cfg.NightStart - t then
		return 1
	elseif clock <= cfg.DayStart - t or clock >= cfg.NightStart + t then
		return 0
	elseif clock < 12 then
		return (clock - (cfg.DayStart - t)) / (2 * t)
	else
		return 1 - (clock - (cfg.NightStart - t)) / (2 * t)
	end
end

-- 마을에서 먼 정도 (0~1)
local function farness(): number
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return smoothedFar
	end
	local best = math.huge
	for _, town in CollectionService:GetTagged("TownArrival") do
		if town:IsA("BasePart") then
			best = math.min(best, ((town.Position - root.Position) * Vector3.new(1, 0, 1)).Magnitude)
		end
	end
	if best == math.huge then
		return 0
	end
	local fog = Config.DayNight.Fog
	return math.clamp((best - fog.ClearRadius) / (fog.FullRadius - fog.ClearRadius), 0, 1)
end

-- 지금 시각·거리에 맞는 밖의 조명 값
local function targets(): { [string]: any }
	local cfg = Config.DayNight
	local day = daylight(Lighting.ClockTime)
	local d, n = cfg.Day, cfg.Night
	local fog = cfg.Fog
	local density = n.Density + (d.Density - n.Density) * day + (fog.FarDensity - d.Density) * smoothedFar
	return {
		Ambient = n.Ambient:Lerp(d.Ambient, day),
		OutdoorAmbient = n.OutdoorAmbient:Lerp(d.OutdoorAmbient, day),
		Brightness = n.Brightness + (d.Brightness - n.Brightness) * day,
		ExposureCompensation = n.Exposure + (d.Exposure - n.Exposure) * day,
		Density = math.clamp(density, 0, 1),
		AtmColor = n.AtmColor:Lerp(d.AtmColor, day),
		AtmDecay = n.AtmDecay:Lerp(d.AtmDecay, day),
		Haze = n.Haze + (d.Haze - n.Haze) * day + fog.FarHaze * smoothedFar,
	}
end

-- 조명에 바로 넣는다 (값이 천천히 변하므로 매번 넣어도 부드럽다)
local function apply()
	local t = targets()
	Lighting.Ambient = t.Ambient
	Lighting.OutdoorAmbient = t.OutdoorAmbient
	Lighting.Brightness = t.Brightness
	Lighting.ExposureCompensation = t.ExposureCompensation
	atmosphere.Density = t.Density
	atmosphere.Color = t.AtmColor
	atmosphere.Decay = t.AtmDecay
	atmosphere.Haze = t.Haze
end

-- 밤에 가끔 부엉이 울음 (내 주변 어딘가에서)
local function owlLoop()
	local cfg = Config.DayNight
	while true do
		task.wait(random:NextNumber(cfg.OwlIntervalMin, cfg.OwlIntervalMax))
		local character = localPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local outside = localPlayer:GetAttribute("InTown") ~= true -- 부엉이는 마을 밖에서만
		if cfg.OwlSound ~= "" and outside and root and root:IsA("BasePart") and daylight(Lighting.ClockTime) < 0.3 and MineAtmosphereController.getFloor() == nil then
			local angle = random:NextNumber(0, math.pi * 2)
			local attachment = Instance.new("Attachment")
			attachment.WorldPosition = root.Position + Vector3.new(math.cos(angle) * 25, 8, math.sin(angle) * 25)
			attachment.Parent = Workspace.Terrain
			local sound = Instance.new("Sound")
			sound.SoundId = cfg.OwlSound
			sound.Volume = cfg.OwlVolume
			sound.PlaybackSpeed = random:NextNumber(0.92, 1.05)
			sound.RollOffMaxDistance = 120
			sound.Parent = attachment
			sound:Play()
			sound.Ended:Once(function()
				attachment:Destroy()
			end)
			task.delay(15, function()
				if attachment.Parent then
					attachment:Destroy()
				end
			end)
		end
	end
end

-- 클라이언트 시작 시 한 번 호출 (MineAtmosphereController.init 이후)
function DayNightController.init()
	local existing = Lighting:FindFirstChildOfClass("Atmosphere")
	if existing then
		atmosphere = existing
	else
		local created = Instance.new("Atmosphere")
		created.Offset = 0.1
		created.Parent = Lighting
		atmosphere = created
	end
	-- 광산에서 나올 때 이 값으로 돌아간다
	MineAtmosphereController.outdoorTargets = targets

	local wasInMine = false
	task.spawn(function()
		while true do
			local inMine = MineAtmosphereController.getFloor() ~= nil
			if wasInMine and not inMine then
				resumeAt = os.clock() + Config.MineAtmosphere.TweenTime + 0.1
			end
			wasInMine = inMine
			smoothedFar += (farness() - smoothedFar) * 0.1
			if not inMine and os.clock() >= resumeAt then
				apply()
			end
			task.wait(0.2)
		end
	end)
	task.spawn(owlLoop)
end

return DayNightController
