--!strict
-- 차징 자세 (클라이언트, 내 캐릭터만).
-- 애니메이션 위에 어깨·허리 관절(Motor6D C0)을 살짝 돌려 자세를 만든다. 애니메이션은 Transform만 바꾸므로 겹쳐도 된다.
--   windUp: 무기를 머리 위 뒤로 들어 올리고 상체를 살짝 젖힌다 (놓으면 휘두르기 애니메이션과 함께 원래대로 내려온다)
--   bowDraw: 왼손을 앞으로 뻗어 시위를 잡고, 시위가 뒤로 당겨지며 화살이 걸린다. 놓으면 시위가 튕겨 돌아온다
-- 관절 바꾼 값은 다른 플레이어에게는 보이지 않는다 (연출용)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local localPlayer = Players.LocalPlayer

local PoseController = {}

type Joint = { Motor: Motor6D, Base: CFrame, Target: CFrame, Current: CFrame }

local joints: { [string]: Joint } = {}
local jointCharacter: Model? = nil
local blendSpeed = 12 -- 자세로 옮겨 가는 빠르기
local bow: {
	Tool: Tool,
	String: BasePart,
	Upper: BasePart,
	Lower: BasePart,
	Arrow: BasePart,
	Draw: number, -- 0~1 지금 당긴 정도
	Target: number,
}? = nil

-- 캐릭터 관절 찾기 (R15·R6)
local function findJoints(): { [string]: Motor6D }
	local character = localPlayer.Character
	local found: { [string]: Motor6D } = {}
	if not character then
		return found
	end
	local function pick(name: string, parentName: string, motorName: string)
		local parent = character:FindFirstChild(parentName)
		local motor = parent and parent:FindFirstChild(motorName)
		if motor and motor:IsA("Motor6D") then
			found[name] = motor
		end
	end
	pick("Right", "RightUpperArm", "RightShoulder")
	pick("Left", "LeftUpperArm", "LeftShoulder")
	pick("Waist", "UpperTorso", "Waist")
	if not found.Right then -- R6
		pick("Right", "Torso", "Right Shoulder")
		pick("Left", "Torso", "Left Shoulder")
	end
	return found
end

-- 관절 하나의 목표 자세를 정한다 (offset = 기본 C0에 곱할 회전, nil이면 기본으로)
local function setJoint(name: string, offset: CFrame?)
	local character = localPlayer.Character
	if character ~= jointCharacter then
		joints = {}
		jointCharacter = character
	end
	local joint = joints[name]
	if not joint then
		local motor = findJoints()[name]
		if not motor then
			return
		end
		joint = { Motor = motor, Base = motor.C0, Target = motor.C0, Current = motor.C0 }
		joints[name] = joint
	end
	joint.Target = if offset then joint.Base * offset else joint.Base
end

local function isR6(): boolean
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R6
end

-- 무기를 머리 위 뒤로 들어 올린다
function PoseController.windUp()
	blendSpeed = 10
	if isR6() then
		setJoint("Right", CFrame.Angles(0, 0, math.rad(115)))
	else
		setJoint("Right", CFrame.Angles(math.rad(115), 0, 0))
		setJoint("Waist", CFrame.Angles(math.rad(-12), 0, 0)) -- 상체를 살짝 뒤로
	end
end

-- 얇은 원통 부품 (시위·화살, 이 클라이언트에만)
local function localRod(name: string, diameter: number, color: Color3, material: Enum.Material): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(1, diameter, diameter)
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = Workspace
	return p
end

-- 두 점 사이에 원통을 놓는다
local function placeRod(rod: BasePart, a: Vector3, b: Vector3)
	local length = (b - a).Magnitude
	rod.Size = Vector3.new(math.max(length, 0.01), rod.Size.Y, rod.Size.Z)
	rod.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
end

-- 활 당기기 시작: 왼손을 앞으로 뻗고, 시위를 둘로 나눠 뒤로 당기고, 화살을 건다
function PoseController.bowDraw(tool: Tool)
	PoseController.release()
	local stringPart = tool:FindFirstChild("String", true)
	if not stringPart or not stringPart:IsA("BasePart") then
		return
	end
	blendSpeed = 14
	if isR6() then
		setJoint("Left", CFrame.Angles(0, 0, math.rad(-85)))
	else
		setJoint("Left", CFrame.Angles(math.rad(85), 0, math.rad(30))) -- 앞으로, 몸 안쪽으로
	end
	stringPart.LocalTransparencyModifier = 1
	bow = {
		Tool = tool,
		String = stringPart,
		Upper = localRod("DrawStringUpper", 0.04, stringPart.Color, Enum.Material.SmoothPlastic),
		Lower = localRod("DrawStringLower", 0.04, stringPart.Color, Enum.Material.SmoothPlastic),
		Arrow = localRod("NockedArrow", 0.1, Color3.fromRGB(150, 110, 70), Enum.Material.Wood),
		Draw = 0,
		Target = 1,
	}
end

-- 자세를 푼다. 활이면 시위가 튕겨 돌아온다
function PoseController.release()
	blendSpeed = 16
	for name in joints do
		setJoint(name, nil)
	end
	local current = bow
	if current then
		bow = nil
		current.Upper:Destroy()
		current.Lower:Destroy()
		current.Arrow:Destroy()
		if current.String.Parent then
			current.String.LocalTransparencyModifier = 0
		end
	end
end

-- 매 프레임: 관절을 목표 자세로 부드럽게, 시위·화살 위치 갱신
local function update(dt: number)
	local alpha = math.clamp(dt * blendSpeed, 0, 1)
	for name, joint in joints do
		if not joint.Motor.Parent then
			joints[name] = nil
		else
			joint.Current = joint.Current:Lerp(joint.Target, alpha)
			joint.Motor.C0 = joint.Current
		end
	end

	local current = bow
	if current then
		if not current.String.Parent or not current.Tool.Parent then
			PoseController.release()
			return
		end
		-- 모으는 시간 동안 끝까지 당긴다
		current.Draw = math.min(current.Draw + dt / Config.Charge.Time, current.Target)
		local cf = current.String.CFrame
		local half = current.String.Size.X / 2
		local top = cf:PointToWorldSpace(Vector3.new(half, 0, 0))
		local bottom = cf:PointToWorldSpace(Vector3.new(-half, 0, 0))
		local middle = (top + bottom) / 2
		-- 당기는 방향: 활 손잡이(가운데)에서 시위 쪽으로
		local handle = current.Tool:FindFirstChild("Handle")
		local grip = if handle and handle:IsA("BasePart") then handle.CFrame:PointToWorldSpace(current.Tool.Grip.Position) else middle
		local back = middle - grip
		back = if back.Magnitude > 0.01 then back.Unit else -cf.LookVector
		local pull = middle + back * (0.25 + current.Draw * 1.1)
		placeRod(current.Upper, top, pull)
		placeRod(current.Lower, bottom, pull)
		placeRod(current.Arrow, pull, pull - back * 2.2)
	end
end

-- 클라이언트 시작 시 한 번 호출
function PoseController.init()
	RunService.RenderStepped:Connect(update)
	localPlayer.CharacterAdded:Connect(function()
		joints = {}
		PoseController.release()
	end)
end

return PoseController
