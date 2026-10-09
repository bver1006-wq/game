--!strict
-- 아이템 아이콘: ReplicatedStorage/ItemIcons의 작은 3D 모델을 ViewportFrame에 비춰서 그린다.
-- 아이콘 모델이 없으면 아이템 색으로 칠한 네모를 대신 그린다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

-- parent를 꽉 채우는 아이콘을 만든다
function ItemIcon.create(parent: GuiObject, itemId: string): GuiObject
	local def = ItemDefs.Items[itemId]
	local template = def and findIconModel(def.Icon)
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
