--!strict
-- 모든 밸런스 수치를 모아 두는 모듈.
-- 플레이테스트로 계속 바뀌므로 다른 코드에는 숫자를 직접 쓰지 말고 여기 값을 참조한다.

local Config = {}

-- 채굴(휘두르기) 기본 수치
Config.Mining = {
	SwingInterval = 0.8, -- 휘두르기 최소 간격(초). 서버 쿨다운 기준
	CooldownTolerance = 0.1, -- 네트워크 흔들림 때문에 서버 쿨다운을 이만큼 봐준다(초)
	SwingAnimDuration = 0.3, -- 휘두르는 동작 길이(초). 0.3 이내 유지
	BaseDamage = 1, -- 일반 타격 1회 기본 데미지. 곡괭이 Power와 판정 배수(Config.Judgment)를 곱한다
	MaxSwingDistance = 8, -- 캐릭터와 바위 중심 사이 최대 거리(스터드)
	AutoAimRange = 8, -- 클라이언트 자동 조준 탐색 반경(스터드). 서버 거리 제한 이하로 둔다
	EffectBroadcastRange = 100, -- 타격·깨짐 연출을 받을 플레이어 거리(스터드)
	-- 휘두르기 애니메이션 (Roblox 기본 toolslash)
	SwingAnimationR15 = "rbxassetid://522635514",
	SwingAnimationR6 = "rbxassetid://129967390",
}

-- 판정별 데미지 배수 (판정은 데미지에만 반영하고 산출량에는 영향 없음)
Config.Judgment = {
	DamageMultiplier = {
		Perfect = 2,
		Nice = 1.5,
		Normal = 1,
	},
}

-- 타이밍 판정: 타격하면 흐릿한 바위(잔상)가 커진 상태에서 원래 크기로 줄어든다.
-- 잔상이 바위 크기와 딱 맞는 순간 다시 치면 Perfect, 조금 어긋나면 Nice, 그 외 Normal
-- 리듬이 단조롭지 않게 잔상이 줄어드는 시간은 타격마다 서버가 Min~Max 사이에서 랜덤으로 정한다
Config.Timing = {
	GhostDurationMin = 0.9, -- 잔상이 줄어드는 시간 최소(초). 쿨다운(SwingInterval)보다 길어야 Perfect를 칠 수 있다
	GhostDurationMax = 1.4, -- 잔상이 줄어드는 시간 최대(초)
	GhostStartScale = 1.5, -- 잔상 시작 크기 (바위 대비 배수)
	-- 잔상은 ForceField 재질: 안쪽은 비치고 가장자리만 빛나서 돌 모양 테두리로 보인다
	GhostMaterial = Enum.Material.ForceField,
	GhostColor = Color3.fromRGB(255, 255, 255), -- 잔상 테두리 색 (2026-10-10 노랑 → 흰색)
	GhostFlashColor = Color3.fromRGB(120, 255, 140), -- 바위 크기에 닿는 순간 색 ("지금!" 신호. 테두리가 흰색이라 연두로)
	GhostLayers = 3, -- 테두리를 굵게: 잔상 껍데기를 이만큼 겹친다 (조금씩 크게)
	GhostLayerStep = 0.035, -- 겹칠 때마다 커지는 비율
	GhostTransparency = 0, -- 잔상 투명도 (ForceField는 0이어도 안쪽이 비친다. 올리면 더 옅어짐)
	MaxLatencyTolerance = 0.25, -- 클라이언트 시각을 믿어 줄 최대 차이(초). 넘으면 서버 수신 시각 사용
	-- 기기별 판정 범위: 잔상이 바위 크기가 되는 순간에서 앞뒤로 허용하는 시간(초)
	Windows = {
		PC = { Perfect = 0.08, Nice = 0.3 },
		Mobile = { Perfect = 0.12, Nice = 0.35 },
	},
}

-- 약점 수치 (7단계, 아직 미구현)
Config.Weakpoint = {
	SpawnChance = 0.25, -- 휘두를 때마다 약점이 새로 생길 확률. TODO: 조정
	Duration = 3, -- 약점 유지 시간(초)
	MaxAngle = 45, -- 약점 방향과 캐릭터 방향이 이 각도(도) 이내면 약점 타격
}

-- 광석별 수치 (정의는 OreDefs, 숫자는 여기)
-- TODO(미정): 구리·철 HP와 리스폰 시간은 임시값. 플레이테스트로 조정
-- HP = 첫 타(잔상이 없어 항상 일반, 1) + 이후 Perfect(2)만 쳤을 때 깨지는 횟수로 맞춘다
-- 돌: Perfect 연속 5타(1+2×4=9) / 일반만 9타
-- 구리: Perfect 연속 8타(1+2×7=15) / 일반만 15타
-- 철: Perfect 연속 15타(1+2×14=29) / 일반만 29타
-- 좋은 곡괭이(MVP-1)는 데미지가 올라 횟수가 줄어든다
-- 석탄은 T2 기준 임시값. TODO: 플레이테스트로 조정
-- 나무도 같은 표에 둔다 (도끼로 베는 자원 노드). TODO: 나무 HP·리스폰은 임시값
Config.Ores = {
	Stone = { MaxHp = 9, RespawnTime = 8 },
	Coal = { MaxHp = 12, RespawnTime = 10 },
	CopperOre = { MaxHp = 15, RespawnTime = 12 },
	IronOre = { MaxHp = 29, RespawnTime = 15 },
	Mithril = { MaxHp = 45, RespawnTime = 30 }, -- 광산 3층 (2026-10-09)
	Orichalcum = { MaxHp = 70, RespawnTime = 300 }, -- 광산 3층 아주 희귀 (RandomPools.Orichalcum)
	Pine = { MaxHp = 9, RespawnTime = 10 },
	Oak = { MaxHp = 12, RespawnTime = 12 },
	Birch = { MaxHp = 15, RespawnTime = 15 },
	Maple = { MaxHp = 29, RespawnTime = 20 },
	Ebony = { MaxHp = 45, RespawnTime = 90 },
}

-- 자연 회복: 바위·나무·몹은 한동안 안 맞으면 최대 체력의 일정 비율씩 천천히 찬다 (2026-10-09)
Config.Regen = {
	Delay = 6, -- 마지막으로 맞은 뒤 이만큼 지나야 차기 시작(초)
	NodePercentPerSecond = 0.04, -- 바위·나무: 1초에 최대 체력의 4% (다 차는 데 약 25초)
	MobPercentPerSecond = 0.05, -- 몹: 1초에 5% (쫓는 중에는 안 참)
}

-- 장비 벽: 도구·무기 단계가 모자라면 때릴 수는 있어도 체력이 안 닳는다 ("더 좋은 장비가 필요해")
-- 바위·나무: 도구 단계 < 필요 단계면 데미지 0
-- 몹: 무기 단계가 몹 단계보다 BlockGap 이상 낮으면 0, 1단계 낮으면 OneTierLowMultiplier배
Config.TierWall = {
	BlockGap = 2,
	OneTierLowMultiplier = 0.4,
	NoticeInterval = 4, -- (2026-10-09부터 안 씀: 알림 창 대신 "단단해!" 문구만)
}

-- 희귀 나무: 후보 자리(스폰 파트 속성 RandomPool) 중 Active개만 동시에 서 있고, 베면 다른 빈 자리에 다시 생긴다
-- 오리하르콘(광산 3층)도 같은 방식: 후보 자리 중 1개만, 캐면 RespawnTime 뒤 다른 빈 자리에
Config.RandomPools = {
	Ebony = { Active = 2 },
	Orichalcum = { Active = 1 },
}

-- 마을 거리별 난이도 (2026-10-09 사용자 요청): 마을 NPC 가까이는 쉬운 것(아주 가끔 중간), 조금 멀면 중간, 꽤 멀면 센 것
-- 거리 = 마을 도착점(TownArrival)에서 잰 수평 거리(스터드). 띠끼리 거리가 조금 겹치고, 겹친 곳에서는 비율이 서서히 바뀐다 (딱 끊기면 어색해서)
-- 제작 스크립트가 맵의 실제 땅 반경을 재서 MapRadius보다 좁으면 모든 거리(몹 구역 포함)를 그 비율로 줄인다 (넓으면 그대로)
-- 몹은 Config.MobZones, 광산 층 광석은 층별로 이미 나뉘어 있어서 그대로
Config.WorldTiers = {
	MapRadius = 280, -- 아래 거리들이 기준으로 삼는 맵 반경
	MinScale = 0.5, -- 맵이 좁아도 이보다 더 줄이지는 않는다
	-- 나무 종류: 띠마다 가중치(클수록 많이). 흑단나무는 아래 Ebony로 따로 (희귀 무리 Config.RandomPools.Ebony)
	Trees = {
		{ Name = "마을 근처", Distance = { 0, 130 }, Weights = { Pine = 50, Oak = 45, Birch = 5 } },
		{ Name = "조금 먼 숲", Distance = { 105, 210 }, Weights = { Pine = 5, Oak = 20, Birch = 60, Maple = 15 } },
		{ Name = "먼 숲", Distance = { 185, 99999 }, Weights = { Oak = 5, Birch = 25, Maple = 70 } },
	},
	-- 나무 개수: 맵 나무 자리에 더해 빈 풀밭에 더 심는다 (2026-10-09: 나무가 너무 적어서)
	TreeDensity = {
		Multiplier = 2.5, -- 맵 나무 수의 이 배수가 될 때까지
		MinCount = 90, -- 그래도 이만큼은
		MaxCount = 200, -- 너무 많으면 느려지니 이만큼까지
		Spacing = 10, -- 새로 심는 나무와 다른 나무·바위 사이 최소 간격
		MapTreeSpacing = 4, -- 맵 나무 자리끼리는 원래 간격 그대로 (이보다 가까운 것만 뺀다)
		ClearRadius = 4, -- 새 자리 둘레 이 반경이 모두 풀밭이어야 심는다 (길·건물·물 가장자리 피하기)
		ScatterMin = 40, -- 마을에서 이 거리 밖부터 (마을 안전지대 Config.MobAI.SafeZoneRadius 안에도 새로 안 심는다)
	},
	Ebony = { Candidates = 6, MinDistance = 185 }, -- 흑단나무 후보 자리: 이 거리 밖에서 마을에서 가장 먼 자리들 (서로 멀리)
	-- 지상 돌: 마을 근처에 최소 이만큼 (Studio에서 직접 놓은 돌 자리도 센다). 모자라면 제작 스크립트가 채운다
	Stone = { MinCount = 10, Distance = { 60, 150 } },
}

-- 곡괭이 데미지
-- 데미지 = BaseDamage × Power × 판정 배수 (2026-10-09 결정: 1 / 1.5 / 2 / 3)
-- 도끼도 같은 표에 둔다. 만드는 법(가격)은 Config.Recipes (2026-10-09 조합식으로 바뀜)
Config.Pickaxes = {
	StonePickaxe = { Power = 1 }, -- 시작 지급
	CopperPickaxe = { Power = 1.5 },
	IronPickaxe = { Power = 2 },
	SteelPickaxe = { Power = 3 }, -- 다이아몬드 곡괭이
	MithrilPickaxe = { Power = 4 }, -- 5단계 (2026-10-09). 오리하르콘(OreDefs RequiredTier 5)을 캔다
	OrichalcumPickaxe = { Power = 5.5 }, -- 6단계
	StoneAxe = { Power = 1 }, -- 시작 지급
	CopperAxe = { Power = 1.5 },
	IronAxe = { Power = 2 },
	DiamondAxe = {
		Power = 3,
		LightningChance = 0.2, -- 나무를 칠 때 이 확률로 번개가 내려쳐 한 방에 벤다 (2026-10-09 사용자 요청)
	},
	MithrilAxe = { Power = 4, LightningChance = 0.25 },
	OrichalcumAxe = { Power = 5.5, LightningChance = 0.3 },
}

-- 마나: 스킬·차징 스매시·달리기에 쓴다 (스킬·차징은 나중에). 플레이어 속성 Mana·MaxMana·Sprinting
Config.Mana = {
	Max = 100,
	Regen = 2.5, -- (2026-10-09부터 안 씀: 마을에서만 Config.TownRegen으로 찬다)
	RegenDelay = 1.5, -- 마나를 쓴 뒤 이만큼 지나야 다시 찬다(초)
}

-- 마을(몹 안전지대 Config.MobAI.SafeZoneRadius 안)에서만 체력·마나가 찬다. 밖에서는 음식으로만 (2026-10-09)
Config.TownRegen = {
	HpPerSecond = 5,
	ManaPerSecond = 6,
}

-- 이동 속도
Config.Movement = {
	WalkSpeed = 16, -- Roblox 기본 걷기 (지금은 안 씀)
	RunSpeed = 24, -- 항상 이 속도로 달린다 (2026-10-09 달리기 버튼 삭제)
	MovingThreshold = 2, -- 이 속도(스터드/초)보다 빠르면 움직이는 중으로 본다
}

-- 장비 능력치: 칸마다 1단계 기본값 × 단계 배수 (공격 Atk, 방어 Def, 체력 Hp, 치명타 Crit %)
-- 방어: 몹에게 받는 피해 × 100 / (100 + 방어). 체력: 최대 체력 + Hp. 공격: 무기 데미지에 더함. 치명타: 확률 + Crit%
-- 전투력 = 공격×3 + 방어×4 + 체력×1 + 치명타×15 (머리 위에 착용 장비 합산 값). 무기 칸은 손에 든 도구·무기
-- TODO(미정): 수치·가격은 임시값
Config.Equipment = {
	Base = {
		Helmet = { Def = 3, Hp = 10 },
		Armor = { Def = 6, Hp = 25 },
		Boots = { Def = 2, Hp = 5 },
		Gloves = { Atk = 2, Def = 1 },
		Necklace = { Hp = 15, Crit = 2 },
		Bracelet = { Atk = 3, Crit = 1 },
	},
	TierMultiplier = { 1, 2.2, 4, 7, 11, 16, 23 }, -- 단계별 (5 미스릴·6 오리하르콘 2026-10-09, 7 베헤모스 방어구 2026-10-10). 없는 단계는 가장 높은 아래 단계 값 (TierDefs.pick)
	ToolAtkPerPower = 6, -- 곡괭이·도끼를 들고 있으면 공격 = Power × 이 값 (무기는 Config.Weapons의 Damage)
	PowerWeights = { Atk = 3, Def = 4, Hp = 1, Crit = 15 },
	BaseMaxHealth = 100,
	-- 만드는 법(가격)은 Config.Recipes (2026-10-09 조합식으로 바뀜)
}

-- 화살통 (2026-10-09 사용자 요청): 방패 칸에 끼우고 등에 멘다. 활은 끼운 화살통에 화살이 있어야 쏘고, 한 발에 1개씩 준다
-- 화살이 0이 되면 화살통이 가방에서 사라지고, 가방에 다른 화살통이 있으면 저절로 바꿔 낀다. 능력치는 없음
-- 사냥꾼 "활" 탭에서 통나무를 잔뜩 + 골드 조금 (만들기는 조금 귀찮게, 사냥은 조금 편하게). TODO(미정): 임시값
Config.Quiver = {
	Items = {
		WoodQuiver = { Arrows = 30, Price = { Gold = 10, Items = { Pine = 20 } } },
		IronQuiver = { Arrows = 60, Price = { Gold = 40, Items = { Oak = 30, IronIngot = 2 } } },
		MithrilQuiver = { Arrows = 100, Price = { Gold = 120, Items = { Maple = 30, MithrilIngot = 1 } } }, -- 2026-10-09
	},
	VisibleArrows = 7, -- 등의 화살통에 꽂혀 보이는 화살 수 (남은 화살이 이보다 적으면 그만큼만)
	NoticeInterval = 1.5, -- "화살이 없어요" 알림을 다시 띄우기까지(초)
	Tilt = 25, -- 등에 비스듬히 메는 각도(도). 화살 끝이 오른쪽 어깨 위로 나온다
}

-- 장비 겉모습 (GearVisualService): 끼운 장비가 캐릭터 몸에 보인다. 크기는 전부 몸 부위 크기에 대한 배율
Config.GearVisual = {
	Padding = 1.1, -- 손·발·몸통을 덮는 조각은 부위보다 이 배율만큼 크게
	HelmetScale = 1.18, -- 투구 둥근 껍데기 지름 = 머리 크기 × 이 값
	ArmorDepth = 1.25, -- 갑옷 몸통 덮개의 앞뒤 두께 = 몸통 두께 × 이 값
	PlateThickness = 0.12, -- 가슴판 두께 (몸통 두께 대비)
	CuffScale = 1.3, -- 장갑·장화 목 둘레 지름 (팔다리 굵기 대비)
	BraceletScale = 1.45, -- 팔찌 지름 (팔 굵기 대비). 장갑 목보다 커야 바깥에 보인다
	NecklaceGap = 0.05, -- 목걸이를 갑옷(또는 가슴) 앞으로 띄우는 거리 (몸통 두께 대비)
	GemSize = 0.12, -- 보석 크기 (부위 너비 대비)
	GemColor = Color3.fromRGB(120, 240, 255), -- 다이아몬드 장신구의 빛나는 보석 색
	GlowBrightness = 0.6, -- 장신구 보석의 은은한 빛 밝기
	GlowRange = 5, -- 그 빛이 닿는 거리(스터드)
	HideHairWithHelmet = true, -- 투구를 쓰면 머리카락·모자 액세서리를 숨긴다 (벗으면 되돌림)
	-- 장신구(목걸이·팔찌) 5단계 이상 겉모습 (2026-10-09). 몸통 색은 장비 Color(TierDefs), 여기는 테두리·장식·보석·빛. 없는 단계는 가장 높은 아래 단계 값
	-- Trim 테두리(챙·허리띠·줄), Accent 작은 장식, Gem 보석·빛 색, Wings 투구 큰 날개, Sparkle 반짝이 입자 수(1초에), Shoulder 어깨 뿔
	HighTiers = {
		[5] = { -- 미스릴: 은빛 파란 금속 + 파랗게 빛나는 테두리 (가볍고 날렵)
			Trim = Color3.fromRGB(70, 150, 255),
			TrimMat = Enum.Material.Neon,
			Accent = Color3.fromRGB(150, 210, 255),
			Gem = Color3.fromRGB(80, 170, 255),
			Wings = false,
			Sparkle = 3,
			Shoulder = false,
			GlowBrightness = 0.9,
			GlowRange = 7,
		},
		[6] = { -- 오리하르콘: 금빛 금속 + 주황빛 보석, 투구 날개·볏, 어깨 뿔, 반짝이 (묵직하고 화려)
			Trim = Color3.fromRGB(255, 225, 140),
			TrimMat = Enum.Material.Metal,
			Accent = Color3.fromRGB(255, 140, 40),
			Gem = Color3.fromRGB(255, 130, 30),
			Wings = true,
			Sparkle = 6,
			Shoulder = true,
			GlowBrightness = 1.2,
			GlowRange = 8,
		},
	},
	-- 방어구 세트 색·재질 (2026-10-10, 헬멧·갑옷·신발·장갑. 세트 Id = EquipmentDefs.Set). HighTiers는 이제 장신구만 쓴다
	-- Main 주 재질, Trim 띠·테두리, Accent 작은 장식(송곳니·징·뿔·수정), Gem 빛나는 부분(눈·핵·금), Glow 빛 밝기(0이면 없음)·GlowRange, Sparkle 반짝이·불티 입자 수(1초에)
	Sets = {
		Leather = { -- 가죽(슬라임): 갈색 가죽 + 천 테두리 + 금색 단추
			Main = Color3.fromRGB(140, 95, 60), MainMat = Enum.Material.Leather,
			Trim = Color3.fromRGB(95, 62, 38), TrimMat = Enum.Material.Fabric,
			Accent = Color3.fromRGB(225, 185, 95), AccentMat = Enum.Material.SmoothPlastic,
			Gem = Color3.fromRGB(225, 185, 95), Glow = 0, GlowRange = 0, Sparkle = 0,
		},
		Bone = { -- 뼈(스켈레톤): 상아색 뼈 + 가죽 끈 + 해골 눈구멍의 초록 빛
			Main = Color3.fromRGB(235, 228, 205), MainMat = Enum.Material.SmoothPlastic,
			Trim = Color3.fromRGB(92, 70, 50), TrimMat = Enum.Material.Leather,
			Accent = Color3.fromRGB(40, 30, 35), AccentMat = Enum.Material.SmoothPlastic,
			Gem = Color3.fromRGB(120, 255, 140), Glow = 0.4, GlowRange = 4, Sparkle = 0,
		},
		Cerberus = { -- 케르베로스: 짙은 털가죽 + 하얀 송곳니 장식 + 빨간 눈
			Main = Color3.fromRGB(70, 52, 60), MainMat = Enum.Material.Fabric,
			Trim = Color3.fromRGB(40, 30, 34), TrimMat = Enum.Material.Leather,
			Accent = Color3.fromRGB(250, 245, 230), AccentMat = Enum.Material.SmoothPlastic,
			Gem = Color3.fromRGB(255, 60, 40), Glow = 0.5, GlowRange = 4, Sparkle = 0,
		},
		Cyclops = { -- 사이클롭스: 두껍게 기운 올리브색 거대 가죽 + 굵은 바느질 + 투구의 큰 외눈
			Main = Color3.fromRGB(150, 138, 92), MainMat = Enum.Material.Leather,
			Trim = Color3.fromRGB(100, 84, 55), TrimMat = Enum.Material.Leather,
			Accent = Color3.fromRGB(235, 220, 175), AccentMat = Enum.Material.Fabric,
			Patch = Color3.fromRGB(180, 165, 110), -- 덧댄 가죽 조각
			Gem = Color3.fromRGB(255, 165, 40), Glow = 0.5, GlowRange = 5, Sparkle = 0,
		},
		Golem = { -- 바위 골렘: 회색 돌판 + 이끼 + 금 사이로 빛나는 초록빛 핵
			Main = Color3.fromRGB(122, 116, 108), MainMat = Enum.Material.Slate,
			Trim = Color3.fromRGB(80, 76, 72), TrimMat = Enum.Material.Rock,
			Accent = Color3.fromRGB(95, 140, 70), AccentMat = Enum.Material.Grass,
			Gem = Color3.fromRGB(80, 255, 170), Glow = 0.9, GlowRange = 6, Sparkle = 0,
		},
		Frost = { -- 서리 거인: 하얀 털 + 얼음 판 + 뾰족한 얼음 수정, 푸른 서리 빛·눈송이
			Main = Color3.fromRGB(232, 240, 250), MainMat = Enum.Material.Fabric,
			Trim = Color3.fromRGB(150, 205, 245), TrimMat = Enum.Material.Ice,
			Accent = Color3.fromRGB(175, 230, 255), AccentMat = Enum.Material.Glass,
			Gem = Color3.fromRGB(110, 200, 255), Glow = 1.0, GlowRange = 7, Sparkle = 4,
		},
		Behemoth = { -- 베헤모스: 검붉은 비늘 + 큰 뿔 + 갈라진 틈의 용암 불빛·불티
			Main = Color3.fromRGB(125, 26, 32), MainMat = Enum.Material.Slate,
			Trim = Color3.fromRGB(40, 14, 16), TrimMat = Enum.Material.CrackedLava,
			Accent = Color3.fromRGB(235, 215, 175), AccentMat = Enum.Material.SmoothPlastic, -- 뿔
			Gem = Color3.fromRGB(255, 110, 25), Glow = 1.3, GlowRange = 8, Sparkle = 6,
		},
	},
}

-- 차징: 모든 도구·무기는 누르고 있으면 모았다가 놓을 때 휘두른다
-- 활: 짧게 누르면 사거리·데미지가 줄고(BowTap*), 다 모으면 원래 사거리·데미지. 게이지가 보인다
-- 나머지(곡괭이·도끼·칼·방망이): 휘두르기 직전 자세로 멈추고 도구에 빛이 점점 커진다. 다 모으면 마나를 써서 강타(Multiplier배)
-- 모으는 동안은 달리기 모드여도 WalkSpeed로 천천히 걷는다
Config.Charge = {
	Time = 1.0, -- 다 모으는 데 걸리는 시간(초)
	TapThreshold = 0.2, -- 이보다 짧게 누르면 그냥 한 번 휘두르기(초)
	WalkSpeed = 8, -- 모으는 동안 걷는 속도
	Multiplier = 2.5, -- 다 모은 강타 데미지 배수 (활 제외). 2026-10-09 1.8 → 2.5
	ManaCost = 10, -- 강타에 쓰는 마나. 모자라면 보통 타격
	BowTapDamage = 0.5, -- 활을 짧게 쏘면 데미지 배수
	BowTapRange = 0.6, -- 활을 짧게 쏘면 사거리 배수
	-- 활은 다 모은 뒤 계속 누르면 2단계(마나가 모이는 추가 차징). 다 모이면 마나를 써서 강타
	BowOverTime = 1.0, -- 추가 차징에 걸리는 시간(초)
	BowOverMultiplier = 2.5, -- 추가 차징 강타 데미지 배수
	-- 활 시위를 당기는 거리(스터드, 시위 기준). 너무 당기면 왼손이 머리 뒤로 넘어가서 줄임 (2026-10-09)
	BowPullStart = 0.15, -- 누르자마자
	BowPullDistance = 0.45, -- 다 모았을 때 더 당기는 만큼
	GlowColor = Color3.fromRGB(255, 235, 170), -- 모을 때 도구 빛
	FullColor = Color3.fromRGB(255, 255, 255), -- 다 모였을 때 선명한 테두리
	MaxHold = 6, -- 서버: 이보다 오래 누른 기록은 무시(초)
	-- 강타가 맞았을 때 연출 (도끼 표와 같은 항목)
	Impact = { Color = Color3.fromRGB(255, 245, 210), Chunks = 8, Ring = 8, Shake = 2.2, Sparkle = true, Sparks = 24, Slash = true },
}

-- 음식: 먹으면 체력(Hp)·마나(Mana)를 채운다. 나중에 요리로 만든다 (지금은 상인 잡화에서 판다)
Config.Foods = {
	Bread = { Hp = 30 },
	ManaBerry = { Mana = 30 },
	LunchBox = { Hp = 60, Mana = 60 },
	-- 바다에서 잡는 음식 (2026-10-09): 마을 밖은 체력이 안 차니 사냥하다 먹는다
	FishMeat = { Hp = 20 }, -- 생선 (상어가 가끔 준다. 물고기는 2026-10-10 삭제)
	OctopusLeg = { Hp = 35, Mana = 10 }, -- 낙지 다리 (낙지)
}
Config.FoodCooldown = 10 -- 같은 음식을 다시 먹으려면 기다리는 시간(초). 칸 위에 시계 방향 덮개로 보인다 (2026-10-09)

-- 무기: 데미지·쿨다운(초)·사거리(스터드). 만드는 법(가격)은 Config.Recipes (2026-10-09 조합식으로 바뀜)
-- 칼은 빠르고, 방망이는 느리지만 세고 밀쳐 내고, 활은 약하지만 멀리서 쏜다
-- TODO(미정): 수치는 임시값. 플레이테스트로 조정
Config.Weapons = {
	WoodenSword = { Damage = 8, Cooldown = 0.5, Range = 7 }, -- 시작 지급
	CopperSword = { Damage = 13, Cooldown = 0.5, Range = 7.5 },
	IronSword = { Damage = 20, Cooldown = 0.5, Range = 8 },
	DiamondSword = { Damage = 32, Cooldown = 0.5, Range = 9 },
	WoodenBow = { Damage = 7, Cooldown = 0.8, Range = 40 },
	CopperBow = { Damage = 11, Cooldown = 0.8, Range = 45 },
	IronBow = { Damage = 17, Cooldown = 0.8, Range = 50 },
	DiamondBow = { Damage = 27, Cooldown = 0.8, Range = 55 },
	BaseballBat = { Damage = 12, Cooldown = 0.9, Range = 6.5, Knockback = 4 },
	GoblinClub = { Damage = 20, Cooldown = 0.9, Range = 6.5, Knockback = 5 },
	MorningStar = { Damage = 31, Cooldown = 0.9, Range = 7, Knockback = 6 },
	DiamondMace = { Damage = 48, Cooldown = 0.9, Range = 7.5, Knockback = 8 },
	-- 5단계 미스릴: 가볍고 빠름 (간격이 짧다) / 6단계 오리하르콘: 묵직하고 세다 (2026-10-09). TODO(미정): 임시값
	MithrilSword = { Damage = 48, Cooldown = 0.42, Range = 9.5 },
	OrichalcumSword = { Damage = 78, Cooldown = 0.5, Range = 10 },
	MithrilBow = { Damage = 40, Cooldown = 0.65, Range = 62 },
	OrichalcumBow = { Damage = 64, Cooldown = 0.8, Range = 68 },
	MithrilHammer = { Damage = 70, Cooldown = 0.75, Range = 8, Knockback = 9 },
	OrichalcumHammer = { Damage = 112, Cooldown = 0.95, Range = 8.5, Knockback = 11 },
}

-- 전투 공통 수치
Config.Combat = {
	CritChance = 0.12, -- 치명타 확률
	CritMultiplier = 1.6, -- 치명타 데미지 배수
	DamageSpread = 0.1, -- 데미지 ±10% 흔들림
	RangeTolerance = 2, -- 서버 거리 검사 여유(스터드)
	CooldownTolerance = 0.1, -- 서버 쿨다운 여유(초)
	ArrowSpeed = 140, -- 화살 날아가는 연출 속도(스터드/초)
	MobBroadcastRange = 120, -- 전투 연출을 받을 거리(스터드)
	HpBarRange = 45, -- 이 거리 안의 몹에 체력바 표시(스터드)
	BowAimAngle = 40, -- 활: 화면 가운데에서 이 각도(도) 안의 몹을 먼저 노린다
	CritBurnTime = 0.7, -- 치명타 불꽃이 타는 시간(초)
	-- 무기 티어별 타격 연출 (도끼 표와 같은 항목)
	TierEffects = {
		[1] = { Color = Color3.fromRGB(255, 240, 200), Chunks = 0, Ring = 2.5, Shake = 1, Sparkle = false, Sparks = 4, Slash = false },
		[2] = { Color = Color3.fromRGB(255, 150, 70), Chunks = 0, Ring = 3.5, Shake = 1.2, Sparkle = false, Sparks = 10, Slash = true },
		[3] = { Color = Color3.fromRGB(230, 235, 255), Chunks = 0, Ring = 4.5, Shake = 1.45, Sparkle = false, Sparks = 16, Slash = true },
		[4] = { Color = Color3.fromRGB(110, 235, 255), Chunks = 0, Ring = 6, Shake = 1.75, Sparkle = true, Sparks = 24, Slash = true },
		-- 5 미스릴: 파란 빛줄기 / 6 오리하르콘: 금빛 이중 고리 + 번쩍임(Flash = 빛 밝기) (2026-10-09). 없는 단계는 가장 높은 아래 단계 값
		[5] = { Color = Color3.fromRGB(110, 175, 255), Chunks = 0, Ring = 7.5, Shake = 1.95, Sparkle = true, Sparks = 30, Slash = true },
		[6] = { Color = Color3.fromRGB(255, 180, 60), Chunks = 0, Ring = 9, Shake = 2.2, Sparkle = true, Sparks = 40, Slash = true, DoubleRing = true, Flash = 4 },
	},
}

-- 몹 수치 (정의는 MobDefs). TODO(미정): 임시값
-- Hp 체력, Damage 한 번에 플레이어에게 주는 피해(플레이어 체력 100), AttackInterval 공격 간격(초), AttackRange 공격 거리
-- Speed 이동 속도(스터드/초), Aggro 플레이어를 알아채는 거리, Gold 골드 범위, Loot 전리품 개수 범위, Respawn 다시 나오는 시간(초)
-- Scale 모델 크기 배율. 생성 자리·마리 수는 Config.MobZones (몹 구역)
-- Passive = true면 먼저 공격하지 않고, 맞으면 FleeTime초 동안 때린 사람 반대쪽으로 Speed × FleeSpeed로 도망친다 (피해 0)
-- 전리품: 주 전리품 = MobDefs.LootId를 Loot개. ExtraLoot = 두 번째 전리품 목록 { Id, Chance 확률, Count 개수 범위 } (2026-10-09)
--   몹마다 방어구 재료가 하나씩 나온다: 슬라임 젤리 / 뼈다귀 / 낡은 천 / 케르베로스 털가죽 / 사이클롭스 가죽. 보스는 Config.MobBoss.ExtraLoot도
Config.Mobs = {
	Slime = { Hp = 20, Damage = 0, AttackInterval = 1.5, AttackRange = 3.5, Speed = 7, Aggro = 18, Gold = { 2, 5 }, Loot = { 1, 2 }, Respawn = 10, Scale = 0.9, Passive = true, FleeTime = 4, FleeSpeed = 1.5 },
	Skeleton = { Hp = 40, Damage = 8, AttackInterval = 1.4, AttackRange = 4, Speed = 9, Aggro = 22, Gold = { 5, 9 }, Loot = { 1, 2 }, Respawn = 18, Scale = 1 },
	Zombie = { Hp = 55, Damage = 10, AttackInterval = 1.6, AttackRange = 4, Speed = 6, Aggro = 20, Gold = { 7, 12 }, Loot = { 1, 2 }, Respawn = 18, Scale = 1 },
	Cerberus = {
		Hp = 90, Damage = 14, AttackInterval = 1.2, AttackRange = 4.5, Speed = 13, Aggro = 26, Gold = { 14, 24 }, Loot = { 1, 2 }, Respawn = 30, Scale = 1.1,
		ExtraLoot = { { Id = "CerberusHide", Chance = 0.85, Count = { 1, 2 } } }, -- 2026-10-10 사용자 요청 "케르베로스 가죽도" 확인: 털가죽 85%로 1~2장, 주 전리품 송곳니는 그대로
	},
	-- 사이클롭스: 플레이어 키의 약 1.9배 (모델 높이 약 7.2 × Scale 1.4 ≈ 10스터드)
	Cyclops = {
		Hp = 160, Damage = 18, AttackInterval = 1.8, AttackRange = 6.5, Speed = 9, Aggro = 26, Gold = { 25, 40 }, Loot = { 1, 3 }, Respawn = 45, Scale = 1.4,
		ExtraLoot = { { Id = "CyclopsHide", Chance = 0.85, Count = { 1, 3 } } },
	},
	-- 스켈레톤 궁수 (2026-10-10): Ranged가 있으면 활을 쏘는 몹. 가까이 오면 뒤로 물러나고(KeepAway), Range 안에서 AttackInterval마다 쏜다
	--   Ranged: Range 쏘는 거리, KeepAway 이보다 가까우면 물러남, ArrowSpeed 화살 속도(스터드/초, 날아가는 동안 피할 수 있다),
	--   HitRadius 화살이 떨어질 때 이 반경 안에 있으면 맞음, Lead 움직이는 사람 앞을 노리는 정도(0 = 지금 자리, 1 = 도착할 자리),
	--   RetreatSpeed 물러날 때 속도 배율. 데미지는 Damage (구르기 무적이면 "피함!")
	SkeletonArcher = {
		Hp = 32, Damage = 7, AttackInterval = 2.2, AttackRange = 4, Speed = 8, Aggro = 32, Gold = { 6, 11 }, Loot = { 1, 2 }, Respawn = 22, Scale = 1,
		Ranged = { Range = 30, KeepAway = 12, ArrowSpeed = 45, HitRadius = 3.5, Lead = 0.5, RetreatSpeed = 0.9 },
		ExtraLoot = { { Id = "WoodQuiver", Chance = 0.05, Count = { 1, 1 } } }, -- 아주 가끔 나무 화살통
	},
	-- 거대 몬스터 (2026-10-10): 사이클롭스(플레이어 키 약 1.9배)보다 크다 = 골렘 약 2.3배 / 서리 거인 약 2.7배 / 베헤모스 약 3.2배
	-- Specials: 큰 기술 목록 (차례로 돌아가며 쓴다). 대상이 Trigger 거리 안이고 Cooldown이 지났으면 Windup초 동안 바닥에 빨간 표시 → 그 뒤 판정
	--   Kind "Slam" 대상 자리 내려찍기(둘레 Radius) / "Stomp" 내 둘레 발구르기(Radius) / "Charge" 대상 쪽으로 Distance만큼 Speed로 돌진(폭 Width, 닿으면 Damage)
	--   BossScale: 이 몹이 보스가 될 때 크기 범위 (없으면 Config.MobBoss.Scale. 거인은 이미 커서 작게)
	--   Damage는 보스면 크기만큼, Radius·Width·Distance도 크기만큼. 기절(방망이 내려찍기)하면 준비하던 기술이 취소된다. 구르기 무적이면 피한다
	StoneGolem = {
		Hp = 380, Damage = 26, AttackInterval = 2.0, AttackRange = 8, Speed = 7, Aggro = 28, Gold = { 50, 80 }, Loot = { 1, 3 }, Respawn = 70, Scale = 1.6, BossScale = { 1.2, 1.5 },
		Specials = { { Kind = "Slam", Trigger = 18, Cooldown = 7, Windup = 1.1, Radius = 9, Damage = 34 } },
		ExtraLoot = { { Id = "GolemCore", Chance = 0.3, Count = { 1, 1 } } },
	},
	FrostGiant = {
		Hp = 560, Damage = 32, AttackInterval = 2.0, AttackRange = 9, Speed = 8, Aggro = 30, Gold = { 80, 120 }, Loot = { 1, 3 }, Respawn = 90, Scale = 1.8, BossScale = { 1.2, 1.5 },
		Specials = { { Kind = "Stomp", Trigger = 14, Cooldown = 8, Windup = 1.3, Radius = 14, Damage = 40 } },
		ExtraLoot = { { Id = "FrostCrystal", Chance = 0.3, Count = { 1, 1 } } },
	},
	-- 베헤모스: 7단계라 6단계 무기로도 0.4배 (Config.TierWall). 돌진과 발구르기를 번갈아 쓴다
	Behemoth = {
		Hp = 700, Damage = 38, AttackInterval = 2.2, AttackRange = 14, Speed = 8, -- 몸이 길어서(반지름 약 11) 공격 거리도 길게 Aggro = 32, Gold = { 120, 180 }, Loot = { 1, 3 }, Respawn = 120, Scale = 2.0, BossScale = { 1.2, 1.4 },
		Specials = {
			{ Kind = "Charge", Trigger = 30, Cooldown = 6, Windup = 1.2, Distance = 30, Speed = 42, Width = 7, Damage = 46 },
			{ Kind = "Stomp", Trigger = 13, Cooldown = 6, Windup = 1.2, Radius = 13, Damage = 40 },
		},
		ExtraLoot = { { Id = "BehemothHorn", Chance = 0.25, Count = { 1, 1 } } },
	},
	-- 바다 생물 (2026-10-09): Swim = true면 지형 물 속을 헤엄친다 (헤엄 수치 Config.SeaAI, 사는 곳 Config.SeaZones)
	--   Retaliate = true: 먼저 덤비지 않지만 맞으면 쫓아와 때린다 (낙지)
	--   Drift = true: 쫓지도 도망치지도 않고 둥둥 떠다니다 몸에 닿은(AttackRange) 사람을 쏜다 (해파리)
	--   Prick: 맞으면 PuffTime초 동안 PuffScale배로 부풀고, Range 안(칼·방망이 거리)에서 때린 사람을 Damage만큼 찌른다 (Cooldown초마다, 복어)
	--   Ink: 맞으면 Chance 확률로 먹물을 뿜는다 (Cooldown초마다, 때린 사람 화면이 Blind초 동안 어두워짐, 낙지)
	--   ChargeSpeed·ChargeRange: 대상이 ChargeRange 안이면 속도 ChargeSpeed배로 돌진 (상어)
	-- (물고기·복어·황금 물고기는 2026-10-10 사용자 요청으로 삭제. Prick은 지금 쓰는 몹이 없다)
	Octopus = {
		Hp = 70, Damage = 9, AttackInterval = 1.3, AttackRange = 5, Speed = 7, Aggro = 22, Gold = { 10, 18 }, Loot = { 1, 3 }, Respawn = 25, Scale = 1, Swim = true, Retaliate = true,
		Ink = { Chance = 0.35, Cooldown = 6, Blind = 1.5 },
		ExtraLoot = { { Id = "InkSac", Chance = 0.7, Count = { 1, 1 } } },
	},
	Jellyfish = { Hp = 30, Damage = 5, AttackInterval = 1.2, AttackRange = 3.5, Speed = 2.5, Aggro = 0, Gold = { 4, 9 }, Loot = { 1, 2 }, Respawn = 20, Scale = 1, Swim = true, Drift = true },
	-- 상어: 멀고 깊은 바다를 돌아다니다 물에 들어온 사람에게 돌진해 문다
	Shark = {
		Hp = 140, Damage = 15, AttackInterval = 1.5, AttackRange = 8, Speed = 11, Aggro = 26, Gold = { 25, 40 }, Loot = { 1, 2 }, Respawn = 45, Scale = 2.6, Swim = true, -- 2026-10-09 크기 1.3 → 2.6 (2배), 무는 거리 5.5 → 8
		ChargeSpeed = 1.8, ChargeRange = 14,
		ExtraLoot = { { Id = "SharkSkin", Chance = 0.85, Count = { 1, 2 } }, { Id = "FishMeat", Chance = 0.4, Count = { 1, 2 } } },
	},
}

-- 바다 생물 사는 곳 (2026-10-09). 제작 스크립트(studio/BuildWeaponsAndMobs)가 게임 시작 때 지형 물을 찾아 구역마다 생성 자리를 둔다
-- Distance 마을(TownArrival)에서 잰 구역 가운데 거리 범위(스터드, 벗어날수록 점수가 깎임), Depth 물 깊이 범위(수면 ~ 바닥, 스터드)
-- Radius 구역 반경, Count 주인 몹 자리 수. Schools·SchoolSize가 있으면 Count 대신 떼(자리 하나에 SchoolSize마리, 같이 헤엄침)
-- Extras 같은 구역에 따로 두는 몹 { 몹 = 마리 }, BossSpots 보스가 잘 나오는 자리 수 (Config.MobBoss.SpotChance)
Config.SeaZones = {
	-- (얕은 바다 = 물고기 떼·복어·황금 물고기 구역은 2026-10-10 물고기 삭제와 함께 뺐다)
	{ Name = "낙지 바위", MobType = "Octopus", Count = 4, Extras = { Jellyfish = 3 }, Distance = { 80, 280 }, Depth = { 6, 40 }, Radius = 35, BossSpots = 1 },
	{ Name = "깊은 바다", MobType = "Shark", Count = 3, Extras = { Octopus = 1 }, Distance = { 140, 450 }, Depth = { 10, 999 }, Radius = 45, BossSpots = 1 },
}
-- 물 찾기 (제작 스크립트): 마을 둘레 ScanRadius를 ScanStep 격자로 아래로 광선 → 지형 물에 맞으면 수면, 물을 무시한 두 번째 광선으로 바닥
Config.SeaSpawn = {
	ScanRadius = 600, -- 마을에서 이 거리까지 물을 찾는다 (스터드)
	ScanStep = 8, -- 광선 간격 (스터드)
	ScanTop = 400, -- 광선 시작 높이 (마을 높이 + 이만큼)
	MaxDepth = 300, -- 바닥을 찾는 최대 깊이
	MinDepth = 4, -- 이보다 얕은 물에는 안 둔다 (헤엄칠 틈)
	MinCells = 6, -- 구역 가운데 둘레(Radius)에 물 칸이 이만큼은 있어야 구역으로 고른다
	MaxCandidates = 1500, -- 넓은 바다면 구역 가운데 후보를 무작위로 이만큼만 본다 (시작이 느려지지 않게)
	ZoneGap = 45, -- 바다 구역 가운데끼리 최소 거리
	SpotGap = 8, -- 생성 자리끼리 최소 거리 (떼 안의 물고기는 SchoolSpread 안에 모인다)
	SchoolSpread = 3, -- 떼 물고기끼리 흩어진 정도 (스터드)
}
-- 헤엄 (서버 MobService): 몸이 수면 아래·바닥 위에 있게 한다. 물 기둥(수면·바닥 높이)은 ColumnCell 칸마다 한 번 재고 기억한다
Config.SeaAI = {
	ColumnCell = 4, -- 물 기둥을 재는 칸 크기 (스터드)
	ScanTop = 400, -- 물 기둥 광선 시작 높이 (월드 Y)
	ScanLength = 900, -- 광선 길이
	SurfaceMargin = 0.6, -- 몸 위쪽이 수면에서 이만큼 아래
	FloorMargin = 0.5, -- 몸 아래가 바닥에서 이만큼 위
	Leash = 40, -- 집에서 이 거리를 넘게 쫓으면 포기
	WanderRadius = 14, -- 한가할 때 집 둘레를 헤엄치는 반경 (위아래도)
	WanderPause = { 0.5, 2.5 }, -- 헤엄 사이 쉬는 시간 범위(초)
	SchoolRetarget = { 3, 6 }, -- 물고기 떼가 다음 목적지를 고르는 간격(초)
	PlayerWaterAbove = 3, -- 플레이어 뿌리가 수면에서 이만큼 위까지는 "물 속"으로 본다 (수면에서 헤엄치는 중)
	MinChaseRange = 20, -- 쫓는 걸 포기하는 거리 = max(Aggro, 이 값) × 2
	MaxPitch = 30, -- 위아래로 기우는 최대 각도(도)
	WiggleAngle = 12, -- 물고기 꼬리 흔들기 각도(도)
	WiggleSpeed = 9, -- 흔들기 빠르기 (움직일 때)
	PulseBob = 0.45, -- 낙지·해파리 둥실 높이
	PulseSpeed = 2.4, -- 둥실 빠르기
}

-- 몹 구역 (2026-10-09, 같은 날 넓게 펼침): 마을에서 가까우면 슬라임, 조금 멀면 스켈레톤·좀비, 꽤 멀면 케르베로스·사이클롭스
-- 구역 = 마을을 둘러싼 고리의 한 조각(부채꼴). Distance 생성 자리가 놓일 마을(TownArrival) 거리 범위(스터드),
--   Arc 구역이 차지하는 방향 폭(도). 띠끼리 거리가 조금 겹쳐서 경계가 딱 끊기지 않는다
-- Count 생성 자리 수, BossSpots 보스가 잘 나오는 자리 수 (Config.MobBoss.SpotChance)
-- Mix 자리마다 이웃 단계 몹이 대신 설 확률 (나머지는 MobType). 예: { Skeleton = 0.04 } = 4%는 스켈레톤
-- 맵이 Config.WorldTiers.MapRadius보다 좁으면 거리를 그 비율로 줄인다
-- 제작 스크립트(studio/BuildWeaponsAndMobs)가 게임 시작 때 구역 방향과 생성 자리를 고른다
Config.MobZones = {
	-- 가까운 띠: 슬라임 (아주 가끔 스켈레톤·좀비)
	{ Name = "슬라임 들판", MobType = "Slime", Count = 11, Distance = { 80, 150 }, Arc = 70, BossSpots = 1, Mix = { Skeleton = 0.04 } },
	{ Name = "슬라임 언덕", MobType = "Slime", Count = 10, Distance = { 80, 150 }, Arc = 65, BossSpots = 1, Mix = { Zombie = 0.04 } },
	{ Name = "슬라임 연못", MobType = "Slime", Count = 9, Distance = { 85, 155 }, Arc = 60, BossSpots = 1, Mix = { Skeleton = 0.04 } },
	-- 중간 띠: 스켈레톤·좀비 (가끔 슬라임, 아주 가끔 케르베로스)
	-- Extras: 구역 안에 따로 두는 몹 { 몹 = 마리 } (Mix와 상관없이 그 수만큼, 2026-10-10 스켈레톤 궁수)
	{ Name = "스켈레톤 무덤", MobType = "Skeleton", Count = 9, Distance = { 135, 210 }, Arc = 60, BossSpots = 1, Mix = { Zombie = 0.15, Slime = 0.08, Cerberus = 0.04 }, Extras = { SkeletonArcher = 4 } },
	{ Name = "좀비 숲", MobType = "Zombie", Count = 9, Distance = { 135, 210 }, Arc = 60, BossSpots = 1, Mix = { Skeleton = 0.15, Slime = 0.08, Cerberus = 0.04 } },
	-- 먼 띠: 케르베로스·사이클롭스 (가끔 스켈레톤·좀비)
	{ Name = "케르베로스 굴", MobType = "Cerberus", Count = 5, Distance = { 195, 280 }, Arc = 55, BossSpots = 1, Mix = { Skeleton = 0.08, Zombie = 0.08, Cyclops = 0.06 } },
	{ Name = "사이클롭스 골짜기", MobType = "Cyclops", Count = 4, Distance = { 215, 300 }, Arc = 55, BossSpots = 1, Mix = { Cerberus = 0.2 } },
	-- 아주 먼 띠 (2026-10-10): 거대 몬스터. 사이클롭스보다 멀리, 몇 마리만. 땅이 모자라면 제작 스크립트가 거리를 조금씩 당겨 다시 찾는다 (FallbackShrink)
	{ Name = "바위 골렘 돌무덤", MobType = "StoneGolem", Count = 3, Distance = { 280, 350 }, Arc = 45, BossSpots = 0 },
	{ Name = "서리 거인 얼음벌판", MobType = "FrostGiant", Count = 3, Distance = { 320, 400 }, Arc = 45, BossSpots = 0 },
	{ Name = "베헤모스 둥지", MobType = "Behemoth", Count = 2, Distance = { 370, 450 }, Arc = 40, BossSpots = 0 },
}
Config.MobZoneLayout = {
	ArcGap = 12, -- 같은 띠 구역끼리 방향 사이 여유(도). 서로 안 겹치게
	SpawnGap = 14, -- 생성 자리끼리 최소 거리 (2026-10-09: 7 → 14, 몹이 너무 붙어 있어서)
	ObstacleGap = 25, -- 광산 입구 같은 시설에서 떨어질 거리
	NodeGap = 5, -- 나무·바위 생성 자리에서 떨어질 거리
	-- 구역 자리를 다 못 채우면(맵 끝 너머라 땅이 없음) 거리를 이 배율로 차례로 당겨 다시 찾는다 (2026-10-10, 먼 거대 몬스터 구역용)
	FallbackShrink = { 0.92, 0.85, 0.78 },
}

-- 보스 몹 (2026-10-09): 생성(다시 생성 포함)될 때마다 Chance 확률로 보스가 된다. 보스 자리는 SpotChance
-- 크기 = Scale 범위에서 랜덤. 체력 × HpPerScale × 크기, 공격 × DamagePerScale × 크기, 골드 × GoldPerScale × 크기, 전리품 × LootPerScale × 크기
Config.MobBoss = {
	Chance = 0.04,
	SpotChance = 0.5,
	Scale = { 1.5, 3 },
	HpPerScale = 2.5, -- 크기 2배면 체력 5배
	DamagePerScale = 0.8, -- 크기 2배면 공격 1.6배
	GoldPerScale = 2.5,
	LootPerScale = 1.5,
	SpeedMultiplier = 0.85, -- 덩치가 커서 조금 느리다
	RespawnMultiplier = 2, -- 보스를 잡은 자리는 더 늦게 다시 나온다
	NamePrefix = "👑 보스 ",
	NameColor = Color3.fromRGB(255, 205, 60),
	HpBarScale = 1.6, -- 체력바 크기 배율
	HpBarRangeMultiplier = 2, -- 체력바가 보이는 거리 배율
	-- 보스만 주는 전리품 (2026-10-09): 보스의 증표 = 6단계 방어구·거인망치 재료. 어느 몹 보스든 나온다 (크기와 상관없이 Count개)
	ExtraLoot = { { Id = "BossToken", Chance = 1, Count = { 1, 2 } } },
}
Config.MobAI = {
	TickRate = 15, -- 1초에 몇 번 생각하고 움직이는지
	Leash = 35, -- 집(생성 자리)에서 이 거리를 넘게 쫓아가면 포기하고 돌아간다
	WanderRadius = 10, -- 한가할 때 집 주변을 어슬렁거리는 반경
	WanderPause = { 1.5, 4 }, -- 어슬렁 사이 쉬는 시간 범위(초)
	HopHeight = 1.2, -- 슬라임 튀는 높이
	WalkBob = 0.15, -- 걸을 때 위아래 흔들림
	LungeDistance = 0.8, -- 공격할 때 앞으로 들이받는 거리
	KnockbackTime = 0.2, -- 방망이에 맞아 밀려나는 시간(초)
	-- 마을 안전지대: 마을 도착점(TownArrival)과 NPC(ShopNPC) 둘레 이 반경(스터드) 안에는 몹이 생기지 않고 들어오지도 않는다
	SafeZoneRadius = 55,
	SafeZoneSpawnMargin = 20, -- 생성 자리는 안전지대 바깥으로 이만큼 더 떨어뜨린다
}

-- 가방: 칸 단위. 쌓이는 아이템(광석·괴)은 한 칸에 MaxStack개까지, 도구는 1개가 1칸
Config.Inventory = {
	StartSlots = 20, -- 처음 가방 칸 수 (2026-10-10 10 → 20)
	BagShopEnabled = false, -- 상인에게서 가방 확장을 살 수 있는지 (2026-10-10 우선 못 사게)
	MaxStack = 99, -- 한 칸에 쌓이는 최대 개수
	-- 상인에게 사는 가방 확장 (순서대로 하나씩). TODO(미정): 가격은 임시값
	BagUpgrades = {
		{ Name = "작은 가죽 가방", Slots = 15, Price = 40 },
		{ Name = "튼튼한 가방", Slots = 20, Price = 150 },
		{ Name = "광부의 큰 가방", Slots = 30, Price = 500 },
	},
	HotbarSlots = 5, -- 하단 빠른 호출 칸 수
}

-- 테스트용 설정 (Studio에서만 적용)
-- 저장 (DataService, 2026-10-09)
Config.Save = {
	StoreName = "PlayerData_v1", -- 실제 게임 저장소 이름
	StudioStoreName = "PlayerData_Studio_v3", -- Studio 테스트 저장소 (테스트 지급이 실제 저장에 섞이지 않게). 2026-10-09 v1 → v2: 새로 시작. 2026-10-10 v2 → v3: 테스트 아이템이 쌓여서 돌 곡괭이 하나로 새로 시작
	AutoSaveInterval = 60, -- 자동 저장 간격(초)
	Retries = 3, -- 실패하면 다시 시도하는 횟수
	LockTimeout = 90, -- 다른 서버의 잠금이 이 초보다 오래됐으면 버려진 것으로 본다
	LockWaitTries = 4, -- 잠겨 있으면 몇 번 기다렸다 다시 시도하는지
	LockWaitSeconds = 3, -- 기다리는 간격(초)
	CleanupDelay = 5, -- 나간 뒤 가방·장비 정보를 지우기 전 기다리는 시간(초). 저장이 먼저 모아 가도록
}

-- 처음 들어오면 받는 도구 (2026-10-09: 돌 곡괭이 하나만. 나머지는 돌을 캐서 팔고 직접 산다)
Config.StarterTools = { "StonePickaxe" }

Config.Debug = {
	-- 2026-10-09 사용자 요청: 테스트도 처음부터 직접 구해서 하도록 테스트 지급을 전부 끔 (다시 켜려면 true / 숫자)
	GiveAllPickaxes = false, -- true면 들어올 때 도구·무기를 전부 지급 (테스트용)
	StartSlots = 100, -- Studio 테스트 때 가방 칸 수 (도구·무기 30 + 장비 36 + 화살통·음식을 전부 받으면 70칸이 넘는다, 2026-10-09 60 → 100)
	GiveAllEquipment = false, -- Studio에서 들어오면 장비(방어구 4칸 × 7세트 + 장신구 2칸 × 6단계 = 40종)를 전부 지급 (테스트용)
	GiveFoods = 0, -- Studio에서 들어오면 음식을 종류마다 이만큼 지급. 테스트 끝나면 0
	GiveQuivers = 0, -- Studio에서 처음 들어오면 화살통을 종류마다 이만큼 지급. 테스트 끝나면 0
	-- TODO(임시, 테스트 끝나면 지우기): 상점 아이콘(또는 재료 그림)을 빨리 3번 누르면 그 아이템을 공짜로 받는다 (Studio 전용, 2026-10-10 사용자 요청)
	-- 클라 ShopUI가 세 번 누름을 알아채 DebugShopGrant를 보내고, 서버 CraftingService가 Studio·이 값·NPC 거리를 확인한 뒤 준다
	ShopTripleClickFree = true,
	ShopTripleClickWindow = 0.8, -- 이 초 안에 3번 눌러야 한다
	ShopFreeStackAmount = 10, -- 쌓이는 아이템(광석·괴·재료·음식)은 한 번에 이만큼, 도구·무기·장비는 1개
}

-- 화면 가장자리 작은 버튼 위치 (QuickButtonsHUD)
Config.QuickButtons = {
	MusicPosition = UDim2.fromOffset(96, 18), -- 왼쪽 위 가방 그림 오른쪽
	MusicSize = 40,
	ReturnPosition = UDim2.new(0, 16, 0.4, 0), -- 왼쪽 가운데 (공격 버튼·가방과 멀리)
	ReturnSize = UDim2.fromOffset(120, 44),
}

-- 귀환 버튼(왼쪽, 2026-10-09 주문서 대신): 누르면 CastTime초 뒤 마을(태그 TownArrival)로. 그사이 움직이거나 다시 누르면 취소
Config.ReturnHome = {
	CastTime = 2.5,
	CancelMoveDistance = 2, -- 이만큼(스터드) 움직이면 취소
	Cooldown = 20, -- 한 번 돌아온 뒤 다시 쓰기까지(초)
}

-- 상인이 파는 잡화 (순서대로 표시). TODO(미정): 가격은 임시값
Config.MerchantGoods = {
	{ ItemId = "Bread", Price = 8 },
	{ ItemId = "ManaBerry", Price = 8 },
	{ ItemId = "LunchBox", Price = 25 },
}

-- 상인에게 파는 가격(골드). 여기 없는 아이템은 팔 수 없다
Config.SellPrices = {
	Stone = 1,
	Coal = 2,
	CopperOre = 3,
	IronOre = 6,
	Mithril = 15,
	Orichalcum = 60,
	CopperIngot = 12,
	IronIngot = 20,
	SteelIngot = 60,
	MithrilIngot = 45, -- 2026-10-09
	OrichalcumIngot = 200,
	Pine = 1, -- 통나무
	Oak = 2,
	Birch = 4,
	Maple = 8,
	Ebony = 25,
	SlimeJelly = 2, -- 몹 전리품
	Bone = 4,
	OldCloth = 5,
	CerberusFang = 12,
	CyclopsEye = 20,
	CerberusHide = 14, -- 두 번째 전리품 (2026-10-09)
	CyclopsHide = 22,
	BossToken = 50, -- 보스만 준다
	FishMeat = 3, -- 바다 생물 전리품 (2026-10-09). 생선은 지금 상어가 준다
	-- 거대 몬스터 전리품 (2026-10-10): 방어구 재료 (주 전리품 / 두 번째 전리품)
	GolemPlate = 30,
	GolemCore = 70,
	FrostHide = 45,
	FrostCrystal = 100,
	BehemothScale = 65,
	BehemothHorn = 150,
	OctopusLeg = 8,
	InkSac = 10,
	JellyfishJelly = 6,
	SharkTooth = 18,
	SharkSkin = 20,
}

-- 대장장이 제련: 재료 + 수수료(골드) → 결과 1개
-- TODO(미정): 수수료는 임시값
Config.Smelting = {
	Order = { "CopperIngot", "IronIngot", "SteelIngot", "MithrilIngot", "OrichalcumIngot" }, -- UI 표시 순서
	Recipes = {
		CopperIngot = { Inputs = { CopperOre = 2, Coal = 1 }, Fee = 2 },
		IronIngot = { Inputs = { IronOre = 2, Coal = 1 }, Fee = 4 },
		SteelIngot = { Inputs = { IronIngot = 2, Coal = 2 }, Fee = 10 },
		-- 광산 3층 광석 (2026-10-09): 미스릴괴는 5단계, 오리하르콘괴는 6단계 재료
		MithrilIngot = { Inputs = { Mithril = 2, Coal = 2 }, Fee = 20 },
		OrichalcumIngot = { Inputs = { Orichalcum = 2, Coal = 3, MithrilIngot = 1 }, Fee = 40 },
	},
}

-- 조합식 (2026-10-09 사용자 요청): 도구·무기·장비 만드는 법. 키 = 만들어지는 아이템 Id
-- 1단계(From 없음): 골드 + 재료 조금으로 산다 (여러 개 살 수 있다)
-- 2단계부터: 같은 종류(칸) 바로 아래 단계 From.Count개 + 재료 Items + 골드 Gold → 1개. 실패 확률 없음
--   From.Count: 모든 단계 2개 (2026-10-10 사용자 결정: 4단계 전까지도 3개 → 2개)
-- 재료 원칙 (2026-10-09 사용자 결정):
--   도구·무기·장신구(목걸이·팔찌) = 광물(광석·괴) + 통나무 (+ 무기는 가끔 귀한 몹 부위: 송곳니·눈알·보스의 증표)
--   방어구(헬멧·갑옷·신발·장갑) = 몹 세트 (2026-10-10): 가죽 → 뼈 → 케르베로스 → 사이클롭스 → 바위 골렘 → 서리 거인 → 베헤모스(7단계), 그 몹 재료가 주재료
-- 재료는 그 단계 직전 도구·무기로 구할 수 있는 것 위주 (예: 미스릴 곡괭이에는 다이아몬드 곡괭이로 캐는 미스릴괴, 오리하르콘은 미스릴 곡괭이로 캔다)
-- 대장장이가 곡괭이·도끼, 사냥꾼이 칼·활·방망이·장비를 만든다. 화살통은 Config.Quiver
-- TODO(미정): 숫자는 임시값. 플레이테스트로 조정
export type Recipe = { From: { Id: string, Count: number }?, Items: { [string]: number }, Gold: number }
local RECIPES: { [string]: Recipe } = {
	-- 곡괭이 (돌 → 구리 → 철 → 다이아몬드 → 미스릴 → 오리하르콘)
	StonePickaxe = { Gold = 5, Items = { Stone = 3, Pine = 2 } },
	CopperPickaxe = { From = { Id = "StonePickaxe", Count = 2 }, Gold = 30, Items = { Stone = 10, Oak = 4 } },
	IronPickaxe = { From = { Id = "CopperPickaxe", Count = 2 }, Gold = 150, Items = { CopperIngot = 6, Coal = 8, Birch = 4 } },
	SteelPickaxe = { From = { Id = "IronPickaxe", Count = 2 }, Gold = 600, Items = { SteelIngot = 5, IronIngot = 8, Coal = 15, Maple = 6 } },
	MithrilPickaxe = { From = { Id = "SteelPickaxe", Count = 2 }, Gold = 1800, Items = { MithrilIngot = 6, SteelIngot = 6, Coal = 20, Ebony = 3 } },
	OrichalcumPickaxe = { From = { Id = "MithrilPickaxe", Count = 2 }, Gold = 4500, Items = { OrichalcumIngot = 4, MithrilIngot = 8, SteelIngot = 6, Ebony = 6 } },
	-- 도끼
	StoneAxe = { Gold = 5, Items = { Stone = 5 } }, -- 처음엔 곡괭이만 있으니 통나무 없이 (돌 캐서 팔고 → 도끼)
	CopperAxe = { From = { Id = "StoneAxe", Count = 2 }, Gold = 30, Items = { CopperIngot = 2, Oak = 6 } },
	IronAxe = { From = { Id = "CopperAxe", Count = 2 }, Gold = 150, Items = { IronIngot = 4, Birch = 8, Coal = 5 } },
	DiamondAxe = { From = { Id = "IronAxe", Count = 2 }, Gold = 600, Items = { SteelIngot = 5, IronIngot = 6, Maple = 10, Birch = 10 } },
	MithrilAxe = { From = { Id = "DiamondAxe", Count = 2 }, Gold = 1800, Items = { MithrilIngot = 5, SteelIngot = 5, Maple = 12, Ebony = 4 } },
	OrichalcumAxe = { From = { Id = "MithrilAxe", Count = 2 }, Gold = 4500, Items = { OrichalcumIngot = 3, MithrilIngot = 6, Ebony = 10, Maple = 15 } },
	-- 칼 (광물 + 통나무, 높은 단계는 귀한 몹 부위 조금)
	WoodenSword = { Gold = 5, Items = { Pine = 4 } },
	CopperSword = { From = { Id = "WoodenSword", Count = 2 }, Gold = 40, Items = { CopperIngot = 3, Oak = 3 } },
	IronSword = { From = { Id = "CopperSword", Count = 2 }, Gold = 180, Items = { IronIngot = 5, CopperIngot = 2, Birch = 4 } },
	DiamondSword = { From = { Id = "IronSword", Count = 2 }, Gold = 700, Items = { SteelIngot = 6, IronIngot = 6, CerberusFang = 4, CyclopsEye = 2 } },
	MithrilSword = { From = { Id = "DiamondSword", Count = 2 }, Gold = 2000, Items = { MithrilIngot = 6, SteelIngot = 4, Ebony = 2, CerberusFang = 2, SharkTooth = 4 } }, -- 상어 이빨 (2026-10-09)
	OrichalcumSword = { From = { Id = "MithrilSword", Count = 2 }, Gold = 5000, Items = { OrichalcumIngot = 4, MithrilIngot = 6, CyclopsEye = 4, BossToken = 1 } },
	-- 활
	WoodenBow = { Gold = 5, Items = { Pine = 5 } },
	CopperBow = { From = { Id = "WoodenBow", Count = 2 }, Gold = 40, Items = { CopperIngot = 2, Oak = 5 } },
	IronBow = { From = { Id = "CopperBow", Count = 2 }, Gold = 180, Items = { IronIngot = 4, Birch = 6, Maple = 3 } },
	DiamondBow = { From = { Id = "IronBow", Count = 2 }, Gold = 700, Items = { SteelIngot = 5, Maple = 8, Ebony = 2, CerberusFang = 4 } },
	MithrilBow = { From = { Id = "DiamondBow", Count = 2 }, Gold = 2000, Items = { MithrilIngot = 4, Ebony = 4, Maple = 10, CerberusFang = 3 } },
	OrichalcumBow = { From = { Id = "MithrilBow", Count = 2 }, Gold = 5000, Items = { OrichalcumIngot = 3, MithrilIngot = 4, Ebony = 8, CyclopsEye = 3 } },
	-- 방망이 (6단계 오리하르콘 거인망치는 보스의 증표가 들어간다)
	BaseballBat = { Gold = 5, Items = { Oak = 4 } },
	GoblinClub = { From = { Id = "BaseballBat", Count = 2 }, Gold = 40, Items = { CopperIngot = 3, Oak = 5 } },
	MorningStar = { From = { Id = "GoblinClub", Count = 2 }, Gold = 180, Items = { IronIngot = 6, Coal = 6, Oak = 10 } },
	DiamondMace = { From = { Id = "MorningStar", Count = 2 }, Gold = 700, Items = { SteelIngot = 7, IronIngot = 5, CyclopsEye = 3, Maple = 6 } },
	MithrilHammer = { From = { Id = "DiamondMace", Count = 2 }, Gold = 2000, Items = { MithrilIngot = 7, SteelIngot = 5, Maple = 8, CyclopsEye = 3 } },
	OrichalcumHammer = { From = { Id = "MithrilHammer", Count = 2 }, Gold = 5000, Items = { OrichalcumIngot = 4, MithrilIngot = 6, Ebony = 6, BossToken = 2 } },
	-- 방어구 세트 (2026-10-10 사용자 요청): 단계마다 그 몹의 재료로 만든다 (EquipmentDefs ARMOR_SETS)
	--   1 가죽(슬라임 젤리) / 2 뼈(뼈다귀 + 낡은 천) / 3 케르베로스(털가죽 + 송곳니) / 4 사이클롭스(거대한 가죽 + 눈알)
	--   5 바위 골렘(바위 판 + 골렘 핵) / 6 서리 거인(서리 털가죽 + 서리 수정) / 7 베헤모스(비늘 + 뿔 + 보스의 증표)
	--   주재료 많이 + 두 번째 재료 조금 + 바로 아래 세트 재료 조금 + 묶는 괴 1개(3단계부터)
	-- 헬멧
	LeatherHelmet = { Gold = 8, Items = { SlimeJelly = 3 } },
	BoneHelmet = { From = { Id = "LeatherHelmet", Count = 2 }, Gold = 40, Items = { Bone = 12, OldCloth = 2 } },
	CerberusHelmet = { From = { Id = "BoneHelmet", Count = 2 }, Gold = 180, Items = { CerberusHide = 8, CerberusFang = 3, Bone = 4, IronIngot = 1 } },
	CyclopsHelmet = { From = { Id = "CerberusHelmet", Count = 2 }, Gold = 700, Items = { CyclopsHide = 10, CyclopsEye = 2, CerberusHide = 3, SteelIngot = 1 } },
	GolemHelmet = { From = { Id = "CyclopsHelmet", Count = 2 }, Gold = 1800, Items = { GolemPlate = 10, GolemCore = 1, CyclopsHide = 4, MithrilIngot = 1 } },
	FrostHelmet = { From = { Id = "GolemHelmet", Count = 2 }, Gold = 4500, Items = { FrostHide = 12, FrostCrystal = 2, GolemPlate = 4, MithrilIngot = 1 } },
	BehemothHelmet = { From = { Id = "FrostHelmet", Count = 2 }, Gold = 9000, Items = { BehemothScale = 14, BehemothHorn = 2, FrostHide = 4, BossToken = 1, OrichalcumIngot = 1 } },
	-- 갑옷
	LeatherArmor = { Gold = 12, Items = { SlimeJelly = 5 } },
	BoneArmor = { From = { Id = "LeatherArmor", Count = 2 }, Gold = 50, Items = { Bone = 16, OldCloth = 4 } },
	CerberusArmor = { From = { Id = "BoneArmor", Count = 2 }, Gold = 220, Items = { CerberusHide = 12, CerberusFang = 4, OldCloth = 4, IronIngot = 1 } },
	CyclopsArmor = { From = { Id = "CerberusArmor", Count = 2 }, Gold = 850, Items = { CyclopsHide = 14, CyclopsEye = 2, CerberusHide = 4, SteelIngot = 1 } },
	GolemArmor = { From = { Id = "CyclopsArmor", Count = 2 }, Gold = 2200, Items = { GolemPlate = 14, GolemCore = 2, CyclopsHide = 5, MithrilIngot = 1 } },
	FrostArmor = { From = { Id = "GolemArmor", Count = 2 }, Gold = 5500, Items = { FrostHide = 16, FrostCrystal = 3, GolemPlate = 5, MithrilIngot = 2 } },
	BehemothArmor = { From = { Id = "FrostArmor", Count = 2 }, Gold = 11000, Items = { BehemothScale = 18, BehemothHorn = 3, FrostHide = 5, BossToken = 2, OrichalcumIngot = 1 } },
	-- 신발
	LeatherBoots = { Gold = 8, Items = { SlimeJelly = 3 } },
	BoneBoots = { From = { Id = "LeatherBoots", Count = 2 }, Gold = 40, Items = { Bone = 10, OldCloth = 3 } },
	CerberusBoots = { From = { Id = "BoneBoots", Count = 2 }, Gold = 180, Items = { CerberusHide = 8, CerberusFang = 2, Bone = 3, IronIngot = 1 } },
	CyclopsBoots = { From = { Id = "CerberusBoots", Count = 2 }, Gold = 700, Items = { CyclopsHide = 9, CyclopsEye = 1, CerberusHide = 3, SteelIngot = 1 } },
	GolemBoots = { From = { Id = "CyclopsBoots", Count = 2 }, Gold = 1800, Items = { GolemPlate = 9, GolemCore = 1, CyclopsHide = 3, MithrilIngot = 1 } },
	FrostBoots = { From = { Id = "GolemBoots", Count = 2 }, Gold = 4500, Items = { FrostHide = 10, FrostCrystal = 2, GolemPlate = 3, MithrilIngot = 1 } },
	BehemothBoots = { From = { Id = "FrostBoots", Count = 2 }, Gold = 9000, Items = { BehemothScale = 12, BehemothHorn = 1, FrostHide = 3, BossToken = 1, OrichalcumIngot = 1 } },
	-- 장갑
	LeatherGloves = { Gold = 8, Items = { SlimeJelly = 3 } },
	BoneGloves = { From = { Id = "LeatherGloves", Count = 2 }, Gold = 40, Items = { Bone = 10, OldCloth = 2 } },
	CerberusGloves = { From = { Id = "BoneGloves", Count = 2 }, Gold = 180, Items = { CerberusHide = 6, CerberusFang = 4, Bone = 3, IronIngot = 1 } },
	CyclopsGloves = { From = { Id = "CerberusGloves", Count = 2 }, Gold = 700, Items = { CyclopsHide = 8, CyclopsEye = 1, CerberusHide = 3, SteelIngot = 1 } },
	GolemGloves = { From = { Id = "CyclopsGloves", Count = 2 }, Gold = 1800, Items = { GolemPlate = 8, GolemCore = 1, CyclopsHide = 3, MithrilIngot = 1 } },
	FrostGloves = { From = { Id = "GolemGloves", Count = 2 }, Gold = 4500, Items = { FrostHide = 9, FrostCrystal = 2, GolemPlate = 3, MithrilIngot = 1 } },
	BehemothGloves = { From = { Id = "FrostGloves", Count = 2 }, Gold = 9000, Items = { BehemothScale = 11, BehemothHorn = 1, FrostHide = 3, BossToken = 1, OrichalcumIngot = 1 } },
	-- 목걸이 (광물 + 통나무)
	BoneNecklace = { Gold = 8, Items = { Stone = 4, Pine = 2 } },
	CopperNecklace = { From = { Id = "BoneNecklace", Count = 2 }, Gold = 40, Items = { CopperIngot = 3, Stone = 6 } },
	IronNecklace = { From = { Id = "CopperNecklace", Count = 2 }, Gold = 180, Items = { IronIngot = 4, CopperIngot = 3, Coal = 6 } },
	DiamondNecklace = { From = { Id = "IronNecklace", Count = 2 }, Gold = 700, Items = { SteelIngot = 4, IronIngot = 5, Coal = 10, Ebony = 1 } },
	MithrilNecklace = { From = { Id = "DiamondNecklace", Count = 2 }, Gold = 1800, Items = { MithrilIngot = 4, SteelIngot = 4, Ebony = 2 } },
	OrichalcumNecklace = { From = { Id = "MithrilNecklace", Count = 2 }, Gold = 4500, Items = { OrichalcumIngot = 2, MithrilIngot = 5, Ebony = 3 } },
	-- 팔찌 (광물 + 통나무)
	WoodBracelet = { Gold = 8, Items = { Pine = 3 } },
	CopperBracelet = { From = { Id = "WoodBracelet", Count = 2 }, Gold = 40, Items = { CopperIngot = 2, Birch = 3 } },
	IronBracelet = { From = { Id = "CopperBracelet", Count = 2 }, Gold = 180, Items = { IronIngot = 3, Maple = 4, Coal = 4 } },
	DiamondBracelet = { From = { Id = "IronBracelet", Count = 2 }, Gold = 700, Items = { SteelIngot = 3, IronIngot = 4, Ebony = 2 } },
	MithrilBracelet = { From = { Id = "DiamondBracelet", Count = 2 }, Gold = 1800, Items = { MithrilIngot = 3, SteelIngot = 3, Ebony = 3 } },
	OrichalcumBracelet = { From = { Id = "MithrilBracelet", Count = 2 }, Gold = 4500, Items = { OrichalcumIngot = 2, MithrilIngot = 4, Ebony = 4 } },
}
Config.Recipes = RECIPES
Config.Crafting = {
	MaxPerRequest = 10, -- 한 번 요청으로 만들 수 있는 최대 개수 (1단계 "3개 사기" 버튼용)
}

-- 아이템 상세 창 (가방·상점에서 아이템을 한 번 누르면 뜬다, 2026-10-09)
Config.ItemDetail = {
	SpinSeconds = 8, -- 한 바퀴(360°) 도는 데 걸리는 시간(초)
	Tilt = 18, -- 위에서 내려다보는 각도(도)
	FieldOfView = 30,
	-- 창 모양 (2026-10-09: 가방·상점 창 오른쪽에 붙는 세로 창)
	PanelWidth = 250, -- 창 너비(px)
	MinHeight = 320, -- 붙은 창이 낮아도 이 높이까지는 늘린다(px)
	Gap = 8, -- 붙은 창과 사이 간격(px)
	ScreenMargin = 8, -- 화면 가장자리 여백(px)
	ViewHeight = 200, -- 돌아가는 모델 칸 최대 높이(px)
	OverlayRatio = 0.62, -- 옆에 자리가 없을 때(휴대폰) 붙은 창 너비의 이만큼으로 겹쳐 띄운다
}

-- 장비 창 사람 그림 (2026-10-09): 내 캐릭터를 복제해 똑바로 선 모습으로 보여 주고, 장비 칸을 몸 위치에 둔다
Config.EquipFigure = {
	UseCharacter = true, -- false면 복제하지 않고 네모 블록 사람 그림만
	FieldOfView = 20, -- 캐릭터를 비추는 카메라 시야(작을수록 납작하게)
	SpinSeconds = 14, -- 카메라가 캐릭터 둘레를 한 바퀴 도는 시간(초). 0이면 정면 고정 (2026-10-09)
	PanelWidth = 250, -- 장비 창 너비(px)
	MinHeight = 300, -- 장비 창 최소 높이(px). 가방 창과 같은 높이를 쓰되 이보다 작아지지 않게
}

-- NPC 상호작용
Config.Npc = {
	InteractDistance = 12, -- 이 거리 안에서만 상점 요청을 받는다(스터드)
	PromptDistance = 10, -- ProximityPrompt가 뜨는 거리(스터드)
}

-- 광산 층: 이동 발판을 쓰려면 RequiredTier 이상 곡괭이가 필요하다
Config.Mine = {
	Floors = {
		[0] = { Name = "광산 지상", RequiredTier = 1 },
		[1] = { Name = "광산 1층", RequiredTier = 2 },
		[2] = { Name = "광산 2층", RequiredTier = 3 },
		[3] = { Name = "광산 3층", RequiredTier = 4 }, -- 미스릴·오리하르콘 (2026-10-09 열림, 다이아몬드 곡괭이 필요)
		[4] = { Name = "광산 4층", RequiredTier = 5, Locked = true }, -- 공사 중
	},
	PromptDistance = 8, -- 이동 발판 ProximityPrompt 거리(스터드)
}

-- 광산 3층 제작 스크립트(studio/BuildMineFloor3) 수치 (2026-10-09)
Config.MineFloor3 = {
	Seed = 3303, -- 미로 모양 고정용 (바꾸면 미로가 바뀐다)
	ExtraLoops = 4, -- 막다른 길만 있으면 답답해서 벽을 몇 개 더 뚫는다
	MithrilSpawns = 18, -- 미스릴 자리 수 (일부는 두 개가 붙어 나옴)
	PairChance = 0.35, -- 두 개가 붙어 나올 확률
	OrichalcumCandidates = 6, -- 오리하르콘 후보 자리 수 (동시에 서는 수는 RandomPools.Orichalcum.Active)
	Depth = 40, -- 2층 맨 아래보다 이만큼 더 아래에 바닥 (스터드)
}

-- 광산 안 분위기 (클라이언트 전용): 광산 구역(MineZone)에 들어가면 어둡게, 음악, 박쥐
Config.MineAtmosphere = {
	TweenTime = 1.2, -- 조명이 바뀌는 시간(초)
	Ambient = Color3.fromRGB(38, 33, 40),
	OutdoorAmbient = Color3.fromRGB(40, 35, 44),
	Brightness = 0.4,
	ExposureCompensation = -0.35,
	AtmosphereDensity = 0.5, -- 안개 (높을수록 먼 곳이 안 보인다)
	AtmosphereColor = Color3.fromRGB(35, 30, 42),
	AtmosphereDecay = Color3.fromRGB(15, 12, 20),
	Saturation = -0.25, -- 색을 빼서 으스스하게
	TintColor = Color3.fromRGB(215, 210, 235),
	EnterVolume = 0.8, -- 입장 음악
	AmbientVolume = 0.35, -- 배경음
	DripVolume = 0.3, -- 물방울 소리
	BatCount = 6, -- 층마다 날아다니는 박쥐 수
	BatSpeedMin = 5, -- 박쥐 속도 범위(스터드/초). 수시로 바뀐다
	BatSpeedMax = 17,
	BatTurnRate = 2.5, -- 박쥐가 제멋대로 방향을 트는 정도
	BatHoverChance = 0.08, -- 1초마다 잠깐 제자리에서 퍼덕일 확률
	BatFlapChance = 0.15, -- 가까운 박쥐가 1초마다 날갯짓 소리를 낼 확률
	BatSoundRange = 30, -- 이 거리 안의 박쥐만 소리를 낸다
	TorchFlicker = 0.35, -- 횃불·랜턴 밝기 흔들림 정도
}

-- 지도 (클라이언트 전용, MinimapController·MapData). 2026-10-09 손그림 지도로 바뀜
--   밖: 양피지 위에 물·풀·모래·바위·흙길(지형 광선 격자), 언덕 ^, 나무·집 그림, 몹 구역, NPC·광산 입구
--   광산: 층 미로 벽 전체 + 출구·아래층 길 표시. 안 가 본 칸은 조금 어둡게
Config.Minimap = {
	-- 큰 지도 창 크기: 화면 높이·너비에 대한 비율 (지도 모양에 맞춰 줄어든다)
	HeightFraction = 0.72,
	MaxWidthFraction = 0.92,
	TitleHeight = 38, -- 창 위 제목 줄 높이(픽셀)
	Padding = 14, -- 지도 그림 둘레 여백(픽셀)
	MaxOutdoorScale = 2.5, -- 밖: 1스터드당 최대 픽셀 (큰 화면에서 너무 커지지 않게)
	MaxCaveScale = 3.2, -- 광산: 1스터드당 최대 픽셀
	-- 작은 지도 (큰 지도의 "작게" 버튼): 오른쪽 위, 내 위치가 가운데
	CornerSize = 170, -- 픽셀
	CornerTop = 110, -- 화면 위에서 거리(픽셀). 골드 칸 아래
	CornerOutdoorScale = 1.1, -- 작은 지도 밖 확대(1스터드당 픽셀)
	CornerCaveScale = 2.4, -- 작은 지도 광산 확대
	-- 밖 지형 그리기 (처음 열 때 한 번 광선을 쏴서 기억)
	SampleStep = 8, -- 광선 간격(스터드). 맵이 크면 MaxSamplesPerSide에 맞춰 넓어진다
	MaxSamplesPerSide = 96, -- 한 변 최대 광선 수
	SamplesPerFrame = 400, -- 한 프레임에 쏘는 광선 수 (끊김 방지)
	SampleTop = 400, -- 광선 시작 높이(스터드)
	SurfaceMinY = -60, -- 이보다 낮은 것은 지하(광산 층)로 보고 밖 지도에서 뺀다
	WorldMargin = 50, -- 마을·NPC·나무·몹 자리 범위 둘레 여유(스터드)
	HillHeight = 22, -- 땅 평균보다 이만큼 높으면 언덕 ^ (스터드)
	MountainHeight = 45, -- 이만큼 높으면 큰 산
	HillStride = 3, -- 언덕 그림은 광선 몇 칸마다 하나
	WaveChance = 0.05, -- 물 칸마다 물결 ~ 그릴 확률
	TreeCell = 22, -- 나무 그림 하나가 대표하는 칸 크기(스터드)
	TreeSize = 12, -- 나무 그림 크기(픽셀)
	TownHouseCount = 5, -- 마을 건물 모델을 못 찾으면 광장 둘레에 그릴 집 수
	TownHouseRadius = 30, -- 그 집들의 광장 중심 거리(스터드)
	MaxHouses = 30,
	RockRange = 160, -- 밖: 내 둘레 이 거리 안의 바위만 점으로 (스터드)
	RockRefresh = 1, -- 바위 점 다시 그리는 간격(초)
	-- 광산 미로
	VisitRadius = 13, -- 칸 중심에서 이 거리 안에 들어가면 그 칸을 가 본 칸으로 (스터드)
	WallRayHeight = 3, -- 벽 확인 광선 높이: 바닥에서 이만큼 위 (스터드)
	FloorSearch = 40, -- 경로점 아래로 바닥을 찾는 거리 (스터드)
	WallThickness = 5, -- 벽 선 굵기(픽셀)
	WallJitter = 1.2, -- 손그림처럼 벽 선을 이만큼 흔든다(픽셀)
	FogTransparency = 0.45, -- 안 가 본 칸 어둡게 덮는 정도 (1이면 안 덮음)
	PortalFloorRange = 30, -- 이 높이 차 안의 갱도만 이 층 것으로 본다 (스터드)
	-- 글꼴·아이콘
	Font = Enum.Font.Cartoon,
	NpcIcons = { Blacksmith = "⚒", Merchant = "💰", Hunter = "🏹" },
	-- 몹 사는 곳: 구역(MobSpawns Zone)마다 주인 몹의 큰 손그림 얼굴 하나 + 이름표 (몹 하나하나는 안 그림)
	HabitatFaceSize = 52, -- 큰 지도 얼굴 크기(픽셀)
	HabitatLabelSize = 14, -- 이름표 글자 크기
	HabitatInkWidth = 2, -- 얼굴 잉크 테두리 굵기(픽셀)
	HabitatTilt = 6, -- 손그림처럼 얼굴을 이만큼까지 기울임(도). 이름표는 절반
	HabitatCornerScale = 0.6, -- 작은 지도에서 얼굴 크기 배율 (이름표는 숨김)
	Colors = {
		Parchment = Color3.fromRGB(238, 222, 184),
		ParchmentEdge = Color3.fromRGB(120, 80, 40), -- 가장자리 그늘
		Ink = Color3.fromRGB(88, 58, 32),
		InkLight = Color3.fromRGB(250, 240, 215), -- 글자 테두리
		Grass = Color3.fromRGB(200, 212, 152),
		Dirt = Color3.fromRGB(212, 186, 138),
		Path = Color3.fromRGB(196, 176, 146),
		Sand = Color3.fromRGB(236, 218, 162),
		Rock = Color3.fromRGB(178, 164, 142),
		Snow = Color3.fromRGB(244, 244, 238),
		Water = Color3.fromRGB(150, 192, 210),
		WaterLine = Color3.fromRGB(80, 130, 165),
		Hill = Color3.fromRGB(125, 90, 55),
		TreeCrown = Color3.fromRGB(95, 160, 80),
		Trunk = Color3.fromRGB(110, 75, 45),
		House = Color3.fromRGB(250, 238, 210),
		Roof = Color3.fromRGB(180, 80, 55),
		Npc = Color3.fromRGB(240, 180, 80),
		MineMound = Color3.fromRGB(150, 135, 120),
		CaveBackground = Color3.fromRGB(40, 34, 32),
		CaveFloor = Color3.fromRGB(214, 198, 168),
		CaveWall = Color3.fromRGB(52, 38, 28),
		Fog = Color3.fromRGB(30, 24, 22),
		Exit = Color3.fromRGB(70, 165, 80),
		Down = Color3.fromRGB(60, 120, 210),
		Locked = Color3.fromRGB(130, 120, 115),
		Player = Color3.fromRGB(230, 60, 50),
		OtherPlayer = Color3.fromRGB(60, 110, 220),
	},
}

-- 바위 생성 수치
Config.OreSpawn = {
	RandomYaw = true, -- 생성할 때 Y축으로 랜덤 회전해서 같은 모양이 덜 반복돼 보이게
	-- 스폰 파트 아래로 땅을 찾아 바위 바닥을 땅에 맞춘다
	GroundSearchUp = 3, -- 스폰 파트에서 이만큼 위에서부터 (스터드)
	GroundSearchDown = 12, -- 이만큼 아래까지 땅을 찾는다 (스터드)
	FallbackDrop = 2, -- 땅을 못 찾으면 스폰 파트에서 이만큼 아래를 땅으로 본다 (스터드)
	SinkDepth = 0.15, -- 바위를 땅에 살짝 묻어 떠 보이지 않게 (스터드)
	TreeSinkDepth = 0.6, -- 나무는 비탈에서도 밑동이 뜨지 않게 더 묻는다 (스터드)
	-- 광산(Floor 1 이상) 광석: 벽 속에 묻혀 작아 보이던 문제 (2026-10-09)
	MineScale = 1.4, -- 광산 광석 크기 배수
	WallGap = 0.4, -- 벽에서 밀어낼 때 띄우는 틈 (스터드)
}

-- 보스 바위·나무 (2026-10-09 사용자 요청): 가끔 크고 단단하고 많이 주는 노드가 나온다
Config.BossNodes = {
	Chance = 0.07, -- 생길 때 보스일 확률
	ScaleMin = 1.5, -- 크기 배수 범위
	ScaleMax = 3,
	HpExponent = 2, -- 체력 = 원래 × 크기^HpExponent (1.5배 → 2.25배, 3배 → 9배)
	RewardExponent = 1.5, -- 산출량 = 원래 × 크기^RewardExponent (1.5배 → 1.8배, 3배 → 5.2배)
}

-- 바위 하나당 산출량: 랜덤 BaseMin~BaseMax개 (판정과 상관없음)
-- 여러 명이 같이 캤으면 기여도(준 데미지 비율)대로 나눈다. 피버를 연 사람은 자기 몫에 피버 배수를 곱한다
Config.Reward = {
	BaseMin = 5, -- 기본 개수 최소 (2026-10-09 보상 키우기: 2~5 → 5~10)
	BaseMax = 10, -- 기본 개수 최대
	MinPerContributor = 1, -- 조금이라도 친 사람은 최소 이만큼 받는다
}

-- 주인 정하기: 먼저 데미지를 준 사람만 그 바위·나무·몹을 칠 수 있다 (2026-10-09 사용자 요청)
Config.Ownership = {
	HoldTime = 8, -- 주인이 이 초 동안 안 치면 누구나 칠 수 있게 풀린다
	NoticeInterval = 3, -- "다른 사람이 ~중이에요" 알림 간격(초)
	LockShowRange = 60, -- 남의 것 위 "🔒 이름" 표시가 보이는 거리(스터드)
}

-- 피버 수치
Config.Fever = {
	Chance = 0.1, -- 마지막 일격에서 발동 확률 (10%)
	FreezeDuration = 0.3, -- 1단계 멈춤
	OrbitDuration = 1, -- 2단계 카메라 반 바퀴 회전 + 균열에서 빛
	TitleDuration = 0.5, -- 3단계 "FEVER!" 문구
	TapDuration = 4, -- 4단계 연타
	BurstDuration = 0.5, -- 5단계 폭발
	MaxTapsPerSecond = 12, -- 서버가 인정하는 초당 최대 탭 수
	TapBurstAllowance = 3, -- 네트워크로 탭이 몰려 들어와도 한 번에 인정하는 개수
	TapLatencyTolerance = 0.3, -- 연타 구간 앞뒤로 봐주는 시간(초)
	CameraOrbit = true, -- 카메라 회전 연출. 어지러우면 false
	CameraDistance = 9, -- 피버 중 카메라와 바위 거리(스터드)
	CameraHeight = 3, -- 피버 중 카메라 높이(바위 기준, 스터드)
	-- 연타 "뿅" 소리: 탭할수록 음이 올라가서 게이지가 찰 때 긴장감이 오르게
	TapPitchStart = 1.0, -- 첫 탭 음높이 (PlaybackSpeed)
	TapPitchEnd = 2.0, -- 게이지가 가득 찼을 때 음높이
	TapPitchJitter = 0.06, -- 매번 조금씩 다르게 (±)
	TapVolume = 0.9,
	TapSparkleVolume = 0.45, -- 겹치는 반짝임 소리 볼륨
	-- 탭 수 기준 보상 배수 (MinTaps 이상이면 해당 배수, 큰 값부터 검사). 피버를 연 사람의 몫에 곱한다
	-- 2026-10-09 사용자 요청: 조금만 잘해도 3~5배 (4초에 16번 = 초당 4번이면 3배)
	Tiers = {
		{ MinTaps = 24, Multiplier = 5 },
		{ MinTaps = 16, Multiplier = 3 },
		{ MinTaps = 10, Multiplier = 2 },
		{ MinTaps = 5, Multiplier = 1.5 },
		{ MinTaps = 0, Multiplier = 1.3 },
	},
}

-- 타격감 연출 수치 (클라이언트 전용)
Config.HitFeel = {
	-- 나무가 다 베일 때 "뻐지지직" (나무 찍는 소리를 빠르게 여러 번 겹친다, 2026-10-09)
	TreeCrack = {
		Count = 7, -- 겹치는 횟수
		Interval = 0.05, -- 간격(초)
		PitchMin = 1.25, -- 음높이 범위 (높을수록 잘게 갈라지는 소리)
		PitchMax = 1.9,
		Volume = 0.7,
		BreakVolume = 0.35, -- 원래 쓰러지는 소리(쿵)는 작게 깔아 둔다
	},
	HitStop = { Normal = 0.05, Nice = 0.065, Perfect = 0.08 }, -- 히트스톱 길이(초)
	CameraShake = { Magnitude = 0.15, Duration = 0.12, PerfectMultiplier = 1.8 },
	PitchRange = { Min = 0.9, Max = 1.1 }, -- 타격음 PlaybackSpeed 랜덤 범위
	Clang = { Volume = 0.55, PerfectVolume = 0.8, NicePitch = 1.08, PerfectPitch = 1.18 }, -- 곡괭이 "깡!" 볼륨·음높이
	RockShake = { Amplitude = 0.12, Duration = 0.12 }, -- 바위 떨림(스터드, 초)
	DebrisCount = { Normal = 8, Nice = 14, Perfect = 22, Break = 40 }, -- 파편 파티클 개수
	OreChunkMax = 20, -- 깨질 때 튀어나오는 조각 최대 개수 (보상이 더 많아도 이 이상은 안 그림)
	-- 줍기 연출: 조각이 땅에 떨어져 있다가 가까이 가면(또는 잠시 뒤 저절로) 빨려 와서 "획득" 알림이 뜬다
	-- (보상은 서버가 이미 가방에 넣었다. 잃어버리지 않게 PickupAutoTime이 지나면 저절로 빨려 온다)
	PickupSizeMin = 0.8, -- 떨어지는 조각 크기(스터드). 2026-10-09 너무 작아 안 보여서 0.35~0.55 → 키움
	PickupSizeMax = 1.1,
	PickupMagnetRange = 10, -- 이 거리 안에 들어오면 빨려 온다(스터드)
	PickupAutoTime = 3, -- 이만큼 지나면 멀리 있어도 빨려 온다(초)
	PickupLandTime = 0.6, -- 튀어나와 땅에 떨어지는 동안은 안 빨려 온다(초)
	OreSuckDuration = 0.3, -- 빨려오는 시간(초)
	JudgmentPopupDuration = 0.8, -- Perfect!/Nice! 말풍선이 떠 있는 시간(초)
	HpBarRange = 12, -- 이 거리 안의 가장 가까운 바위에 체력바 표시(스터드)
	-- 좋은 곡괭이일수록 강한 타격 연출: 충격파 고리, 튀는 광석 조각, 카메라 흔들림
	-- Chunks: 튀는 조각 수, Ring: 충격파 최대 크기(스터드), Shake: 카메라 흔들림 배수, Sparkle: 반짝이 가루
	-- 번개 (다이아몬드 도끼): 하늘에서 지그재그 빛줄기가 내려와 나무를 한 방에 벤다
	Lightning = {
		Height = 60, -- 번개가 시작하는 높이(스터드)
		Segments = 9, -- 지그재그 마디 수
		Jitter = 2.5, -- 마디가 옆으로 벗어나는 정도(스터드)
		Color = Color3.fromRGB(170, 230, 255),
		Duration = 0.35, -- 번개가 보이는 시간(초)
		FlashBrightness = 12, -- 번쩍이는 빛 밝기
		Shake = 3, -- 카메라 흔들림 배수
		ThunderPitch = 0.55, -- 천둥 소리 음높이 (폭발음을 낮게 깔아 쓴다)
		ThunderVolume = 1,
	},
	-- 나무 타격 연출: 덜 흔들리고, 나뭇조각과 잎이 떨어지고, 다 베면 쓰러진다
	Tree = {
		ShakeScale = 0.35, -- 바위 떨림 대비 나무 떨림 배수
		ChopVolume = 0.8, -- "퍽" 소리 볼륨
		LeafCount = 5, -- 칠 때마다 떨어지는 잎 수
		BreakLeafCount = 30, -- 쓰러질 때 떨어지는 잎 수
		FallTime = 1.1, -- 쓰러지는 시간(초)
		FadeTime = 0.5, -- 쓰러진 뒤 사라지는 시간(초)
		GhostRingHeight = 1.6, -- 타이밍 잔상 고리 높이(스터드). 나무는 줄기 둘레에 고리가 줄어든다
	},
	-- 도끼(나무) 타격 연출 (나무는 돌 조각 대신 잎이 흩날리므로 Chunks = 0). 곡괭이 표와 같은 항목 + Sparks: 튀는 불꽃 수, Slash: 베는 빛줄기, Leaves: 떨어지는 잎 배수
	AxeTierEffects = {
		[1] = { Color = Color3.fromRGB(200, 170, 120), Chunks = 0, Ring = 2.5, Shake = 1.05, Sparkle = false, Sparks = 0, Slash = false, Leaves = 1 },
		[2] = { Color = Color3.fromRGB(255, 150, 70), Chunks = 0, Ring = 4, Shake = 1.3, Sparkle = false, Sparks = 12, Slash = false, Leaves = 1.6 },
		[3] = { Color = Color3.fromRGB(230, 235, 255), Chunks = 0, Ring = 5.5, Shake = 1.55, Sparkle = false, Sparks = 18, Slash = true, Leaves = 2.2 },
		[4] = { Color = Color3.fromRGB(110, 235, 255), Chunks = 0, Ring = 8, Shake = 1.9, Sparkle = true, Sparks = 26, Slash = true, Leaves = 3 },
		-- 5 미스릴 파란 빛 / 6 오리하르콘 금빛 이중 고리 + 번쩍임(Flash = 빛 밝기) (2026-10-09). 없는 단계는 가장 높은 아래 단계 값
		[5] = { Color = Color3.fromRGB(110, 175, 255), Chunks = 0, Ring = 9.5, Shake = 2.05, Sparkle = true, Sparks = 32, Slash = true, Leaves = 3.5 },
		[6] = { Color = Color3.fromRGB(255, 180, 60), Chunks = 0, Ring = 11, Shake = 2.3, Sparkle = true, Sparks = 40, Slash = true, Leaves = 4, DoubleRing = true, Flash = 5 },
	},
	TierEffects = {
		[2] = { Color = Color3.fromRGB(235, 140, 70), Chunks = 3, Ring = 3.5, Shake = 1.2, Sparkle = false },
		[3] = { Color = Color3.fromRGB(225, 230, 240), Chunks = 6, Ring = 5, Shake = 1.45, Sparkle = false },
		[4] = { Color = Color3.fromRGB(110, 235, 255), Chunks = 9, Ring = 7, Shake = 1.75, Sparkle = true },
		[5] = { Color = Color3.fromRGB(110, 175, 255), Chunks = 11, Ring = 8.5, Shake = 1.95, Sparkle = true, Sparks = 12 }, -- 미스릴 (2026-10-09)
		[6] = { Color = Color3.fromRGB(255, 180, 60), Chunks = 14, Ring = 10, Shake = 2.2, Sparkle = true, Sparks = 24, DoubleRing = true, Flash = 5 }, -- 오리하르콘
	},
}

-- 모바일 조작 (MobileControls, 2026-10-09): 왼쪽 아래 이동 패드(기본 조이스틱), 오른쪽 아래 공격 버튼
Config.MobileControls = {
	AttackSize = 120, -- 공격 버튼 지름(픽셀)
	Margin = 28, -- 화면 가장자리에서 떨어진 거리(픽셀)
	Gap = 14, -- 공격 버튼과 점프 버튼 사이(픽셀)
	-- 구르기·스킬 버튼 (2026-10-09): 공격 버튼 둘레에 동그랗게. 각도는 공격 버튼 가운데 기준, 0° = 오른쪽, 270° = 위 (화면 좌표)
	SmallSize = 80, -- 점프·구르기·스킬 버튼 지름(픽셀)
	JumpAngle = 185, -- 점프 버튼 (왼쪽)
	RollAngle = 232, -- 구르기 버튼 (왼쪽 위)
	SkillAngle = 280, -- 스킬 버튼 (위)
	PcSize = 58, -- PC: 오른쪽 아래 구르기·스킬 버튼 지름(픽셀)
	PcMargin = 20, -- PC: 화면 가장자리에서 떨어진 거리(픽셀)
}

-- 구르기 (2026-10-09 사용자 요청): 짧게 휙 굴러 피한다. PC Q키 / 모바일 공격 버튼 왼쪽 위
-- 움직임은 클라이언트가(캐릭터 물리는 클라 소유), 무적 시간·마나·쿨다운은 서버(SkillService)가 정한다
Config.Roll = {
	ManaCost = 0, -- 한 번 구르는 데 쓰는 마나 (2026-10-10 사용자 요청: 마나 없이)
	Cooldown = 5, -- 다시 구르려면 기다리는 시간(초) (2026-10-10 1.2 → 5)
	Distance = 18, -- 굴러가는 거리(스터드) (2026-10-10 12 → 18)
	Duration = 0.38, -- 굴러가는 시간(초) (거리를 늘려서 조금 길게)
	IFrame = 0.48, -- 서버: 구르기 요청을 받은 뒤 몹 공격을 안 맞는 시간(초). 지연을 생각해 Duration보다 조금 길게
	CooldownTolerance = 0.15, -- 서버 쿨다운 여유(초)
	Crouch = 0.9, -- 구르는 동안 몸이 내려가는 깊이(스터드, 연출)
	Sound = "rbxasset://sounds/swordslash.wav", -- "휙" (높은 음으로)
}

-- 무기·도구별 스킬 (2026-10-09 사용자 요청): 들고 있는 것에 맞는 스킬 하나. PC F키 / 모바일 공격 버튼 위
-- 전부 서버(SkillService)가 검사한다: 맞는 종류를 들었나, 마나, 쿨다운, 거리, 주인, 장비 벽, 피버 중인지
-- Kind = 도구 종류(PickaxeDefs Kind). Icon은 버튼 그림, Name은 버튼 아래 이름
Config.Skills = {
	-- 칼: 방패 막기. Duration초 동안 몹에게 받는 피해를 Reduction만큼 줄인다
	Block = {
		Kind = { "Sword" },
		Name = "방패 막기",
		Icon = "🛡",
		ManaCost = 12,
		Cooldown = 10, -- 2026-10-10 사용자 요청: 스킬 쿨타임 10초
		Duration = 1.5,
		Reduction = 0.8, -- 0.8 = 피해 80% 줄임
		Color = Color3.fromRGB(110, 190, 255),
	},
	-- 방망이: 내려찍기. 둘레 Radius 안 몹에게 무기 데미지 × DamageMultiplier + 기절 StunTime초 + 밀쳐 내기
	Slam = {
		Kind = { "Club" },
		Name = "내려찍기",
		Icon = "💥",
		ManaCost = 15,
		Cooldown = 10, -- 2026-10-10 사용자 요청: 스킬 쿨타임 10초
		Radius = 8,
		DamageMultiplier = 1.8,
		StunTime = 1.5,
		Knockback = 6,
		Color = Color3.fromRGB(255, 200, 90),
	},
	-- 활: 연사. 지금 노리는 몹에게 화살 Arrows발을 Interval초 간격으로 (화살을 그만큼 쓴다, 한 발 데미지 × DamageMultiplier)
	RapidFire = {
		Kind = { "Bow" },
		Name = "연사",
		Icon = "🏹",
		ManaCost = 12,
		Cooldown = 10, -- 2026-10-10 사용자 요청: 스킬 쿨타임 10초
		Arrows = 3,
		Interval = 0.15,
		DamageMultiplier = 0.8,
		Color = Color3.fromRGB(150, 255, 170),
	},
	-- 곡괭이·도끼: 강하게 내려찍기. ArmTime초 안의 다음 한 번이 Multiplier배 (장비 벽·주인 규칙은 그대로)
	PowerStrike = {
		Kind = { "Pickaxe", "Axe" },
		Name = "강하게 찍기",
		Icon = "⚒",
		ManaCost = 10,
		Cooldown = 10, -- 2026-10-10 사용자 요청: 스킬 쿨타임 10초
		Multiplier = 3,
		ArmTime = 5,
		Color = Color3.fromRGB(255, 160, 80),
	},
	CooldownTolerance = 0.15, -- 서버 쿨다운 여유(초)
	ShieldSound = "rbxassetid://9125361455", -- 방패 "챙" (Anvil Hit을 높게)
	SlamSound = "rbxassetid://9118608146", -- 내려찍기 "쿵" (Rock Hits Rock을 낮게)
}

-- 배경음악 (2026-10-09, MusicController). 밖에서 차례로 틀고 광산에서는 줄인다
-- TODO: 곡 Id는 팬 사이트 목록에서 고른 잔잔한 곡(Spirit LoFi "Calm Waves"·"Easy Flow", APM "Ruins of Tomorrow"). 안 나오면 Creator Store에서 찾아 바꾸기
Config.Music = {
	-- 평소: 느릿하고 여유 있는 곡 (2026-10-09 사용자 요청: 박자가 빠르지 않게). APM 공식 곡은 모든 게임에서 쓸 수 있다
	Calm = {
		"rbxassetid://1848354536", -- Relaxed Scene (APM, 잔잔한 선율)
		"rbxassetid://1840880603", -- Evening
		"rbxassetid://1837070127", -- Calming Nostalgia
	},
	-- 전투: 몹과 싸울 때 긴박한 곡
	Battle = {
		"rbxassetid://1836104000", -- Determined Epic Theme (Alt 1)
		"rbxassetid://1837779548", -- Ancient Myths (APM)
		"rbxassetid://1836104037", -- Determined Epic Theme (Alt 2)
	},
	-- 밤: 더 느리고 차분하고 조용하게 (2026-10-09). 같은 잔잔한 곡을 느리게(PlaybackSpeed) 작게 튼다
	Night = {
		Tracks = {
			"rbxassetid://1837070127", -- Calming Nostalgia
			"rbxassetid://1840880603", -- Evening
		},
		Volume = 0.14,
		PlaybackSpeed = 0.85,
	},
	-- 밤에 마을 밖에서 들리는 풀벌레 소리 (계속 반복). TODO: Creator Store에서 "crickets night ambience"를 찾아 Id 넣기. 빈 값이면 안 틂
	NightAmbience = "",
	NightAmbienceVolume = 0.4,
	BattleHoldTime = 10, -- 마지막으로 때리거나 맞은 뒤 전투곡을 유지하는 시간(초)
	-- 왼쪽 위 음표 버튼: 누르면 끄기·켜기, 옆 -/+로 크기 단계 (2026-10-09). 각 곡 볼륨에 곱해진다
	VolumeLevels = { 0.25, 0.5, 0.75, 1, 1.4, 1.8 },
	DefaultLevel = 4,
	BattleVolume = 0.3,
	-- 새소리 같은 자연 소리 (계속 반복). TODO: Creator Store에서 "birds forest ambience"를 찾아 Id 넣기. 빈 값이면 안 틂
	Ambience = "",
	AmbienceVolume = 0.35,
	Volume = 0.25, -- 밖에서 볼륨
	MineVolume = 0, -- 광산 안 볼륨 (광산 배경음이 따로 있다)
	FadeTime = 2, -- 볼륨이 바뀌는 시간(초)
	GapBetweenTracks = 3, -- 곡 사이 쉬는 시간(초)
}

-- 밤낮·먼 곳 안개 (2026-10-09, 서버 DayNightService가 시각을 돌리고 클라 DayNightController가 조명·안개·부엉이)
Config.DayNight = {
	StartClock = 9, -- 서버가 켜질 때 시각
	DayStart = 6, -- 해 뜨는 시각
	NightStart = 18.5, -- 해 지는 시각
	DaySeconds = 360, -- 낮이 실제로 흐르는 시간(초) = 6분 (2026-10-10 너무 길어서 반으로)
	NightSeconds = 180, -- 밤 = 3분
	TwilightHours = 1, -- 해 뜨고 질 때 밝기가 바뀌는 시간(게임 시각)
	Day = {
		Ambient = Color3.fromRGB(120, 120, 125),
		OutdoorAmbient = Color3.fromRGB(140, 140, 140),
		Brightness = 2.2,
		Exposure = 0,
		Density = 0.3, -- 낮에도 아주 먼 곳은 뿌옇게
		AtmColor = Color3.fromRGB(199, 214, 230),
		AtmDecay = Color3.fromRGB(106, 112, 125),
		Haze = 1,
	},
	Night = { -- 어둡지만 움직일 수는 있게 (2026-10-09: 너무 깜깜해서 밝힘. 달빛처럼 푸르스름)
		Ambient = Color3.fromRGB(55, 62, 95),
		OutdoorAmbient = Color3.fromRGB(70, 80, 120),
		Brightness = 0.8,
		Exposure = -0.25,
		Density = 0.4,
		AtmColor = Color3.fromRGB(30, 36, 62),
		AtmDecay = Color3.fromRGB(10, 12, 25),
		Haze = 2,
	},
	-- 마을에서 멀수록 안개가 짙어진다 ("미지의 세계")
	Fog = {
		ClearRadius = 90, -- 마을에서 이 거리까지는 맑음(스터드)
		FullRadius = 260, -- 이 거리부터 가장 짙음
		FarDensity = 0.62, -- 가장 먼 곳 안개 짙기 (0~1)
		FarHaze = 2.5, -- 더해지는 뿌연 정도
	},
	-- 밤에 들리는 부엉이 (내 주변 어딘가에서). TODO: Creator Store에서 "owl hoot"을 찾아 Id 넣기. 빈 값이면 안 남
	OwlSound = "",
	OwlVolume = 0.6,
	OwlIntervalMin = 12, -- 울음 간격 범위(초)
	OwlIntervalMax = 30,
}

-- 몹이 죽을 때 비명 (2026-10-09). Id는 Roblox 기본 소리를 음높이로 바꿔 쓴다. TODO: Creator Store 전용 소리 찾으면 교체
-- Repeat가 있으면 그 초 뒤에 한 번 더 (깨갱)
Config.MobDeathSounds = {
	Slime = { Id = "rbxasset://sounds/splat.wav", Pitch = 1.7, Volume = 0.9 }, -- 뀍!
	Skeleton = { Id = "rbxasset://sounds/uuhhh.mp3", Pitch = 0.75, Volume = 0.8 }, -- 으어억!
	Zombie = { Id = "rbxasset://sounds/uuhhh.mp3", Pitch = 0.55, Volume = 0.9 }, -- 우어어...
	Cerberus = { Id = "rbxasset://sounds/uuhhh.mp3", Pitch = 1.9, Volume = 0.8, Repeat = 0.16 }, -- 깨갱!
	Cyclops = { Id = "rbxasset://sounds/uuhhh.mp3", Pitch = 0.42, Volume = 1 }, -- 쿠어어엉!
	SkeletonArcher = { Id = "rbxasset://sounds/uuhhh.mp3", Pitch = 0.9, Volume = 0.8 }, -- 으억! (스켈레톤보다 조금 높게, 2026-10-10)
	-- 거대 몬스터 (2026-10-10): 아주 낮게 두 번 끊어 쿠웅… 크아앙
	StoneGolem = { Id = "rbxasset://sounds/uuhhh.mp3", Pitch = 0.32, Volume = 1, Repeat = 0.35 },
	FrostGiant = { Id = "rbxasset://sounds/uuhhh.mp3", Pitch = 0.36, Volume = 1, Repeat = 0.3 },
	Behemoth = { Id = "rbxasset://sounds/uuhhh.mp3", Pitch = 0.27, Volume = 1, Repeat = 0.4 },
	-- 바다 생물 (2026-10-09): 해파리는 뽀글(splat 높게), 낙지는 뿌직, 상어는 낮게 크앙
	Octopus = { Id = "rbxasset://sounds/splat.wav", Pitch = 0.9, Volume = 1 },
	Jellyfish = { Id = "rbxasset://sounds/splat.wav", Pitch = 1.9, Volume = 0.6 },
	Shark = { Id = "rbxasset://sounds/uuhhh.mp3", Pitch = 0.5, Volume = 1 },
}

-- 바다 생물 연출 (클라이언트, 2026-10-09)
Config.SeaEffects = {
	InkColor = Color3.fromRGB(25, 20, 35), -- 낙지 먹물 구름 색
	InkCloudTime = 2.5, -- 먹물 구름이 남는 시간(초)
	InkCloudSize = 5, -- 먹물 입자 크기
	InkScreen = 0.35, -- 먹물을 맞은 사람 화면 어두움 (0 = 깜깜, 1 = 그대로)
	PuffSound = "rbxasset://sounds/splat.wav", -- 복어가 부풀 때 "뿅"
	PuffPitch = 0.8,
}

-- 몹 화살·큰 기술 연출 (클라이언트 CombatController, 리모트 MobSpecial "Arrow"·"Telegraph"·"Impact", 2026-10-10)
Config.MobAttackEffects = {
	ArrowColor = Color3.fromRGB(205, 195, 170), -- 스켈레톤 궁수 화살 (뼈 색)
	ArrowTrail = Color3.fromRGB(255, 120, 90), -- 화살 꼬리 (빨갛게 → 날아오는 게 잘 보이게)
	ArrowSound = "rbxasset://sounds/swordslash.wav", -- 쏠 때 "휘익" (플레이어 활과 같은 소리, 낮게)
	ArrowPitch = 0.8,
	TelegraphColor = Color3.fromRGB(255, 60, 40), -- 바닥 경고 표시 색
	TelegraphTransparency = 0.55, -- 처음 투명도 (판정 직전 0.25까지 진해진다)
	WarnSound = "rbxasset://sounds/uuhhh.mp3", -- 기술 준비 "흐으읍"
	WarnPitch = 0.45,
	ImpactSound = "rbxassetid://9118608146", -- 쾅! (방망이 내려찍기와 같은 Rock Hits Rock을 더 낮게)
	ImpactPitch = 0.35,
	ImpactShakeRange = 40, -- 이 거리 안이면 화면이 흔들린다
	ImpactShake = 2.5, -- 흔들림 배수 (Config.HitFeel.CameraShake 기준)
	-- 거인마다 충격파 색
	Colors = {
		StoneGolem = Color3.fromRGB(150, 140, 125),
		FrostGiant = Color3.fromRGB(170, 225, 255),
		Behemoth = Color3.fromRGB(170, 80, 120),
	},
}

-- 사운드 에셋 ID (Creator Store 무료 사운드). 빈 값이면 재생하지 않는다
Config.Sounds = {
	HitNormal = "rbxassetid://9118608146", -- Rock Hits Rock (ProSoundEffects)
	HitPerfect = "rbxassetid://9120146349", -- Pickaxe Hit
	PickaxeClang = "rbxassetid://9125361455", -- 곡괭이 "깡!" (Anvil Hit, ProSoundEffects). 돌 소리에 겹쳐 재생
	WoodChop = "rbxassetid://9120950231", -- 도끼로 나무 찍는 "퍽" (ProSoundEffects). 나무 타격음
	-- 전투: 따로 찾기 전까지 있는 소리를 음높이만 바꿔 쓴다. TODO: 칼·활·방망이 전용 소리 찾기
	SwordHit = "rbxassetid://9125361455", -- 칼 (Anvil Hit을 높게)
	ClubHit = "rbxassetid://9118608146", -- 방망이 (Rock Hits Rock을 낮게)
	ArrowHit = "rbxassetid://9120950231", -- 화살이 맞아 데미지가 뜰 때 "퍽!" (Wood Chop)
	PlayerHurt = "rbxassetid://9118608146", -- 몹에게 맞음
	MobDie = "rbxassetid://17779566040", -- 몹이 펑 사라짐 (pop click을 낮게)
	BowShoot = "rbxasset://sounds/swordslash.wav", -- 활을 놓을 때 "휘익" (Roblox 기본 칼 휘두르는 소리). 2026-10-09 푸드덕(Bird Flying) 소리를 바꿈
	CritBurn = "rbxassetid://3406813517", -- 치명타 불꽃 (Power_Up을 높게)
	ChargeUp = "rbxassetid://3406813517", -- 차징: 기운이 차오르는 소리 (Power_Up, 모일수록 음이 올라간다). TODO: 전용 소리
	Eat = "rbxassetid://17779566040", -- 먹기 (pop click)
	TreeBreak = "rbxassetid://9120963881", -- 나무가 갈라지며 쓰러지는 소리 (ProSoundEffects)
	JudgmentPop = "rbxassetid://17779566040", -- minimal pop click
	RockBreak = "rbxassetid://9118587698", -- Rock Drop On Concrete Breaks (ProSoundEffects)
	FeverStart = "rbxassetid://3406813517", -- Power_Up
	FeverTap = "rbxassetid://133564751966469", -- Platformer Jump (Daily Sounds), 연타할 때 튀는 "뿅"
	FeverTapSparkle = "rbxassetid://130378474223829", -- Coin Pickup (Daily Sounds), "뿅"에 겹치는 반짝임
	FeverBurst = "rbxassetid://138533090376585", -- Explosion Blast Impact Boom
	MineEnter = "rbxassetid://9114353038", -- 광산 입장 음악: Evil Drone Deep Airy Swell (ProSoundEffects)
	MineAmbient = "rbxassetid://9125351901", -- 광산 배경음: Afterworld Ambience (ProSoundEffects), 반복
	CaveDrip = "rbxassetid://9126190654", -- 동굴 물방울 (ProSoundEffects), 반복
	BatFlap = "rbxassetid://9113443901", -- 박쥐 날갯짓: Bird Flying (ProSoundEffects)를 높은 음으로
}

-- 횃불: 밤에 마을·길을 밝힌다 (2026-10-09 사용자 요청: 밤에 너무 깜깜함). 제작 스크립트 studio/BuildTorches, 켜고 끄기 TorchService
Config.Torches = {
	-- 불빛 (따뜻한 주황, 무섭지 않게)
	LightColor = Color3.fromRGB(255, 176, 96),
	FlameColor = Color3.fromRGB(255, 150, 60),
	TownRange = 26, -- 마을 가로등 불빛 거리(스터드)
	TownBrightness = 1.9,
	RoadRange = 22, -- 길 횃불 불빛 거리
	RoadBrightness = 1.5,
	ShadowEvery = 6, -- 마을 가로등 몇 개마다 하나만 그림자 켜기 (0 = 모두 끔, 성능)
	UseFire = true, -- 길 횃불에 Fire 효과 (끄면 빛나는 불꽃 부품만)
	-- 켜는 시간: 해 지기 LightBefore시간 전 ~ 해 뜨고 LightAfter시간 뒤 (Config.DayNight 시각 기준)
	LightBefore = 0.75,
	LightAfter = 0.5,
	-- 마을 (TownArrival 둘레). 마을 반경 = 가장 먼 NPC 거리 + TownMargin (최소 TownMinRadius)
	TownMargin = 10,
	TownMinRadius = 28,
	PlazaRadius = 12, -- 광장 가운데 둘레 가로등
	PlazaCount = 5,
	PerNpc = 1, -- NPC 가판대마다 가로등 수
	NpcDistance = 7, -- NPC에서 떨어뜨리는 거리
	TownRings = { -- 마을 둘레 고리 (Scale = 마을 반경 배수)
		{ Scale = 0.6, Count = 6 },
		{ Scale = 1.0, Count = 10 },
		{ Scale = 1.55, Count = 14 },
	},
	TownMinGap = 9, -- 마을 가로등끼리 최소 간격
	KeepAway = 6, -- 도착점·광산 입구에서 이만큼 떨어뜨린다
	-- 길 (지형을 격자로 찍어서 찾는다)
	RoadScanRadius = 300, -- 마을에서 이 거리까지 길을 찾는다
	RoadScanStep = 4, -- 격자 간격(스터드)
	DirtRoadMaxWidth = 20, -- 흙(Ground·Mud) 띠가 이보다 좁으면 흙길로 본다 (넓으면 그냥 흙밭)
	RoadSpacing = 40, -- 길 횃불 간격(다른 횃불과의 최소 거리)
	RoadSideOffset = 2.5, -- 길 가장자리에서 바깥으로 더 밀기
	RoadSideSearch = 16, -- 길 가장자리를 찾는 최대 거리
	MaxRoadTorches = 90,
	-- 길을 거의 못 찾으면 마을 → 광산 입구 직선을 따라 세운다
	RouteFallbackMin = 3, -- 길 횃불이 이보다 적으면 직선 경로 사용
	RouteSpacing = 40,
	RouteSideOffset = 5,
}

-- 측정 로그
Config.Analytics = {
	PrintToOutput = true,
}

return Config
