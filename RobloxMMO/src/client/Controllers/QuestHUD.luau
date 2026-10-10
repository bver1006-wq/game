--!strict
-- 시작 퀘스트 화면 (2026-10-10 사용자 요청). 왼쪽 위 가방 그림 아래 작은 창:
--   "📜 퀘스트 2/9" · 단계 이름 · 진행 막대 "3/5" · 짧은 설명 · 필요한 재료(조합식) · 가야 할 NPC 이름
-- 진행은 서버가 정한 플레이어 속성 QuestStep·QuestProgress를 보여 주기만 한다 (서버 QuestService)
-- 단계를 마치면 QuestComplete 리모트로 화면 가운데 축하 창 + 보상. 가야 할 NPC 머리 위에는 ❗가 통통 튄다
-- 창을 누르면 설명을 접고 펼친다 (휴대폰처럼 화면이 낮으면 처음부터 접힘)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local ItemDefs = require(ReplicatedStorage.Shared.ItemDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ShopDefs = require(ReplicatedStorage.Shared.ShopDefs)
local UiKit = require(script.Parent.UiKit)

local NPC_TAG = "ShopNPC"

local localPlayer = Players.LocalPlayer

local QuestHUD = {}

local gui: ScreenGui
local panel: Frame
local headerLabel: TextLabel
local titleLabel: TextLabel
local barFill: Frame
local countLabel: TextLabel
local hintLabel: TextLabel
local needLabel: TextLabel
local npcLabel: TextLabel
local collapsed = false
local marker: BillboardGui? = nil
local markerNpc: string? = nil
local finishedHideToken = 0

-- 아이템 이름 (없으면 Id)
local function itemName(itemId: string): string
	local def = ItemDefs.Items[itemId]
	return if def then def.DisplayName else itemId
end

-- 만들기 단계: 조합식을 "필요: 나무 검 2, 돌 4, 소나무 4, 20G"로 (Config.Recipes가 바뀌어도 그대로 맞음)
local function recipeText(itemId: string): string?
	local recipe = Config.Recipes[itemId]
	if not recipe then
		return nil
	end
	local parts = {}
	if recipe.From then
		table.insert(parts, `{itemName(recipe.From.Id)} {recipe.From.Count}`)
	end
	local ids = {}
	for id in recipe.Items do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		table.insert(parts, `{itemName(id)} {recipe.Items[id]}`)
	end
	if recipe.Gold > 0 then
		table.insert(parts, `{recipe.Gold}G`)
	end
	return "필요: " .. table.concat(parts, ", ")
end

-- NPC 모델 찾기 (태그 ShopNPC + 속성 ShopId)
local function findNpc(shopId: string): Model?
	for _, npc in CollectionService:GetTagged(NPC_TAG) do
		if npc:IsA("Model") and npc:GetAttribute("ShopId") == shopId then
			return npc
		end
	end
	return nil
end

-- 가야 할 NPC 머리 위 ❗ (없으면 지운다)
local function setMarker(shopId: string?)
	if markerNpc == shopId and (marker == nil or marker.Parent ~= nil) then
		return
	end
	if marker then
		marker:Destroy()
		marker = nil
	end
	markerNpc = shopId
	if not shopId then
		return
	end
	local npc = findNpc(shopId)
	if not npc then
		return
	end
	local root: Instance? = npc.PrimaryPart or npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChildWhichIsA("BasePart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "QuestMarker"
	billboard.Size = UDim2.fromOffset(46, 46)
	billboard.StudsOffset = Vector3.new(0, 6.5, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Adornee = root
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = Config.Quest.NpcMarker
	label.TextColor3 = UiKit.Colors.Gold
	label.Parent = billboard
	billboard.Parent = gui
	-- 통통 튀는 움직임
	TweenService:Create(
		billboard,
		TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ StudsOffset = Vector3.new(0, 7.5, 0) }
	):Play()
	marker = billboard
end

-- 설명 줄 보이기 (접힘이면 숨김)
local function applyCollapsed()
	hintLabel.Visible = not collapsed and hintLabel.Text ~= ""
	needLabel.Visible = not collapsed and needLabel.Text ~= ""
end

-- 속성을 읽어 창을 다시 그린다
local function refresh()
	local steps = Config.Quest.Steps
	local stepIndex = localPlayer:GetAttribute("QuestStep")
	if typeof(stepIndex) ~= "number" then
		panel.Visible = false
		setMarker(nil)
		return
	end
	if stepIndex > #steps then
		-- 다 끝남: 완료 문구를 잠깐 보여 주고 숨긴다
		headerLabel.Text = `📜 퀘스트 {#steps}/{#steps}`
		titleLabel.Text = "🎉 " .. Config.Quest.FinishMessage
		countLabel.Text = ""
		barFill.Size = UDim2.fromScale(1, 1)
		hintLabel.Text = ""
		needLabel.Text = ""
		npcLabel.Text = ""
		npcLabel.Visible = false
		applyCollapsed()
		setMarker(nil)
		finishedHideToken += 1
		local token = finishedHideToken
		task.delay(Config.Quest.FinishHideDelay, function()
			if token == finishedHideToken then
				panel.Visible = false
			end
		end)
		return
	end
	finishedHideToken += 1
	panel.Visible = true
	local step = steps[stepIndex]
	local progressValue = localPlayer:GetAttribute("QuestProgress")
	local progress = if typeof(progressValue) == "number" then progressValue else 0
	headerLabel.Text = `📜 퀘스트 {stepIndex}/{#steps}`
	titleLabel.Text = step.Title
	countLabel.Text = `{progress}/{step.Count}`
	barFill.Size = UDim2.fromScale(math.clamp(progress / math.max(step.Count, 1), 0, 1), 1)
	hintLabel.Text = step.Hint
	needLabel.Text = if step.Kind == "Craft" then recipeText(step.Targets[1]) or "" else ""
	local shop = if step.Npc then ShopDefs[step.Npc] else nil
	npcLabel.Text = if shop then `👉 {shop.NpcName}에게 가요` else ""
	npcLabel.Visible = shop ~= nil
	applyCollapsed()
	setMarker(step.Npc)
end

-- 화면 가운데 축하 창 (단계 완료)
local function celebrate(stepIndex: number, rewardText: string)
	local steps = Config.Quest.Steps
	local step = steps[stepIndex]
	if not step then
		return
	end
	local isLast = stepIndex >= #steps
	local popup = UiKit.panel(gui, UDim2.fromOffset(320, 0), UDim2.new(0.5, 0, 0.28, 0), Vector2.new(0.5, 0.5))
	popup.AutomaticSize = Enum.AutomaticSize.Y
	popup.BackgroundColor3 = UiKit.Colors.PanelLight
	popup.ZIndex = 5
	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = popup
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = popup

	local function line(text: string, color: Color3, size: number, order: number)
		local label = UiKit.label(popup, text, UDim2.new(1, 0, 0, 0), nil, color, size)
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.Font = Enum.Font.FredokaOne
		label.LayoutOrder = order
		label.ZIndex = 6
	end
	line("🎉 퀘스트 완료! 🎉", UiKit.Colors.Gold, 26, 1)
	line(step.Title, UiKit.Colors.Text, 20, 2)
	if rewardText ~= "" then
		line(`보상: {rewardText}`, UiKit.Colors.Good, 18, 3)
	end
	if isLast then
		line(Config.Quest.FinishMessage, UiKit.Colors.Gold, 18, 4)
	else
		line(`다음: {steps[stepIndex + 1].Title}`, UiKit.Colors.SubText, 16, 4)
	end

	-- 톡 튀어나왔다가 잠시 뒤 사라짐
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = popup
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local holdTime = if isLast then Config.Quest.CelebrateTime * 1.6 else Config.Quest.CelebrateTime
	task.delay(holdTime, function()
		local tween = TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 })
		tween:Play()
		tween.Completed:Wait()
		popup:Destroy()
	end)
end

-- 왼쪽 위 퀘스트 창 만들기
local function buildPanel()
	local width = Config.Quest.HudWidth
	panel = UiKit.panel(gui, UDim2.fromOffset(width, 0), Config.Quest.HudPosition)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundTransparency = 0.12
	panel.Visible = false
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 3)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = panel

	local function autoLabel(color: Color3, size: number, order: number): TextLabel
		local label = UiKit.label(panel, "", UDim2.new(1, 0, 0, 0), nil, color, size)
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.LayoutOrder = order
		return label
	end
	headerLabel = autoLabel(UiKit.Colors.SubText, 12, 1)
	titleLabel = autoLabel(UiKit.Colors.Gold, 17, 2)
	titleLabel.Font = Enum.Font.FredokaOne

	-- 진행 막대 + "3/5"
	local barRow = Instance.new("Frame")
	barRow.BackgroundTransparency = 1
	barRow.Size = UDim2.new(1, 0, 0, 16)
	barRow.LayoutOrder = 3
	barRow.Parent = panel
	local barBack = Instance.new("Frame")
	barBack.BackgroundColor3 = Color3.fromRGB(20, 16, 14)
	barBack.BorderSizePixel = 0
	barBack.Size = UDim2.new(1, -52, 0, 10)
	barBack.Position = UDim2.fromOffset(0, 3)
	barBack.Parent = barRow
	UiKit.corner(barBack, 5)
	barFill = Instance.new("Frame")
	barFill.BackgroundColor3 = UiKit.Colors.Good
	barFill.BorderSizePixel = 0
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.Parent = barBack
	UiKit.corner(barFill, 5)
	countLabel = UiKit.label(barRow, "", UDim2.new(0, 48, 1, 0), UDim2.new(1, -48, 0, 0), UiKit.Colors.Text, 15)
	countLabel.TextXAlignment = Enum.TextXAlignment.Right

	hintLabel = autoLabel(UiKit.Colors.Text, 13, 4)
	hintLabel.Font = Enum.Font.Gotham
	needLabel = autoLabel(Color3.fromRGB(150, 210, 255), 13, 5)
	npcLabel = autoLabel(UiKit.Colors.Good, 14, 6)

	-- 누르면 접기·펼치기 (창 안 버튼은 목록 정렬에 끼므로 창 자체의 입력을 쓴다)
	panel.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			collapsed = not collapsed
			applyCollapsed()
		end
	end)
end

-- 클라이언트 시작 시 한 번 호출
function QuestHUD.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "QuestGui"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 4 -- 가방 창(5)보다 아래
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	buildPanel()
	local camera = Workspace.CurrentCamera
	collapsed = camera ~= nil and camera.ViewportSize.Y > 0 and camera.ViewportSize.Y < Config.Quest.CompactScreenHeight

	localPlayer:GetAttributeChangedSignal("QuestStep"):Connect(refresh)
	localPlayer:GetAttributeChangedSignal("QuestProgress"):Connect(refresh)
	CollectionService:GetInstanceAddedSignal(NPC_TAG):Connect(function()
		markerNpc = nil -- NPC가 늦게 생기면 표시를 다시 단다
		refresh()
	end)
	Remotes.get(Remotes.Names.QuestComplete).OnClientEvent:Connect(function(stepIndex: unknown, rewardText: unknown)
		if typeof(stepIndex) == "number" then
			celebrate(stepIndex, if typeof(rewardText) == "string" then rewardText else "")
		end
	end)
	refresh()
end

return QuestHUD
