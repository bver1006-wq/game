--!strict
-- 휘두르기 요청의 기본 검증: 쿨다운, 거리.
-- 매크로 탐지(간격이 기계처럼 일정한지)는 MVP-1에서 추가한다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local AntiCheatService = {}

local lastSwing: { [Player]: number } = {} -- 플레이어별 마지막으로 인정한 휘두르기 시각 (os.clock)

-- 서버 시작 시 한 번 호출
function AntiCheatService.init()
	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player] = nil
	end)
end

-- 쿨다운이 지났는지 확인하고, 지났으면 이번 휘두르기를 기록한다
function AntiCheatService.tryConsumeSwing(player: Player): boolean
	local now = os.clock()
	local last = lastSwing[player]
	local minInterval = Config.Mining.SwingInterval - Config.Mining.CooldownTolerance
	if last and now - last < minInterval then
		return false
	end
	lastSwing[player] = now
	return true
end

-- 캐릭터가 바위에 휘두를 수 있는 거리 안에 있는지 확인한다
function AntiCheatService.isInRange(player: Player, rockPosition: Vector3, extraReach: number?): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	return (root.Position - rockPosition).Magnitude <= Config.Mining.MaxSwingDistance + (extraReach or 0)
end

return AntiCheatService
