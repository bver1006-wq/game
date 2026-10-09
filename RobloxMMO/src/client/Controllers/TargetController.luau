--!strict
-- 가장 가까운 자원 노드(바위·나무) 자동 조준.
-- 곡괭이를 들고 있으면 바위를, 도끼를 들고 있으면 나무를 먼저 고른다 (맞는 노드가 범위 안에 없을 때만 다른 종류).
-- 실제로 칠 수 있는지는 서버가 다시 확인하므로 여기서는 화면 표시·요청 대상 고르기만 한다.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local OreDefs = require(ReplicatedStorage.Shared.OreDefs)
local PickaxeDefs = require(ReplicatedStorage.Shared.PickaxeDefs)

local ORE_TAG = "OreNode"

local localPlayer = Players.LocalPlayer

local TargetController = {}

-- 손에 든 도구로 캐는 노드 종류 ("Rock" / "Tree"). 도구가 없으면 nil
function TargetController.heldNodeKind(): string?
	local character = localPlayer.Character
	local tool = character and character:FindFirstChildWhichIsA("Tool")
	local id = tool and tool:GetAttribute("PickaxeId")
	local def = if typeof(id) == "string" then PickaxeDefs[id] else nil
	if not def then
		return nil
	end
	return if def.Kind == "Axe" then "Tree" else "Rock"
end

-- 캐릭터에서 range 이내에 있는, 아직 HP가 남은 가장 가까운 노드를 돌려준다
-- 든 도구에 맞는 종류를 먼저 고르고, 없으면 다른 종류 중 가장 가까운 것 (서버가 "도끼로 베어야 해요" 안내)
function TargetController.getNearestRock(range: number): Model?
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end

	local preferKind = TargetController.heldNodeKind()
	local best: Model? = nil
	local bestDistance = range
	local other: Model? = nil
	local otherDistance = range
	for _, instance in CollectionService:GetTagged(ORE_TAG) do
		if instance:IsA("Model") and instance:IsDescendantOf(Workspace) then
			local hp = instance:GetAttribute("Hp")
			if typeof(hp) == "number" and hp > 0 then
				local distance = (instance:GetPivot().Position - root.Position).Magnitude
				local oreType = instance:GetAttribute("OreType")
				local def = if typeof(oreType) == "string" then OreDefs[oreType] else nil
				local matches = preferKind == nil or (def ~= nil and def.Kind == preferKind)
				if matches and distance <= bestDistance then
					best = instance
					bestDistance = distance
				elseif not matches and distance <= otherDistance then
					other = instance
					otherDistance = distance
				end
			end
		end
	end
	return best or other
end

return TargetController
