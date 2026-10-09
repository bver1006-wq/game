--!strict
-- 휘두르기 입력: PC 클릭 / 모바일 공격 버튼 / 패드 R2.
-- 곡괭이·도끼·무기(PickaxeId 속성이 있는 Tool)를 들고 있을 때만 입력을 받는다.
-- 곡괭이·도끼는 가장 가까운 바위·나무를 자동 조준해서 서버에 "이 바위를 이 시각에 휘둘렀다"만 보내고,
-- 무기(칼·활·방망이)는 CombatController가 가장 가까운 몹을 공격한다.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local PickaxeDefs = require(ReplicatedStorage.Shared.PickaxeDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CombatController = require(script.Parent.CombatController)
local FeverController = require(script.Parent.FeverController)
local SwingAnimation = require(script.Parent.SwingAnimation)
local TargetController = require(script.Parent.TargetController)

local ACTION_NAME = "MiningSwing"

local localPlayer = Players.LocalPlayer

local InputController = {}

local swingRemote: RemoteEvent
local lastSwingClock = -math.huge
local bound = false

-- 이 Tool이 곡괭이인지
local function isPickaxe(instance: Instance): boolean
	return instance:IsA("Tool") and instance:GetAttribute("PickaxeId") ~= nil
end

-- 캐릭터가 바위를 바라보게 돌린다 (자동 조준)
local function faceRock(rock: Model)
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local target = rock:GetPivot().Position
	local flatTarget = Vector3.new(target.X, root.Position.Y, target.Z)
	if (flatTarget - root.Position).Magnitude > 0.1 then
		root.CFrame = CFrame.lookAt(root.Position, flatTarget)
	end
end

-- 지금 들고 있는 도구 정의
local function equippedDef(): PickaxeDefs.PickaxeDef?
	local character = localPlayer.Character
	local tool = character and character:FindFirstChildWhichIsA("Tool")
	local id = tool and tool:GetAttribute("PickaxeId")
	return if typeof(id) == "string" then PickaxeDefs[id] else nil
end

-- 한 번 휘두른다. 쿨다운은 서버와 같은 값으로 로컬에서도 막는다
local function swing(isTouch: boolean)
	if FeverController.isActive() then
		return -- 피버 중 입력은 FeverController가 연타로 센다
	end
	local def = equippedDef()
	if def and CombatController.isWeapon(def) then
		CombatController.attack(def)
		return
	end
	local now = os.clock()
	if now - lastSwingClock < Config.Mining.SwingInterval then
		return
	end
	lastSwingClock = now

	local rock = TargetController.getNearestRock(Config.Mining.AutoAimRange)
	if rock then
		faceRock(rock)
	end
	SwingAnimation.play()
	if rock then
		swingRemote:FireServer(rock, Workspace:GetServerTimeNow(), isTouch)
	end
end

-- ContextActionService 콜백
local function onAction(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		local isTouch = input.UserInputType == Enum.UserInputType.Touch
			or (UserInputService.TouchEnabled and not UserInputService.MouseEnabled)
		swing(isTouch)
	end
	return Enum.ContextActionResult.Pass
end

-- 곡괭이를 들면 입력을 연결하고, 내려놓으면 끊는다
local function setBound(shouldBind: boolean)
	if shouldBind == bound then
		return
	end
	bound = shouldBind
	if shouldBind then
		-- 세 번째 인자 true: 모바일에서 화면 공격 버튼을 만든다
		ContextActionService:BindAction(ACTION_NAME, onAction, true, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
		ContextActionService:SetTitle(ACTION_NAME, "공격")
		ContextActionService:SetPosition(ACTION_NAME, UDim2.new(1, -150, 1, -150))
	else
		ContextActionService:UnbindAction(ACTION_NAME)
	end
end

-- 캐릭터에 곡괭이가 들려 있는지 다시 확인한다
local function refresh(character: Model)
	for _, child in character:GetChildren() do
		if isPickaxe(child) then
			setBound(true)
			return
		end
	end
	setBound(false)
end

-- 새 캐릭터의 Tool 장착·해제를 지켜본다
local function onCharacterAdded(character: Model)
	setBound(false)
	character.ChildAdded:Connect(function()
		refresh(character)
	end)
	character.ChildRemoved:Connect(function()
		refresh(character)
	end)
	refresh(character)
end

-- 클라이언트 시작 시 한 번 호출
function InputController.init()
	swingRemote = Remotes.get(Remotes.Names.SwingRequest)
	localPlayer.CharacterAdded:Connect(onCharacterAdded)
	if localPlayer.Character then
		onCharacterAdded(localPlayer.Character)
	end
end

return InputController
