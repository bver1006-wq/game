--!strict
-- 단계(티어) 공통 정보: 이름·색·별 표시 (2026-10-09, 5·6단계 미스릴·오리하르콘 추가 때 만듦)
-- 단계 수는 이 목록 길이로 정해진다. 8~9단계(운석철·용뼈)를 더할 때는 여기에 한 줄씩 더하고
-- PickaxeDefs·EquipmentDefs·Config(Pickaxes·Weapons·Equipment.TierMultiplier·Recipes·HitFeel·Combat.TierEffects·GearVisual.HighTiers)에 데이터만 더하면 된다.
-- 단계별 표(효과·배수)에 그 단계 값이 없으면 pick이 가장 가까운 아래 단계 값을 대신 쓴다.

export type TierInfo = {
	Id: string,
	Name: string, -- 재질 이름 (UI 표시)
	Color: Color3, -- 장비 몸통 색 (EquipmentDefs.Color)
	TextColor: Color3, -- 아이템 이름 글자 색 (상세 창)
}

local TIERS: { TierInfo } = {
	{ Id = "Basic", Name = "가죽·뼈·나무", Color = Color3.fromRGB(140, 95, 60), TextColor = Color3.fromRGB(215, 175, 130) },
	{ Id = "Copper", Name = "구리", Color = Color3.fromRGB(205, 115, 60), TextColor = Color3.fromRGB(240, 150, 90) },
	{ Id = "Iron", Name = "철", Color = Color3.fromRGB(175, 178, 188), TextColor = Color3.fromRGB(215, 220, 235) },
	{ Id = "Diamond", Name = "다이아몬드", Color = Color3.fromRGB(110, 220, 255), TextColor = Color3.fromRGB(120, 230, 255) },
	{ Id = "Mithril", Name = "미스릴", Color = Color3.fromRGB(175, 200, 235), TextColor = Color3.fromRGB(140, 185, 255) }, -- 은빛 파랑, 가볍고 날렵
	{ Id = "Orichalcum", Name = "오리하르콘", Color = Color3.fromRGB(240, 180, 55), TextColor = Color3.fromRGB(255, 190, 60) }, -- 금빛, 묵직하고 화려
	-- 7단계 (2026-10-10): 지금은 방어구(헬멧·갑옷·신발·장갑) 베헤모스 세트만 있다. 도구·무기·장신구는 6단계까지
	{ Id = "Legend", Name = "전설", Color = Color3.fromRGB(150, 25, 60), TextColor = Color3.fromRGB(255, 90, 130) }, -- 짙은 진홍
	-- 나중에: 8 운석철 / 9 용뼈
}

local TierDefs = {}

TierDefs.List = table.freeze(TIERS)
TierDefs.Max = #TIERS -- 지금 있는 가장 높은 단계

-- 단계 정보 (범위를 벗어나면 가까운 끝 단계)
function TierDefs.get(tier: number): TierInfo
	return TIERS[math.clamp(math.floor(tier), 1, #TIERS)]
end

-- 별 글자 ("★★☆☆☆☆"). 칸 수 = 지금 있는 단계 수
function TierDefs.stars(tier: number): string
	local filled = math.clamp(math.floor(tier), 0, #TIERS)
	return string.rep("★", filled) .. string.rep("☆", #TIERS - filled)
end

-- 단계별 표에서 그 단계 값을 고른다. 없으면 그보다 낮은 단계 중 가장 높은 값 (새 단계를 더해도 표가 모자라 깨지지 않게)
-- 더 낮은 값도 없으면 nil
function TierDefs.pick<T>(values: { [number]: T }, tier: number): T?
	local exact = values[tier]
	if exact ~= nil then
		return exact
	end
	local best: T? = nil
	local bestTier = -math.huge
	for key, value in values do
		if key <= tier and key > bestTier then
			best, bestTier = value, key
		end
	end
	return best
end

return table.freeze(TierDefs)
