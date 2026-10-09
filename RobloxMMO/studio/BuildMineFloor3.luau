--!nocheck
-- Studio 제작 스크립트: 광산 3층 (미스릴·오리하르콘, 2026-10-09 사용자 요청 "오리하르콘까지, 3층에서 아주 가끔").
-- Rojo가 ServerStorage/StudioTools/BuildMineFloor3(ModuleScript)로 넣고, 서버(Main.server)가 게임을 시작할 때
-- MoveMineUnderground 바로 다음에 실행한다 (옮긴 2층을 기준으로 위치를 정하므로 순서가 중요).
-- 편집 상태에서 직접 실행하려면 명령 모음에: require(game.ServerStorage.StudioTools.BuildMineFloor3:Clone())
--
-- 만드는 것
--   1. Workspace/Mine/Floor3 모델: 지형(Terrain)으로 판 6x6 미로 (통로 폭 16, 칸 간격 24, 1·2층과 같은 규격)
--      - 위치: 2층보다 Config.MineFloor3.Depth 아래, 2층·다른 층·광산 구역과 겹치지 않게 2층 동쪽 옆
--      - 시작 방(0,0칸): 북쪽 오르막 계단 → 2층 (MinePortal TargetFloor=2, WalkIn), 도착점(MineArrival Floor=3)
--        2층에 지상 출구(TargetFloor=0)가 있으면 3층에도 서쪽 오르막으로 지상 출구를 둔다
--      - 반대편 구석(5,5칸): 남쪽 파란빛 내리막, 판자로 막힌 4층 길 (TargetFloor=4, Config에서 잠김 "공사 중")
--      - 광산 구역(MineZone Floor=3), 박쥐·지도용 경로점(BatWaypoints: Index·Links), 범위 표시(Bounds)
--      - 벽 횃불(파란 불꽃, 속성 Flicker)·파랑/금색 수정 덩어리, 얼음빛 벽 무늬
--   2. Workspace/OreSpawns: 미스릴 자리(벽에 붙여, 일부는 두 개) + 오리하르콘 후보 자리(RandomPool="Orichalcum",
--      Config.RandomPools.Orichalcum.Active개만 동시에 선다). 속성 OreType·Floor=3·GeneratedBy
--   3. 바위 템플릿 ServerStorage/Templates/Ores/{Mithril, Orichalcum}: 철 바위(IronOre)를 복제해 광맥 색을 바꾼다
--      아이콘 ReplicatedStorage/ItemIcons/{Mithril, Orichalcum}: 철 아이콘을 복제해 색을 바꾼다
--   4. 2층의 3층 길: 막고 있던 판자를 치운다(투명·안 부딪힘). 3층 길(TargetFloor=3)이 없으면 2층 반대편 구석 벽에 새로 만든다
--
-- 다시 실행하면: Floor3가 이 스크립트 같은 버전이면 층은 그대로 두고(템플릿·판자만 다시), 버전이 다르면 지우고 새로 짓는다.
-- 사람이 직접 만든 Floor3(속성 GeneratedBy 없음)는 건드리지 않는다.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local GENERATED = "BuildMineFloor3"
local VERSION = 1 -- 층 모양을 바꾸면 올린다 (예전 것을 지우고 새로 짓는다)
local cfg = Config.MineFloor3

-- 미로 규격 (1·2층과 같게)
local N = 6 -- 6x6 칸
local CELL = 24 -- 칸 간격
local HALF = 8 -- 통로 폭의 절반 (폭 16)
local HEIGHT = 16 -- 통로 높이
local VOXEL = 4
-- 지형 덩어리(암반) 범위: 미로 원점(0,0칸 중심, 바닥 높이) 기준
local SHELL_MIN = Vector3.new(-44, -16, -44)
local SHELL_MAX = Vector3.new((N - 1) * CELL + 44, HEIGHT + 12, (N - 1) * CELL + 44)
local GAP = 48 -- 다른 층·구역과 띄우는 거리
local MAX_FLOOR_Y = -160 -- 3층 바닥은 적어도 이만큼 아래 (MoveMineUnderground의 맨 위 -120보다 아래)

local WALL_MATERIAL = Enum.Material.Slate
local FLOOR_MATERIAL = Enum.Material.Basalt
local ICE_MATERIAL = Enum.Material.Glacier -- 벽의 푸른 얼음빛 무늬

local MITHRIL_COLOR = Color3.fromRGB(150, 205, 255)
local GOLD_COLOR = Color3.fromRGB(255, 195, 70)

local terrain = Workspace.Terrain

---------------------------------------------------------------- 도우미
-- 부품 하나 만들기
local function part(props, parent)
	local p = Instance.new(props.ClassName or "Part")
	props.ClassName = nil
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		p[key] = value
	end
	p.Parent = parent
	return p
end

-- 장식 부품 (안 부딪히고 광선에도 안 걸림: 바위 조준·벽 밀어내기를 방해하지 않게)
local function decor(props, parent)
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	props.CastShadow = false
	return part(props, parent)
end

local function folder(parent, name)
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

local function snap(value)
	return math.floor(value / VOXEL + 0.5) * VOXEL
end

-- 축 정렬 범위 (부품 모서리 기준)
local function boundsOf(instance)
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = -minV
	local list = instance:GetDescendants()
	if instance:IsA("BasePart") then
		table.insert(list, instance)
	end
	for _, d in list do
		if d:IsA("BasePart") then
			local cf, size = d.CFrame, d.Size
			local half = Vector3.new(
				math.abs(cf.RightVector.X) * size.X + math.abs(cf.UpVector.X) * size.Y + math.abs(cf.LookVector.X) * size.Z,
				math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y + math.abs(cf.LookVector.Y) * size.Z,
				math.abs(cf.RightVector.Z) * size.X + math.abs(cf.UpVector.Z) * size.Y + math.abs(cf.LookVector.Z) * size.Z
			) / 2
			minV = minV:Min(d.Position - half)
			maxV = maxV:Max(d.Position + half)
		end
	end
	if minV.X == math.huge then
		return nil, nil
	end
	return minV, maxV
end

-- 지형 상자 채우기 (모서리 두 점)
local function fillBox(minV, maxV, material)
	local size = maxV - minV
	if size.X <= 0 or size.Y <= 0 or size.Z <= 0 then
		return
	end
	terrain:FillBlock(CFrame.new((minV + maxV) / 2), size, material)
end

local mine = Workspace:FindFirstChild("Mine")
if not mine then
	warn("[BuildMineFloor3] Workspace/Mine이 없어요")
	return true
end
local floor2 = mine:FindFirstChild("Floor2")
local spawnsFolder = folder(Workspace, "OreSpawns")

---------------------------------------------------------------- 1. 바위 템플릿·아이콘 (철을 복제해 색 바꾸기)
-- 광맥 부품 고르기: 가장 큰 부품(바위 몸통)과 색이 다르거나 훨씬 작은 부품
local function recolor(model, style, withEffects)
	local parts = {}
	local biggest, biggestVolume = nil, 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			local volume = d.Size.X * d.Size.Y * d.Size.Z
			if volume > biggestVolume then
				biggest, biggestVolume = d, volume
			end
		end
	end
	if not biggest then
		return
	end
	local bodyColor = biggest.Color
	local function colorGap(a, b)
		return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B)
	end
	local veins = 0
	for _, p in parts do
		if p:IsA("UnionOperation") then
			p.UsePartColor = true
		end
		local volume = p.Size.X * p.Size.Y * p.Size.Z
		local isVein = p ~= biggest and (colorGap(p.Color, bodyColor) > 0.15 or volume < biggestVolume * 0.2)
		if isVein then
			veins += 1
			p.Color = style.Vein
			p.Material = if veins % 2 == 0 then Enum.Material.Foil else Enum.Material.Neon
		else
			p.Color = p.Color:Lerp(style.Body, 0.65)
		end
	end
	-- 광맥 부품이 따로 없으면(한 덩어리 바위) 몸통 겉에 반짝이 점을 붙인다
	if veins == 0 then
		local random = Random.new(7)
		local half = biggest.Size / 2
		for i = 1, 7 do
			local axis = random:NextInteger(1, 3)
			local sign = if random:NextNumber() < 0.5 then -1 else 1
			local offset = Vector3.new(
				if axis == 1 then sign * half.X * 0.92 else random:NextNumber(-0.7, 0.7) * half.X,
				if axis == 2 then math.abs(half.Y) * 0.92 else random:NextNumber(-0.5, 0.8) * half.Y,
				if axis == 3 then sign * half.Z * 0.92 else random:NextNumber(-0.7, 0.7) * half.Z
			)
			local size = math.max(0.3, math.min(half.X, half.Y, half.Z) * random:NextNumber(0.25, 0.45))
			local speck = part({
				Name = "Vein",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(size, size, size),
				CFrame = biggest.CFrame * CFrame.new(offset),
				Color = style.Vein,
				Material = if i % 2 == 0 then Enum.Material.Foil else Enum.Material.Neon,
				Anchored = biggest.Anchored,
				CanCollide = false,
				Massless = true,
			}, biggest.Parent)
			if not biggest.Anchored then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = biggest
				weld.Part1 = speck
				weld.Parent = speck
			end
		end
	end
	if withEffects then
		local light = Instance.new("PointLight")
		light.Color = style.Vein
		light.Range = style.LightRange
		light.Brightness = style.LightBrightness
		light.Shadows = false
		light.Parent = biggest
		if style.Sparkles then
			local sparkles = Instance.new("Sparkles")
			sparkles.SparkleColor = style.Vein
			sparkles.Parent = biggest
		end
	end
end

local STYLES = {
	Mithril = { Vein = MITHRIL_COLOR, Body = Color3.fromRGB(90, 100, 125), LightRange = 7, LightBrightness = 0.6, Sparkles = false },
	Orichalcum = { Vein = GOLD_COLOR, Body = Color3.fromRGB(115, 90, 65), LightRange = 11, LightBrightness = 1.3, Sparkles = true },
}

local templates = ServerStorage:FindFirstChild("Templates")
local oreTemplates = templates and templates:FindFirstChild("Ores")
local ironTemplate = oreTemplates and oreTemplates:FindFirstChild("IronOre")
local iconFolder = ReplicatedStorage:FindFirstChild("ItemIcons")
local ironIcon = iconFolder and iconFolder:FindFirstChild("IronOre")
for id, style in STYLES do
	-- 바위 템플릿 (사람이 직접 만든 것이면 그대로 둔다)
	if ironTemplate then
		local old = oreTemplates:FindFirstChild(id)
		if not old or old:GetAttribute("GeneratedBy") == GENERATED then
			if old then
				old:Destroy()
			end
			local copy = ironTemplate:Clone()
			copy.Name = id
			copy:SetAttribute("GeneratedBy", GENERATED)
			if copy:IsA("Model") then
				recolor(copy, style, true)
			else
				for _, variant in copy:GetChildren() do
					if variant:IsA("Model") then
						recolor(variant, style, true)
					end
				end
			end
			copy.Parent = oreTemplates
		end
	else
		warn(`[BuildMineFloor3] Templates/Ores/IronOre가 없어 {id} 바위 템플릿을 못 만들었어요`)
	end
	-- 가방 아이콘 (철 아이콘 복제, 빛은 아이콘에 필요 없음)
	if ironIcon then
		local old = iconFolder:FindFirstChild(id)
		if not old or old:GetAttribute("GeneratedBy") == GENERATED then
			if old then
				old:Destroy()
			end
			local copy = ironIcon:Clone()
			copy.Name = id
			copy:SetAttribute("GeneratedBy", GENERATED)
			recolor(copy, style, false)
			copy.Parent = iconFolder
		end
	end
end

---------------------------------------------------------------- 2. 2층의 3층 길 열기
-- 3층 길 근처의 판자(이름에 Plank·Board·Barricade·판자, 없으면 나무 재질 판)를 치운다
local PLANK_WORDS = { "plank", "board", "barric", "판자", "blocker" }
local KEEP_WORDS = { "beam", "support", "post", "pillar", "rail", "지지", "기둥", "track", "cart", "torch", "lantern", "frame", "틀" }
local function nameHas(instance, words)
	local name = string.lower(instance.Name)
	for _, word in words do
		if string.find(name, word, 1, true) then
			return true
		end
	end
	return false
end

local function openPlanks(portal)
	local center = portal.Position
	local opened = 0
	local candidates = {}
	for _, d in Workspace:GetDescendants() do
		if d:IsA("BasePart") and d ~= portal and not d:IsA("Terrain") and (d.Position - center).Magnitude <= 16 then
			table.insert(candidates, d)
		end
	end
	local function open(p)
		if p:GetAttribute("OpenedBy") ~= GENERATED then
			p:SetAttribute("OpenedBy", GENERATED)
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Transparency = 1
			for _, d in p:GetDescendants() do
				if d:IsA("SurfaceGui") or d:IsA("BillboardGui") or d:IsA("Decal") or d:IsA("Texture") then
					d.Enabled = false
					if d:IsA("Decal") or d:IsA("Texture") then
						d.Transparency = 1
					end
				end
			end
		end
		opened += 1
	end
	-- 이름으로 (부품 이름 또는 부모 모델 이름)
	for _, p in candidates do
		local holder = p.Parent
		if nameHas(p, PLANK_WORDS) or (holder and holder:IsA("Model") and nameHas(holder, PLANK_WORDS)) then
			if not nameHas(p, KEEP_WORDS) then
				open(p)
			end
		end
	end
	-- 이름으로 못 찾으면: 입구 가까이(10스터드)의 나무 재질 가로 판 (긴 쪽이 눕고, 입구 위쪽 틀보다 낮은 것)
	if opened == 0 then
		local portalTop = center.Y + portal.Size.Y / 2
		for _, p in candidates do
			local size = p.Size
			local long = if size.X >= size.Y and size.X >= size.Z then p.CFrame.RightVector
				elseif size.Y >= size.Z then p.CFrame.UpVector
				else p.CFrame.LookVector
			if (p.Position - center).Magnitude <= 10
				and (p.Material == Enum.Material.WoodPlanks or p.Material == Enum.Material.Wood)
				and math.abs(long.Y) < 0.5
				and p.Position.Y < portalTop - 2
				and not nameHas(p, KEEP_WORDS)
				and not p:FindFirstAncestor("Floor3Way")
			then
				open(p)
			end
		end
	end
	-- "공사 중" 글씨 끄기
	for _, d in Workspace:GetDescendants() do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and string.find(d.Text, "공사", 1, true) then
			local gui = d:FindFirstAncestorWhichIsA("LayerCollector")
			local adornee = gui and (gui:IsA("SurfaceGui") or gui:IsA("BillboardGui")) and (gui.Adornee or gui.Parent)
			if adornee and adornee:IsA("BasePart") and (adornee.Position - center).Magnitude <= 20 then
				gui.Enabled = false
			end
		end
	end
	return opened
end

-- 2층 미로 칸(경로점)과 그 칸이 바깥쪽으로 막힌 벽 방향
local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = { terrain }

local function floorBelow(position)
	local result = Workspace:Raycast(position + Vector3.new(0, 1, 0), Vector3.new(0, -40, 0), terrainParams)
	return if result then result.Position.Y else nil
end

-- 3층 길(TargetFloor=3)이 없으면 2층 도착점에서 가장 먼 칸의 바깥 벽에 새로 만든다
local function createFloor2Portal()
	local waypoints = floor2 and floor2:FindFirstChild("BatWaypoints")
	if not waypoints then
		warn("[BuildMineFloor3] 2층 BatWaypoints가 없어 3층 길을 못 만들었어요")
		return nil
	end
	local arrival = nil
	for _, a in CollectionService:GetTagged("MineArrival") do
		if a:IsA("BasePart") and a:GetAttribute("Floor") == 2 then
			arrival = a
		end
	end
	local from = if arrival then arrival.Position else floor2:GetPivot().Position
	local nodes = {}
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, wp in waypoints:GetChildren() do
		if wp:IsA("BasePart") then
			table.insert(nodes, wp)
			minX, maxX = math.min(minX, wp.Position.X), math.max(maxX, wp.Position.X)
			minZ, maxZ = math.min(minZ, wp.Position.Z), math.max(maxZ, wp.Position.Z)
		end
	end
	table.sort(nodes, function(a, b)
		local da = ((a.Position - from) * Vector3.new(1, 0, 1)).Magnitude
		local db = ((b.Position - from) * Vector3.new(1, 0, 1)).Magnitude
		return da > db
	end)
	for _, wp in nodes do
		local groundY = floorBelow(wp.Position)
		if groundY then
			-- 바깥쪽(미로 가장자리 쪽) 방향부터 벽을 찾는다
			local dirs = {}
			if wp.Position.X >= maxX - 1 then table.insert(dirs, Vector3.xAxis) end
			if wp.Position.X <= minX + 1 then table.insert(dirs, -Vector3.xAxis) end
			if wp.Position.Z >= maxZ - 1 then table.insert(dirs, Vector3.zAxis) end
			if wp.Position.Z <= minZ + 1 then table.insert(dirs, -Vector3.zAxis) end
			for _, dir in dirs do
				local origin = Vector3.new(wp.Position.X, groundY + 4, wp.Position.Z)
				local hit = Workspace:Raycast(origin, dir * 16, terrainParams)
				if hit then
					local wallPoint = Vector3.new(hit.Position.X, groundY, hit.Position.Z)
					local look = CFrame.lookAt(wallPoint, wallPoint + dir)
					local model = Instance.new("Model")
					model.Name = "Floor3Way"
					model:SetAttribute("GeneratedBy", GENERATED)
					model.Parent = floor2
					-- 벽에 붙은 까만 갱도 입구 + 나무 틀 + 파란빛
					local portal = part({
						Name = "Floor3Portal",
						Size = Vector3.new(10, 11, 2),
						CFrame = look * CFrame.new(0, 5.5, 0.6),
						Color = Color3.fromRGB(5, 5, 10),
						Material = Enum.Material.SmoothPlastic,
						CanCollide = false,
						CanQuery = false,
					}, model)
					portal:SetAttribute("WalkIn", true)
					portal:SetAttribute("TargetFloor", 3)
					portal:SetAttribute("Facing", -dir)
					CollectionService:AddTag(portal, "MinePortal")
					for _, x in { -5.6, 5.6 } do
						decor({ Name = "Frame", Size = Vector3.new(1.2, 12, 1.2), CFrame = look * CFrame.new(x, 6, -0.2), Color = Color3.fromRGB(105, 70, 40), Material = Enum.Material.Wood }, model)
					end
					decor({ Name = "Frame", Size = Vector3.new(12.4, 1.2, 1.2), CFrame = look * CFrame.new(0, 12, -0.2), Color = Color3.fromRGB(105, 70, 40), Material = Enum.Material.Wood }, model)
					local glow = decor({ Name = "Glow", Size = Vector3.new(1, 1, 1), Transparency = 1, CFrame = look * CFrame.new(0, 4, 3) }, model)
					local light = Instance.new("PointLight")
					light.Color = Color3.fromRGB(110, 160, 255)
					light.Range = 16
					light.Brightness = 1.5
					light.Parent = glow
					print(`[BuildMineFloor3] 2층에 3층 길이 없어 새로 만들었어요 ({math.floor(wallPoint.X)}, {math.floor(wallPoint.Y)}, {math.floor(wallPoint.Z)})`)
					return portal
				end
			end
		end
	end
	warn("[BuildMineFloor3] 2층 구석에서 벽을 못 찾아 3층 길을 못 만들었어요")
	return nil
end

local floor2Portals = {}
local floor2HasSurfaceExit = false
local floor3Model = mine:FindFirstChild("Floor3")
for _, portal in CollectionService:GetTagged("MinePortal") do
	if portal:IsA("BasePart") and portal:IsDescendantOf(Workspace) and not (floor3Model and portal:IsDescendantOf(floor3Model)) then
		local target = portal:GetAttribute("TargetFloor")
		if target == 3 then
			table.insert(floor2Portals, portal)
		elseif target == 0 and floor2 and portal:IsDescendantOf(floor2) then
			floor2HasSurfaceExit = true
		end
	end
end
-- 2층 모델 밖에 둔 지상 출구도 찾는다 (2층 범위 안)
if floor2 and not floor2HasSurfaceExit then
	local f2Min, f2Max = boundsOf(floor2)
	if f2Min then
		for _, portal in CollectionService:GetTagged("MinePortal") do
			local p = portal:IsA("BasePart") and portal.Position
			if p and portal:GetAttribute("TargetFloor") == 0
				and p.X >= f2Min.X and p.X <= f2Max.X and p.Y >= f2Min.Y and p.Y <= f2Max.Y and p.Z >= f2Min.Z and p.Z <= f2Max.Z
			then
				floor2HasSurfaceExit = true
			end
		end
	end
end
local openedPlanks = 0
if #floor2Portals == 0 and floor2 then
	local created = createFloor2Portal()
	if created then
		table.insert(floor2Portals, created)
	end
end
for _, portal in floor2Portals do
	openedPlanks += openPlanks(portal)
end

---------------------------------------------------------------- 3. 층을 지을지 정하기
local existing = mine:FindFirstChild("Floor3")
if existing then
	if existing:GetAttribute("GeneratedBy") ~= GENERATED then
		print("[BuildMineFloor3] 직접 만든 Floor3가 있어 층은 건드리지 않아요 (템플릿·2층 길만 정리)")
		return true
	end
	if existing:GetAttribute("Version") == VERSION then
		print(`[BuildMineFloor3] 3층은 이미 있어요 (2층 판자 {openedPlanks}개 치움)`)
		return true
	end
	-- 예전 버전: 지형 덩어리·부품을 지우고 새로 짓는다
	local bounds = existing:FindFirstChild("Bounds")
	local a = bounds and bounds:FindFirstChild("Min")
	local b = bounds and bounds:FindFirstChild("Max")
	if a and b then
		fillBox(a.Position:Min(b.Position), a.Position:Max(b.Position), Enum.Material.Air)
	end
	existing:Destroy()
end
for _, child in spawnsFolder:GetChildren() do
	if child:GetAttribute("GeneratedBy") == GENERATED then
		child:Destroy()
	end
end
if not floor2 then
	warn("[BuildMineFloor3] Workspace/Mine/Floor2가 없어 3층 위치를 못 정했어요")
	return true
end

---------------------------------------------------------------- 4. 위치: 2층 아래, 다른 층·구역과 안 겹치게 옆으로
local f2Min, f2Max = boundsOf(floor2)
if not f2Min then
	warn("[BuildMineFloor3] 2층 범위를 못 쟀어요")
	return true
end
local avoid = {} -- 피할 수평 범위 (다른 층 모델·광산 구역)
for _, child in mine:GetChildren() do
	if child:IsA("Model") and string.match(child.Name, "^Floor%d+$") then
		local a, b = boundsOf(child)
		if a then
			table.insert(avoid, { Min = a, Max = b })
		end
	end
end
for _, zone in CollectionService:GetTagged("MineZone") do
	if zone:IsA("BasePart") and zone:IsDescendantOf(Workspace) then
		local a, b = boundsOf(zone)
		table.insert(avoid, { Min = a, Max = b })
	end
end

-- 2층이 아직 지하로 안 옮겨졌어도 바다에서 안 보이게 MAX_FLOOR_Y보다 아래
local floorY = math.min(math.floor((f2Min.Y - cfg.Depth) / VOXEL) * VOXEL, MAX_FLOOR_Y)
local destroyHeight = Workspace.FallenPartsDestroyHeight
if floorY + SHELL_MIN.Y < destroyHeight + 40 then
	floorY = math.ceil((destroyHeight + 40 - SHELL_MIN.Y) / VOXEL) * VOXEL
end
local originX = snap(f2Max.X + GAP - SHELL_MIN.X)
local originZ = snap(f2Min.Z - SHELL_MIN.Z)
local function overlaps(ox, oz)
	local minX, maxX = ox + SHELL_MIN.X - GAP / 2, ox + SHELL_MAX.X + GAP / 2
	local minZ, maxZ = oz + SHELL_MIN.Z - GAP / 2, oz + SHELL_MAX.Z + GAP / 2
	for _, box in avoid do
		if box.Max.X >= minX and box.Min.X <= maxX and box.Max.Z >= minZ and box.Min.Z <= maxZ then
			return true
		end
	end
	return false
end
for _ = 1, 30 do
	if not overlaps(originX, originZ) then
		break
	end
	originX += GAP
end
local origin = Vector3.new(originX, floorY, originZ) -- (0,0)칸 중심의 바닥

-- 칸 중심 (바닥 높이)
local function cellCenter(c, r)
	return origin + Vector3.new(c * CELL, 0, r * CELL)
end

-- 칸 방 크기의 절반 (시작 방은 조금 넓게)
local function halfOf(c, r)
	return if c == 0 and r == 0 then 12 else HALF
end

---------------------------------------------------------------- 5. 미로 만들기 (고정 씨앗)
local rng = Random.new(cfg.Seed)
local function idx(c, r)
	return r * N + c + 1
end
local links = {} -- links[i][j] = true
for i = 1, N * N do
	links[i] = {}
end
local DIRS = {
	{ dc = 1, dr = 0, v = Vector3.xAxis },
	{ dc = -1, dr = 0, v = -Vector3.xAxis },
	{ dc = 0, dr = 1, v = Vector3.zAxis },
	{ dc = 0, dr = -1, v = -Vector3.zAxis },
}
local function inGrid(c, r)
	return c >= 0 and c < N and r >= 0 and r < N
end
local function link(c1, r1, c2, r2)
	links[idx(c1, r1)][idx(c2, r2)] = true
	links[idx(c2, r2)][idx(c1, r1)] = true
end
do
	local visited = { [idx(0, 0)] = true }
	local stack = { { 0, 0 } }
	while #stack > 0 do
		local top = stack[#stack]
		local options = {}
		for _, d in DIRS do
			local nc, nr = top[1] + d.dc, top[2] + d.dr
			if inGrid(nc, nr) and not visited[idx(nc, nr)] then
				table.insert(options, { nc, nr })
			end
		end
		if #options > 0 then
			local pick = options[rng:NextInteger(1, #options)]
			link(top[1], top[2], pick[1], pick[2])
			visited[idx(pick[1], pick[2])] = true
			table.insert(stack, pick)
		else
			table.remove(stack)
		end
	end
	-- 고리 몇 개 (막다른 길만 있으면 답답하다)
	local added, tries = 0, 0
	while added < cfg.ExtraLoops and tries < 200 do
		tries += 1
		local c, r = rng:NextInteger(0, N - 1), rng:NextInteger(0, N - 1)
		local d = DIRS[rng:NextInteger(1, 4)]
		local nc, nr = c + d.dc, r + d.dr
		if inGrid(nc, nr) and not links[idx(c, r)][idx(nc, nr)] and not (c == 0 and r == 0) then
			link(c, r, nc, nr)
			added += 1
		end
	end
end

-- 칸마다 이미 쓴 벽 방향 (장식·광석이 겹치지 않게). 키 = idx * 10 + 방향 번호
local usedSide = {}
local function sideKey(c, r, dirIndex)
	return idx(c, r) * 10 + dirIndex
end
-- 시작 방 북쪽(계단)·서쪽(지상 출구), 4층 길(5,5칸 남쪽)
usedSide[sideKey(0, 0, 4)] = true
usedSide[sideKey(0, 0, 2)] = true
usedSide[sideKey(N - 1, N - 1, 3)] = true

local function closedSides(c, r)
	local list = {}
	for i, d in DIRS do
		local nc, nr = c + d.dc, r + d.dr
		if not (inGrid(nc, nr) and links[idx(c, r)][idx(nc, nr)]) and not usedSide[sideKey(c, r, i)] then
			table.insert(list, i)
		end
	end
	return list
end

---------------------------------------------------------------- 6. 지형 파기
local shellMin = origin + SHELL_MIN
local shellMax = origin + SHELL_MAX
fillBox(shellMin, shellMax, WALL_MATERIAL)
fillBox(Vector3.new(shellMin.X, origin.Y - 8, shellMin.Z), Vector3.new(shellMax.X, origin.Y, shellMax.Z), FLOOR_MATERIAL)

local up = Vector3.new(0, HEIGHT, 0)
for c = 0, N - 1 do
	for r = 0, N - 1 do
		local center = cellCenter(c, r)
		local h = halfOf(c, r) -- 시작 방은 조금 넓게
		fillBox(center - Vector3.new(h, 0, h), center + Vector3.new(h, 0, h) + up, Enum.Material.Air)
		-- 동쪽·남쪽 이웃과 이어진 통로
		if c + 1 < N and links[idx(c, r)][idx(c + 1, r)] then
			fillBox(center - Vector3.new(0, 0, HALF), center + Vector3.new(CELL, 0, HALF) + up, Enum.Material.Air)
		end
		if r + 1 < N and links[idx(c, r)][idx(c, r + 1)] then
			fillBox(center - Vector3.new(HALF, 0, 0), center + Vector3.new(HALF, 0, CELL) + up, Enum.Material.Air)
		end
	end
end
-- 시작 방 북쪽 오르막 터널 (2층 길), 서쪽 터널 (지상 출구, 2층에 있을 때만)
local start = cellCenter(0, 0)
fillBox(start + Vector3.new(-HALF, 0, -28), start + Vector3.new(HALF, 24, -12), Enum.Material.Air)
if floor2HasSurfaceExit then
	fillBox(start + Vector3.new(-28, 0, -HALF), start + Vector3.new(-12, 24, HALF), Enum.Material.Air)
end
-- 반대편 구석 남쪽 내리막 터널 (4층 길)
local corner = cellCenter(N - 1, N - 1)
fillBox(corner + Vector3.new(-HALF, -8, HALF), corner + Vector3.new(HALF, HEIGHT, 28), Enum.Material.Air)

-- 벽의 얼음빛 무늬: 통로 벽 몇 군데를 Glacier로
do
	local patches = 0
	for _ = 1, 40 do
		local c, r = rng:NextInteger(0, N - 1), rng:NextInteger(0, N - 1)
		local center = cellCenter(c, r)
		local d = DIRS[rng:NextInteger(1, 4)].v
		local p = center + d * (HALF + 2) + Vector3.new(0, rng:NextInteger(1, 3) * 4, 0)
		local pMin = Vector3.new(snap(p.X) - 4, snap(p.Y) - 4, snap(p.Z) - 4)
		local ok = pcall(function()
			terrain:ReplaceMaterial(Region3.new(pMin, pMin + Vector3.new(8, 8, 8)), VOXEL, WALL_MATERIAL, ICE_MATERIAL)
		end)
		if ok then
			patches += 1
		end
	end
end

---------------------------------------------------------------- 7. 층 모델
local model = Instance.new("Model")
model.Name = "Floor3"
model:SetAttribute("GeneratedBy", GENERATED)
model:SetAttribute("Version", VERSION)
model.Parent = mine

-- 범위 표시: MoveMineUnderground가 층 범위(부품 기준)로 지형을 옮기므로 암반 모서리에 투명 부품을 둔다
local boundsFolder = folder(model, "Bounds")
for name, position in { Min = shellMin, Max = shellMax } do
	decor({ Name = name, Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(position), Transparency = 1 }, boundsFolder)
end

-- 광산 구역 (분위기·박쥐 범위)
local zoneMin = origin + Vector3.new(-32, -10, -32)
local zoneMax = origin + Vector3.new((N - 1) * CELL + 32, HEIGHT + 8, (N - 1) * CELL + 32)
local zone = decor({
	Name = "MineZone3",
	Size = zoneMax - zoneMin,
	CFrame = CFrame.new((zoneMin + zoneMax) / 2),
	Transparency = 1,
}, model)
zone:SetAttribute("Floor", 3)
CollectionService:AddTag(zone, "MineZone")

-- 박쥐·지도 경로점 (칸 중심, Index = 줄*6 + 칸 + 1, Links = 이어진 칸 Index)
local waypoints = folder(model, "BatWaypoints")
for r = 0, N - 1 do
	for c = 0, N - 1 do
		local linked = {}
		for j in links[idx(c, r)] do
			table.insert(linked, j)
		end
		table.sort(linked)
		local wp = decor({
			Name = `Waypoint{idx(c, r)}`,
			Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.new(cellCenter(c, r) + Vector3.new(0, 6, 0)),
			Transparency = 1,
		}, waypoints)
		wp:SetAttribute("Index", idx(c, r))
		wp:SetAttribute("Links", table.concat(linked, ","))
	end
end

-- 도착점 (계단 반대쪽을 보고 선다)
local arrival = decor({
	Name = "Floor3Arrival",
	Size = Vector3.new(4, 1, 4),
	CFrame = CFrame.lookAt(start + Vector3.new(0, 0.5, 4), start + Vector3.new(0, 0.5, 20)),
	Transparency = 1,
}, model)
arrival:SetAttribute("Floor", 3)
CollectionService:AddTag(arrival, "MineArrival")

local stairsFolder = folder(model, "Stairs")
local STONE = Color3.fromRGB(95, 95, 110)

-- 오르막 계단 (dir 방향으로 올라감). 끝에 걸어 들어가는 입구
local function upStairs(dir, targetFloor, glowColor, name)
	local right = Vector3.yAxis:Cross(dir) -- 계단 폭 방향
	for i = 1, 5 do
		local rise = i * 1.2
		local pos = start + dir * (12 + (i - 0.5) * 2) + Vector3.new(0, rise / 2, 0)
		part({
			Name = "Step",
			Size = Vector3.new(16, rise, 2),
			CFrame = CFrame.lookAt(pos, pos + dir),
			Color = STONE,
			Material = Enum.Material.Slate,
		}, stairsFolder)
	end
	local landing = start + dir * 25 + Vector3.new(0, 3, 0)
	part({ Name = "Landing", Size = Vector3.new(16, 6, 6), CFrame = CFrame.lookAt(landing, landing + dir), Color = STONE, Material = Enum.Material.Slate }, stairsFolder)
	-- 입구: 밝게 빛나는 막 (걸어 들어가면 이동)
	local portalPos = start + dir * 23 + Vector3.new(0, 6 + 6, 0)
	local portal = part({
		Name = name,
		Size = Vector3.new(14, 12, 1),
		CFrame = CFrame.lookAt(portalPos, portalPos + dir),
		Color = glowColor,
		Material = Enum.Material.Neon,
		Transparency = 0.55,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	}, model)
	portal:SetAttribute("WalkIn", true)
	portal:SetAttribute("TargetFloor", targetFloor)
	portal:SetAttribute("Facing", -dir)
	CollectionService:AddTag(portal, "MinePortal")
	local light = Instance.new("PointLight")
	light.Color = glowColor
	light.Range = 22
	light.Brightness = 1.6
	light.Parent = portal
	-- 나무 틀
	for _, x in { -7.5, 7.5 } do
		local p = portalPos + right * x + Vector3.new(0, 0.5, 0)
		decor({ Name = "Frame", Size = Vector3.new(1.2, 13, 1.2), CFrame = CFrame.lookAt(p, p + dir), Color = Color3.fromRGB(105, 70, 40), Material = Enum.Material.Wood }, model)
	end
	local top = portalPos + Vector3.new(0, 6.6, 0)
	decor({ Name = "Frame", Size = Vector3.new(16.2, 1.2, 1.2), CFrame = CFrame.lookAt(top, top + dir), Color = Color3.fromRGB(105, 70, 40), Material = Enum.Material.Wood }, model)
end
upStairs(-Vector3.zAxis, 2, Color3.fromRGB(255, 235, 190), "Floor2Portal")
if floor2HasSurfaceExit then
	upStairs(-Vector3.xAxis, 0, Color3.fromRGB(200, 255, 200), "ExitPortal")
end

-- 4층 길: 남쪽 내리막 + 판자 + 파란빛 (잠김. 닿으면 "공사 중" 알림 후 밀려남)
do
	local dir = Vector3.zAxis
	for i = 1, 5 do
		local topY = -i * 1.4
		local pos = corner + dir * (HALF + (i - 0.5) * 2) + Vector3.new(0, (topY - 8) / 2, 0)
		part({ Name = "DownStep", Size = Vector3.new(16, topY + 8, 2), CFrame = CFrame.lookAt(pos, pos + dir), Color = STONE, Material = Enum.Material.Slate }, stairsFolder)
	end
	local floorPos = corner + dir * 23 + Vector3.new(0, -7.5, 0)
	part({ Name = "DownFloor", Size = Vector3.new(16, 1, 10), CFrame = CFrame.lookAt(floorPos, floorPos + dir), Color = STONE, Material = Enum.Material.Slate }, stairsFolder)
	-- 판자 (가로로 여러 장, 살짝 비뚤게)
	for i, y in { -4, -1, 2, 5 } do
		local pos = corner + dir * 21 + Vector3.new(0, y, 0)
		part({
			Name = "Plank",
			Size = Vector3.new(17, 1.4, 0.5),
			CFrame = CFrame.lookAt(pos, pos + dir) * CFrame.Angles(0, 0, math.rad(if i % 2 == 0 then 4 else -5)),
			Color = Color3.fromRGB(125, 90, 55),
			Material = Enum.Material.WoodPlanks,
		}, model)
	end
	-- "공사 중" 표지판
	local signPos = corner + dir * 20.6 + Vector3.new(0, 0.5, 0)
	local sign = decor({ Name = "Sign", Size = Vector3.new(6, 2.4, 0.3), CFrame = CFrame.lookAt(signPos, signPos - dir), Color = Color3.fromRGB(230, 200, 90), Material = Enum.Material.Wood }, model)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "🔒 공사 중"
	label.TextScaled = true
	label.Font = Enum.Font.Cartoon
	label.TextColor3 = Color3.fromRGB(60, 35, 20)
	label.Parent = gui
	-- 판자 앞의 입구 판정 (보이지 않음)
	local portalPos = corner + dir * 19 + Vector3.new(0, 0, 0)
	local portal = part({
		Name = "Floor4Portal",
		Size = Vector3.new(16, 14, 2),
		CFrame = CFrame.lookAt(portalPos, portalPos + dir),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	}, model)
	portal:SetAttribute("WalkIn", true)
	portal:SetAttribute("TargetFloor", 4)
	portal:SetAttribute("Facing", -dir)
	CollectionService:AddTag(portal, "MinePortal")
	-- 판자 틈으로 새는 파란빛
	local glow = decor({ Name = "Glow", Size = Vector3.new(1, 1, 1), Transparency = 1, CFrame = CFrame.new(corner + dir * 25 + Vector3.new(0, -3, 0)) }, model)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(90, 140, 255)
	light.Range = 20
	light.Brightness = 2
	light.Parent = glow
end

---------------------------------------------------------------- 8. 장식: 파란 불꽃 벽 횃불, 파랑·금색 수정
local decorFolder = folder(model, "Decor")
local CRYSTAL_BLUE = Color3.fromRGB(110, 170, 255)
local CRYSTAL_GOLD = Color3.fromRGB(255, 200, 90)

-- 벽 횃불: 나무 막대 + 쇠 그릇 + 파란 불꽃 (속성 Flicker로 깜빡임)
local function wallTorch(c, r, dirIndex)
	local d = DIRS[dirIndex].v
	local base = cellCenter(c, r) + d * (halfOf(c, r) - 0.6) + Vector3.new(0, 7, 0)
	local m = Instance.new("Model")
	m.Name = "WallTorch"
	m.Parent = decorFolder
	local look = CFrame.lookAt(base, base - d)
	decor({ Name = "Stick", Size = Vector3.new(0.5, 2.6, 0.5), CFrame = look * CFrame.new(0, 0, -0.5) * CFrame.Angles(math.rad(-25), 0, 0), Color = Color3.fromRGB(95, 65, 40), Material = Enum.Material.Wood }, m)
	decor({ Name = "Bowl", Size = Vector3.new(1, 0.5, 1), CFrame = look * CFrame.new(0, 1.2, -1.1), Color = Color3.fromRGB(60, 60, 70), Material = Enum.Material.Metal }, m)
	local flame = decor({ Name = "Flame", Shape = Enum.PartType.Ball, Size = Vector3.new(0.8, 0.8, 0.8), CFrame = look * CFrame.new(0, 1.7, -1.1), Color = Color3.fromRGB(120, 190, 255), Material = Enum.Material.Neon }, m)
	flame:SetAttribute("Flicker", true)
	local fire = Instance.new("Fire")
	fire.Color = Color3.fromRGB(90, 150, 255)
	fire.SecondaryColor = Color3.fromRGB(220, 240, 255)
	fire.Size = 2.5
	fire.Heat = 6
	fire.Parent = flame
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(140, 190, 255)
	light.Range = 18
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = flame
end

-- 수정 덩어리: 벽 밑(바닥) 또는 천장에서 자란 길쭉한 수정 몇 개 + 빛 하나
local function crystalCluster(position, color, hanging)
	local m = Instance.new("Model")
	m.Name = "Crystal"
	m.Parent = decorFolder
	local count = rng:NextInteger(3, 5)
	for i = 1, count do
		local h = rng:NextNumber(2.5, 6)
		local w = rng:NextNumber(0.7, 1.4)
		local tilt = CFrame.Angles(math.rad(rng:NextNumber(-28, 28)), math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(-28, 28)))
		local offset = Vector3.new(rng:NextNumber(-1.5, 1.5), 0, rng:NextNumber(-1.5, 1.5))
		local cf = CFrame.new(position + offset) * tilt * CFrame.new(0, if hanging then -h / 2 + 0.5 else h / 2 - 0.5, 0)
		decor({
			Name = "Shard",
			Size = Vector3.new(w, h, w),
			CFrame = cf,
			Color = color:Lerp(Color3.new(1, 1, 1), rng:NextNumber(0, 0.25)),
			Material = if i == 1 then Enum.Material.Neon else Enum.Material.Glass,
			Transparency = if i == 1 then 0.1 else 0.25,
			Reflectance = 0.1,
		}, m)
	end
	local glow = decor({ Name = "Glow", Size = Vector3.new(0.5, 0.5, 0.5), Transparency = 1, CFrame = CFrame.new(position + Vector3.new(0, if hanging then -2 else 2, 0)) }, m)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 14
	light.Brightness = 1.1
	light.Shadows = false
	light.Parent = glow
end

-- 칸 순서를 섞는다
local cellOrder = {}
for r = 0, N - 1 do
	for c = 0, N - 1 do
		table.insert(cellOrder, { c, r })
	end
end
for i = #cellOrder, 2, -1 do
	local j = rng:NextInteger(1, i)
	cellOrder[i], cellOrder[j] = cellOrder[j], cellOrder[i]
end

-- 시작 방: 횃불 두 개 (동·남 벽이 막혀 있으면)
local torches, crystals = 0, 0
for _, cell in cellOrder do
	local c, r = cell[1], cell[2]
	local sides = closedSides(c, r)
	if #sides > 0 and (torches < 12) and (c + r) % 2 == 0 then
		local s = sides[rng:NextInteger(1, #sides)]
		usedSide[sideKey(c, r, s)] = true
		wallTorch(c, r, s)
		torches += 1
	end
end
for _, cell in cellOrder do
	local c, r = cell[1], cell[2]
	if not (c == 0 and r == 0) and rng:NextNumber() < 0.6 then
		local center = cellCenter(c, r)
		-- 구석(벽 모서리)에 바닥 수정, 가끔 천장에 매달린 수정
		local corners = { Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, -1) }
		local k = corners[rng:NextInteger(1, 4)]
		local color = if rng:NextNumber() < 0.3 then CRYSTAL_GOLD else CRYSTAL_BLUE
		crystalCluster(center + k * (HALF - 1.5), color, false)
		crystals += 1
		if rng:NextNumber() < 0.35 then
			crystalCluster(center + Vector3.new(rng:NextNumber(-4, 4), HEIGHT, rng:NextNumber(-4, 4)), CRYSTAL_BLUE, true)
			crystals += 1
		end
	end
end

---------------------------------------------------------------- 9. 광석 자리
local function addSpawn(position, oreType, pool)
	local p = part({
		Name = `{oreType}Spawn`,
		Size = Vector3.new(2, 1, 2),
		CFrame = CFrame.new(position),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	}, spawnsFolder)
	p:SetAttribute("OreType", oreType)
	p:SetAttribute("Floor", 3)
	p:SetAttribute("GeneratedBy", GENERATED)
	if pool then
		p:SetAttribute("RandomPool", pool)
	end
end

-- 벽 쪽 자리: 칸 중심에서 막힌 벽 방향으로 5스터드, 벽을 따라 조금 비껴서
local function wallSpot(c, r, dirIndex, along)
	local d = DIRS[dirIndex].v
	local side = Vector3.yAxis:Cross(d)
	return cellCenter(c, r) + d * 5 + side * along + Vector3.new(0, 1.5, 0)
end

-- 시작 칸에서 걸어서 몇 칸인지 (멀수록 오리하르콘 후보)
local distance = { [idx(0, 0)] = 0 }
do
	local queue = { { 0, 0 } }
	local head = 1
	while queue[head] do
		local cur = queue[head]
		head += 1
		for _, d in DIRS do
			local nc, nr = cur[1] + d.dc, cur[2] + d.dr
			if inGrid(nc, nr) and links[idx(cur[1], cur[2])][idx(nc, nr)] and distance[idx(nc, nr)] == nil then
				distance[idx(nc, nr)] = distance[idx(cur[1], cur[2])] + 1
				table.insert(queue, { nc, nr })
			end
		end
	end
end

-- 오리하르콘 후보: 막다른 길을 먼저, 시작에서 먼 순서
local candidates = {}
for r = 0, N - 1 do
	for c = 0, N - 1 do
		local count = 0
		for _ in links[idx(c, r)] do
			count += 1
		end
		if not (c == 0 and r == 0) then
			table.insert(candidates, { c = c, r = r, score = (distance[idx(c, r)] or 0) + (if count == 1 then 6 else 0) + rng:NextNumber() })
		end
	end
end
table.sort(candidates, function(a, b)
	return a.score > b.score
end)
local orichalcumCells = {}
local orichalcum = 0
for _, cand in candidates do
	if orichalcum >= cfg.OrichalcumCandidates then
		break
	end
	local sides = closedSides(cand.c, cand.r)
	if #sides > 0 then
		local s = sides[rng:NextInteger(1, #sides)]
		usedSide[sideKey(cand.c, cand.r, s)] = true
		addSpawn(wallSpot(cand.c, cand.r, s, 0), "Orichalcum", "Orichalcum")
		orichalcumCells[idx(cand.c, cand.r)] = true
		orichalcum += 1
	end
end

-- 미스릴: 섞은 칸 순서대로 벽에 붙여, PairChance로 두 개
local mithril = 0
for pass = 1, 3 do
	for _, cell in cellOrder do
		if mithril >= cfg.MithrilSpawns then
			break
		end
		local c, r = cell[1], cell[2]
		local isStart = c == 0 and r == 0
		if not isStart and (pass > 1 or not orichalcumCells[idx(c, r)]) then
			local sides = closedSides(c, r)
			if #sides > 0 then
				local s = sides[rng:NextInteger(1, #sides)]
				usedSide[sideKey(c, r, s)] = true
				if rng:NextNumber() < cfg.PairChance then
					addSpawn(wallSpot(c, r, s, -2.6), "Mithril")
					addSpawn(wallSpot(c, r, s, 2.6), "Mithril")
					mithril += 2
				else
					addSpawn(wallSpot(c, r, s, rng:NextNumber(-3, 3)), "Mithril")
					mithril += 1
				end
			end
		end
	end
end

print(
	`[BuildMineFloor3] 3층 완료: 원점 ({origin.X}, {origin.Y}, {origin.Z}), 미스릴 자리 {mithril}, 오리하르콘 후보 {orichalcum}(동시에 {Config.RandomPools.Orichalcum.Active}), 횃불 {torches}, 수정 {crystals}, 2층 판자 {openedPlanks}개 치움{if floor2HasSurfaceExit then ", 지상 출구 있음" else ""}`
)
return true
