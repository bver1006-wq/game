--!nocheck
-- 광산 층(Workspace/Mine/Floor1~)을 지하로 옮긴다. 바다 위에서 동굴 지형이 보이던 문제를 없앤다 (2026-10-09 사용자 요청).
-- 서버(Main.server)가 게임을 시작할 때 다른 서비스보다 먼저 실행한다. 편집 상태에서 직접 실행해 저장해도 된다:
--   require(game.ServerStorage.StudioTools.MoveMineUnderground:Clone())
-- 이미 옮겼으면(Mine 속성 MovedUnderground) 아무것도 하지 않는다.
--
-- 옮기는 것
--   - 층 모델 (BatWaypoints 포함)
--   - 층 범위 안에 있는 다른 부품 (OreSpawns의 광석 자리, MinePortal·MineArrival·MineZone 등)
--   - 층 범위의 지형: 복사 → 아래에 붙여 넣기 → 원래 자리의 돌·흙만 지운다 (바닷물은 그대로)
-- 맨 아래가 FallenPartsDestroyHeight(기본 -500)보다 위에 오도록 깊이를 정한다.

local Workspace = game:GetService("Workspace")

local TOP_TARGET = -120 -- 옮긴 뒤 층들의 맨 위 높이(스터드)
local MARGIN = 16 -- 층 모델 둘레로 함께 옮길 여유(스터드)
local VOXEL = 4

local mine = Workspace:FindFirstChild("Mine")
if not mine then
	warn("[MoveMineUnderground] Workspace/Mine이 없어요")
	return true
end
if mine:GetAttribute("MovedUnderground") then
	return true
end

-- 지하로 보낼 층 모델들 (Floor0은 지상 입구라 그대로)
local floors = {}
for _, child in mine:GetChildren() do
	local number = tonumber(string.match(child.Name, "^Floor(%d+)$"))
	if child:IsA("Model") and number and number >= 1 then
		table.insert(floors, child)
	end
end
if #floors == 0 then
	warn("[MoveMineUnderground] 층 모델(Floor1~)이 없어요")
	return true
end

-- 축 정렬 범위 (부품 모서리 기준)
local function boundsOf(model: Model): (Vector3, Vector3)
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = -minV
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local half = Vector3.new(
				math.abs(d.CFrame.RightVector.X) * d.Size.X + math.abs(d.CFrame.UpVector.X) * d.Size.Y + math.abs(d.CFrame.LookVector.X) * d.Size.Z,
				math.abs(d.CFrame.RightVector.Y) * d.Size.X + math.abs(d.CFrame.UpVector.Y) * d.Size.Y + math.abs(d.CFrame.LookVector.Y) * d.Size.Z,
				math.abs(d.CFrame.RightVector.Z) * d.Size.X + math.abs(d.CFrame.UpVector.Z) * d.Size.Y + math.abs(d.CFrame.LookVector.Z) * d.Size.Z
			) / 2
			minV = minV:Min(d.Position - half)
			maxV = maxV:Max(d.Position + half)
		end
	end
	return minV, maxV
end

local boxes = {}
local topY, bottomY = -math.huge, math.huge
for _, floor in floors do
	local minV, maxV = boundsOf(floor)
	minV -= Vector3.new(MARGIN, MARGIN, MARGIN)
	maxV += Vector3.new(MARGIN, MARGIN, MARGIN)
	table.insert(boxes, { Min = minV, Max = maxV })
	topY = math.max(topY, maxV.Y)
	bottomY = math.min(bottomY, minV.Y)
end

-- 깊이: 맨 위가 TOP_TARGET에 오게, 지형 칸(4스터드) 단위로. 너무 깊으면 FallenPartsDestroyHeight 위로 올린다
local offsetY = math.floor((TOP_TARGET - topY) / VOXEL) * VOXEL
local destroyHeight = Workspace.FallenPartsDestroyHeight
if bottomY + offsetY < destroyHeight + 40 then
	offsetY = math.ceil((destroyHeight + 40 - bottomY) / VOXEL) * VOXEL
end
if offsetY >= 0 then
	mine:SetAttribute("MovedUnderground", true)
	return true -- 이미 충분히 아래에 있다
end
local offset = Vector3.new(0, offsetY, 0)

local function inside(position: Vector3): boolean
	for _, box in boxes do
		if position.X >= box.Min.X and position.X <= box.Max.X and position.Y >= box.Min.Y and position.Y <= box.Max.Y and position.Z >= box.Min.Z and position.Z <= box.Max.Z then
			return true
		end
	end
	return false
end

-- 1. 지형: 층 범위마다 복사해서 아래에 붙여 넣고, 원래 자리의 단단한 지형은 공기로
local terrain = Workspace.Terrain
local SOLID = {}
for _, material in Enum.Material:GetEnumItems() do
	if material ~= Enum.Material.Air and material ~= Enum.Material.Water then
		local ok = pcall(function()
			terrain:GetMaterialColor(material)
		end)
		if ok then
			table.insert(SOLID, material)
		end
	end
end
for _, box in boxes do
	local cellMin = Vector3int16.new(math.floor(box.Min.X / VOXEL), math.floor(box.Min.Y / VOXEL), math.floor(box.Min.Z / VOXEL))
	local cellMax = Vector3int16.new(math.ceil(box.Max.X / VOXEL), math.ceil(box.Max.Y / VOXEL), math.ceil(box.Max.Z / VOXEL))
	local ok, err = pcall(function()
		local copied = terrain:CopyRegion(Region3int16.new(cellMin, cellMax))
		terrain:PasteRegion(copied, Vector3int16.new(cellMin.X, cellMin.Y + offsetY / VOXEL, cellMin.Z), true)
		local region = Region3.new(Vector3.new(cellMin.X, cellMin.Y, cellMin.Z) * VOXEL, Vector3.new(cellMax.X + 1, cellMax.Y + 1, cellMax.Z + 1) * VOXEL)
		for _, material in SOLID do
			terrain:ReplaceMaterial(region, VOXEL, material, Enum.Material.Air)
		end
	end)
	if not ok then
		warn(`[MoveMineUnderground] 지형 옮기기 실패: {err}`)
	end
end

-- 2. 층 범위 안의 다른 부품 (광석 자리·입구·도착점·구역 등). 층 모델·캐릭터는 빼고
local moved = 0
local function isInFloor(instance: Instance): boolean
	for _, floor in floors do
		if instance:IsDescendantOf(floor) then
			return true
		end
	end
	return false
end
for _, d in Workspace:GetDescendants() do
	if d:IsA("BasePart") and not d:IsA("Terrain") and d.Anchored and not isInFloor(d) and inside(d.Position) then
		local model = d:FindFirstAncestorOfClass("Model")
		local isCharacter = model and model:FindFirstChildOfClass("Humanoid") ~= nil
		if not isCharacter then
			d.CFrame += offset
			moved += 1
		end
	end
end

-- 3. 층 모델
for _, floor in floors do
	floor:PivotTo(floor:GetPivot() + offset)
end

mine:SetAttribute("MovedUnderground", true)
print(`[MoveMineUnderground] 광산 {#floors}개 층을 {-offsetY}스터드 아래로 옮겼어요 (다른 부품 {moved}개)`)
return true
