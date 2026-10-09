--!strict
-- 마을 NPC. Studio에서 배치한 NPC 모델(태그 "ShopNPC", 속성 ShopId)에 이름표와 ProximityPrompt를 붙이고 자세를 잡는다.
-- 망치질·고개 돌리기 같은 움직임은 클라이언트 NpcAnimator가 한다.
-- 프롬프트를 누르면 클라이언트가 그 상점 UI를 연다 (ProximityPrompt의 ShopId 속성으로 구분).
-- 상점 요청이 오면 서버는 그 NPC 근처에 있는지 다시 확인한다.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ShopDefs = require(ReplicatedStorage.Shared.ShopDefs)

local NPC_TAG = "ShopNPC"

local NpcService = {}

-- NPC 모델의 위치 기준 파트
local function rootOf(npc: Model): BasePart?
	local root = npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart or npc:FindFirstChildWhichIsA("BasePart")
	return if root and root:IsA("BasePart") then root else nil
end

-- 몸을 움직일 수 있게 한다: 뿌리(HumanoidRootPart)만 고정하고 나머지는 관절로 붙어 있게
-- 속성 Pose = "Sit"이면 앉은 자세 (다리를 앞으로, 몸을 SitDrop만큼 낮춤)
local function preparePose(npc: Model, root: BasePart)
	-- Studio가 땅(Terrain)이나 모델 밖 파트에 자동으로 붙인 용접은 관절을 묶어 버리므로 지운다
	for _, descendant in npc:GetDescendants() do
		if descendant:IsA("JointInstance") and not descendant:IsA("Motor6D") then
			local part0, part1 = descendant.Part0, descendant.Part1
			if not part0 or not part1 or not part0:IsDescendantOf(npc) or not part1:IsDescendantOf(npc) then
				descendant:Destroy()
			end
		end
	end
	for _, descendant in npc:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= root then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.Massless = true
		end
	end
	root.Anchored = true
	if npc:GetAttribute("Pose") == "Sit" then
		-- R6는 다리 관절을 직접 접는다 (R15는 클라이언트가 앉는 애니메이션을 튼다)
		local torso = npc:FindFirstChild("Torso")
		for _, hipName in { "Right Hip", "Left Hip" } do
			local hip = torso and torso:FindFirstChild(hipName)
			if hip and hip:IsA("Motor6D") then
				local side = if hipName == "Right Hip" then 1 else -1
				hip.C0 = hip.C0 * CFrame.Angles(0, 0, side * math.rad(90))
			end
		end
		local drop = npc:GetAttribute("SitDrop")
		if typeof(drop) == "number" then
			root.CFrame -= Vector3.new(0, drop, 0)
		end
	end
end

-- NPC 하나에 이름표와 프롬프트를 붙인다
local function setupNpc(npc: Instance)
	if not npc:IsA("Model") then
		return
	end
	local shopId = npc:GetAttribute("ShopId")
	local shop = if typeof(shopId) == "string" then ShopDefs[shopId] else nil
	local root = rootOf(npc)
	if not shop or not root then
		warn(`[NpcService] ShopId가 없거나 잘못된 NPC: {npc:GetFullName()}`)
		return
	end

	preparePose(npc, root)

	-- 머리 위 이름표
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NameTag"
	billboard.Size = UDim2.new(6, 0, 1.4, 0)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 80
	billboard.LightInfluence = 0
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.55)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 230, 140)
	title.Text = shop.NpcName
	title.Parent = billboard
	local subtitle = title:Clone()
	subtitle.Position = UDim2.fromScale(0, 0.55)
	subtitle.Size = UDim2.fromScale(1, 0.45)
	subtitle.TextColor3 = Color3.new(1, 1, 1)
	subtitle.Text = shop.Role
	subtitle.Parent = billboard
	for _, label in { title, subtitle } do
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Parent = label
	end
	billboard.Parent = root

	-- 대화 프롬프트
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "대화"
	prompt.ObjectText = shop.NpcName
	prompt.MaxActivationDistance = Config.Npc.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("ShopId", shopId)
	prompt.Parent = root
end

-- 서버 시작 시 한 번 호출
function NpcService.init()
	for _, npc in CollectionService:GetTagged(NPC_TAG) do
		setupNpc(npc)
	end
	CollectionService:GetInstanceAddedSignal(NPC_TAG):Connect(setupNpc)
end

-- 플레이어가 그 상점 NPC 근처에 있는지 (상점 요청 검증용)
function NpcService.isNear(player: Player, shopId: string): boolean
	local character = player.Character
	local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
	if not playerRoot or not playerRoot:IsA("BasePart") then
		return false
	end
	for _, npc in CollectionService:GetTagged(NPC_TAG) do
		if npc:IsA("Model") and npc:GetAttribute("ShopId") == shopId then
			local root = rootOf(npc)
			if root and (root.Position - playerRoot.Position).Magnitude <= Config.Npc.InteractDistance then
				return true
			end
		end
	end
	return false
end

return NpcService
