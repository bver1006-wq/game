--!strict
-- 몹 정의. 이름·전리품·모델 이름·색 같은 고정 정보만 둔다.
-- 체력·공격력·속도·보상 같은 밸런스 수치는 Config.Mobs에, 사는 구역은 Config.MobZones에 있다.
-- 모델은 ServerStorage/Templates/Mobs/<TemplateName> (제작 스크립트가 부품으로 만든다).
-- 생성 위치는 Workspace/MobSpawns의 투명 파트 (속성 MobType, Zone, BossSpot).

export type MobDef = {
	Id: string,
	DisplayName: string,
	TemplateName: string,
	LootId: string, -- 쓰러뜨리면 떨어뜨리는 전리품 아이템 Id (ItemDefs)
	Color: Color3, -- 맞을 때 튀는 파편·쓰러질 때 연기 색
	Hop: boolean?, -- true면 통통 튀며 움직인다 (슬라임)
	Tier: number, -- 몹 단계. 무기 단계가 많이 낮으면 데미지가 안 들어간다 (Config.TierWall)
}

-- 마을에서 가까운 순서: 슬라임 → 스켈레톤·좀비 → 케르베로스 → 사이클롭스
local MobDefs: { [string]: MobDef } = {
	Slime = { Id = "Slime", DisplayName = "귀여운 슬라임", TemplateName = "Slime", LootId = "SlimeJelly", Color = Color3.fromRGB(110, 225, 160), Hop = true, Tier = 1 },
	Skeleton = { Id = "Skeleton", DisplayName = "귀여운 스켈레톤", TemplateName = "Skeleton", LootId = "Bone", Color = Color3.fromRGB(240, 235, 220), Tier = 2 },
	Zombie = { Id = "Zombie", DisplayName = "귀여운 좀비", TemplateName = "Zombie", LootId = "OldCloth", Color = Color3.fromRGB(140, 200, 120), Tier = 2 },
	Cerberus = { Id = "Cerberus", DisplayName = "귀여운 케르베로스", TemplateName = "Cerberus", LootId = "CerberusFang", Color = Color3.fromRGB(70, 55, 60), Tier = 3 },
	Cyclops = { Id = "Cyclops", DisplayName = "사이클롭스", TemplateName = "Cyclops", LootId = "CyclopsEye", Color = Color3.fromRGB(150, 160, 120), Tier = 4 },
}

return table.freeze(MobDefs)
