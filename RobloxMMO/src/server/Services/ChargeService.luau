--!strict
-- 차징(모으기) 기록. 클라이언트가 누르기 시작하면 ChargeStart를 보내고, 놓을 때 휘두르기·공격 요청을 보낸다.
-- 얼마나 모았는지는 서버가 두 요청 사이 시간으로 계산한다 (클라이언트가 보낸 값을 믿지 않는다).
-- 모으는 동안은 플레이어 속성 Charging = true (ManaService가 걷기 속도를 늦춘다).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local ChargeService = {}

local started: { [Player]: number } = {}

local function stop(player: Player)
	started[player] = nil
	player:SetAttribute("Charging", false)
end

-- 모은 정도(0~1)를 꺼내고 기록을 지운다. 휘두르기·공격을 처리할 때 한 번 부른다
function ChargeService.consume(player: Player): number
	local start = started[player]
	stop(player)
	if not start then
		return 0
	end
	local held = os.clock() - start
	if held > Config.Charge.MaxHold + Config.Charge.Time then
		return 1 -- 아주 오래 누르고 있었어도 다 모은 것
	end
	if held < Config.Charge.TapThreshold then
		return 0
	end
	return math.clamp(held / Config.Charge.Time, 0, 1)
end

-- 서버 시작 시 한 번 호출
function ChargeService.init()
	Remotes.get(Remotes.Names.ChargeStart).OnServerEvent:Connect(function(player)
		started[player] = os.clock()
		player:SetAttribute("Charging", true)
	end)
	Remotes.get(Remotes.Names.ChargeCancel).OnServerEvent:Connect(stop)
	Players.PlayerRemoving:Connect(function(player)
		started[player] = nil
	end)
	-- 안전장치: 요청 없이 너무 오래 모으는 중이면(연결 끊김 등) 느린 걸음을 푼다
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for player, start in started do
				if now - start > 30 then
					stop(player)
				end
			end
		end
	end)
end

return ChargeService
