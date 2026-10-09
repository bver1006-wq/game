--!strict
-- 마을 NPC 움직임 (이 클라이언트에서만 재생하는 연출).
--   모든 NPC: 가만히 서 있는 숨쉬기 동작, 플레이어가 가까이 오면 고개를 그쪽으로 돌린다
--   속성 Pose = "Sit": 앉은 동작
--   속성 Work = "Hammer": 팔을 휘둘러 모루를 두드린다. 내려칠 때 불꽃(NPC 안 SparkPoint 파트)과 쇳소리
-- 동작은 Roblox 기본 애니메이션(누구나 쓸 수 있는 공식 에셋)을 쓴다. R15 몸 기준, R6도 고개 돌리기는 된다.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local NPC_TAG = "ShopNPC"
local LOOK_RANGE = 16 -- 이 거리 안이면 고개를 돌린다(스터드)
local SOUND_RANGE = 45 -- 망치 소리가 들리는 거리(스터드)
local HAMMER_PERIOD = 1.2 -- 한 번 두드리는 데 걸리는 시간(초)
local STRIKE_DELAY = 0.2 -- 휘두르기 시작부터 모루에 닿기까지(초)

-- Roblox 기본 R15 애니메이션
local ANIM_IDLE = "rbxassetid://507766388"
local ANIM_SIT = "rbxassetid://2506281703"
local ANIM_SWING = "rbxassetid://522635514" -- toolslash (곡괭이 휘두르기와 같은 것)

local localPlayer = Players.LocalPlayer

type NpcState = {
	Model: Model,
	Root: BasePart,
	Neck: Motor6D?,
	NeckBase: CFrame?,
	IsR15: boolean,
	Spark: BasePart?,
	SwingTrack: AnimationTrack?,
	NextStrike: number,
	HeadYaw: number,
}

local NpcAnimator = {}

local npcs: { NpcState } = {}
local registered: { [Instance]: boolean } = {}

-- 애니메이션 하나 불러서 재생
local function play(animator: Animator, id: string, looped: boolean, priority: Enum.AnimationPriority): AnimationTrack
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local track = animator:LoadAnimation(animation)
	track.Looped = looped
	track.Priority = priority
	return track
end

-- 불꽃 튀기기
local function sparks(at: BasePart)
	local attachment = at:FindFirstChild("SparkAttachment") :: Attachment?
	local emitter = attachment and attachment:FindFirstChildOfClass("ParticleEmitter")
	if not attachment then
		local newAttachment = Instance.new("Attachment")
		newAttachment.Name = "SparkAttachment"
		newAttachment.Parent = at
		local newEmitter = Instance.new("ParticleEmitter")
		newEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		newEmitter.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 90, 20))
		newEmitter.LightEmission = 1
		newEmitter.Size = NumberSequence.new(0.25, 0)
		newEmitter.Lifetime = NumberRange.new(0.2, 0.45)
		newEmitter.Speed = NumberRange.new(6, 12)
		newEmitter.SpreadAngle = Vector2.new(70, 70)
		newEmitter.EmissionDirection = Enum.NormalId.Top
		newEmitter.Acceleration = Vector3.new(0, -30, 0)
		newEmitter.Rate = 0
		newEmitter.Parent = newAttachment
		emitter = newEmitter
	end
	if emitter then
		emitter:Emit(14)
	end
end

-- 쇳소리 (가까울 때만)
local function clang(at: BasePart)
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or (root.Position - at.Position).Magnitude > SOUND_RANGE then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = Config.Sounds.PickaxeClang
	sound.PlaybackSpeed = 1.25 + math.random() * 0.15
	sound.Volume = 0.35
	sound.RollOffMaxDistance = SOUND_RANGE
	sound.Parent = at
	sound:Play()
	task.delay(2, function()
		sound:Destroy()
	end)
end

-- NPC 하나를 등록한다 (스트리밍으로 몸 파트가 늦게 들어올 수 있어 잠시 기다린다)
local function register(npc: Instance)
	if not npc:IsA("Model") or registered[npc] then
		return
	end
	registered[npc] = true
	local root = npc:WaitForChild("HumanoidRootPart", 15)
	local humanoid = npc:WaitForChild("Humanoid", 15)
	if not root or not root:IsA("BasePart") or not humanoid or not humanoid:IsA("Humanoid") then
		registered[npc] = nil
		return
	end
	local isR15 = humanoid.RigType == Enum.HumanoidRigType.R15
	local neckParent = if isR15 then npc:WaitForChild("Head", 10) else npc:WaitForChild("Torso", 10)
	local neck = neckParent and neckParent:WaitForChild("Neck", 5)
	local spark = npc:WaitForChild("SparkPoint", 3)

	local state: NpcState = {
		Model = npc,
		Root = root,
		Neck = if neck and neck:IsA("Motor6D") then neck else nil,
		NeckBase = if neck and neck:IsA("Motor6D") then neck.C0 else nil,
		IsR15 = isR15,
		Spark = if spark and spark:IsA("BasePart") then spark else nil,
		SwingTrack = nil,
		NextStrike = os.clock() + math.random(),
		HeadYaw = 0,
	}

	local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 5)
	if isR15 and animator and animator:IsA("Animator") then
		if npc:GetAttribute("Pose") == "Sit" then
			play(animator, ANIM_SIT, true, Enum.AnimationPriority.Core):Play()
		else
			play(animator, ANIM_IDLE, true, Enum.AnimationPriority.Core):Play()
		end
		if npc:GetAttribute("Work") == "Hammer" then
			state.SwingTrack = play(animator, ANIM_SWING, false, Enum.AnimationPriority.Action)
		end
	end
	table.insert(npcs, state)
end

-- 매 프레임
local function update(dt: number)
	local character = localPlayer.Character
	local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
	local now = os.clock()
	for _, npc in npcs do
		if not npc.Model.Parent then
			continue
		end
		-- 고개 돌리기 (좌우만, 최대 약 70도)
		if npc.Neck and npc.NeckBase then
			local targetYaw = 0
			if playerRoot and playerRoot:IsA("BasePart") then
				local offset = npc.Root.CFrame:PointToObjectSpace(playerRoot.Position)
				if offset.Magnitude <= LOOK_RANGE and offset.Z < 2 then
					targetYaw = math.clamp(math.atan2(-offset.X, -offset.Z), -1.2, 1.2)
				end
			end
			npc.HeadYaw += (targetYaw - npc.HeadYaw) * math.min(dt * 5, 1)
			-- R15 목은 Y축, R6 목은 기울어진 축이라 Z축으로 돌린다
			npc.Neck.C0 = if npc.IsR15
				then npc.NeckBase * CFrame.Angles(0, npc.HeadYaw, 0)
				else npc.NeckBase * CFrame.Angles(0, 0, npc.HeadYaw)
		end
		-- 망치질: 일정 간격으로 휘두르고, 닿는 순간 불꽃 + 소리
		local swing = npc.SwingTrack
		if swing and now >= npc.NextStrike then
			npc.NextStrike = now + HAMMER_PERIOD
			swing:Play(0.05, 1, 1)
			local spark = npc.Spark
			if spark then
				task.delay(STRIKE_DELAY, function()
					sparks(spark)
					clang(spark)
				end)
			end
		end
	end
end

-- 클라이언트 시작 시 한 번 호출
function NpcAnimator.init()
	for _, npc in CollectionService:GetTagged(NPC_TAG) do
		task.spawn(register, npc)
	end
	CollectionService:GetInstanceAddedSignal(NPC_TAG):Connect(function(npc)
		task.spawn(register, npc)
	end)
	RunService.RenderStepped:Connect(update)
end

return NpcAnimator
