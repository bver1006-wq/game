--!strict
-- 배경음악 (2026-10-09 사용자 요청)
--   평소: 느릿하고 여유 있는 곡(Config.Music.Calm)을 차례로 + 새소리 같은 자연 소리(Config.Music.Ambience, 있으면)
--   전투: 몹을 때리거나 몹에게 맞으면 긴박한 곡(Config.Music.Battle)으로 바꾸고, 마지막 전투 뒤 BattleHoldTime초 동안 유지
--   광산: 광산 배경음이 따로 있어서 음악은 MineVolume까지 줄인다
-- 두 곡은 각자 소리 하나씩 갖고, 볼륨을 천천히 바꿔 서로 넘긴다(크로스페이드). 재생이 안 되는 곡은 건너뛴다

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
local ambience: Sound? = nil
local lastCombat = -math.huge
local mode = "" -- "Calm" | "Battle" | "Mine"

-- 소리 하나를 만든다
local function makeSound(name: string, looped: boolean): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.Looped = looped
	sound.Volume = 0
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

-- 지금 상황에 맞는 곡으로 넘긴다
local function setMode(newMode: string)
	if newMode == mode then
		return
	end
	mode = newMode
	local music = Config.Music
	if newMode == "Battle" then
		-- 전투곡은 처음부터 (긴박감이 시작부터 나게)
		if not battle.Sound.IsPlaying then
			task.spawn(playNext, battle)
		end
		fadeTo(battle.Sound, battle.Volume)
		fadeTo(calm.Sound, 0)
	else
		fadeTo(calm.Sound, if newMode == "Mine" then music.MineVolume else calm.Volume)
		fadeTo(battle.Sound, 0)
		-- 전투곡은 다 줄어든 뒤 멈춘다 (다음 전투 때 처음부터)
		task.delay(music.FadeTime, function()
			if mode ~= "Battle" then
				battle.Sound:Stop()
			end
		end)
	end
	if ambience then
		fadeTo(ambience, if newMode == "Calm" then music.AmbienceVolume else 0)
	end
end

-- 전투가 났다 (내가 몹을 때렸거나 몹에게 맞았다)
local function markCombat()
	lastCombat = os.clock()
end

-- 클라이언트 시작 시 한 번 호출
function MusicController.init()
	local music = Config.Music
	calm = makeChannel("CalmMusic", music.Calm, music.Volume)
	battle = makeChannel("BattleMusic", music.Battle, music.BattleVolume)
	if music.Ambience ~= "" then
		local sound = makeSound("NatureAmbience", true)
		sound.SoundId = music.Ambience
		sound:Play()
		ambience = sound
	end
	task.spawn(playNext, calm)

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
			setMode(if inBattle and #battle.Tracks > 0 then "Battle" elseif inMine then "Mine" else "Calm")
			task.wait(0.5)
		end
	end)
end

return MusicController
