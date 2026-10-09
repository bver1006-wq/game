--!strict
-- 타격감 연출: 히트스톱, 카메라 흔들림, 바위 떨림, 파편, 타격음, 깨질 때 광석이 튀어나와 빨려오는 연출.
-- 나무는 "퍽" 소리·나뭇조각·떨어지는 잎으로 바꾸고, 다 베면 쓰러지는 연출을 한다.
-- 서버가 보낸 HitEffect/RockBroken을 받아 각 클라이언트가 로컬로만 재생한다. 바위를 서버에서 움직이지 않는다.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local OreDefs = require(ReplicatedStorage.Shared.OreDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PickupFeed = require(script.Parent.PickupFeed)
local RockHUD = require(script.Parent.RockHUD)
local SwingAnimation = require(script.Parent.SwingAnimation)
local TargetController = require(script.Parent.TargetController)

local localPlayer = Players.LocalPlayer

local DEBRIS_TEXTURE = "rbxassetid://243660364"
local DEFAULT_COLOR = Color3.fromRGB(140, 140, 140)
local LEAF_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local DEFAULT_LEAF_COLOR = Color3.fromRGB(80, 140, 60)

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

-- 마지막 일격을 맞은 나무의 복제본. RockBroken이 오면 이걸 쓰러뜨린다 (서버는 원본을 바로 지운다)
type PendingFall = { Model: Model, Position: Vector3, Direction: Vector3, LeafColor: Color3 }
local pendingFalls: { PendingFall } = {}

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

-- 줍기 연출: 조각이 사방으로 튀어 땅에 떨어져 있다가, 가까이 가거나 PickupAutoTime이 지나면 캐릭터에게 빨려 온다
-- 빨려 들어올 때마다 "뽁"(점점 높게), 다 들어오면 onCollected(실제 개수)
-- shape: "Cube"(광석) / "Log"(통나무) / "Coin"(골드)
function HitFeelController.spawnPickups(position: Vector3, color: Color3, count: number, material: Enum.Material, shape: string, onCollected: (() -> ())?)
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	count = math.min(count, Config.HitFeel.OreChunkMax)
	if not root or not root:IsA("BasePart") or count <= 0 then
		if onCollected then
			onCollected()
		end
		return
	end
	local feel = Config.HitFeel
	local chunks = {}
	for _ = 1, count do
		local chunk = Instance.new("Part")
		local size = random:NextNumber(0.35, 0.55)
		chunk.Size = Vector3.new(size, size, size)
		if shape == "Log" then
			chunk.Shape = Enum.PartType.Cylinder
			chunk.Size = Vector3.new(size * 2, size, size)
		elseif shape == "Coin" then
			chunk.Shape = Enum.PartType.Cylinder
			chunk.Size = Vector3.new(0.12, size * 1.2, size * 1.2)
		end
		chunk.Color = color
		chunk.Material = material
		chunk.CanCollide = true
		chunk.CanQuery = false
		chunk.CanTouch = false
		chunk.CastShadow = false
		chunk.Massless = true
		chunk.CFrame = CFrame.new(position + Vector3.new(0, 0.8, 0)) * CFrame.Angles(random:NextNumber(0, 6.28), random:NextNumber(0, 6.28), 0)
		chunk.AssemblyLinearVelocity = Vector3.new(random:NextNumber(-14, 14), random:NextNumber(14, 24), random:NextNumber(-14, 14))
		chunk.AssemblyAngularVelocity = Vector3.new(random:NextNumber(-10, 10), random:NextNumber(-10, 10), 0)
		chunk.Parent = effectsFolder
		table.insert(chunks, { Part = chunk, Size = chunk.Size, State = "Ground", From = Vector3.zero, Start = 0 })
	end

	local started = os.clock()
	local collected = 0
	local finished = false
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local target = if root.Parent then root.Position else position
		local remaining = 0
		for _, entry in chunks do
			if entry.State == "Ground" then
				remaining += 1
				local landed = now - started >= feel.PickupLandTime
				local near = (entry.Part.Position - target).Magnitude <= feel.PickupMagnetRange
				if landed and (near or now - started >= feel.PickupAutoTime) then
					-- 빨려 오기 시작 (조금씩 어긋나게)
					entry.State = "Suck"
					entry.From = entry.Part.Position
					entry.Start = now + random:NextNumber(0, 0.15)
					entry.Part.Anchored = true
					entry.Part.CanCollide = false
				end
			elseif entry.State == "Suck" then
				remaining += 1
				local t = math.clamp((now - entry.Start) / feel.OreSuckDuration, 0, 1)
				entry.Part.Position = entry.From:Lerp(target, t * t)
				entry.Part.Size = entry.Size * (1 - t * 0.6)
				if t >= 1 then
					entry.State = "Done"
					entry.Part:Destroy()
					collected += 1
					HitFeelController.playSound(Config.Sounds.JudgmentPop, nil, 1 + math.min(collected, 15) * 0.05, 0.35)
				end
			end
		end
		if remaining == 0 and not finished then
			finished = true
			connection:Disconnect()
			if onCollected then
				onCollected()
			end
		end
	end)
	-- 안전장치: 오래 지나도 안 끝나면 정리
	task.delay(feel.PickupAutoTime + 4, function()
		if not finished then
			finished = true
			connection:Disconnect()
			for _, entry in chunks do
				if entry.Part.Parent then
					entry.Part:Destroy()
				end
			end
			if onCollected then
				onCollected()
			end
		end
	end)
end

-- 좋은 곡괭이 타격 연출: 충격파 고리 + 사방으로 튀는 광석 조각 (+ 다이아몬드는 반짝이)
-- effects: 곡괭이는 Config.HitFeel.TierEffects, 도끼는 AxeTierEffects (도끼 표에는 불꽃·베는 빛줄기가 더 있다)
local function tierImpact(rock: Model?, hitPosition: Vector3, color: Color3, tier: number, judgment: string, material: Enum.Material, effects: { [number]: any })
	local effect = effects[tier]
	if not effect then
		return
	end
	local center = if rock then TargetController.focusPosition(rock) else hitPosition
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
		chunk.Material = if random:NextNumber() < 0.3 then Enum.Material.Neon else material
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

	-- 도끼: 사방으로 튀는 불꽃 (좋은 도끼일수록 많이)
	local sparkCount = (effect.Sparks or 0) + (if judgment == "Perfect" and (effect.Sparks or 0) > 0 then 8 else 0)
	if sparkCount > 0 then
		local attachment = Instance.new("Attachment")
		attachment.WorldPosition = hitPosition + outward * 0.2
		attachment.Parent = Workspace.Terrain
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = ColorSequence.new(effect.Color, Color3.new(1, 1, 1))
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new(0.25, 0)
		emitter.Lifetime = NumberRange.new(0.15, 0.35)
		emitter.Speed = NumberRange.new(14, 26)
		emitter.SpreadAngle = Vector2.new(50, 50)
		emitter.Acceleration = Vector3.new(0, -40, 0)
		emitter.Rate = 0
		emitter.Parent = attachment
		emitter.EmissionDirection = Enum.NormalId.Top
		attachment.WorldCFrame = CFrame.lookAt(attachment.WorldPosition, attachment.WorldPosition + outward) * CFrame.Angles(math.rad(-90), 0, 0)
		emitter:Emit(sparkCount)
		task.delay(0.8, function()
			attachment:Destroy()
		end)
	end

	-- 도끼: 줄기를 가로로 베는 빛줄기
	if effect.Slash then
		local slash = Instance.new("Part")
		slash.Material = Enum.Material.Neon
		slash.Color = effect.Color
		slash.Anchored = true
		slash.CanCollide = false
		slash.CanQuery = false
		slash.CanTouch = false
		slash.CastShadow = false
		slash.Transparency = 0.1
		local tangent = Vector3.yAxis:Cross(outward)
		local length = effect.Ring * (if judgment == "Perfect" then 1.3 else 1)
		slash.Size = Vector3.new(0.08, 0.12, length * 0.3)
		slash.CFrame = CFrame.lookAt(hitPosition + outward * 0.15, hitPosition + outward * 0.15 + tangent) * CFrame.Angles(0, 0, math.rad(random:NextNumber(-20, 20)))
		slash.Parent = effectsFolder
		TweenService:Create(slash, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.04, 0.35, length),
			Transparency = 1,
		}):Play()
		task.delay(0.25, function()
			slash:Destroy()
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

-- 나무 위쪽(잎 부분)에서 잎이 팔랑팔랑 떨어진다
-- 나뭇잎 흩날리기: 얇은 잎 조각이 팔랑팔랑 흔들리며 천천히 떨어지다 사라진다 (이 클라이언트에만)
local function leafBurst(origin: Vector3, color: Color3, count: number, spread: number)
	local leaves = {}
	for _ = 1, count do
		local leaf = Instance.new("Part")
		local scale = random:NextNumber(0.8, 1.3)
		leaf.Size = Vector3.new(0.38 * scale, 0.05, 0.26 * scale)
		leaf.Color = color:Lerp(Color3.fromRGB(255, 250, 170), random:NextNumber(0, 0.2))
		leaf.Material = Enum.Material.SmoothPlastic
		leaf.Anchored = true
		leaf.CanCollide = false
		leaf.CanQuery = false
		leaf.CanTouch = false
		leaf.CastShadow = false
		leaf.Parent = effectsFolder
		local start = origin + Vector3.new(random:NextNumber(-1, 1), random:NextNumber(-0.5, 1), random:NextNumber(-1, 1)) * spread
		table.insert(leaves, {
			Part = leaf,
			Start = start,
			Drift = Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1)) * random:NextNumber(0.5, 2),
			Fall = random:NextNumber(1.5, 2.6), -- 1초에 떨어지는 거리
			Phase = random:NextNumber(0, math.pi * 2),
			Spin = Vector3.new(random:NextNumber(-3, 3), random:NextNumber(-3, 3), random:NextNumber(-3, 3)),
			Life = random:NextNumber(1.6, 2.6),
		})
	end
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		local alive = false
		for _, entry in leaves do
			local life = t / entry.Life
			if life >= 1 then
				if entry.Part.Parent then
					entry.Part:Destroy()
				end
			else
				alive = true
				-- 좌우로 흔들리며(sin) 천천히 내려온다
				local sway = Vector3.new(math.sin(t * 3 + entry.Phase), 0, math.cos(t * 2.4 + entry.Phase)) * 0.6
				local position = entry.Start + entry.Drift * t + sway - Vector3.new(0, entry.Fall * t, 0)
				entry.Part.CFrame = CFrame.new(position) * CFrame.Angles(entry.Spin.X * t, entry.Spin.Y * t, entry.Spin.Z * t + math.sin(t * 4 + entry.Phase) * 0.6)
				entry.Part.Transparency = if life > 0.7 then (life - 0.7) / 0.3 else 0
			end
		end
		if not alive then
			connection:Disconnect()
		end
	end)
end

-- 나무 위쪽(잎 부분)에서 잎이 떨어진다
local function dropLeaves(rock: Model?, position: Vector3, color: Color3, count: number)
	local height = if rock and rock.Parent then rock:GetExtentsSize().Y else 8
	leafBurst(position + Vector3.new(0, height * 0.65, 0), color, count, 2.5)
end

-- 짧게 떠올랐다 사라지는 글자 ("단단해!")
local function popText(position: Vector3, text: string, color: Color3)
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = Workspace.Terrain
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(4, 1.2)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 1, 0)
	billboard.Adornee = attachment
	billboard.Parent = effectsFolder
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = color
	label.Parent = billboard
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = label
	TweenService:Create(billboard, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0) }):Play()
	task.delay(0.45, function()
		TweenService:Create(label, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.25), { Transparency = 1 }):Play()
	end)
	task.delay(0.75, function()
		attachment:Destroy()
		billboard:Destroy()
	end)
end
HitFeelController.popText = popText

-- 장비가 모자라 튕겨 나온 타격: 둔한 "텅" 소리, 작은 회색 불꽃, "단단해!" (체력은 그대로)
local function blockedEffect(rock: Model?, hitPosition: Vector3, isMine: boolean)
	HitFeelController.playSound(Config.Sounds.PickaxeClang, hitPosition, 0.55, 0.45)
	HitFeelController.emitDebris(hitPosition, Color3.fromRGB(190, 190, 190), 4, 0.6)
	if rock and rock.Parent then
		HitFeelController.shakeRock(rock, 0.25)
	end
	popText(hitPosition, "단단해!", Color3.fromRGB(200, 200, 210))
	if isMine then
		HitFeelController.cameraShake(Config.HitFeel.CameraShake.Magnitude * 0.6, Config.HitFeel.CameraShake.Duration)
		SwingAnimation.freeze(0.1) -- 손이 튕겨 나오는 느낌
	end
end

-- 마지막 일격을 맞은 나무를 복제해 둔다. 원본은 서버가 곧 지우므로, 복제본을 쓰러뜨리는 데 쓴다
local function prepareFall(rock: Model, hitPosition: Vector3)
	local model = rock:Clone()
	-- 자동 조준·체력바에 걸리지 않게 태그와 속성을 지운다
	CollectionService:RemoveTag(model, "OreNode")
	for _, name in { "OreType", "Hp", "MaxHp" } do
		model:SetAttribute(name, nil)
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
	local pivot = HitFeelController.getRestPivot(rock)
	model:PivotTo(pivot)
	-- 친 사람 반대쪽으로 쓰러진다
	local away = (pivot.Position - hitPosition) * Vector3.new(1, 0, 1)
	local entry: PendingFall = {
		Model = model,
		Position = pivot.Position,
		Direction = if away.Magnitude > 0.01 then away.Unit else Vector3.xAxis,
		LeafColor = (function()
			local def = TargetController.getDef(rock)
			return if def and def.LeafColor then def.LeafColor else DEFAULT_LEAF_COLOR
		end)(),
	}
	table.insert(pendingFalls, entry)
	-- 피버가 끝날 때까지 기다릴 수 있으니 넉넉히 두고, 그래도 안 쓰이면 버린다
	task.delay(Config.Fever.FreezeDuration + Config.Fever.OrbitDuration + Config.Fever.TitleDuration + Config.Fever.TapDuration + 5, function()
		local index = table.find(pendingFalls, entry)
		if index then
			table.remove(pendingFalls, index)
			entry.Model:Destroy()
		end
	end)
end

-- 복제해 둔 나무를 밑동을 축으로 쓰러뜨리고 서서히 사라지게 한다
local function playFall(entry: PendingFall)
	local tree = Config.HitFeel.Tree
	local model = entry.Model
	model.Parent = effectsFolder
	local start = model:GetPivot()
	-- 쓰러지는 방향과 수직인 수평축으로 90도 가까이 돌린다
	local axis = Vector3.yAxis:Cross(entry.Direction).Unit
	local parts: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	local baseTransparency: { [BasePart]: number } = {}
	for _, part in parts do
		baseTransparency[part] = part.Transparency
	end

	local started = os.clock()
	local landed = false
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		if not model.Parent then
			connection:Disconnect()
			return
		end
		local elapsed = os.clock() - started
		local t = math.min(elapsed / tree.FallTime, 1)
		local angle = math.rad(85) * t * t -- 처음엔 천천히, 갈수록 빨리 넘어간다
		model:PivotTo(CFrame.fromAxisAngle(axis, angle) * (start - start.Position) + start.Position)
		if t >= 1 and not landed then
			landed = true
			-- 땅에 닿는 순간: 흙먼지 + 흔들림
			leafBurst(entry.Position + entry.Direction * 4 + Vector3.new(0, 1.5, 0), entry.LeafColor, 18, 2.5)
			HitFeelController.cameraShake(Config.HitFeel.CameraShake.Magnitude * 1.5, Config.HitFeel.CameraShake.Duration * 2)
		end
		local fade = math.clamp((elapsed - tree.FallTime) / tree.FadeTime, 0, 1)
		for _, part in parts do
			part.Transparency = baseTransparency[part] + (1 - baseTransparency[part]) * fade
		end
		if fade >= 1 then
			connection:Disconnect()
			model:Destroy()
		end
	end)
end

-- 번개: 하늘에서 지그재그 빛줄기가 내려와 나무에 꽂힌다 (번쩍임 + 천둥 + 큰 흔들림)
local function playLightning(target: Vector3, isMine: boolean)
	local bolt = Config.HitFeel.Lightning
	local parts: { BasePart } = {}
	local previous = target + Vector3.new(random:NextNumber(-4, 4), bolt.Height, random:NextNumber(-4, 4))
	for i = 1, bolt.Segments do
		local t = i / bolt.Segments
		local point = if i == bolt.Segments
			then target
			else previous:Lerp(target, 1 / (bolt.Segments - i + 1)) + Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1)) * bolt.Jitter * (1 - t)
		local length = (point - previous).Magnitude
		local segment = Instance.new("Part")
		segment.Material = Enum.Material.Neon
		segment.Color = bolt.Color
		segment.Anchored = true
		segment.CanCollide = false
		segment.CanQuery = false
		segment.CanTouch = false
		segment.CastShadow = false
		segment.Size = Vector3.new(0.35, 0.35, length)
		segment.CFrame = CFrame.lookAt((previous + point) / 2, point)
		segment.Parent = effectsFolder
		table.insert(parts, segment)
		previous = point
	end
	-- 번쩍이는 빛
	local flashAttachment = Instance.new("Attachment")
	flashAttachment.WorldPosition = target + Vector3.new(0, 4, 0)
	flashAttachment.Parent = Workspace.Terrain
	local light = Instance.new("PointLight")
	light.Color = bolt.Color
	light.Range = 40
	light.Brightness = bolt.FlashBrightness
	light.Parent = flashAttachment
	HitFeelController.emitDebris(target, bolt.Color, 30, 2)
	HitFeelController.playSound(Config.Sounds.FeverBurst, target, bolt.ThunderPitch, bolt.ThunderVolume)
	HitFeelController.cameraShake(Config.HitFeel.CameraShake.Magnitude * bolt.Shake * (if isMine then 1 else 0.5), Config.HitFeel.CameraShake.Duration * 3)
	-- 깜빡이다 사라진다
	for _, segment in parts do
		TweenService:Create(segment, TweenInfo.new(bolt.Duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Size = segment.Size * Vector3.new(0.3, 0.3, 1) }):Play()
	end
	TweenService:Create(light, TweenInfo.new(bolt.Duration * 1.5), { Brightness = 0 }):Play()
	task.delay(bolt.Duration * 1.6, function()
		for _, segment in parts do
			segment:Destroy()
		end
		flashAttachment:Destroy()
	end)
end

-- 다른 연출(전투)에서도 쓰도록 공개한다
HitFeelController.tierImpact = tierImpact

-- 다 모은 강타가 맞았을 때: 큰 흰 충격파·불꽃·반짝이와 큰 화면 흔들림
function HitFeelController.chargedImpact(target: Model?, hitPosition: Vector3, isMine: boolean)
	local impact = Config.Charge.Impact
	tierImpact(target, hitPosition, impact.Color, 1, "Perfect", Enum.Material.Neon, { [1] = impact })
	HitFeelController.emitDebris(hitPosition, impact.Color, 25, 1.8)
	HitFeelController.playSound(Config.Sounds.FeverBurst, hitPosition, 1.4, 0.5)
	if isMine then
		local shake = Config.HitFeel.CameraShake
		HitFeelController.cameraShake(shake.Magnitude * impact.Shake, shake.Duration * 1.6)
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
	pickaxeTier: number?,
	special: string?
)
	local isMine = attackerUserId == localPlayer.UserId
	if special == "Lightning" then
		playLightning(hitPosition, isMine)
	elseif special == "Charged" then
		HitFeelController.chargedImpact(rock, hitPosition, isMine)
	elseif special == "Blocked" then
		blockedEffect(rock, hitPosition, isMine)
		return
	end
	local def = if rock then TargetController.getDef(rock) else nil
	local isTree = def ~= nil and def.Kind == "Tree"
	local color = if def then def.Color else DEFAULT_COLOR
	local material = if isTree then Enum.Material.Wood else Enum.Material.Slate
	local debrisCount = (Config.HitFeel.DebrisCount :: any)[judgment] or Config.HitFeel.DebrisCount.Normal
	local treeFeel = Config.HitFeel.Tree

	if rock and rock.Parent then
		local shakeScale = if judgment == "Perfect" then 1.6 else 1
		HitFeelController.shakeRock(rock, if isTree then shakeScale * treeFeel.ShakeScale else shakeScale)
	end
	if isTree then
		-- 나무는 돌가루 대신 맞은 자리에서 잎이 흩날린다
		leafBurst(hitPosition, (def :: OreDefs.OreDef).LeafColor or DEFAULT_LEAF_COLOR, math.ceil(debrisCount / 3), 0.8)
	else
		HitFeelController.emitDebris(hitPosition, color, debrisCount, if judgment == "Perfect" then 1.3 else 1)
	end

	local pitch = random:NextNumber(Config.HitFeel.PitchRange.Min, Config.HitFeel.PitchRange.Max)
	if isTree then
		-- 도끼 "퍽": 판정이 좋을수록 조금 높고 크게. 잎이 떨어진다
		local chopPitch = pitch * (if judgment == "Perfect" then 1.15 elseif judgment == "Nice" then 1.07 else 1)
		HitFeelController.playSound(Config.Sounds.WoodChop, hitPosition, chopPitch, treeFeel.ChopVolume * (if judgment == "Perfect" then 1.2 else 1))
		if rock then
			-- 좋은 도끼일수록 잎이 더 많이 떨어진다
			local axeEffect = Config.HitFeel.AxeTierEffects[pickaxeTier or 1]
			local leafCount = math.round(treeFeel.LeafCount * (if axeEffect then axeEffect.Leaves else 1))
			dropLeaves(rock, rock:GetPivot().Position, (def :: OreDefs.OreDef).LeafColor or DEFAULT_LEAF_COLOR, leafCount)
		end
	else
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
	end

	local tier = pickaxeTier or 1
	local tierTable = if isTree then Config.HitFeel.AxeTierEffects else Config.HitFeel.TierEffects
	tierImpact(rock, hitPosition, color, tier, judgment, material, tierTable)

	-- 나무의 마지막 일격: 원본이 지워지기 전에 쓰러뜨릴 복제본을 만들어 둔다
	local hp = if rock then rock:GetAttribute("Hp") else nil
	if isTree and rock and rock.Parent and typeof(hp) == "number" and hp <= 0 then
		prepareFall(rock, hitPosition)
	end

	if isMine then
		SwingAnimation.freeze((Config.HitFeel.HitStop :: any)[judgment] or Config.HitFeel.HitStop.Normal)
		local shake = Config.HitFeel.CameraShake
		local tierEffect = tierTable[tier]
		local tierShake = if tierEffect then tierEffect.Shake else 1
		HitFeelController.cameraShake(shake.Magnitude * tierShake * (if judgment == "Perfect" then shake.PerfectMultiplier else 1), shake.Duration)
	end
	if rock and (judgment == "Perfect" or judgment == "Nice") then
		RockHUD.showJudgment(rock, judgment)
		HitFeelController.playSound(Config.Sounds.JudgmentPop, hitPosition, if judgment == "Perfect" then 1.25 else 1, 0.5)
	end
end

-- 서버의 RockBroken: 바위가 깨졌다 (rewards는 UserId 문자열 → 개수, feverMultiplier는 피버 배수, 피버가 아니면 1)
local function onRockBroken(position: Vector3, oreType: string, rewards: { [string]: number }, feverMultiplier: number)
	local color = oreColor(oreType)
	local def = OreDefs[oreType]
	local treeDef = if def and def.Kind == "Tree" then def else nil
	-- 나무는 기준점이 밑동이라 줄기 타격 높이에서 터뜨린다
	local burstPosition = if treeDef then position + Vector3.new(0, treeDef.HitHeight or 2.5, 0) else position
	if not treeDef then
		HitFeelController.emitDebris(burstPosition, color, Config.HitFeel.DebrisCount.Break, 1.6)
	end
	if treeDef then
		HitFeelController.playSound(Config.Sounds.TreeBreak, position, random:NextNumber(0.95, 1.05), 0.9)
		dropLeaves(nil, position, treeDef.LeafColor or DEFAULT_LEAF_COLOR, Config.HitFeel.Tree.BreakLeafCount)
		-- 이 자리 나무의 복제본이 있으면 쓰러뜨린다
		for index, entry in pendingFalls do
			if (entry.Position - position).Magnitude < 1 then
				table.remove(pendingFalls, index)
				playFall(entry)
				break
			end
		end
	else
		HitFeelController.playSound(Config.Sounds.RockBreak, position, random:NextNumber(0.95, 1.05), 0.8)
	end

	local amount = rewards[tostring(localPlayer.UserId)]
	if amount and amount > 0 then
		HitFeelController.cameraShake(Config.HitFeel.CameraShake.Magnitude * 2, Config.HitFeel.CameraShake.Duration * 2)
		-- 조각이 땅에 떨어졌다가 빨려 들어오면 "+7 구리" 획득 알림
		HitFeelController.spawnPickups(burstPosition, color, amount, if treeDef then Enum.Material.Wood else Enum.Material.Slate, if treeDef then "Log" else "Cube", function()
			PickupFeed.show(oreType, amount)
		end)
		local def = OreDefs[oreType]
		RockHUD.showReward(burstPosition, amount, if def then def.DisplayName else oreType, feverMultiplier)
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
