--!strict
-- 배경음악 (2026-10-09 사용자 요청)
--   낮: 느릿하고 여유 있는 곡(Config.Music.Calm)을 차례로 + 새소리(Config.Music.Ambience, 있으면)
--   밤: 더 느리고 조용한 곡(Config.Music.Night), 마을 밖이면 풀벌레 소리(NightAmbience, 있으면). 부엉이는 DayNightController
--   전투: 몹을 때리거나 몹에게 맞으면 긴박한 곡(Config.Music.Battle)으로 바꾸고, 마지막 전투 뒤 BattleHoldTime초 동안 유지
--   광산: 광산 배경음이 따로 있어서 음악은 MineVolume까지 줄인다
-- 두 곡은 각자 소리 하나씩 갖고, 볼륨을 천천히 바꿔 서로 넘긴다(크로스페이드). 재생이 안 되는 곡은 건너뛴다

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MineAtmosphereController = require(script.Parent.MineAtmosphereController)

local localPlayer = Players.LocalPlayer

type Channel = { Sound: Sound, Tracks: { string }, Index: number, Volume: number }

local MusicController = {}

local calm: Channel
local battle: Channel
local night: Channel
local dayAmbience: Sound? = nil
local nightAmbience: Sound? = nil
local lastAmbienceKey = ""
local lastCombat = -math.huge
local musicGroup: SoundGroup -- 모든 배경음이 들어가는 묶음. 끄기·크기 조절은 이 볼륨으로
local muted = false
local level = 0 -- 크기 단계 (Config.Music.VolumeLevels의 번호)
local mode = "" -- "Calm" | "Battle" | "Mine"

-- 소리 하나를 만든다
local function makeSound(name: string, looped: boolean): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.Looped = looped
	sound.Volume = 0
	sound.SoundGroup = musicGroup
	sound.Parent = SoundService
	return sound
end

-- 볼륨을 천천히 바꾼다
local function fadeTo(sound: Sound, volume: number)
	TweenService:Create(sound, TweenInfo.new(Config.Music.FadeTime), { Volume = volume }):Play()
end

-- 채널의 다음 곡을 튼다 (불러오지 못하면 다음 곡으로)
local function playNext(channel: Channel)
	local tracks = channel.Tracks
	for _ = 1, #tracks do
		channel.Index = channel.Index % #tracks + 1
		channel.Sound.SoundId = tracks[channel.Index]
		local started = os.clock()
		while not channel.Sound.IsLoaded and os.clock() - started < 8 do
			task.wait(0.2)
		end
		if channel.Sound.IsLoaded then
			channel.Sound.TimePosition = 0
			channel.Sound:Play()
			return
		end
		warn(`[MusicController] 음악을 불러오지 못했어요: {tracks[channel.Index]}`)
	end
end

local function makeChannel(name: string, tracks: { string }, volume: number): Channel
	local channel: Channel = { Sound = makeSound(name, false), Tracks = tracks, Index = 0, Volume = volume }
	channel.Sound.Ended:Connect(function()
		task.wait(Config.Music.GapBetweenTracks)
		playNext(channel)
	end)
	return channel
end

-- 지금 상황에 맞는 곡으로 넘긴다 ("Calm" 낮 / "Night" 밤 / "Battle" 전투 / "Mine" 광산)
local function setMode(newMode: string)
	if newMode == mode then
		return
	end
	local previous = mode
	mode = newMode
	local music = Config.Music
	-- 모드마다 소리 낼 채널과 볼륨
	local wanted: { [Channel]: number } = {
		[calm] = if newMode == "Calm" then calm.Volume elseif newMode == "Mine" then music.MineVolume else 0,
		[night] = if newMode == "Night" then night.Volume else 0,
		[battle] = if newMode == "Battle" then battle.Volume else 0,
	}
	for channel, volume in wanted do
		if volume > 0 and not channel.Sound.IsPlaying then
			-- 전투곡·밤 곡은 들어갈 때 처음부터
			task.spawn(playNext, channel)
		end
		fadeTo(channel.Sound, volume)
	end
	-- 다 줄어든 전투곡·밤 곡은 멈춘다 (다음에 처음부터). 낮 곡은 이어서 틀도록 둔다
	for _, channel in { battle, night } do
		if wanted[channel] == 0 and previous ~= "" then
			task.delay(music.FadeTime, function()
				if channel.Sound.Volume <= 0.001 then
					channel.Sound:Stop()
				end
			end)
		end
	end
end

-- 자연 소리: 낮엔 새소리(Ambience), 밤에 마을 밖이면 풀벌레(NightAmbience). 전투·광산에서는 끈다
local function updateAmbience()
	local music = Config.Music
	local outside = localPlayer:GetAttribute("InTown") ~= true
	if dayAmbience then
		fadeTo(dayAmbience, if mode == "Calm" then music.AmbienceVolume else 0)
	end
	if nightAmbience then
		fadeTo(nightAmbience, if mode == "Night" and outside then music.NightAmbienceVolume else 0)
	end
end

-- 전투가 났다 (내가 몹을 때렸거나 몹에게 맞았다)
local function markCombat()
	lastCombat = os.clock()
end

-- 묶음 볼륨을 지금 설정(끄기·크기 단계)에 맞춘다
local function applyMaster()
	musicGroup.Volume = if muted then 0 else Config.Music.VolumeLevels[level]
end

-- 배경음 끄기·켜기 (음표 버튼)
function MusicController.setMuted(value: boolean)
	muted = value
	applyMaster()
end

function MusicController.isMuted(): boolean
	return muted
end

-- 크기 한 단계 키우기(+1)·줄이기(-1). 지금 단계와 전체 단계 수를 돌려준다
function MusicController.changeLevel(delta: number): (number, number)
	local levels = Config.Music.VolumeLevels
	level = math.clamp(level + delta, 1, #levels)
	if delta > 0 then
		muted = false
	end
	applyMaster()
	return level, #levels
end

function MusicController.getLevel(): (number, number)
	return level, #Config.Music.VolumeLevels
end

-- 클라이언트 시작 시 한 번 호출
function MusicController.init()
	local music = Config.Music
	local group = Instance.new("SoundGroup")
	group.Name = "MusicGroup"
	group.Parent = SoundService
	musicGroup = group
	level = music.DefaultLevel
	applyMaster()
	calm = makeChannel("CalmMusic", music.Calm, music.Volume)
	night = makeChannel("NightMusic", music.Night.Tracks, music.Night.Volume)
	night.Sound.PlaybackSpeed = music.Night.PlaybackSpeed -- 더 느리고 낮게
	battle = makeChannel("BattleMusic", music.Battle, music.BattleVolume)
	local function loopSound(name: string, id: string): Sound?
		if id == "" then
			return nil
		end
		local sound = makeSound(name, true)
		sound.SoundId = id
		sound:Play()
		return sound
	end
	dayAmbience = loopSound("DayAmbience", music.Ambience)
	nightAmbience = loopSound("NightAmbience", music.NightAmbience)

	-- 전투 감지: 내가 때린 공격, 나를 때린 몹
	Remotes.get(Remotes.Names.CombatEffect).OnClientEvent:Connect(function(_mob, _damage, _isCrit, _kind, _tier, attackerUserId)
		if attackerUserId == localPlayer.UserId then
			markCombat()
		end
	end)
	Remotes.get(Remotes.Names.MobAttack).OnClientEvent:Connect(function(_mob, targetUserId)
		if targetUserId == localPlayer.UserId then
			markCombat()
		end
	end)

	task.spawn(function()
		while true do
			local inBattle = os.clock() - lastCombat < music.BattleHoldTime
			local inMine = MineAtmosphereController.getFloor() ~= nil
			local clock = Lighting.ClockTime
			local isNight = clock < Config.DayNight.DayStart or clock >= Config.DayNight.NightStart
			setMode(if inBattle and #battle.Tracks > 0 then "Battle" elseif inMine then "Mine" elseif isNight then "Night" else "Calm")
			local key = `{mode}{localPlayer:GetAttribute("InTown")}`
			if key ~= lastAmbienceKey then
				lastAmbienceKey = key
				updateAmbience()
			end
			task.wait(0.5)
		end
	end)
end

return MusicController
