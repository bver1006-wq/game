--!strict
-- 지도 그림에 쓸 자료 모으기 (클라이언트 전용). 처음 지도를 열 때 한 번 계산해서 기억해 둔다.
--   밖: 마을·NPC·나무·몹 자리로 맵 범위를 잡고, 지형에 아래로 성긴 격자 광선을 쏴서
--       칸마다 종류(물·풀·흙·길·모래·바위·눈)와 높이를 안다
--   광산: 층의 BatWaypoints(칸 중심 경로점, 속성 Index·Links)로 6x6 미로 격자를 만들고,
--       이웃한 두 칸 사이를 바닥 + WallRayHeight 높이에서 옆으로 광선을 쏴 지형에 막히면 벽으로 본다.
--       바닥을 못 찾으면(지형이 아직 안 보임 등) Links(통로로 이어진 칸)로 대신 판단한다.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

export type Sample = { Class: string?, Height: number }
export type TerrainSamples = {
	Min: Vector2, -- 격자 왼쪽 위 (월드 X, Z)
	Step: number,
	Cols: number,
	Rows: number,
	Grid: { { Sample } }, -- Grid[줄(Z)][칸(X)]
	BaseHeight: number, -- 땅 높이 가운데 값 (언덕 판단 기준)
}
export type Bounds = { Min: Vector2, Max: Vector2 } -- 월드 X, Z
export type MazeCell = { Col: number, Row: number, Index: number, Position: Vector3 }
export type Maze = {
	Floor: number,
	Spacing: number,
	Cols: number,
	Rows: number,
	Origin: Vector2, -- (0, 0) 칸 중심의 월드 X, Z
	FloorY: number, -- 층 바닥 높이 (대략)
	Cells: { [number]: MazeCell }, -- 키 = MapData.cellKey(칸, 줄)
	ByIndex: { [number]: MazeCell }, -- 경로점 Index → 칸
	OpenEast: { [number]: boolean }, -- 그 칸과 오른쪽(동쪽) 칸 사이가 뚫렸는지
	OpenSouth: { [number]: boolean }, -- 그 칸과 아래쪽(남쪽, +Z) 칸 사이가 뚫렸는지
}

local MapData = {}

local MATERIAL_CLASS: { [Enum.Material]: string } = {
	[Enum.Material.Water] = "Water",
	[Enum.Material.Grass] = "Grass",
	[Enum.Material.LeafyGrass] = "Grass",
	[Enum.Material.Ground] = "Dirt",
	[Enum.Material.Mud] = "Dirt",
	[Enum.Material.Sand] = "Sand",
	[Enum.Material.Sandstone] = "Sand",
	[Enum.Material.Salt] = "Sand",
	[Enum.Material.Rock] = "Rock",
	[Enum.Material.Slate] = "Rock",
	[Enum.Material.Basalt] = "Rock",
	[Enum.Material.Granite] = "Rock",
	[Enum.Material.Limestone] = "Rock",
	[Enum.Material.CrackedLava] = "Rock",
	[Enum.Material.Cobblestone] = "Path",
	[Enum.Material.Pavement] = "Path",
	[Enum.Material.Brick] = "Path",
	[Enum.Material.Asphalt] = "Path",
	[Enum.Material.Concrete] = "Path",
	[Enum.Material.WoodPlanks] = "Path",
	[Enum.Material.Snow] = "Snow",
	[Enum.Material.Glacier] = "Snow",
	[Enum.Material.Ice] = "Snow",
}

local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = { Workspace.Terrain }

local samplesCache: TerrainSamples? = nil
local sampling = false
local boundsCache: Bounds? = nil
local mazeCache: { [number]: Maze } = {}

-- 칸 번호 (칸 = X 방향, 줄 = Z 방향)
function MapData.cellKey(col: number, row: number): number
	return row * 1000 + col
end

-- 부품이나 모델의 위치
function MapData.positionOf(instance: Instance): Vector3?
	if instance:IsA("BasePart") then
		return instance.Position
	elseif instance:IsA("Model") then
		return instance:GetPivot().Position
	end
	return nil
end

-- 밖(지상) 것인지: 지하로 옮긴 광산 층은 아주 낮다
function MapData.isSurface(position: Vector3): boolean
	return position.Y > Config.Minimap.SurfaceMinY
end

-- 밖 지도 범위: 마을·NPC·광산 입구·나무·바위 자리·몹 자리를 모두 담는 네모 + 여유
function MapData.worldBounds(): Bounds
	if boundsCache then
		return boundsCache
	end
	local minV = Vector2.new(math.huge, math.huge)
	local maxV = Vector2.new(-math.huge, -math.huge)
	local count = 0
	local function add(position: Vector3?)
		if position and MapData.isSurface(position) then
			local flat = Vector2.new(position.X, position.Z)
			minV = minV:Min(flat)
			maxV = maxV:Max(flat)
			count += 1
		end
	end
	for _, tag in { "TownArrival", "ShopNPC", "MinePortal" } do
		for _, instance in CollectionService:GetTagged(tag) do
			add(MapData.positionOf(instance))
		end
	end
	for _, folderName in { "OreSpawns", "MobSpawns" } do
		local folder = Workspace:FindFirstChild(folderName)
		if folder then
			for _, child in folder:GetChildren() do
				-- 광산 층 광석 자리(속성 Floor 1 이상)는 빼고
				local floor = child:GetAttribute("Floor")
				if not (typeof(floor) == "number" and floor >= 1) then
					add(MapData.positionOf(child))
				end
			end
		end
	end
	if count < 2 then
		-- 아무것도 못 찾으면 마을(또는 원점) 둘레 맵 반경
		local town = CollectionService:GetTagged("TownArrival")[1]
		local center = if town then MapData.positionOf(town) or Vector3.zero else Vector3.zero
		local radius = Config.WorldTiers.MapRadius
		minV = Vector2.new(center.X - radius, center.Z - radius)
		maxV = Vector2.new(center.X + radius, center.Z + radius)
	end
	local margin = Vector2.new(Config.Minimap.WorldMargin, Config.Minimap.WorldMargin)
	local bounds: Bounds = { Min = minV - margin, Max = maxV + margin }
	boundsCache = bounds
	return bounds
end

-- 밖 지형 격자 (처음 한 번만 광선을 쏜다. 여러 프레임에 나눠 쏘므로 기다릴 수 있다)
function MapData.sampleTerrain(bounds: Bounds): TerrainSamples
	while sampling do
		task.wait()
	end
	if samplesCache then
		return samplesCache
	end
	sampling = true
	local cfg = Config.Minimap
	local extent = bounds.Max - bounds.Min
	local step = math.max(cfg.SampleStep, math.max(extent.X, extent.Y) / cfg.MaxSamplesPerSide)
	local cols = math.max(1, math.ceil(extent.X / step))
	local rows = math.max(1, math.ceil(extent.Y / step))
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace.Terrain }
	params.IgnoreWater = false
	local grid: { { Sample } } = {}
	local landHeights: { number } = {}
	local shot = 0
	for row = 1, rows do
		local line: { Sample } = {}
		local z = bounds.Min.Y + (row - 0.5) * step
		for col = 1, cols do
			local x = bounds.Min.X + (col - 0.5) * step
			local result = Workspace:Raycast(Vector3.new(x, cfg.SampleTop, z), Vector3.new(0, -(cfg.SampleTop - cfg.SurfaceMinY), 0), params)
			if result then
				local class = MATERIAL_CLASS[result.Material] or "Grass"
				line[col] = { Class = class, Height = result.Position.Y }
				if class ~= "Water" then
					table.insert(landHeights, result.Position.Y)
				end
			else
				line[col] = { Class = nil, Height = 0 }
			end
			shot += 1
			if shot % cfg.SamplesPerFrame == 0 then
				task.wait()
			end
		end
		grid[row] = line
	end
	table.sort(landHeights)
	local base = if #landHeights > 0 then landHeights[math.max(1, math.floor(#landHeights / 2))] else 0
	local samples: TerrainSamples = {
		Min = bounds.Min,
		Step = step,
		Cols = cols,
		Rows = rows,
		Grid = grid,
		BaseHeight = base,
	}
	samplesCache = samples
	sampling = false
	return samples
end

-- 경로점 아래 바닥 높이 (지형)
local function findFloor(position: Vector3): number?
	local result = Workspace:Raycast(position + Vector3.new(0, 1, 0), Vector3.new(0, -Config.Minimap.FloorSearch, 0), terrainParams)
	return if result then result.Position.Y else nil
end

-- 옆으로 광선 한 번: 막히면 true
local function blocked(from: Vector3, to: Vector3): boolean
	local direction = to - from
	return Workspace:Raycast(from, direction, terrainParams) ~= nil
end

-- 두 칸 사이가 뚫렸는지. 바닥을 찾았으면 광선으로, 못 찾았으면 Links로 판단. 두 번째 값 = 광선으로 확인했는지
local function isOpen(a: MazeCell, b: MazeCell, linked: boolean, hasLinks: boolean): (boolean, boolean)
	local floorA = findFloor(a.Position)
	local floorB = findFloor(b.Position)
	if not floorA or not floorB then
		return if hasLinks then linked else true, false
	end
	local y = math.max(floorA, floorB) + Config.Minimap.WallRayHeight
	local fromLow = Vector3.new(a.Position.X, y, a.Position.Z)
	local toLow = Vector3.new(b.Position.X, y, b.Position.Z)
	if not blocked(fromLow, toLow) then
		return true, true
	end
	-- 낮게는 막혔지만 Links로 이어져 있으면 턱·계단일 수 있으니 조금 더 높게 한 번 더
	if linked then
		local lift = Vector3.new(0, Config.Minimap.WallRayHeight + 2, 0)
		if not blocked(fromLow + lift, toLow + lift) then
			return true, true
		end
	end
	return false, true
end

-- 이 층의 미로 (칸·벽). 층 모델이 없으면 nil. 광선으로 다 확인했으면 기억해 두고 다시 계산하지 않는다
function MapData.getMaze(floor: number): Maze?
	local cached = mazeCache[floor]
	if cached then
		return cached
	end
	local mine = Workspace:FindFirstChild("Mine")
	local floorModel = mine and mine:FindFirstChild("Floor" .. floor)
	local folder = floorModel and floorModel:FindFirstChild("BatWaypoints")
	if not folder then
		return nil
	end
	-- 경로점 읽기
	type Node = { Index: number, Position: Vector3, Links: { [number]: boolean } }
	local nodes: { Node } = {}
	local hasLinks = false
	for _, wp in folder:GetChildren() do
		local index = wp:GetAttribute("Index")
		if wp:IsA("BasePart") and typeof(index) == "number" then
			local links: { [number]: boolean } = {}
			local raw = wp:GetAttribute("Links")
			if typeof(raw) == "string" then
				for token in string.gmatch(raw, "%d+") do
					links[tonumber(token) :: number] = true
					hasLinks = true
				end
			end
			table.insert(nodes, { Index = index, Position = wp.Position, Links = links })
		end
	end
	if #nodes == 0 then
		return nil
	end
	-- 칸 간격 = 경로점 사이 가장 짧은 수평 거리
	local spacing = math.huge
	for i = 1, #nodes do
		for j = i + 1, #nodes do
			local d = ((nodes[i].Position - nodes[j].Position) * Vector3.new(1, 0, 1)).Magnitude
			if d > 4 and d < spacing then
				spacing = d
			end
		end
	end
	if spacing == math.huge then
		spacing = 24
	end
	local minX, minZ, sumY = math.huge, math.huge, 0
	for _, node in nodes do
		minX = math.min(minX, node.Position.X)
		minZ = math.min(minZ, node.Position.Z)
		sumY += node.Position.Y
	end
	-- 격자에 놓기
	local cells: { [number]: MazeCell } = {}
	local byIndex: { [number]: MazeCell } = {}
	local linksOf: { [number]: { [number]: boolean } } = {}
	local cols, rows = 0, 0
	for _, node in nodes do
		local col = math.floor((node.Position.X - minX) / spacing + 0.5)
		local row = math.floor((node.Position.Z - minZ) / spacing + 0.5)
		local key = MapData.cellKey(col, row)
		if not cells[key] then
			local cell: MazeCell = { Col = col, Row = row, Index = node.Index, Position = node.Position }
			cells[key] = cell
			byIndex[node.Index] = cell
			linksOf[node.Index] = node.Links
			cols = math.max(cols, col + 1)
			rows = math.max(rows, row + 1)
		end
	end
	-- 이웃 칸 사이 벽 확인
	local openEast: { [number]: boolean } = {}
	local openSouth: { [number]: boolean } = {}
	local complete = true
	local floorSum, floorCount = 0, 0
	local function linkedBetween(a: MazeCell, b: MazeCell): boolean
		local la = linksOf[a.Index]
		local lb = linksOf[b.Index]
		return (la ~= nil and la[b.Index] == true) or (lb ~= nil and lb[a.Index] == true)
	end
	for key, cell in cells do
		local y = findFloor(cell.Position)
		if y then
			floorSum += y
			floorCount += 1
		end
		for _, dir in { { 1, 0 }, { 0, 1 } } do
			local other = cells[MapData.cellKey(cell.Col + dir[1], cell.Row + dir[2])]
			if other then
				local open, checked = isOpen(cell, other, linkedBetween(cell, other), hasLinks)
				if not checked then
					complete = false
				end
				if dir[1] == 1 then
					openEast[key] = open
				else
					openSouth[key] = open
				end
			end
		end
	end
	local maze: Maze = {
		Floor = floor,
		Spacing = spacing,
		Cols = cols,
		Rows = rows,
		Origin = Vector2.new(minX, minZ),
		FloorY = if floorCount > 0 then floorSum / floorCount else sumY / #nodes,
		Cells = cells,
		ByIndex = byIndex,
		OpenEast = openEast,
		OpenSouth = openSouth,
	}
	if complete then
		mazeCache[floor] = maze
	end
	return maze
end

-- 이 층 미로를 광선으로 다 확인해서 기억해 두었는지
function MapData.isMazeCached(floor: number): boolean
	return mazeCache[floor] ~= nil
end

-- 미로에서 이 위치와 가장 가까운 칸과 수평 거리
function MapData.nearestCell(maze: Maze, position: Vector3): (MazeCell?, number)
	local col = math.floor((position.X - maze.Origin.X) / maze.Spacing + 0.5)
	local row = math.floor((position.Z - maze.Origin.Y) / maze.Spacing + 0.5)
	local cell = maze.Cells[MapData.cellKey(col, row)]
	if not cell then
		return nil, math.huge
	end
	local center = Vector2.new(maze.Origin.X + col * maze.Spacing, maze.Origin.Y + row * maze.Spacing)
	return cell, (Vector2.new(position.X, position.Z) - center).Magnitude
end

return MapData
