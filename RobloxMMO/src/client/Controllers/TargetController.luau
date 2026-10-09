--!strict
-- 가장 가까운 바위 자동 조준.
-- 실제로 칠 수 있는지는 서버가 다시 확인하므로 여기서는 화면 표시·요청 대상 고르기만 한다.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ORE_TAG = "OreNode"

local localPlayer = Players.LocalPlayer

local TargetController = {}

-- 캐릭터에서 range 이내에 있는, 아직 HP가 남은 가장 가까운 바위를 돌려준다
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
			if typeof(hp) == "number" and hp > 0 then
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

return TargetController
