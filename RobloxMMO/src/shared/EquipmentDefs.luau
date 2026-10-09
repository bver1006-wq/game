--!strict
-- 장비 칸과 장비 아이템 정의 (이름·칸·단계·색). 능력치·가격 수치는 Config.Equipment에 있다.
-- 칸: 무기(손에 든 도구·무기) / 헬멧 / 갑옷 / 신발 / 장갑 / 목걸이 / 팔찌
-- 무기 칸은 따로 끼우지 않고 지금 손에 든 도구·무기가 들어간다.
-- 장비 아이템은 ItemDefs에도 등록된다 (분류 "방어구").

export type Slot = "Weapon" | "Helmet" | "Armor" | "Boots" | "Gloves" | "Necklace" | "Bracelet"

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
	{ Id = "Helmet", Title = "헬멧" },
	{ Id = "Armor", Title = "갑옷" },
	{ Id = "Boots", Title = "신발" },
	{ Id = "Gloves", Title = "장갑" },
	{ Id = "Necklace", Title = "목걸이" },
	{ Id = "Bracelet", Title = "팔찌" },
}

-- 단계별 재질 이름과 색 (1 가죽·뼈·나무 / 2 구리 / 3 철 / 4 다이아몬드)
local TIER_COLORS = {
	Color3.fromRGB(140, 95, 60),
	Color3.fromRGB(205, 115, 60),
	Color3.fromRGB(175, 178, 188),
	Color3.fromRGB(110, 220, 255),
}

-- 칸마다 단계별 (Id, 이름)
local NAMES: { [string]: { { string } } } = {
	Helmet = { { "LeatherHelmet", "가죽 모자" }, { "CopperHelmet", "구리 투구" }, { "IronHelmet", "철 투구" }, { "DiamondHelmet", "다이아몬드 투구" } },
	Armor = { { "LeatherArmor", "가죽 갑옷" }, { "CopperArmor", "구리 갑옷" }, { "IronArmor", "철 갑옷" }, { "DiamondArmor", "다이아몬드 갑옷" } },
	Boots = { { "LeatherBoots", "가죽 장화" }, { "CopperBoots", "구리 장화" }, { "IronBoots", "철 장화" }, { "DiamondBoots", "다이아몬드 장화" } },
	Gloves = { { "LeatherGloves", "가죽 장갑" }, { "CopperGloves", "구리 장갑" }, { "IronGloves", "철 장갑" }, { "DiamondGloves", "다이아몬드 장갑" } },
	Necklace = { { "BoneNecklace", "뼈 목걸이" }, { "CopperNecklace", "구리 목걸이" }, { "IronNecklace", "철 목걸이" }, { "DiamondNecklace", "다이아몬드 목걸이" } },
	Bracelet = { { "WoodBracelet", "나무 팔찌" }, { "CopperBracelet", "구리 팔찌" }, { "IronBracelet", "철 팔찌" }, { "DiamondBracelet", "다이아몬드 팔찌" } },
}

local items: { [string]: EquipmentDef } = {}
local order: { string } = {}
for _, slot in SLOTS do
	local list = NAMES[slot.Id]
	if list then
		for tier, entry in list do
			items[entry[1]] = { Id = entry[1], DisplayName = entry[2], Slot = slot.Id, Tier = tier, Color = TIER_COLORS[tier] }
			table.insert(order, entry[1])
		end
	end
end

return table.freeze({
	Slots = table.freeze(SLOTS),
	Items = table.freeze(items),
	Order = table.freeze(order), -- 헬멧 T1~T4, 갑옷 T1~T4 ... 순서
})
