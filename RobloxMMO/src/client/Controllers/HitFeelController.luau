--!strict
-- 타격감 연출: 히트스톱, 카메라 흔들림, 바위 떨림, 파편, 타격음, 깨질 때 광석이 튀어나와 빨려오는 연출.
-- 서버가 보낸 HitEffect/RockBroken을 받아 각 클라이언트가 로컬로만 재생한다. 바위를 서버에서 움직이지 않는다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local OreDefs = require(ReplicatedStorage.Shared.OreDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RockHUD = require(script.Parent.RockHUD)
local SwingAnimation = require(script.Parent.SwingAnimation)

local localPlayer = Players.LocalPlayer

local DEBRIS_TEXTURE = "rbxassetid://243660364"
local DEFAULT_COLOR = Color3.fromRGB(140, 140, 140)

local HitFeelController = {}

local effectsFolder: Folder
local sfxGroup: SoundGroup
local random = Random.new()

-- 바위가 떨리기 전 원래 위치 (떨림이 겹쳐도 항상 여기로 돌아온다)
local restPivots: { [Model]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local shakeTokens: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

-- 카메라 흔들림 상태
local shakeMagnitude = 0
local shakeEndTime = 0
local shakeDuration = 1

-- 광석 종류의 색
local function oreColor(oreType: unknown): Color3
	if typeof(oreType) == "string" and OreDefs[oreType] then
		return OreDefs[oreType].Color
	end
	return DEFAULT_COLOR
end

-- 바위의 원래 위치를 돌려준다 (처음 보는 바위면 지금 위치를 원래 위치로 기록)
function HitFeelController.getRestPivot(rock: Model): CFrame
	local pivot = restPivots[rock]
	if not pivot then
		pivot = rock:GetPivot()
		restPivots[rock] = pivot
	end
	return pivot
end

-- 바위를 원래 위치 기준으로 짧게 떤다. 연속으로 맞아도 밀리지 않는다
function HitFeelController.shakeRock(rock: Model, amplitudeScale: number?)
	if not rock.Parent then
		return
	end
	local rest = HitFeelController.getRestPivot(rock)
	local amplitude = Config.HitFeel.RockShake.Amplitude * (amplitudeScale or 1)
	local duration = Config.HitFeel.RockShake.Duration
	local token = (shakeTokens[rock] or 0) + 1
	shakeTokens[rock] = token

	local direction = Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1))
	direction = if direction.Magnitude > 0.01 then direction.Unit else Vector3.xAxis
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		if shakeTokens[rock] ~= token or not rock.Parent then
			connection:Disconnect()
			return
		end
		local t = (os.clock() - started) / duration
		if t >= 1 then
			rock:PivotTo(rest)
			connection:Disconnect()
			return
		end
		local offset = direction * math.sin(t * math.pi * 5) * amplitude * (1 - t)
		rock:PivotTo(rest + offset)
	end)
end

-- 위치에서 소리를 한 번 재생한다. id가 비어 있으면 아무것도 안 한다
function HitFeelController.playSound(soundId: string, position: Vector3?, playbackSpeed: number?, volume: number?)
	if soundId == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.PlaybackSpeed = playbackSpeed or 1
	sound.Volume = volume or 0.6
	sound.SoundGroup = sfxGroup
	if position then
		local attachment = Instance.new("Attachment")
		attachment.WorldPosition = position
		attachment.Parent = Workspace.Terrain
		sound.Parent = attachment
		sound.Ended:Once(function()
			attachment:Destroy()
		end)
		task.delay(6, function()
			attachment:Destroy()
		end)
	else
		sound.Parent = SoundService
		sound.Ended:Once(function()
			sound:Destroy()
		end)
		task.delay(6, function()
			sound:Destroy()
		end)
	end
	sound:Play()
end

-- 효과음 전체 볼륨 (피버 멈춤 때 소리를 끊는 데 쓴다)
function HitFeelController.setSfxVolume(volume: number)
	sfxGroup.Volume = volume
end

-- 파편 파티클을 한 번 터뜨린다
function HitFeelController.emitDebris(position: Vector3, color: Color3, count: number, speedScale: number?)
	local scale = speedScale or 1
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = Workspace.Terrain

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = DEBRIS_TEXTURE
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3 * scale),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Lifetime = NumberRange.new(0.35, 0.7)
	emitter.Speed = NumberRange.new(7 * scale, 14 * scale)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Acceleration = Vector3.new(0, -45, 0)
	emitter.Drag = 2
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-300, 300)
	emitter.LightInfluence = 1
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(count)

	task.delay(1.5, function()
		attachment:Destroy()
	end)
end

-- 카메라를 짧게 흔든다 (더 센 흔들림이 오면 덮어쓴다)
function HitFeelController.cameraShake(magnitude: number, duration: number)
	local now = os.clock()
	local remaining = if now < shakeEndTime then shakeMagnitude * (shakeEndTime - now) / shakeDuration else 0
	if magnitude >= remaining then
		shakeMagnitude = magnitude
		shakeDuration = duration
		shakeEndTime = now + duration
	end
end

-- 매 프레임 카메라 모듈이 위치를 잡은 직후에 흔들림 오프셋을 더한다
local function applyCameraShake()
	local now = os.clock()
	if now >= shakeEndTime then
		return
	end
	local strength = shakeMagnitude * (shakeEndTime - now) / shakeDuration
	local camera = Workspace.CurrentCamera
	camera.CFrame *= CFrame.new(
		random:NextNumber(-1, 1) * strength,
		random:NextNumber(-1, 1) * strength,
		0
	) * CFrame.Angles(0, 0, math.rad(random:NextNumber(-1, 1) * strength * 4))
end

-- 깨진 바위에서 광석 조각이 튀어나왔다가 캐릭터에게 빨려온다
local function spawnOreChunks(position: Vector3, color: Color3, amount: number)
	local count = math.min(amount, Config.HitFeel.OreChunkMax)
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	for _ = 1, count do
		local chunk = Instance.new("Part")
		local size = random:NextNumber(0.3, 0.5)
		chunk.Size = Vector3.new(size, size, size)
		chunk.Color = color
		chunk.Material = Enum.Material.Slate
		chunk.CanCollide = true
		chunk.CanQuery = false
		chunk.CanTouch = false
		chunk.CastShadow = false
		chunk.Massless = true
		chunk.CFrame = CFrame.new(position + Vector3.new(0, 0.8, 0))
			* CFrame.Angles(random:NextNumber(0, 6.28), random:NextNumber(0, 6.28), 0)
		chunk.AssemblyLinearVelocity = Vector3.new(random:NextNumber(-12, 12), random:NextNumber(14, 24), random:NextNumber(-12, 12))
		chunk.AssemblyAngularVelocity = Vector3.new(random:NextNumber(-10, 10), random:NextNumber(-10, 10), 0)
		chunk.Parent = effectsFolder

		-- 잠깐 튀어 오른 뒤 캐릭터 쪽으로 빨려 들어간다
		task.delay(Config.HitFeel.OreSuckDelay + random:NextNumber(0, 0.25), function()
			if not chunk.Parent then
				return
			end
			chunk.Anchored = true
			chunk.CanCollide = false
			local from = chunk.Position
			local started = os.clock()
			local duration = Config.HitFeel.OreSuckDuration
			local connection: RBXScriptConnection
			connection = RunService.RenderStepped:Connect(function()
				local t = math.min((os.clock() - started) / duration, 1)
				local target = if root.Parent then root.Position else from
				local eased = t * t -- 갈수록 빨라지게
				chunk.Position = from:Lerp(target, eased)
				chunk.Size = Vector3.new(size, size, size) * (1 - t * 0.6)
				if t >= 1 then
					connection:Disconnect()
					chunk:Destroy()
				end
			end)
		end)
		task.delay(4, function()
			chunk:Destroy()
		end)
	end
end

-- 좋은 곡괭이 타격 연출: 충격파 고리 + 사방으로 튀는 광석 조각 (+ 다이아몬드는 반짝이)
local function tierImpact(rock: Model?, hitPosition: Vector3, color: Color3, tier: number, judgment: string)
	local effect = Config.HitFeel.TierEffects[tier]
	if not effect then
		return
	end
	local center = if rock then rock:GetPivot().Position else hitPosition
	local outward = (hitPosition - center) * Vector3.new(1, 0, 1)
	outward = if outward.Magnitude > 0.01 then outward.Unit else Vector3.zAxis

	-- 충격파 고리 (타격 면에서 바깥쪽을 보며 퍼진다)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = effect.Color
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.15, 0.6, 0.6)
	ring.CFrame = CFrame.lookAt(hitPosition, hitPosition + outward) * CFrame.Angles(0, math.rad(90), 0)
	ring.Parent = effectsFolder
	local ringSize = effect.Ring * (if judgment == "Perfect" then 1.3 else 1)
	TweenService:Create(ring, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.05, ringSize, ringSize),
		Transparency = 1,
	}):Play()
	task.delay(0.3, function()
		ring:Destroy()
	end)

	-- 사방으로 튀는 광석 조각 (바닥에 튕긴 뒤 사라진다)
	local count = effect.Chunks + (if judgment == "Perfect" then 3 else 0)
	for _ = 1, count do
		local chunk = Instance.new("Part")
		local size = random:NextNumber(0.2, 0.45)
		chunk.Size = Vector3.new(size, size, size)
		chunk.Color = if random:NextNumber() < 0.3 then effect.Color else color
		chunk.Material = if random:NextNumber() < 0.3 then Enum.Material.Neon else Enum.Material.Slate
		chunk.CanCollide = true
		chunk.CanQuery = false
		chunk.CanTouch = false
		chunk.CastShadow = false
		chunk.Massless = true
		chunk.CFrame = CFrame.new(hitPosition + outward * 0.3) * CFrame.Angles(random:NextNumber(0, 6), random:NextNumber(0, 6), 0)
		local spread = Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1)) * 0.7
		chunk.AssemblyLinearVelocity = (outward + spread).Unit * random:NextNumber(14, 24) + Vector3.new(0, random:NextNumber(10, 20), 0)
		chunk.AssemblyAngularVelocity = Vector3.new(random:NextNumber(-20, 20), random:NextNumber(-20, 20), random:NextNumber(-20, 20))
		chunk.Parent = effectsFolder
		task.delay(0.9, function()
			if chunk.Parent then
				TweenService:Create(chunk, TweenInfo.new(0.3), { Transparency = 1, Size = chunk.Size * 0.3 }):Play()
			end
		end)
		task.delay(1.25, function()
			chunk:Destroy()
		end)
	end

	-- 다이아몬드: 반짝이 가루 + 높은 "팅" 소리
	if effect.Sparkle then
		local attachment = Instance.new("Attachment")
		attachment.WorldPosition = hitPosition
		attachment.Parent = Workspace.Terrain
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = ColorSequence.new(effect.Color)
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new(0.6, 0)
		emitter.Lifetime = NumberRange.new(0.3, 0.6)
		emitter.Speed = NumberRange.new(8, 16)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Rate = 0
		emitter.Parent = attachment
		emitter:Emit(25)
		task.delay(1, function()
			attachment:Destroy()
		end)
		HitFeelController.playSound(Config.Sounds.HitPerfect, hitPosition, 1.7, 0.45)
	end
end

-- 서버의 HitEffect: 근처 누군가가 바위를 쳤다
local function onHitEffect(
	rock: Model?,
	judgment: string,
	hitPosition: Vector3,
	attackerUserId: number,
	_hitTime: number,
	_ghostDuration: number,
	pickaxeTier: number?
)
	local isMine = attackerUserId == localPlayer.UserId
	local color = if rock then oreColor(rock:GetAttribute("OreType")) else DEFAULT_COLOR
	local debrisCount = (Config.HitFeel.DebrisCount :: any)[judgment] or Config.HitFeel.DebrisCount.Normal

	if rock and rock.Parent then
		HitFeelController.shakeRock(rock, if judgment == "Perfect" then 1.6 else 1)
	end
	HitFeelController.emitDebris(hitPosition, color, debrisCount, if judgment == "Perfect" then 1.3 else 1)

	local pitch = random:NextNumber(Config.HitFeel.PitchRange.Min, Config.HitFeel.PitchRange.Max)
	if judgment == "Perfect" then
		HitFeelController.playSound(Config.Sounds.HitPerfect, hitPosition, pitch, 0.8)
	else
		HitFeelController.playSound(Config.Sounds.HitNormal, hitPosition, pitch * (if judgment == "Nice" then 1.08 else 1), 0.6)
	end

	-- 곡괭이 "깡!": 돌 소리에 겹친다. 판정이 좋을수록 높고 크게
	local clang = Config.HitFeel.Clang
	local clangPitch = pitch * (if judgment == "Perfect" then clang.PerfectPitch elseif judgment == "Nice" then clang.NicePitch else 1)
	HitFeelController.playSound(
		Config.Sounds.PickaxeClang,
		hitPosition,
		clangPitch,
		if judgment == "Perfect" then clang.PerfectVolume else clang.Volume
	)

	local tier = pickaxeTier or 1
	tierImpact(rock, hitPosition, color, tier, judgment)

	if isMine then
		SwingAnimation.freeze((Config.HitFeel.HitStop :: any)[judgment] or Config.HitFeel.HitStop.Normal)
		local shake = Config.HitFeel.CameraShake
		local tierEffect = Config.HitFeel.TierEffects[tier]
		local tierShake = if tierEffect then tierEffect.Shake else 1
		HitFeelController.cameraShake(shake.Magnitude * tierShake * (if judgment == "Perfect" then shake.PerfectMultiplier else 1), shake.Duration)
	end
	if rock and (judgment == "Perfect" or judgment == "Nice") then
		RockHUD.showJudgment(rock, judgment)
		HitFeelController.playSound(Config.Sounds.JudgmentPop, hitPosition, if judgment == "Perfect" then 1.25 else 1, 0.5)
	end
end

-- 서버의 RockBroken: 바위가 깨졌다 (rewards는 UserId 문자열 → 개수, feverBonus는 피버 보너스 개수)
local function onRockBroken(position: Vector3, oreType: string, rewards: { [string]: number }, feverBonus: number)
	local color = oreColor(oreType)
	HitFeelController.emitDebris(position, color, Config.HitFeel.DebrisCount.Break, 1.6)
	HitFeelController.playSound(Config.Sounds.RockBreak, position, random:NextNumber(0.95, 1.05), 0.8)

	local amount = rewards[tostring(localPlayer.UserId)]
	if amount and amount > 0 then
		HitFeelController.cameraShake(Config.HitFeel.CameraShake.Magnitude * 2, Config.HitFeel.CameraShake.Duration * 2)
		spawnOreChunks(position, color, amount)
		local def = OreDefs[oreType]
		RockHUD.showReward(position, amount, if def then def.DisplayName else oreType, feverBonus)
	end
end

-- 클라이언트 시작 시 한 번 호출
function HitFeelController.init()
	local folder = Instance.new("Folder")
	folder.Name = "ClientEffects"
	folder.Parent = Workspace
	effectsFolder = folder

	local group = Instance.new("SoundGroup")
	group.Name = "MiningSFX"
	group.Volume = 1
	group.Parent = SoundService
	sfxGroup = group

	RunService:BindToRenderStep("MiningCameraShake", Enum.RenderPriority.Camera.Value + 1, applyCameraShake)
	Remotes.get(Remotes.Names.HitEffect).OnClientEvent:Connect(onHitEffect)
	Remotes.get(Remotes.Names.RockBroken).OnClientEvent:Connect(onRockBroken)
end

return HitFeelController
