--!strict
-- 광산 안 분위기 (이 클라이언트에만 적용되는 연출).
-- 광산 구역(태그 "MineZone", 속성 Floor) 안에 들어가면:
--   조명을 어둡게 하고 안개·색을 바꾼다, 입장 음악 + 배경음·물방울 소리를 튼다,
--   박쥐가 정해진 길 없이 제멋대로 날아다닌다 (시작 위치: Floor모델/BatWaypoints)
-- 나오면 모두 원래대로 돌린다. 횃불·랜턴(속성 Flicker)은 항상 살짝 깜빡인다.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local ZONE_TAG = "MineZone"
local CHECK_INTERVAL = 0.3 -- 구역 확인 간격(초)

local localPlayer = Players.LocalPlayer

-- 박쥐 하나: 정해진 길 없이 제멋대로 방향을 틀며 날고, 벽에 닿으면 튕겨 나간다
type Bat = {
	Model: Model,
	Body: BasePart,
	LeftWing: BasePart,
	RightWing: BasePart,
	Eyes: BasePart,
	Position: Vector3,
	Direction: Vector3,
	Speed: number,
	TargetSpeed: number,
	HoverUntil: number, -- 이 시각까지 제자리에서 퍼덕인다
	Phase: number,
}

local MineAtmosphereController = {}

local currentFloor: number? = nil
local original: { [string]: any } = {}
local colorCorrection: ColorCorrectionEffect
local ambientSound: Sound
local dripSound: Sound
local bats: { Bat } = {}
local batFolder: Folder
local random = Random.new()

-- 소리 하나 만들기 (화면 전체에서 들리는 소리)
local function makeSound(id: string, looped: boolean): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Looped = looped
	sound.Volume = 0
	sound.Parent = SoundService
	return sound
end

-- 소리 볼륨을 천천히 바꾼다 (0이 되면 멈춘다)
local function fadeSound(sound: Sound, volume: number)
	if volume > 0 and not sound.IsPlaying then
		sound:Play()
	end
	local tween = TweenService:Create(sound, TweenInfo.new(Config.MineAtmosphere.TweenTime), { Volume = volume })
	tween:Play()
	if volume <= 0 then
		tween.Completed:Once(function()
			if sound.Volume <= 0.001 then
				sound:Stop()
			end
		end)
	end
end

-- 조명을 광산용으로 / 원래대로
local function applyLighting(inMine: boolean)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	local info = TweenInfo.new(Config.MineAtmosphere.TweenTime)
	local cfg = Config.MineAtmosphere
	if inMine then
		TweenService:Create(Lighting, info, {
			Ambient = cfg.Ambient,
			OutdoorAmbient = cfg.OutdoorAmbient,
			Brightness = cfg.Brightness,
			ExposureCompensation = cfg.ExposureCompensation,
		}):Play()
		if atmosphere then
			TweenService:Create(atmosphere, info, { Density = cfg.AtmosphereDensity, Color = cfg.AtmosphereColor, Decay = cfg.AtmosphereDecay }):Play()
		end
		TweenService:Create(colorCorrection, info, { Saturation = cfg.Saturation, TintColor = cfg.TintColor }):Play()
	else
		TweenService:Create(Lighting, info, {
			Ambient = original.Ambient,
			OutdoorAmbient = original.OutdoorAmbient,
			Brightness = original.Brightness,
			ExposureCompensation = original.ExposureCompensation,
		}):Play()
		if atmosphere and original.Density then
			TweenService:Create(atmosphere, info, { Density = original.Density, Color = original.AtmColor, Decay = original.AtmDecay }):Play()
		end
		TweenService:Create(colorCorrection, info, { Saturation = 0, TintColor = Color3.new(1, 1, 1) }):Play()
	end
end

-- 박쥐 모델 하나 (검은 몸통 + 날개 두 장)
local function makeBatModel(): (Model, BasePart, BasePart, BasePart)
	local model = Instance.new("Model")
	model.Name = "Bat"
	local function piece(name: string, size: Vector3, shape: Enum.PartType?): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Shape = shape or Enum.PartType.Block
		p.Color = Color3.fromRGB(20, 18, 22)
		p.Material = Enum.Material.Fabric
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = model
		return p
	end
	local body = piece("Body", Vector3.new(0.7, 0.7, 0.7), Enum.PartType.Ball)
	local left = piece("LeftWing", Vector3.new(1.3, 0.06, 0.7))
	local right = piece("RightWing", Vector3.new(1.3, 0.06, 0.7))
	-- 빨간 눈
	local eye = piece("Eyes", Vector3.new(0.4, 0.1, 0.05))
	eye.Color = Color3.fromRGB(255, 40, 40)
	eye.Material = Enum.Material.Neon
	model.Parent = batFolder
	return model, body, left, right
end

local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = { Workspace.Terrain }
local spawnPoints: { Vector3 } = {}
local currentZone: BasePart? = nil

-- 아무 방향 (위아래는 약하게)
local function randomDirection(): Vector3
	local v = Vector3.new(random:NextNumber(-1, 1), random:NextNumber(-0.35, 0.35), random:NextNumber(-1, 1))
	return if v.Magnitude > 0.01 then v.Unit else Vector3.xAxis
end

-- 이 층의 박쥐를 만든다 (통로 칸 중심 근처에서 시작)
local function spawnBats(floor: number)
	local mine = Workspace:FindFirstChild("Mine")
	local floorModel = mine and mine:FindFirstChild("Floor" .. floor)
	local folder = floorModel and floorModel:FindFirstChild("BatWaypoints")
	if not folder then
		return
	end
	table.clear(spawnPoints)
	for _, wp in folder:GetChildren() do
		if wp:IsA("BasePart") then
			table.insert(spawnPoints, wp.Position)
		end
	end
	if #spawnPoints == 0 then
		return
	end
	local cfg = Config.MineAtmosphere
	for _ = 1, cfg.BatCount do
		local model, body, left, right = makeBatModel()
		local bat: Bat = {
			Model = model,
			Body = body,
			LeftWing = left,
			RightWing = right,
			Eyes = model:FindFirstChild("Eyes") :: BasePart,
			Position = spawnPoints[random:NextInteger(1, #spawnPoints)],
			Direction = randomDirection(),
			Speed = cfg.BatSpeedMin,
			TargetSpeed = random:NextNumber(cfg.BatSpeedMin, cfg.BatSpeedMax),
			HoverUntil = 0,
			Phase = random:NextNumber(0, 10),
		}
		table.insert(bats, bat)
	end
end

-- 박쥐를 모두 없앤다
local function clearBats()
	for _, bat in bats do
		bat.Model:Destroy()
	end
	table.clear(bats)
end

-- 박쥐 한 마리 움직이기: 제멋대로 방향 틀기 + 벽·바닥·천장 피하기 + 가끔 멈칫·급가속
local function moveBat(bat: Bat, dt: number, now: number)
	local cfg = Config.MineAtmosphere
	-- 속도는 수시로 바뀐다
	if random:NextNumber() < dt * 0.7 then
		bat.TargetSpeed = random:NextNumber(cfg.BatSpeedMin, cfg.BatSpeedMax)
	end
	if random:NextNumber() < dt * cfg.BatHoverChance then
		bat.HoverUntil = now + random:NextNumber(0.4, 1.2)
	end
	local hovering = now < bat.HoverUntil
	local targetSpeed = if hovering then 0.5 else bat.TargetSpeed
	bat.Speed += (targetSpeed - bat.Speed) * math.min(dt * 3, 1)

	-- 제멋대로 방향 틀기
	local turn = randomDirection() * cfg.BatTurnRate * dt
	local direction = (bat.Direction + turn).Unit

	-- 앞이 막혔으면 튕겨 나간다
	local look = workspace:Raycast(bat.Position, direction * 3, terrainParams)
	if look then
		direction = (direction - 2 * direction:Dot(look.Normal) * look.Normal + randomDirection() * 0.5).Unit
	end
	-- 바닥·천장과 거리 유지
	local down = workspace:Raycast(bat.Position, Vector3.new(0, -3, 0), terrainParams)
	local up = workspace:Raycast(bat.Position, Vector3.new(0, 2, 0), terrainParams)
	if down then
		direction = (direction + Vector3.new(0, 0.6, 0)).Unit
	elseif up then
		direction = (direction + Vector3.new(0, -0.6, 0)).Unit
	end
	bat.Direction = direction

	local nextPosition = bat.Position + direction * bat.Speed * dt
	-- 벽을 뚫고 나가지 않게: 이동 경로가 막히면 제자리에서 방향만 바꾼다
	if workspace:Raycast(bat.Position, nextPosition - bat.Position, terrainParams) then
		bat.Direction = -direction
	else
		bat.Position = nextPosition
	end
	-- 광산 구역 밖으로 나가면 아무 칸으로 다시 데려온다
	local zone = currentZone
	if zone then
		local localPos = zone.CFrame:PointToObjectSpace(bat.Position)
		local half = zone.Size / 2
		if math.abs(localPos.X) > half.X or math.abs(localPos.Y) > half.Y or math.abs(localPos.Z) > half.Z then
			bat.Position = spawnPoints[random:NextInteger(1, #spawnPoints)]
		end
	end

	local flapSpeed = if hovering then 30 else 18 + bat.Speed
	local flap = math.sin(now * flapSpeed + bat.Phase) * 0.9
	local base = CFrame.lookAt(bat.Position, bat.Position + Vector3.new(direction.X, direction.Y * 0.5, direction.Z))
	bat.Body.CFrame = base
	bat.LeftWing.CFrame = base * CFrame.new(-0.3, 0, 0) * CFrame.Angles(0, 0, flap) * CFrame.new(-0.6, 0, 0)
	bat.RightWing.CFrame = base * CFrame.new(0.3, 0, 0) * CFrame.Angles(0, 0, -flap) * CFrame.new(0.6, 0, 0)
	bat.Eyes.CFrame = base * CFrame.new(0, 0.1, -0.36)
end

-- 매 프레임 박쥐 움직이기
local function updateBats(dt: number)
	local now = os.clock()
	for _, bat in bats do
		moveBat(bat, dt, now)
	end
end

-- 가까운 박쥐가 가끔 날갯짓 소리를 낸다
local function batSounds(rootPosition: Vector3)
	local cfg = Config.MineAtmosphere
	for _, bat in bats do
		if (bat.Body.Position - rootPosition).Magnitude <= cfg.BatSoundRange and random:NextNumber() < cfg.BatFlapChance * CHECK_INTERVAL then
			local sound = Instance.new("Sound")
			sound.SoundId = Config.Sounds.BatFlap
			sound.PlaybackSpeed = random:NextNumber(1.6, 2.0)
			sound.Volume = 0.35
			sound.RollOffMaxDistance = cfg.BatSoundRange
			sound.Parent = bat.Body
			sound:Play()
			task.delay(1.5, function()
				sound:Destroy()
			end)
		end
	end
end

-- 캐릭터가 있는 광산 층 (밖이면 nil)
local function findFloor(position: Vector3): number?
	for _, zone in CollectionService:GetTagged(ZONE_TAG) do
		if zone:IsA("BasePart") then
			local localPos = zone.CFrame:PointToObjectSpace(position)
			local half = zone.Size / 2
			if math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y and math.abs(localPos.Z) <= half.Z then
				local floor = zone:GetAttribute("Floor")
				currentZone = zone
				return if typeof(floor) == "number" then floor else 0
			end
		end
	end
	return nil
end

-- 광산에 들어가거나 나갔을 때
local function setFloor(floor: number?)
	if floor == currentFloor then
		return
	end
	local wasInMine = currentFloor ~= nil
	currentFloor = floor
	clearBats()
	if floor then
		if not wasInMine then
			applyLighting(true)
			-- 입장 음악 (한 번)
			local enter = Instance.new("Sound")
			enter.SoundId = Config.Sounds.MineEnter
			enter.Volume = Config.MineAtmosphere.EnterVolume
			enter.Parent = SoundService
			enter:Play()
			enter.Ended:Once(function()
				enter:Destroy()
			end)
			fadeSound(ambientSound, Config.MineAtmosphere.AmbientVolume)
			fadeSound(dripSound, Config.MineAtmosphere.DripVolume)
		end
		spawnBats(floor)
	else
		applyLighting(false)
		fadeSound(ambientSound, 0)
		fadeSound(dripSound, 0)
	end
end

-- 횃불·랜턴 깜빡임 (속성 Flicker가 있는 파트의 PointLight)
local flickerLights: { PointLight } = {}
local function collectFlickerLights()
	table.clear(flickerLights)
	for _, part in Workspace:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("Flicker") then
			local light = part:FindFirstChildOfClass("PointLight")
			if light then
				light:SetAttribute("BaseBrightness", light:GetAttribute("BaseBrightness") or light.Brightness)
				table.insert(flickerLights, light)
			end
		end
	end
end

-- 지금 있는 광산 층 (광산 밖이면 nil). 미니맵이 쓴다
function MineAtmosphereController.getFloor(): number?
	return currentFloor
end

-- 클라이언트 시작 시 한 번 호출
function MineAtmosphereController.init()
	original.Ambient = Lighting.Ambient
	original.OutdoorAmbient = Lighting.OutdoorAmbient
	original.Brightness = Lighting.Brightness
	original.ExposureCompensation = Lighting.ExposureCompensation
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		original.Density = atmosphere.Density
		original.AtmColor = atmosphere.Color
		original.AtmDecay = atmosphere.Decay
	end

	colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "MineColorCorrection"
	colorCorrection.Parent = Lighting

	ambientSound = makeSound(Config.Sounds.MineAmbient, true)
	dripSound = makeSound(Config.Sounds.CaveDrip, true)

	local folder = Instance.new("Folder")
	folder.Name = "ClientBats"
	folder.Parent = Workspace
	batFolder = folder

	-- 구역 확인 + 박쥐 소리 (주기적으로)
	task.spawn(function()
		while true do
			local character = localPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				setFloor(findFloor(root.Position))
				if currentFloor then
					batSounds(root.Position)
				end
			end
			task.wait(CHECK_INTERVAL)
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		if #bats > 0 then
			updateBats(dt)
		end
		local amount = Config.MineAtmosphere.TorchFlicker
		for _, light in flickerLights do
			local base = light:GetAttribute("BaseBrightness")
			if typeof(base) == "number" and light.Parent then
				light.Brightness = base * (1 + (math.noise(os.clock() * 4, base * 13) * amount))
			end
		end
	end)

	-- 횃불 목록은 스트리밍으로 늦게 들어올 수 있어 가끔 다시 모은다
	task.spawn(function()
		while true do
			collectFlickerLights()
			task.wait(5)
		end
	end)
end

return MineAtmosphereController
