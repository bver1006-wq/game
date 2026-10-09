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
	-- 둥근 모험가 배낭: 위쪽 손잡이, 그라데이션 가죽 몸통, 덮개와 금 버클, 앞주머니, 바느질, 왼쪽 윤기
	local leather = Color3.fromRGB(196, 128, 64)
	local leatherDark = Color3.fromRGB(128, 76, 34)
	local outline = Color3.fromRGB(64, 36, 16)
	local function gradient(target: GuiObject, top: Color3, bottom: Color3)
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new(top, bottom)
		g.Rotation = 90
		g.Parent = target
	end
	local function frame(name: string, anchor: Vector2, position: UDim2, size: UDim2, color: Color3, radius: number, z: number, parentFrame: Instance?): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.AnchorPoint = anchor
		f.Position = position
		f.Size = size
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.ZIndex = z
		f.Parent = parentFrame or parent
		UiKit.corner(f, radius)
		return f
	end

	-- 손잡이 (두꺼운 고리)
	local handle = frame("Handle", Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0), UDim2.fromScale(0.38, 0.3), Color3.new(0, 0, 0), 100, 1)
	handle.BackgroundTransparency = 1
	local handleStroke = Instance.new("UIStroke")
	handleStroke.Color = leatherDark
	handleStroke.Thickness = 4
	handleStroke.Parent = handle

	-- 몸통
	local body = frame("Body", Vector2.new(0.5, 1), UDim2.fromScale(0.5, 1), UDim2.fromScale(0.9, 0.8), leather, 16, 2)
	gradient(body, Color3.fromRGB(225, 160, 92), Color3.fromRGB(160, 98, 46))
	UiKit.stroke(body, outline, 2)
	-- 왼쪽 윤기
	local shine = frame("Shine", Vector2.new(0, 0), UDim2.fromScale(0.1, 0.42), UDim2.fromScale(0.08, 0.38), Color3.new(1, 1, 1), 6, 3, body)
	shine.BackgroundTransparency = 0.65

	-- 덮개 (위쪽 절반, 아래 모서리 둥글게)
	local flap = frame("Flap", Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0), UDim2.fromScale(1, 0.46), leatherDark, 16, 4, body)
	gradient(flap, Color3.fromRGB(150, 92, 44), Color3.fromRGB(110, 64, 28))
	UiKit.stroke(flap, outline, 2)
	-- 덮개 바느질 (점선)
	for i = 0, 6 do
		local stitch = frame("Stitch", Vector2.new(0.5, 0.5), UDim2.fromScale(0.14 + i * 0.12, 0.82), UDim2.fromScale(0.06, 0.06), Color3.fromRGB(240, 205, 150), 2, 5, flap)
		stitch.BackgroundTransparency = 0.15
	end
	-- 버클 띠 + 금 버클
	frame("Strap", Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.3), UDim2.fromScale(0.16, 0.32), leatherDark, 3, 5, body)
	local buckle = frame("Buckle", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.26, 0.18), Color3.fromRGB(250, 205, 70), 4, 6, body)
	gradient(buckle, Color3.fromRGB(255, 230, 120), Color3.fromRGB(215, 160, 40))
	UiKit.stroke(buckle, Color3.fromRGB(120, 80, 10), 1.5)
	frame("Hole", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.45, 0.4), Color3.fromRGB(110, 64, 28), 2, 7, buckle)

	-- 앞주머니
	local pocket = frame("Pocket", Vector2.new(0.5, 1), UDim2.fromScale(0.5, 0.94), UDim2.fromScale(0.62, 0.3), Color3.fromRGB(176, 110, 52), 8, 4, body)
	gradient(pocket, Color3.fromRGB(205, 140, 78), Color3.fromRGB(150, 90, 40))
	UiKit.stroke(pocket, outline, 1.5)
	return body
end

return UiKit
