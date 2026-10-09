--!strict
-- 장비 칸과 장비 아이템 정의 (이름·칸·단계·색). 능력치·가격 수치는 Config.Equipment에 있다.
-- 칸: 무기(손에 든 도구·무기) / 방패 / 헬멧 / 갑옷 / 신발 / 장갑 / 목걸이 / 팔찌
-- 무기 칸은 따로 끼우지 않고 지금 손에 든 도구·무기가 들어간다.
-- 방패 칸에는 지금은 화살통만 들어간다 (활을 쏘려면 화살이 든 화살통이 필요. 화살 수는 Config.Quiver).
-- 장비 아이템은 ItemDefs에도 등록된다 (분류 "방어구", 화살통은 "무기").
-- 단계 색·이름은 TierDefs. 단계 수를 가정하지 않으니 7단계부터는 NAMES 각 줄에 하나씩 더하면 된다

local TierDefs = require(script.Parent.TierDefs)

export type Slot = "Weapon" | "Shield" | "Helmet" | "Armor" | "Boots" | "Gloves" | "Necklace" | "Bracelet"

export type EquipmentDef = {
	Id: string,
	DisplayName: string,
	Slot: Slot,
	Tier: number,
	Color: Color3,
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

-- 칸마다 단계별 (Id, 이름). 단계 = 목록 순서 (1 가죽·뼈·나무 / 2 구리 / 3 철 / 4 다이아몬드 / 5 미스릴 / 6 오리하르콘)
-- 방어구(헬멧·갑옷·신발·장갑)는 이름은 금속이어도 주재료는 몹 전리품(가죽·뼈·천), 장신구는 광물 (Config.Recipes, 2026-10-09)
local NAMES: { [string]: { { string } } } = {
	Helmet = { { "LeatherHelmet", "가죽 모자" }, { "CopperHelmet", "구리 투구" }, { "IronHelmet", "철 투구" }, { "DiamondHelmet", "다이아몬드 투구" }, { "MithrilHelmet", "미스릴 투구" }, { "OrichalcumHelmet", "오리하르콘 투구" } },
	Armor = { { "LeatherArmor", "가죽 갑옷" }, { "CopperArmor", "구리 갑옷" }, { "IronArmor", "철 갑옷" }, { "DiamondArmor", "다이아몬드 갑옷" }, { "MithrilArmor", "미스릴 갑옷" }, { "OrichalcumArmor", "오리하르콘 갑옷" } },
	Boots = { { "LeatherBoots", "가죽 장화" }, { "CopperBoots", "구리 장화" }, { "IronBoots", "철 장화" }, { "DiamondBoots", "다이아몬드 장화" }, { "MithrilBoots", "미스릴 장화" }, { "OrichalcumBoots", "오리하르콘 장화" } },
	Gloves = { { "LeatherGloves", "가죽 장갑" }, { "CopperGloves", "구리 장갑" }, { "IronGloves", "철 장갑" }, { "DiamondGloves", "다이아몬드 장갑" }, { "MithrilGloves", "미스릴 장갑" }, { "OrichalcumGloves", "오리하르콘 장갑" } },
	Necklace = { { "BoneNecklace", "뼈 목걸이" }, { "CopperNecklace", "구리 목걸이" }, { "IronNecklace", "철 목걸이" }, { "DiamondNecklace", "다이아몬드 목걸이" }, { "MithrilNecklace", "미스릴 목걸이" }, { "OrichalcumNecklace", "오리하르콘 목걸이" } },
	Bracelet = { { "WoodBracelet", "나무 팔찌" }, { "CopperBracelet", "구리 팔찌" }, { "IronBracelet", "철 팔찌" }, { "DiamondBracelet", "다이아몬드 팔찌" }, { "MithrilBracelet", "미스릴 팔찌" }, { "OrichalcumBracelet", "오리하르콘 팔찌" } },
}

local items: { [string]: EquipmentDef } = {}
local order: { string } = {}
for _, slot in SLOTS do
	local list = NAMES[slot.Id]
	if list then
		for tier, entry in list do
			items[entry[1]] = { Id = entry[1], DisplayName = entry[2], Slot = slot.Id, Tier = tier, Color = TierDefs.get(tier).Color }
			table.insert(order, entry[1])
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
	items[entry[1]] = { Id = entry[1], DisplayName = entry[2], Slot = "Shield", Tier = entry[3], Color = entry[4] }
	table.insert(quiverOrder, entry[1])
end

return table.freeze({
	Slots = table.freeze(SLOTS),
	Items = table.freeze(items),
	Order = table.freeze(order), -- 헬멧 1~6단계, 갑옷 1~6단계 ... 순서 (화살통은 빠짐)
	QuiverOrder = table.freeze(quiverOrder), -- 화살통 (작은 것부터)
})
