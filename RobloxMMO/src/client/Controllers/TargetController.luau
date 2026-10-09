--!strict
-- 가장 가까운 바위 자동 조준.
-- 실제로 칠 수 있는지는 서버가 다시 확인하므로 여기서는 화면 표시·요청 대상 고르기만 한다.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local OreDefs = require(ReplicatedStorage.Shared.OreDefs)

local ORE_TAG = "OreNode"

local localPlayer = Players.LocalPlayer

local TargetController = {}

-- 다른 사람이 주인인 바위·나무·몹인가 (서버가 모델 속성 OwnerId로 알려 준다. 남의 것은 조준하지 않는다)
function TargetController.isOthers(model: Instance): boolean
	local ownerId = model:GetAttribute("OwnerId")
	return typeof(ownerId) == "number" and ownerId ~= localPlayer.UserId
end

-- 캐릭터에서 range 이내에 있는, 아직 HP가 남은 가장 가까운 바위를 돌려준다 (남이 캐는 바위는 뺀다)
function TargetController.getNearestRock(range: number): Model?
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end

	local best: Model? = nil
	local bestDistance = range
	for _, instance in CollectionService:GetTagged(ORE_TAG) do
		if instance:IsA("Model") and instance:IsDescendantOf(Workspace) then
			local hp = instance:GetAttribute("Hp")
			if typeof(hp) == "number" and hp > 0 and not TargetController.isOthers(instance) then
				local distance = (instance:GetPivot().Position - root.Position).Magnitude
				if distance <= bestDistance then
					best = instance
					bestDistance = distance
				end
			end
		end
	end
	return best
end

-- 노드 정의 (바위·나무). 모르는 노드면 nil
function TargetController.getDef(rock: Instance): OreDefs.OreDef?
	local oreType = rock:GetAttribute("OreType")
	return if typeof(oreType) == "string" then OreDefs[oreType] else nil
end

-- 연출 기준 위치: 바위는 기준점(가운데), 나무는 밑동 위 HitHeight 높이(줄기 타격 높이)
-- pivot을 주면 그 위치 기준으로 계산한다 (떨림 중에도 원래 위치를 쓰기 위해)
function TargetController.focusPosition(rock: Model, pivot: CFrame?): Vector3
	local base = (pivot or rock:GetPivot()).Position
	local def = TargetController.getDef(rock)
	if def and def.Kind == "Tree" then
		return base + Vector3.new(0, def.HitHeight or 2.5, 0)
	end
	return base
end

-- 나무 줄기 반지름: 템플릿 속성 HitRadius(맵 나무에서 잰 값)가 있으면 그것, 없으면 OreDefs 값
function TargetController.hitRadius(rock: Model): number
	local attribute = rock:GetAttribute("HitRadius")
	if typeof(attribute) == "number" then
		return attribute
	end
	local def = TargetController.getDef(rock)
	return if def and def.HitRadius then def.HitRadius else 1
end

return TargetController
