--!strict
-- 전투 (클라이언트): 무기 공격 입력, 몹 자동 조준, 타격·처치 연출, 몹 체력바.
-- 판정·데미지·보상은 서버(CombatService·MobService)가 하고, 여기서는 요청 보내기와 보여주기만 한다.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local ItemDefs = require(ReplicatedStorage.Shared.ItemDefs)
local MobDefs = require(ReplicatedStorage.Shared.MobDefs)
local TierDefs = require(ReplicatedStorage.Shared.TierDefs)
local PickaxeDefs = require(ReplicatedStorage.Shared.PickaxeDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local HitFeelController = require(script.Parent.HitFeelController)
local NotifyController = require(script.Parent.NotifyController)
local PickupFeed = require(script.Parent.PickupFeed)
local RockHUD = require(script.Parent.RockHUD)
local SwingAnimation = require(script.Parent.SwingAnimation)
local TargetController = require(script.Parent.TargetController)

local MOB_TAG = "Mob"
local WEAPON_KINDS: { [string]: boolean } = { Sword = true, Bow = true, Club = true }

local localPlayer = Players.LocalPlayer

local CombatController = {}

local attackRemote: RemoteEvent
local effectsFolder: Folder
local hudFolder: Folder
local lastAttackClock = -math.huge
local lastArrowNotice = -math.huge
local hpBars: { [Model]: { Gui: BillboardGui, Fill: Frame, Range: number } } = {}
local hurtFrame: Frame
local inkFrame: Frame -- 낙지 먹물을 맞으면 화면이 잠깐 어두워진다 (2026-10-09)

-- 이 도구가 무기인지
function CombatController.isWeapon(def: PickaxeDefs.PickaxeDef): boolean
	return WEAPON_KINDS[def.Kind] == true
end

-- 몹 정의 (모르는 몹이면 nil)
local function mobDef(mob: Instance): MobDefs.MobDef?
	local mobType = mob:GetAttribute("MobType")
	return if typeof(mobType) == "string" then MobDefs[mobType] else nil
end

-- 사거리 안에서 가장 가까운 살아 있는 몹 (남이 사냥 중인 몹은 뺀다)
local function nearestMob(range: number): Model?
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local best: Model? = nil
	local bestDistance = math.huge
	for _, mob in CollectionService:GetTagged(MOB_TAG) do
		local hp = mob:GetAttribute("Hp")
		if mob:IsA("Model") and mob:IsDescendantOf(Workspace) and typeof(hp) == "number" and hp > 0 and not TargetController.isOthers(mob) then
			local size = mob:GetExtentsSize()
			local offset = mob:GetPivot().Position - root.Position
			local flat = offset * Vector3.new(1, 0, 1)
			local distance = flat.Magnitude - math.max(size.X, size.Z) / 2
			-- 물 속 몹은 위아래로 너무 멀면 못 친다 (서버 CombatService와 같은 기준, 2026-10-09)
			local def = mobDef(mob)
			local reachable = not (def and def.Habitat == "Water") or math.abs(offset.Y + size.Y / 2) <= range + size.Y / 2
			if reachable and distance <= range and distance < bestDistance then
				best, bestDistance = mob, distance
			end
		end
	end
	return best
end

-- 활: 화면 가운데(카메라가 보는 쪽) 가까이 있는 몹을 먼저 노린다. 없으면 가장 가까운 몹
local function bowTarget(range: number): Model?
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = Workspace.CurrentCamera
	if not root or not root:IsA("BasePart") or not camera then
		return nil
	end
	local look = camera.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.zAxis
	local maxAngle = math.rad(Config.Combat.BowAimAngle)
	local best: Model? = nil
	local bestScore = math.huge
	for _, mob in CollectionService:GetTagged(MOB_TAG) do
		local hp = mob:GetAttribute("Hp")
		if mob:IsA("Model") and mob:IsDescendantOf(Workspace) and typeof(hp) == "number" and hp > 0 and not TargetController.isOthers(mob) then
			local flat = (mob:GetPivot().Position - root.Position) * Vector3.new(1, 0, 1)
			local distance = flat.Magnitude
			if distance <= range and distance > 0.1 then
				local angle = math.acos(math.clamp(flat.Unit:Dot(look), -1, 1))
				if angle <= maxAngle and distance < bestScore then
					best, bestScore = mob, distance
				end
			end
		end
	end
	return best or nearestMob(range)
end

-- 스킬이 노릴 몹 (SkillController): 활은 화면 가운데 쪽을 먼저, 나머지는 가장 가까운 몹. 남의 몹은 뺀다
function CombatController.findTarget(kind: string, range: number): Model?
	return if kind == "Bow" then bowTarget(range) else nearestMob(range)
end

-- 캐릭터가 대상을 바라보게 돌린다
local function face(target: Vector3)
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local flatTarget = Vector3.new(target.X, root.Position.Y, target.Z)
	if (flatTarget - root.Position).Magnitude > 0.1 then
		root.CFrame = CFrame.lookAt(root.Position, flatTarget)
	end
end

-- 화살이 날아간다 (도착하면 onArrive)
local function shootArrow(from: Vector3, to: Vector3, tier: number, onArrive: () -> ())
	local effect = TierDefs.pick(Config.Combat.TierEffects :: { [number]: any }, tier)
	local arrow = Instance.new("Part")
	arrow.Size = Vector3.new(0.12, 0.12, 2)
	arrow.Material = if tier >= 4 then Enum.Material.Neon else Enum.Material.Wood
	arrow.Color = if tier >= 2 and effect then effect.Color else Color3.fromRGB(150, 110, 70)
	arrow.Anchored = true
	arrow.CanCollide = false
	arrow.CanQuery = false
	arrow.CanTouch = false
	arrow.CastShadow = false
	arrow.CFrame = CFrame.lookAt(from, to)
	arrow.Parent = effectsFolder
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.1, 1)
	a0.Parent = arrow
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.1, 1)
	a1.Parent = arrow
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(if effect then effect.Color else Color3.new(1, 1, 1))
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.Lifetime = 0.15
	trail.LightEmission = 0.7
	trail.Parent = arrow
	local travel = math.max((to - from).Magnitude / Config.Combat.ArrowSpeed, 0.05)
	TweenService:Create(arrow, TweenInfo.new(travel, Enum.EasingStyle.Linear), { CFrame = CFrame.lookAt(to, to + (to - from).Unit) }):Play()
	task.delay(travel, function()
		arrow:Destroy()
		onArrive()
	end)
end

-- 무기로 한 번 공격한다 (InputController가 놓는 순간 부른다). charge: 모은 정도 0~1
-- 쿨다운은 서버와 같은 값으로 로컬에서도 막는다. 서버에 요청을 보냈으면 true
function CombatController.attack(def: PickaxeDefs.PickaxeDef, charge: number, held: number?): boolean
	local config = Config.Weapons[def.Id]
	if not config then
		return false
	end
	local now = os.clock()
	if now - lastAttackClock < config.Cooldown then
		return false
	end
	if def.Kind == "Bow" then
		-- 활: 끼운 화살통에 화살이 있어야 쏜다 (서버가 센 속성 Arrows. 실제로 빼는 건 서버)
		local arrows = localPlayer:GetAttribute("Arrows")
		if typeof(arrows) ~= "number" or arrows <= 0 then
			if now - lastArrowNotice >= Config.Quiver.NoticeInterval then
				lastArrowNotice = now
				local worn = localPlayer:GetAttribute("Equip_Shield")
				local hasQuiver = typeof(worn) == "string" and (Config.Quiver.Items :: any)[worn] ~= nil
				local hasShield = typeof(worn) == "string" and worn ~= "" and not hasQuiver -- 방패를 찼으면 화살통 자리가 없다 (2026-10-10)
				local message = if hasQuiver then "화살이 없어요!"
					elseif hasShield then `{Config.Shield.BowHint}! 방패 칸에 방패 대신 화살통을 끼우세요.`
					else "화살통이 필요해요! 사냥꾼에게 사서 방패 칸에 끼우세요."
				NotifyController.show(message, "bad")
			end
			return false
		end
	end
	lastAttackClock = now
	if def.Kind == "Bow" then
		-- 활: 짧게 쏘면 사거리가 짧고, 다 모으면 원래 사거리. 몹이 없으면 앞으로 쏘고 서버에 nil로 알려 화살만 쓴다
		local chargeConfig = Config.Charge
		local range = config.Range * (chargeConfig.BowTapRange + (1 - chargeConfig.BowTapRange) * charge)
		local mob = bowTarget(range)
		local character = localPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			return false
		end
		local from = root.Position + Vector3.new(0, 1, 0)
		local to: Vector3
		if mob then
			face(mob:GetPivot().Position)
			to = mob:GetPivot().Position + Vector3.new(0, mob:GetExtentsSize().Y * 0.5, 0)
			attackRemote:FireServer(mob)
		else
			local camera = Workspace.CurrentCamera
			local look = (if camera then camera.CFrame.LookVector else root.CFrame.LookVector) * Vector3.new(1, 0, 1)
			look = if look.Magnitude > 0.01 then look.Unit else root.CFrame.LookVector
			face(root.Position + look)
			to = from + look * range
			attackRemote:FireServer(nil) -- 빗나간 화살도 화살 1개를 쓴다
		end
		-- 추가 차징(마나)까지 다 모았으면 가장 밝은 화살
		local over = (held or 0) >= chargeConfig.Time + chargeConfig.BowOverTime
		HitFeelController.playSound(Config.Sounds.BowShoot, from, if charge >= 1 then 0.9 else 1.15, if charge >= 1 then 0.9 else 0.6) -- "휘익"
		shootArrow(from, to, if over then math.max(def.Tier, 4) elseif charge >= 1 then math.max(def.Tier, 3) else def.Tier, function() end) -- 내 화살은 바로 보여 준다 (서버 연출에서는 다시 그리지 않는다)
		return true -- 몹이 없어도 요청을 보냈다 (서버가 모으기 기록을 꺼낸다)
	end
	local mob = nearestMob(config.Range)
	if mob then
		face(mob:GetPivot().Position)
	end
	SwingAnimation.play()
	if mob then
		attackRemote:FireServer(mob)
		return true
	end
	return false
end

-- 위치에 잠깐 떠올랐다 사라지는 숫자
local function popNumber(position: Vector3, text: string, color: Color3, size: number)
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = Workspace.Terrain
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(3 * size, 1.4 * size)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.StudsOffsetWorldSpace = Vector3.new((math.random() - 0.5) * 1.5, 0.5, 0)
	billboard.Adornee = attachment
	billboard.Parent = hudFolder
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = color
	label.Parent = billboard
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Parent = label
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(billboard, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = billboard.StudsOffsetWorldSpace + Vector3.new(0, 2.5, 0),
	}):Play()
	task.delay(0.5, function()
		TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.3), { Transparency = 1 }):Play()
	end)
	task.delay(0.85, function()
		attachment:Destroy()
		billboard:Destroy()
	end)
end

-- 몹이 맞으면 하얗게 번쩍
local function flash(mob: Model)
	if not mob.Parent then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.2
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = mob
	highlight.Parent = effectsFolder
	TweenService:Create(highlight, TweenInfo.new(0.18), { FillTransparency = 1 }):Play()
	task.delay(0.2, function()
		highlight:Destroy()
	end)
end

-- 치명타: 몹이 짧게 불타오른다 (불꽃 + 주황 빛)
local function burn(mob: Model)
	local root = mob.PrimaryPart or mob:FindFirstChildWhichIsA("BasePart")
	if not root then
		return
	end
	local burnTime = Config.Combat.CritBurnTime
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, mob:GetExtentsSize().Y * 0.45, 0)
	attachment.Parent = root
	local fire = Instance.new("ParticleEmitter")
	fire.Texture = "rbxasset://textures/particles/fire_main.dds"
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 70, 20))
	fire.LightEmission = 1
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0) })
	fire.Transparency = NumberSequence.new(0.1, 1)
	fire.Lifetime = NumberRange.new(0.3, 0.55)
	fire.Speed = NumberRange.new(3, 6)
	fire.SpreadAngle = Vector2.new(35, 35)
	fire.Acceleration = Vector3.new(0, 8, 0)
	fire.Rate = 70
	fire.Parent = attachment
	local embers = Instance.new("ParticleEmitter")
	embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 160, 60))
	embers.LightEmission = 1
	embers.Size = NumberSequence.new(0.25, 0)
	embers.Lifetime = NumberRange.new(0.4, 0.8)
	embers.Speed = NumberRange.new(5, 10)
	embers.SpreadAngle = Vector2.new(180, 180)
	embers.Rate = 0
	embers.Parent = attachment
	embers:Emit(18)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 130, 40)
	light.Range = 12
	light.Brightness = 3
	light.Parent = attachment
	HitFeelController.playSound(Config.Sounds.CritBurn, root.Position, 1.8, 0.35)
	TweenService:Create(light, TweenInfo.new(burnTime), { Brightness = 0 }):Play()
	task.delay(burnTime, function()
		fire.Enabled = false
	end)
	task.delay(burnTime + 0.6, function()
		attachment:Destroy()
	end)
end

-- 맞은 순간 연출 (활은 화살이 도착한 뒤에 부른다)
local function playImpact(mob: Model?, damage: number, isCrit: boolean, kind: string, tier: number, isMine: boolean, hitPosition: Vector3, charged: boolean?)
	local def = if mob then mobDef(mob) else nil
	local color = if def then def.Color else Color3.new(1, 1, 1)
	if mob then
		flash(mob)
		if isCrit and mob.Parent then
			burn(mob)
		end
	end
	HitFeelController.emitDebris(hitPosition, color, if isCrit then 18 else 10, if isCrit then 1.4 else 1)
	HitFeelController.tierImpact(mob, hitPosition, color, tier, if isCrit then "Perfect" else "Normal", Enum.Material.SmoothPlastic, Config.Combat.TierEffects)

	local pitch = math.random() * 0.15 + 0.95
	if kind == "Sword" then
		HitFeelController.playSound(Config.Sounds.SwordHit, hitPosition, pitch * 1.35, 0.45)
	elseif kind == "Club" then
		HitFeelController.playSound(Config.Sounds.ClubHit, hitPosition, pitch * 0.75, 0.8)
	else
		HitFeelController.playSound(Config.Sounds.ArrowHit, hitPosition, pitch * 1.1, 0.9) -- "퍽!"
	end

	-- 다 모은 강타: 큰 충격파와 흔들림
	if charged then
		HitFeelController.chargedImpact(mob, hitPosition, isMine)
	end
	if isCrit then
		popNumber(hitPosition, `{damage}!`, Color3.fromRGB(255, 150, 40), 1.4)
	else
		popNumber(hitPosition, tostring(damage), Color3.new(1, 1, 1), 1)
	end
	if isMine then
		local effect = TierDefs.pick(Config.Combat.TierEffects :: { [number]: any }, tier)
		local shake = Config.HitFeel.CameraShake
		HitFeelController.cameraShake(shake.Magnitude * (if effect then effect.Shake else 1) * (if isCrit then 1.6 else 1), shake.Duration)
		if kind ~= "Bow" then
			SwingAnimation.freeze(if isCrit then 0.08 else 0.05)
		end
	end
end

-- 서버의 CombatEffect: 누군가 몹을 때렸다
-- fromSkill: 스킬(연사 등)로 쏜 화살은 쏠 때 그리지 않았으니 내 화면에서도 날아가는 화살을 그린다
local function onCombatEffect(mob: Model?, damage: number, isCrit: boolean, kind: string, tier: number, attackerUserId: number, from: Vector3, hitPosition: Vector3, charged: boolean?, blocked: boolean?, fromSkill: boolean?)
	local isMine = attackerUserId == localPlayer.UserId
	local drawArrow = not isMine or fromSkill == true
	if blocked then
		-- 무기가 너무 약해 흠집도 안 남: 둔한 소리 + "흠집도 안 나!" (활은 화살이 도착한 뒤)
		local function bounce()
			HitFeelController.playSound(Config.Sounds.SwordHit, hitPosition, 0.5, 0.4)
			HitFeelController.emitDebris(hitPosition, Color3.fromRGB(190, 190, 190), 4, 0.6)
			HitFeelController.popText(hitPosition, "흠집도 안 나!", Color3.fromRGB(200, 200, 210))
			if isMine and kind ~= "Bow" then
				SwingAnimation.freeze(0.1)
			end
		end
		if kind == "Bow" and drawArrow then
			shootArrow(from, hitPosition, tier, bounce)
		elseif kind == "Bow" then
			task.delay((hitPosition - from).Magnitude / Config.Combat.ArrowSpeed, bounce)
		else
			bounce()
		end
		return
	end
	if kind == "Bow" then
		if not drawArrow then
			-- 내 화살은 쏠 때 이미 그렸다. 도착할 즈음 맞은 연출만
			task.delay(math.max((hitPosition - from).Magnitude / Config.Combat.ArrowSpeed - 0.05, 0), function()
				playImpact(mob, damage, isCrit, kind, tier, isMine, hitPosition, charged)
			end)
		else
			shootArrow(from, hitPosition, tier, function()
				playImpact(mob, damage, isCrit, kind, tier, isMine, hitPosition, charged)
			end)
		end
	else
		playImpact(mob, damage, isCrit, kind, tier, isMine, hitPosition, charged)
	end
end

-- 서버의 MobAttack: 몹이 누군가를 때렸다. 나라면 화면이 빨갛게 번쩍
-- guarded: 구르기 무적·방패 막기로 피했거나(damage 0) 줄였다 → 빨간 번쩍임 대신 "피함!"·"막음!"
local function onMobAttack(_mob: Model?, targetUserId: number, damage: number, guarded: boolean?)
	if targetUserId ~= localPlayer.UserId then
		return
	end
	if guarded then
		local character = localPlayer.Character
		local head = character and character:FindFirstChild("Head")
		local position = if head and head:IsA("BasePart") then head.Position + Vector3.new(0, 1, 0) else nil
		HitFeelController.playSound(Config.Skills.ShieldSound, position, 1.6, 0.5) -- "챙"
		if position then
			if damage <= 0 then
				HitFeelController.popText(position, "피함!", Color3.fromRGB(150, 230, 255))
			else
				HitFeelController.popText(position, `막음! -{damage}`, Color3.fromRGB(150, 200, 255))
			end
		end
		if damage > 0 then
			HitFeelController.cameraShake(Config.HitFeel.CameraShake.Magnitude * 0.7, Config.HitFeel.CameraShake.Duration)
		end
		return
	end
	hurtFrame.BackgroundTransparency = 0.55
	TweenService:Create(hurtFrame, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
	HitFeelController.cameraShake(Config.HitFeel.CameraShake.Magnitude * 2, Config.HitFeel.CameraShake.Duration * 1.5)
	HitFeelController.playSound(Config.Sounds.PlayerHurt, nil, 0.6, 0.6)
	local character = localPlayer.Character
	local head = character and character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		popNumber(head.Position + Vector3.new(0, 1, 0), `-{damage}`, Color3.fromRGB(255, 80, 80), 1)
	end
end

-- 서버의 MobSpecial: 바다 생물 특수 연출 (2026-10-09)
-- "Ink": 낙지가 먹물을 뿜었다 → 그 자리에 검은 먹물 구름, 맞은 사람(나)이면 화면이 data초 동안 어두워졌다 밝아짐
-- "Puff": 복어가 부풀었다 → "뿅" 소리와 가시 조각 (크기는 서버가 Model:ScaleTo로 바꾼다, 지금은 쓰는 몹 없음)
-- 2026-10-10 몹 공격 연출 (판정은 서버 MobService):
-- "Arrow": 스켈레톤 궁수 화살. position = 쏜 곳, data = { To, Time } → Time초 동안 To로 날아간다 (그 자리를 피하면 안 맞음)
-- "Telegraph": 거대 몬스터 큰 기술 경고. position = 가운데, data = { Kind, Shape "Circle"|"Line", Radius, Length, Width, Dir, Time }
--   → 바닥에 빨간 원·직선이 Time초 동안 진해진다 (그 안에서 나가거나 구르면 피함)
-- "Impact": 기술 판정 순간. data = { Kind, Radius } → 충격파 고리·흙먼지·쾅·화면 흔들림 (돌진은 흙먼지만)
-- "Cancel": 기절로 기술 취소 → 그 몹의 경고 표시를 지운다
local telegraphs: { [Model]: { Instance } } = {} -- 몹마다 떠 있는 경고 표시

-- 바닥에 붙는 납작한 경고 부품 하나 (원 = 원통을 눕힘, 직선 = 판)
local function telegraphPart(cframe: CFrame, size: Vector3, cylinder: boolean): Part
	local fx = Config.MobAttackEffects
	local p = Instance.new("Part")
	p.Name = "Telegraph"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = fx.TelegraphColor
	p.Transparency = fx.TelegraphTransparency
	if cylinder then
		p.Shape = Enum.PartType.Cylinder
	end
	p.Size = size
	p.CFrame = cframe
	p.Parent = effectsFolder
	return p
end

local function onMobAttackFx(mob: Model?, kind: string, position: Vector3, data: any)
	local fx = Config.MobAttackEffects
	local mobType = if mob then mob:GetAttribute("MobType") else nil
	local color = (if typeof(mobType) == "string" then (fx.Colors :: any)[mobType] else nil) or Color3.fromRGB(200, 190, 170)
	if kind == "Arrow" then
		if typeof(data) ~= "table" or typeof(data.To) ~= "Vector3" or typeof(data.Time) ~= "number" then
			return
		end
		HitFeelController.playSound(fx.ArrowSound, position, fx.ArrowPitch, 0.6)
		-- 플레이어 화살 모양(shootArrow)을 빌려 쓰고 색만 바꾼다. 날아가는 시간은 서버가 정한 값
		local to: Vector3 = data.To
		local arrow = Instance.new("Part")
		arrow.Size = Vector3.new(0.14, 0.14, 2.2)
		arrow.Material = Enum.Material.SmoothPlastic
		arrow.Color = fx.ArrowColor
		arrow.Anchored = true
		arrow.CanCollide = false
		arrow.CanQuery = false
		arrow.CanTouch = false
		arrow.CastShadow = false
		arrow.CFrame = CFrame.lookAt(position, to)
		arrow.Parent = effectsFolder
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.12, 1.1)
		a0.Parent = arrow
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.12, 1.1)
		a1.Parent = arrow
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(fx.ArrowTrail)
		trail.Transparency = NumberSequence.new(0.2, 1)
		trail.Lifetime = 0.25
		trail.LightEmission = 0.8
		trail.Parent = arrow
		local direction = if (to - position).Magnitude > 0.01 then (to - position).Unit else Vector3.zAxis
		TweenService:Create(arrow, TweenInfo.new(data.Time, Enum.EasingStyle.Linear), { CFrame = CFrame.lookAt(to, to + direction) }):Play()
		task.delay(data.Time, function()
			arrow:Destroy()
			HitFeelController.emitDebris(to, fx.ArrowColor, 4, 0.5)
		end)
	elseif kind == "Telegraph" then
		if typeof(data) ~= "table" or typeof(data.Time) ~= "number" then
			return
		end
		local time: number = data.Time
		local made: { Instance } = {}
		local up = 0.15
		if data.Shape == "Line" and typeof(data.Dir) == "Vector3" and typeof(data.Length) == "number" and typeof(data.Width) == "number" then
			local dir: Vector3 = data.Dir
			local mid = position + dir * (data.Length / 2) + Vector3.new(0, up, 0)
			table.insert(made, telegraphPart(CFrame.lookAt(mid, mid + dir), Vector3.new(data.Width, 0.12, data.Length), false))
		elseif typeof(data.Radius) == "number" and data.Radius > 0 then
			local base = CFrame.new(position + Vector3.new(0, up, 0)) * CFrame.Angles(0, 0, math.rad(90))
			local outer = telegraphPart(base, Vector3.new(0.1, data.Radius * 2, data.Radius * 2), true)
			table.insert(made, outer)
			-- 가운데에서 바깥으로 차오르는 안쪽 원 (다 차면 쾅)
			local inner = telegraphPart(base, Vector3.new(0.14, 0.5, 0.5), true)
			inner.Transparency = 0.3
			TweenService:Create(inner, TweenInfo.new(time, Enum.EasingStyle.Linear), { Size = Vector3.new(0.14, data.Radius * 2, data.Radius * 2) }):Play()
			table.insert(made, inner)
		end
		for _, p in made do
			if p:IsA("BasePart") and p.Name == "Telegraph" then
				TweenService:Create(p, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 0.25 }):Play()
			end
		end
		if mob then
			telegraphs[mob] = made
		end
		HitFeelController.playSound(fx.WarnSound, position, fx.WarnPitch, 0.7)
		task.delay(time + 0.1, function()
			for _, p in made do
				p:Destroy()
			end
			if mob and telegraphs[mob] == made then
				telegraphs[mob] = nil
			end
		end)
	elseif kind == "Cancel" then
		local made = if mob then telegraphs[mob] else nil
		if mob and made then
			for _, p in made do
				p:Destroy()
			end
			telegraphs[mob] = nil
		end
	elseif kind == "Impact" then
		local radius = if typeof(data) == "table" and typeof(data.Radius) == "number" then data.Radius else 6
		local impactKind = if typeof(data) == "table" then data.Kind else nil
		HitFeelController.emitDebris(position + Vector3.new(0, 1, 0), color, if impactKind == "Charge" then 14 else 30, if impactKind == "Charge" then 1 else 1.8)
		HitFeelController.playSound(fx.ImpactSound, position, fx.ImpactPitch, 1)
		if impactKind ~= "Charge" then
			-- 바깥으로 퍼지는 충격파 고리
			local ring = telegraphPart(CFrame.new(position + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.3, 1, 1), true)
			ring.Color = color
			ring.Transparency = 0.2
			TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.3, radius * 2.2, radius * 2.2), Transparency = 1 }):Play()
			task.delay(0.4, function()
				ring:Destroy()
			end)
		end
		local character = localPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - position).Magnitude <= fx.ImpactShakeRange then
			local shake = Config.HitFeel.CameraShake
			HitFeelController.cameraShake(shake.Magnitude * fx.ImpactShake, shake.Duration * 2)
		end
	end
end

local function onMobSpecial(mob: Model?, kind: string, targetUserId: number, position: Vector3, data: any)
	if typeof(position) ~= "Vector3" then
		return
	end
	if kind == "Arrow" or kind == "Telegraph" or kind == "Impact" or kind == "Cancel" then
		onMobAttackFx(mob, kind, position, data)
		return
	end
	local sea = Config.SeaEffects
	if kind == "Ink" then
		local cloud = Instance.new("Part")
		cloud.Name = "InkCloud"
		cloud.Size = Vector3.new(1, 1, 1)
		cloud.Transparency = 1
		cloud.Anchored = true
		cloud.CanCollide = false
		cloud.CanQuery = false
		cloud.CanTouch = false
		cloud.CFrame = CFrame.new(position)
		cloud.Parent = effectsFolder
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(sea.InkColor)
		emitter.LightEmission = 0
		emitter.LightInfluence = 0.2
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, sea.InkCloudSize * 0.4),
			NumberSequenceKeypoint.new(0.4, sea.InkCloudSize),
			NumberSequenceKeypoint.new(1, sea.InkCloudSize * 1.3),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(0.6, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Lifetime = NumberRange.new(sea.InkCloudTime * 0.6, sea.InkCloudTime)
		emitter.Speed = NumberRange.new(2, 7)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Drag = 3
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-40, 40)
		emitter.Rate = 0
		emitter.Parent = cloud
		emitter:Emit(30)
		task.delay(sea.InkCloudTime + 0.5, function()
			cloud:Destroy()
		end)
		HitFeelController.playSound(sea.PuffSound, position, 0.55, 0.7) -- "뿌직"
		if targetUserId == localPlayer.UserId then
			local blind = if typeof(data) == "number" then data else 1.5
			inkFrame.BackgroundTransparency = sea.InkScreen
			TweenService:Create(inkFrame, TweenInfo.new(blind, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
			NotifyController.show("앗, 먹물!", "info")
		end
	elseif kind == "Puff" then
		HitFeelController.playSound(sea.PuffSound, position, sea.PuffPitch, 0.8)
		local def = if mob then mobDef(mob) else nil
		HitFeelController.emitDebris(position, if def then def.Color else Color3.new(1, 1, 1), 10, 0.6)
	end
end

-- 서버의 MobDied: 몹이 쓰러졌다. 펑 하고 사라지고, 내가 잡았으면 보상 표시
-- extras: 주 전리품 말고 더 받은 전리품 목록 { {Id, Count} } (두 번째 전리품·보스 전리품, 2026-10-09)
local function onMobDied(position: Vector3, mobType: string, killerUserId: number, gold: number, lootId: string, lootCount: number, extras: { any }?)
	local def = MobDefs[mobType]
	local center = position + Vector3.new(0, 1.5, 0)
	HitFeelController.emitDebris(center, if def then def.Color else Color3.new(1, 1, 1), 35, 1.5)
	HitFeelController.emitDebris(center, Color3.new(1, 1, 1), 15, 0.8)
	HitFeelController.playSound(Config.Sounds.MobDie, center, 0.7, 0.5)
	-- 몹마다 다른 비명 (슬라임 "뀍!", 스켈레톤 "으어억!", 케르베로스 "깨갱!" ...)
	local cry = Config.MobDeathSounds[mobType]
	if cry then
		HitFeelController.playSound(cry.Id, center, cry.Pitch, cry.Volume)
		if cry.Repeat then
			-- 깨갱처럼 두 번 끊어 우는 소리
			task.delay(cry.Repeat, function()
				HitFeelController.playSound(cry.Id, center, cry.Pitch * 1.12, cry.Volume * 0.8)
			end)
		end
	end
	if killerUserId == localPlayer.UserId then
		-- 골드 동전과 전리품이 땅에 떨어졌다가 빨려 들어오면 획득 알림
		RockHUD.showReward(center, gold, "G", 0)
		HitFeelController.spawnPickups(center, Color3.fromRGB(255, 205, 60), math.min(gold, 8), Enum.Material.Metal, "Coin", function()
			PickupFeed.show("Gold", gold)
		end)
		local drops: { { Id: string, Count: number } } = { { Id = lootId, Count = lootCount } }
		if typeof(extras) == "table" then
			for _, extra in extras do
				if typeof(extra) == "table" and typeof(extra.Id) == "string" and typeof(extra.Count) == "number" then
					table.insert(drops, { Id = extra.Id, Count = extra.Count })
				end
			end
		end
		for _, drop in drops do
			local loot = ItemDefs.Items[drop.Id]
			if loot and drop.Count > 0 then
				HitFeelController.spawnPickups(center, loot.Color, drop.Count, Enum.Material.SmoothPlastic, "Cube", function()
					PickupFeed.show(drop.Id, drop.Count)
				end)
			end
		end
	end
end

-- 몹 머리 위 이름·체력바를 만든다
-- 태그가 먼저 도착하고 부품은 나중에 복제되므로, 뿌리 부품(Root)이 올 때까지 기다렸다가 붙인다
local function addHpBar(mob: Instance)
	if not mob:IsA("Model") or hpBars[mob] then
		return
	end
	local root = mob:FindFirstChild("Root") or mob:WaitForChild("Root", 10)
	if not root or not root:IsA("BasePart") or hpBars[mob] or not mob.Parent then
		return
	end
	task.wait() -- 나머지 몸 부품도 들어올 틈
	local def = mobDef(mob)
	-- 보스(속성 Boss)는 "👑 보스" 금색 이름 + 더 큰 체력바, 더 멀리서도 보인다
	local boss = mob:GetAttribute("Boss") == true
	local bossConfig = Config.MobBoss
	local barScale = if boss then bossConfig.HpBarScale else 1
	local range = Config.Combat.HpBarRange * (if boss then bossConfig.HpBarRangeMultiplier else 1)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(4.5 * barScale, 0, 1.1 * barScale, 0)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, math.max(mob:GetExtentsSize().Y, 2) + 0.8 * barScale, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = range
	billboard.Enabled = false
	billboard.Adornee = root
	billboard.Parent = hudFolder

	local name = Instance.new("TextLabel")
	name.Size = UDim2.fromScale(1, 0.5)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.FredokaOne
	-- 원소 보스(속성 Element, 2026-10-10)는 "👑 불타는 보스 ~" + 원소 색
	local elementAttribute = mob:GetAttribute("Element")
	local element = if boss and typeof(elementAttribute) == "string" then ((bossConfig :: any).Elements or {})[elementAttribute] else nil
	local prefix = if element then element.BossPrefix elseif boss then bossConfig.NamePrefix else ""
	name.Text = if def then prefix .. def.DisplayName else ""
	name.TextScaled = true
	name.TextColor3 = if element then element.NameColor elseif boss then bossConfig.NameColor else Color3.new(1, 1, 1)
	name.Parent = billboard
	local nameStroke = Instance.new("UIStroke")
	nameStroke.Thickness = 1.5
	nameStroke.Parent = name

	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 0.35)
	back.Position = UDim2.fromScale(0, 0.58)
	back.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	back.BorderSizePixel = 0
	back.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = back
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(235, 80, 80)
	fill.BorderSizePixel = 0
	fill.Parent = back
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill

	if boss then
		fill.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
		local backStroke = Instance.new("UIStroke")
		backStroke.Color = bossConfig.NameColor
		backStroke.Thickness = 2
		backStroke.Parent = back
	end

	hpBars[mob] = { Gui = billboard, Fill = fill, Range = range }
end

local function removeHpBar(mob: Instance)
	if not mob:IsA("Model") then
		return
	end
	local bar = hpBars[mob]
	if bar then
		bar.Gui:Destroy()
		hpBars[mob] = nil
	end
end

-- 매 프레임: 가까운 몹만 체력바를 켜고 체력을 반영한다
local function updateHpBars()
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local rootPosition = if root and root:IsA("BasePart") then root.Position else nil
	for mob, bar in hpBars do
		if not mob.Parent then
			bar.Gui:Destroy()
			hpBars[mob] = nil
			continue
		end
		local hp = mob:GetAttribute("Hp")
		local maxHp = mob:GetAttribute("MaxHp")
		local near = rootPosition ~= nil and (mob:GetPivot().Position - rootPosition).Magnitude <= bar.Range
		bar.Gui.Enabled = near
		if near and typeof(hp) == "number" and typeof(maxHp) == "number" and maxHp > 0 then
			bar.Fill.Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1)
		end
	end
end

-- 클라이언트 시작 시 한 번 호출
function CombatController.init()
	attackRemote = Remotes.get(Remotes.Names.AttackRequest)

	local folder = Instance.new("Folder")
	folder.Name = "ClientCombatEffects"
	folder.Parent = Workspace
	effectsFolder = folder
	local hud = Instance.new("Folder")
	hud.Name = "ClientCombatHUD"
	hud.Parent = Workspace
	hudFolder = hud

	-- 맞았을 때 화면 가장자리 빨간 번쩍임
	local gui = Instance.new("ScreenGui")
	gui.Name = "HurtGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	hurtFrame = Instance.new("Frame")
	hurtFrame.Size = UDim2.fromScale(1, 1)
	hurtFrame.BackgroundColor3 = Color3.fromRGB(200, 20, 20)
	hurtFrame.BackgroundTransparency = 1
	hurtFrame.BorderSizePixel = 0
	hurtFrame.Parent = gui
	inkFrame = Instance.new("Frame")
	inkFrame.Name = "Ink"
	inkFrame.Size = UDim2.fromScale(1, 1)
	inkFrame.BackgroundColor3 = Config.SeaEffects.InkColor
	inkFrame.BackgroundTransparency = 1
	inkFrame.BorderSizePixel = 0
	inkFrame.Parent = gui

	for _, mob in CollectionService:GetTagged(MOB_TAG) do
		task.spawn(addHpBar, mob)
	end
	CollectionService:GetInstanceAddedSignal(MOB_TAG):Connect(function(mob)
		task.spawn(addHpBar, mob)
	end)
	CollectionService:GetInstanceRemovedSignal(MOB_TAG):Connect(removeHpBar)
	RunService.Heartbeat:Connect(updateHpBars)

	Remotes.get(Remotes.Names.CombatEffect).OnClientEvent:Connect(onCombatEffect)
	Remotes.get(Remotes.Names.MobAttack).OnClientEvent:Connect(onMobAttack)
	Remotes.get(Remotes.Names.MobDied).OnClientEvent:Connect(onMobDied)
	Remotes.get(Remotes.Names.MobSpecial).OnClientEvent:Connect(onMobSpecial)
end

return CombatController
