--!strict
-- 곡괭이 휘두르기 애니메이션 재생과 히트스톱(애니메이션 일시 정지).
-- Roblox 기본 toolslash 애니메이션을 Animator로 재생하므로 다른 플레이어에게도 보인다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local localPlayer = Players.LocalPlayer

local SwingAnimation = {}

local track: AnimationTrack? = nil
local trackHumanoid: Humanoid? = nil
local freezeToken = 0 -- 히트스톱이 겹칠 때 마지막 것만 속도를 되돌리게

-- 현재 캐릭터의 휘두르기 트랙을 가져온다 (캐릭터가 바뀌면 새로 로드)
local function getTrack(): AnimationTrack?
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	if track and trackHumanoid == humanoid then
		return track
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = if humanoid.RigType == Enum.HumanoidRigType.R6
		then Config.Mining.SwingAnimationR6
		else Config.Mining.SwingAnimationR15
	local newTrack = animator:LoadAnimation(animation)
	newTrack.Priority = Enum.AnimationPriority.Action
	newTrack.Looped = false
	track = newTrack
	trackHumanoid = humanoid
	return newTrack
end

-- 휘두르기 동작을 SwingAnimDuration 안에 끝나도록 재생한다
function SwingAnimation.play()
	local swingTrack = getTrack()
	if not swingTrack then
		return
	end
	-- 애니메이션 길이를 아직 모르면(첫 로드 중) 기본 속도로 재생
	local speed = if swingTrack.Length > 0 then swingTrack.Length / Config.Mining.SwingAnimDuration else 1
	swingTrack:Play(0.05, 1, speed)

	-- 좋은 곡괭이에는 머리에 궤적(Trail)이 달려 있다. 휘두르는 동안만 켠다
	local character = localPlayer.Character
	local tool = character and character:FindFirstChildWhichIsA("Tool")
	if tool then
		for _, trail in tool:GetDescendants() do
			if trail:IsA("Trail") then
				trail.Enabled = true
				task.delay(Config.Mining.SwingAnimDuration + 0.12, function()
					trail.Enabled = false
				end)
			end
		end
	end
end

-- 휘두르기 동작만 잠깐 멈춘다 (타격 히트스톱)
function SwingAnimation.freeze(duration: number)
	local swingTrack = track
	if not swingTrack or not swingTrack.IsPlaying then
		return
	end
	freezeToken += 1
	local token = freezeToken
	local speed = swingTrack.Speed
	swingTrack:AdjustSpeed(0)
	task.delay(duration, function()
		if token == freezeToken and swingTrack.IsPlaying then
			swingTrack:AdjustSpeed(speed)
		end
	end)
end

-- 캐릭터의 모든 애니메이션을 잠깐 멈춘다 (피버 멈춤 연출)
function SwingAnimation.freezeAll(duration: number)
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	for _, playing in animator:GetPlayingAnimationTracks() do
		local speed = playing.Speed
		playing:AdjustSpeed(0)
		task.delay(duration, function()
			if playing.IsPlaying then
				playing:AdjustSpeed(speed)
			end
		end)
	end
end

return SwingAnimation
