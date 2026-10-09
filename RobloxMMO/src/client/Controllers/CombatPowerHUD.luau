--!strict
-- 머리 위 전투력 표시 (모든 플레이어). 값은 서버 EquipmentService가 정한 플레이어 속성 CombatPower (착용 장비 합산).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local CombatPowerHUD = {}

local folder: Folder

-- 캐릭터 머리 위에 전투력 표시를 붙인다
local function attach(player: Player, character: Model)
	local head = character:WaitForChild("Head", 10)
	if not head or not head:IsA("BasePart") or not character.Parent then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = `CombatPower_{player.UserId}`
	billboard.Size = UDim2.fromOffset(160, 26)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.3, 0) -- Roblox 이름표보다 위
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 80
	billboard.Adornee = head
	billboard.Parent = folder

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 18
	label.TextColor3 = Color3.fromRGB(255, 215, 90)
	label.Parent = billboard
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(60, 35, 0)
	stroke.Parent = label

	local function render()
		local power = player:GetAttribute("CombatPower")
		label.Text = `⚔ 전투력 {if typeof(power) == "number" then power else 0}`
	end
	render()
	local connection = player:GetAttributeChangedSignal("CombatPower"):Connect(render)
	character.AncestryChanged:Connect(function()
		if not character.Parent then
			connection:Disconnect()
			billboard:Destroy()
		end
	end)
end

local function watch(player: Player)
	player.CharacterAdded:Connect(function(character)
		attach(player, character)
	end)
	if player.Character then
		task.spawn(attach, player, player.Character)
	end
end

-- 클라이언트 시작 시 한 번 호출
function CombatPowerHUD.init()
	folder = Instance.new("Folder")
	folder.Name = "ClientCombatPower"
	folder.Parent = Workspace
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return CombatPowerHUD
