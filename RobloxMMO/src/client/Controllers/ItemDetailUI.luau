--!strict
-- 아이템 상세 창 (2026-10-09 사용자 요청): 가방·상점에서 아이템을 한 번 누르면 뜬다.
-- 왼쪽: 아이템 3D 모델(ReplicatedStorage/ItemIcons, ItemIcon과 같은 모델)을 크게, 천천히 360° 돌린다. 카메라는 모델 크기에 맞춘다
-- 오른쪽: 이름·단계 별·분류, 자세한 능력치(Config에서 읽음), 만드는 법, 쓰이는 곳, 판매가
-- X 버튼이나 창 바깥을 누르면 닫힌다. 처음 열 때 화면을 만든다 (Main.client에서 init을 부르지 않아도 된다)
-- 화면 표시용이며 능력치 계산은 서버(EquipmentService.itemStats 등)와 같은 식을 Config로 다시 계산한다

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local EquipmentDefs = require(ReplicatedStorage.Shared.EquipmentDefs)
local ItemDefs = require(ReplicatedStorage.Shared.ItemDefs)
local MobDefs = require(ReplicatedStorage.Shared.MobDefs)
local OreDefs = require(ReplicatedStorage.Shared.OreDefs)
local PickaxeDefs = require(ReplicatedStorage.Shared.PickaxeDefs)
local InventoryState = require(script.Parent.InventoryState)
local ItemIcon = require(script.Parent.ItemIcon)
local RecipeView = require(script.Parent.RecipeView)
local UiKit = require(script.Parent.UiKit)

local localPlayer = Players.LocalPlayer

-- 단계별 이름 색 (1 나무·가죽 / 2 구리 / 3 철 / 4 다이아몬드)
local TIER_COLORS = {
	Color3.fromRGB(215, 175, 130),
	Color3.fromRGB(240, 150, 90),
	Color3.fromRGB(215, 220, 235),
	Color3.fromRGB(120, 230, 255),
}
local KIND_NAMES: { [string]: string } = { Pickaxe = "곡괭이", Axe = "도끼", Sword = "칼", Bow = "활", Club = "방망이" }
local BLACKSMITH_KINDS: { [string]: boolean } = { Pickaxe = true, Axe = true }

local ItemDetailUI = {}

-- 아래 함수들이 재료·결과 아이콘을 누르면 다른 아이템 상세로 넘어간다 (open은 맨 아래에서 정한다)
local openDetail: (itemId: string) -> ()

local gui: ScreenGui? = nil
local panel: Frame
local nameLabel: TextLabel
local starsLabel: TextLabel
local kindLabel: TextLabel
local viewport: ViewportFrame
local info: ScrollingFrame
local camera: Camera
local spinConnection: RBXScriptConnection? = nil
local currentItem: string? = nil
local model: Model? = nil
local modelCenter = Vector3.zero -- 모델 기준점에서 본 상자 가운데
local modelRadius = 1
local angle = 0

-- 숫자를 보기 좋게 (소수 첫째 자리까지)
local function num(value: number): string
	local rounded = math.round(value * 10) / 10
	if rounded == math.floor(rounded) then
		return tostring(math.floor(rounded))
	end
	return tostring(rounded)
end

-- 장비 하나의 능력치 (서버 EquipmentService.itemStats와 같은 식)
local function equipmentStats(itemId: string): { Atk: number, Def: number, Hp: number, Crit: number }
	local stats = { Atk = 0, Def = 0, Hp = 0, Crit = 0 }
	local def = EquipmentDefs.Items[itemId]
	if def then
		local base = (Config.Equipment.Base :: any)[def.Slot] or {}
		local multiplier = Config.Equipment.TierMultiplier[def.Tier] or 1
		stats.Atk = math.round((base.Atk or 0) * multiplier * 10) / 10
		stats.Def = math.round((base.Def or 0) * multiplier * 10) / 10
		stats.Hp = math.round((base.Hp or 0) * multiplier * 10) / 10
		stats.Crit = math.round((base.Crit or 0) * multiplier * 10) / 10
	end
	return stats
end

-- 전투력 (서버와 같은 가중치)
local function combatPower(stats: { Atk: number, Def: number, Hp: number, Crit: number }): number
	local w = Config.Equipment.PowerWeights
	return math.round(stats.Atk * w.Atk + stats.Def * w.Def + stats.Hp * w.Hp + stats.Crit * w.Crit)
end

-- 한국어 조사: 앞 글자에 받침이 있으면 withFinal, 없으면 withoutFinal ("슬라임을" / "좀비를")
local function josa(word: string, withFinal: string, withoutFinal: string): string
	local last = 0
	for _, code in utf8.codes(word) do
		last = code
	end
	local hasFinal = last >= 0xAC00 and last <= 0xD7A3 and (last - 0xAC00) % 28 ~= 0
	return word .. (if hasFinal then withFinal else withoutFinal)
end

-- 이름 목록을 "돌, 석탄, 구리"로
local function joinNames(names: { string }): string
	return if #names > 0 then table.concat(names, ", ") else "없음"
end

-- 분류 글자와 단계 (단계가 없으면 nil)
local function describeKind(itemId: string): (string, number?)
	local tool = PickaxeDefs[itemId]
	if tool then
		local group = if BLACKSMITH_KINDS[tool.Kind] then "도구" else "무기"
		return `{KIND_NAMES[tool.Kind] or "도구"} · {group}`, tool.Tier
	end
	local equipment = EquipmentDefs.Items[itemId]
	if equipment then
		if equipment.Slot == "Shield" then
			return "화살통 · 방패 칸", nil
		end
		for _, slot in EquipmentDefs.Slots do
			if slot.Id == equipment.Slot then
				return `{slot.Title} · 장비`, equipment.Tier
			end
		end
		return "장비", equipment.Tier
	end
	if (Config.Foods :: any)[itemId] then
		return "음식", nil
	end
	if itemId == "ReturnScroll" then
		return "주문서", nil
	end
	local ore = OreDefs[itemId]
	if ore then
		return if ore.Kind == "Tree" then "통나무 · 재료" else "광석 · 재료", nil
	end
	if (Config.Smelting.Recipes :: any)[itemId] then
		return "괴 · 재료", nil
	end
	for _, mob in MobDefs do
		if mob.LootId == itemId then
			return "몹 전리품 · 재료", nil
		end
	end
	return "아이템", nil
end

-- 정보 영역을 비운다
local function clearInfo()
	for _, child in info:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local lineOrder = 0

-- 정보 영역에 섹션 제목 한 줄
local function addHeader(text: string)
	lineOrder += 1
	local label = UiKit.label(info, text, UDim2.new(1, -8, 0, 24), nil, UiKit.Colors.Gold, 16)
	label.LayoutOrder = lineOrder
end

-- 정보 영역에 "이름   값" 한 줄
local function addStat(name: string, value: string, color: Color3?)
	lineOrder += 1
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -8, 0, 22)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.LayoutOrder = lineOrder
	row.Parent = info
	UiKit.label(row, name, UDim2.new(0.45, 0, 0, 22), nil, UiKit.Colors.SubText, 14)
	local valueLabel = UiKit.label(row, value, UDim2.new(0.55, 0, 0, 22), UDim2.fromScale(0.45, 0), color or UiKit.Colors.Text, 15)
	valueLabel.AutomaticSize = Enum.AutomaticSize.Y
end

-- 정보 영역에 설명 글 한 줄 (여러 줄로 감김)
local function addText(text: string, color: Color3?)
	lineOrder += 1
	local label = UiKit.label(info, text, UDim2.new(1, -8, 0, 20), nil, color or UiKit.Colors.Text, 14)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.LayoutOrder = lineOrder
end

-- 정보 영역에 조합식 그림 줄
local function addRecipe(recipe: RecipeView.RecipeLike)
	lineOrder += 1
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, -8, 0, 58)
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.LayoutOrder = lineOrder
	holder.Parent = info
	RecipeView.chips(holder, recipe, UDim2.new(), UDim.new(1, 0), function(id)
		openDetail(id)
	end)
end

-- 정보 영역에 아이템 아이콘 목록 (누르면 그 아이템 상세로)
local function addItemList(itemIds: { string })
	lineOrder += 1
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, -8, 0, 62)
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.LayoutOrder = lineOrder
	holder.Parent = info
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(62, 62)
	layout.CellPadding = UDim2.fromOffset(4, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder
	for order, id in itemIds do
		local cell = Instance.new("TextButton")
		cell.Text = ""
		cell.BackgroundColor3 = UiKit.Colors.Panel
		cell.BorderSizePixel = 0
		cell.LayoutOrder = order
		cell.Parent = holder
		UiKit.corner(cell, 6)
		local icon = Instance.new("Frame")
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.new(1, -16, 1, -22)
		icon.Position = UDim2.fromOffset(8, 2)
		icon.Parent = cell
		ItemIcon.create(icon, id)
		local label = UiKit.label(cell, ItemDefs.Items[id].DisplayName, UDim2.new(1, -2, 0, 18), UDim2.new(0, 1, 1, -19), UiKit.Colors.Text, 11)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextWrapped = false
		label.TextScaled = true
		local sizeLimit = Instance.new("UITextSizeConstraint")
		sizeLimit.MaxTextSize = 11
		sizeLimit.Parent = label
		cell.Activated:Connect(function()
			openDetail(id)
		end)
	end
end

-- 곡괭이·도끼 능력치
local function drawToolStats(tool: PickaxeDefs.PickaxeDef)
	local config = Config.Pickaxes[tool.Id]
	local power = if config then config.Power else 1
	addStat("힘", `x{num(power)}`, UiKit.Colors.Good)
	addStat("휘두르기 간격", `{num(Config.Mining.SwingInterval)}초`)
	addStat("공격력 (전투력)", num(power * Config.Equipment.ToolAtkPerPower))
	addStat("다 모은 강타", `x{num(Config.Charge.Multiplier)} (마나 {Config.Charge.ManaCost})`)
	if config and (config :: any).LightningChance then
		addStat("번개 확률", `{num((config :: any).LightningChance * 100)}%`, Color3.fromRGB(150, 220, 255))
	end
	-- 캘 수 있는 것: 노드 종류가 맞고 필요 단계 이하
	local nodeKind = if tool.Kind == "Axe" then "Tree" else "Rock"
	local can: { string } = {}
	local cannot: { string } = {}
	local ids: { string } = {}
	for id in OreDefs do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		return (table.find(ItemDefs.Order, a) or 0) < (table.find(ItemDefs.Order, b) or 0)
	end)
	for _, id in ids do
		local ore = OreDefs[id]
		if ore.Kind == nodeKind then
			table.insert(if ore.RequiredTier <= tool.Tier then can else cannot, ore.DisplayName)
		end
	end
	local verb = if tool.Kind == "Axe" then "벨 수 있어요" else "캘 수 있어요"
	addStat(verb, joinNames(can), UiKit.Colors.Good)
	if #cannot > 0 then
		addStat("아직 못 해요", joinNames(cannot), UiKit.Colors.Bad)
	end
end

-- 칼·활·방망이 능력치
local function drawWeaponStats(tool: PickaxeDefs.PickaxeDef)
	local config = Config.Weapons[tool.Id]
	if not config then
		return
	end
	addStat("공격력", num(config.Damage), UiKit.Colors.Good)
	addStat("공격 간격", `{num(config.Cooldown)}초`)
	addStat("사거리", `{num(config.Range)}칸`)
	local knockback = (config :: any).Knockback
	if knockback then
		addStat("밀쳐 내기", num(knockback))
	end
	addStat("치명타", `{num(Config.Combat.CritChance * 100)}% · x{num(Config.Combat.CritMultiplier)}`)
	if tool.Kind == "Bow" then
		addStat("다 모은 강타", `x{num(Config.Charge.BowOverMultiplier)} (마나 {Config.Charge.ManaCost})`)
		addText("화살통이 있어야 쏴요. 한 발에 화살 1개.", UiKit.Colors.SubText)
	else
		addStat("다 모은 강타", `x{num(Config.Charge.Multiplier)} (마나 {Config.Charge.ManaCost})`)
	end
	-- 잘 싸울 수 있는 몹: 몹 단계 이하 (Config.TierWall: 1단계 낮으면 약하게, 2단계 낮으면 흠집도 안 남)
	local strong: { string } = {}
	local weak: { string } = {}
	for _, mob in MobDefs do
		if mob.Tier <= tool.Tier then
			table.insert(strong, mob.DisplayName)
		elseif mob.Tier - tool.Tier < Config.TierWall.BlockGap then
			table.insert(weak, mob.DisplayName)
		end
	end
	addStat("잘 싸워요", joinNames(strong), UiKit.Colors.Good)
	if #weak > 0 then
		addStat("조금만 아파해요", joinNames(weak), Color3.fromRGB(240, 190, 90))
	end
end

-- 장비 능력치
local function drawEquipmentStats(itemId: string)
	local equipment = EquipmentDefs.Items[itemId]
	if equipment.Slot == "Shield" then
		local quiver = (Config.Quiver.Items :: any)[itemId]
		if quiver then
			addStat("화살", `{quiver.Arrows}개`, UiKit.Colors.Good)
		end
		addText("방패 칸에 끼우고 등에 메요. 다 쓰면 사라져요.", UiKit.Colors.SubText)
		return
	end
	local stats = equipmentStats(itemId)
	if stats.Atk > 0 then
		addStat("공격", `+{num(stats.Atk)}`, UiKit.Colors.Good)
	end
	if stats.Def > 0 then
		addStat("방어", `+{num(stats.Def)}`, UiKit.Colors.Good)
	end
	if stats.Hp > 0 then
		addStat("체력", `+{num(stats.Hp)}`, UiKit.Colors.Good)
	end
	if stats.Crit > 0 then
		addStat("치명타", `+{num(stats.Crit)}%`, UiKit.Colors.Good)
	end
	addStat("전투력", `+{combatPower(stats)}`, Color3.fromRGB(255, 220, 120))
end

-- 음식·주문서 정보
local function drawUsableStats(itemId: string)
	local food = (Config.Foods :: any)[itemId]
	if food then
		if food.Hp then
			addStat("체력 회복", `+{food.Hp}`, UiKit.Colors.Good)
		end
		if food.Mana then
			addStat("마나 회복", `+{food.Mana}`, Color3.fromRGB(130, 170, 255))
		end
		addStat("다시 먹기", `{Config.FoodCooldown}초 뒤`)
	elseif itemId == "ReturnScroll" then
		addStat("마을로 돌아가기", `{num(Config.ReturnScroll.CastTime)}초`)
		addText("쓰는 동안 움직이면 취소돼요.", UiKit.Colors.SubText)
	end
	addText("빠른 칸에 놓고 누르면 써요.", UiKit.Colors.SubText)
end

-- 어디서 만드는지 (조합식이 있는 도구·무기·장비)
local function whereCrafted(itemId: string): string
	local tool = PickaxeDefs[itemId]
	if tool and BLACKSMITH_KINDS[tool.Kind] then
		return "대장장이 브론"
	end
	return "사냥꾼 카엘"
end

-- 정보 영역 전체를 다시 그린다
local function drawInfo(itemId: string)
	clearInfo()
	lineOrder = 0
	local def = ItemDefs.Items[itemId]

	addHeader("능력치")
	local tool = PickaxeDefs[itemId]
	if tool then
		if BLACKSMITH_KINDS[tool.Kind] then
			drawToolStats(tool)
		else
			drawWeaponStats(tool)
		end
	elseif EquipmentDefs.Items[itemId] then
		drawEquipmentStats(itemId)
	elseif def.Usable then
		drawUsableStats(itemId)
	else
		addText("재료 아이템이에요.", UiKit.Colors.SubText)
	end
	addStat("가진 개수", `{InventoryState.count(itemId)}개`)
	local price = Config.SellPrices[itemId]
	if price then
		addStat("팔면", `개당 {price}G (상인)`, UiKit.Colors.Gold)
	end

	-- 만드는 법
	local recipe, where = RecipeView.recipeFor(itemId)
	if recipe then
		local craftWhere = where or whereCrafted(itemId)
		addHeader(if recipe.From then `만드는 법 · {craftWhere}` else `사는 곳 · {craftWhere}`)
		if recipe.From then
			addText(`{ItemDefs.Items[recipe.From.Id].DisplayName} {recipe.From.Count}개를 모아서 만들어요.`, UiKit.Colors.SubText)
		end
		addRecipe(recipe)
	else
		local ore = OreDefs[itemId]
		if ore then
			addHeader("얻는 법")
			addText(if ore.Kind == "Tree" then `{josa(ore.DisplayName, "을", "를")} 도끼로 베면 나와요.` else `{ore.DisplayName} 바위를 곡괭이로 캐면 나와요.`)
		else
			for _, mob in MobDefs do
				if mob.LootId == itemId then
					addHeader("얻는 법")
					addText(`{josa(mob.DisplayName, "을", "를")} 잡으면 나와요.`)
					break
				end
			end
		end
	end

	-- 쓰이는 곳 (이 아이템이 재료인 조합식)
	local used = RecipeView.usedIn(itemId)
	if #used > 0 then
		addHeader("이걸로 만들 수 있어요")
		addItemList(used)
	end
end

-- 모델을 돌리고 카메라를 모델 크기·창 비율에 맞춘다 (매 프레임)
local function updateSpin(dt: number)
	local current = model
	if not current then
		return
	end
	angle = (angle + dt * (2 * math.pi / Config.ItemDetail.SpinSeconds)) % (2 * math.pi)
	-- 상자 가운데를 원점에 두고 세로축으로 돌린다
	current:PivotTo(CFrame.Angles(0, angle, 0) * CFrame.new(-modelCenter))
	-- 창이 좁으면 가로 시야가 더 좁으니 둘 중 작은 쪽에 맞춘다
	local size = viewport.AbsoluteSize
	local aspect = if size.Y > 0 then size.X / size.Y else 1
	local halfV = math.rad(camera.FieldOfView / 2)
	local halfH = math.atan(math.tan(halfV) * aspect)
	local distance = modelRadius / math.sin(math.min(halfV, halfH)) * 1.02
	camera.CFrame = CFrame.Angles(math.rad(-Config.ItemDetail.Tilt), 0, 0) * CFrame.new(0, 0, distance)
end

-- 큰 3D 모델을 넣는다 (없으면 색 네모)
local function setModel(itemId: string)
	if model then
		model:Destroy()
		model = nil
	end
	for _, child in viewport:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local template = ItemIcon.getModel(itemId)
	if not template then
		ItemIcon.create(viewport, itemId) -- 모델이 없으면 아이콘(색 네모)을 대신
		return
	end
	local clone = template:Clone()
	clone:PivotTo(CFrame.new())
	local boxCFrame, boxSize = clone:GetBoundingBox()
	modelCenter = boxCFrame.Position
	modelRadius = math.max(boxSize.Magnitude / 2, 0.1)
	clone.Parent = viewport
	model = clone
	angle = math.rad(35)
	updateSpin(0)
end

-- 창 화면을 만든다 (처음 열 때 한 번)
local function build(): ScreenGui
	local screen = Instance.new("ScreenGui")
	screen.Name = "ItemDetailGui"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 20 -- 가방(5)·상점(10)보다 위, 끌기 아이콘(50)보다 아래
	screen.Enabled = false
	screen.Parent = localPlayer:WaitForChild("PlayerGui")

	-- 창 바깥을 누르면 닫힌다
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Parent = screen
	backdrop.Activated:Connect(function()
		ItemDetailUI.close()
	end)

	panel = UiKit.panel(screen, UDim2.fromScale(0.92, 0.86), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	panel.ZIndex = 2
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(600, 430)
	constraint.Parent = panel
	-- 창 안을 눌러도 뒤로 새지 않게 (빈 곳은 아무 일 없음)
	local blocker = Instance.new("TextButton")
	blocker.Text = ""
	blocker.AutoButtonColor = false
	blocker.BackgroundTransparency = 1
	blocker.Size = UDim2.fromScale(1, 1)
	blocker.Parent = panel

	nameLabel = UiKit.label(panel, "", UDim2.new(1, -70, 0, 34), UDim2.fromOffset(16, 8), UiKit.Colors.Text, 24)
	nameLabel.TextScaled = true
	local nameLimit = Instance.new("UITextSizeConstraint")
	nameLimit.MaxTextSize = 24
	nameLimit.Parent = nameLabel
	local closeButton = UiKit.button(panel, "X", UDim2.fromOffset(40, 40), UDim2.new(1, -50, 0, 6), function()
		ItemDetailUI.close()
	end)
	closeButton.TextSize = 20

	-- 왼쪽: 돌아가는 모델 + 별·분류
	local left = Instance.new("Frame")
	left.BackgroundTransparency = 1
	left.Size = UDim2.new(0.44, -16, 1, -56)
	left.Position = UDim2.fromOffset(12, 48)
	left.Parent = panel
	viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.new(1, 0, 1, -50)
	viewport.BackgroundColor3 = UiKit.Colors.PanelLight
	viewport.BorderSizePixel = 0
	viewport.Ambient = Color3.fromRGB(175, 175, 175)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-1, -2, -1)
	viewport.Parent = left
	UiKit.corner(viewport, 10)
	camera = Instance.new("Camera")
	camera.FieldOfView = Config.ItemDetail.FieldOfView
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	starsLabel = UiKit.label(left, "", UDim2.new(1, 0, 0, 26), UDim2.new(0, 0, 1, -48), UiKit.Colors.Gold, 22)
	starsLabel.TextXAlignment = Enum.TextXAlignment.Center
	kindLabel = UiKit.label(left, "", UDim2.new(1, 0, 0, 20), UDim2.new(0, 0, 1, -22), UiKit.Colors.SubText, 14)
	kindLabel.TextXAlignment = Enum.TextXAlignment.Center

	-- 오른쪽: 능력치·만드는 법 (스크롤)
	info = UiKit.list(panel, UDim2.new(0.56, -8, 1, -56), UDim2.new(0.44, 4, 0, 48))
	info.ZIndex = 3

	gui = screen
	return screen
end

-- 지금 열려 있는지
function ItemDetailUI.isOpen(): boolean
	return gui ~= nil and (gui :: ScreenGui).Enabled
end

-- 지금 보여 주는 아이템 Id (닫혀 있으면 nil)
function ItemDetailUI.current(): string?
	return if ItemDetailUI.isOpen() then currentItem else nil
end

-- 아이템 상세 창을 연다 (이미 열려 있으면 내용만 바꾼다)
function ItemDetailUI.open(itemId: string)
	local def = ItemDefs.Items[itemId]
	if not def then
		return
	end
	local screen = gui or build()
	currentItem = itemId
	local kindText, tier = describeKind(itemId)
	nameLabel.Text = def.DisplayName
	nameLabel.TextColor3 = if tier then TIER_COLORS[tier] or UiKit.Colors.Text else UiKit.Colors.Text
	starsLabel.Text = if tier then string.rep("★", tier) .. string.rep("☆", 4 - tier) else ""
	kindLabel.Text = kindText
	setModel(itemId)
	drawInfo(itemId)
	info.CanvasPosition = Vector2.zero
	screen.Enabled = true
	if not spinConnection then
		spinConnection = RunService.RenderStepped:Connect(updateSpin)
	end
end

-- 창을 닫는다
function ItemDetailUI.close()
	if gui then
		gui.Enabled = false
	end
	currentItem = nil
	if spinConnection then
		spinConnection:Disconnect()
		spinConnection = nil
	end
	if model then
		model:Destroy()
		model = nil
	end
end

openDetail = ItemDetailUI.open

-- 가방이 바뀌면 열린 창의 숫자(가진 개수·재료 색)를 다시 그린다
InventoryState.Changed:Connect(function()
	local itemId = ItemDetailUI.current()
	if itemId then
		drawInfo(itemId)
	end
end)

return ItemDetailUI
