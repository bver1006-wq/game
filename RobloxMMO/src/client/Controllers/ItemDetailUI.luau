--!strict
-- 아이템 상세 창 (2026-10-09 사용자 요청): 가방·상점에서 아이템을 한 번 누르면 뜬다.
-- 세로로 긴 창이 연 창(host: 가방 창·상점 창) 바로 오른쪽에 붙는다 (장비 창처럼). 화면 가운데를 가리지 않고 어두운 배경도 없다
-- 오른쪽에 자리가 모자라면 host 무리(가방이면 장비 창까지)를 왼쪽으로 조금 밀고, 그래도 안 되면(휴대폰) host 창 오른쪽 안에 겹쳐 띄운다
-- host가 움직이거나 크기가 바뀌거나 화면 크기가 바뀌면 다시 맞춘다. host가 닫히면 같이 닫힌다
-- 위→아래: 돌아가는 큰 3D 모델(ReplicatedStorage/ItemIcons) · 이름·단계 별 · 분류 · 능력치 · 가진 개수·판매가 · 만드는 법 · 쓰이는 곳 (길면 스크롤)
-- X 버튼으로 닫는다. 처음 열 때 화면을 만든다 (Main.client에서 init을 부르지 않아도 된다)
-- 2026-10-09 고침: 예전 창은 panel.ZIndex = 2인데 안쪽 글자·모델은 ZIndex 1이었다. Instance.new로 만든 ScreenGui는
--   ZIndexBehavior가 Global이라 안쪽이 전부 패널 배경 뒤에 그려져 빈 상자 + 어두운 전체 화면만 보였다 → Sibling으로 정한다
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
local TierDefs = require(ReplicatedStorage.Shared.TierDefs)
local InventoryState = require(script.Parent.InventoryState)
local ItemIcon = require(script.Parent.ItemIcon)
local RecipeView = require(script.Parent.RecipeView)
local UiKit = require(script.Parent.UiKit)

local localPlayer = Players.LocalPlayer

-- 단계별 이름 색·별은 TierDefs (1 나무·가죽 / 2 구리 / 3 철 / 4 다이아몬드 / 5 미스릴 / 6 오리하르콘)
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
local viewHolder: Frame
local viewport: ViewportFrame
local info: ScrollingFrame -- 창 전체 스크롤 (모델·이름·능력치 ...)
local body: Frame -- info 안에서 아이템마다 다시 그리는 부분 (능력치~쓰이는 곳)
local camera: Camera
local spinConnection: RBXScriptConnection? = nil
local currentItem: string? = nil
local model: Model? = nil
local modelCenter = Vector3.zero -- 모델 기준점에서 본 상자 가운데
local modelRadius = 1
local angle = 0

-- 붙어 있는 창(host)과 같이 움직이는 창들(group, 가방이면 장비 창). 자리를 내려고 왼쪽으로 민 만큼(appliedShift)은 닫을 때 되돌린다
local host: GuiObject? = nil
local hostGroup: { GuiObject } = {}
local hostOrigins: { [GuiObject]: UDim2 } = {}
local hostConnections: { RBXScriptConnection } = {}
local appliedShift = 0
local positioning = false

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
		local multiplier = TierDefs.pick(Config.Equipment.TierMultiplier, def.Tier) or 1
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

-- 이 아이템을 떨어뜨리는 몹 이름 목록 (주 전리품 MobDefs.LootId + 두 번째 전리품 Config.Mobs ExtraLoot).
-- 보스만 주는 전리품(Config.MobBoss.ExtraLoot)이면 둘째 값 true (2026-10-09)
local function dropSources(itemId: string): ({ string }, boolean)
	local names: { string } = {}
	for id, mob in MobDefs do
		local found = mob.LootId == itemId
		local extra = ((Config.Mobs :: any)[id] or {}).ExtraLoot
		if not found and typeof(extra) == "table" then
			for _, entry in extra do
				if entry.Id == itemId then
					found = true
				end
			end
		end
		if found then
			table.insert(names, mob.DisplayName)
		end
	end
	local bossOnly = false
	local bossLoot = (Config.MobBoss :: any).ExtraLoot
	if typeof(bossLoot) == "table" then
		for _, entry in bossLoot do
			if entry.Id == itemId then
				bossOnly = true
			end
		end
	end
	table.sort(names)
	return names, bossOnly
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
	local ore = OreDefs[itemId]
	if ore then
		return if ore.Kind == "Tree" then "통나무 · 재료" else "광석 · 재료", nil
	end
	if (Config.Smelting.Recipes :: any)[itemId] then
		return "괴 · 재료", nil
	end
	local sources, bossOnly = dropSources(itemId)
	if #sources > 0 or bossOnly then
		return "몹 전리품 · 재료", nil
	end
	return "아이템", nil
end

-- 정보 영역을 비운다
local function clearInfo()
	for _, child in body:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local lineOrder = 0

-- 정보 영역에 섹션 제목 한 줄
local function addHeader(text: string)
	lineOrder += 1
	local label = UiKit.label(body, text, UDim2.new(1, -8, 0, 22), nil, UiKit.Colors.Gold, 15)
	label.AutomaticSize = Enum.AutomaticSize.Y
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
	row.Parent = body
	-- 창이 좁으니 이름 42% · 값 58%
	UiKit.label(row, name, UDim2.new(0.42, -4, 0, 22), nil, UiKit.Colors.SubText, 13)
	local valueLabel = UiKit.label(row, value, UDim2.new(0.58, 0, 0, 22), UDim2.fromScale(0.42, 0), color or UiKit.Colors.Text, 14)
	valueLabel.AutomaticSize = Enum.AutomaticSize.Y
end

-- 정보 영역에 설명 글 한 줄 (여러 줄로 감김)
local function addText(text: string, color: Color3?)
	lineOrder += 1
	local label = UiKit.label(body, text, UDim2.new(1, -8, 0, 20), nil, color or UiKit.Colors.Text, 13)
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
	holder.Parent = body
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
	holder.Parent = body
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
			local sources, bossOnly = dropSources(itemId)
			if #sources > 0 then
				addHeader("얻는 법")
				addText(`{josa(table.concat(sources, ", "), "을", "를")} 잡으면 나와요.`)
			elseif bossOnly then
				addHeader("얻는 법")
				addText(`{Config.MobBoss.NamePrefix}몹(커다란 몹)을 잡으면 나와요.`)
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
	local aspect = if size.Y > 0 and size.X > 0 then size.X / size.Y else 1
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

-- 자리를 내려고 host 무리를 왼쪽으로 shift(px)만큼 민다 (0이면 원래 자리)
local function applyShift(shift: number)
	if math.abs(shift - appliedShift) < 0.5 then
		return
	end
	appliedShift = shift
	for frame, origin in hostOrigins do
		if frame.Parent then
			frame.Position = origin + UDim2.fromOffset(-shift, 0)
		end
	end
end

-- 창 위치·크기를 host 옆에 맞춘다 (host가 움직이거나 화면 크기가 바뀌면 다시 부른다)
local function reposition()
	local screen = gui
	if not screen or not screen.Enabled or positioning then
		return
	end
	positioning = true
	local settings = Config.ItemDetail
	local screenSize = screen.AbsoluteSize
	local origin = screen.AbsolutePosition
	if screenSize.X <= 0 or screenSize.Y <= 0 then
		positioning = false
		return
	end
	local margin = settings.ScreenMargin
	local gap = settings.Gap
	local width = math.min(settings.PanelWidth, screenSize.X - margin * 2)
	local x, y, w, h
	local shift = 0
	local current = host
	if current then
		-- 밀기 전 원래 자리 기준으로 계산한다 (이미 민 만큼 되돌려 본다)
		local hostPos = current.AbsolutePosition - origin + Vector2.new(appliedShift, 0)
		local hostSize = current.AbsoluteSize
		local hostRight = hostPos.X + hostSize.X
		local groupLeft = hostPos.X
		for _, frame in hostGroup do
			if frame ~= current and frame.Visible then
				groupLeft = math.min(groupLeft, frame.AbsolutePosition.X - origin.X + appliedShift)
			end
		end
		local room = screenSize.X - margin - (hostRight + gap) -- 오른쪽 빈 자리
		local need = width - room -- 모자란 만큼
		if need <= 0 or groupLeft - margin >= need then
			-- 오른쪽에 붙인다 (모자라면 host 무리를 need만큼 왼쪽으로)
			shift = math.max(need, 0)
			w = width
			x = hostRight - shift + gap
			y = hostPos.Y
			h = math.max(hostSize.Y, settings.MinHeight)
		else
			-- 자리가 없다(휴대폰): host 창 오른쪽 안에 겹친다 (화면 전체는 가리지 않음)
			w = math.min(width, math.max(hostSize.X * settings.OverlayRatio, 170))
			x = hostRight - w - 6
			y = hostPos.Y + 6
			h = math.max(hostSize.Y - 12, 120)
		end
	else
		-- 붙을 창이 없으면 화면 오른쪽에 세로로
		w = width
		x = screenSize.X - margin - w
		y = margin + 60
		h = screenSize.Y * 0.7
	end
	-- 화면 밖으로 나가지 않게
	h = math.min(h, screenSize.Y - margin * 2)
	y = math.clamp(y, margin, math.max(margin, screenSize.Y - margin - h))
	x = math.clamp(x, margin, math.max(margin, screenSize.X - margin - w))
	panel.Position = UDim2.fromOffset(x, y)
	panel.Size = UDim2.fromOffset(w, h)
	-- 모델 칸 높이: 창 너비만큼(정사각형), 단 창 높이의 42%·Config 값보다 크지 않게
	viewHolder.Size = UDim2.new(1, -8, 0, math.floor(math.clamp(math.min(w - 24, h * 0.42), 80, settings.ViewHeight)))
	applyShift(shift)
	positioning = false
end

-- 붙어 있던 창을 놓는다 (밀었던 창들을 원래 자리로)
local function releaseHost()
	for _, connection in hostConnections do
		connection:Disconnect()
	end
	table.clear(hostConnections)
	for frame, origin in hostOrigins do
		if frame.Parent then
			frame.Position = origin
		end
	end
	table.clear(hostOrigins)
	table.clear(hostGroup)
	appliedShift = 0
	host = nil
end

-- 이 창(newHost) 옆에 붙인다. group은 같이 밀 창들 (가방이면 장비 창)
local function setHost(newHost: GuiObject, group: { GuiObject })
	if host == newHost then
		return
	end
	releaseHost()
	host = newHost
	table.insert(hostGroup, newHost)
	for _, frame in group do
		table.insert(hostGroup, frame)
	end
	for _, frame in hostGroup do
		hostOrigins[frame] = frame.Position
	end
	table.insert(hostConnections, newHost:GetPropertyChangedSignal("AbsolutePosition"):Connect(reposition))
	table.insert(hostConnections, newHost:GetPropertyChangedSignal("AbsoluteSize"):Connect(reposition))
end

-- host가 아직 보이는지 (닫혔으면 상세 창도 닫는다)
local function hostShown(current: GuiObject): boolean
	if not current.Visible or not current.Parent then
		return false
	end
	local screen = current:FindFirstAncestorWhichIsA("ScreenGui")
	return screen == nil or screen.Enabled
end

-- 창 화면을 만든다 (처음 열 때 한 번)
local function build(): ScreenGui
	local screen = Instance.new("ScreenGui")
	screen.Name = "ItemDetailGui"
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling -- 자식은 언제나 부모 위에 (예전 버그의 원인)
	screen.DisplayOrder = 20 -- 가방(5)·상점(10)보다 위, 끌기 아이콘(50)보다 아래
	screen.Enabled = false
	screen.Parent = localPlayer:WaitForChild("PlayerGui")

	panel = UiKit.panel(screen, UDim2.fromOffset(Config.ItemDetail.PanelWidth, 400), UDim2.fromOffset(0, 0))
	-- 창 안을 눌러도 뒤(가방·상점)로 새지 않게 (빈 곳은 아무 일 없음). 맨 먼저 만들어 다른 것들 아래에 깔린다
	local blocker = Instance.new("TextButton")
	blocker.Name = "Blocker"
	blocker.Text = ""
	blocker.AutoButtonColor = false
	blocker.BackgroundTransparency = 1
	blocker.Size = UDim2.fromScale(1, 1)
	blocker.Parent = panel

	-- 창 전체 스크롤: 모델 → 이름 → 별 → 분류 → 능력치 ...
	info = UiKit.list(panel, UDim2.new(1, -10, 1, -16), UDim2.fromOffset(8, 8))
	info.ZIndex = 2

	viewHolder = Instance.new("Frame")
	viewHolder.Name = "View"
	viewHolder.BackgroundTransparency = 1
	viewHolder.Size = UDim2.new(1, -8, 0, Config.ItemDetail.ViewHeight)
	viewHolder.LayoutOrder = 1
	viewHolder.Parent = info
	viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundColor3 = UiKit.Colors.PanelLight
	viewport.BorderSizePixel = 0
	viewport.Ambient = Color3.fromRGB(175, 175, 175)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-1, -2, -1)
	viewport.Parent = viewHolder
	UiKit.corner(viewport, 10)
	camera = Instance.new("Camera")
	camera.FieldOfView = Config.ItemDetail.FieldOfView
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	nameLabel = UiKit.label(info, "", UDim2.new(1, -8, 0, 26), nil, UiKit.Colors.Text, 20)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.AutomaticSize = Enum.AutomaticSize.Y
	nameLabel.LayoutOrder = 2
	starsLabel = UiKit.label(info, "", UDim2.new(1, -8, 0, 22), nil, UiKit.Colors.Gold, 20)
	starsLabel.TextXAlignment = Enum.TextXAlignment.Center
	starsLabel.LayoutOrder = 3
	kindLabel = UiKit.label(info, "", UDim2.new(1, -8, 0, 18), nil, UiKit.Colors.SubText, 13)
	kindLabel.TextXAlignment = Enum.TextXAlignment.Center
	kindLabel.LayoutOrder = 4

	body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.LayoutOrder = 5
	body.Parent = info
	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.Padding = UDim.new(0, 6)
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Parent = body

	-- 닫기 X: 모델 칸 오른쪽 위에 겹쳐 둔다 (스크롤해도 그 자리)
	local closeButton = UiKit.button(panel, "X", UDim2.fromOffset(34, 34), UDim2.new(1, -40, 0, 6), function()
		ItemDetailUI.close()
	end)
	closeButton.TextSize = 18
	closeButton.ZIndex = 5

	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(reposition)
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
-- hostFrame: 옆에 붙을 창 (가방 창·상점 창). nil이면 지금 붙어 있는 창 그대로 (상세 창 안에서 다른 아이템으로 넘어갈 때)
-- group: hostFrame과 같이 왼쪽으로 밀어도 되는 창들 (가방이면 장비 창)
function ItemDetailUI.open(itemId: string, hostFrame: GuiObject?, group: { GuiObject }?)
	local def = ItemDefs.Items[itemId]
	if not def then
		return
	end
	local screen = gui or build()
	if hostFrame then
		setHost(hostFrame, group or {})
	end
	currentItem = itemId
	local kindText, tier = describeKind(itemId)
	nameLabel.Text = def.DisplayName
	nameLabel.TextColor3 = if tier then TierDefs.get(tier).TextColor else UiKit.Colors.Text
	starsLabel.Text = if tier then TierDefs.stars(tier) else ""
	starsLabel.Visible = tier ~= nil
	kindLabel.Text = kindText
	screen.Enabled = true
	reposition()
	setModel(itemId)
	drawInfo(itemId)
	info.CanvasPosition = Vector2.zero
	if not spinConnection then
		spinConnection = RunService.RenderStepped:Connect(function(dt: number)
			-- 붙어 있던 창이 닫히면 같이 닫는다
			local current = host
			if current and not hostShown(current) then
				ItemDetailUI.close()
				return
			end
			updateSpin(dt)
		end)
	end
end

-- 창을 닫는다
function ItemDetailUI.close()
	if gui then
		gui.Enabled = false
	end
	currentItem = nil
	releaseHost()
	if spinConnection then
		spinConnection:Disconnect()
		spinConnection = nil
	end
	if model then
		model:Destroy()
		model = nil
	end
end

openDetail = function(itemId: string)
	ItemDetailUI.open(itemId)
end

-- 가방이 바뀌면 열린 창의 숫자(가진 개수·재료 색)를 다시 그린다
InventoryState.Changed:Connect(function()
	local itemId = ItemDetailUI.current()
	if itemId then
		drawInfo(itemId)
	end
end)

return ItemDetailUI
