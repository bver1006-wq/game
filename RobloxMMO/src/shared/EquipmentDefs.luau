--!strict
-- 장비 칸과 장비 아이템 정의 (이름·칸·단계·색). 능력치·가격 수치는 Config.Equipment에 있다.
-- 칸: 무기(손에 든 도구·무기) / 방패 / 헬멧 / 갑옷 / 신발 / 장갑 / 목걸이 / 팔찌
-- 무기 칸은 따로 끼우지 않고 지금 손에 든 도구·무기가 들어간다.
-- 방패 칸에는 방패 또는 화살통 하나가 들어간다 (활을 쏘려면 화살이 든 화살통이 필요. 화살 수는 Config.Quiver).
--   방패(2026-10-10): 한손 무기(칼·방망이)와 같이 쓴다. 활(두 손)을 들면 숨고 능력치도 빠진다 (Config.Shield)
-- 장비 아이템은 ItemDefs에도 등록된다 (분류 "방어구", 화살통은 "무기").
-- 단계 색·이름은 TierDefs. 단계 수를 가정하지 않으니 장신구 7단계부터는 NAMES 각 줄에, 방어구는 ARMOR_SETS에 하나씩 더하면 된다

local TierDefs = require(script.Parent.TierDefs)

export type Slot = "Weapon" | "Shield" | "Helmet" | "Armor" | "Boots" | "Gloves" | "Necklace" | "Bracelet"

export type EquipmentDef = {
	Id: string,
	DisplayName: string,
	Slot: Slot,
	Tier: number,
	Color: Color3,
	Set: string?, -- 방어구 세트 Id (Leather·Bone·Cerberus·Cyclops·Golem·Frost·Behemoth). 방패도 세트 모양. 장신구·화살통은 nil
	Quiver: boolean?, -- 화살통이면 true (방패 칸이지만 능력치 없음, 화살 수는 Config.Quiver)
}

-- 칸 순서와 이름
local SLOTS: { { Id: Slot, Title: string } } = {
	{ Id = "Weapon", Title = "무기" },
	{ Id = "Shield", Title = "방패" },
	{ Id = "Helmet", Title = "헬멧" },
	{ Id = "Armor", Title = "갑옷" },
	{ Id = "Boots", Title = "신발" },
	{ Id = "Gloves", Title = "장갑" },
	{ Id = "Necklace", Title = "목걸이" },
	{ Id = "Bracelet", Title = "팔찌" },
}

-- 칸마다 단계별 (Id, 이름). 단계 = 목록 순서
-- 장신구(목걸이·팔찌)는 광물 단계 (1 뼈·나무 / 2 구리 / 3 철 / 4 다이아몬드 / 5 미스릴 / 6 오리하르콘)
-- 방어구(헬멧·갑옷·신발·장갑)는 2026-10-10부터 몹 세트 (ARMOR_SETS 순서 = 단계 1~7, 재료는 Config.Recipes, 겉모습은 GearVisualService)
local NAMES: { [string]: { { string } } } = {
	Necklace = { { "BoneNecklace", "뼈 목걸이" }, { "CopperNecklace", "구리 목걸이" }, { "IronNecklace", "철 목걸이" }, { "DiamondNecklace", "다이아몬드 목걸이" }, { "MithrilNecklace", "미스릴 목걸이" }, { "OrichalcumNecklace", "오리하르콘 목걸이" } },
	Bracelet = { { "WoodBracelet", "나무 팔찌" }, { "CopperBracelet", "구리 팔찌" }, { "IronBracelet", "철 팔찌" }, { "DiamondBracelet", "다이아몬드 팔찌" }, { "MithrilBracelet", "미스릴 팔찌" }, { "OrichalcumBracelet", "오리하르콘 팔찌" } },
}

-- 방어구 세트 (2026-10-10 사용자 요청: 잡은 몹 재료로 만들고, 겉에서 봐도 어떤 세트인지 딱 알아보게)
-- Id 앞부분 + 칸 이름이 아이템 Id (예: Bone + Helmet = BoneHelmet). Color = 아이콘·가방 대신 색 (세트 주 재질 색)
-- 1 가죽(슬라임) / 2 뼈(스켈레톤) / 3 케르베로스 털가죽 / 4 사이클롭스 거대가죽 / 5 바위 골렘 / 6 서리 거인 / 7 베헤모스
type ArmorSet = { Id: string, Color: Color3, Names: { [string]: string } }
local ARMOR_SETS: { ArmorSet } = {
	{ Id = "Leather", Color = Color3.fromRGB(140, 95, 60), Names = { Helmet = "가죽 모자", Armor = "가죽 갑옷", Boots = "가죽 장화", Gloves = "가죽 장갑" } },
	{ Id = "Bone", Color = Color3.fromRGB(235, 228, 205), Names = { Helmet = "해골 투구", Armor = "갈비뼈 갑옷", Boots = "뼈 정강이 장화", Gloves = "뼈마디 장갑" } },
	{ Id = "Cerberus", Color = Color3.fromRGB(70, 52, 60), Names = { Helmet = "케르베로스 늑대 두건", Armor = "케르베로스 가죽갑옷", Boots = "케르베로스 털장화", Gloves = "케르베로스 발톱 장갑" } },
	{ Id = "Cyclops", Color = Color3.fromRGB(150, 138, 92), Names = { Helmet = "사이클롭스 외눈 투구", Armor = "사이클롭스 거대가죽갑옷", Boots = "거대가죽 장화", Gloves = "거대가죽 장갑" } },
	{ Id = "Golem", Color = Color3.fromRGB(122, 116, 108), Names = { Helmet = "바위 골렘 투구", Armor = "바위 골렘 갑옷", Boots = "바위 골렘 장화", Gloves = "바위 골렘 주먹" } },
	{ Id = "Frost", Color = Color3.fromRGB(232, 240, 250), Names = { Helmet = "서리 거인 투구", Armor = "서리 거인 갑옷", Boots = "서리 거인 장화", Gloves = "서리 거인 장갑" } },
	{ Id = "Behemoth", Color = Color3.fromRGB(125, 26, 32), Names = { Helmet = "베헤모스 뿔 투구", Armor = "베헤모스 비늘 갑옷", Boots = "베헤모스 장화", Gloves = "베헤모스 발톱 장갑" } },
}
local ARMOR_SLOTS = { Helmet = true, Armor = true, Boots = true, Gloves = true }

-- 예전 금속 방어구 Id → 같은 단계의 새 세트 Id (저장 불러올 때 바꿔 준다, InventoryService·EquipmentService·DataService)
local RENAMED: { [string]: string } = {}
for tier, metal in { [2] = "Copper", [3] = "Iron", [4] = "Diamond", [5] = "Mithril", [6] = "Orichalcum" } do
	for slot in ARMOR_SLOTS do
		RENAMED[metal .. slot] = ARMOR_SETS[tier].Id .. slot
	end
end

local items: { [string]: EquipmentDef } = {}
local order: { string } = {}
for _, slot in SLOTS do
	local list = NAMES[slot.Id]
	if list then
		for tier, entry in list do
			items[entry[1]] = { Id = entry[1], DisplayName = entry[2], Slot = slot.Id, Tier = tier, Color = TierDefs.get(tier).Color }
			table.insert(order, entry[1])
		end
	elseif ARMOR_SLOTS[slot.Id] then
		for tier, set in ARMOR_SETS do
			local id = set.Id .. slot.Id
			items[id] = { Id = id, DisplayName = set.Names[slot.Id], Slot = slot.Id, Tier = tier, Color = set.Color, Set = set.Id }
			table.insert(order, id)
		end
	end
end

-- 화살통 (방패 칸, 등에 멘다). 단계는 겉모습용 (1 나무·가죽 / 3 철 테두리 / 5 미스릴 테두리). 화살 수·가격은 Config.Quiver
-- 장비 아이콘을 만드는 Studio 스크립트가 칸마다 모양을 정해 두어서 Order에는 넣지 않고 QuiverOrder로 따로 둔다
local QUIVERS: { { any } } = {
	{ "WoodQuiver", "나무 화살통", 1, Color3.fromRGB(150, 98, 58) },
	{ "IronQuiver", "철 화살통", 3, Color3.fromRGB(105, 62, 38) },
	{ "MithrilQuiver", "미스릴 화살통", 5, Color3.fromRGB(55, 70, 105) }, -- 2026-10-09: 화살 많이
}
local quiverOrder: { string } = {}
for _, entry in QUIVERS do
	items[entry[1]] = { Id = entry[1], DisplayName = entry[2], Slot = "Shield", Tier = entry[3], Color = entry[4], Quiver = true }
	table.insert(quiverOrder, entry[1])
end

-- 방패 (방패 칸, 왼팔 아래팔 바깥에 찬다, 2026-10-10 사용자 요청). 단계 = 방어구 세트 단계, 모양·색은 세트마다 (GearVisualService buildShield)
-- 1단계만 나무 방패 (세트는 가죽 = 가죽 끈). Order에 넣어서 가방 "방어구"·사냥꾼 "방패" 탭·장비 아이콘이 같이 다룬다. 수치 Config.Equipment.Base.Shield
local SHIELDS: { { string } } = {
	{ "WoodShield", "나무 방패" },
	{ "BoneShield", "뼈 방패" },
	{ "CerberusShield", "케르베로스 송곳니 방패" },
	{ "CyclopsShield", "사이클롭스 외눈 방패" },
	{ "GolemShield", "바위 골렘 방패" },
	{ "FrostShield", "서리 거인 얼음 방패" },
	{ "BehemothShield", "베헤모스 비늘 방패" },
}
local shieldOrder: { string } = {}
for tier, entry in SHIELDS do
	local set = ARMOR_SETS[tier]
	local color = if tier == 1 then Color3.fromRGB(160, 112, 66) else set.Color
	items[entry[1]] = { Id = entry[1], DisplayName = entry[2], Slot = "Shield", Tier = tier, Color = color, Set = set.Id }
	table.insert(order, entry[1])
	table.insert(shieldOrder, entry[1])
end

return table.freeze({
	Slots = table.freeze(SLOTS),
	Items = table.freeze(items),
	Order = table.freeze(order), -- 헬멧 1~7단계, 갑옷 1~7단계 ... 목걸이 1~6단계, 방패 1~7단계 순서 (화살통은 빠짐)
	Renamed = table.freeze(RENAMED), -- 예전 방어구 Id → 새 Id (2026-10-10)
	QuiverOrder = table.freeze(quiverOrder), -- 화살통 (작은 것부터)
	ShieldOrder = table.freeze(shieldOrder), -- 방패 1~7단계 (Order에도 들어 있다)
})
