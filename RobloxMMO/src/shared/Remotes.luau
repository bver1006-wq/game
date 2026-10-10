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
	HitEffect = "HitEffect", -- 서버 → 클라: (rock, judgment, hitPosition, attackerUserId, hitTime, ghostDuration, pickaxeTier, special "Lightning"|"Charged"|"Blocked"|nil)
	RockBroken = "RockBroken", -- 서버 → 클라: (position, oreType, rewards {[userId 문자열]=개수}, feverMultiplier 피버 배수·아니면 1)
	FeverStart = "FeverStart", -- 서버 → 피버 발동자: (rock, startTime)
	FeverTap = "FeverTap", -- 클라 → 서버: 연타 1회
	FeverResult = "FeverResult", -- 서버 → 피버 발동자: (rock, multiplier 보상 배수, acceptedTaps)
	InventoryChanged = "InventoryChanged", -- 서버 → 클라: ({ Items = {[itemId]=개수}, Gold, Capacity })
	ShopAction = "ShopAction", -- 클라 → 서버: (shopId, action, ...) 판매·제련·곡괭이 구매 요청
	Notify = "Notify", -- 서버 → 클라: (message, kind) 화면 알림 ("good" | "bad" | "info")
	UseItem = "UseItem", -- 클라 → 서버: (itemId) 귀환 주문서 같은 소모품 쓰기
	ItemCooldown = "ItemCooldown", -- 서버 → 클라: (itemId, seconds) 이 아이템 쿨타임 시작 (칸 위 시계 방향 덮개)
	SetSprint = "SetSprint", -- 클라 → 서버: (on) 달리기 모드 켜기·끄기
	ChargeStart = "ChargeStart", -- 클라 → 서버: () 도구·무기 모으기 시작 (놓을 때 보내는 휘두르기·공격 요청이 끝)
	ChargeCancel = "ChargeCancel", -- 클라 → 서버: () 모으기 취소 (도구를 내려놓음)
	EquipItem = "EquipItem", -- 클라 → 서버: (itemId) 장비 끼우기 (가방에서 더블클릭)
	UnequipSlot = "UnequipSlot", -- 클라 → 서버: (slot) 장비 빼기
	AttackRequest = "AttackRequest", -- 클라 → 서버: (targetMob) 무기로 몹 공격
	CombatEffect = "CombatEffect", -- 서버 → 클라: (mob, damage, isCrit, weaponKind, tier, attackerUserId, fromPosition, hitPosition, charged, blocked, fromSkill)
	MobAttack = "MobAttack", -- 서버 → 클라: (mob, targetUserId, damage, guarded) 몹이 플레이어를 때렸다 (guarded: 구르기·방패로 피하거나 줄임)
	RollRequest = "RollRequest", -- 클라 → 서버: (direction Vector3) 구르기 (움직임은 클라, 무적·마나·쿨다운은 서버)
	SkillRequest = "SkillRequest", -- 클라 → 서버: (target 몹·바위 Model 또는 nil) 들고 있는 도구·무기 스킬 쓰기
	SkillEffect = "SkillEffect", -- 서버 → 클라: (kind "Roll"|"Block"|"Slam"|"RapidFire"|"PowerStrike", userId, position, data) 스킬 연출·쿨다운 시작
	MobSpecial = "MobSpecial", -- 서버 → 클라: (mob, kind "Ink"|"Puff"|"Arrow"|"Telegraph"|"Impact"|"Cancel", targetUserId, position, data) 몹 특수 연출 (낙지 먹물 2026-10-09 / 궁수 화살·거인 기술 경고·충격 2026-10-10)
	MobDied = "MobDied", -- 서버 → 클라: (position, mobType, killerUserId, gold, lootId, lootCount, extras { {Id, Count} } — 두 번째·보스 전리품, 2026-10-09)
	ReturnHome = "ReturnHome", -- 클라 → 서버: () 마을로 귀환 (다시 누르면 취소)
	SaveHotbar = "SaveHotbar", -- 클라 → 서버: ({ itemId 또는 "" }) 빠른 칸 배치 저장 (들어올 때는 플레이어 속성 SavedHotbar로 돌려받는다)
	DebugShopGrant = "DebugShopGrant", -- 클라 → 서버: (shopId, itemId) TODO(임시): Studio 테스트용, 상점 아이콘 3번 누르면 공짜 지급 (Config.Debug.ShopTripleClickFree)
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
