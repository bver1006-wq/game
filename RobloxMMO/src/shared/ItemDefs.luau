--!strict
-- 가방에 들어가는 아이템 정의. 이름·분류·아이콘 같은 고정 정보만 둔다.
-- 판매가·레시피 같은 밸런스 수치는 Config에 있다.
-- 광석·통나무 아이템 Id는 OreDefs의 Id와, 곡괭이·도끼 아이템 Id는 PickaxeDefs의 Id와 같다.

-- 가방 분류 탭: 무기 / 방어구 / 도구 / 기타
export type Category = "Weapon" | "Armor" | "Tool" | "Etc"

export type ItemDef = {
	Id: string,
	DisplayName: string,
	Category: Category,
	Stackable: boolean, -- true면 한 칸에 Config.Inventory.MaxStack개까지 쌓인다. false면 1개가 1칸
	Usable: boolean?, -- true면 빠른 호출 칸에서 눌러 쓴다 (서버 ItemUseService가 처리)
	Icon: string, -- ReplicatedStorage/ItemIcons 안의 아이콘 모델 이름
	Color: Color3, -- 아이콘이 없을 때 대신 칠할 색
}

local ItemDefs: { [string]: ItemDef } = {
	-- 기타: 광석
	Stone = { Id = "Stone", DisplayName = "돌", Category = "Etc", Stackable = true, Icon = "Stone", Color = Color3.fromRGB(150, 145, 140) },
	Coal = { Id = "Coal", DisplayName = "석탄", Category = "Etc", Stackable = true, Icon = "Coal", Color = Color3.fromRGB(45, 45, 50) },
	CopperOre = { Id = "CopperOre", DisplayName = "구리", Category = "Etc", Stackable = true, Icon = "CopperOre", Color = Color3.fromRGB(205, 120, 70) },
	IronOre = { Id = "IronOre", DisplayName = "철", Category = "Etc", Stackable = true, Icon = "IronOre", Color = Color3.fromRGB(175, 160, 150) },
	-- 기타: 괴
	CopperIngot = { Id = "CopperIngot", DisplayName = "구리괴", Category = "Etc", Stackable = true, Icon = "CopperIngot", Color = Color3.fromRGB(230, 140, 80) },
	IronIngot = { Id = "IronIngot", DisplayName = "철괴", Category = "Etc", Stackable = true, Icon = "IronIngot", Color = Color3.fromRGB(200, 200, 205) },
	SteelIngot = { Id = "SteelIngot", DisplayName = "강철괴", Category = "Etc", Stackable = true, Icon = "SteelIngot", Color = Color3.fromRGB(130, 150, 175) },
	-- 기타: 통나무 (나무 노드 Id와 같다)
	Pine = { Id = "Pine", DisplayName = "소나무 통나무", Category = "Etc", Stackable = true, Icon = "Pine", Color = Color3.fromRGB(150, 105, 65) },
	Oak = { Id = "Oak", DisplayName = "참나무 통나무", Category = "Etc", Stackable = true, Icon = "Oak", Color = Color3.fromRGB(130, 90, 55) },
	Birch = { Id = "Birch", DisplayName = "자작나무 통나무", Category = "Etc", Stackable = true, Icon = "Birch", Color = Color3.fromRGB(230, 225, 210) },
	Maple = { Id = "Maple", DisplayName = "단풍나무 통나무", Category = "Etc", Stackable = true, Icon = "Maple", Color = Color3.fromRGB(175, 80, 45) },
	Ebony = { Id = "Ebony", DisplayName = "흑단나무 통나무", Category = "Etc", Stackable = true, Icon = "Ebony", Color = Color3.fromRGB(55, 35, 55) },
	-- 기타: 몹 전리품
	SlimeJelly = { Id = "SlimeJelly", DisplayName = "슬라임 젤리", Category = "Etc", Stackable = true, Icon = "SlimeJelly", Color = Color3.fromRGB(110, 225, 160) },
	Bone = { Id = "Bone", DisplayName = "뼈다귀", Category = "Etc", Stackable = true, Icon = "Bone", Color = Color3.fromRGB(240, 235, 220) },
	OldCloth = { Id = "OldCloth", DisplayName = "낡은 천", Category = "Etc", Stackable = true, Icon = "OldCloth", Color = Color3.fromRGB(90, 110, 150) },
	CerberusFang = { Id = "CerberusFang", DisplayName = "케르베로스 송곳니", Category = "Etc", Stackable = true, Icon = "CerberusFang", Color = Color3.fromRGB(250, 245, 230) },
	BugbearFur = { Id = "BugbearFur", DisplayName = "버그베어 털", Category = "Etc", Stackable = true, Icon = "BugbearFur", Color = Color3.fromRGB(140, 95, 60) },
	-- 도구: 소모품
	ReturnScroll = { Id = "ReturnScroll", DisplayName = "귀환 주문서", Category = "Tool", Stackable = true, Usable = true, Icon = "ReturnScroll", Color = Color3.fromRGB(235, 215, 160) },
	-- 도구: 곡괭이 (실제 Tool은 PickaxeService가 가방에 넣는다)
	StonePickaxe = { Id = "StonePickaxe", DisplayName = "돌 곡괭이", Category = "Tool", Stackable = false, Icon = "StonePickaxe", Color = Color3.fromRGB(150, 145, 140) },
	CopperPickaxe = { Id = "CopperPickaxe", DisplayName = "구리 곡괭이", Category = "Tool", Stackable = false, Icon = "CopperPickaxe", Color = Color3.fromRGB(205, 115, 60) },
	IronPickaxe = { Id = "IronPickaxe", DisplayName = "철 곡괭이", Category = "Tool", Stackable = false, Icon = "IronPickaxe", Color = Color3.fromRGB(170, 170, 175) },
	SteelPickaxe = { Id = "SteelPickaxe", DisplayName = "다이아몬드 곡괭이", Category = "Tool", Stackable = false, Icon = "SteelPickaxe", Color = Color3.fromRGB(110, 220, 255) },
	-- 도구: 도끼 (실제 Tool은 PickaxeService가 가방에 넣는다)
	StoneAxe = { Id = "StoneAxe", DisplayName = "돌 도끼", Category = "Tool", Stackable = false, Icon = "StoneAxe", Color = Color3.fromRGB(150, 145, 140) },
	CopperAxe = { Id = "CopperAxe", DisplayName = "구리 도끼", Category = "Tool", Stackable = false, Icon = "CopperAxe", Color = Color3.fromRGB(205, 115, 60) },
	IronAxe = { Id = "IronAxe", DisplayName = "철 도끼", Category = "Tool", Stackable = false, Icon = "IronAxe", Color = Color3.fromRGB(170, 170, 175) },
	DiamondAxe = { Id = "DiamondAxe", DisplayName = "다이아몬드 도끼", Category = "Tool", Stackable = false, Icon = "DiamondAxe", Color = Color3.fromRGB(110, 220, 255) },
	-- 무기 (실제 Tool은 PickaxeService가 가방에 넣는다)
	WoodenSword = { Id = "WoodenSword", DisplayName = "나무 검", Category = "Weapon", Stackable = false, Icon = "WoodenSword", Color = Color3.fromRGB(160, 115, 70) },
	CopperSword = { Id = "CopperSword", DisplayName = "구리 검", Category = "Weapon", Stackable = false, Icon = "CopperSword", Color = Color3.fromRGB(205, 115, 60) },
	IronSword = { Id = "IronSword", DisplayName = "철 장검", Category = "Weapon", Stackable = false, Icon = "IronSword", Color = Color3.fromRGB(170, 170, 175) },
	DiamondSword = { Id = "DiamondSword", DisplayName = "다이아몬드 대검", Category = "Weapon", Stackable = false, Icon = "DiamondSword", Color = Color3.fromRGB(110, 220, 255) },
	WoodenBow = { Id = "WoodenBow", DisplayName = "나무 활", Category = "Weapon", Stackable = false, Icon = "WoodenBow", Color = Color3.fromRGB(160, 115, 70) },
	CopperBow = { Id = "CopperBow", DisplayName = "구리 활", Category = "Weapon", Stackable = false, Icon = "CopperBow", Color = Color3.fromRGB(205, 115, 60) },
	IronBow = { Id = "IronBow", DisplayName = "철 장궁", Category = "Weapon", Stackable = false, Icon = "IronBow", Color = Color3.fromRGB(170, 170, 175) },
	DiamondBow = { Id = "DiamondBow", DisplayName = "다이아몬드 활", Category = "Weapon", Stackable = false, Icon = "DiamondBow", Color = Color3.fromRGB(110, 220, 255) },
	BaseballBat = { Id = "BaseballBat", DisplayName = "야구방망이", Category = "Weapon", Stackable = false, Icon = "BaseballBat", Color = Color3.fromRGB(215, 180, 130) },
	GoblinClub = { Id = "GoblinClub", DisplayName = "도깨비방망이", Category = "Weapon", Stackable = false, Icon = "GoblinClub", Color = Color3.fromRGB(120, 75, 45) },
	MorningStar = { Id = "MorningStar", DisplayName = "모닝스타", Category = "Weapon", Stackable = false, Icon = "MorningStar", Color = Color3.fromRGB(170, 170, 175) },
	DiamondMace = { Id = "DiamondMace", DisplayName = "다이아몬드 철퇴", Category = "Weapon", Stackable = false, Icon = "DiamondMace", Color = Color3.fromRGB(110, 220, 255) },
}

-- UI에 보여줄 순서 (무기 → 도구 → 기타)
local ORDER = {
	"WoodenSword", "CopperSword", "IronSword", "DiamondSword",
	"WoodenBow", "CopperBow", "IronBow", "DiamondBow",
	"BaseballBat", "GoblinClub", "MorningStar", "DiamondMace",
	"StonePickaxe", "CopperPickaxe", "IronPickaxe", "SteelPickaxe",
	"StoneAxe", "CopperAxe", "IronAxe", "DiamondAxe", "ReturnScroll",
	"Stone", "Coal", "CopperOre", "IronOre", "CopperIngot", "IronIngot", "SteelIngot",
	"Pine", "Oak", "Birch", "Maple", "Ebony",
	"SlimeJelly", "Bone", "OldCloth", "CerberusFang", "BugbearFur",
}

-- 가방 분류 탭 (순서대로 표시). Category가 nil이면 전체
local TABS: { { Title: string, Category: Category? } } = {
	{ Title = "전체", Category = nil },
	{ Title = "무기", Category = "Weapon" },
	{ Title = "방어구", Category = "Armor" },
	{ Title = "도구", Category = "Tool" },
	{ Title = "기타", Category = "Etc" },
}

return table.freeze({
	Items = table.freeze(ItemDefs),
	Order = table.freeze(ORDER),
	Tabs = table.freeze(TABS),
})
