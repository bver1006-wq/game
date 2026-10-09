--!strict
-- 오른쪽 위 미니맵 ("지도" 버튼 또는 M 키로 켜고 끈다). 북쪽(-Z)이 위.
--   밖: 내 위치, 마을·NPC·광산 입구, 근처 바위(광석 색 점)
--   동굴 안: 내가 직접 가 본 칸만 밝혀서 그린다 (칸·통로는 층의 BatWaypoints 경로점과 Links로 안다)
-- 가 본 칸 기록은 이 클라이언트에만 남는다 (저장 없음).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local OreDefs = require(ReplicatedStorage.Shared.OreDefs)
local ShopDefs = require(ReplicatedStorage.Shared.ShopDefs)
local MineAtmosphereController = require(script.Parent.MineAtmosphereController)
local UiKit = require(script.Parent.UiKit)

local TOGGLE_KEY = Enum.KeyCode.M
local UPDATE_INTERVAL = 0.1
local CAVE_BACKGROUND = Color3.fromRGB(14, 12, 16)
local OUTDOOR_BACKGROUND = Color3.fromRGB(40, 62, 38)
local CELL_COLOR = Color3.fromRGB(120, 105, 90)

local localPlayer = Players.LocalPlayer

type Node = { Index: number, Position: Vector3, Links: { number } }

local MinimapController = {}

local panel: Frame
local titleLabel: TextLabel
local mapLayer: Frame -- 지도 그림 (내 위치가 가운데 오도록 통째로 움직인다)
local staticLayer: Frame -- 칸·통로·건물 (바뀔 때만 다시 그림)
local dynamicLayer: Frame -- 바위 점 (자주 다시 그림)
local arrow: TextLabel
local visible = false

local visited: { [number]: { [number]: boolean } } = {} -- 층 → 칸 번호 → 가 봤는지
local nodeCache: { [number]: { [number]: Node } } = {}
local staticKey = "" -- 정적 그림이 무엇을 기준으로 그려졌는지 (바뀌면 다시 그림)

-- 월드 좌표 → 지도 픽셀 (원점 기준)
local function toMap(position: Vector3, scale: number): Vector2
	return Vector2.new(position.X * scale, position.Z * scale)
end

-- 지도 위에 네모 하나
local function rect(parent: Instance, center: Vector2, size: Vector2, color: Color3, rotation: number?): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromOffset(center.X, center.Y)
	frame.Size = UDim2.fromOffset(size.X, size.Y)
	frame.Rotation = rotation or 0
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

-- 지도 위에 글자 아이콘 하나
local function icon(parent: Instance, center: Vector2, text: string, color: Color3)
	local frame = rect(parent, center, Vector2.new(22, 22), color)
	frame.ZIndex = 3
	UiKit.corner(frame, 11)
	UiKit.stroke(frame, Color3.new(0, 0, 0), 1.5)
	local label = UiKit.label(frame, text, UDim2.fromScale(1, 1), nil, Color3.new(1, 1, 1), 12)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.ZIndex = 4
end

-- 층의 칸 정보 (경로점에서 읽어 기억해 둔다)
local function getNodes(floor: number): { [number]: Node }?
	local mine = Workspace:FindFirstChild("Mine")
	local floorModel = mine and mine:FindFirstChild("Floor" .. floor)
	local folder = floorModel and floorModel:FindFirstChild("BatWaypoints")
	if not folder then
		return nodeCache[floor]
	end
	local nodes: { [number]: Node } = {}
	local count = 0
	for _, wp in folder:GetChildren() do
		local index = wp:GetAttribute("Index")
		local links = wp:GetAttribute("Links")
		if wp:IsA("BasePart") and typeof(index) == "number" then
			local list = {}
			if typeof(links) == "string" then
				for token in string.gmatch(links, "%d+") do
					table.insert(list, tonumber(token) :: number)
				end
			end
			nodes[index] = { Index = index, Position = wp.Position, Links = list }
			count += 1
		end
	end
	if count > 0 then
		nodeCache[floor] = nodes
	end
	return nodeCache[floor]
end

-- 가장 가까운 칸
local function nearestNode(nodes: { [number]: Node }, position: Vector3): (Node?, number)
	local best: Node? = nil
	local bestDistance = math.huge
	for _, node in nodes do
		local flat = (node.Position - position) * Vector3.new(1, 0, 1)
		if flat.Magnitude < bestDistance then
			best = node
			bestDistance = flat.Magnitude
		end
	end
	return best, bestDistance
end

-- 동굴 칸 사이 간격 (연결된 두 칸의 거리)
local function cellSpacing(nodes: { [number]: Node }): number
	for _, node in nodes do
		local other = node.Links[1] and nodes[node.Links[1]]
		if other then
			return ((other.Position - node.Position) * Vector3.new(1, 0, 1)).Magnitude
		end
	end
	return 24
end

-- 정적 그림: 동굴 (가 본 칸과 그 통로만)
local function drawCave(floor: number, nodes: { [number]: Node })
	local scale = Config.Minimap.CaveScale
	local spacing = cellSpacing(nodes)
	local cellSize = spacing * 0.68 * scale
	local seen = visited[floor] or {}
	for index, node in nodes do
		if seen[index] then
			local center = toMap(node.Position, scale)
			rect(staticLayer, center, Vector2.new(cellSize, cellSize), CELL_COLOR)
			for _, linkIndex in node.Links do
				local other = nodes[linkIndex]
				if other then
					-- 둘 다 가 봤으면 통로 전체, 하나만 가 봤으면 절반만 (그 너머는 아직 모른다)
					local otherCenter = toMap(other.Position, scale)
					local reach = if seen[linkIndex] then 1 else 0.5
					local finish = center:Lerp(otherCenter, reach)
					local mid = (center + finish) / 2
					local length = (finish - center).Magnitude
					local horizontal = math.abs(otherCenter.X - center.X) > math.abs(otherCenter.Y - center.Y)
					local size = if horizontal then Vector2.new(length, cellSize * 0.65) else Vector2.new(cellSize * 0.65, length)
					rect(staticLayer, mid, size, CELL_COLOR)
				end
			end
		end
	end
	-- 출구(도착 지점)
	for _, arrival in CollectionService:GetTagged("MineArrival") do
		if arrival:IsA("BasePart") and arrival:GetAttribute("Floor") == floor then
			icon(staticLayer, toMap(arrival.Position, scale), "출", Color3.fromRGB(90, 170, 90))
		end
	end
end

-- 정적 그림: 밖 (마을·NPC·광산 입구)
local function drawOutdoor()
	local scale = Config.Minimap.OutdoorScale
	for _, town in CollectionService:GetTagged("TownArrival") do
		if town:IsA("BasePart") then
			local center = toMap(town.Position, scale)
			local plaza = rect(staticLayer, center, Vector2.new(70, 70), Color3.fromRGB(150, 130, 95))
			plaza.BackgroundTransparency = 0.4
			UiKit.corner(plaza, 35)
		end
	end
	for _, npc in CollectionService:GetTagged("ShopNPC") do
		local shopId = npc:GetAttribute("ShopId")
		local shop = if typeof(shopId) == "string" then ShopDefs[shopId] else nil
		if npc:IsA("Model") and shop then
			icon(staticLayer, toMap(npc:GetPivot().Position, scale), string.sub(shop.NpcName, 1, 3), Color3.fromRGB(200, 150, 60))
		end
	end
	for _, portal in CollectionService:GetTagged("MinePortal") do
		if portal:IsA("BasePart") and portal:GetAttribute("TargetFloor") == 1 and portal.Position.X < 1000 then
			icon(staticLayer, toMap(portal.Position, scale), "광", Color3.fromRGB(110, 110, 120))
		end
	end
end

-- 바위 점 (밖은 거리 안, 동굴은 가 본 칸 안만)
local function drawRocks(floor: number?, rootPosition: Vector3)
	for _, child in dynamicLayer:GetChildren() do
		child:Destroy()
	end
	local scale = if floor then Config.Minimap.CaveScale else Config.Minimap.OutdoorScale
	local nodes = if floor then getNodes(floor) else nil
	local seen = if floor then (visited[floor] or {}) else nil
	for _, rock in CollectionService:GetTagged("OreNode") do
		if rock:IsA("Model") and rock.Parent then
			local position = rock:GetPivot().Position
			if (position - rootPosition).Magnitude <= Config.Minimap.RockRange then
				local show = true
				if nodes and seen then
					local node = nearestNode(nodes, position)
					show = node ~= nil and seen[node.Index] == true
				end
				if show then
					local oreType = rock:GetAttribute("OreType")
					local def = if typeof(oreType) == "string" then OreDefs[oreType] else nil
					local dot = rect(dynamicLayer, toMap(position, scale), Vector2.new(6, 6), if def then def.Color else Color3.new(1, 1, 1))
					UiKit.corner(dot, 3)
					dot.ZIndex = 2
				end
			end
		end
	end
end

-- 한 번 갱신: 칸 밝히기, 다시 그릴지 판단, 지도 위치·화살표
local function update()
	if not visible then
		return
	end
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local floor = MineAtmosphereController.getFloor()
	local nodes = if floor then getNodes(floor) else nil
	local scale = if floor then Config.Minimap.CaveScale else Config.Minimap.OutdoorScale

	-- 동굴: 지금 있는 칸을 밝힌다
	if floor and nodes then
		local node, distance = nearestNode(nodes, root.Position)
		if node and distance <= Config.Minimap.VisitRadius then
			visited[floor] = visited[floor] or {}
			visited[floor][node.Index] = true
		end
	end

	-- 정적 그림 다시 그리기 (층이 바뀌었거나 새 칸을 밝혔을 때)
	local seenCount = 0
	if floor and visited[floor] then
		for _ in visited[floor] do
			seenCount += 1
		end
	end
	local key = `{floor or "out"}:{seenCount}`
	if key ~= staticKey then
		staticKey = key
		for _, child in staticLayer:GetChildren() do
			child:Destroy()
		end
		panel.BackgroundColor3 = if floor then CAVE_BACKGROUND else OUTDOOR_BACKGROUND
		if floor and nodes then
			drawCave(floor, nodes)
			local info = Config.Mine.Floors[floor]
			titleLabel.Text = if info then info.Name else `광산 {floor}층`
		else
			drawOutdoor()
			titleLabel.Text = "마을 주변"
		end
	end
	drawRocks(floor, root.Position)

	-- 내 위치가 가운데 오도록 지도를 옮기고, 화살표를 바라보는 방향으로
	local me = toMap(root.Position, scale)
	local size = Config.Minimap.Size
	mapLayer.Position = UDim2.fromOffset(size / 2 - me.X, size / 2 - me.Y)
	local look = root.CFrame.LookVector
	arrow.Rotation = math.deg(math.atan2(look.X, -look.Z))
end

-- 지도 켜고 끄기
function MinimapController.toggle()
	visible = not visible
	panel.Visible = visible
	staticKey = ""
	update()
end

-- 클라이언트 시작 시 한 번 호출
function MinimapController.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "MinimapGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 4
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	local size = Config.Minimap.Size
	UiKit.button(gui, "지도 (M)", UDim2.fromOffset(150, 34), UDim2.new(1, -166, 0, 168), MinimapController.toggle)

	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -16, 0, 110) -- 골드 칸 아래 (2026-10-09 체력·마나를 맨 위로 올리면서)
	panel.Size = UDim2.fromOffset(size, size)
	panel.BackgroundColor3 = OUTDOOR_BACKGROUND
	panel.BorderSizePixel = 0
	panel.ClipsDescendants = true
	panel.Visible = false
	panel.Parent = gui
	UiKit.corner(panel, 12)
	UiKit.stroke(panel, UiKit.Colors.Border, 3)

	mapLayer = Instance.new("Frame")
	mapLayer.Size = UDim2.fromOffset(0, 0)
	mapLayer.BackgroundTransparency = 1
	mapLayer.Parent = panel
	staticLayer = Instance.new("Frame")
	staticLayer.Size = UDim2.fromOffset(0, 0)
	staticLayer.BackgroundTransparency = 1
	staticLayer.Parent = mapLayer
	dynamicLayer = staticLayer:Clone()
	dynamicLayer.Parent = mapLayer

	arrow = UiKit.label(panel, "▲", UDim2.fromOffset(20, 20), UDim2.new(0.5, -10, 0.5, -10), Color3.fromRGB(255, 230, 120), 18)
	arrow.TextXAlignment = Enum.TextXAlignment.Center
	arrow.ZIndex = 5
	local arrowStroke = Instance.new("UIStroke")
	arrowStroke.Thickness = 2
	arrowStroke.Parent = arrow

	local titleBack = Instance.new("Frame")
	titleBack.Size = UDim2.new(1, 0, 0, 22)
	titleBack.BackgroundColor3 = Color3.new(0, 0, 0)
	titleBack.BackgroundTransparency = 0.4
	titleBack.BorderSizePixel = 0
	titleBack.ZIndex = 6
	titleBack.Parent = panel
	titleLabel = UiKit.label(titleBack, "", UDim2.fromScale(1, 1), nil, UiKit.Colors.Gold, 13)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	titleLabel.ZIndex = 7

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == TOGGLE_KEY then
			MinimapController.toggle()
		end
	end)
	task.spawn(function()
		while true do
			update()
			task.wait(UPDATE_INTERVAL)
		end
	end)
end

return MinimapController
