--!strict
-- 손그림 지도 ("지도" 버튼 또는 M 키). 북쪽(-Z)이 위. (2026-10-09 손그림 지도로 바뀜)
--   큰 지도: 화면 가운데 창. ✕로 닫고, "작게"를 누르면 오른쪽 위 작은 지도(내 위치가 가운데)로, 작은 지도를 누르면 다시 크게
--   밖: 양피지 위에 지형(물·풀·모래·바위·흙길), 언덕 ^, 나무·집 그림, 몹 구역, NPC(아이콘 + 이름), 광산 입구
--   광산: 그 층 미로 벽 전체, 안 가 본 칸은 어둡게, 출구 ↑ · 아래층 ↓ · 잠긴 층 🔒
-- 자료(지형 격자·미로 벽)는 MapData가 처음 열 때 한 번 계산해 기억한다.
-- 그림은 층이 바뀌거나 화면 크기가 바뀔 때만 다시 그리고, 매 프레임은 화살표·다른 플레이어 점만 옮긴다.
-- 가 본 칸 기록은 이 클라이언트에만 남는다 (저장 없음).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local OreDefs = require(ReplicatedStorage.Shared.OreDefs)
local ShopDefs = require(ReplicatedStorage.Shared.ShopDefs)
local MapData = require(script.Parent.MapData)
local MineAtmosphereController = require(script.Parent.MineAtmosphereController)
local UiKit = require(script.Parent.UiKit)

local TOGGLE_KEY = Enum.KeyCode.M
local SLOW_TICK = 0.25 -- 가 본 칸 확인 간격(초)
local COLORS = Config.Minimap.Colors

type Mode = "Closed" | "Big" | "Small"
type Rect = { Min: Vector2, Max: Vector2 }

local localPlayer = Players.LocalPlayer

local MinimapController = {}

-- 화면 요소
local gui: ScreenGui
local openButton: TextButton
local panel: Frame -- 큰 지도 창
local titleLabel: TextLabel
local content: Frame -- 큰 지도 그림 자리
local vignette: { Frame } = {}
local corner: TextButton -- 작은 지도
local cornerNorth: TextLabel
local canvas: Frame -- 지도 그림 전체 (큰 지도·작은 지도가 함께 쓴다)
local canvasScale: UIScale
local loadingLabel: TextLabel
local layers: { [string]: Frame } = {}
local arrow: TextLabel
local otherDots: { [Player]: Frame } = {}

-- 상태
local mode: Mode = "Closed"
local drawnKey = "" -- 무엇을 어떤 크기로 그렸는지 (바뀌면 다시 그림)
local generation = 0 -- 그리기 차례 번호 (늦게 끝난 옛 그리기는 버린다)
local ready = false -- 그림이 다 그려졌는지
local viewFloor: number? = nil -- 지금 그림의 층 (nil이면 밖)
local viewMaze: MapData.Maze? = nil
local viewScale = 1 -- 1스터드당 픽셀
local viewMin = Vector2.zero -- 그림 왼쪽 위의 월드 X, Z
local viewPad = 0
local canvasSize = Vector2.new(300, 300)
local placed: { Rect } = {} -- 글자·아이콘 자리 (겹치지 않게)
local visited: { [number]: { [number]: boolean } } = {} -- 층 → 칸 번호(경로점 Index) → 가 봤는지
local fogFrames: { [number]: Frame } = {} -- 칸 번호 → 어둡게 덮는 네모
local lastSlow = 0
local lastRocks = 0

-- 월드 좌표 → 그림 픽셀
local function toCanvas(position: Vector3): Vector2
	return Vector2.new((position.X - viewMin.X) * viewScale + viewPad, (position.Z - viewMin.Y) * viewScale + viewPad)
end

-- 네모 하나 (가운데 기준)
local function rect(parent: Instance, center: Vector2, size: Vector2, color: Color3, transparency: number?): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromOffset(center.X, center.Y)
	frame.Size = UDim2.fromOffset(size.X, size.Y)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency or 0
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

-- 둥근 모서리 (scale 0.5면 알약·동그라미)
local function round(frame: GuiObject, scale: number?, offset: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale or 0.5, offset or 0)
	c.Parent = frame
end

-- 테두리 선 (글자가 아니라 상자 테두리)
local function outline(frame: GuiObject, color: Color3, thickness: number, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = frame
end

-- 손글씨 같은 글자 (가운데 기준, 크기는 글자에 맞춰 저절로)
local function ink(parent: Instance, text: string, center: Vector2, size: number, color: Color3?, strokeColor: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromOffset(center.X, center.Y)
	label.Size = UDim2.fromOffset(0, 0)
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.BackgroundTransparency = 1
	label.Font = Config.Minimap.Font
	label.Text = text
	label.TextSize = size
	label.TextColor3 = color or COLORS.Ink
	label.TextStrokeColor3 = strokeColor or COLORS.InkLight
	label.TextStrokeTransparency = 0.25
	label.Parent = parent
	return label
end

-- 글자 폭 어림 (한글은 글자 크기만큼, 영문·기호는 조금 좁게)
local function textWidth(text: string, size: number): number
	local width = 0
	for _, code in utf8.codes(text) do
		width += if code > 0x2000 then size else size * 0.6
	end
	return width
end

-- 두 네모가 겹치는지
local function overlaps(a: Rect, b: Rect): boolean
	return a.Min.X < b.Max.X and a.Max.X > b.Min.X and a.Min.Y < b.Max.Y and a.Max.Y > b.Min.Y
end

-- 자리 등록 (다음 글자가 피해 간다)
local function reserve(center: Vector2, size: Vector2)
	table.insert(placed, { Min = center - size / 2, Max = center + size / 2 })
end

-- 아이콘 옆에 이름 글자: 아래 → 위 → 오른쪽 → 왼쪽 중 다른 글자와 안 겹치는 곳
local function placeLabel(text: string, anchor: Vector2, radius: number, size: number, color: Color3?): TextLabel
	local box = Vector2.new(textWidth(text, size) + 4, size + 4)
	local candidates = {
		Vector2.new(0, radius + box.Y / 2 + 1),
		Vector2.new(0, -(radius + box.Y / 2 + 1)),
		Vector2.new(radius + box.X / 2 + 2, 0),
		Vector2.new(-(radius + box.X / 2 + 2), 0),
		Vector2.new(0, radius + box.Y * 1.5 + 2),
		Vector2.new(0, -(radius + box.Y * 1.5 + 2)),
	}
	local chosen = anchor + candidates[1]
	for _, offset in candidates do
		local center = anchor + offset
		local candidate: Rect = { Min = center - box / 2, Max = center + box / 2 }
		local inside = candidate.Min.X >= 0 and candidate.Min.Y >= 0 and candidate.Max.X <= canvasSize.X and candidate.Max.Y <= canvasSize.Y
		local free = inside
		if free then
			for _, other in placed do
				if overlaps(candidate, other) then
					free = false
					break
				end
			end
		end
		if free then
			chosen = center
			break
		end
	end
	reserve(chosen, box)
	return ink(layers.Labels, text, chosen, size, color)
end

-- 그림을 모두 지운다
local function clearCanvas()
	for _, layer in layers do
		for _, child in layer:GetChildren() do
			child:Destroy()
		end
	end
	table.clear(placed)
	table.clear(fogFrames)
	for _, dot in otherDots do
		dot:Destroy()
	end
	table.clear(otherDots)
	ready = false
end

-- 그림 크기·배율 정하기: 큰 지도 창에 맞게 (extent = 월드 크기 X, Z)
local function layout(extent: Vector2, maxScale: number)
	local cfg = Config.Minimap
	local screen = gui.AbsoluteSize
	local maxW = math.max(200, screen.X * cfg.MaxWidthFraction - 12)
	local maxH = math.max(160, screen.Y * cfg.HeightFraction - cfg.TitleHeight - 8)
	viewPad = cfg.Padding
	viewScale = math.min((maxW - 2 * viewPad) / math.max(extent.X, 1), (maxH - 2 * viewPad) / math.max(extent.Y, 1), maxScale)
	viewScale = math.max(viewScale, 0.05)
	canvasSize = extent * viewScale + Vector2.new(2 * viewPad, 2 * viewPad)
	canvas.Size = UDim2.fromOffset(canvasSize.X, canvasSize.Y)
	content.Size = UDim2.fromOffset(canvasSize.X, canvasSize.Y)
	panel.Size = UDim2.fromOffset(canvasSize.X + 12, canvasSize.Y + cfg.TitleHeight + 8)
end

-- 큰 지도 배경 색 (양피지 / 어두운 돌)
local function setTheme(cave: boolean)
	local back = if cave then COLORS.CaveBackground else COLORS.Parchment
	content.BackgroundColor3 = back
	corner.BackgroundColor3 = back
	panel.BackgroundColor3 = if cave then COLORS.CaveWall else COLORS.ParchmentEdge
	for _, edge in vignette do
		edge.BackgroundColor3 = if cave then Color3.new(0, 0, 0) else COLORS.ParchmentEdge
	end
	cornerNorth.TextColor3 = if cave then COLORS.InkLight else COLORS.Ink
end

----------------------------------------------------------------------
-- 밖 지도
----------------------------------------------------------------------

-- 지형: 줄마다 같은 종류가 이어진 구간을 둥근 띠 하나로 (위아래 줄과 겹쳐서 손으로 칠한 덩어리처럼)
local function drawTerrain(samples: MapData.TerrainSamples, rng: Random)
	local stepPx = samples.Step * viewScale
	for row = 1, samples.Rows do
		local line = samples.Grid[row]
		local col = 1
		while col <= samples.Cols do
			local class = line[col].Class
			local finish = col
			while finish + 1 <= samples.Cols and line[finish + 1].Class == class do
				finish += 1
			end
			if class then
				local color = (COLORS :: any)[class] :: Color3?
				if color then
					local x0 = samples.Min.X + (col - 1) * samples.Step
					local x1 = samples.Min.X + finish * samples.Step
					local z = samples.Min.Y + (row - 0.5) * samples.Step
					local center = toCanvas(Vector3.new((x0 + x1) / 2, 0, z)) + Vector2.new(0, rng:NextNumber(-0.1, 0.1) * stepPx)
					local thick = if class == "Path" then 0.9 else rng:NextNumber(1.3, 1.6)
					local band = rect(layers.Terrain, center, Vector2.new((x1 - x0) * viewScale + stepPx * 0.5, stepPx * thick), color)
					round(band)
				end
			end
			col = finish + 1
		end
	end
end

-- 물결 ~ 와 언덕 ^
local function drawDoodles(samples: MapData.TerrainSamples, rng: Random)
	local cfg = Config.Minimap
	local stepPx = samples.Step * viewScale
	local waves, hills = 0, 0
	for row = 1, samples.Rows do
		for col = 1, samples.Cols do
			local sample = samples.Grid[row][col]
			local world = Vector3.new(samples.Min.X + (col - 0.5) * samples.Step, 0, samples.Min.Y + (row - 0.5) * samples.Step)
			if sample.Class == "Water" then
				local right = samples.Grid[row][col + 1]
				if waves < 70 and right and right.Class == "Water" and rng:NextNumber() < cfg.WaveChance then
					waves += 1
					local wave = ink(layers.Deco, "~", toCanvas(world) + Vector2.new(stepPx / 2, 0), math.clamp(stepPx * 1.6, 12, 22), COLORS.WaterLine, COLORS.Water)
					wave.TextStrokeTransparency = 1
				end
			elseif sample.Class and row % cfg.HillStride == 0 and col % cfg.HillStride == 0 and hills < 90 then
				local rise = sample.Height - samples.BaseHeight
				if rise >= cfg.HillHeight then
					hills += 1
					local big = rise >= cfg.MountainHeight
					local jitter = Vector2.new(rng:NextNumber(-0.5, 0.5), rng:NextNumber(-0.5, 0.5)) * stepPx
					local size = if big then rng:NextInteger(24, 30) else rng:NextInteger(16, 20)
					local hill = ink(layers.Deco, if big then "▲" else "^", toCanvas(world) + jitter, size, COLORS.Hill)
					hill.TextStrokeTransparency = if big then 0.4 else 1
					if big then
						hill.TextTransparency = 0.25
					end
				end
			end
		end
	end
end

-- 나무 그림 (동그란 잎 + 줄기). 나무 자리를 TreeCell 칸마다 하나로 묶는다
local function drawTrees(rng: Random)
	local cfg = Config.Minimap
	local buckets: { [number]: { Sum: Vector3, Count: number } } = {}
	local function add(position: Vector3)
		if not MapData.isSurface(position) then
			return
		end
		local key = math.floor(position.X / cfg.TreeCell) * 100000 + math.floor(position.Z / cfg.TreeCell)
		local bucket = buckets[key]
		if bucket then
			bucket.Sum += position
			bucket.Count += 1
		else
			buckets[key] = { Sum = position, Count = 1 }
		end
	end
	local function isTree(oreType: any): boolean
		local def = if typeof(oreType) == "string" then OreDefs[oreType] else nil
		return def ~= nil and def.Kind == "Tree"
	end
	local spawns = Workspace:FindFirstChild("OreSpawns")
	local found = 0
	if spawns then
		for _, child in spawns:GetChildren() do
			if child:IsA("BasePart") and isTree(child:GetAttribute("OreType")) then
				add(child.Position)
				found += 1
			end
		end
	end
	if found == 0 then
		for _, node in CollectionService:GetTagged("OreNode") do
			if node:IsA("Model") and isTree(node:GetAttribute("OreType")) then
				add(node:GetPivot().Position)
			end
		end
	end
	for _, bucket in buckets do
		local center = toCanvas(bucket.Sum / bucket.Count)
		local size = cfg.TreeSize * rng:NextNumber(0.8, 1.2) * (if bucket.Count >= 3 then 1.2 else 1)
		local trunk = rect(layers.Deco, center + Vector2.new(0, size * 0.45), Vector2.new(math.max(2, size * 0.22), size * 0.5), COLORS.Trunk)
		trunk.ZIndex = 1
		local crown = rect(layers.Deco, center, Vector2.new(size, size * rng:NextNumber(0.85, 1)), COLORS.TreeCrown)
		crown.ZIndex = 2
		round(crown)
		outline(crown, COLORS.Ink, 1, 0.3)
	end
end

-- 집 그림 하나 (몸통 + 세모 지붕 + 문)
local function drawHouse(center: Vector2, size: number)
	local house = Instance.new("Frame")
	house.AnchorPoint = Vector2.new(0.5, 0.5)
	house.Position = UDim2.fromOffset(center.X, center.Y)
	house.Size = UDim2.fromOffset(size, size)
	house.BackgroundTransparency = 1
	house.Parent = layers.Icons
	local body = rect(house, Vector2.new(size / 2, size * 0.7), Vector2.new(size * 0.75, size * 0.55), COLORS.House)
	outline(body, COLORS.Ink, 1.5)
	local door = rect(body, Vector2.new(size * 0.375, size * 0.38), Vector2.new(size * 0.18, size * 0.28), COLORS.Ink)
	door.AnchorPoint = Vector2.new(0.5, 1)
	door.Position = UDim2.new(0.5, 0, 1, 0)
	local roof = ink(house, "▲", Vector2.new(size / 2, size * 0.28), math.floor(size * 0.95), COLORS.Roof, COLORS.Ink)
	roof.TextStrokeTransparency = 0.2
	reserve(center, Vector2.new(size, size))
end

-- 마을: 건물 모델(이름에 House·집 등)이 있으면 그 자리, 없으면 광장 둘레에 집 몇 채 + "마을" 글자
local function drawTown(rng: Random)
	local cfg = Config.Minimap
	local town = CollectionService:GetTagged("TownArrival")[1]
	local townPosition = if town then MapData.positionOf(town) else nil
	local houses: { Vector3 } = {}
	local patterns = { "house", "home", "cottage", "building", "tavern", "집", "건물", "주택" }
	local skipRoots = { Workspace:FindFirstChild("Mine"), Workspace:FindFirstChild("Ores"), Workspace:FindFirstChild("NPCs") }
	for _, d in Workspace:GetDescendants() do
		if #houses >= cfg.MaxHouses then
			break
		end
		local skip = false
		for _, root in skipRoots do
			if root and d:IsDescendantOf(root) then
				skip = true
			end
		end
		if not skip and d:IsA("Model") and not CollectionService:HasTag(d, "ShopNPC") then
			local name = string.lower(d.Name)
			local match = false
			for _, pattern in patterns do
				if string.find(name, pattern, 1, true) then
					match = true
					break
				end
			end
			if match then
				local position = d:GetPivot().Position
				local far = MapData.isSurface(position)
				for _, other in houses do
					if far and ((other - position) * Vector3.new(1, 0, 1)).Magnitude < 10 then
						far = false
					end
				end
				if far then
					table.insert(houses, position)
				end
			end
		end
	end
	if #houses == 0 and townPosition then
		local npcs = CollectionService:GetTagged("ShopNPC")
		for i = 1, cfg.TownHouseCount do
			local angle = (i / cfg.TownHouseCount) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
			local position = townPosition + Vector3.new(math.cos(angle), 0, math.sin(angle)) * cfg.TownHouseRadius
			local clear = true
			for _, npc in npcs do
				local npcPosition = MapData.positionOf(npc)
				if npcPosition and ((npcPosition - position) * Vector3.new(1, 0, 1)).Magnitude < 10 then
					clear = false
				end
			end
			if clear then
				table.insert(houses, position)
			end
		end
	end
	for _, position in houses do
		drawHouse(toCanvas(position), rng:NextInteger(15, 19))
	end
	if townPosition then
		local center = toCanvas(townPosition)
		local plaza = rect(layers.Terrain, center, Vector2.new(cfg.TownHouseRadius * 1.6, cfg.TownHouseRadius * 1.6) * viewScale, COLORS.Path, 0.2)
		plaza.ZIndex = 2
		round(plaza)
		outline(plaza, COLORS.Ink, 1.5, 0.5)
		placeLabel("마을", center, cfg.TownHouseRadius * viewScale * 0.5, 20, COLORS.Ink)
	end
end

-- 몹 구역: 생성 자리(MobSpawns, 속성 Zone)를 구역별로 묶어 옅은 색 동그라미 + 이름
local function drawMobZones()
	local folder = Workspace:FindFirstChild("MobSpawns")
	if not folder then
		return
	end
	type Zone = { Name: string, MobType: string?, Points: { Vector3 } }
	local zones: { [string]: Zone } = {}
	for _, child in folder:GetChildren() do
		local name = child:GetAttribute("Zone")
		local position = MapData.positionOf(child)
		if typeof(name) == "string" and position and MapData.isSurface(position) then
			local zone = zones[name]
			if not zone then
				local mobType = child:GetAttribute("MobType")
				zone = { Name = name, MobType = if typeof(mobType) == "string" then mobType else nil, Points = {} }
				zones[name] = zone
			end
			table.insert(zone.Points, position)
		end
	end
	for _, zone in zones do
		local sum = Vector3.zero
		for _, p in zone.Points do
			sum += p
		end
		local middle = sum / #zone.Points
		local radius = 0
		for _, p in zone.Points do
			radius = math.max(radius, ((p - middle) * Vector3.new(1, 0, 1)).Magnitude)
		end
		radius = math.clamp(radius + 8, 20, 90)
		local color = if zone.MobType then (Config.Minimap.ZoneColors :: { [string]: Color3 })[zone.MobType] else nil
		local center = toCanvas(middle)
		local blob = rect(layers.Deco, center, Vector2.new(radius * 2, radius * 1.8) * viewScale, color or COLORS.Hill, 0.7)
		blob.ZIndex = 0
		round(blob)
		outline(blob, color or COLORS.Ink, 2, 0.35)
		placeLabel(zone.Name, center, 0, 13, COLORS.Ink)
	end
end

-- 광산 입구: 바위 둔덕 + 검은 굴 입구 + "광산"
local function drawMineEntrance()
	for _, portal in CollectionService:GetTagged("MinePortal") do
		local position = MapData.positionOf(portal)
		if position and MapData.isSurface(position) and portal:GetAttribute("TargetFloor") == 1 then
			local center = toCanvas(position)
			local mound = rect(layers.Icons, center, Vector2.new(30, 24), COLORS.MineMound)
			round(mound)
			outline(mound, COLORS.Ink, 2)
			local mouth = rect(mound, Vector2.new(15, 16), Vector2.new(14, 12), Color3.fromRGB(25, 18, 14))
			round(mouth, 0.5)
			reserve(center, Vector2.new(30, 24))
			placeLabel("광산", center, 13, 17, COLORS.Ink)
			return
		end
	end
end

-- NPC: 동그란 아이콘(직업 그림) + 직업 이름 (예: "대장장이 브론" → "대장장이")
local function drawNpcs()
	for _, npc in CollectionService:GetTagged("ShopNPC") do
		local shopId = npc:GetAttribute("ShopId")
		local shop = if typeof(shopId) == "string" then ShopDefs[shopId] else nil
		local position = MapData.positionOf(npc)
		if shop and position and typeof(shopId) == "string" then
			local center = toCanvas(position)
			local badge = rect(layers.Icons, center, Vector2.new(24, 24), COLORS.Npc)
			badge.ZIndex = 3
			round(badge)
			outline(badge, COLORS.Ink, 2)
			local symbol = (Config.Minimap.NpcIcons :: { [string]: string })[shopId] or "🙂"
			local glyph = ink(badge, symbol, Vector2.new(12, 12), 15, COLORS.Ink)
			glyph.TextStrokeTransparency = 1
			reserve(center, Vector2.new(24, 24))
			local role = string.match(shop.NpcName, "^(%S+)") or shop.NpcName
			placeLabel(role, center, 12, 14, COLORS.Ink)
		end
	end
end

-- 밖 지도 전체 그리기 (지형 광선이 처음이면 기다린다). 옛 차례면 false
local function drawOutdoor(gen: number): boolean
	local bounds = MapData.worldBounds()
	local samples = MapData.sampleTerrain(bounds)
	if gen ~= generation then
		return false
	end
	viewFloor = nil
	viewMaze = nil
	viewMin = bounds.Min
	layout(bounds.Max - bounds.Min, Config.Minimap.MaxOutdoorScale)
	setTheme(false)
	titleLabel.Text = "마을 주변 지도"
	local rng = Random.new(20261009)
	drawTerrain(samples, rng)
	drawDoodles(samples, rng)
	drawMobZones()
	drawTrees(rng)
	drawTown(rng)
	drawNpcs()
	drawMineEntrance()
	return true
end

----------------------------------------------------------------------
-- 광산 지도
----------------------------------------------------------------------

-- 벽 선 하나 (손그림처럼 살짝 흔들림)
local function wall(from: Vector2, to: Vector2, rng: Random)
	local cfg = Config.Minimap
	local thickness = cfg.WallThickness
	local jitter = cfg.WallJitter
	local horizontal = math.abs(to.X - from.X) > math.abs(to.Y - from.Y)
	local length = (to - from).Magnitude + thickness
	local mid = (from + to) / 2
	local shake = rng:NextNumber(-jitter, jitter)
	local center = if horizontal then mid + Vector2.new(0, shake) else mid + Vector2.new(shake, 0)
	local width = thickness * rng:NextNumber(0.85, 1.15)
	local size = if horizontal then Vector2.new(length, width) else Vector2.new(width, length)
	local line = rect(layers.Deco, center, size, COLORS.CaveWall)
	round(line, 0, math.floor(width / 2))
end

-- 갱도 표시 알약 ("출구 ↑", "2층 ↓", "🔒 공사 중") + 반짝이는 고리
local function portalBadge(center: Vector2, text: string, color: Color3, note: string?, pulse: boolean)
	-- 그림 밖으로 안 나가게
	local half = textWidth(text, 15) / 2 + 10
	local clamped = Vector2.new(math.clamp(center.X, half + 2, canvasSize.X - half - 2), math.clamp(center.Y, 16, canvasSize.Y - 16))
	if pulse then
		local ring = rect(layers.Icons, center, Vector2.new(20, 20), color, 0.3)
		round(ring)
		local info = TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, -1)
		TweenService:Create(ring, info, { Size = UDim2.fromOffset(46, 46), BackgroundTransparency = 1 }):Play()
	end
	local pill = Instance.new("TextLabel")
	pill.AnchorPoint = Vector2.new(0.5, 0.5)
	pill.Position = UDim2.fromOffset(clamped.X, clamped.Y)
	pill.Size = UDim2.fromOffset(0, 24)
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.BackgroundColor3 = color
	pill.BorderSizePixel = 0
	pill.Font = Config.Minimap.Font
	pill.Text = text
	pill.TextSize = 15
	pill.TextColor3 = Color3.new(1, 1, 1)
	pill.TextStrokeColor3 = COLORS.Ink
	pill.TextStrokeTransparency = 0.2
	pill.ZIndex = 3
	pill.Parent = layers.Labels
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = pill
	round(pill)
	outline(pill, COLORS.InkLight, 2)
	if note then
		local small = ink(layers.Labels, note, clamped + Vector2.new(0, 20), 11, COLORS.InkLight, COLORS.Ink)
		small.ZIndex = 3
	end
end

-- 이 층의 갱도(MinePortal): 미로 범위 안 + 높이가 비슷한 것. 위로 가면 출구, 아래로 가면 N층, 잠긴 층은 자물쇠
local function drawPortals(floor: number, maze: MapData.Maze)
	local cfg = Config.Minimap
	local half = maze.Spacing
	local minX, minZ = maze.Origin.X - half, maze.Origin.Y - half
	local maxX, maxZ = maze.Origin.X + maze.Cols * maze.Spacing, maze.Origin.Y + maze.Rows * maze.Spacing
	for _, portal in CollectionService:GetTagged("MinePortal") do
		local target = portal:GetAttribute("TargetFloor")
		local position = MapData.positionOf(portal)
		if typeof(target) == "number" and target ~= floor and position then
			local inside = position.X >= minX and position.X <= maxX and position.Z >= minZ and position.Z <= maxZ
			if inside and math.abs(position.Y - maze.FloorY) <= cfg.PortalFloorRange then
				local center = toCanvas(position)
				local info = Config.Mine.Floors[target]
				if target < floor then
					portalBadge(center, if target == 0 then "출구 ↑" else `{target}층 ↑`, COLORS.Exit, nil, true)
				elseif info and info.Locked then
					portalBadge(center, "🔒 공사 중", COLORS.Locked, nil, false)
				else
					local note = if info then `T{info.RequiredTier} 곡괭이부터` else nil
					portalBadge(center, `{target}층 ↓`, COLORS.Down, note, true)
				end
			end
		end
	end
end

-- 광산 층 지도 전체 그리기: 칸 바닥 → 안 가 본 칸 그늘 → 벽 → 갱도
local function drawCave(floor: number, maze: MapData.Maze)
	local spacing = maze.Spacing
	viewFloor = floor
	viewMaze = maze
	viewMin = Vector2.new(maze.Origin.X - spacing / 2, maze.Origin.Y - spacing / 2)
	layout(Vector2.new(maze.Cols * spacing, maze.Rows * spacing), Config.Minimap.MaxCaveScale)
	setTheme(true)
	local info = Config.Mine.Floors[floor]
	titleLabel.Text = if info then `{info.Name} 지도` else `광산 {floor}층 지도`
	local rng = Random.new(floor * 7919)
	local cellPx = spacing * viewScale
	local seen = visited[floor] or {}
	local function centerOf(col: number, row: number): Vector2
		return toCanvas(Vector3.new(maze.Origin.X + col * spacing, 0, maze.Origin.Y + row * spacing))
	end
	for _, cell in maze.Cells do
		local center = centerOf(cell.Col, cell.Row)
		rect(layers.Terrain, center, Vector2.new(cellPx + 1, cellPx + 1), COLORS.CaveFloor)
		local fog = rect(layers.Fog, center, Vector2.new(cellPx + 1, cellPx + 1), COLORS.Fog, Config.Minimap.FogTransparency)
		fog.Visible = not seen[cell.Index]
		fogFrames[cell.Index] = fog
	end
	-- 벽: 칸마다 위·왼쪽 변은 이웃과 막혔거나 이웃이 없으면, 오른쪽·아래 변은 이웃이 없을 때만 (겹쳐 그리지 않게)
	local h = cellPx / 2
	for _, cell in maze.Cells do
		local c = centerOf(cell.Col, cell.Row)
		local north = maze.Cells[MapData.cellKey(cell.Col, cell.Row - 1)]
		local west = maze.Cells[MapData.cellKey(cell.Col - 1, cell.Row)]
		if not north or not maze.OpenSouth[MapData.cellKey(cell.Col, cell.Row - 1)] then
			wall(c + Vector2.new(-h, -h), c + Vector2.new(h, -h), rng)
		end
		if not west or not maze.OpenEast[MapData.cellKey(cell.Col - 1, cell.Row)] then
			wall(c + Vector2.new(-h, -h), c + Vector2.new(-h, h), rng)
		end
		if not maze.Cells[MapData.cellKey(cell.Col + 1, cell.Row)] then
			wall(c + Vector2.new(h, -h), c + Vector2.new(h, h), rng)
		end
		if not maze.Cells[MapData.cellKey(cell.Col, cell.Row + 1)] then
			wall(c + Vector2.new(-h, h), c + Vector2.new(h, h), rng)
		end
	end
	drawPortals(floor, maze)
end

----------------------------------------------------------------------
-- 움직이는 것 (바위 점, 내 화살표, 다른 플레이어)
----------------------------------------------------------------------

-- 바위 점: 밖은 내 둘레 RockRange 안, 광산은 가 본 칸 안만
local function drawRocks(rootPosition: Vector3)
	for _, child in layers.Dynamic:GetChildren() do
		child:Destroy()
	end
	local maze = viewMaze
	local seen = if viewFloor then (visited[viewFloor] or {}) else nil
	for _, rock in CollectionService:GetTagged("OreNode") do
		if rock:IsA("Model") and rock.Parent then
			local oreType = rock:GetAttribute("OreType")
			local def = if typeof(oreType) == "string" then OreDefs[oreType] else nil
			if def and def.Kind == "Rock" then
				local position = rock:GetPivot().Position
				local show
				if maze and seen then
					local cell, distance = MapData.nearestCell(maze, position)
					show = cell ~= nil and distance <= maze.Spacing and seen[cell.Index] == true and math.abs(position.Y - maze.FloorY) < 30
				else
					show = MapData.isSurface(position) and (position - rootPosition).Magnitude <= Config.Minimap.RockRange
				end
				if show then
					local dot = rect(layers.Dynamic, toCanvas(position), Vector2.new(7, 7), def.Color)
					round(dot)
					outline(dot, COLORS.Ink, 1)
				end
			end
		end
	end
end

-- 다른 플레이어 점 (같은 층에 있는 사람만)
local function updateOthers(myPosition: Vector3)
	local inverse = 1 / canvasScale.Scale
	local alive: { [Player]: boolean } = {}
	for _, player in Players:GetPlayers() do
		if player ~= localPlayer then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local position = root.Position
				local sameLayer = if viewFloor then math.abs(position.Y - myPosition.Y) < 40 else MapData.isSurface(position)
				local point = toCanvas(position)
				local onMap = point.X >= 0 and point.Y >= 0 and point.X <= canvasSize.X and point.Y <= canvasSize.Y
				if sameLayer and onMap then
					alive[player] = true
					local dot = otherDots[player]
					if not dot then
						dot = rect(layers.Players, point, Vector2.new(10, 10), COLORS.OtherPlayer)
						round(dot)
						outline(dot, Color3.new(1, 1, 1), 1.5)
						otherDots[player] = dot
					end
					dot.Position = UDim2.fromOffset(point.X, point.Y)
					dot.Size = UDim2.fromOffset(10 * inverse, 10 * inverse)
				end
			end
		end
	end
	for player, dot in otherDots do
		if not alive[player] then
			dot:Destroy()
			otherDots[player] = nil
		end
	end
end

-- 지금 그려야 할 것의 이름 (층 + 화면 크기)
local function wantedKey(): string
	local floor = MineAtmosphereController.getFloor()
	local screen = gui.AbsoluteSize
	local where = "out"
	if floor and floor >= 1 and MapData.getMaze(floor) then
		-- 벽 확인을 다 못 했으면 "?"를 붙여 두고, 다 되면 다시 그린다
		where = if MapData.isMazeCached(floor) then `cave{floor}` else `cave{floor}?`
	end
	return `{where}:{math.floor(screen.X)}x{math.floor(screen.Y)}`
end

-- 다시 그리기 (밖 지형은 처음에 시간이 조금 걸려서 따로 돌린다)
local function redraw()
	generation += 1
	local gen = generation
	drawnKey = wantedKey()
	clearCanvas()
	loadingLabel.Visible = true
	task.spawn(function()
		local floor = MineAtmosphereController.getFloor()
		local maze = if floor and floor >= 1 then MapData.getMaze(floor) else nil
		local done = false
		if floor and maze then
			drawCave(floor, maze)
			done = true
		else
			done = drawOutdoor(gen)
		end
		if done and gen == generation then
			loadingLabel.Visible = false
			ready = true
			lastRocks = 0
		end
	end)
end

-- 큰 지도 / 작은 지도에 그림 붙이기
local function applyMode()
	panel.Visible = mode == "Big"
	corner.Visible = mode == "Small"
	openButton.Visible = mode ~= "Small"
	if mode == "Big" then
		canvas.Parent = content
		canvasScale.Scale = 1
		canvas.Position = UDim2.fromOffset(0, 0)
	elseif mode == "Small" then
		canvas.Parent = corner
	end
	if mode ~= "Closed" and wantedKey() ~= drawnKey then
		redraw()
	end
end

-- 매 프레임: 화살표·다른 플레이어·작은 지도 위치. 가끔: 가 본 칸, 바위 점, 층 바뀜
local function step()
	if mode == "Closed" then
		return
	end
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local now = os.clock()
	if now - lastSlow >= SLOW_TICK then
		lastSlow = now
		if wantedKey() ~= drawnKey then
			redraw()
			return
		end
		-- 광산: 지금 있는 칸을 밝힌다
		local maze = viewMaze
		local floor = viewFloor
		if ready and maze and floor then
			local cell, distance = MapData.nearestCell(maze, root.Position)
			if cell and distance <= Config.Minimap.VisitRadius then
				visited[floor] = visited[floor] or {}
				if not visited[floor][cell.Index] then
					visited[floor][cell.Index] = true
					local fog = fogFrames[cell.Index]
					if fog then
						fog.Visible = false
					end
				end
			end
		end
	end
	if not ready then
		return
	end
	if now - lastRocks >= Config.Minimap.RockRefresh then
		lastRocks = now
		drawRocks(root.Position)
	end

	-- 작은 지도: 확대 + 내 위치가 가운데
	if mode == "Small" then
		local wanted = if viewFloor then Config.Minimap.CornerCaveScale else Config.Minimap.CornerOutdoorScale
		canvasScale.Scale = math.clamp(wanted / viewScale, 0.4, 4)
	end
	local s = canvasScale.Scale
	local me = toCanvas(root.Position)
	if mode == "Small" then
		local half = Config.Minimap.CornerSize / 2
		canvas.Position = UDim2.fromOffset(half - me.X * s, half - me.Y * s)
	end
	arrow.Position = UDim2.fromOffset(me.X, me.Y)
	arrow.Size = UDim2.fromOffset(26 / s, 26 / s)
	local look = root.CFrame.LookVector
	arrow.Rotation = math.deg(math.atan2(look.X, -look.Z))
	updateOthers(root.Position)
end

-- 큰 지도 켜고 끄기 (M 키·"지도" 버튼). 작은 지도일 때 누르면 크게
function MinimapController.toggle()
	mode = if mode == "Big" then "Closed" else "Big"
	applyMode()
end

----------------------------------------------------------------------
-- 화면 만들기
----------------------------------------------------------------------

-- 가장자리 그늘 4개 (양피지 끝이 조금 어둡게)
local function makeVignette(parent: Frame)
	local specs = {
		{ Size = UDim2.new(0, 26, 1, 0), Position = UDim2.fromScale(0, 0), Rotation = 0 },
		{ Size = UDim2.new(0, 26, 1, 0), Position = UDim2.new(1, -26, 0, 0), Rotation = 180 },
		{ Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromScale(0, 0), Rotation = 90 },
		{ Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 1, -26), Rotation = 270 },
	}
	for _, spec in specs do
		local edge = Instance.new("Frame")
		edge.Size = spec.Size
		edge.Position = spec.Position
		edge.BackgroundColor3 = COLORS.ParchmentEdge
		edge.BorderSizePixel = 0
		edge.ZIndex = 5
		edge.Parent = parent
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = spec.Rotation
		gradient.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
		gradient.Parent = edge
		table.insert(vignette, edge)
	end
end

-- 나침반 (오른쪽 위, 동그라미 + 십자 + N)
local function makeCompass(parent: Frame): Frame
	local rose = Instance.new("Frame")
	rose.AnchorPoint = Vector2.new(1, 0)
	rose.Position = UDim2.new(1, -10, 0, 10)
	rose.Size = UDim2.fromOffset(40, 40)
	rose.BackgroundColor3 = COLORS.Parchment
	rose.BackgroundTransparency = 0.15
	rose.ZIndex = 6
	rose.Parent = parent
	round(rose)
	outline(rose, COLORS.Ink, 2)
	local vertical = rect(rose, Vector2.new(20, 20), Vector2.new(2, 28), COLORS.Ink)
	vertical.ZIndex = 6
	local horizontal = rect(rose, Vector2.new(20, 20), Vector2.new(28, 2), COLORS.Ink)
	horizontal.ZIndex = 6
	local tip = ink(rose, "▲", Vector2.new(20, 9), 12, COLORS.Player, COLORS.Ink)
	tip.ZIndex = 7
	local north = ink(rose, "N", Vector2.new(20, -7), 16, COLORS.Ink)
	north.ZIndex = 7
	return rose
end

-- 클라이언트 시작 시 한 번 호출
function MinimapController.init()
	local cfg = Config.Minimap
	gui = Instance.new("ScreenGui")
	gui.Name = "MinimapGui"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 4
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	openButton = UiKit.button(gui, "🗺 지도 (M)", UDim2.fromOffset(150, 34), UDim2.new(1, -166, 0, 168), MinimapController.toggle)

	-- 큰 지도 창
	panel = Instance.new("Frame")
	panel.Name = "MapPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(320, 320)
	panel.BackgroundColor3 = COLORS.ParchmentEdge
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 10
	panel.Parent = gui
	round(panel, 0, 12)
	outline(panel, COLORS.Ink, 3)

	titleLabel = ink(panel, "지도", Vector2.new(0, 0), 22, COLORS.InkLight, COLORS.Ink)
	titleLabel.AutomaticSize = Enum.AutomaticSize.None
	titleLabel.AnchorPoint = Vector2.new(0, 0.5)
	titleLabel.Position = UDim2.new(0, 12, 0, cfg.TitleHeight / 2 + 2)
	titleLabel.Size = UDim2.new(1, -120, 0, cfg.TitleHeight - 10)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextScaled = true
	local titleLimit = Instance.new("UITextSizeConstraint")
	titleLimit.MaxTextSize = 22
	titleLimit.Parent = titleLabel
	local closeButton = UiKit.button(panel, "✕", UDim2.fromOffset(34, 30), UDim2.new(1, -40, 0, 4), function()
		mode = "Closed"
		applyMode()
	end)
	closeButton.TextSize = 18
	local smallButton = UiKit.button(panel, "작게", UDim2.fromOffset(56, 30), UDim2.new(1, -102, 0, 4), function()
		mode = "Small"
		applyMode()
	end)
	smallButton.TextSize = 14

	content = Instance.new("Frame")
	content.Name = "Content"
	content.Position = UDim2.fromOffset(6, cfg.TitleHeight + 2)
	content.Size = UDim2.fromOffset(300, 300)
	content.BackgroundColor3 = COLORS.Parchment
	content.BorderSizePixel = 0
	content.ClipsDescendants = true
	content.Parent = panel
	outline(content, COLORS.Ink, 1.5)
	makeVignette(content)
	makeCompass(content)

	loadingLabel = ink(content, "지도 그리는 중...", Vector2.zero, 18, COLORS.Ink)
	loadingLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	loadingLabel.Position = UDim2.fromScale(0.5, 0.5)
	loadingLabel.ZIndex = 8

	-- 작은 지도 (오른쪽 위, 누르면 크게)
	corner = Instance.new("TextButton")
	corner.Name = "CornerMap"
	corner.AnchorPoint = Vector2.new(1, 0)
	corner.Position = UDim2.new(1, -16, 0, cfg.CornerTop)
	corner.Size = UDim2.fromOffset(cfg.CornerSize, cfg.CornerSize)
	corner.BackgroundColor3 = COLORS.Parchment
	corner.BorderSizePixel = 0
	corner.AutoButtonColor = false
	corner.Text = ""
	corner.ClipsDescendants = true
	corner.Visible = false
	corner.Parent = gui
	round(corner, 0, 12)
	outline(corner, COLORS.Ink, 3)
	corner.Activated:Connect(function()
		mode = "Big"
		applyMode()
	end)
	cornerNorth = ink(corner, "N▲", Vector2.new(18, 12), 14, COLORS.Ink)
	cornerNorth.ZIndex = 6
	local cornerClose = UiKit.button(corner, "✕", UDim2.fromOffset(26, 24), UDim2.new(1, -30, 0, 4), function()
		mode = "Closed"
		applyMode()
	end)
	cornerClose.ZIndex = 6

	-- 그림 (층마다 다시 그림)
	canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.BackgroundTransparency = 1
	canvas.Size = UDim2.fromOffset(300, 300)
	canvas.ZIndex = 1
	canvas.Parent = content
	canvasScale = Instance.new("UIScale")
	canvasScale.Parent = canvas
	for order, name in { "Terrain", "Fog", "Deco", "Icons", "Labels", "Dynamic", "Players" } do
		local layer = Instance.new("Frame")
		layer.Name = name
		layer.BackgroundTransparency = 1
		layer.Size = UDim2.fromScale(1, 1)
		layer.ZIndex = order
		layer.Parent = canvas
		layers[name] = layer
	end

	-- 내 화살표 (빨간 ▲, 바라보는 방향)
	arrow = Instance.new("TextLabel")
	arrow.Name = "Me"
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.BackgroundTransparency = 1
	arrow.Font = Enum.Font.GothamBlack
	arrow.Text = "▲"
	arrow.TextScaled = true
	arrow.TextColor3 = COLORS.Player
	arrow.TextStrokeColor3 = Color3.new(1, 1, 1)
	arrow.TextStrokeTransparency = 0
	arrow.ZIndex = 9
	arrow.Parent = canvas

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if mode ~= "Closed" and wantedKey() ~= drawnKey then
			redraw()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == TOGGLE_KEY then
			MinimapController.toggle()
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local dot = otherDots[player]
		if dot then
			dot:Destroy()
			otherDots[player] = nil
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return MinimapController
