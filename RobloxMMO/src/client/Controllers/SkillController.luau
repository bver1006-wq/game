--!strict
-- 구르기·무기별 스킬 (클라이언트, 2026-10-09 사용자 요청)
--   구르기: PC Q키 / 모바일 공격 버튼 왼쪽 위 버튼 / 패드 X. 짧게 휙 굴러 피한다 (마나 조금)
--     움직임은 여기서 바로 한다 (캐릭터 물리는 내 것). 서버(SkillService)는 쿨다운·마나를 보고 잠깐 무적을 준다
--   스킬 칸: PC F키 / 모바일 공격 버튼 위 버튼 / 패드 Y. 아무것도 안 들면 빈 칸, 들고 있는 것에 맞는 스킬 하나가 된다
--     칼 = 🛡 방패 막기 / 방망이 = 💥 내려찍기(기절) / 활 = 🏹 연사 / 곡괭이·도끼 = ⚒ 강하게 찍기
--     요청만 보내고, 서버가 허락하면 SkillEffect가 와서 연출·쿨다운이 시작된다 (마나·쿨다운·거리·주인·장비 벽은 서버가 확인)
--   E키는 상점·광산 ProximityPrompt가 쓰므로 스킬은 F키
--   버튼: 모바일은 공격 버튼 둘레(MobileControls.ringPosition), PC는 오른쪽 아래에 작게 + [Q] [F] 표시
--   쿨다운은 버튼 위 어두운 덮개가 아래로 줄어들며 남은 초를 보여 준다

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local PickaxeDefs = require(ReplicatedStorage.Shared.PickaxeDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CombatController = require(script.Parent.CombatController)
local FeverController = require(script.Parent.FeverController)
local HitFeelController = require(script.Parent.HitFeelController)
local InputController = require(script.Parent.InputController)
local MobileControls = require(script.Parent.MobileControls)
local NotifyController = require(script.Parent.NotifyController)
local SwingAnimation = require(script.Parent.SwingAnimation)
local TargetController = require(script.Parent.TargetController)
local UiKit = require(script.Parent.UiKit)

local ROLL_KEYS: { [Enum.KeyCode]: boolean } = { [Enum.KeyCode.Q] = true, [Enum.KeyCode.ButtonX] = true }
local SKILL_KEYS: { [Enum.KeyCode]: boolean } = { [Enum.KeyCode.F] = true, [Enum.KeyCode.ButtonY] = true }

local localPlayer = Players.LocalPlayer

local SkillController = {}

type SkillButton = {
	Button: TextButton,
	Icon: TextLabel,
	Shade: Frame, -- 쿨다운 덮개 (남은 비율만큼 높이)
	Count: TextLabel, -- 남은 초
	Name: TextLabel?,
	Stroke: UIStroke,
}

local rollRemote: RemoteEvent
local skillRemote: RemoteEvent
local effectsFolder: Folder
local rollButton: SkillButton
local skillButton: SkillButton

local rollReadyAt = 0 -- 구르기를 다시 쓸 수 있는 시각 (os.clock, 서버와 같은 쿨다운으로 예상)
local skillReadyAt: { [string]: number } = {} -- 스킬 Id → 다시 쓸 수 있는 시각 (서버가 허락한 순간부터)
local skillPendingUntil = 0 -- 요청을 보내고 답을 기다리는 중 (연타로 여러 번 보내지 않게)
local lastNotice = -math.huge
local rollingCharacters: { [Model]: boolean } = {} -- 구르는 모습을 보여 주는 중인 캐릭터
local dashing = false

-- 도구 종류 → 스킬 Id (Config.Skills의 Kind 목록으로 만든다. 서버 SkillService와 같은 방법)
local skillByKind: { [string]: string } = {}
for id, def in Config.Skills :: any do
	if typeof(def) == "table" and typeof(def.Kind) == "table" then
		for _, kind in def.Kind do
			skillByKind[kind] = id
		end
	end
end

-- 스킬 정의 (Config.Skills 안의 표)
local function skillDef(id: string): any
	return (Config.Skills :: any)[id]
end

-- 지금 들고 있는 도구 정의
local function heldDef(): PickaxeDefs.PickaxeDef?
	local character = localPlayer.Character
	local tool = character and character:FindFirstChildWhichIsA("Tool")
	local id = tool and tool:GetAttribute("PickaxeId")
	return if typeof(id) == "string" then PickaxeDefs[id] else nil
end

-- 들고 있는 것에 맞는 스킬 Id (아무것도 안 들었으면 nil)
local function currentSkill(): string?
	local def = heldDef()
	return if def then skillByKind[def.Kind] else nil
end

-- 지금 마나 (서버가 정한 플레이어 속성)
local function mana(): number
	local value = localPlayer:GetAttribute("Mana")
	return if typeof(value) == "number" then value else 0
end

-- 알림 (연타해도 1초에 한 번만)
local function notice(message: string)
	local now = os.clock()
	if now - lastNotice < 1 then
		return
	end
	lastNotice = now
	NotifyController.show(message, "bad")
end

-- 캐릭터의 몸통 뿌리 관절 (R15 LowerTorso.Root / R6 HumanoidRootPart.RootJoint)
local function rootJoint(character: Model): Motor6D?
	local lower = character:FindFirstChild("LowerTorso")
	local joint = lower and lower:FindFirstChild("Root")
	if not joint then
		local root = character:FindFirstChild("HumanoidRootPart")
		joint = root and root:FindFirstChild("RootJoint")
	end
	return if joint and joint:IsA("Motor6D") then joint else nil
end

-- 구르는 모습: 몸통을 앞으로 한 바퀴 돌리며 살짝 웅크린다 (관절 C0만 이 화면에서 바꾼다. 누구 캐릭터든 된다)
-- 흙먼지 + "휙" 소리
local function playRollVisual(character: Model, position: Vector3)
	local roll = Config.Roll
	HitFeelController.playSound(roll.Sound, position, 1.6, 0.55)
	HitFeelController.emitDebris(position - Vector3.new(0, 2.5, 0), Color3.fromRGB(170, 150, 120), 8, 0.6)
	if rollingCharacters[character] then
		return
	end
	local joint = rootJoint(character)
	if not joint then
		return
	end
	rollingCharacters[character] = true
	local base = joint.C0
	local duration = roll.Duration * 1.15
	local start = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - start) / duration, 0, 1)
		-- 처음과 끝은 천천히, 가운데는 빠르게 도는 곡선
		local eased = if t < 0.5 then 2 * t * t else 1 - (-2 * t + 2) ^ 2 / 2
		if joint.Parent then
			-- 뿌리 부품 기준으로 앞(-Z) 쪽으로 한 바퀴 (X축 음의 방향 회전 = 머리가 앞으로)
			joint.C0 = CFrame.new(0, -roll.Crouch * math.sin(math.pi * t), 0) * CFrame.Angles(-math.pi * 2 * eased, 0, 0) * base
		end
		if t >= 1 or not joint.Parent then
			connection:Disconnect()
			if joint.Parent then
				joint.C0 = base
			end
			rollingCharacters[character] = nil
		end
	end)
	-- 연결이 끊긴 채로 남지 않게 (캐릭터가 사라지는 경우 등)
	task.delay(duration + 1, function()
		if connection.Connected then
			connection:Disconnect()
			if joint.Parent then
				joint.C0 = base
			end
			rollingCharacters[character] = nil
		end
	end)
end

-- 이 방향으로 얼마나 굴러갈 수 있는지 (벽이 있으면 그 앞까지)
local function rollDistance(character: Model, root: BasePart, direction: Vector3): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { character, effectsFolder }
	for _, name in { "ClientEffects", "Mobs", "Ores" } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(exclude, folder)
		end
	end
	params.FilterDescendantsInstances = exclude
	local distance = Config.Roll.Distance
	-- 허리 높이와 발목 높이 두 줄로 벽을 본다 (낮은 턱은 물리가 알아서 넘는다)
	for _, height in { 0, -1.5 } do
		local result = Workspace:Raycast(root.Position + Vector3.new(0, height, 0), direction * Config.Roll.Distance, params)
		if result and result.Instance.CanCollide then
			distance = math.min(distance, math.max(result.Distance - 1.5, 0))
		end
	end
	return distance
end

-- 구르기: 이 화면에서 바로 굴러간다 (서버에는 방향만 알린다)
local function roll()
	if dashing or FeverController.isActive() then
		return
	end
	local now = os.clock()
	if now < rollReadyAt then
		return
	end
	local config = Config.Roll
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 or humanoid.Sit then
		return
	end
	if mana() < config.ManaCost then
		notice("마나가 모자라요!")
		return
	end
	-- 방향: 움직이는 쪽, 가만히 있으면 바라보는 쪽
	local direction = humanoid.MoveDirection * Vector3.new(1, 0, 1)
	if direction.Magnitude < 0.1 then
		direction = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	end
	if direction.Magnitude < 0.01 then
		return
	end
	direction = direction.Unit
	rollReadyAt = now + config.Cooldown
	rollRemote:FireServer(direction)

	-- 굴러가는 방향을 보고, 수평 속도만 정해 준다 (위아래는 중력 그대로)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + direction)
	local distance = rollDistance(character, root, direction)
	local speed = config.Distance / config.Duration
	local duration = distance / speed
	playRollVisual(character, root.Position)
	if duration <= 0.02 then
		return -- 바로 앞이 벽이면 제자리에서 구르기만
	end
	dashing = true
	local autoRotate = humanoid.AutoRotate
	humanoid.AutoRotate = false
	local attachment = Instance.new("Attachment")
	attachment.Name = "RollAttachment"
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.xAxis
	velocity.SecondaryTangentAxis = Vector3.zAxis
	velocity.PlaneVelocity = Vector2.new(direction.X * speed, direction.Z * speed)
	velocity.MaxForce = root.AssemblyMass * 4000
	velocity.Parent = root
	task.delay(duration, function()
		velocity:Destroy()
		attachment:Destroy()
		if humanoid.Parent then
			humanoid.AutoRotate = autoRotate
		end
		-- 구르기가 끝나면 미끄러지지 않게 수평 속도를 걷는 속도 이하로
		if root.Parent then
			local v = root.AssemblyLinearVelocity
			local flat = Vector3.new(v.X, 0, v.Z)
			if flat.Magnitude > humanoid.WalkSpeed then
				flat = flat.Unit * humanoid.WalkSpeed
				root.AssemblyLinearVelocity = Vector3.new(flat.X, v.Y, flat.Z)
			end
		end
		dashing = false
	end)
end

-- 스킬 쓰기: 미리 볼 수 있는 것(마나·대상·화살)만 여기서 보고 서버에 요청한다
local function useSkill()
	if FeverController.isActive() then
		return
	end
	local id = currentSkill()
	local def = id and skillDef(id)
	local tool = heldDef()
	if not id or not def or not tool then
		notice("도구나 무기를 들면 스킬을 쓸 수 있어요!")
		return
	end
	local now = os.clock()
	if now < (skillReadyAt[id] or 0) or now < skillPendingUntil then
		return
	end
	if mana() < def.ManaCost then
		notice("마나가 모자라요!")
		return
	end
	local target: Model? = nil
	if id == "RapidFire" then
		local arrows = localPlayer:GetAttribute("Arrows")
		if typeof(arrows) ~= "number" or arrows <= 0 then
			notice("화살이 없어요!")
			return
		end
		local weapon = Config.Weapons[tool.Id]
		target = CombatController.findTarget("Bow", if weapon then weapon.Range else 40)
		if not target then
			notice("쏠 몹이 없어요!")
			return
		end
	elseif id == "PowerStrike" then
		target = TargetController.getNearestRock(Config.Mining.AutoAimRange)
		if not target then
			notice(if tool.Kind == "Axe" then "가까이에 나무가 없어요!" else "가까이에 바위가 없어요!")
			return
		end
	end
	skillPendingUntil = now + 0.6
	skillRemote:FireServer(target)
end

-- 캐릭터 둘레에 빛나는 방패 막 (Duration초, 누구 캐릭터든)
local function showShield(character: Model, duration: number)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local def = Config.Skills.Block
	local bubble = Instance.new("Part")
	bubble.Name = "BlockShield"
	bubble.Shape = Enum.PartType.Ball
	bubble.Size = Vector3.one * 2
	bubble.Material = Enum.Material.ForceField
	bubble.Color = def.Color
	bubble.Transparency = 0
	bubble.CanCollide = false
	bubble.CanQuery = false
	bubble.CanTouch = false
	bubble.CastShadow = false
	bubble.Massless = true
	bubble.CFrame = root.CFrame
	bubble.Parent = effectsFolder
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = bubble
	weld.Parent = bubble
	-- 퐁 하고 커졌다가, 끝나기 직전 사라진다
	TweenService:Create(bubble, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.one * 7.5 }):Play()
	task.delay(math.max(duration - 0.2, 0), function()
		if bubble.Parent then
			TweenService:Create(bubble, TweenInfo.new(0.2), { Transparency = 1, Size = Vector3.one * 8.5 }):Play()
		end
	end)
	task.delay(duration + 0.1, function()
		bubble:Destroy()
	end)
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		HitFeelController.popText(head.Position + Vector3.new(0, 1.5, 0), "🛡 막기!", def.Color)
	end
end

-- 기절한 몹 머리 위에 빙글빙글 도는 별 (seconds초)
local function showStars(mob: Model, seconds: number)
	local anchor = mob.PrimaryPart or mob:FindFirstChild("Root") or mob:FindFirstChildWhichIsA("BasePart")
	if not anchor or not anchor:IsA("BasePart") then
		return
	end
	local top = mob:GetPivot().Position.Y + mob:GetExtentsSize().Y + 0.6
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(3, 1.2)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.StudsOffsetWorldSpace = Vector3.new(0, top - anchor.Position.Y, 0)
	billboard.Adornee = anchor
	billboard.Parent = effectsFolder
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = "💫 ⭐ 💫"
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 230, 120)
	label.Parent = billboard
	local start = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - start
		if elapsed >= seconds or not anchor.Parent then
			connection:Disconnect()
			billboard:Destroy()
			return
		end
		label.Rotation = math.sin(elapsed * 9) * 18 -- 어질어질 흔들림
	end)
end

-- 땅을 쿵 내려찍은 충격파 고리 + 흙먼지
local function showSlam(position: Vector3, isMine: boolean)
	local def = Config.Skills.Slam
	local ground = position - Vector3.new(0, 2.6, 0)
	local ring = Instance.new("Part")
	ring.Name = "SlamRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.25, 2, 2)
	ring.Material = Enum.Material.Neon
	ring.Color = def.Color
	ring.Transparency = 0.2
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.CFrame = CFrame.new(ground) * CFrame.Angles(0, 0, math.pi / 2) -- 원통 축을 위로
	ring.Parent = effectsFolder
	TweenService:Create(ring, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.25, def.Radius * 2, def.Radius * 2),
		Transparency = 1,
	}):Play()
	task.delay(0.45, function()
		ring:Destroy()
	end)
	HitFeelController.emitDebris(ground, Color3.fromRGB(150, 125, 95), 18, 1.3)
	for index = 1, 8 do
		local angle = index / 8 * math.pi * 2
		HitFeelController.emitDebris(ground + Vector3.new(math.cos(angle), 0, math.sin(angle)) * def.Radius * 0.7, Color3.fromRGB(170, 150, 120), 4, 0.8)
	end
	HitFeelController.playSound(Config.Skills.SlamSound, ground, 0.5, 1)
	HitFeelController.playSound(Config.Sounds.FeverBurst, ground, 0.8, 0.45)
	local shake = Config.HitFeel.CameraShake
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if isMine then
		HitFeelController.cameraShake(shake.Magnitude * 3, shake.Duration * 2)
	elseif root and root:IsA("BasePart") and (root.Position - position).Magnitude < 30 then
		HitFeelController.cameraShake(shake.Magnitude * 1.5, shake.Duration * 1.5)
	end
end

-- 도구에 잠깐 빛 테두리 (강하게 찍기가 걸린 동안)
local function glowTool(character: Model, color: Color3, seconds: number)
	local tool = character:FindFirstChildWhichIsA("Tool")
	if not tool then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "SkillGlow"
	highlight.FillColor = color
	highlight.FillTransparency = 0.4
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = tool
	highlight.Parent = effectsFolder
	task.delay(seconds, function()
		highlight:Destroy()
	end)
end

-- 서버의 SkillEffect: 누군가 구르기·스킬을 썼다. 내 것이면 쿨다운 시작
local function onSkillEffect(kind: string, userId: number, position: Vector3, data: any)
	local isMine = userId == localPlayer.UserId
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	local def = skillDef(kind)
	if isMine and kind ~= "Roll" and typeof(def) == "table" then
		skillReadyAt[kind] = os.clock() + def.Cooldown
		skillPendingUntil = 0
	end

	if kind == "Roll" then
		if character and not isMine then
			playRollVisual(character, position)
		end
	elseif kind == "Block" then
		HitFeelController.playSound(Config.Skills.ShieldSound, position, 1.3, 0.6)
		if character then
			showShield(character, if typeof(data) == "number" then data else def.Duration)
		end
	elseif kind == "Slam" then
		if isMine then
			SwingAnimation.play()
		end
		showSlam(position, isMine)
		if typeof(data) == "table" then
			for _, mob in data do
				if typeof(mob) == "Instance" and mob:IsA("Model") then
					showStars(mob, def.StunTime)
				end
			end
		end
	elseif kind == "RapidFire" then
		-- 화살은 서버 CombatEffect(fromSkill)로 한 발씩 날아간다. 여기서는 "휘익" 소리를 겹친다
		for index = 1, def.Arrows do
			task.delay((index - 1) * def.Interval, function()
				HitFeelController.playSound(Config.Sounds.BowShoot, position, 1.25, 0.6)
			end)
		end
		if isMine and typeof(data) == "Instance" and data:IsA("Model") then
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local target = (data :: Model):GetPivot().Position
				local flat = Vector3.new(target.X, root.Position.Y, target.Z)
				if (flat - root.Position).Magnitude > 0.1 then
					root.CFrame = CFrame.lookAt(root.Position, flat)
				end
			end
		end
	elseif kind == "PowerStrike" then
		if character then
			glowTool(character, def.Color, 0.8)
		end
		if isMine then
			HitFeelController.playSound(Config.Sounds.ChargeUp, nil, 1.6, 0.5)
			InputController.skillSwing() -- 걸리자마자 한 번 휘두른다 (못 휘두르면 ArmTime 안의 다음 한 번)
		end
	end
end

-- 둥근 버튼 하나 (아이콘 + 쿨다운 덮개 + 남은 초 + 키 표시)
local function makeButton(parent: Instance, size: number, position: UDim2, icon: string, keyHint: string?, showName: boolean): SkillButton
	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = position
	button.Size = UDim2.fromOffset(size, size)
	button.BackgroundColor3 = Color3.fromRGB(45, 55, 80)
	button.BackgroundTransparency = 0.2
	button.AutoButtonColor = false
	button.Text = ""
	button.Parent = parent
	UiKit.corner(button, size / 2)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button

	-- 쿨다운 덮개: 둥근 모양 안에서만 보이게 CanvasGroup으로 자른다
	local clip = Instance.new("CanvasGroup")
	clip.Size = UDim2.fromScale(1, 1)
	clip.BackgroundTransparency = 1
	clip.Parent = button
	UiKit.corner(clip, size / 2)
	local shade = Instance.new("Frame")
	shade.AnchorPoint = Vector2.new(0, 1)
	shade.Position = UDim2.fromScale(0, 1)
	shade.Size = UDim2.fromScale(1, 0)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.4
	shade.BorderSizePixel = 0
	shade.Parent = clip

	local iconLabel = Instance.new("TextLabel")
	iconLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	iconLabel.Position = UDim2.fromScale(0.5, 0.5)
	iconLabel.Size = UDim2.fromScale(0.62, 0.62)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Font = Enum.Font.FredokaOne
	iconLabel.Text = icon
	iconLabel.TextScaled = true
	iconLabel.TextColor3 = Color3.new(1, 1, 1)
	iconLabel.ZIndex = 2
	iconLabel.Parent = button

	local count = Instance.new("TextLabel")
	count.AnchorPoint = Vector2.new(0.5, 0.5)
	count.Position = UDim2.fromScale(0.5, 0.5)
	count.Size = UDim2.fromScale(0.5, 0.5)
	count.BackgroundTransparency = 1
	count.Font = Enum.Font.FredokaOne
	count.Text = ""
	count.TextScaled = true
	count.TextColor3 = Color3.new(1, 1, 1)
	count.ZIndex = 3
	count.Parent = button
	local countStroke = Instance.new("UIStroke")
	countStroke.Thickness = 2
	countStroke.Parent = count

	if keyHint then
		local key = Instance.new("TextLabel")
		key.AnchorPoint = Vector2.new(0, 0)
		key.Position = UDim2.fromOffset(-4, -4)
		key.Size = UDim2.fromOffset(22, 22)
		key.BackgroundColor3 = UiKit.Colors.Panel
		key.Font = Enum.Font.FredokaOne
		key.Text = keyHint
		key.TextScaled = true
		key.TextColor3 = UiKit.Colors.Gold
		key.ZIndex = 4
		key.Parent = button
		UiKit.corner(key, 6)
	end

	local name: TextLabel? = nil
	if showName then
		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.new(0.5, 0, 0, -2)
		label.Size = UDim2.fromOffset(size * 1.6, 18)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.Text = ""
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.ZIndex = 4
		label.Parent = button
		local labelStroke = Instance.new("UIStroke")
		labelStroke.Thickness = 1.5
		labelStroke.Parent = label
		name = label
	end
	return { Button = button, Icon = iconLabel, Shade = shade, Count = count, Name = name, Stroke = stroke }
end

-- 누르면 바로 (손가락·마우스 둘 다). 모바일은 누르는 순간 반응해야 덜 답답하다
local function onPress(entry: SkillButton, action: () -> ())
	entry.Button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			action()
		end
	end)
end

-- 버튼 하나의 쿨다운·흐림 표시
local function paint(entry: SkillButton, remaining: number, total: number, usable: boolean)
	local ratio = if total > 0 then math.clamp(remaining / total, 0, 1) else 0
	entry.Shade.Size = UDim2.fromScale(1, ratio)
	entry.Count.Text = if remaining > 0.05 then (if remaining >= 1 then tostring(math.ceil(remaining)) else string.format("%.1f", remaining)) else ""
	local dim = not usable or remaining > 0
	entry.Icon.TextTransparency = if dim then 0.45 else 0
	entry.Button.BackgroundTransparency = if usable then 0.2 else 0.55
	entry.Stroke.Transparency = if usable and remaining <= 0 then 0.3 else 0.7
end

-- 매 프레임: 스킬 칸 모양(들고 있는 것에 맞게)과 쿨다운
local function update()
	local now = os.clock()
	local playing = not FeverController.isActive()
	-- 구르기
	paint(rollButton, math.max(rollReadyAt - now, 0), Config.Roll.Cooldown, playing and mana() >= Config.Roll.ManaCost)
	-- 스킬 칸: 아무것도 안 들면 빈 칸
	local id = currentSkill()
	local def = id and skillDef(id)
	if id and def then
		skillButton.Icon.Text = def.Icon
		if skillButton.Name then
			skillButton.Name.Text = def.Name
		end
		skillButton.Button.BackgroundColor3 = def.Color:Lerp(Color3.fromRGB(30, 30, 40), 0.55)
		paint(skillButton, math.max((skillReadyAt[id] or 0) - now, 0), def.Cooldown, playing and mana() >= def.ManaCost)
	else
		skillButton.Icon.Text = ""
		if skillButton.Name then
			skillButton.Name.Text = ""
		end
		skillButton.Button.BackgroundColor3 = Color3.fromRGB(45, 55, 80)
		paint(skillButton, 0, 1, false)
	end
end

-- 버튼 만들기: 모바일은 공격 버튼 둘레, PC는 오른쪽 아래
local function buildButtons()
	local gui = Instance.new("ScreenGui")
	gui.Name = "SkillButtons"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	local layout = Config.MobileControls
	-- MobileControls와 같은 기준 (터치 화면이면 공격 버튼 둘레)
	if UserInputService.TouchEnabled then
		rollButton = makeButton(gui, layout.SmallSize, MobileControls.ringPosition(layout.RollAngle), "🌀", nil, false)
		skillButton = makeButton(gui, layout.SmallSize, MobileControls.ringPosition(layout.SkillAngle), "", nil, true)
	else
		local size = layout.PcSize
		local y = -(layout.PcMargin + size / 2)
		skillButton = makeButton(gui, size, UDim2.new(1, -(layout.PcMargin + size / 2), 1, y), "", "F", true)
		rollButton = makeButton(gui, size, UDim2.new(1, -(layout.PcMargin + size * 1.5 + 14), 1, y), "🌀", "Q", false)
	end
	onPress(rollButton, roll)
	onPress(skillButton, useSkill)
end

-- 클라이언트 시작 시 한 번 호출 (InputController·MobileControls 다음)
function SkillController.init()
	rollRemote = Remotes.get(Remotes.Names.RollRequest)
	skillRemote = Remotes.get(Remotes.Names.SkillRequest)
	local folder = Instance.new("Folder")
	folder.Name = "SkillEffects"
	folder.Parent = Workspace
	effectsFolder = folder

	buildButtons()
	Remotes.get(Remotes.Names.SkillEffect).OnClientEvent:Connect(onSkillEffect)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if ROLL_KEYS[input.KeyCode] then
			roll()
		elseif SKILL_KEYS[input.KeyCode] then
			useSkill()
		end
	end)
	RunService.RenderStepped:Connect(update)
	localPlayer.CharacterAdded:Connect(function()
		dashing = false
	end)
end

return SkillController
