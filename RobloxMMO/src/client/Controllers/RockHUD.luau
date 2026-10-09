--!strict
-- 바위 위 BillboardGui: 체력바, 판정 말풍선(Perfect!/Nice!), 획득량 숫자.
-- 전부 로컬 연출이고, 값은 서버가 바위 속성(Hp/MaxHp)과 RemoteEvent로 알려준 것만 쓴다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local OreDefs = require(ReplicatedStorage.Shared.OreDefs)
local TargetController = require(script.Parent.TargetController)

-- 판정별 말풍선 색
local JUDGMENT_STYLE = {
	Perfect = { Text = "Perfect!", Fill = Color3.fromRGB(255, 205, 40), Outline = Color3.fromRGB(120, 60, 0) },
	Nice = { Text = "Nice!", Fill = Color3.fromRGB(80, 210, 255), Outline = Color3.fromRGB(10, 70, 130) },
}

local RockHUD = {}

local guiFolder: Folder
local hpBillboard: BillboardGui
local hpFill: Frame
local hpLabel: TextLabel
local currentRock: Model? = nil
local shownHp = -1

-- 바위 꼭대기 높이 (바위 중심 기준)
local function rockTopOffset(rock: Model): number
	return rock:GetExtentsSize().Y / 2
end

-- 위치에 붙일 보이지 않는 Attachment (바위가 없어진 뒤에도 문구를 띄우기 위해)
local function makeAnchor(position: Vector3, lifetime: number): Attachment
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = Workspace.Terrain
	task.delay(lifetime, function()
		attachment:Destroy()
	end)
	return attachment
end

-- 체력바 BillboardGui를 만든다 (하나를 만들어 두고 대상 바위만 바꿔 쓴다)
local function createHpBar()
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "RockHpBar"
	billboard.Size = UDim2.new(3, 0, 0.55, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Enabled = false

	local back = Instance.new("Frame")
	back.Size = UDim2.new(1, 0, 0.5, 0)
	back.Position = UDim2.new(0, 0, 0.5, 0)
	back.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	back.BackgroundTransparency = 0.2
	back.BorderSizePixel = 0
	back.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = back
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Parent = back

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(110, 220, 90)
	fill.BorderSizePixel = 0
	fill.Parent = back
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0.5, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = billboard
	local labelStroke = Instance.new("UIStroke")
	labelStroke.Thickness = 1.5
	labelStroke.Parent = label

	billboard.Parent = guiFolder
	hpBillboard = billboard
	hpFill = fill
	hpLabel = label
end

-- 매 프레임: 가장 가까운 바위로 체력바를 옮기고 HP를 반영한다
local function updateHpBar()
	local rock = TargetController.getNearestRock(Config.HitFeel.HpBarRange)
	if rock ~= currentRock then
		currentRock = rock
		shownHp = -1
		if rock then
			hpBillboard.Adornee = rock.PrimaryPart or rock:FindFirstChildWhichIsA("BasePart", true)
			hpBillboard.StudsOffsetWorldSpace = Vector3.new(0, rockTopOffset(rock) + 0.9, 0)
			local oreType = rock:GetAttribute("OreType")
			local def = if typeof(oreType) == "string" then OreDefs[oreType] else nil
			hpLabel.Text = if def then def.DisplayName else ""
		end
	end
	hpBillboard.Enabled = rock ~= nil
	if not rock then
		return
	end

	local hp = rock:GetAttribute("Hp")
	local maxHp = rock:GetAttribute("MaxHp")
	if typeof(hp) ~= "number" or typeof(maxHp) ~= "number" or maxHp <= 0 then
		return
	end
	if hp ~= shownHp then
		local ratio = math.clamp(hp / maxHp, 0, 1)
		local tweenTime = if shownHp < 0 then 0 else 0.12
		shownHp = hp
		TweenService:Create(hpFill, TweenInfo.new(tweenTime, Enum.EasingStyle.Quad), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
		-- 체력이 줄수록 초록 → 노랑 → 빨강
		hpFill.BackgroundColor3 = Color3.fromRGB(230, 70, 60):Lerp(Color3.fromRGB(110, 220, 90), ratio)
	end
end

-- 뾰족한 별 모양: 회전한 정사각형 3개를 겹치면 12각 별이 된다
local function makeStar(parent: GuiObject, sizeScale: number, color: Color3, zIndex: number): { Frame }
	local squares = {}
	for i = 0, 2 do
		local square = Instance.new("Frame")
		square.AnchorPoint = Vector2.new(0.5, 0.5)
		square.Position = UDim2.fromScale(0.5, 0.5)
		square.Size = UDim2.fromScale(sizeScale, sizeScale)
		square.Rotation = i * 30
		square.BackgroundColor3 = color
		square.BorderSizePixel = 0
		square.ZIndex = zIndex
		square.Parent = parent
		table.insert(squares, square)
	end
	return squares
end

-- 판정 말풍선을 바위 위에 띄운다 (Perfect!/Nice!)
function RockHUD.showJudgment(rock: Model, judgment: string)
	local style = JUDGMENT_STYLE[judgment]
	if not style or not rock.Parent then
		return
	end
	local duration = Config.HitFeel.JudgmentPopupDuration
	local top = rock:GetPivot().Position + Vector3.new(0, rockTopOffset(rock), 0)
	local sideways = (math.random() - 0.5) * 1.2
	local anchor = makeAnchor(top, duration + 0.1)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(3.4, 0, 3.4, 0)
	billboard.StudsOffsetWorldSpace = Vector3.new(sideways, 1.2, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Adornee = anchor

	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = billboard
	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = root

	-- 테두리 별(조금 크게) 위에 채움 별을 겹친다
	local spikes = makeStar(root, 0.74, style.Outline, 1)
	for _, square in makeStar(root, 0.66, style.Fill, 2) do
		table.insert(spikes, square)
	end

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(1.1, 0.36)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = style.Text
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.ZIndex = 3
	label.Rotation = -8
	label.Parent = root
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = style.Outline
	stroke.Parent = label

	billboard.Parent = guiFolder

	-- 튀어나옴 → 살짝 줄어듦 → 위로 떠오르며 사라짐
	TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.2 }):Play()
	task.delay(0.1, function()
		TweenService:Create(scale, TweenInfo.new(0.08), { Scale = 1 }):Play()
	end)
	TweenService:Create(billboard, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = Vector3.new(sideways, 2.2, 0),
	}):Play()
	for _, square in spikes do
		TweenService:Create(square, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Rotation = square.Rotation + 20 }):Play()
	end
	local fadeTime = duration * 0.35
	task.delay(duration - fadeTime, function()
		local fade = TweenInfo.new(fadeTime)
		for _, square in spikes do
			TweenService:Create(square, fade, { BackgroundTransparency = 1 }):Play()
		end
		TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
	end)
	task.delay(duration, function()
		billboard:Destroy()
	end)
end

-- 획득량 숫자를 위치 위에 띄운다 ("+5 돌", 피버면 보너스도 함께)
function RockHUD.showReward(position: Vector3, amount: number, oreName: string, feverBonus: number)
	local duration = 1.6
	local anchor = makeAnchor(position, duration + 0.1)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(5, 0, 2, 0)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Adornee = anchor

	local labels: { TextLabel } = {}
	local function addLine(text: string, color: Color3, y: number, height: number)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, height)
		label.Position = UDim2.fromScale(0, y)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.Text = text
		label.TextScaled = true
		label.TextColor3 = color
		label.Parent = billboard
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2.5
		stroke.Parent = label
		table.insert(labels, label)
	end
	if feverBonus > 0 then
		addLine(`FEVER +{feverBonus}`, Color3.fromRGB(255, 120, 40), 0, 0.4)
	end
	addLine(`+{amount} {oreName}`, Color3.fromRGB(255, 245, 160), 0.4, 0.6)

	billboard.Parent = guiFolder

	TweenService:Create(billboard, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = Vector3.new(0, 4, 0),
	}):Play()
	task.delay(duration * 0.6, function()
		for _, label in labels do
			TweenService:Create(label, TweenInfo.new(duration * 0.4), { TextTransparency = 1 }):Play()
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				TweenService:Create(stroke, TweenInfo.new(duration * 0.4), { Transparency = 1 }):Play()
			end
		end
	end)
	task.delay(duration, function()
		billboard:Destroy()
	end)
end

-- 클라이언트 시작 시 한 번 호출
function RockHUD.init()
	-- 리스폰 때 PlayerGui가 초기화되지 않게 Workspace 아래 로컬 폴더에 둔다 (BillboardGui는 Adornee로 위치를 정한다)
	local folder = Instance.new("Folder")
	folder.Name = "ClientRockHUD"
	folder.Parent = Workspace
	guiFolder = folder

	createHpBar()
	RunService.Heartbeat:Connect(updateHpBar)
end

return RockHUD
