--!strict
-- 휘두르기 입력: PC 클릭 / 모바일 공격 버튼 / 패드 R2.
-- 곡괭이·도끼·무기(PickaxeId 속성이 있는 Tool)를 들고 있을 때만 입력을 받는다.
-- 곡괭이·도끼는 가장 가까운 바위·나무를 자동 조준해서 서버에 "이 바위를 이 시각에 휘둘렀다"만 보내고,
-- 무기(칼·활·방망이)는 CombatController가 가장 가까운 몹을 공격한다.
-- 누르고 있으면 모으고(차징, ChargeController), 놓을 때 휘두른다. 짧게 누르면 그냥 한 번 휘두르기.
-- 모은 정도는 서버가 ChargeStart ~ 휘두르기 요청 사이 시간으로 정한다. 요청을 안 보내게 되면 ChargeCancel을 보낸다.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local PickaxeDefs = require(ReplicatedStorage.Shared.PickaxeDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ChargeController = require(script.Parent.ChargeController)
local CombatController = require(script.Parent.CombatController)
local FeverController = require(script.Parent.FeverController)
local SwingAnimation = require(script.Parent.SwingAnimation)
local TargetController = require(script.Parent.TargetController)

local ACTION_NAME = "MiningSwing"

local localPlayer = Players.LocalPlayer

local InputController = {}

local swingRemote: RemoteEvent
local chargeStartRemote: RemoteEvent
local chargeCancelRemote: RemoteEvent
local pressing = false -- 누르고 있는 중 (모으는 중)
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

-- 한 번 휘두른다 (놓는 순간). charge: 모은 정도 0~1. 서버에 요청을 보냈으면 true
-- 쿨다운은 서버와 같은 값으로 로컬에서도 막는다
local function swing(isTouch: boolean, charge: number, held: number): boolean
	local def = equippedDef()
	if def and CombatController.isWeapon(def) then
		return CombatController.attack(def, charge, held)
	end
	local now = os.clock()
	if now - lastSwingClock < Config.Mining.SwingInterval then
		return false
	end
	lastSwingClock = now

	local rock = TargetController.getNearestRock(Config.Mining.AutoAimRange)
	if rock then
		faceRock(rock)
	end
	SwingAnimation.play()
	if rock then
		swingRemote:FireServer(rock, Workspace:GetServerTimeNow(), isTouch)
		return true
	end
	return false
end

-- 누르기 시작: 모으기 시작
local function press()
	if FeverController.isActive() then
		return -- 피버 중 입력은 FeverController가 연타로 센다
	end
	local def = equippedDef()
	if not def then
		return
	end
	pressing = true
	chargeStartRemote:FireServer()
	ChargeController.start(def)
end

-- 놓기: 모은 만큼 휘두른다
local function release(isTouch: boolean)
	if not pressing then
		return
	end
	pressing = false
	local held, charge = ChargeController.stop()
	if FeverController.isActive() or not swing(isTouch, charge, held) then
		chargeCancelRemote:FireServer() -- 요청을 안 보냈으면 서버의 모으기 기록을 지운다
	end
end

-- 휘두르지 않고 모으기 취소 (도구를 내려놓음 등)
local function cancelPress()
	if pressing then
		pressing = false
		ChargeController.cancel()
		chargeCancelRemote:FireServer()
	end
end

-- ContextActionService 콜백
local function onAction(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local isTouch = input.UserInputType == Enum.UserInputType.Touch
		or (UserInputService.TouchEnabled and not UserInputService.MouseEnabled)
	if state == Enum.UserInputState.Begin then
		press()
	elseif state == Enum.UserInputState.End then
		release(isTouch)
	elseif state == Enum.UserInputState.Cancel then
		cancelPress()
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
		-- 모바일 공격 버튼은 MobileControls가 오른쪽 아래에 크게 만든다 (기본 작은 버튼은 안 씀)
		ContextActionService:BindAction(ACTION_NAME, onAction, false, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	else
		cancelPress()
		ContextActionService:UnbindAction(ACTION_NAME)
	end
end

-- 캐릭터에 곡괭이가 들려 있는지 다시 확인한다
local function refresh(character: Model)
	cancelPress() -- 도구를 바꾸면 모으던 것은 취소
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

-- 도구·무기를 들고 있어서 공격 버튼이 먹는지 (MobileControls가 버튼을 흐리게 할 때 쓴다)
function InputController.canAttack(): boolean
	return bound
end

-- 모바일 공격 버튼을 눌렀다 / 뗐다 (PC 클릭과 똑같이 모으고 휘두른다)
function InputController.pressAttack()
	if bound then
		press()
	end
end
function InputController.releaseAttack()
	release(true)
end

-- 클라이언트 시작 시 한 번 호출
function InputController.init()
	swingRemote = Remotes.get(Remotes.Names.SwingRequest)
	chargeStartRemote = Remotes.get(Remotes.Names.ChargeStart)
	chargeCancelRemote = Remotes.get(Remotes.Names.ChargeCancel)
	localPlayer.CharacterAdded:Connect(onCharacterAdded)
	if localPlayer.Character then
		onCharacterAdded(localPlayer.Character)
	end
end

return InputController
