--!strict
-- 아이템 아이콘: ReplicatedStorage/ItemIcons의 작은 3D 모델을 ViewportFrame에 비춰서 그린다.
-- 아이콘 모델이 없으면 아이템 색으로 칠한 네모를 대신 그린다.
-- 화살통은 Studio 아이콘 모델이 없으면 여기서 부품으로 아이콘을 지어 쓴다 (buildQuiverIcon).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EquipmentDefs = require(ReplicatedStorage.Shared.EquipmentDefs)
local ItemDefs = require(ReplicatedStorage.Shared.ItemDefs)

local ICON_FOLDER_NAME = "ItemIcons"
local VIEW_ANGLE = CFrame.Angles(math.rad(-25), math.rad(35), 0) -- 아이콘을 비스듬히 위에서 본다

local ItemIcon = {}

-- 아이콘 모델 원본을 찾는다
local function findIconModel(iconName: string): Model?
	local folder = ReplicatedStorage:FindFirstChild(ICON_FOLDER_NAME)
	local model = folder and folder:FindFirstChild(iconName)
	return if model and model:IsA("Model") then model else nil
end

local builtIcons: { [string]: Model } = {} -- 코드로 지은 아이콘 원본 (한 번만 짓는다)

-- 아이콘용 부품 하나
local function iconPart(model: Model, shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material)
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
end

-- 화살통 아이콘: 비스듬한 가죽 통 + 금속 테 + 화살 다섯 개 (빨강·흰 깃)
local function buildQuiverIcon(def: EquipmentDefs.EquipmentDef): Model
	local model = Instance.new("Model")
	local up = CFrame.Angles(0, 0, math.pi / 2) -- 원기둥을 세운다
	local base = CFrame.Angles(0, 0, math.rad(-20))
	-- 테 색: 1 황동 / 3 철 / 5 미스릴(은빛 파랑, 2026-10-09)
	local rim = if def.Tier >= 5 then Color3.fromRGB(150, 200, 255) elseif def.Tier >= 3 then Color3.fromRGB(170, 176, 188) else Color3.fromRGB(205, 160, 75)
	local vane = if def.Tier >= 5 then Color3.fromRGB(90, 170, 255) elseif def.Tier >= 3 then Color3.fromRGB(70, 130, 230) else Color3.fromRGB(215, 60, 55)
	iconPart(model, Enum.PartType.Cylinder, Vector3.new(2, 0.75, 0.75), base * up, def.Color, Enum.Material.Leather)
	iconPart(model, Enum.PartType.Cylinder, Vector3.new(0.14, 0.86, 0.86), base * CFrame.new(0, 0.95, 0) * up, rim, Enum.Material.Metal)
	iconPart(model, Enum.PartType.Cylinder, Vector3.new(0.1, 0.8, 0.8), base * CFrame.new(0, -0.95, 0) * up, def.Color:Lerp(Color3.new(0, 0, 0), 0.35), Enum.Material.Leather)
	iconPart(model, Enum.PartType.Cylinder, Vector3.new(0.08, 0.8, 0.8), base * CFrame.new(0, 0.2, 0) * up, rim, Enum.Material.Metal)
	iconPart(model, Enum.PartType.Block, Vector3.new(0.12, 1.5, 0.05), base * CFrame.new(0, -0.1, -0.38), Color3.fromRGB(232, 205, 150), Enum.Material.Fabric)
	for i = 1, 5 do
		local angle = i / 5 * math.pi * 2
		local frame = base * CFrame.new(math.cos(angle) * 0.2, 1.3 + (i % 2) * 0.08, math.sin(angle) * 0.2)
		iconPart(model, Enum.PartType.Cylinder, Vector3.new(0.8, 0.07, 0.07), frame * up, Color3.fromRGB(214, 178, 128), Enum.Material.Wood)
		local color = if i % 2 == 1 then vane else Color3.fromRGB(248, 246, 238)
		iconPart(model, Enum.PartType.Block, Vector3.new(0.24, 0.3, 0.02), frame * CFrame.new(0, 0.22, 0), color, Enum.Material.Fabric)
		iconPart(model, Enum.PartType.Block, Vector3.new(0.24, 0.3, 0.02), frame * CFrame.new(0, 0.22, 0) * CFrame.Angles(0, math.pi / 2, 0), color, Enum.Material.Fabric)
	end
	return model
end

-- 코드로 짓는 아이콘 (지금은 화살통만). 없으면 nil
local function builtIconModel(itemId: string): Model?
	local cached = builtIcons[itemId]
	if cached then
		return cached
	end
	local equipment = EquipmentDefs.Items[itemId]
	if equipment and equipment.Quiver then -- 방패(2026-10-10)는 Studio 아이콘 모델(BuildWeaponsAndMobs)을 쓴다
		local model = buildQuiverIcon(equipment)
		builtIcons[itemId] = model
		return model
	end
	return nil
end

-- 아이콘 모델 원본 (복제해서 쓸 것). 없으면 nil. 아이템 상세 창(ItemDetailUI)이 크게 돌려 보일 때 쓴다
function ItemIcon.getModel(itemId: string): Model?
	local def = ItemDefs.Items[itemId]
	if not def then
		return nil
	end
	return findIconModel(def.Icon) or builtIconModel(itemId)
end

-- parent를 꽉 채우는 아이콘을 만든다
function ItemIcon.create(parent: GuiObject, itemId: string): GuiObject
	local def = ItemDefs.Items[itemId]
	local template = def and (findIconModel(def.Icon) or builtIconModel(itemId))
	if not def or not template then
		local swatch = Instance.new("Frame")
		swatch.AnchorPoint = Vector2.new(0.5, 0.5)
		swatch.Position = UDim2.fromScale(0.5, 0.5)
		swatch.Size = UDim2.fromScale(0.6, 0.6)
		swatch.BackgroundColor3 = if def then def.Color else Color3.new(1, 0, 1)
		swatch.BorderSizePixel = 0
		swatch.Parent = parent
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.2, 0)
		corner.Parent = swatch
		return swatch
	end

	local viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(170, 170, 170)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-1, -2, -1)
	viewport.Parent = parent

	local model = template:Clone()
	model:PivotTo(CFrame.new())
	model.Parent = viewport

	-- 모델 크기에 맞춰 카메라를 뒤로 뺀다
	local boxCFrame, boxSize = model:GetBoundingBox()
	local radius = boxSize.Magnitude / 2
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * 1.05
	camera.CFrame = CFrame.new(boxCFrame.Position) * VIEW_ANGLE * CFrame.new(0, 0, distance)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return viewport
end

return ItemIcon
