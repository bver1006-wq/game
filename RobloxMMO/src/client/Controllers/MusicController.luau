--!strict
-- 잔잔한 배경음악 (2026-10-09 사용자 요청)
-- 밖(마을·들판)에서는 Config.Music.Tracks를 차례로 틀고, 광산에 들어가면 천천히 줄여 광산 배경음에 자리를 내준다
-- 재생이 안 되는 곡(지워졌거나 권한 없음)은 건너뛴다

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local MineAtmosphereController = require(script.Parent.MineAtmosphereController)

local MusicController = {}

local sound: Sound
local index = 0
local inMine = false

-- 볼륨을 천천히 바꾼다
local function fadeTo(volume: number)
	TweenService:Create(sound, TweenInfo.new(Config.Music.FadeTime), { Volume = volume }):Play()
end

-- 다음 곡을 튼다 (불러오지 못하면 다음 곡으로)
local function playNext()
	local tracks = Config.Music.Tracks
	if #tracks == 0 then
		return
	end
	for _ = 1, #tracks do
		index = index % #tracks + 1
		sound.SoundId = tracks[index]
		local started = os.clock()
		while not sound.IsLoaded and os.clock() - started < 8 do
			task.wait(0.2)
		end
		if sound.IsLoaded then
			sound.TimePosition = 0
			sound:Play()
			return
		end
		warn(`[MusicController] 배경음악을 불러오지 못했어요: {tracks[index]}`)
	end
end

-- 클라이언트 시작 시 한 번 호출
function MusicController.init()
	sound = Instance.new("Sound")
	sound.Name = "BackgroundMusic"
	sound.Looped = false
	sound.Volume = Config.Music.Volume
	sound.Parent = SoundService
	sound.Ended:Connect(function()
		task.wait(Config.Music.GapBetweenTracks)
		playNext()
	end)
	task.spawn(playNext)

	-- 광산 안에서는 줄이고, 나오면 다시 키운다
	task.spawn(function()
		while true do
			task.wait(0.5)
			local nowInMine = MineAtmosphereController.getFloor() ~= nil
			if nowInMine ~= inMine then
				inMine = nowInMine
				fadeTo(if inMine then Config.Music.MineVolume else Config.Music.Volume)
			end
		end
	end)
end

return MusicController
