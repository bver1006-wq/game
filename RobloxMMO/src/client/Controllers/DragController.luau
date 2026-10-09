--!strict
-- 아이템 끌어다 놓기. 가방 칸·빠른 호출 칸에 붙여 쓴다.
-- 누른 채 조금 움직이면 아이콘이 손가락(마우스)을 따라오고, 놓은 위치를 onDrop으로 알려준다.
-- 거의 움직이지 않고 떼면 onClick으로 처리한다 (PC 마우스, 모바일 터치 둘 다).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local ItemIcon = require(script.Parent.ItemIcon)

local DRAG_THRESHOLD = 8 -- 이만큼(픽셀) 움직여야 끌기로 본다
local GHOST_SIZE = 60

local DragController = {}

local ghostGui: ScreenGui? = nil

-- 끄는 동안 아이콘을 그릴 화면
local function getGhostGui(): ScreenGui
	if ghostGui and ghostGui.Parent then
		return ghostGui
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "DragGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	ghostGui = gui
	return gui
end

-- 버튼에 끌기를 붙인다
-- getItemId: 지금 이 칸의 아이템 (없으면 끌지 않음)
-- onClick: 끌지 않고 눌렀다 뗐을 때
-- onDrop: 끌어서 놓았을 때 (화면 위치, 아이템 Id)
function DragController.attach(
	button: GuiObject,
	getItemId: () -> string?,
	onClick: () -> (),
	onDrop: (position: Vector2, itemId: string) -> ()
)
	button.InputBegan:Connect(function(input: InputObject)
		local isMouse = input.UserInputType == Enum.UserInputType.MouseButton1
		local isTouch = input.UserInputType == Enum.UserInputType.Touch
		if not isMouse and not isTouch then
			return
		end
		local itemId = getItemId()
		local start = Vector2.new(input.Position.X, input.Position.Y)
		local current = start
		local ghost: Frame? = nil

		local moveConnection = UserInputService.InputChanged:Connect(function(changed: InputObject)
			local matches = (isMouse and changed.UserInputType == Enum.UserInputType.MouseMovement)
				or (isTouch and changed == input)
			if not matches then
				return
			end
			current = Vector2.new(changed.Position.X, changed.Position.Y)
			if not ghost and itemId and (current - start).Magnitude >= DRAG_THRESHOLD then
				local frame = Instance.new("Frame")
				frame.Size = UDim2.fromOffset(GHOST_SIZE, GHOST_SIZE)
				frame.AnchorPoint = Vector2.new(0.5, 0.5)
				frame.BackgroundTransparency = 1
				frame.Parent = getGhostGui()
				ItemIcon.create(frame, itemId)
				ghost = frame
			end
			if ghost then
				ghost.Position = UDim2.fromOffset(current.X, current.Y)
			end
		end)

		local endConnection: RBXScriptConnection
		endConnection = UserInputService.InputEnded:Connect(function(ended: InputObject)
			local matches = (isMouse and ended.UserInputType == Enum.UserInputType.MouseButton1)
				or (isTouch and ended == input)
			if not matches then
				return
			end
			moveConnection:Disconnect()
			endConnection:Disconnect()
			if ghost then
				ghost:Destroy()
				if itemId then
					onDrop(current, itemId)
				end
			elseif (current - start).Magnitude < DRAG_THRESHOLD then
				onClick()
			end
		end)
	end)
end

-- 화면 위치가 GUI 안에 있는지
function DragController.isOver(gui: GuiObject, position: Vector2): boolean
	local topLeft = gui.AbsolutePosition
	local size = gui.AbsoluteSize
	return position.X >= topLeft.X
		and position.Y >= topLeft.Y
		and position.X <= topLeft.X + size.X
		and position.Y <= topLeft.Y + size.Y
end

return DragController
