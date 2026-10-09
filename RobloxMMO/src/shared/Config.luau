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
	GhostColor = Color3.fromRGB(255, 200, 0), -- 잔상 테두리 색
	GhostFlashColor = Color3.fromRGB(255, 255, 255), -- 바위 크기에 닿는 순간 색 ("지금!" 신호)
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
	NoticeInterval = 4, -- "더 좋은 장비가 필요해요" 알림 간격(초)
}

-- 희귀 나무: 후보 자리(스폰 파트 속성 RandomPool) 중 Active개만 동시에 서 있고, 베면 다른 빈 자리에 다시 생긴다
Config.RandomPools = {
	Ebony = { Active = 2 },
}

-- 곡괭이 데미지와 대장장이 판매 가격
-- 데미지 = BaseDamage × Power × 판정 배수 (2026-10-09 결정: 1 / 1.5 / 2 / 3)
-- TODO(미정): 가격은 임시값. 기획서 목표(T2 3분, T3 17분, T4 1시간)에 맞춰 조정
-- 도끼도 같은 표에 둔다. 손잡이에 통나무가 들어간다 (2026-10-09 결정)
Config.Pickaxes = {
	StonePickaxe = { Power = 1 }, -- 시작 지급
	CopperPickaxe = { Power = 1.5, Price = { Gold = 50, Items = { Oak = 3 } } },
	IronPickaxe = { Power = 2, Price = { Gold = 250, Items = { CopperIngot = 5, Birch = 3 } } },
	SteelPickaxe = { Power = 3, Price = { Gold = 1000, Items = { SteelIngot = 5, Maple = 3 } } }, -- 다이아몬드 곡괭이
	StoneAxe = { Power = 1 }, -- 시작 지급
	CopperAxe = { Power = 1.5, Price = { Gold = 50, Items = { CopperIngot = 2, Pine = 3 } } },
	IronAxe = { Power = 2, Price = { Gold = 250, Items = { IronIngot = 3, Birch = 3 } } },
	DiamondAxe = {
		Power = 3,
		Price = { Gold = 1000, Items = { SteelIngot = 5, Maple = 3 } },
		LightningChance = 0.2, -- 나무를 칠 때 이 확률로 번개가 내려쳐 한 방에 벤다 (2026-10-09 사용자 요청)
	},
}

-- 마나: 스킬·차징 스매시·달리기에 쓴다 (스킬·차징은 나중에). 플레이어 속성 Mana·MaxMana·Sprinting
Config.Mana = {
	Max = 100,
	Regen = 2.5, -- 1초에 차는 양 (달리는 중이 아닐 때). 2026-10-09 절반으로 (천천히 참)
	RegenDelay = 1.5, -- 마나를 쓴 뒤 이만큼 지나야 다시 찬다(초)
}

-- 이동: 달리기 모드 (오른쪽 버튼으로 켜고 끈다. 움직이는 동안 마나가 계속 준다)
Config.Movement = {
	WalkSpeed = 16, -- 평소 속도 (Roblox 기본)
	SprintSpeed = 26, -- 달리기 속도
	SprintManaPerSecond = 4, -- 달리는 동안 1초에 쓰는 마나. 2026-10-09 절반으로 (천천히 닳음)
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
	TierMultiplier = { 1, 2.2, 4, 7 },
	ToolAtkPerPower = 6, -- 곡괭이·도끼를 들고 있으면 공격 = Power × 이 값 (무기는 Config.Weapons의 Damage)
	PowerWeights = { Atk = 3, Def = 4, Hp = 1, Crit = 15 },
	BaseMaxHealth = 100,
	-- 사냥꾼 상점 가격 (단계별, 모든 장비 공통)
	Prices = {
		{ Gold = 40, Items = { OldCloth = 3 } },
		{ Gold = 150, Items = { CopperIngot = 3, Bone = 2 } },
		{ Gold = 500, Items = { IronIngot = 4, CerberusFang = 2 } },
		{ Gold = 1800, Items = { SteelIngot = 5, CyclopsEye = 3 } },
	},
}

-- 장비 겉모습 (GearVisualService): 끼운 장비가 캐릭터 몸에 보인다. 크기는 전부 몸 부위 크기에 대한 배율
Config.GearVisual = {
	Padding = 1.1, -- 손·발·몸통을 덮는 조각은 부위보다 이 배율만큼 크게
	HelmetScale = 1.18, -- 투구 둥근 껍데기 지름 = 머리 크기 × 이 값
	ArmorDepth = 1.25, -- 갑옷 몸통 덮개의 앞뒤 두께 = 몸통 두께 × 이 값
	PlateThickness = 0.12, -- 가슴판 두께 (몸통 두께 대비)
	PauldronScale = { 1.45, 1.75 }, -- 어깨 보호대 지름 (팔 굵기 대비): 3단계, 4단계
	CuffScale = 1.3, -- 장갑·장화 목 둘레 지름 (팔다리 굵기 대비)
	BraceletScale = 1.45, -- 팔찌 지름 (팔 굵기 대비). 장갑 목보다 커야 바깥에 보인다
	NecklaceGap = 0.05, -- 목걸이를 갑옷(또는 가슴) 앞으로 띄우는 거리 (몸통 두께 대비)
	GemSize = 0.12, -- 보석 크기 (부위 너비 대비)
	GemColor = Color3.fromRGB(120, 240, 255), -- 다이아몬드 장비의 빛나는 보석 색
	GlowBrightness = 0.6, -- 다이아몬드 투구·갑옷 보석의 은은한 빛 밝기
	GlowRange = 5, -- 그 빛이 닿는 거리(스터드)
	DiamondSparkles = false, -- true면 다이아몬드 갑옷에 반짝이 효과도 붙인다
	HideHairWithHelmet = true, -- 투구를 쓰면 머리카락·모자 액세서리를 숨긴다 (벗으면 되돌림)
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
}
Config.FoodCooldown = 10 -- 같은 음식을 다시 먹으려면 기다리는 시간(초). 칸 위에 시계 방향 덮개로 보인다 (2026-10-09)

-- 무기: 데미지·쿨다운(초)·사거리(스터드)·대장장이 아닌 사냥꾼 판매 가격
-- 칼은 빠르고, 방망이는 느리지만 세고 밀쳐 내고, 활은 약하지만 멀리서 쏜다
-- TODO(미정): 수치와 가격은 임시값. 플레이테스트로 조정
Config.Weapons = {
	WoodenSword = { Damage = 8, Cooldown = 0.5, Range = 7 }, -- 시작 지급
	CopperSword = { Damage = 13, Cooldown = 0.5, Range = 7.5, Price = { Gold = 80, Items = { CopperIngot = 3, Oak = 2 } } },
	IronSword = { Damage = 20, Cooldown = 0.5, Range = 8, Price = { Gold = 300, Items = { IronIngot = 5, Birch = 2 } } },
	DiamondSword = { Damage = 32, Cooldown = 0.5, Range = 9, Price = { Gold = 1200, Items = { SteelIngot = 6, Maple = 2 } } },
	WoodenBow = { Damage = 7, Cooldown = 0.8, Range = 40, Price = { Gold = 30, Items = { Pine = 5 } } },
	CopperBow = { Damage = 11, Cooldown = 0.8, Range = 45, Price = { Gold = 100, Items = { CopperIngot = 2, Birch = 3 } } },
	IronBow = { Damage = 17, Cooldown = 0.8, Range = 50, Price = { Gold = 350, Items = { IronIngot = 4, Maple = 3 } } },
	DiamondBow = { Damage = 27, Cooldown = 0.8, Range = 55, Price = { Gold = 1300, Items = { SteelIngot = 5, Ebony = 2 } } },
	BaseballBat = { Damage = 12, Cooldown = 0.9, Range = 6.5, Knockback = 4, Price = { Gold = 30, Items = { Oak = 5 } } },
	GoblinClub = { Damage = 20, Cooldown = 0.9, Range = 6.5, Knockback = 5, Price = { Gold = 120, Items = { CopperIngot = 3, Oak = 4 } } },
	MorningStar = { Damage = 31, Cooldown = 0.9, Range = 7, Knockback = 6, Price = { Gold = 400, Items = { IronIngot = 6, Bone = 5 } } },
	DiamondMace = { Damage = 48, Cooldown = 0.9, Range = 7.5, Knockback = 8, Price = { Gold = 1500, Items = { SteelIngot = 7, CyclopsEye = 3 } } },
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
	},
}

-- 몹 수치 (정의는 MobDefs). TODO(미정): 임시값
-- Hp 체력, Damage 한 번에 플레이어에게 주는 피해(플레이어 체력 100), AttackInterval 공격 간격(초), AttackRange 공격 거리
-- Speed 이동 속도(스터드/초), Aggro 플레이어를 알아채는 거리, Gold 골드 범위, Loot 전리품 개수 범위, Respawn 다시 나오는 시간(초)
-- Scale 모델 크기 배율. 생성 자리·마리 수는 Config.MobZones (몹 구역)
-- Passive = true면 먼저 공격하지 않고, 맞으면 FleeTime초 동안 때린 사람 반대쪽으로 Speed × FleeSpeed로 도망친다 (피해 0)
Config.Mobs = {
	Slime = { Hp = 20, Damage = 0, AttackInterval = 1.5, AttackRange = 3.5, Speed = 7, Aggro = 18, Gold = { 2, 5 }, Loot = { 1, 2 }, Respawn = 10, Scale = 0.9, Passive = true, FleeTime = 4, FleeSpeed = 1.5 },
	Skeleton = { Hp = 40, Damage = 8, AttackInterval = 1.4, AttackRange = 4, Speed = 9, Aggro = 22, Gold = { 5, 9 }, Loot = { 1, 2 }, Respawn = 18, Scale = 1 },
	Zombie = { Hp = 55, Damage = 10, AttackInterval = 1.6, AttackRange = 4, Speed = 6, Aggro = 20, Gold = { 7, 12 }, Loot = { 1, 2 }, Respawn = 18, Scale = 1 },
	Cerberus = { Hp = 90, Damage = 14, AttackInterval = 1.2, AttackRange = 4.5, Speed = 13, Aggro = 26, Gold = { 14, 24 }, Loot = { 1, 2 }, Respawn = 30, Scale = 1.1 },
	-- 사이클롭스: 플레이어 키의 약 1.8배 (모델 높이 약 6.6 × Scale 1.4)
	Cyclops = { Hp = 160, Damage = 18, AttackInterval = 1.8, AttackRange = 6.5, Speed = 9, Aggro = 26, Gold = { 25, 40 }, Loot = { 1, 3 }, Respawn = 45, Scale = 1.4 },
}

-- 몹 구역 (2026-10-09): 구역마다 한 종류의 몹이 모여 산다. 마을에서 멀수록 센 몹
-- Distance 마을 중심(TownArrival)에서 구역 가운데까지 거리 범위, Radius 구역 반경, Count 생성 자리 수
-- BossSpots 구역마다 보스가 잘 나오는 자리 수 (Config.MobBoss.SpotChance)
-- 제작 스크립트(studio/BuildWeaponsAndMobs)가 게임 시작 때 구역 가운데와 생성 자리를 고른다
Config.MobZones = {
	{ Name = "슬라임 들판", MobType = "Slime", Count = 16, Distance = { 75, 115 }, Radius = 30, BossSpots = 1 },
	{ Name = "슬라임 언덕", MobType = "Slime", Count = 14, Distance = { 80, 125 }, Radius = 26, BossSpots = 1 },
	{ Name = "스켈레톤 무덤", MobType = "Skeleton", Count = 7, Distance = { 125, 175 }, Radius = 24, BossSpots = 1 },
	{ Name = "좀비 숲", MobType = "Zombie", Count = 7, Distance = { 125, 175 }, Radius = 24, BossSpots = 1 },
	{ Name = "케르베로스 굴", MobType = "Cerberus", Count = 4, Distance = { 180, 230 }, Radius = 22, BossSpots = 1 },
	{ Name = "사이클롭스 골짜기", MobType = "Cyclops", Count = 3, Distance = { 215, 270 }, Radius = 24, BossSpots = 1 },
}
Config.MobZoneLayout = {
	ZoneGap = 70, -- 구역 가운데끼리 최소 거리 (서로 섞이지 않게)
	SpawnGap = 7, -- 생성 자리끼리 최소 거리
	ObstacleGap = 25, -- 광산 입구 같은 시설에서 떨어질 거리
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
	StartSlots = 10, -- 처음 가방 칸 수
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
	StudioStoreName = "PlayerData_Studio_v1", -- Studio 테스트 저장소 (테스트 지급이 실제 저장에 섞이지 않게)
	AutoSaveInterval = 60, -- 자동 저장 간격(초)
	Retries = 3, -- 실패하면 다시 시도하는 횟수
	LockTimeout = 90, -- 다른 서버의 잠금이 이 초보다 오래됐으면 버려진 것으로 본다
	LockWaitTries = 4, -- 잠겨 있으면 몇 번 기다렸다 다시 시도하는지
	LockWaitSeconds = 3, -- 기다리는 간격(초)
	CleanupDelay = 5, -- 나간 뒤 가방·장비 정보를 지우기 전 기다리는 시간(초). 저장이 먼저 모아 가도록
}

Config.Debug = {
	GiveAllPickaxes = true, -- true면 들어올 때 곡괭이·도끼를 전부 지급 (테스트용, 2026-10-09 사용자 요청으로 켬)
	GiveReturnScrolls = 5, -- 들어오면 귀환 주문서를 이만큼 지급. 테스트 끝나면 0
	StartSlots = 60, -- Studio 테스트 때 가방 칸 수 (도구·무기·장비를 전부 받으면 45칸이 넘는다)
	GiveAllEquipment = true, -- Studio에서 들어오면 장비 24종을 전부 지급 (테스트용)
	GiveFoods = 5, -- Studio에서 들어오면 음식을 종류마다 이만큼 지급. 테스트 끝나면 0
}

-- 귀환 주문서: 쓰면 CastTime초 뒤 마을(태그 TownArrival)로 돌아간다. 그사이 움직이면 취소
Config.ReturnScroll = {
	CastTime = 2.5,
	CancelMoveDistance = 2, -- 이만큼(스터드) 움직이면 취소
}

-- 상인이 파는 잡화 (순서대로 표시). TODO(미정): 가격은 임시값
Config.MerchantGoods = {
	{ ItemId = "ReturnScroll", Price = 15 },
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
	CopperIngot = 12,
	IronIngot = 20,
	SteelIngot = 60,
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
}

-- 대장장이 제련: 재료 + 수수료(골드) → 결과 1개
-- TODO(미정): 수수료는 임시값
Config.Smelting = {
	Order = { "CopperIngot", "IronIngot", "SteelIngot" }, -- UI 표시 순서
	Recipes = {
		CopperIngot = { Inputs = { CopperOre = 2, Coal = 1 }, Fee = 2 },
		IronIngot = { Inputs = { IronOre = 2, Coal = 1 }, Fee = 4 },
		SteelIngot = { Inputs = { IronIngot = 2, Coal = 2 }, Fee = 10 },
	},
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
		[3] = { Name = "광산 3층", RequiredTier = 4, Locked = true }, -- 공사 중
	},
	PromptDistance = 8, -- 이동 발판 ProximityPrompt 거리(스터드)
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

-- 미니맵 (클라이언트 전용). 동굴 안에서는 가 본 칸만 보인다
Config.Minimap = {
	Size = 220, -- 지도 크기(픽셀)
	OutdoorScale = 0.6, -- 밖: 1스터드당 픽셀
	CaveScale = 1.6, -- 동굴: 1스터드당 픽셀
	RockRange = 160, -- 이 거리 안의 바위만 점으로 표시(스터드)
	VisitRadius = 13, -- 칸 중심에서 이 거리 안에 들어가면 그 칸을 밝힌다(스터드)
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
	},
	TierEffects = {
		[2] = { Color = Color3.fromRGB(235, 140, 70), Chunks = 3, Ring = 3.5, Shake = 1.2, Sparkle = false },
		[3] = { Color = Color3.fromRGB(225, 230, 240), Chunks = 6, Ring = 5, Shake = 1.45, Sparkle = false },
		[4] = { Color = Color3.fromRGB(110, 235, 255), Chunks = 9, Ring = 7, Shake = 1.75, Sparkle = true },
	},
}

-- 배경음악 (2026-10-09, MusicController). 밖에서 차례로 틀고 광산에서는 줄인다
-- TODO: 곡 Id는 팬 사이트 목록에서 고른 잔잔한 곡(Spirit LoFi "Calm Waves"·"Easy Flow", APM "Ruins of Tomorrow"). 안 나오면 Creator Store에서 찾아 바꾸기
Config.Music = {
	Tracks = {
		"rbxassetid://76350635489391", -- Calm Waves
		"rbxassetid://140319470451829", -- Easy Flow
		"rbxassetid://111916174750874", -- Ruins of Tomorrow (APM)
	},
	Volume = 0.25, -- 밖에서 볼륨
	MineVolume = 0, -- 광산 안 볼륨 (광산 배경음이 따로 있다)
	FadeTime = 2, -- 볼륨이 바뀌는 시간(초)
	GapBetweenTracks = 3, -- 곡 사이 쉬는 시간(초)
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

-- 측정 로그
Config.Analytics = {
	PrintToOutput = true,
}

return Config
