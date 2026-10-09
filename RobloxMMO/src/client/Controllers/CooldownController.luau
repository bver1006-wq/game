--!strict
-- 아이템 쿨타임 표시: 가방 칸·빠른 칸 위에 어두운 덮개가 시계 방향으로 걷히며 남은 시간을 보여 준다 (숫자 없음).
-- 쿨타임 시작은 서버가 ItemCooldown(itemId, 초)으로 알려 준다. 실제로 막는 건 서버(ItemUseService)다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local CooldownController = {}

type Overlay = { ItemId: string, Root: Frame, RightGradient: UIGradient, LeftGradient: UIGradient }

local endsAt: { [string]: number } = {} -- 아이템 Id → 쿨타임 끝 시각 (os.clock)
local durations: { [string]: number } = {}
local overlays: { Overlay } = {}

-- 반쪽 덮개: 반쪽만 보이게 자르는 틀 안에, 칸 크기 사각형 + 날카로운 경계 그라데이션
local function half(root: Frame, isRight: boolean): UIGradient
	local clip = Instance.new("Frame")
	clip.Name = if isRight then "Right" else "Left"
	clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true
	clip.Size = UDim2.fromScale(0.5, 1)
	clip.Position = UDim2.fromScale(if isRight then 0.5 else 0, 0)
	clip.Parent = root
	local square = Instance.new("Frame")
	square.BackgroundColor3 = Color3.new(0, 0, 0)
	square.BackgroundTransparency = 0.35
	square.BorderSizePixel = 0
	square.Size = UDim2.fromScale(2, 1)
	square.Position = UDim2.fromScale(if isRight then -1 else 0, 0)
	square.Parent = clip
	local gradient = Instance.new("UIGradient")
	-- 앞 절반은 투명, 뒤 절반은 보임 (경계가 가운데를 지나는 날카로운 선)
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(0.501, 0),
		NumberSequenceKeypoint.new(1, 0),
	})
	gradient.Parent = square
	return gradient
end

-- 칸(parent)에 이 아이템의 쿨타임 덮개를 붙인다. 칸을 다시 그릴 때마다 새로 붙이면 된다
function CooldownController.attach(parent: GuiObject, itemId: string)
	local root = Instance.new("Frame")
	root.Name = "Cooldown"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = 5
	root.Visible = false
	root.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = root
	table.insert(overlays, { ItemId = itemId, Root = root, RightGradient = half(root, true), LeftGradient = half(root, false) })
end

-- 남은 비율 (0이면 쿨타임 없음)
function CooldownController.remaining(itemId: string): number
	local finish = endsAt[itemId]
	local duration = durations[itemId]
	if not finish or not duration or duration <= 0 then
		return 0
	end
	return math.clamp((finish - os.clock()) / duration, 0, 1)
end

-- 매 프레임: 덮개 각도를 맞춘다. 12시에서 시작해 시계 방향으로 걷힌다
local function update()
	for index = #overlays, 1, -1 do
		local overlay = overlays[index]
		if not overlay.Root.Parent then
			table.remove(overlays, index)
		else
			local remaining = CooldownController.remaining(overlay.ItemId)
			overlay.Root.Visible = remaining > 0
			if remaining > 0 then
				-- 걷힌 각도 (0~360). 오른쪽 반은 0~180, 왼쪽 반은 180~360을 맡는다
				local swept = (1 - remaining) * 360
				overlay.RightGradient.Rotation = math.clamp(swept, 0, 180)
				overlay.LeftGradient.Rotation = math.clamp(swept, 180, 360)
			end
		end
	end
end

-- 클라이언트 시작 시 한 번 호출
function CooldownController.init()
	Remotes.get(Remotes.Names.ItemCooldown).OnClientEvent:Connect(function(itemId: string, seconds: number)
		durations[itemId] = seconds
		endsAt[itemId] = os.clock() + seconds
	end)
	RunService.RenderStepped:Connect(update)
end

return CooldownController
