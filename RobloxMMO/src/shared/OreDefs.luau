--!strict
-- 자원 노드(바위·나무) 정의. 이름·종류·필요 티어·템플릿·색 같은 고정 정보만 둔다.
-- HP, 리스폰 시간 같은 밸런스 수치는 Config.Ores에 있다.
-- 노드를 깨면 같은 Id의 아이템(ItemDefs)이 가방에 들어온다 (나무는 통나무).

export type OreDef = {
	Id: string, -- OreSpawns 파트의 OreType 속성 값과 같아야 한다
	DisplayName: string,
	Kind: "Rock" | "Tree", -- 바위는 곡괭이로 캐고, 나무는 도끼로 벤다
	RequiredTier: number, -- 캘 수 있는 최소 도구 티어 (바위는 곡괭이, 나무는 도끼)
	TemplateName: string, -- ServerStorage/Templates/Ores 안의 폴더 이름 (모양 변형 모델들이 들어 있다)
	Color: Color3, -- 파편·조각 색
	HitHeight: number?, -- 나무: 타격 위치 높이 (밑동 기준, 스터드)
	HitRadius: number?, -- 나무: 줄기 중심에서 타격 위치까지 거리 (스터드). 잔상 고리 크기에도 쓴다
	LeafColor: Color3?, -- 나무: 칠 때 떨어지는 잎 색
}

-- 위치: 돌은 광산 지상, 석탄·구리는 1층, 철은 2층
-- 나무: 소나무·참나무·자작나무는 맵 곳곳, 단풍나무는 산 구석에 모여서, 흑단나무는 무작위 희귀 자리
-- 나무 모델의 기준점(Pivot)은 줄기 밑동 가운데다
local OreDefs: { [string]: OreDef } = {
	Stone = {
		Id = "Stone",
		DisplayName = "돌",
		Kind = "Rock",
		RequiredTier = 1,
		TemplateName = "Stone",
		Color = Color3.fromRGB(150, 145, 140),
	},
	Coal = {
		Id = "Coal",
		DisplayName = "석탄",
		Kind = "Rock",
		RequiredTier = 2,
		TemplateName = "Coal",
		Color = Color3.fromRGB(45, 45, 50),
	},
	CopperOre = {
		Id = "CopperOre",
		DisplayName = "구리",
		Kind = "Rock",
		RequiredTier = 2,
		TemplateName = "CopperOre",
		Color = Color3.fromRGB(205, 120, 70),
	},
	IronOre = {
		Id = "IronOre",
		DisplayName = "철",
		Kind = "Rock",
		RequiredTier = 3,
		TemplateName = "IronOre",
		Color = Color3.fromRGB(175, 160, 150),
	},
	Pine = {
		Id = "Pine",
		DisplayName = "소나무",
		Kind = "Tree",
		RequiredTier = 1,
		TemplateName = "Pine",
		Color = Color3.fromRGB(150, 105, 65),
		HitHeight = 2.5,
		HitRadius = 0.9,
		LeafColor = Color3.fromRGB(60, 110, 60),
	},
	Oak = {
		Id = "Oak",
		DisplayName = "참나무",
		Kind = "Tree",
		RequiredTier = 1,
		TemplateName = "Oak",
		Color = Color3.fromRGB(130, 90, 55),
		HitHeight = 2.5,
		HitRadius = 1.3,
		LeafColor = Color3.fromRGB(85, 140, 60),
	},
	Birch = {
		Id = "Birch",
		DisplayName = "자작나무",
		Kind = "Tree",
		RequiredTier = 2,
		TemplateName = "Birch",
		Color = Color3.fromRGB(230, 225, 210),
		HitHeight = 2.5,
		HitRadius = 0.8,
		LeafColor = Color3.fromRGB(150, 190, 80),
	},
	Maple = {
		Id = "Maple",
		DisplayName = "단풍나무",
		Kind = "Tree",
		RequiredTier = 3,
		TemplateName = "Maple",
		Color = Color3.fromRGB(150, 85, 50),
		HitHeight = 2.5,
		HitRadius = 1.1,
		LeafColor = Color3.fromRGB(215, 85, 40),
	},
	Ebony = {
		Id = "Ebony",
		DisplayName = "흑단나무",
		Kind = "Tree",
		RequiredTier = 4,
		TemplateName = "Ebony",
		Color = Color3.fromRGB(55, 35, 55),
		HitHeight = 2.5,
		HitRadius = 1.1,
		LeafColor = Color3.fromRGB(70, 50, 90),
	},
}

return table.freeze(OreDefs)
