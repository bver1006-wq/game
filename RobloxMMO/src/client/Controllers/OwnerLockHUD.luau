--!strict
-- 다른 사람이 주인인 바위·나무·몹 위에 "🔒 이름" 표시를 띄운다 (2026-10-09 사용자 요청)
-- 주인은 서버가 모델 속성 OwnerId로 알려 준다. 내 것이나 주인 없는 것에는 아무것도 안 띄운다

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local TargetController = require(script.Parent.TargetController)

local localPlayer = Players.LocalPlayer

local TAGS = { "OreNode", "Mob" }
local UPDATE_INTERVAL = 0.25

type Lock = { Anchor: Attachment, Gui: BillboardGui, Label: TextLabel }

local OwnerLockHUD = {}

local locks: { [Model]: Lock } = {}
local guiFolder: Folder

-- 표시 위치: 몹은 이름·체력바 위, 나무는 줄기 타격 높이 위, 바위는 꼭대기 위
local function lockPosition(model: Model): Vector3
	local size = model:GetExtentsSize()
	if CollectionService:HasTag(model, "Mob") then
		return model:GetPivot().Position + Vector3.new(0, math.max(size.Y, 2) + 2.2, 0)
	end
	local def = TargetController.getDef(model)
	if def and def.Kind == "Tree" then
		return TargetController.focusPosition(model) + Vector3.new(0, 3.5, 0)
	end
	return model:GetPivot().Position + Vector3.new(0, size.Y / 2 + 1.2, 0)
end

local function ownerName(model: Model): string
	local ownerId = model:GetAttribute("OwnerId")
	local owner = if typeof(ownerId) == "number" then Players:GetPlayerByUserId(ownerId) else nil
	return if owner then owner.DisplayName else "다른 사람"
end

local function createLock(model: Model): Lock
	local anchor = Instance.new("Attachment")
	anchor.Parent = Workspace.Terrain

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(6, 0, 0.8, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = Config.Ownership.LockShowRange
	gui.Adornee = anchor
	gui.Parent = guiFolder

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(200, 200, 210)
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Parent = label

	return { Anchor = anchor, Gui = gui, Label = label }
end

local function removeLock(model: Model)
	local lock = locks[model]
	if lock then
		lock.Gui:Destroy()
		lock.Anchor:Destroy()
		locks[model] = nil
	end
end

-- 가까운 노드·몹을 훑어 자물쇠를 붙이거나 뗀다
local function update()
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local rootPosition = if root and root:IsA("BasePart") then root.Position else nil
	local seen: { [Model]: boolean } = {}
	if rootPosition then
		for _, tag in TAGS do
			for _, instance in CollectionService:GetTagged(tag) do
				if instance:IsA("Model") and instance:IsDescendantOf(Workspace) and TargetController.isOthers(instance) then
					local position = lockPosition(instance)
					if (position - rootPosition).Magnitude <= Config.Ownership.LockShowRange then
						seen[instance] = true
						local lock = locks[instance] or createLock(instance)
						locks[instance] = lock
						lock.Anchor.WorldPosition = position
						lock.Label.Text = `🔒 {ownerName(instance)}`
					end
				end
			end
		end
	end
	for model in locks do
		if not seen[model] then
			removeLock(model)
		end
	end
end

-- 클라이언트 시작 시 한 번 호출
function OwnerLockHUD.init()
	local folder = Instance.new("Folder")
	folder.Name = "ClientOwnerLocks"
	-- 리스폰 때 PlayerGui가 초기화되지 않게 Workspace 아래 로컬 폴더에 둔다 (위치는 Adornee로 정한다)
	folder.Parent = Workspace
	guiFolder = folder
	task.spawn(function()
		while true do
			update()
			task.wait(UPDATE_INTERVAL)
		end
	end)
end

return OwnerLockHUD
