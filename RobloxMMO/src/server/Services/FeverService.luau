--!strict
-- 피버: 바위를 깨는 마지막 일격에서 확률로 발동한다.
-- 멈춤 → 회전 → "FEVER!" → 연타 → 폭발 순서로 진행되고, 연타 구간의 탭 수로 보너스 개수(+1~+5)를 정한다.
-- 탭 수는 서버가 직접 센다 (초당 MaxTapsPerSecond까지만 인정).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

-- 진행 중인 피버 하나
type FeverSession = {
	Rock: Model,
	TapStart: number, -- 연타 구간 시작 (서버 시각)
	TapEnd: number,
	Taps: number, -- 인정된 탭 수
	Tokens: number, -- 남은 탭 허용량 (초당 MaxTapsPerSecond씩 차오른다)
	LastRefill: number,
	ForceField: ForceField?,
}

local FeverService = {}

local sessions: { [Player]: FeverSession } = {}
local random = Random.new()

-- 탭 수에 맞는 보상 배수를 고른다
local function multiplierFor(taps: number): number
	for _, tier in Config.Fever.Tiers do
		if taps >= tier.MinTaps then
			return tier.Multiplier
		end
	end
	return 1
end

-- 연타 1회를 받는다. 구간 밖이거나 초당 한도를 넘으면 무시한다
local function onTap(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local tolerance = Config.Fever.TapLatencyTolerance
	if now < session.TapStart - tolerance or now > session.TapEnd + tolerance then
		return
	end

	-- 토큰 버킷: 초당 MaxTapsPerSecond개씩 차오르고 최대 TapBurstAllowance개까지 쌓인다
	local rate = Config.Fever.MaxTapsPerSecond
	if now > session.LastRefill then
		session.Tokens = math.min(session.Tokens + (now - session.LastRefill) * rate, Config.Fever.TapBurstAllowance)
		session.LastRefill = now
	end
	if session.Tokens < 1 then
		return
	end
	session.Tokens -= 1
	session.Taps += 1
end

-- 서버 시작 시 한 번 호출
function FeverService.init()
	Remotes.get(Remotes.Names.FeverTap).OnServerEvent:Connect(onTap)
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
end

-- 피버가 발동할지 굴린다
function FeverService.roll(): boolean
	return random:NextNumber() < Config.Fever.Chance
end

-- 이 플레이어가 피버 중인지
function FeverService.isActive(player: Player): boolean
	return sessions[player] ~= nil
end

-- 피버를 시작한다. 끝나면 onFinish(보너스 개수)를 부른다 (플레이어가 나가도 그때까지 센 탭으로 부른다)
function FeverService.start(player: Player, rock: Model, onFinish: (multiplier: number) -> ())
	local fever = Config.Fever
	local startTime = Workspace:GetServerTimeNow()
	local tapStart = startTime + fever.FreezeDuration + fever.OrbitDuration + fever.TitleDuration
	local tapEnd = tapStart + fever.TapDuration

	-- 피버 중 캐릭터는 무적 (보이지 않는 ForceField)
	local forceField: ForceField? = nil
	if player.Character then
		local ff = Instance.new("ForceField")
		ff.Visible = false
		ff.Parent = player.Character
		forceField = ff
	end

	local session: FeverSession = {
		Rock = rock,
		TapStart = tapStart,
		TapEnd = tapEnd,
		Taps = 0,
		Tokens = 1, -- 첫 탭은 바로 인정
		LastRefill = tapStart - fever.TapLatencyTolerance,
		ForceField = forceField,
	}
	sessions[player] = session

	Remotes.get(Remotes.Names.FeverStart):FireClient(player, rock, startTime)

	-- 연타 구간이 끝나고 지연 허용치만큼 기다린 뒤 결과를 낸다
	task.delay(tapEnd + fever.TapLatencyTolerance - startTime, function()
		local multiplier = multiplierFor(session.Taps)
		if sessions[player] == session then
			sessions[player] = nil
		end
		if session.ForceField then
			session.ForceField:Destroy()
		end
		if player.Parent then
			Remotes.get(Remotes.Names.FeverResult):FireClient(player, rock, multiplier, session.Taps)
		end
		print(`[FeverService] {player.Name} 피버 종료: 탭 {session.Taps}회 → x{multiplier}`)
		-- 폭발 연출 시간을 준 뒤 바위를 깨뜨린다
		task.wait(fever.BurstDuration)
		onFinish(multiplier)
	end)
end

return FeverService
