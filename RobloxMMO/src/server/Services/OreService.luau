--!strict
-- 광석 노드(바위) 생성·리스폰·체력 관리.
-- Workspace/OreSpawns의 스폰 파트(속성 OreType)마다 바위를 하나씩 만들고,
-- 바위별 상태(HP, 기여도, 판정 기록, 약점)는 서버 메모리에만 둔다.
-- 클라이언트가 볼 수 있도록 바위에는 OreNode 태그와 OreType·MaxHp·Hp 속성만 복제한다.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local OreDefs = require(ReplicatedStorage.Shared.OreDefs)

-- 플레이어 한 명이 이 바위에서 낸 판정 횟수
export type JudgmentCounts = {
	Nice: number,
	Perfect: number,
}

-- 바위 하나의 서버 상태
export type RockState = {
	Rock: Model,
	OreType: string,
	SpawnPart: BasePart,
	Position: Vector3, -- 생성 위치. 바위가 제거된 뒤에도 연출 위치로 쓴다
	Hp: number,
	MaxHp: number,
	Depleted: boolean, -- HP가 0이 됐다 (피버 중이면 아직 제거 전)
	Contributions: { [number]: number }, -- UserId → 누적 데미지 (보상 분배용)
	Judgments: { [number]: JudgmentCounts }, -- UserId → Nice·Perfect 횟수
	HitCount: number,
	LastHit: number, -- 마지막으로 맞은 시각 (자연 회복용)
	Weakpoint: Vector3?, -- 7단계(약점)부터 사용. 바위 기준 약점 방향
}

local ORE_TAG = "OreNode"

local OreService = {}
OreService.Tag = ORE_TAG

local states: { [Model]: RockState } = {}
local occupied: { [BasePart]: boolean } = {} -- 지금 노드가 서 있는 스폰 파트
local pools: { [string]: { BasePart } } = {} -- 무리 이름 → 후보 스폰 파트 (Config.RandomPools)
local random = Random.new()

local oresFolder: Folder
local templatesFolder: Folder

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = true

-- 광석 종류에 맞는 템플릿 모델을 고른다. 템플릿이 폴더면 안의 모양 변형 중 하나를 랜덤으로. 없으면 nil
local function pickTemplate(oreType: string): Model?
	local def = OreDefs[oreType]
	if not def then
		return nil
	end
	local template = templatesFolder:FindFirstChild(def.TemplateName)
	if template and template:IsA("Model") then
		return template
	end
	if template and template:IsA("Folder") then
		local variants = {}
		for _, child in template:GetChildren() do
			if child:IsA("Model") then
				table.insert(variants, child)
			end
		end
		if #variants > 0 then
			return variants[random:NextInteger(1, #variants)]
		end
	end
	return nil
end

-- 스폰 파트 아래의 땅 높이를 찾는다 (바위·스폰 파트·캐릭터는 무시)
local function findGroundY(spawnPart: BasePart): number
	local spawnConfig = Config.OreSpawn
	local origin = spawnPart.Position + Vector3.new(0, spawnConfig.GroundSearchUp, 0)
	local length = spawnConfig.GroundSearchUp + spawnConfig.GroundSearchDown
	local result = Workspace:Raycast(origin, Vector3.new(0, -length, 0), groundParams)
	-- 리스폰 자리에 사람이 서 있으면 그 사람 위에 올라가지 않게 땅으로 치지 않는다
	local hitModel = result and result.Instance:FindFirstAncestorOfClass("Model")
	local hitCharacter = hitModel ~= nil and Players:GetPlayerFromCharacter(hitModel) ~= nil
	if result and not hitCharacter then
		return result.Position.Y
	end
	return spawnPart.Position.Y - spawnConfig.FallbackDrop
end

-- 스폰 파트 위치에 바위를 하나 만들고 상태를 등록한다
local function spawnRock(spawnPart: BasePart): Model?
	local oreType = spawnPart:GetAttribute("OreType")
	if typeof(oreType) ~= "string" then
		return nil
	end
	local template = pickTemplate(oreType)
	local oreConfig = Config.Ores[oreType]
	if not template or not oreConfig then
		return nil
	end

	local rock = template:Clone()
	rock.Name = oreType
	rock.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- 스트리밍 중에 바위 일부만 보이지 않게

	-- 스폰 파트 위치에 놓고, 필요하면 Y축으로 랜덤 회전
	local cframe = CFrame.new(spawnPart.Position)
	if Config.OreSpawn.RandomYaw then
		cframe *= CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
	end
	rock:PivotTo(cframe)

	-- 모양마다 높이가 달라서, 바위 바닥이 땅에 닿도록 위아래만 맞춘다
	local boxCFrame, boxSize = rock:GetBoundingBox()
	local bottomY = boxCFrame.Position.Y - boxSize.Y / 2
	local def = OreDefs[oreType]
	local sink = if def and def.Kind == "Tree" then Config.OreSpawn.TreeSinkDepth else Config.OreSpawn.SinkDepth
	local targetBottomY = findGroundY(spawnPart) - sink
	cframe += Vector3.new(0, targetBottomY - bottomY, 0)
	rock:PivotTo(cframe)

	rock:SetAttribute("OreType", oreType)
	rock:SetAttribute("MaxHp", oreConfig.MaxHp)
	rock:SetAttribute("Hp", oreConfig.MaxHp)
	CollectionService:AddTag(rock, ORE_TAG)

	states[rock] = {
		Rock = rock,
		OreType = oreType,
		SpawnPart = spawnPart,
		Position = cframe.Position,
		Hp = oreConfig.MaxHp,
		MaxHp = oreConfig.MaxHp,
		Depleted = false,
		Contributions = {},
		Judgments = {},
		HitCount = 0,
		LastHit = 0,
		Weakpoint = nil,
	}

	occupied[spawnPart] = true
	rock.Parent = oresFolder
	return rock
end

-- 희귀 노드 무리(스폰 파트 속성 RandomPool)에서 비어 있는 자리 하나에 노드를 만든다
-- avoid를 주면 다른 빈 자리가 있는 한 그 자리는 고르지 않는다 (방금 벤 자리)
local function spawnInPool(poolName: string, avoid: BasePart?)
	local free = {}
	for _, part in pools[poolName] or {} do
		if not occupied[part] and part.Parent and part ~= avoid then
			table.insert(free, part)
		end
	end
	if #free == 0 and avoid and not occupied[avoid] and avoid.Parent then
		table.insert(free, avoid)
	end
	if #free > 0 then
		spawnRock(free[random:NextInteger(1, #free)])
	end
end

-- 서버 시작 시 한 번 호출. 모든 스폰 파트에 바위를 만든다
function OreService.init()
	local templates = ServerStorage:WaitForChild("Templates"):WaitForChild("Ores")
	assert(templates:IsA("Folder"), "ServerStorage/Templates/Ores는 Folder여야 한다")
	-- 각 광석은 Templates/Ores/<TemplateName> 폴더 안에 모양 변형 모델을 여러 개 둔다 (모델 하나여도 된다)
	templatesFolder = templates

	local existing = Workspace:FindFirstChild("Ores")
	if existing and existing:IsA("Folder") then
		oresFolder = existing
	else
		oresFolder = Instance.new("Folder")
		oresFolder.Name = "Ores"
		oresFolder.Parent = Workspace
	end

	local spawns = Workspace:WaitForChild("OreSpawns")
	groundParams.FilterDescendantsInstances = { oresFolder, spawns }
	local spawned = 0
	local skipped: { [string]: number } = {} -- 아직 정의가 없는 광석 종류별 건너뛴 개수
	for _, child in spawns:GetChildren() do
		local poolName = child:GetAttribute("RandomPool")
		if child:IsA("BasePart") and typeof(poolName) == "string" then
			-- 희귀 노드 후보 자리: 바로 만들지 않고 무리에 모았다가 Active개만 뽑는다
			pools[poolName] = pools[poolName] or {}
			table.insert(pools[poolName], child)
		elseif child:IsA("BasePart") then
			if spawnRock(child) then
				spawned += 1
			else
				local oreType = tostring(child:GetAttribute("OreType"))
				skipped[oreType] = (skipped[oreType] or 0) + 1
			end
		end
	end

	for poolName, parts in pools do
		local poolConfig = Config.RandomPools[poolName]
		for _ = 1, math.min(if poolConfig then poolConfig.Active else 1, #parts) do
			spawnInPool(poolName)
		end
		print(`[OreService] 희귀 무리 {poolName}: 후보 {#parts}곳`)
	end

	print(`[OreService] 바위 {spawned}개 생성`)

	-- 자연 회복: 한동안 안 맞은 바위·나무는 천천히 찬다
	task.spawn(function()
		local step = 0.5
		while true do
			task.wait(step)
			local now = os.clock()
			for rock, state in states do
				if not state.Depleted and state.Hp < state.MaxHp and now - state.LastHit >= Config.Regen.Delay then
					state.Hp = math.min(state.MaxHp, state.Hp + state.MaxHp * Config.Regen.NodePercentPerSecond * step)
					rock:SetAttribute("Hp", math.floor(state.Hp * 10 + 0.5) / 10)
					if state.Hp >= state.MaxHp then
						state.Contributions = {} -- 다 찼으면 기여도도 처음부터
						state.Judgments = {}
					end
				end
			end
		end
	end)
	for oreType, count in skipped do
		-- MVP-0은 돌만 쓰므로 다른 종류는 정의·템플릿이 생길 때까지 건너뛴다
		print(`[OreService] OreType={oreType} 스폰 {count}개 건너뜀 (OreDefs·Config·템플릿 중 없음)`)
	end
end

-- 바위의 서버 상태를 가져온다. 바위가 아니거나 이미 제거됐으면 nil
function OreService.getState(rock: Instance): RockState?
	if not rock:IsA("Model") then
		return nil
	end
	return states[rock]
end

-- 바위에 데미지를 준다. 이번 타격으로 HP가 0이 됐으면 true.
-- 바위를 실제로 제거하는 건 호출하는 쪽이 breakRock으로 한다 (피버 연출 동안 남겨 두기 위해)
-- 검증(거리·쿨다운 등)은 호출하는 쪽(MiningService)이 끝낸 뒤 부른다
function OreService.applyDamage(rock: Model, player: Player, damage: number): boolean
	local state = states[rock]
	if not state or state.Depleted or damage <= 0 then
		return false
	end

	-- 넘친 데미지는 기여도에 넣지 않는다 (남은 HP만큼만 인정)
	local dealt = math.min(damage, state.Hp)
	state.Hp -= dealt
	state.HitCount += 1
	state.LastHit = os.clock()
	state.Contributions[player.UserId] = (state.Contributions[player.UserId] or 0) + dealt
	rock:SetAttribute("Hp", state.Hp)

	if state.Hp <= 0 then
		state.Depleted = true
		return true
	end
	return false
end

-- 플레이어의 판정 기록을 남긴다 (Nice·Perfect만 센다)
function OreService.recordJudgment(rock: Model, player: Player, judgment: string)
	local state = states[rock]
	if not state then
		return
	end
	local counts = state.Judgments[player.UserId]
	if not counts then
		counts = { Nice = 0, Perfect = 0 }
		state.Judgments[player.UserId] = counts
	end
	if judgment == "Perfect" then
		counts.Perfect += 1
	elseif judgment == "Nice" then
		counts.Nice += 1
	end
end

-- 바위를 제거하고 같은 자리에 리스폰을 예약한다
function OreService.breakRock(state: RockState)
	if states[state.Rock] ~= state then
		return
	end
	states[state.Rock] = nil
	state.Rock:Destroy()

	local spawnPart = state.SpawnPart
	occupied[spawnPart] = nil
	local poolName = spawnPart:GetAttribute("RandomPool")
	task.delay(Config.Ores[state.OreType].RespawnTime, function()
		if typeof(poolName) == "string" then
			-- 희귀 노드는 같은 자리가 아니라 무리 안의 다른 빈 자리에 다시 생긴다
			spawnInPool(poolName, spawnPart)
		elseif spawnPart.Parent then
			-- 리스폰 대기 중에 스폰 파트가 지워졌으면 다시 만들지 않는다
			spawnRock(spawnPart)
		end
	end)
end

return OreService
