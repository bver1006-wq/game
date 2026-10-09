--!strict
-- 장비 창 (가방 창 왼쪽, 2026-10-09 사용자 요청으로 새로 그림): 똑바로 선 로블록스 사람 그림 + 몸 위치마다 장비 칸 네모.
-- 사람 그림: 내 캐릭터를 복제해 ViewportFrame에 정면으로 세운다 (애니메이션 없이 관절 기본 자세 = 차렷).
--   복제가 안 되면(캐릭터 없음 등) 둥근 네모로 만든 블록 사람(노란 머리·팔, 파란 몸, 초록 다리)을 대신 그린다
-- 칸: 헬멧=머리, 목걸이=목, 갑옷=가슴, 방패(화살통)=등·왼쪽 어깨, 장갑=왼손, 팔찌=오른 손목, 무기=오른손, 신발=발.
--   정면에서 보므로 캐릭터의 오른손은 화면 왼쪽이다. 칸에서 몸까지 가는 선을 긋는다
-- 칸을 한 번 누르면 그 아이템 상세 창, 두 번 빠르게 누르면 장비를 뺀다 (무기 칸은 빼지 않음). 아래에 전투력·능력치
-- 모든 위치는 정사각형에 가까운 무대(stage) 비율 좌표라 휴대폰에서도 같이 줄어든다. 수치는 Config.EquipFigure

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local EquipmentDefs = require(ReplicatedStorage.Shared.EquipmentDefs)
local ItemDefs = require(ReplicatedStorage.Shared.ItemDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ItemIcon = require(script.Parent.ItemIcon)
local UiKit = require(script.Parent.UiKit)

local localPlayer = Players.LocalPlayer

local DOUBLE_CLICK = 0.4 -- 이 시간 안에 두 번 누르면 빼기(초)
local STAGE_ASPECT = 0.8 -- 무대 너비/높이
local SLOT_W = 0.22 -- 칸 너비 (무대 너비 비율)
local SLOT_H = SLOT_W * STAGE_ASPECT -- 칸 높이 (무대 높이 비율, 정사각형이 되게)
local LEFT_X = 0.12 -- 왼쪽 칸 줄 가운데
local RIGHT_X = 0.88 -- 오른쪽 칸 줄 가운데
local ROW_Y = { 0.11, 0.37, 0.63, 0.89 } -- 칸 줄 높이 (무대 높이 비율)
-- 캐릭터 복제를 비추는 칸 (무대 비율): 가운데 세로로 긴 상자
local FIG_X, FIG_Y, FIG_W, FIG_H = 0.25, 0.04, 0.5, 0.86
local FIG_ASPECT = FIG_W / (FIG_H / STAGE_ASPECT) -- 그 상자의 실제 너비/높이

-- 몸 위치 이름 → 블록 사람 그림에서의 위치 (무대 비율). 복제 캐릭터면 실제 부품 위치로 바꾼다
local FALLBACK_ANCHORS: { [string]: Vector2 } = {
	Head = Vector2.new(0.43, 0.155),
	Neck = Vector2.new(0.53, 0.228),
	Chest = Vector2.new(0.42, 0.36),
	Back = Vector2.new(0.70, 0.27),
	RightWrist = Vector2.new(0.315, 0.455),
	RightHand = Vector2.new(0.315, 0.505),
	LeftHand = Vector2.new(0.685, 0.505),
	Feet = Vector2.new(0.5625, 0.835),
}

-- 복제 캐릭터에서 몸 위치 찾기: 부품 이름 후보(R15 먼저, R6 다음)와 부품 안 위치(크기 비율, +X = 캐릭터 오른쪽, +Z = 등 쪽)
type AnchorPart = { Name: string, Offset: Vector3 }
local CHARACTER_ANCHORS: { [string]: { AnchorPart } } = {
	Head = { { Name = "Head", Offset = Vector3.new(0.35, 0, 0) } },
	Neck = { { Name = "Head", Offset = Vector3.new(-0.15, -0.55, 0) } },
	Chest = { { Name = "UpperTorso", Offset = Vector3.new(0.25, 0, 0) }, { Name = "Torso", Offset = Vector3.new(0.25, 0.1, 0) } },
	Back = { { Name = "UpperTorso", Offset = Vector3.new(-0.45, 0.35, 0.3) }, { Name = "Torso", Offset = Vector3.new(-0.45, 0.4, 0.3) } },
	RightWrist = { { Name = "RightLowerArm", Offset = Vector3.new(0, -0.35, 0) }, { Name = "Right Arm", Offset = Vector3.new(0, -0.25, 0) } },
	RightHand = { { Name = "RightHand", Offset = Vector3.zero }, { Name = "Right Arm", Offset = Vector3.new(0, -0.45, 0) } },
	LeftHand = { { Name = "LeftHand", Offset = Vector3.zero }, { Name = "Left Arm", Offset = Vector3.new(0, -0.45, 0) } },
	Feet = { { Name = "LeftFoot", Offset = Vector3.zero }, { Name = "Left Leg", Offset = Vector3.new(0, -0.4, 0) } },
}

-- 칸 배치: 어느 줄(왼쪽/오른쪽, 몇 번째)에 두고 몸 어디와 잇는지
type SlotPlace = { Side: number, Row: number, Anchor: string } -- Side -1 = 화면 왼쪽, 1 = 오른쪽
local SLOT_PLACES: { [string]: SlotPlace } = {
	Helmet = { Side = -1, Row = 1, Anchor = "Head" },
	Armor = { Side = -1, Row = 2, Anchor = "Chest" },
	Bracelet = { Side = -1, Row = 3, Anchor = "RightWrist" },
	Weapon = { Side = -1, Row = 4, Anchor = "RightHand" },
	Necklace = { Side = 1, Row = 1, Anchor = "Neck" },
	Shield = { Side = 1, Row = 2, Anchor = "Back" },
	Gloves = { Side = 1, Row = 3, Anchor = "LeftHand" },
	Boots = { Side = 1, Row = 4, Anchor = "Feet" },
}

-- 블록 사람 색 (로블록스 기본 캐릭터 느낌)
local SKIN = Color3.fromRGB(245, 205, 48)
local SHIRT = Color3.fromRGB(13, 105, 172)
local PANTS = Color3.fromRGB(164, 189, 71)

type SlotView = { Button: TextButton, Inner: Frame, Label: TextLabel, Badge: TextLabel, Stroke: UIStroke }

local EquipmentPanel = {}

local panel: Frame
local stage: Frame
local figureHolder: Frame -- 사람 그림(복제 또는 블록)을 넣는 곳
local lineLayer: Frame
local powerLabel: TextLabel
local statsLabel: TextLabel
local slotViews: { [string]: SlotView } = {}
local anchors: { [string]: Vector2 } = table.clone(FALLBACK_ANCHORS)
local showDetail: (itemId: string) -> () = function(_itemId: string) end

-- 칸 가운데 (무대 비율)
local function slotCenter(place: SlotPlace): Vector2
	return Vector2.new(if place.Side < 0 then LEFT_X else RIGHT_X, ROW_Y[place.Row])
end

-- 무대 비율 위치에 둥근 네모 하나 (블록 사람 몸 부품)
local function bodyBlock(parent: Instance, center: Vector2, size: Vector2, color: Color3, radius: number): Frame
	local block = Instance.new("Frame")
	block.AnchorPoint = Vector2.new(0.5, 0.5)
	block.Position = UDim2.fromScale(center.X, center.Y)
	block.Size = UDim2.fromScale(size.X, size.Y)
	block.BackgroundColor3 = color
	block.BorderSizePixel = 0
	block.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(radius, 0)
	corner.Parent = block
	local stroke = Instance.new("UIStroke")
	stroke.Color = color:Lerp(Color3.new(0, 0, 0), 0.45)
	stroke.Thickness = 1.5
	stroke.Parent = block
	return block
end

-- 블록 사람 그림 (복제가 안 될 때)
local function drawBlockFigure()
	local holder = Instance.new("Frame")
	holder.Name = "BlockFigure"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = figureHolder
	-- 다리 → 팔 → 몸 → 머리 순서로 (나중 것이 위에)
	bodyBlock(holder, Vector2.new(0.4375, 0.68), Vector2.new(0.12, 0.33), PANTS, 0.15)
	bodyBlock(holder, Vector2.new(0.5625, 0.68), Vector2.new(0.12, 0.33), PANTS, 0.15)
	bodyBlock(holder, Vector2.new(0.315, 0.375), Vector2.new(0.11, 0.28), SKIN, 0.2)
	bodyBlock(holder, Vector2.new(0.685, 0.375), Vector2.new(0.11, 0.28), SKIN, 0.2)
	bodyBlock(holder, Vector2.new(0.5, 0.375), Vector2.new(0.25, 0.28), SHIRT, 0.1)
	local head = bodyBlock(holder, Vector2.new(0.5, 0.155), Vector2.new(0.17, 0.13), SKIN, 0.3)
	-- 얼굴: 눈 두 개 + 웃는 입
	for _, x in { 0.32, 0.68 } do
		local eye = Instance.new("Frame")
		eye.AnchorPoint = Vector2.new(0.5, 0.5)
		eye.Position = UDim2.fromScale(x, 0.4)
		eye.Size = UDim2.fromScale(0.12, 0.16)
		eye.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
		eye.BorderSizePixel = 0
		eye.Parent = head
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = eye
	end
	local mouth = Instance.new("Frame")
	mouth.AnchorPoint = Vector2.new(0.5, 0.5)
	mouth.Position = UDim2.fromScale(0.5, 0.7)
	mouth.Size = UDim2.fromScale(0.42, 0.1)
	mouth.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	mouth.BorderSizePixel = 0
	mouth.Parent = head
	local mouthCorner = Instance.new("UICorner")
	mouthCorner.CornerRadius = UDim.new(1, 0)
	mouthCorner.Parent = mouth
end

-- 복제본을 관절 기본 자세(차렷)로 다시 세운다: 루트에서 시작해 관절(C0·C1)·용접을 따라 부품 위치를 정한다
-- 애니메이션(Transform)은 무시되므로 팔다리가 곧게 내려온다. 이어지지 않은 부품은 지운다
local function poseNeutral(clone: Model, root: BasePart)
	local original: { [BasePart]: CFrame } = {}
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BasePart") then
			original[descendant] = descendant.CFrame
		end
	end
	type Link = { Part: BasePart, Offset: CFrame }
	local links: { [BasePart]: { Link } } = {}
	local function link(a: BasePart, b: BasePart, offset: CFrame) -- b = a * offset
		links[a] = links[a] or {}
		table.insert(links[a], { Part = b, Offset = offset })
		links[b] = links[b] or {}
		table.insert(links[b], { Part = a, Offset = offset:Inverse() })
	end
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("JointInstance") then
			local p0, p1 = descendant.Part0, descendant.Part1
			if p0 and p1 and original[p0] and original[p1] then
				link(p0, p1, descendant.C0 * descendant.C1:Inverse())
			end
		elseif descendant:IsA("WeldConstraint") then
			local p0, p1 = descendant.Part0, descendant.Part1
			if p0 and p1 and original[p0] and original[p1] then
				link(p0, p1, original[p0]:Inverse() * original[p1])
			end
		end
	end
	local placed: { [BasePart]: CFrame } = { [root] = CFrame.new() } -- 루트는 원점, 앞(-Z)을 본다
	local queue: { BasePart } = { root }
	local index = 1
	while index <= #queue do
		local part = queue[index]
		index += 1
		for _, item in links[part] or {} do
			if not placed[item.Part] then
				placed[item.Part] = placed[part] * item.Offset
				table.insert(queue, item.Part)
			end
		end
	end
	for part in original do
		local cframe = placed[part]
		if cframe then
			part.Anchored = true
			part.CFrame = cframe
		else
			part:Destroy()
		end
	end
end

-- 내 캐릭터 복제본을 만든다 (스크립트·도구·소리 등은 지움). 안 되면 nil
local function cloneCharacter(): (Model?, BasePart?)
	local character = localPlayer.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return nil, nil
	end
	-- 캐릭터는 Archivable이 false라 그냥은 복제가 안 된다 → 잠깐 켠다
	local wasArchivable = character.Archivable
	character.Archivable = true
	local ok, result = pcall(function()
		return character:Clone()
	end)
	character.Archivable = wasArchivable
	if not ok or typeof(result) ~= "Instance" or not result:IsA("Model") then
		return nil, nil
	end
	local clone = result :: Model
	for _, descendant in clone:GetDescendants() do
		if
			descendant:IsA("LuaSourceContainer")
			or descendant:IsA("Tool")
			or descendant:IsA("ForceField")
			or descendant:IsA("Sound")
			or descendant:IsA("BillboardGui")
			or descendant:IsA("ParticleEmitter")
			or descendant:IsA("Trail")
			or descendant:IsA("Beam")
			or descendant:IsA("Light")
			or descendant:IsA("ProximityPrompt")
		then
			descendant:Destroy()
		end
	end
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	local root = clone:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		clone:Destroy()
		return nil, nil
	end
	root.Transparency = 1
	poseNeutral(clone, root)
	return clone, root
end

-- 복제 캐릭터 그림: 정면 카메라를 몸 크기에 맞추고, 몸 위치(anchors)를 화면 위치로 계산한다
local function drawCharacterFigure(): boolean
	local clone = cloneCharacter()
	if not clone then
		return false
	end
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "CharacterFigure"
	viewport.BackgroundTransparency = 1
	viewport.Position = UDim2.fromScale(FIG_X, FIG_Y)
	viewport.Size = UDim2.fromScale(FIG_W, FIG_H)
	viewport.Ambient = Color3.fromRGB(190, 190, 190)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-0.5, -1, 1) -- 앞(카메라 쪽)에서 비춘다
	viewport.Parent = figureHolder

	local boxCFrame, boxSize = clone:GetBoundingBox()
	local center = boxCFrame.Position
	local camera = Instance.new("Camera")
	camera.FieldOfView = Config.EquipFigure.FieldOfView
	local tanV = math.tan(math.rad(camera.FieldOfView / 2))
	local halfHeight = boxSize.Y / 2 * 1.04
	local halfWidth = math.max(boxSize.X, boxSize.Z) / 2 * 1.04
	local distance = math.max(halfHeight / tanV, halfWidth / (tanV * FIG_ASPECT)) + boxSize.Z / 2
	-- 캐릭터는 -Z를 본다 → 카메라는 -Z 쪽에서 +Z를 본다 (캐릭터 오른손이 화면 왼쪽)
	local cameraCFrame = CFrame.lookAt(center + Vector3.new(0, 0, -distance), center)
	camera.CFrame = cameraCFrame
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	clone.Parent = viewport

	-- 몸 위치를 무대 비율 좌표로 (원근 투영)
	for anchorName, candidates in CHARACTER_ANCHORS do
		for _, candidate in candidates do
			local part = clone:FindFirstChild(candidate.Name, true)
			if part and part:IsA("BasePart") then
				local world = part.CFrame:PointToWorldSpace(part.Size * candidate.Offset)
				local relative = cameraCFrame:PointToObjectSpace(world)
				local depth = -relative.Z
				if depth > 0.01 then
					local u = 0.5 + relative.X / (depth * tanV * FIG_ASPECT) / 2
					local v = 0.5 - relative.Y / (depth * tanV) / 2
					anchors[anchorName] = Vector2.new(FIG_X + u * FIG_W, FIG_Y + v * FIG_H)
				end
				break
			end
		end
	end
	return true
end

-- 칸에서 몸 위치까지 선을 긋는다 (무대 픽셀 크기가 바뀔 때마다)
local function drawLines()
	for _, child in lineLayer:GetChildren() do
		child:Destroy()
	end
	local size = stage.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	for _, place in SLOT_PLACES do
		local center = slotCenter(place)
		local fromScale = Vector2.new(center.X - place.Side * SLOT_W / 2, center.Y) -- 몸 쪽 칸 가장자리
		local toScale = anchors[place.Anchor] or FALLBACK_ANCHORS[place.Anchor]
		local from = fromScale * size
		local to = toScale * size
		local delta = to - from
		local line = Instance.new("Frame")
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.Position = UDim2.fromScale((fromScale.X + toScale.X) / 2, (fromScale.Y + toScale.Y) / 2)
		line.Size = UDim2.fromOffset(delta.Magnitude, 2)
		line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
		line.BackgroundColor3 = UiKit.Colors.Gold
		line.BackgroundTransparency = 0.35
		line.BorderSizePixel = 0
		line.Parent = lineLayer
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(toScale.X, toScale.Y)
		dot.Size = UDim2.fromOffset(7, 7)
		dot.BackgroundColor3 = UiKit.Colors.Gold
		dot.BorderSizePixel = 0
		dot.Parent = lineLayer
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = dot
	end
end

-- 사람 그림을 다시 만든다 (창을 열 때·장비가 바뀔 때). 캐릭터 복제가 안 되면 블록 사람
function EquipmentPanel.rebuildFigure()
	if not figureHolder then
		return
	end
	for _, child in figureHolder:GetChildren() do
		child:Destroy()
	end
	anchors = table.clone(FALLBACK_ANCHORS)
	local ok = false
	if Config.EquipFigure.UseCharacter then
		local success, result = pcall(drawCharacterFigure)
		ok = success and result == true
		if not ok then
			for _, child in figureHolder:GetChildren() do
				child:Destroy()
			end
			anchors = table.clone(FALLBACK_ANCHORS)
		end
	end
	if not ok then
		drawBlockFigure()
	end
	drawLines()
end

-- 지금 이 칸에 끼운 아이템 Id (없으면 nil)
local function equippedItem(slotId: string): string?
	local itemId = localPlayer:GetAttribute(`Equip_{slotId}`)
	if typeof(itemId) == "string" and itemId ~= "" and ItemDefs.Items[itemId] then
		return itemId
	end
	return nil
end

-- 칸 아이콘·전투력·능력치를 다시 그린다 (속성 Equip_<칸>·Stat*·CombatPower·Arrows)
function EquipmentPanel.refresh()
	if not panel then
		return
	end
	for slotId, view in slotViews do
		for _, child in view.Inner:GetChildren() do
			child:Destroy()
		end
		local itemId = equippedItem(slotId)
		view.Label.Visible = itemId == nil
		view.Stroke.Color = if itemId then UiKit.Colors.Gold else UiKit.Colors.Border
		view.Badge.Visible = false
		if itemId then
			ItemIcon.create(view.Inner, itemId)
			if slotId == "Shield" then
				-- 화살통: 남은 화살 수 (서버가 센 속성 Arrows)
				local arrows = localPlayer:GetAttribute("Arrows")
				view.Badge.Text = `🏹{if typeof(arrows) == "number" then arrows else 0}`
				view.Badge.Visible = true
			end
		end
	end
	local function stat(name: string): number
		local value = localPlayer:GetAttribute(name)
		return if typeof(value) == "number" then value else 0
	end
	powerLabel.Text = `⚔ 전투력 {stat("CombatPower")}`
	statsLabel.Text = `공격 {stat("StatAtk")}  방어 {stat("StatDef")}\n체력 +{stat("StatHp")}  치명타 +{stat("StatCrit")}%`
end

-- 칸 네모 하나
local function buildSlot(slotId: string, title: string, place: SlotPlace)
	local center = slotCenter(place)
	local button = Instance.new("TextButton")
	button.Name = slotId
	button.Text = ""
	button.AutoButtonColor = true
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(center.X, center.Y)
	button.Size = UDim2.fromScale(SLOT_W, SLOT_H)
	button.BackgroundColor3 = UiKit.Colors.PanelLight
	button.BorderSizePixel = 0
	button.ZIndex = 3
	button.Parent = stage
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = button
	UiKit.corner(button, 8)
	local stroke = Instance.new("UIStroke")
	stroke.Color = UiKit.Colors.Border
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	local inner = Instance.new("Frame")
	inner.BackgroundTransparency = 1
	inner.Size = UDim2.new(1, -6, 1, -6)
	inner.Position = UDim2.fromOffset(3, 3)
	inner.Parent = button
	-- 빈 칸이면 흐린 칸 이름
	local label = UiKit.label(button, title, UDim2.fromScale(1, 1), nil, UiKit.Colors.SubText, 12)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextTransparency = 0.35
	label.TextScaled = true
	local labelLimit = Instance.new("UITextSizeConstraint")
	labelLimit.MaxTextSize = 13
	labelLimit.Parent = label
	local labelPadding = Instance.new("UIPadding")
	labelPadding.PaddingLeft = UDim.new(0.1, 0)
	labelPadding.PaddingRight = UDim.new(0.1, 0)
	labelPadding.Parent = label
	-- 화살 수 (방패 칸)
	local badge = UiKit.label(button, "", UDim2.new(1, 0, 0.32, 0), UDim2.fromScale(0, 0.7), Color3.new(1, 1, 1), 12)
	badge.TextXAlignment = Enum.TextXAlignment.Center
	badge.TextScaled = true
	badge.Visible = false
	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.Thickness = 1.5
	badgeStroke.Parent = badge
	slotViews[slotId] = { Button = button, Inner = inner, Label = label, Badge = badge, Stroke = stroke }

	-- 한 번: (더블클릭이 아니면) 상세 창 / 두 번: 빼기
	local lastClick = 0
	local token = 0
	button.Activated:Connect(function()
		local now = os.clock()
		token += 1
		if now - lastClick <= DOUBLE_CLICK then
			lastClick = 0
			if slotId ~= "Weapon" and equippedItem(slotId) then
				Remotes.get(Remotes.Names.UnequipSlot):FireServer(slotId)
			end
			return
		end
		lastClick = now
		local myToken = token
		task.delay(DOUBLE_CLICK, function()
			local itemId = equippedItem(slotId)
			if myToken == token and panel.Visible and itemId then
				showDetail(itemId)
			end
		end)
	end)
end

-- 장비 창을 만든다. onShowDetail(itemId): 칸을 한 번 눌렀을 때 상세 창 열기
function EquipmentPanel.build(parent: Instance, onShowDetail: (itemId: string) -> ()): Frame
	showDetail = onShowDetail
	panel = UiKit.panel(parent, UDim2.fromOffset(Config.EquipFigure.PanelWidth, Config.EquipFigure.MinHeight), UDim2.fromOffset(0, 56))
	panel.Name = "EquipmentPanel"
	panel.ZIndex = 1
	panel.Visible = false
	UiKit.label(panel, "장비", UDim2.new(0, 60, 0, 26), UDim2.fromOffset(12, 6), UiKit.Colors.Gold, 18)
	local hint = UiKit.label(panel, "두 번 누르면 빼기", UDim2.new(1, -80, 0, 26), UDim2.fromOffset(70, 6), UiKit.Colors.SubText, 11)
	hint.TextXAlignment = Enum.TextXAlignment.Right

	-- 사람 그림 + 칸이 들어가는 영역 (아래 전투력·능력치 자리 60px 남김)
	local area = Instance.new("Frame")
	area.Name = "FigureArea"
	area.BackgroundTransparency = 1
	area.Position = UDim2.fromOffset(6, 34)
	area.Size = UDim2.new(1, -12, 1, -34 - 60)
	area.Parent = panel
	stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.BackgroundTransparency = 1
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.5)
	stage.Size = UDim2.fromScale(1, 1)
	stage.Parent = area
	local stageAspect = Instance.new("UIAspectRatioConstraint")
	stageAspect.AspectRatio = STAGE_ASPECT
	stageAspect.AspectType = Enum.AspectType.FitWithinMaxSize
	stageAspect.Parent = stage

	-- 바닥 그림자 (사람이 서 있는 느낌)
	local shadow = Instance.new("Frame")
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.Position = UDim2.fromScale(0.5, 0.875)
	shadow.Size = UDim2.fromScale(0.42, 0.04)
	shadow.BackgroundColor3 = Color3.new(0, 0, 0)
	shadow.BackgroundTransparency = 0.6
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 1
	shadow.Parent = stage
	local shadowCorner = Instance.new("UICorner")
	shadowCorner.CornerRadius = UDim.new(1, 0)
	shadowCorner.Parent = shadow

	figureHolder = Instance.new("Frame")
	figureHolder.Name = "Figure"
	figureHolder.BackgroundTransparency = 1
	figureHolder.Size = UDim2.fromScale(1, 1)
	figureHolder.ZIndex = 1
	figureHolder.Parent = stage
	lineLayer = Instance.new("Frame")
	lineLayer.Name = "Lines"
	lineLayer.BackgroundTransparency = 1
	lineLayer.Size = UDim2.fromScale(1, 1)
	lineLayer.ZIndex = 2
	lineLayer.Parent = stage
	for _, slot in EquipmentDefs.Slots do
		local place = SLOT_PLACES[slot.Id]
		if place then
			buildSlot(slot.Id, slot.Title, place)
		end
	end
	stage:GetPropertyChangedSignal("AbsoluteSize"):Connect(drawLines)

	-- 그림 아래: 전투력 + 능력치
	powerLabel = UiKit.label(panel, "⚔ 전투력 0", UDim2.new(1, -16, 0, 22), UDim2.new(0, 8, 1, -60), Color3.fromRGB(255, 220, 120), 16)
	powerLabel.TextXAlignment = Enum.TextXAlignment.Center
	statsLabel = UiKit.label(panel, "", UDim2.new(1, -16, 0, 34), UDim2.new(0, 8, 1, -38), UiKit.Colors.SubText, 12)
	statsLabel.TextXAlignment = Enum.TextXAlignment.Center

	drawBlockFigure()
	drawLines()
	EquipmentPanel.refresh()
	return panel
end

return EquipmentPanel
