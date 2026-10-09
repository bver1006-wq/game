--!strict
-- RemoteEvent 이름 목록과 생성·조회 헬퍼.
-- 서버가 시작할 때 setup()으로 ReplicatedStorage/Remotes 폴더에 만들고,
-- 서버·클라이언트 모두 get()으로 가져다 쓴다. 이름 문자열을 직접 쓰지 말 것.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

local Remotes = {}

-- 사용하는 모든 RemoteEvent 이름
Remotes.Names = table.freeze({
	SwingRequest = "SwingRequest", -- 클라 → 서버: (targetRock, clientTime, isTouch)
	HitEffect = "HitEffect", -- 서버 → 클라: (rock, judgment, hitPosition, attackerUserId, hitTime, ghostDuration, pickaxeTier, special "Lightning"|"Charged"|nil)
	RockBroken = "RockBroken", -- 서버 → 클라: (position, oreType, rewards {[userId 문자열]=개수}, feverBonus)
	FeverStart = "FeverStart", -- 서버 → 피버 발동자: (rock, startTime)
	FeverTap = "FeverTap", -- 클라 → 서버: 연타 1회
	FeverResult = "FeverResult", -- 서버 → 피버 발동자: (rock, bonus, acceptedTaps)
	InventoryChanged = "InventoryChanged", -- 서버 → 클라: ({ Items = {[itemId]=개수}, Gold, Capacity })
	ShopAction = "ShopAction", -- 클라 → 서버: (shopId, action, ...) 판매·제련·곡괭이 구매 요청
	Notify = "Notify", -- 서버 → 클라: (message, kind) 화면 알림 ("good" | "bad" | "info")
	UseItem = "UseItem", -- 클라 → 서버: (itemId) 귀환 주문서 같은 소모품 쓰기
	SetSprint = "SetSprint", -- 클라 → 서버: (on) 달리기 모드 켜기·끄기
	ChargeStart = "ChargeStart", -- 클라 → 서버: () 도구·무기 모으기 시작 (놓을 때 보내는 휘두르기·공격 요청이 끝)
	ChargeCancel = "ChargeCancel", -- 클라 → 서버: () 모으기 취소 (도구를 내려놓음)
	AttackRequest = "AttackRequest", -- 클라 → 서버: (targetMob) 무기로 몹 공격
	CombatEffect = "CombatEffect", -- 서버 → 클라: (mob, damage, isCrit, weaponKind, tier, attackerUserId, fromPosition, hitPosition, charged)
	MobAttack = "MobAttack", -- 서버 → 클라: (mob, targetUserId, damage) 몹이 플레이어를 때렸다
	MobDied = "MobDied", -- 서버 → 클라: (position, mobType, killerUserId, gold, lootId, lootCount)
})

export type RemoteName = typeof(Remotes.Names.SwingRequest)

-- 서버 전용: Remotes 폴더와 RemoteEvent를 전부 만든다. 서버 진입점에서 한 번 호출.
function Remotes.setup()
	assert(RunService:IsServer(), "Remotes.setup()은 서버에서만 호출해야 한다")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for _, name in Remotes.Names do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
end

-- 이름으로 RemoteEvent를 가져온다. 클라이언트는 서버가 만들 때까지 기다린다.
function Remotes.get(name: string): RemoteEvent
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	local remote = folder:WaitForChild(name)
	assert(remote:IsA("RemoteEvent"), `{name}은 RemoteEvent가 아니다`)
	return remote
end

return Remotes
