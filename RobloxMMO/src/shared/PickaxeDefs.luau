--!strict
-- 채집 도구(곡괭이·도끼) 정의. 이름·종류·티어·모델 정보만 둔다.
-- 이름은 PickaxeDefs지만 도끼도 여기 있다 (Kind로 구분). Tool 속성 PickaxeId에 이 Id가 들어간다.
-- 데미지(Power)와 가격은 Config.Pickaxes에 있다.

export type ToolKind = "Pickaxe" | "Axe"

export type PickaxeDef = {
	Id: string,
	DisplayName: string,
	Kind: ToolKind, -- 곡괭이는 바위, 도끼는 나무
	Tier: number,
	ToolName: string, -- ServerStorage/Templates/Pickaxes 안의 Tool 이름
}

local PickaxeDefs: { [string]: PickaxeDef } = {
	StonePickaxe = { Id = "StonePickaxe", DisplayName = "돌 곡괭이", Kind = "Pickaxe", Tier = 1, ToolName = "StonePickaxe" },
	CopperPickaxe = { Id = "CopperPickaxe", DisplayName = "구리 곡괭이", Kind = "Pickaxe", Tier = 2, ToolName = "CopperPickaxe" },
	IronPickaxe = { Id = "IronPickaxe", DisplayName = "철 곡괭이", Kind = "Pickaxe", Tier = 3, ToolName = "IronPickaxe" },
	-- Id는 저장·설정 호환을 위해 SteelPickaxe 그대로 두고 이름만 다이아몬드 곡괭이 (2026-10-09 변경)
	SteelPickaxe = { Id = "SteelPickaxe", DisplayName = "다이아몬드 곡괭이", Kind = "Pickaxe", Tier = 4, ToolName = "SteelPickaxe" },
	StoneAxe = { Id = "StoneAxe", DisplayName = "돌 도끼", Kind = "Axe", Tier = 1, ToolName = "StoneAxe" },
	CopperAxe = { Id = "CopperAxe", DisplayName = "구리 도끼", Kind = "Axe", Tier = 2, ToolName = "CopperAxe" },
	IronAxe = { Id = "IronAxe", DisplayName = "철 도끼", Kind = "Axe", Tier = 3, ToolName = "IronAxe" },
	DiamondAxe = { Id = "DiamondAxe", DisplayName = "다이아몬드 도끼", Kind = "Axe", Tier = 4, ToolName = "DiamondAxe" },
}

return table.freeze(PickaxeDefs)
