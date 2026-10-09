--!strict
-- 손에 드는 도구(곡괭이·도끼·무기) 정의. 이름·종류·티어·모델 정보만 둔다.
-- 이름은 PickaxeDefs지만 도끼와 무기(칼·활·방망이)도 여기 있다 (Kind로 구분). Tool 속성 PickaxeId에 이 Id가 들어간다.
-- 곡괭이·도끼 데미지(Power)와 가격은 Config.Pickaxes, 무기 데미지·사거리·가격은 Config.Weapons에 있다.
-- 단계: 1 돌·나무 / 2 구리 / 3 철 / 4 다이아몬드 / 5 미스릴 / 6 오리하르콘 (이름·색은 TierDefs). 단계 수를 가정하는 코드는 없으니 7단계부터는 줄만 더하면 된다

export type ToolKind = "Pickaxe" | "Axe" | "Sword" | "Bow" | "Club"

export type PickaxeDef = {
	Id: string,
	DisplayName: string,
	Kind: ToolKind, -- 곡괭이는 바위, 도끼는 나무, 칼·활·방망이는 몹
	Tier: number,
	ToolName: string, -- ServerStorage/Templates/Pickaxes 안의 Tool 이름
}

local PickaxeDefs: { [string]: PickaxeDef } = {
	StonePickaxe = { Id = "StonePickaxe", DisplayName = "돌 곡괭이", Kind = "Pickaxe", Tier = 1, ToolName = "StonePickaxe" },
	CopperPickaxe = { Id = "CopperPickaxe", DisplayName = "구리 곡괭이", Kind = "Pickaxe", Tier = 2, ToolName = "CopperPickaxe" },
	IronPickaxe = { Id = "IronPickaxe", DisplayName = "철 곡괭이", Kind = "Pickaxe", Tier = 3, ToolName = "IronPickaxe" },
	-- Id는 저장·설정 호환을 위해 SteelPickaxe 그대로 두고 이름만 다이아몬드 곡괭이 (2026-10-09 변경)
	SteelPickaxe = { Id = "SteelPickaxe", DisplayName = "다이아몬드 곡괭이", Kind = "Pickaxe", Tier = 4, ToolName = "SteelPickaxe" },
	-- 5·6단계 (2026-10-09): Tool은 studio/BuildTreesAndAxes가 다이아몬드 곡괭이를 복제해 색·빛을 바꿔 만든다
	MithrilPickaxe = { Id = "MithrilPickaxe", DisplayName = "미스릴 곡괭이", Kind = "Pickaxe", Tier = 5, ToolName = "MithrilPickaxe" },
	OrichalcumPickaxe = { Id = "OrichalcumPickaxe", DisplayName = "오리하르콘 곡괭이", Kind = "Pickaxe", Tier = 6, ToolName = "OrichalcumPickaxe" },
	StoneAxe = { Id = "StoneAxe", DisplayName = "돌 도끼", Kind = "Axe", Tier = 1, ToolName = "StoneAxe" },
	CopperAxe = { Id = "CopperAxe", DisplayName = "구리 도끼", Kind = "Axe", Tier = 2, ToolName = "CopperAxe" },
	IronAxe = { Id = "IronAxe", DisplayName = "철 도끼", Kind = "Axe", Tier = 3, ToolName = "IronAxe" },
	DiamondAxe = { Id = "DiamondAxe", DisplayName = "다이아몬드 도끼", Kind = "Axe", Tier = 4, ToolName = "DiamondAxe" },
	MithrilAxe = { Id = "MithrilAxe", DisplayName = "미스릴 도끼", Kind = "Axe", Tier = 5, ToolName = "MithrilAxe" },
	OrichalcumAxe = { Id = "OrichalcumAxe", DisplayName = "오리하르콘 도끼", Kind = "Axe", Tier = 6, ToolName = "OrichalcumAxe" },
	-- 무기: 칼
	WoodenSword = { Id = "WoodenSword", DisplayName = "나무 검", Kind = "Sword", Tier = 1, ToolName = "WoodenSword" },
	CopperSword = { Id = "CopperSword", DisplayName = "구리 검", Kind = "Sword", Tier = 2, ToolName = "CopperSword" },
	IronSword = { Id = "IronSword", DisplayName = "철 장검", Kind = "Sword", Tier = 3, ToolName = "IronSword" },
	DiamondSword = { Id = "DiamondSword", DisplayName = "다이아몬드 대검", Kind = "Sword", Tier = 4, ToolName = "DiamondSword" },
	MithrilSword = { Id = "MithrilSword", DisplayName = "미스릴 검", Kind = "Sword", Tier = 5, ToolName = "MithrilSword" },
	OrichalcumSword = { Id = "OrichalcumSword", DisplayName = "오리하르콘 성검", Kind = "Sword", Tier = 6, ToolName = "OrichalcumSword" },
	-- 무기: 활
	WoodenBow = { Id = "WoodenBow", DisplayName = "나무 활", Kind = "Bow", Tier = 1, ToolName = "WoodenBow" },
	CopperBow = { Id = "CopperBow", DisplayName = "구리 활", Kind = "Bow", Tier = 2, ToolName = "CopperBow" },
	IronBow = { Id = "IronBow", DisplayName = "철 장궁", Kind = "Bow", Tier = 3, ToolName = "IronBow" },
	DiamondBow = { Id = "DiamondBow", DisplayName = "다이아몬드 활", Kind = "Bow", Tier = 4, ToolName = "DiamondBow" },
	MithrilBow = { Id = "MithrilBow", DisplayName = "미스릴 활", Kind = "Bow", Tier = 5, ToolName = "MithrilBow" },
	OrichalcumBow = { Id = "OrichalcumBow", DisplayName = "오리하르콘 태양궁", Kind = "Bow", Tier = 6, ToolName = "OrichalcumBow" },
	-- 무기: 방망이
	BaseballBat = { Id = "BaseballBat", DisplayName = "야구방망이", Kind = "Club", Tier = 1, ToolName = "BaseballBat" },
	GoblinClub = { Id = "GoblinClub", DisplayName = "도깨비방망이", Kind = "Club", Tier = 2, ToolName = "GoblinClub" },
	MorningStar = { Id = "MorningStar", DisplayName = "모닝스타", Kind = "Club", Tier = 3, ToolName = "MorningStar" },
	DiamondMace = { Id = "DiamondMace", DisplayName = "다이아몬드 철퇴", Kind = "Club", Tier = 4, ToolName = "DiamondMace" },
	MithrilHammer = { Id = "MithrilHammer", DisplayName = "미스릴 전투망치", Kind = "Club", Tier = 5, ToolName = "MithrilHammer" },
	OrichalcumHammer = { Id = "OrichalcumHammer", DisplayName = "오리하르콘 거인망치", Kind = "Club", Tier = 6, ToolName = "OrichalcumHammer" },
}

return table.freeze(PickaxeDefs)
