--!strict
-- 하단 빠른 호출 칸 (Config.Inventory.HotbarSlots칸, 기본 5칸).
-- 가방에서 아이템을 끌어다 놓고, 칸을 누르거나 숫자키 1~5로 바로 쓴다.
--   도구(곡괭이): 들기 / 다시 누르면 내려놓기
--   소모품(귀환 주문서): 서버에 사용 요청 (ItemUseService)
--   물약·장비: 아직 없음 (나중에 착용·사용 추가)
-- 칸 배치는 바뀔 때마다 서버에 보내 저장하고(SaveHotbar), 들어올 때 플레이어 속성 SavedHotbar로 되살린다 (2026-10-09)
-- Roblox 기본 하단 도구 바는 끄고 이 칸으로 대신한다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local EquipmentDefs = require(ReplicatedStorage.Shared.EquipmentDefs)
local ItemDefs = require(ReplicatedStorage.Shared.ItemDefs)
local DragController = require(script.Parent.DragController)
local InventoryState = require(script.Parent.InventoryState)
local CooldownController = require(script.Parent.CooldownController)
local ItemIcon = require(script.Parent.ItemIcon)
local NotifyController = require(script.Parent.NotifyController)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UiKit = require(script.Parent.UiKit)

local SLOT_SIZE = 64
local KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five }

local localPlayer = Players.LocalPlayer

local HotbarController = {}

local slots: { string? } = {} -- 칸 번호 → 아이템 Id
local slotFrames: { Frame } = {}
local knownTools: { [string]: boolean } = {} -- 이미 본 도구 (새로 생긴 도구만 빈 칸에 자동으로 넣는다)
local layoutReady = false -- 저장된 배치를 받았다 (그 전에는 자동으로 채우지도, 저장하지도 않는다)
local hasInventory = false -- 서버에서 가방 내용을 한 번이라도 받았다
local skipFillOnce = false -- 저장된 배치를 되살렸으면, 처음 받은 가방의 도구는 자동으로 채우지 않는다
local lastSent = ""
local saveRemote: RemoteEvent

-- 아이템이 들어 있는 칸 번호 (slots에 빈 칸이 섞여 있어서 table.find 대신 직접 찾는다)
local function findSlot(itemId: string): number?
	for index = 1, #slotFrames do
		if slots[index] == itemId then
			return index
		end
	end
	return nil
end

-- 캐릭터가 지금 들고 있는 도구의 아이템 Id
local function equippedItemId(): string?
	local character = localPlayer.Character
	local tool = character and character:FindFirstChildWhichIsA("Tool")
	local id = tool and tool:GetAttribute("PickaxeId")
	return if typeof(id) == "string" then id else nil
end

-- 배치가 바뀌었으면 서버에 보내 저장한다
local function sendLayout()
	if not layoutReady or not saveRemote then
		return
	end
	local list: { string } = {}
	for index = 1, Config.Inventory.HotbarSlots do
		list[index] = slots[index] or ""
	end
	local key = table.concat(list, ",")
	if key ~= lastSent then
		lastSent = key
		saveRemote:FireServer(list)
	end
end

-- 칸 그림을 다시 그린다
local function render()
	sendLayout()
	local equipped = equippedItemId()
	for index, frame in slotFrames do
		for _, child in frame:GetChildren() do
			if child:IsA("ViewportFrame") or child.Name == "Icon" or child.Name == "Count" or child.Name == "Cooldown" then
				child:Destroy()
			end
		end
		local itemId = slots[index]
		local stroke = frame:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if itemId and itemId == equipped then UiKit.Colors.Gold else UiKit.Colors.Border
			stroke.Thickness = if itemId and itemId == equipped then 3 else 2
		end
		if itemId then
			local holder = Instance.new("Frame")
			holder.Name = "Icon"
			holder.Size = UDim2.new(1, -8, 1, -8)
			holder.Position = UDim2.fromOffset(4, 4)
			holder.BackgroundTransparency = 1
			holder.Parent = frame
			ItemIcon.create(holder, itemId)
			CooldownController.attach(frame, itemId)
			local def = ItemDefs.Items[itemId]
			local count = InventoryState.count(itemId)
			if def and def.Stackable then
				local label = UiKit.label(frame, tostring(count), UDim2.new(1, -6, 0, 18), UDim2.new(0, 0, 1, -20), Color3.new(1, 1, 1), 14)
				label.Name = "Count"
				label.TextXAlignment = Enum.TextXAlignment.Right
				label.ZIndex = 3
			end
		end
	end
end

-- 아이템을 칸에 넣는다 (같은 아이템이 다른 칸에 있으면 옮긴다)
function HotbarController.assign(index: number, itemId: string?)
	if index < 1 or index > #slotFrames then
		return
	end
	if itemId then
		local existing = findSlot(itemId)
		if existing then
			slots[existing] = nil
		end
	end
	slots[index] = itemId
	render()
end

-- 화면 위치에 있는 칸 번호 (없으면 nil)
function HotbarController.slotAt(position: Vector2): number?
	for index, frame in slotFrames do
		if DragController.isOver(frame, position) then
			return index
		end
	end
	return nil
end

-- 도구를 들거나 내려놓는다
function HotbarController.useItem(itemId: string)
	local def = ItemDefs.Items[itemId]
	if not def then
		return
	end
	if def.Usable then
		Remotes.get(Remotes.Names.UseItem):FireServer(itemId)
		return
	end
	-- 장비(헬멧·갑옷 등)는 한 번 누르면 끼우고, 이미 끼웠으면 뺀다
	local equipment = EquipmentDefs.Items[itemId]
	if equipment then
		if localPlayer:GetAttribute(`Equip_{equipment.Slot}`) == itemId then
			Remotes.get(Remotes.Names.UnequipSlot):FireServer(equipment.Slot)
		else
			Remotes.get(Remotes.Names.EquipItem):FireServer(itemId)
		end
		return
	end
	if def.Category ~= "Tool" and def.Category ~= "Weapon" then
		NotifyController.show(`{def.DisplayName}: 아직 바로 쓸 수 없는 아이템이에요.`, "info")
		return
	end
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if equippedItemId() == itemId then
		humanoid:UnequipTools()
		return
	end
	local backpack = localPlayer:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	for _, tool in backpack:GetChildren() do
		if tool:IsA("Tool") and tool:GetAttribute("PickaxeId") == itemId then
			humanoid:EquipTool(tool)
			return
		end
	end
end

-- 칸 번호로 쓰기 (숫자키·클릭)
local function useSlot(index: number)
	local itemId = slots[index]
	if itemId then
		HotbarController.useItem(itemId)
	end
end

-- 가방이 바뀌면: 없어진 아이템은 칸에서 빼고, 새로 생긴 도구는 빈 칸에 넣는다
local function onInventoryChanged()
	if not layoutReady or not hasInventory then
		return
	end
	if skipFillOnce then
		skipFillOnce = false
		for itemId in InventoryState.get().Items do
			knownTools[itemId] = true
		end
	end
	for index = 1, #slotFrames do
		local itemId = slots[index]
		if itemId and InventoryState.count(itemId) <= 0 then
			slots[index] = nil
		end
	end
	for _, itemId in ItemDefs.Order do
		local def = ItemDefs.Items[itemId]
		if (def.Category == "Tool" or def.Category == "Weapon") and InventoryState.count(itemId) > 0 and not knownTools[itemId] then
			knownTools[itemId] = true
			if not findSlot(itemId) then
				for index = 1, #slotFrames do
					if slots[index] == nil then
						slots[index] = itemId
						break
					end
				end
			end
		end
	end
	render()
end

-- Roblox 기본 도구 바 끄기 (코어 GUI가 늦게 준비될 수 있어 몇 번 시도)
local function disableDefaultBackpack()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if ok then
			return
		end
		task.wait(0.5)
	end
end

-- 클라이언트 시작 시 한 번 호출
function HotbarController.init()
	task.spawn(disableDefaultBackpack)

	local gui = Instance.new("ScreenGui")
	gui.Name = "HotbarGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 15 -- 가방 창 배경보다 위 (가방을 연 채로 끌어다 놓을 수 있게)
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	local count = Config.Inventory.HotbarSlots
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -12)
	bar.Size = UDim2.fromOffset(count * (SLOT_SIZE + 8), SLOT_SIZE + 8)
	bar.BackgroundTransparency = 1
	bar.Parent = gui

	for index = 1, count do
		local frame = Instance.new("TextButton")
		frame.Name = "Slot" .. index
		frame.Text = ""
		frame.AutoButtonColor = false
		frame.Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE)
		frame.Position = UDim2.fromOffset((index - 1) * (SLOT_SIZE + 8) + 4, 4)
		frame.BackgroundColor3 = UiKit.Colors.Panel
		frame.BackgroundTransparency = 0.15
		frame.BorderSizePixel = 0
		frame.Parent = bar
		UiKit.corner(frame, 10)
		UiKit.stroke(frame)
		local number = UiKit.label(frame, tostring(index), UDim2.fromOffset(16, 16), UDim2.fromOffset(5, 2), UiKit.Colors.SubText, 12)
		number.ZIndex = 3
		slotFrames[index] = frame :: any

		-- 칸끼리 끌어서 바꾸기, 칸 밖으로 끌어내면 비우기
		DragController.attach(frame, function()
			return slots[index]
		end, function()
			useSlot(index)
		end, function(position, itemId)
			local target = HotbarController.slotAt(position)
			if target == index then
				return
			end
			if target then
				slots[index], slots[target] = slots[target], itemId
				render()
			else
				HotbarController.assign(index, nil)
			end
		end)
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local index = table.find(KEYS, input.KeyCode)
		if index and index <= count then
			useSlot(index)
		end
	end)
	InventoryState.Changed:Connect(function()
		hasInventory = true
		onInventoryChanged()
	end)

	-- 들고 있는 도구가 바뀌면 테두리 표시를 갱신
	local function watchCharacter(character: Model)
		character.ChildAdded:Connect(render)
		character.ChildRemoved:Connect(render)
		render()
	end
	localPlayer.CharacterAdded:Connect(watchCharacter)
	if localPlayer.Character then
		watchCharacter(localPlayer.Character)
	end
	-- 저장된 배치를 기다렸다가 되살린다 (서버가 불러오면 속성 SavedHotbar를 넣어 준다)
	saveRemote = Remotes.get(Remotes.Names.SaveHotbar)
	task.spawn(function()
		local started = os.clock()
		while localPlayer:GetAttribute("SavedHotbar") == nil and os.clock() - started < 20 do
			task.wait(0.1)
		end
		local saved = localPlayer:GetAttribute("SavedHotbar")
		if typeof(saved) == "string" and saved ~= "" then
			local any = false
			for index, itemId in string.split(saved, ",") do
				if index <= count and itemId ~= "" and ItemDefs.Items[itemId] then
					slots[index] = itemId
					knownTools[itemId] = true
					any = true
				end
			end
			skipFillOnce = any
		end
		lastSent = if typeof(saved) == "string" then saved else ""
		layoutReady = true
		onInventoryChanged()
		render()
	end)
	RunService.Heartbeat:Wait()
	onInventoryChanged()
end

return HotbarController
