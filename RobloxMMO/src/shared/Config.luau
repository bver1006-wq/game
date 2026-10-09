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
	DiamondAxe = { Power = 3, Price = { Gold = 1000, Items = { SteelIngot = 5, Maple = 3 } } },
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
Config.Debug = {
	GiveAllPickaxes = false, -- true면 들어올 때 곡괭이·도끼를 전부 지급 (테스트용)
	GiveReturnScrolls = 5, -- 들어오면 귀환 주문서를 이만큼 지급. 테스트 끝나면 0
}

-- 귀환 주문서: 쓰면 CastTime초 뒤 마을(태그 TownArrival)로 돌아간다. 그사이 움직이면 취소
Config.ReturnScroll = {
	CastTime = 2.5,
	CancelMoveDistance = 2, -- 이만큼(스터드) 움직이면 취소
}

-- 상인이 파는 잡화 (순서대로 표시). TODO(미정): 가격은 임시값
Config.MerchantGoods = {
	{ ItemId = "ReturnScroll", Price = 15 },
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
}

-- 바위 하나당 산출량: 랜덤 BaseMin~BaseMax개 (판정과 상관없음)
-- 여러 명이 같이 캤으면 기여도(준 데미지 비율)대로 나눈다. 피버 보너스는 피버를 연 사람에게 더한다
Config.Reward = {
	BaseMin = 2, -- 기본 개수 최소
	BaseMax = 5, -- 기본 개수 최대
	MinPerContributor = 1, -- 조금이라도 친 사람은 최소 이만큼 받는다
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
	-- 탭 수 기준 보너스 개수 (MinTaps 이상이면 해당 보너스, 큰 값부터 검사)
	Tiers = {
		{ MinTaps = 40, Bonus = 5 },
		{ MinTaps = 30, Bonus = 4 },
		{ MinTaps = 20, Bonus = 3 },
		{ MinTaps = 10, Bonus = 2 },
		{ MinTaps = 0, Bonus = 1 },
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
	OreChunkMax = 15, -- 깨질 때 튀어나오는 광석 조각 최대 개수 (보상이 더 많아도 이 이상은 안 그림)
	OreSuckDelay = 0.4, -- 광석이 쏟아진 뒤 캐릭터에게 빨려오기까지(초)
	OreSuckDuration = 0.35, -- 빨려오는 시간(초)
	JudgmentPopupDuration = 0.8, -- Perfect!/Nice! 말풍선이 떠 있는 시간(초)
	HpBarRange = 12, -- 이 거리 안의 가장 가까운 바위에 체력바 표시(스터드)
	-- 좋은 곡괭이일수록 강한 타격 연출: 충격파 고리, 튀는 광석 조각, 카메라 흔들림
	-- Chunks: 튀는 조각 수, Ring: 충격파 최대 크기(스터드), Shake: 카메라 흔들림 배수, Sparkle: 반짝이 가루
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
	TierEffects = {
		[2] = { Color = Color3.fromRGB(235, 140, 70), Chunks = 3, Ring = 3.5, Shake = 1.2, Sparkle = false },
		[3] = { Color = Color3.fromRGB(225, 230, 240), Chunks = 6, Ring = 5, Shake = 1.45, Sparkle = false },
		[4] = { Color = Color3.fromRGB(110, 235, 255), Chunks = 9, Ring = 7, Shake = 1.75, Sparkle = true },
	},
}

-- 사운드 에셋 ID (Creator Store 무료 사운드). 빈 값이면 재생하지 않는다
Config.Sounds = {
	HitNormal = "rbxassetid://9118608146", -- Rock Hits Rock (ProSoundEffects)
	HitPerfect = "rbxassetid://9120146349", -- Pickaxe Hit
	PickaxeClang = "rbxassetid://9125361455", -- 곡괭이 "깡!" (Anvil Hit, ProSoundEffects). 돌 소리에 겹쳐 재생
	WoodChop = "rbxassetid://9120950231", -- 도끼로 나무 찍는 "퍽" (ProSoundEffects). 나무 타격음
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
