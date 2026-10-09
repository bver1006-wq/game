--!strict
-- 화면 가장자리 작은 버튼들 (2026-10-09 사용자 요청)
--   왼쪽 위(가방 옆) 음표 🎵: 누르면 배경음 끄기·켜기, 옆 -/+로 크기 조절 (MusicController)
--   왼쪽 가운데 "🏠 마을로": 귀환 (서버 ReturnHome). 공격 버튼(오른쪽 아래)·가방(왼쪽 위)과 떨어진 곳이라 잘못 누르기 어렵다
--     누르면 CastTime초 뒤 마을로, 그사이 움직이거나 다시 누르면 취소

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MusicController = require(script.Parent.MusicController)
local UiKit = require(script.Parent.UiKit)

local localPlayer = Players.LocalPlayer

local QuickButtonsHUD = {}

-- 둥근 작은 버튼
local function makeButton(parent: Instance, text: string, size: UDim2, position: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = UiKit.Colors.Panel
	button.BackgroundTransparency = 0.15
	button.AutoButtonColor = true
	button.Font = Enum.Font.FredokaOne
	button.Text = text
	button.TextScaled = true
	button.TextColor3 = UiKit.Colors.Text
	button.Parent = parent
	UiKit.corner(button, 10)
	UiKit.stroke(button)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.12, 0)
	padding.PaddingBottom = UDim.new(0.12, 0)
	padding.PaddingLeft = UDim.new(0.08, 0)
	padding.PaddingRight = UDim.new(0.08, 0)
	padding.Parent = button
	return button
end

-- 음표 버튼 + 크기 조절
local function buildMusic(gui: ScreenGui)
	local layout = Config.QuickButtons
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Position = layout.MusicPosition
	holder.Size = UDim2.fromOffset(layout.MusicSize * 3 + 12, layout.MusicSize)
	holder.Parent = gui

	local size = layout.MusicSize
	local note = makeButton(holder, "🎵", UDim2.fromOffset(size, size), UDim2.fromOffset(0, 0))
	local minus = makeButton(holder, "−", UDim2.fromOffset(size * 0.8, size * 0.8), UDim2.fromOffset(size + 6, size * 0.1))
	local plus = makeButton(holder, "+", UDim2.fromOffset(size * 0.8, size * 0.8), UDim2.fromOffset(size * 1.8 + 12, size * 0.1))

	-- 크기 막대 (음표 아래 작은 칸들)
	local bars = Instance.new("Frame")
	bars.BackgroundTransparency = 1
	bars.Position = UDim2.fromOffset(size + 6, size + 2)
	bars.Size = UDim2.fromOffset(size * 1.6 + 6, 6)
	bars.Parent = holder
	local _, total = MusicController.getLevel()
	local cells: { Frame } = {}
	for index = 1, total do
		local cell = Instance.new("Frame")
		cell.BorderSizePixel = 0
		cell.Size = UDim2.new(1 / total, -2, 1, 0)
		cell.Position = UDim2.new((index - 1) / total, 0, 0, 0)
		cell.Parent = bars
		UiKit.corner(cell, 2)
		cells[index] = cell
	end

	local function refresh()
		local muted = MusicController.isMuted()
		local level = MusicController.getLevel()
		note.Text = if muted then "🔇" else "🎵"
		note.TextColor3 = if muted then UiKit.Colors.SubText else UiKit.Colors.Gold
		note.BackgroundColor3 = if muted then UiKit.Colors.ButtonDisabled else UiKit.Colors.Panel
		for index, cell in cells do
			cell.BackgroundColor3 = if not muted and index <= level then UiKit.Colors.Gold else UiKit.Colors.ButtonDisabled
		end
	end
	note.Activated:Connect(function()
		MusicController.setMuted(not MusicController.isMuted())
		refresh()
	end)
	minus.Activated:Connect(function()
		MusicController.changeLevel(-1)
		refresh()
	end)
	plus.Activated:Connect(function()
		MusicController.changeLevel(1)
		refresh()
	end)
	refresh()
end

-- 귀환 버튼
local function buildReturn(gui: ScreenGui)
	local layout = Config.QuickButtons
	local remote = Remotes.get(Remotes.Names.ReturnHome)
	local button = makeButton(gui, "🏠 마을로", layout.ReturnSize, layout.ReturnPosition)
	button.AnchorPoint = Vector2.new(0, 0.5)
	button.BackgroundColor3 = Color3.fromRGB(60, 90, 70)
	button.Activated:Connect(function()
		remote:FireServer()
	end)
end

-- 클라이언트 시작 시 한 번 호출 (MusicController.init 이후)
function QuickButtonsHUD.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "QuickButtons"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	buildMusic(gui)
	buildReturn(gui)
end

return QuickButtonsHUD
