--!strict
-- 주인 정하기: 바위·나무·몹에 먼저 데미지를 준 사람이 주인이 된다 (2026-10-09 사용자 요청)
-- 주인이 있는 동안 다른 사람은 칠 수 없고, 보상(떨어지는 조각)도 주인 몫만 생긴다
-- 주인이 Config.Ownership.HoldTime초 동안 안 치거나 게임을 나가면 풀린다
-- 모델 속성 OwnerId(주인 UserId)로 모두에게 알린다. 클라이언트는 남의 것을 조준에서 빼고 자물쇠를 띄운다

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local NotifyService = require(script.Parent.NotifyService)

-- 주인 정보를 가진 상태 (RockState·MobState가 이 두 칸을 가진다)
export type Owned = {
	Owner: number?, -- 주인 UserId
	OwnerAt: number, -- 주인이 마지막으로 친 시각 (os.clock)
}

local OwnershipService = {}

local lastNotice: { [Player]: number } = {}

-- 주인이 아직 유효한가
local function isHeld(owned: Owned, now: number): boolean
	local owner = owned.Owner
	return owner ~= nil and now - owned.OwnerAt < Config.Ownership.HoldTime and Players:GetPlayerByUserId(owner) ~= nil
end

-- 이 플레이어가 칠 수 있는가 (다른 사람이 주인이면 false)
function OwnershipService.canHit(owned: Owned, player: Player): boolean
	return owned.Owner == player.UserId or not isHeld(owned, os.clock())
end

-- 주인이 따로 있으면 그 UserId (없거나 풀렸으면 nil)
function OwnershipService.ownerOf(owned: Owned): number?
	return if isHeld(owned, os.clock()) then owned.Owner else nil
end

-- 데미지를 준 사람을 주인으로 (이미 주인이면 시각만 늘린다)
function OwnershipService.claim(owned: Owned, model: Model, player: Player)
	if owned.Owner ~= player.UserId then
		owned.Owner = player.UserId
		model:SetAttribute("OwnerId", player.UserId)
	end
	owned.OwnerAt = os.clock()
end

-- 주인이 오래 안 쳤거나 나갔으면 푼다 (서비스의 주기 루프에서 부른다)
function OwnershipService.expire(owned: Owned, model: Model, now: number)
	if owned.Owner ~= nil and not isHeld(owned, now) then
		owned.Owner = nil
		model:SetAttribute("OwnerId", nil)
	end
end

-- 남의 것을 치려 할 때 알림 (너무 자주 뜨지 않게)
function OwnershipService.notifyBlocked(player: Player, text: string)
	local now = os.clock()
	if now - (lastNotice[player] or -math.huge) < Config.Ownership.NoticeInterval then
		return
	end
	lastNotice[player] = now
	NotifyService.send(player, text, "bad")
end

Players.PlayerRemoving:Connect(function(player)
	lastNotice[player] = nil
end)

return OwnershipService
