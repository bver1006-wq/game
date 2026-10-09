--!strict
-- 마을 NPC 상점 정의. 이름·역할·탭 구성만 둔다.
-- 가격·레시피 숫자는 Config(SellPrices, Smelting, Pickaxes)에 있다.
-- Studio의 NPC 모델 속성 ShopId가 여기 키와 같아야 한다.

export type ShopTab = {
	Id: "Smelt" | "Pickaxe" | "Axe" | "Sell" | "Buy" | "Bag" | "ComingSoon",
	Title: string,
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
			{ Id = "Smelt", Title = "제련" },
			{ Id = "Pickaxe", Title = "곡괭이" },
			{ Id = "Axe", Title = "도끼" },
		},
	},
	Merchant = {
		Id = "Merchant",
		NpcName = "상인 미라",
		Role = "잡화 매입 · 가방 · 음식 · 물약",
		Greeting = "캐 온 광석이나 괴, 통나무까지 값 잘 쳐줄게요!",
		Tabs = {
			{ Id = "Sell", Title = "팔기" },
			{ Id = "Buy", Title = "잡화" },
			{ Id = "Bag", Title = "가방" },
			-- MVP 제외 항목(버프 음식은 MVP-2, 물약은 범위 밖). NPC만 먼저 배치
			{ Id = "ComingSoon", Title = "음식 · 물약", Note = "버프 음식과 물약은 준비 중이에요." },
		},
	},
	Hunter = {
		Id = "Hunter",
		NpcName = "사냥꾼 카엘",
		Role = "무기 · 가죽 방어구",
		Greeting = "사냥 장비라면 나한테 오게. ...아직 가게 정리 중이지만.",
		Tabs = {
			-- MVP 제외 항목(사냥과 전투). NPC만 먼저 배치
			{ Id = "ComingSoon", Title = "무기 · 방어구 · 신발", Note = "무기, 방어구, 신발은 준비 중이에요." },
		},
	},
}

return table.freeze(ShopDefs)
