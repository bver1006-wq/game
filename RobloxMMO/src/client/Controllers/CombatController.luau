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
local PickaxeDefs = require(ReplicatedStorage.Shared.PickaxeDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local HitFeelController = require(script.Parent.HitFeelController)
local RockHUD = require(script.Parent.RockHUD)
local SwingAnimation = require(script.Parent.SwingAnimation)

local MOB_TAG = "Mob"
local WEAPON_KINDS: { [string]: boolean } = { Sword = true, Bow = true, Club = true }

local localPlayer = Players.LocalPlayer

local CombatController = {}

local attackRemote: RemoteEvent
local effectsFolder: Folder
local hudFolder: Folder
local lastAttackClock = -math.huge
local hpBars: { [Model]: { Gui: BillboardGui, Fill: Frame } } = {}
local hurtFrame: Frame

-- 이 도구가 무기인지
function CombatController.isWeapon(def: PickaxeDefs.PickaxeDef): boolean
	return WEAPON_KINDS[def.Kind] == true
end

-- 몹 정의 (모르는 몹이면 nil)
local function mobDef(mob: Instance): MobDefs.MobDef?
	local mobType = mob:GetAttribute("MobType")
	return if typeof(mobType) == "string" then MobDefs[mobType] else nil
end

-- 사거리 안에서 가장 가까운 살아 있는 몹
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
		if mob:IsA("Model") and mob:IsDescendantOf(Workspace) and typeof(hp) == "number" and hp > 0 then
			local size = mob:GetExtentsSize()
			local flat = (mob:GetPivot().Position - root.Position) * Vector3.new(1, 0, 1)
			local distance = flat.Magnitude - math.max(size.X, size.Z) / 2
			if distance <= range and distance < bestDistance then
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
		if mob:IsA("Model") and mob:IsDescendantOf(Workspace) and typeof(hp) == "number" and hp > 0 then
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
	local effect = Config.Combat.TierEffects[tier]
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
function CombatController.attack(def: PickaxeDefs.PickaxeDef, charge: number): boolean
	local config = Config.Weapons[def.Id]
	if not config then
		return false
	end
	local now = os.clock()
	if now - lastAttackClock < config.Cooldown then
		SwingAnimation.cancelHold()
		return false
	end
	lastAttackClock = now
	if def.Kind == "Bow" then
		-- 활: 화살 없이 언제든 쏜다. 짧게 쏘면 사거리가 짧고, 다 모으면 원래 사거리
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
		end
		HitFeelController.playSound(Config.Sounds.BowShoot, from, if charge >= 1 then 1.8 else 2.2, if charge >= 1 then 0.8 else 0.5)
		shootArrow(from, to, if charge >= 1 then math.max(def.Tier, 3) else def.Tier, function() end) -- 내 화살은 바로 보여 준다 (서버 연출에서는 다시 그리지 않는다)
		return mob ~= nil
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
		HitFeelController.playSound(Config.Sounds.ArrowHit, hitPosition, pitch * 1.3, 0.6)
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
		local effect = Config.Combat.TierEffects[tier]
		local shake = Config.HitFeel.CameraShake
		HitFeelController.cameraShake(shake.Magnitude * (if effect then effect.Shake else 1) * (if isCrit then 1.6 else 1), shake.Duration)
		if kind ~= "Bow" then
			SwingAnimation.freeze(if isCrit then 0.08 else 0.05)
		end
	end
end

-- 서버의 CombatEffect: 누군가 몹을 때렸다
local function onCombatEffect(mob: Model?, damage: number, isCrit: boolean, kind: string, tier: number, attackerUserId: number, from: Vector3, hitPosition: Vector3, charged: boolean?)
	local isMine = attackerUserId == localPlayer.UserId
	if kind == "Bow" then
		if isMine then
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
local function onMobAttack(_mob: Model?, targetUserId: number, damage: number)
	if targetUserId ~= localPlayer.UserId then
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

-- 서버의 MobDied: 몹이 쓰러졌다. 펑 하고 사라지고, 내가 잡았으면 보상 표시
local function onMobDied(position: Vector3, mobType: string, killerUserId: number, gold: number, lootId: string, lootCount: number)
	local def = MobDefs[mobType]
	local center = position + Vector3.new(0, 1.5, 0)
	HitFeelController.emitDebris(center, if def then def.Color else Color3.new(1, 1, 1), 35, 1.5)
	HitFeelController.emitDebris(center, Color3.new(1, 1, 1), 15, 0.8)
	HitFeelController.playSound(Config.Sounds.MobDie, center, 0.7, 0.8)
	if killerUserId == localPlayer.UserId then
		RockHUD.showReward(center, gold, "G", 0)
		local loot = ItemDefs.Items[lootId]
		if loot and lootCount > 0 then
			task.delay(0.25, function()
				RockHUD.showReward(center + Vector3.new(0, 1.2, 0), lootCount, loot.DisplayName, 0)
			end)
		end
	end
end

-- 몹 머리 위 이름·체력바를 만든다
local function addHpBar(mob: Instance)
	if not mob:IsA("Model") or hpBars[mob] then
		return
	end
	local def = mobDef(mob)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(4, 0, 1, 0)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, mob:GetExtentsSize().Y + 0.8, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Enabled = false
	billboard.Adornee = mob.PrimaryPart or mob:FindFirstChildWhichIsA("BasePart")
	billboard.Parent = hudFolder

	local name = Instance.new("TextLabel")
	name.Size = UDim2.fromScale(1, 0.5)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.FredokaOne
	name.Text = if def then def.DisplayName else ""
	name.TextScaled = true
	name.TextColor3 = Color3.new(1, 1, 1)
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

	hpBars[mob] = { Gui = billboard, Fill = fill }
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
		local hp = mob:GetAttribute("Hp")
		local maxHp = mob:GetAttribute("MaxHp")
		local near = rootPosition ~= nil and (mob:GetPivot().Position - rootPosition).Magnitude <= Config.Combat.HpBarRange
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

	for _, mob in CollectionService:GetTagged(MOB_TAG) do
		addHpBar(mob)
	end
	CollectionService:GetInstanceAddedSignal(MOB_TAG):Connect(addHpBar)
	CollectionService:GetInstanceRemovedSignal(MOB_TAG):Connect(removeHpBar)
	RunService.Heartbeat:Connect(updateHpBars)

	Remotes.get(Remotes.Names.CombatEffect).OnClientEvent:Connect(onCombatEffect)
	Remotes.get(Remotes.Names.MobAttack).OnClientEvent:Connect(onMobAttack)
	Remotes.get(Remotes.Names.MobDied).OnClientEvent:Connect(onMobDied)
end

return CombatController
