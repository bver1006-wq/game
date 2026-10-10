--!strict
-- 마을 NPC 상점 정의. 이름·역할·탭 구성만 둔다.
-- 가격·레시피 숫자는 Config(SellPrices, Smelting, Recipes)에 있다.
-- 탭은 위쪽에 큰 그림 버튼으로 보인다 (Icon = 대표 아이템 Id, 또는 "@Bag" 가방 그림 / "@Coin" 금화 그림, 2026-10-09)
-- Studio의 NPC 모델 속성 ShopId가 여기 키와 같아야 한다.

export type ShopTab = {
	Id: "Smelt" | "Pickaxe" | "Axe" | "Sword" | "Bow" | "Club" | "Helmet" | "Armor" | "Boots" | "Gloves" | "Accessory" | "Sell" | "Buy" | "Bag" | "ComingSoon",
	Title: string, -- 그림 아래 짧은 이름
	Icon: string, -- 탭 그림: 아이템 Id (ItemIcon) 또는 "@Bag" / "@Coin"
	Note: string?, -- ComingSoon 탭에 보여줄 설명
}

export type ShopDef = {
	Id: string,
	NpcName: string,
	Role: string, -- 이름표 아래 한 줄 설명
	Greeting: string,
	Tabs: { ShopTab },
}

local ShopDefs: { [string]: ShopDef } = {
	Blacksmith = {
		Id = "Blacksmith",
		NpcName = "대장장이 브론",
		Role = "제련 · 곡괭이 · 도끼",
		Greeting = "광석이랑 석탄을 가져오면 괴로 녹여 주지. 손잡이 감 통나무도 챙겨 오게.",
		Tabs = {
			{ Id = "Smelt", Title = "제련", Icon = "CopperIngot" },
			{ Id = "Pickaxe", Title = "곡괭이", Icon = "IronPickaxe" },
			{ Id = "Axe", Title = "도끼", Icon = "IronAxe" },
		},
	},
	Merchant = {
		Id = "Merchant",
		NpcName = "상인 미라",
		Role = "잡화 매입 · 가방 · 음식 · 물약",
		Greeting = "캐 온 광석이나 괴, 통나무, 몹 전리품까지 값 잘 쳐줄게요!",
		Tabs = {
			{ Id = "Sell", Title = "팔기", Icon = "@Coin" },
			{ Id = "Buy", Title = "잡화", Icon = "Bread" },
			{ Id = "Bag", Title = "가방", Icon = "@Bag" },
			-- MVP 제외 항목(버프 음식은 MVP-2, 물약은 범위 밖). NPC만 먼저 배치
			{ Id = "ComingSoon", Title = "준비 중", Icon = "Bread", Note = "버프 음식과 물약은 준비 중이에요." },
		},
	},
	Hunter = {
		Id = "Hunter",
		NpcName = "사냥꾼 카엘",
		Role = "칼 · 활 · 방망이 · 방어구 · 장신구",
		Greeting = "들판에 귀여운 녀석들이 늘었어. 얕보면 큰코다치니 무기 하나 챙겨 가게.",
		Tabs = {
			-- 사냥과 전투는 2026-10-09 사용자 결정으로 앞당김. 장비는 칸마다 탭 (장신구 = 목걸이 + 팔찌)
			-- 방어구 탭은 몹 세트 7단계(가죽 → 뼈 → 케르베로스 → 사이클롭스 → 바위 골렘 → 서리 거인 → 베헤모스, 2026-10-10)가 EquipmentDefs 순서대로 나온다
			{ Id = "Sword", Title = "칼", Icon = "IronSword" },
			{ Id = "Bow", Title = "활", Icon = "IronBow" },
			{ Id = "Club", Title = "방망이", Icon = "GoblinClub" },
			{ Id = "Helmet", Title = "투구", Icon = "CerberusHelmet" },
			{ Id = "Armor", Title = "갑옷", Icon = "BoneArmor" },
			{ Id = "Boots", Title = "신발", Icon = "CerberusBoots" },
			{ Id = "Gloves", Title = "장갑", Icon = "GolemGloves" },
			{ Id = "Accessory", Title = "장신구", Icon = "IronNecklace" },
		},
	},
}

return table.freeze(ShopDefs)
