--!strict
-- UI 만들기 도우미. 가방·상점·알림 UI가 같은 모양을 쓰도록 모아 둔다.

local UiKit = {}

UiKit.Colors = {
	Panel = Color3.fromRGB(38, 32, 28),
	PanelLight = Color3.fromRGB(58, 49, 42),
	Border = Color3.fromRGB(120, 95, 60),
	Text = Color3.fromRGB(245, 235, 215),
	SubText = Color3.fromRGB(190, 175, 150),
	Gold = Color3.fromRGB(255, 205, 70),
	Good = Color3.fromRGB(110, 200, 90),
	Bad = Color3.fromRGB(225, 85, 70),
	Button = Color3.fromRGB(205, 140, 55),
	ButtonDisabled = Color3.fromRGB(90, 80, 70),
}

-- 둥근 모서리
function UiKit.corner(parent: Instance, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 10)
	corner.Parent = parent
end

-- 테두리
function UiKit.stroke(parent: Instance, color: Color3?, thickness: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or UiKit.Colors.Border
	stroke.Thickness = thickness or 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
end

-- 패널(배경 상자)
function UiKit.panel(parent: Instance, size: UDim2, position: UDim2, anchor: Vector2?): Frame
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = position
	frame.AnchorPoint = anchor or Vector2.zero
	frame.BackgroundColor3 = UiKit.Colors.Panel
	frame.BorderSizePixel = 0
	frame.Parent = parent
	UiKit.corner(frame, 12)
	UiKit.stroke(frame)
	return frame
end

-- 글자
function UiKit.label(parent: Instance, text: string, size: UDim2, position: UDim2?, color: Color3?, textSize: number?): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = position or UDim2.new()
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = color or UiKit.Colors.Text
	label.TextSize = textSize or 16
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Parent = parent
	return label
end

-- 버튼. enabled가 false면 회색으로 눌리지 않는다
function UiKit.button(parent: Instance, text: string, size: UDim2, position: UDim2?, onClick: () -> (), enabled: boolean?): TextButton
	local isEnabled = enabled ~= false
	local button = Instance.new("TextButton")
	button.Size = size
	button.Position = position or UDim2.new()
	button.BackgroundColor3 = if isEnabled then UiKit.Colors.Button else UiKit.Colors.ButtonDisabled
	button.AutoButtonColor = isEnabled
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextColor3 = if isEnabled then Color3.new(1, 1, 1) else UiKit.Colors.SubText
	button.TextSize = 15
	button.BorderSizePixel = 0
	button.Parent = parent
	UiKit.corner(button, 8)
	if isEnabled then
		button.Activated:Connect(onClick)
	end
	return button
end

-- 아이템 색 네모 (아이콘 대신)
function UiKit.swatch(parent: Instance, color: Color3, size: number, position: UDim2?): Frame
	local swatch = Instance.new("Frame")
	swatch.Size = UDim2.fromOffset(size, size)
	swatch.Position = position or UDim2.new()
	swatch.BackgroundColor3 = color
	swatch.BorderSizePixel = 0
	swatch.Parent = parent
	UiKit.corner(swatch, 6)
	UiKit.stroke(swatch, Color3.new(0, 0, 0), 1)
	return swatch
end

-- 세로 목록 (스크롤)
function UiKit.list(parent: Instance, size: UDim2, position: UDim2?): ScrollingFrame
	local list = Instance.new("ScrollingFrame")
	list.Size = size
	list.Position = position or UDim2.new()
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	return list
end

-- 목록 한 줄 (배경 있는 행)
function UiKit.row(parent: Instance, height: number, order: number): Frame
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -8, 0, height)
	row.BackgroundColor3 = UiKit.Colors.PanelLight
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.Parent = parent
	UiKit.corner(row, 8)
	return row
end

-- 가방 그림 (가죽 가방 몸통 + 덮개 + 손잡이 + 버클). parent를 꽉 채운다
function UiKit.bagIcon(parent: Instance)
	local leather = Color3.fromRGB(150, 95, 50)
	local dark = Color3.fromRGB(105, 62, 30)
	-- 손잡이 (둥근 테두리만)
	local handle = Instance.new("Frame")
	handle.AnchorPoint = Vector2.new(0.5, 0)
	handle.Position = UDim2.fromScale(0.5, 0.04)
	handle.Size = UDim2.fromScale(0.5, 0.4)
	handle.BackgroundTransparency = 1
	handle.Parent = parent
	UiKit.corner(handle, 100)
	local handleStroke = Instance.new("UIStroke")
	handleStroke.Color = dark
	handleStroke.Thickness = 5
	handleStroke.Parent = handle
	-- 몸통
	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(0.5, 1)
	body.Position = UDim2.fromScale(0.5, 0.96)
	body.Size = UDim2.fromScale(0.86, 0.68)
	body.BackgroundColor3 = leather
	body.BorderSizePixel = 0
	body.Parent = parent
	UiKit.corner(body, 12)
	UiKit.stroke(body, Color3.fromRGB(60, 35, 15), 2)
	-- 덮개
	local flap = Instance.new("Frame")
	flap.Size = UDim2.fromScale(1, 0.42)
	flap.BackgroundColor3 = dark
	flap.BorderSizePixel = 0
	flap.Parent = body
	UiKit.corner(flap, 12)
	-- 버클
	local buckle = Instance.new("Frame")
	buckle.AnchorPoint = Vector2.new(0.5, 0.5)
	buckle.Position = UDim2.fromScale(0.5, 0.42)
	buckle.Size = UDim2.fromScale(0.22, 0.2)
	buckle.BackgroundColor3 = Color3.fromRGB(240, 200, 80)
	buckle.BorderSizePixel = 0
	buckle.ZIndex = 2
	buckle.Parent = body
	UiKit.corner(buckle, 4)
	return body
end

return UiKit
