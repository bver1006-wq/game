# 프로젝트: 로블록스 생활형 샌드박스 MMORPG (가칭 미정)

이 파일은 Claude Code가 작업 전에 읽는 프로젝트 정의서다. 기획 원문은 claude.ai의 "로블록스 MMORPG MVP 정의서"이며, 이 파일은 그중 **구현에 필요한 내용**만 추렸다. 둘이 충돌하면 사람에게 먼저 물어볼 것.

---

## 1. 게임 한 줄 요약

마나 기반 산업화 세계관의 생활형 샌드박스 MMORPG. 플레이어는 직업(채광, 벌목, 요리 등)을 키우고, 각 직업의 생산물이 서로 필요하도록 연결된 경제 안에서 성장한다.

**MVP의 목표는 출시가 아니라 검증이다.**
> "휘둘러 캐는 채굴 → 제련·제작 → 판매 → 곡괭이 업그레이드" 루프가 재미있는가?

---

## 2. 단계와 관문 (관문을 통과해야 다음 단계로 간다)

| 단계 | 기간(추정) | 범위 | 통과 관문 |
|---|---|---|---|
| MVP-0 손맛 (2026-10-09 관문 통과로 판단) | 약 2주 | 채굴 한 판만. 판매·성장 없음. 타격감 완성 | 1분 동안 캐도 지루하지 않음 |
| **MVP-1 핵심 루프** ← 현재 | 약 4주 | 광석 4종, 제련, 곡괭이 T1~T4, NPC 판매, 트로피, 저장 | 처음 해본 5명 중 3명이 스스로 15분 이상 플레이 |
| MVP-2 직업 연결 | 약 4주 | 벌목, 버프 요리, 개인 부지 설비 3칸, 1:1 거래 | 직업 간 거래가 생김 |

관문을 통과하지 못하면 새 기능을 더하지 말고 그 단계를 고친다.

---

## 3. 작업 규칙 (Claude Code가 반드시 지킬 것)

1. **서버가 결정한다.** 광석, 골드, 인벤토리, 판정, 보상은 전부 서버에서 계산한다. 클라이언트는 "휘둘렀다" 같은 입력만 보낸다. 클라이언트가 보낸 대상·데미지·결과를 그대로 믿지 않는다.
2. **연출은 클라이언트가 한다.** 히트스톱, 카메라 흔들림, 파티클, 소리 같은 효과는 서버가 RemoteEvent로 "어디서 무슨 판정이 났다"만 알리고 각 클라이언트가 재생한다.
3. **숫자는 코드에 박지 않는다.** 모든 밸런스 수치는 `ReplicatedStorage/Shared/Config` 모듈에 모은다. 플레이테스트로 계속 바뀐다.
4. **한 번에 한 시스템씩.** 한 작업이 끝나면 테스트 방법(Studio에서 무엇을 눌러 확인할지)을 알려주고 멈춘다.
5. **Luau 스타일:** 파일 상단 `--!strict`, ModuleScript 중심 구조, 함수·모듈마다 한국어 주석.
6. **범위 밖 기능 금지:** 7장 "MVP에서 제외하는 것"에 있는 기능은 요청이 있어도 먼저 확인받는다.

---

## 4. 개발 환경과 폴더 구조

### 연동 방식
- 기본: **Rojo**로 로컬 파일과 Roblox Studio를 동기화하고, Git으로 버전 관리한다.
- 보조: Studio 내장 MCP 서버로 Claude Code가 Studio 상태(파트 배치, 출력 로그)를 확인한다.
- 맵·모델(바위 모양, 마을 건물)은 Studio에서 직접 만들고, 스크립트는 전부 파일로 관리한다.

### 폴더 구조 (Rojo 기준)
```
src/
├─ server/                      → ServerScriptService
│  ├─ Main.server.luau          서버 진입점, 서비스 초기화
│  └─ Services/
│     ├─ OreService.luau        광석 노드 생성·리스폰·체력
│     ├─ MiningService.luau     휘두르기 요청 검증, 판정, 보상
│     ├─ TimingService.luau     타이밍 판정(잔상 기준)·약점 위치 결정
│     ├─ FeverService.luau      피버 발동·연타 집계
│     ├─ AntiCheatService.luau  쿨다운, 거리, 매크로 탐지
│     ├─ AnalyticsService.luau  플레이테스트 측정 로그
│     ├─ DataService.luau       저장 (DataStore, 세션 잠금·자동 저장, 2026-10-09)
│     ├─ InventoryService.luau  (MVP-1) 가방
│     ├─ EconomyService.luau    (MVP-1) 골드, NPC 판매
│     ├─ CraftingService.luau   (MVP-1) 제련, 곡괭이 제작 (도구·무기 구매 buyTool)
│     ├─ MobService.luau        몹 생성·AI·체력·처치 보상 (2026-10-09 추가)
│     ├─ CombatService.luau     무기 공격 검증·데미지, 사냥꾼 무기 판매 (2026-10-09 추가)
│     ├─ OwnershipService.luau  바위·나무·몹 주인 정하기 (2026-10-09 추가)
│     ├─ SkillService.luau      구르기·무기별 스킬 검증 (2026-10-09 추가)
│     └─ TrophyService.luau     (MVP-1) 트로피, 뱃지
├─ client/                      → StarterPlayerScripts
│  ├─ Main.client.luau
│  └─ Controllers/
│     ├─ InputController.luau   PC 클릭 / 모바일 공격 버튼
│     ├─ TargetController.luau  가장 가까운 바위 자동 조준
│     ├─ TimingGhostController.luau 타이밍 잔상(흐릿한 바위가 줄어듦) 표시
│     ├─ SwingAnimation.luau    휘두르기 애니메이션, 히트스톱
│     ├─ HitFeelController.luau 히트스톱, 카메라, 파티클, 소리
│     ├─ RockHUD.luau           바위 체력바, 판정 문구, 획득량 (BillboardGui)
│     ├─ FeverController.luau   피버 연출, 연타 입력
│     ├─ CombatController.luau  무기 공격·몹 조준·타격/처치 연출·몹 체력바 (2026-10-09 추가)
│     └─ SkillController.luau   구르기(Q)·스킬 칸(F) 버튼·입력·연출 (2026-10-09 추가)
└─ shared/                      → ReplicatedStorage/Shared
   ├─ Config.luau               모든 밸런스 수치
   ├─ OreDefs.luau              자원 노드(광석·나무) 정의
   ├─ PickaxeDefs.luau          손에 드는 도구(곡괭이·도끼·칼·활·방망이) 정의
   ├─ MobDefs.luau              몹 정의
   ├─ EquipmentDefs.luau        장비 칸·장비 아이템 정의
   ├─ TierDefs.luau             단계(티어) 이름·색·별·단계별 표 고르기 (2026-10-09)
   └─ Remotes.luau              RemoteEvent 이름 목록
```

### 사용자 PC 작업 방식 (2026-10-09)
- 사용자 PC: GitHub Desktop으로 클론한 `Documents\GitHub\game\RobloxMMO`에서 Rojo 서버 실행 (rojo.exe를 폴더에 넣어 둠, .gitignore로 제외)
- `StartDev.bat` 더블클릭: Rojo를 켜고 30초마다 main을 자동 pull. 그래서 클라우드 작업은 main에 합쳐 둔다 (사용자 허락)
- 사용자는 코딩을 모른다. 설명은 짧고 한 단계씩

### Studio 쪽 배치
- `ServerStorage/Templates/Ores/<광석>/` 바위 원본. 광석마다 폴더 안에 모양 변형 모델 여러 개 (생성 때 랜덤 선택)
- `ServerStorage/Templates/Pickaxes/` 곡괭이·도끼 Tool 원본
- `ServerStorage/Templates/Ores/<나무>/` 나무 원본도 같은 폴더 (기준점은 줄기 밑동)
- `Workspace/OreSpawns/` 생성 위치 표시용 투명 Part (속성 `OreType`, `Floor`)
- `Workspace/Ores/` 실행 중 생성된 바위가 들어가는 폴더
- 바위 식별은 `CollectionService` 태그 `"OreNode"` + 속성(Attributes)으로 한다.

---

## 5. MVP-0: 지금 구현할 것 (채굴 한 판의 손맛)

### 5-1. 채굴 방식 개요
화면 전환 없이 세계 안에서 바위에 다가가 휘둘러 캔다. 바위 하나가 곧 한 판이고, 바위가 깨질 때 광석이 한꺼번에 쏟아진다.

1. 바위 근처에 가면 바위 위에 체력바가 뜬다.
2. 클릭(PC) 또는 공격 버튼(모바일)으로 휘두른다. 가장 가까운 바위를 자동 조준한다.
3. 바위를 치면 **노란 형광 잔상**(바위의 1.5배)이 바위 크기로 줄어든다. 줄어드는 시간은 타격마다 0.9~1.4초 랜덤(서버가 정함). 딱 맞는 순간 다시 치면 Perfect, 조금 어긋나면(약 0.3초) Nice, 그 외는 일반. Perfect/Nice는 바위 위에 뾰족한 말풍선으로 표시.
4. 가끔 바위의 다른 면에 **약점**이 반짝인다. 그쪽으로 돌아가서 치면 보너스.
5. 체력이 0이 되면 바위가 갈라지며 광석이 쏟아지고 획득량이 표시된다.

### 5-2. 판정과 수치 (Config에 둘 출발점 값)

| 판정 | 데미지 배수 | 연출 |
|---|---|---|
| Perfect | 2배 | 큰 파편, 다른 타격음, 금색 말풍선 "Perfect!" |
| Nice | 1.5배 | 중간 파편, 하늘색 말풍선 "Nice!" |
| 일반 | 1배 | 작은 파편 |

- **판정은 데미지에만 반영하고 산출량에는 영향 없음** (2026-10-09 변경).
- 출발점: 휘두르기 간격 0.8초, 잔상 0.9~1.4초, 데미지 1
- HP: 돌 9 / 구리 15 / 철 29 (T1 곡괭이로 Perfect 연속이면 5 / 8 / 15타, 일반만이면 9 / 15 / 29타. 2026-10-09 결정)
- 잔상은 바위를 복제한 ForceField 재질(안쪽은 비치고 가장자리만 빛나는 돌 모양 테두리). 바위 크기와 겹치는 순간 흰색으로 번쩍일 때 치면 Perfect. Highlight 테두리는 반투명 물체에 안 그려져서 쓰지 않음
- 타격음은 돌 소리 + 곡괭이 "깡!" 금속음을 겹친다
- 휘두르는 동작은 0.3초 이내.
- 모바일은 타이밍 판정 범위를 PC보다 넓게 (기기별 값을 Config에 분리).

### 5-3. 보상 공식 (바위 하나당 광석 개수)

산출량 = 랜덤 5~10개 × 피버 배수(1.3~5배) (2026-10-09 변경, 모든 광물 공통)

- 여러 명이 같은 바위를 치면 5~10개를 기여도(준 데미지 비율)대로 나눈다. 피버를 연 사람은 자기 몫에 피버 배수를 곱한다.
- 주인 정하기(2026-10-09): 먼저 데미지를 준 사람이 주인이라 보통은 혼자 다 받는다 (아래 6장 진행 상황).
- 약점 보너스는 7단계(약점)에서 정한다.

### 5-4. 피버 (10% 확률, 마지막 일격에서 발동)
1. 멈춤 0.3초: 히트스톱, 소리 끊김
2. 회전 1초: 카메라가 바위 주위 반 바퀴, 균열에서 빛
3. "FEVER!" 문구 0.5초
4. 연타 4초: 탭할 때마다 바위가 흔들리고 배수 게이지가 참
5. 폭발 0.5초: 광석이 사방으로 쏟아지고 보너스 표시

| 4초 동안 탭 수 | 보상 배수 (2026-10-09 사용자 요청: 조금만 잘해도 3~5배) |
|---|---|
| 5회 미만 | x1.3 |
| 5~9회 | x1.5 |
| 10~15회 | x2 |
| 16~23회 | x3 |
| 24회 이상 | x5 |

- 연타는 초당 12회까지만 인정 (서버에서 집계).
- 카메라 회전은 설정에서 끌 수 있게. 피버 중 캐릭터는 무적.

### 5-5. 타격감 체크리스트 (MVP-0에서 모두 구현)
- [ ] 맞는 순간 0.05~0.08초 히트스톱 (클라이언트)
- [ ] 파편 파티클 + 카메라 미세 흔들림
- [ ] 타격음 음높이를 매번 조금씩 다르게 (PlaybackSpeed 랜덤)
- [ ] 바위가 맞을 때 짧게 떨림 (원래 위치 기준으로 복귀, 연속 타격에도 밀리지 않게)
- [ ] 바위가 깨질 때는 다른 소리와 더 큰 연출
- [ ] 광석이 튀어나와 캐릭터에게 빨려오는 연출
- [ ] 판정 문구와 획득량 숫자는 바위 위 BillboardGui
- [ ] 휘두르는 동작 0.3초 이내

> 사운드 에셋은 Creator Store 무료 사운드를 쓰고, 못 찾으면 `Config.Sounds`에 빈 값으로 두고 TODO 주석을 남긴다.

### 5-6. 기술적으로 구현해야 하는 핵심

**A. 타이밍 잔상 동기화 (가장 어려운 부분)**
- 잔상의 시작 시각은 **서버가 인정한 직전 타격 시각**이다. 서버가 HitEffect로 그 시각을 보내고, 클라이언트는 그 시각부터 잔상을 줄인다. 판정 목표 시각 = 직전 타격 + 잔상 시간.
- 시간 기준은 `workspace:GetServerTimeNow()`로 서버·클라이언트를 맞춘다.
- 클라이언트는 휘두를 때 자기 `GetServerTimeNow()` 값을 함께 보내고, 서버는 그 값이 서버 수신 시각과 너무 차이 나지 않는지(지연 허용치 이내인지) 확인한 뒤 판정을 계산한다. 허용치를 넘으면 수신 시각 기준으로 계산한다.
- 판정 범위(Perfect/Nice)는 Config에서 조정, 모바일은 별도 값.

**B. 휘두르기 요청 검증 (MiningService + AntiCheatService)**
- RemoteEvent `SwingRequest(targetRock, clientTime)`.
- 서버 확인 항목: 곡괭이를 들고 있는가, 대상이 `OreNode` 태그인가, 거리 약 8스터드 이내인가, 쿨다운이 지났는가, 이 곡괭이 티어로 캘 수 있는 광석인가.
- 약점 판정: 서버가 정한 약점 면의 방향과, 캐릭터가 바위를 바라보는 방향의 각도로 계산.

**C. 바위 상태 관리 (OreService)**
- 바위마다 HP, 기여도 테이블(플레이어별 누적 데미지), 판정 기록(플레이어별 Nice·Perfect 횟수), 약점 위치를 서버 메모리에 보관.
- 깨지면 보상 계산 → 바위 제거 → 리스폰 타이머 → 같은 자리에 재생성.

**D. 연출 브로드캐스트**
- 서버는 `HitEffect(rock, judgment, hitPosition)`, `RockBroken(rock, rewards)`를 RemoteEvent로 근처 플레이어에게 보낸다.
- 떨림, 파티클, 문구는 각 클라이언트가 로컬로 재생 (서버에서 바위를 직접 흔들지 않는다).

**E. 측정 로그 (AnalyticsService)**
- 접속 후 첫 곡괭이질까지 시간, 판 수, 판정 비율, 세션 길이를 Output에 출력하고 MVP-1부터 저장.

### 5-7. MVP-0 작업 순서
1. [x] Rojo 프로젝트 세팅, 폴더 구조, Config·Remotes 모듈
2. [x] 바위 템플릿 1종(돌) + OreService 생성·리스폰
3. [x] 곡괭이 Tool + 입력(PC/모바일) + 자동 조준 + 휘두르기 애니메이션
4. [x] SwingRequest 서버 검증 + HP 감소 + 깨짐 처리 (판정 없이 일반 타격만)
5. [x] 타격감 체크리스트 전부
6. [x] 타이밍 잔상 + Perfect/Nice 판정
7. [ ] 약점
8. [x] 보상 공식 + 획득량 표시 (MVP-0에서는 획득량 표시만, 저장 없음)
9. [x] 피버
10. [ ] 측정 로그
11. [ ] 관문 1 테스트: "1분 동안 캐도 지루하지 않은가"

---

## 6. MVP-1: 관문 1 통과 후 구현할 것 (요약)

### 광석 (4종)
| 광석 | 위치 | 판매가 | 쓰임 | 필요 곡괭이 |
|---|---|---|---|---|
| 돌 | 지상 | 1G | 초반 돈벌이, 이후 설비 재료 | T1 |
| 석탄 | 1층 | 2G | 모든 제련 연료 | T2 |
| 구리 | 1층 | 3G | 구리괴 → T2·T3 곡괭이 | T2 |
| 철 | 2층 | 6G | 철괴·강철괴 → T3·T4 곡괭이 | T3 |

### 제련 (공용 제련로, ProximityPrompt)
| 레시피 | 결과 | 판매가 |
|---|---|---|
| 구리 2 + 석탄 1 | 구리괴 1 | 10G |
| 철 2 + 석탄 1 | 철괴 1 | 20G |
| 철괴 2 + 석탄 2 | 강철괴 1 | 60G |

### 곡괭이 단계
| 단계 | 획득 | 목표 도달 시점 | 새로 열리는 것 |
|---|---|---|---|
| T1 돌 | 시작 지급 | 0분 | 지상 돌 |
| T2 구리 | 구리괴 3 + 손잡이, 또는 NPC 의뢰 | 3분 | 1층, 제련 |
| T3 철 | 레시피 + 철괴 15 + 구리괴 5, 또는 NPC 의뢰 | 17분 | 2층, 약점 표시 |
| T4 강철 | 레시피 + 강철괴 30 + 철괴 20, 또는 NPC 의뢰 | 약 1시간 | 동시 균열 2개 패턴, 3층 예고 |

- 직접 제작: 모루 타이밍 미니게임(약 5초, 3번 타이밍) → 품질 일반/고품질/명품, 옵션 0~2개
- 옵션(효과 5~10%): 빠름(휘두르기 +5%), 정밀(Perfect 범위 +10%), 행운(피버 +1%p), 넉넉(10번에 한 번 +1개)
- NPC 의뢰: 직접 제작의 약 3배 비용, 옵션 없음
- 레시피: NPC 대장장이 의뢰 완료 보상

### 구현할 시스템
- **DataService:** 저장 항목은 골드, 인벤토리, 보유 곡괭이와 품질·옵션, 트로피, 통계(판 수, 퍼펙트 수). 세션 잠금과 자동 저장을 지원하는 검증된 라이브러리(예: ProfileStore) 사용 검토. Studio 테스트 시 Game Settings → Security → API 서비스 접근 허용 필요.
- **InventoryService:** 가방 50칸 (약 2분에 가득 참)
- **EconomyService:** 골드, NPC 판매
- **CraftingService:** 제련, 곡괭이 제작, 모루 미니게임 판정 (서버 검증)
- **층 이동:** 광산 지상 / 1층 / 2층 / 3층(잠김, "공사 중"). 마을 ↔ 광산 이동 30초 이내
- **TrophyService:** 게임 내 트로피 10개, Roblox 공식 뱃지 2개("첫 곡괭이 제작", "T4 다이아몬드 곡괭이")
- **매크로 방어:** 휘두르는 간격이 기계처럼 일정하면 실력 보너스 제거. 시간당 획득량 상한, 넘으면 수익 점감

---

### MVP-1 진행 상황 (2026-10-09)
- [x] 가방(InventoryService): 칸 단위, 처음 10칸(한 칸 99개까지 쌓임, 도구는 1개 1칸), 상인에게 가방을 사서 15/20/30칸으로 확장 + 골드
- [x] 가방 UI(B 키 또는 왼쪽 위 가방 그림 버튼, 네모 없이 그림만): 아이콘 칸 + 아래 이름(ReplicatedStorage/ItemIcons 3D 모델), 분류 탭 전체/무기/방어구/도구/기타, 창 바깥 누르면 닫힘. 상점 목록도 아이콘으로 표시
- [x] 하단 빠른 호출 5칸: 가방에서 끌어다 놓기, 숫자키 1~5·클릭으로 도구 들기. Roblox 기본 도구 바는 끔
- [x] 곡괭이는 가방 아이템(도구). 산 곡괭이는 기존 것에 더해진다. Config.Debug.GiveAllPickaxes(Studio 전용)로 테스트 때 4종 지급
- [x] NPC 3명 (Workspace/NPCs, 태그 ShopNPC + 속성 ShopId): 대장장이(제련 + 곡괭이 판매), 상인(광석·괴 매입), 사냥꾼(준비 중)
  - 직업별 옷차림(부품을 WeldConstraint로 붙임)과 가판대(BlacksmithCorner / MerchantStall / HunterStall)
  - NPC 몸은 R15 기본 'Man' 패키지 + 공식 무료 머리카락(HumanoidDescription). 옷차림은 부품을 WeldConstraint로 붙임
  - 동작은 Roblox 기본 애니메이션(앉기 2506281703, 서 있기 507766388, 휘두르기 522635514)을 클라 NpcAnimator가 재생
  - 대장장이: 속성 Pose=Sit, Work=Hammer(망치질 + SparkPoint 불꽃·쇳소리). 모든 NPC는 가까이 가면 고개를 돌림
  - 상인 가판대는 광장 서쪽 가장자리(집 벽 앞)
  - 상인의 버프 음식·물약은 7장 제외 항목이라 "준비 중" 탭만 둠 (사용자 결정). 사냥꾼은 무기(칼·활·방망이)를 판다 (방어구·신발은 아직)
- [x] 제련: 재료 + 수수료(골드) → 괴. 곡괭이는 대장장이에게 골드(+괴)로 구매 (모루 미니게임 직접 제작은 아직)
- [x] 광산: 지상 동굴 입구(마을 동쪽, 바위 언덕 + 갱도 + 버팀목·랜턴·레일·광차, 스폰 위치 포함) + 1층(석탄·구리, T2) + 2층(철, T3) + 3층(미스릴·오리하르콘, T4, 2026-10-09 열림) + 4층 잠김
  - 층은 맵 밖(x=1200)에 지형(Terrain)으로 판 6x6 미로 동굴 (통로 폭 16, 칸 간격 24). 종유석·수정·벽 횃불
  - 바다 위에서 보이던 문제로 `studio/MoveMineUnderground.luau`가 게임 시작 때 Floor1~ 층(모델·범위 안 부품·지형)을 지하(맨 위 y=-120)로 옮긴다. 이미 옮겼으면 Mine 속성 MovedUnderground로 건너뜀 (2026-10-09)
  - 층 이동: 갱도(태그 MinePortal, 속성 WalkIn·TargetFloor·Facing)로 걸어 들어가면 이동. 티어가 모자라거나 잠긴 층이면 알림 후 밀어냄
    - 지상 입구는 갱도 몇 걸음 안(EntranceTrigger)에서 이동, 바닥에 철로
    - 층 안: 지상 출구는 시작 방의 밝은 오르막 계단, 아래층 길은 미로 반대편 끝 구석(파란빛 내리막). 2층의 1층 길은 시작 방 북쪽 오르막, 3층 길은 반대편 구석(판자는 BuildMineFloor3가 치움). 3층의 4층 길은 판자로 막힘(공사 중)
  - 광석 스폰은 벽에 붙여 무작위, 35%는 두 개가 붙어 나옴. 통로 절반에 나무 지지대, 막다른 길에 버려진 광차, 층마다 거미줄 30개
  - 석탄 바위는 다른 광석의 1/2 크기
  - 광산 구역(태그 MineZone) 안에서는 클라이언트가 조명을 어둡게, 입장 음악·배경음·물방울 소리, 박쥐(무작위 비행)를 켠다
- [x] 귀환: 주문서는 2026-10-09 삭제(예전 저장의 주문서는 Unknown에 보관). 왼쪽 가운데 "🏠 마을로" 버튼(QuickButtonsHUD → 서버 ReturnHome) → Config.ReturnHome.CastTime초 뒤 마을(태그 TownArrival), 움직이거나 다시 누르면 취소, 쿨타임 Cooldown초
- [x] 음악 버튼 (2026-10-09): 왼쪽 위 가방 옆 🎵 = 배경음 끄기·켜기(🔇), −/+ = 크기 단계(Config.Music.VolumeLevels, MusicGroup SoundGroup 볼륨). 설정은 저장 안 됨
- [x] 미니맵(M 키): 밖은 마을·NPC·광산·바위, 동굴은 직접 가 본 칸만 표시 (층의 BatWaypoints 칸 정보 사용)
- [x] 지도: 손그림 지도·광산 미로 벽·출구 표시 (2026-10-09, MinimapController + MapData, 수치 Config.Minimap)
  - M 키·"지도" 버튼 = 화면 가운데 큰 지도 창(화면 높이의 72%, ✕ 닫기, "작게" = 오른쪽 위 작은 지도, 누르면 다시 크게). 그림은 열 때 한 번만 그리고 화살표·다른 플레이어 점만 매 프레임 옮긴다
  - 밖: 양피지 배경 + 가장자리 그늘 + 나침반. 처음 열 때 지형에 아래로 광선 격자(SampleStep)를 쏴서 물·풀·모래·바위·흙길·눈과 높이를 알고, 줄마다 같은 종류를 둥근 띠로 이어 그린다(손그림 덩어리). 높은 곳 ^ 언덕, 물결 ~, 나무 자리(OreSpawns 나무) 나무 그림, 마을 집 그림(이름에 House·집 등이 든 모델, 없으면 광장 둘레), 몹 사는 곳(MobSpawns를 Zone별로 묶어 생성 자리 가운데에 주인 몹 = Config.MobZones의 MobType, 없으면 가장 많은 MobType의 큰 손그림 얼굴 하나 + 양피지 이름표, 몹 하나하나는 안 그림. 프레임·UICorner·UIStroke 잉크로 그림, ±HabitatTilt° 기울임. 작은 지도에선 HabitatCornerScale로 줄이고 이름표 숨김. 수치 Config.Minimap.Habitat*), NPC 아이콘 + 직업 이름, 광산 입구 "광산"
  - 광산: BatWaypoints(칸 중심, Links)로 미로 격자를 만들고, 이웃 칸 사이를 바닥 + WallRayHeight 높이에서 옆으로 광선을 쏴 벽인지 확인(층마다 한 번, 기억). 지형을 못 찾으면 Links로 대신. 벽은 굵은 갈색 선, 안 가 본 칸은 어둡게. 갱도(MinePortal TargetFloor)로 "출구 ↑"(초록)·"N층 ↓"(파랑, 필요 곡괭이)·"🔒 공사 중" 표시
- [x] 곡괭이 Power: T1 1 / T2 1.5 / T3 2 / T4 3 (2026-10-09 결정). 가격은 임시값
  - T4 이름은 '다이아몬드 곡괭이'(2026-10-09 변경, Id는 SteelPickaxe 그대로). 티어마다 모양·크기가 다른 부품 모델, 휘두를 때 궤적(Trail)
  - 좋은 곡괭이로 칠수록 충격파 고리·튀는 광석 조각·카메라 흔들림이 커짐(Config.HitFeel.TierEffects), 다이아몬드는 반짝이
- [x] 벌목(2026-10-09 사용자 요청으로 MVP-2에서 앞당김): 나무 5종 + 도끼 4종. 바위와 같은 채집 시스템(OreNode·잔상·판정·피버)을 쓰고, 노드 Kind(Rock/Tree)와 도구 Kind(Pickaxe/Axe)가 맞아야 캔다
  - 나무: 소나무·참나무(돌 도끼), 자작나무(구리 도끼), 단풍나무(철 도끼), 흑단나무(다이아몬드 도끼). 베면 같은 Id 통나무가 가방에 들어온다. HP·리스폰·판매가(1/2/4/8/25G)는 Config
  - 배치(아래 "배치: 마을 거리별 난이도"로 바뀜): 마을 거리별로 소나무·참나무 → 자작나무 → 단풍나무, 흑단나무는 후보 자리(스폰 속성 RandomPool="Ebony") 중 Config.RandomPools.Ebony.Active그루만 서고 베면 다른 빈 자리에 다시 생긴다
  - 도끼: 돌 도끼는 시작 지급, 나머지는 대장장이 "도끼" 탭에서 구매(곡괭이와 따로 단계를 밟는다). 플레이어 속성 AxeTier
  - 곡괭이·도끼 가격에 손잡이용 통나무가 들어간다 (Config.Pickaxes)
  - 도끼 모양(2026-10-09 사용자 참고 이미지): 돌 = 한날 손도끼(빨간 끈 손잡이) / 구리 = 바이킹 수염 도끼(새김 무늬) / 철 = 계단식 날개 대형 양날 도끼(마름모 장식) / 다이아 = 양날 전투도끼(창끝·금 장식, 빛). 철·다이아 모양은 사용자 요청으로 서로 바꿈. 곡괭이 Tool의 쥐는 각도를 그대로 쓰고 곡괭이 모양은 숨긴 뒤 부품(쐐기 삼각형)으로 짓는다. 한날 방향이 뒤면 AXE_EDGE_SIGN = -1
  - 다이아몬드 도끼: 나무를 칠 때 Config.Pickaxes.DiamondAxe.LightningChance(20%)로 번개 → 남은 HP를 한 번에 (서버 MiningService, HitEffect 10번째 인자 "Lightning", 연출 Config.HitFeel.Lightning)
  - 크기: 철 도끼는 10% 줄임, 다이아 곡괭이는 제작 스크립트가 실행 때 1.1배로 키움(PICKAXE_SCALES, 속성 ScaledBy)
  - 도끼 타격 연출은 Config.HitFeel.AxeTierEffects (티어마다 충격파·나뭇조각·불꽃·베는 빛줄기·잎 배수)
  - 나무 모양은 맵에 원래 있던 나무(이름에 "Tree")를 본떠 종류별로 색만 바꾸고, 맵 나무 자리에 캘 수 있는 나무가 선다 (2026-10-09 사용자 결정: 직접 만든 나무보다 맵 나무가 그럴싸함)
  - 나무 모델 기준점(Pivot)은 줄기 밑동 가운데, PrimaryPart 없음(있으면 기준점이 부품 방향을 따라가 눕는다). 줄기 반지름 = 템플릿 속성 HitRadius(없으면 OreDefs.HitRadius), 타격 높이 = HitHeight
  - 연출: "퍽" 소리(Sounds.WoodChop), 나뭇조각·떨어지는 잎(OreDefs.LeafColor), 덜 흔들림. 잔상은 줄기 둘레 고리가 줄어든다. 다 베면 Sounds.TreeBreak와 함께 친 사람 반대쪽으로 쓰러진다(클라 복제본). 체력바·말풍선은 타격 높이 위 (Config.HitFeel.Tree)
  - Studio 제작: Rojo가 `studio/`를 ServerStorage/StudioTools로 넣는다. 템플릿이 없으면 게임 시작 때 서버가 자동 실행한다(저장 안 됨). 편집 상태 명령 모음에서 `require(game.ServerStorage.StudioTools.BuildTreesAndAxes:Clone())` 실행하면 도끼 Tool(같은 티어 곡괭이 손잡이 재사용)·나무 템플릿 5종x3모양·아이콘·스폰 자리를 만든다. 다시 실행하면 새로 만든다
- [x] 사냥과 전투 (2026-10-09 사용자 결정으로 7장 제외 항목에서 앞당김)
  - 몹 5종: 귀여운 슬라임·스켈레톤·좀비·케르베로스·사이클롭스 (MobDefs, 수치 Config.Mobs). 마을에서 멀수록 센 몹
    - 모델은 제작 스크립트 `studio/BuildWeaponsAndMobs.luau`가 부품으로 짓는다 (Templates/Mobs, 고정 Root + 용접, 앞 = -Z, 기준점 = 발밑). 생성 자리는 Workspace/MobSpawns (속성 MobType)
    - 서버 MobService가 TickRate번/초로 생각·이동(PivotTo): 어슬렁 → 가까운 플레이어 쫓기 → 공격(Humanoid:TakeDamage), 집에서 Leash 넘게 멀어지면 포기. 슬라임은 통통 튐. 피버 중 플레이어는 무적
    - 처치하면 처치한 사람에게 골드 + 전리품(슬라임 젤리·뼈다귀·낡은 천·케르베로스 송곳니·사이클롭스 눈알, 상인에게 판매). Respawn초 뒤 같은 자리에 다시
  - 무기 12종 = 칼(나무 검·구리 검·철 장검·다이아몬드 대검) / 활(나무·구리·철 장궁·다이아몬드) / 방망이(야구방망이·도깨비방망이·모닝스타·다이아몬드 철퇴) (2026-10-09 5·6단계 6종 더해 18종, 아래 "5·6단계")
    - PickaxeDefs에 Kind Sword/Bow/Club으로 넣어 곡괭이와 같은 Tool·가방·빠른 칸·단계 구매를 쓴다. 가방 분류는 "무기". 플레이어 속성 SwordTier·BowTier·ClubTier
    - 수치는 Config.Weapons (칼 빠름 / 방망이 느리지만 세고 밀쳐 냄 / 활 약하지만 멀리). 치명타·흔들림은 Config.Combat
    - 나무 검은 시작 지급, 나머지는 사냥꾼 카엘 상점 칼·활·방망이 탭에서 구매 (골드 + 괴·통나무·전리품)
    - 모양은 제작 스크립트가 돌 곡괭이 Tool의 쥐는 각도를 그대로 쓰고 부품으로 짓는다. 연출: 맞으면 하얗게 번쩍, 데미지 숫자(치명타 노랑), 티어별 불꽃·빛줄기(Config.Combat.TierEffects), 활은 화살이 날아간다
  - 활은 화살통에 화살이 있어야 쏜다 (아래 "활 화살·화살통"). 몹이 없으면 앞으로 쏜다. 화면 가운데 BowAimAngle 안의 몹을 먼저 노린다. 치명타면 몹이 짧게 불탄다(CritBurnTime)
  - 무기를 들고 있으면 바위·나무 체력바는 띄우지 않는다
- [x] 체력·마나 (2026-10-09): 오른쪽 위(리더보드 아래)에 체력바, 그 아래 마나바, 그 아래 골드 (항상 보임, Roblox 기본 체력바는 끔. StatusHUD)
  - 마나: 플레이어 속성 Mana·MaxMana, 서버 ManaService. 스킬·차징 스매시(예정)·달리기에 쓴다. 안 쓰면 RegenDelay 뒤 Regen/초로 참
  - 달리기 모드: 오른쪽 "달리기 ON/OFF" 버튼 (속성 Sprinting). 움직이는 동안 SprintManaPerSecond씩 줄고, 바닥나면 자동으로 꺼진다 (Config.Movement)
  - 음식(빵·마나 베리·모험가 도시락)으로 체력·마나 회복 (Config.Foods, ItemUseService). 지금은 상인 잡화에서 판다. 나중에 요리 기능으로 만든다
- [x] 차징 (2026-10-09): 모든 도구·무기는 누르고 있으면 모으고 놓을 때 휘두른다 (Config.Charge)
  - 서버 ChargeService가 ChargeStart ~ 휘두르기·공격 요청 사이 시간으로 모은 정도를 정한다. 요청을 안 보내게 되면 클라가 ChargeCancel
  - 모으는 동안 속성 Charging → 달리기 모드여도 Charge.WalkSpeed로 천천히 걷는다 (ManaService)
  - 활: 짧게 쏘면 사거리 BowTapRange·데미지 BowTapDamage배, 다 모으면 원래 값. 화면 아래 게이지 (ChargeController)
  - 나머지: 무기를 머리 위 뒤로 들어 올린 자세(PoseController.windUp, 어깨·허리 Motor6D C0를 돌림, 내 화면에만 보임)로 도구 빛이 깜빡이며 커지다가, 다 모이면 깜빡임이 멈추고 선명한 테두리. 다 모은 강타는 마나 ManaCost를 써서 Multiplier(2.5)배 (바위·나무도). HitEffect special "Charged" / CombatEffect charged
  - 공통: 기운이 차오르는 소리(Sounds.ChargeUp, 모일수록 음이 올라감), 주변에서 마나 입자가 도구로 빨려 들어옴(ParticleEmitter Sphere + Inward)
  - 활: 누르는 순간 시위가 뒤로 휘며 화살이 걸리고 왼손이 당기는 점을 따라간다(PoseController.bowDraw, R15는 IKControl, 내 화면에만). 놓으면 시위가 돌아온다
  - 활 2단 차징: 1단계(Time) 다 차면 금색, 계속 누르면 마나가 모이는 추가 차징(BowOverTime, 파란 게이지). 끝까지 모으면 마나를 써서 BowOverMultiplier(2.5)배
  - 다이아몬드 활은 20% 크게, 휘두르기 차징 자세는 어깨 165°·허리 -28°로 더 뒤로 (2026-10-09)
- [x] 음식 쿨타임 10초 (Config.FoodCooldown, 음식마다 따로). 서버가 ItemCooldown으로 알리면 가방 칸·빠른 칸 위 어두운 덮개가 12시부터 시계 방향으로 걷힌다 (CooldownController)
  - TODO: 칼·활·방망이 전용 소리 (지금은 있는 소리 음높이만 바꿈), 몹 애니메이션, 방어구
- [x] 장비와 전투력 (2026-10-09): 칸 7개 = 무기(손에 든 도구·무기) / 헬멧 / 갑옷 / 신발 / 장갑 / 목걸이 / 팔찌 (EquipmentDefs, 서버 EquipmentService)
  - 장비 24종(칸 6개 × 4단계: 가죽·뼈·나무 / 구리 / 철 / 다이아몬드, 2026-10-09 미스릴·오리하르콘 더해 36종), 사냥꾼 "방어구"·"장신구" 탭에서 구매. 능력치 = 칸 기본값 × 단계 배수 (Config.Equipment)
  - 능력치: 공격(무기 데미지에 더함)·방어(몹 피해 × 100/(100+방어))·체력(최대 체력에 더함)·치명타%(확률에 더함)
  - 전투력 = 공격×3 + 방어×4 + 체력×1 + 치명타×15, 착용 장비 합산(손에 든 무기 포함). 플레이어 속성 CombatPower → 모든 플레이어 머리 위 "⚔ 전투력" (CombatPowerHUD)
  - 가방에서 장착 아이템(도구·무기·장비)은 더블클릭해야 장착, 빠른 칸은 한 번 클릭. 가방 창 왼쪽에 장비 창(EquipmentPanel, 2026-10-09 새로 그림: 내 캐릭터를 입은 장비 모양 그대로 복제해 가운데 세우고 카메라가 천천히 둘레를 돈다(Config.EquipFigure.SpinSeconds, 안 되면 노란 머리·파란 몸·초록 다리 블록 사람), 양옆에 칸 네모(2026-10-09 이음선 삭제) — 헬멧=머리·목걸이=목·갑옷=가슴·방패(화살통)=등·장갑=왼손·팔찌=오른 손목·무기=오른손·신발=발. 칸 한 번 = 상세 창, 두 번 = 빼기. 아래 전투력·능력치. 가방+장비 창을 묶어 화면 가운데에, 수치 Config.EquipFigure). 끼운 아이템은 가방에서 금색 테두리 + E
  - 장비 모양은 서버 GearVisualService가 부품으로 지어 캐릭터에 용접한다 (폴더 GearVisuals, 모두에게 보임, 크기는 몸 부품 비율, 수치 Config.GearVisual). 단계가 높을수록 조각이 늘어남(투구 코·볼 가리개·볏, 갑옷 어깨 보호대·보석 등). 헬멧을 쓰면 머리카락·모자 숨김 (2026-10-09)
- [x] 자연 회복·장비 벽 (2026-10-09)
  - 바위·나무·몹은 Regen.Delay초 동안 안 맞으면 최대 체력의 일정 비율씩 천천히 찬다 (Config.Regen. 몹은 쫓는 중엔 안 참)
  - 장비 벽: 도구 단계 < 필요 단계면 때릴 수는 있지만 체력이 안 닳는다 (HitEffect special "Blocked": 둔한 소리·"단단해!"). 몹은 MobDefs.Tier보다 무기가 2단계 이상 낮으면 0, 1단계 낮으면 0.4배 (Config.TierWall, CombatEffect blocked)
  - 나무를 치면 돌가루 대신 잎 조각(부품)이 팔랑이며 흩날린다. 쓰러질 때·땅에 닿을 때도 잎. 획득 연출은 작은 통나무 모양
- [x] 보상 키우기·줍기 연출 (2026-10-09): 바위·나무 하나당 5~10개 (Config.Reward). 조각(광석=네모, 나무=통나무, 골드=동전)이 땅에 떨어졌다가 가까이 가면(PickupMagnetRange) 또는 PickupAutoTime 뒤 저절로 빨려 오고 "뽁" 소리, 다 들어오면 화면 왼쪽 획득 알림 "[그림] +7 구리 (가방 37개)" (PickupFeed, 같은 아이템은 숫자만 늘어남). 보상은 서버가 이미 가방에 넣으므로 잃어버리지 않는다
- [x] 주인 정하기·피버 배수·활 소리 (2026-10-09)
  - 바위·나무·몹에 먼저 데미지를 준 사람이 주인 (서버 OwnershipService, 상태 Owner·OwnerAt, 모델 속성 OwnerId). 주인이 아니면 못 치고("다른 사람이 ~중이에요"), 보상·떨어지는 조각도 주인 몫만. 주인이 Config.Ownership.HoldTime초 안 치거나 나가면 풀림. 흠집도 못 낸 타격(장비 벽)으로는 주인이 안 됨
  - 몹은 주인이 있으면 주인만 노린다. 클라는 남의 것을 조준에서 빼고 위에 "🔒 이름" (OwnerLockHUD)
  - 피버는 개수 보너스 대신 배수 (5장 표, Config.Fever.Tiers Multiplier). FeverResult·RockBroken은 배수를 보낸다. 화면 "x3배!", "FEVER x3"
  - 활: 푸드덕(Bird Flying) 대신 놓을 때 "휘익"(rbxasset://sounds/swordslash.wav), 맞아서 데미지가 뜰 때 "퍽!"(Wood Chop). 시위는 덜 당긴다(Config.Charge.BowPullStart·BowPullDistance) → 왼손이 활 근처에 머묾
- [x] 저장 (2026-10-09, DataService): 골드·가방(아이템·칸·가방 단계)·끼운 장비·빠른 칸 배치. 키 `Player_<UserId>`
  - 서비스가 DataService.register(칸 이름, 값 함수)로 저장할 칸을 등록 ("Inventory", "Equipped"). InventoryService가 들어올 때 DataService.load → 다른 서비스는 InventoryService.waitLoaded 후 도구 Tool 재생성·장비 복구
  - 세션 잠금(Lock JobId·Time, Config.Save.LockTimeout), 자동 저장 60초, 나갈 때·서버 종료(BindToClose) 저장. 불러오기 실패면 그 접속은 저장 안 함 + 알림
  - 정의가 없어진 아이템은 Unknown에 보관해 지우지 않는다
  - 빠른 칸: 클라가 SaveHotbar로 보냄 → 들어올 때 플레이어 속성 SavedHotbar(쉼표로 이은 Id)
  - Studio는 StudioStoreName 저장소를 쓰고, 테스트 지급(Config.Debug의 주문서·음식·장비)은 처음 들어올 때만. Studio 저장은 게임 게시 + Game Settings → Security → Enable Studio Access to API Services 필요
- [x] 줍는 조각 크기 키움 (Config.HitFeel.PickupSizeMin·Max, 2026-10-09)
- [x] 몹 구역·안전지대·사이클롭스·보스 몹 (2026-10-09)
  - 몹 구역(Config.MobZones): 구역마다 주인 몹이 모여 산다 (슬라임 들판·언덕·연못·스켈레톤 무덤·좀비 숲·케르베로스 굴·사이클롭스 골짜기). 마을에서 멀수록 센 몹. 제작 스크립트가 시작 때 구역 방향과 생성 자리(속성 MobType·Zone·BossSpot)를 고른다 (아래 "배치: 마을 거리별 난이도")
  - 마을 안전지대: TownArrival·ShopNPC 둘레 Config.MobAI.SafeZoneRadius 안에는 몹이 안 생기고(생성 자리는 SafeZoneSpawnMargin 더 바깥), 몹이 들어가려 하면 쫓기를 포기하고 집으로 돌아간다. 안전지대 안 플레이어는 노리지 않는다
  - 슬라임(Config.Mobs.Slime.Passive): 먼저 공격 안 함, 피해 0. 맞으면 FleeTime초 동안 때린 사람 반대쪽으로 FleeSpeed배 빠르게 도망친 뒤 진정. 구역 두 곳에 30마리
  - 버그베어 → 사이클롭스(큰 눈 하나·짧은 뿔·나무 몽둥이, 플레이어 키의 약 1.9배). 전리품 "사이클롭스 눈알"(CyclopsEye)로 바뀌어 다이아몬드 장비·철퇴 재료도 이것. 예전 저장의 버그베어 털은 Unknown에 보관됨
  - 보스 몹(Config.MobBoss): 생길 때 Chance(보스 자리는 SpotChance)로 1.5~3배 크기(Model:ScaleTo). 체력·공격·골드·전리품이 크기에 비례, 공격 거리도 몸만큼 늘어남, 다시 나오기는 RespawnMultiplier배 늦게. 모델 속성 Boss·BossScale → 체력바 "👑 보스 ~" 금색 이름 + 큰 체력바. 슬라임 보스도 도망만 친다
- [x] 보스 바위·나무 (2026-10-09): 생길 때 Config.BossNodes.Chance로 1.5~3배 크기(Model:ScaleTo), 체력 크기^2배, 산출량 크기^1.5배. 속성 Boss·ExtraReach(커진 만큼 더 멀리서 침, 서버 AntiCheat 거리에도 더함). 체력바 이름 "👑 보스 ~" 금색. 나무는 HitRadius도 같이 커짐
- [x] 광산 광석: MineScale(1.4)배로 키우고, 옆으로 광선을 쏴 벽 속에 묻힌 만큼 밀어낸 뒤 다시 땅에 맞춘다 (OreService.pushOutOfWalls)
- [x] 배경음악 (MusicController, Config.Music): 평소 느릿한 곡(Calm, APM)을 차례로, 몹을 때리거나 맞으면 전투곡(Battle)으로 크로스페이드하고 마지막 전투 뒤 BattleHoldTime(10초) 유지, 광산에선 줄임. 새소리(Ambience)는 Id를 아직 못 찾아 빈 값. 곡 Id는 웹 목록에서 찾은 값이라 안 나오면 Creator Store 곡으로 교체
- [x] 활 화살·화살통 (2026-10-09)
  - 장비 칸 8개: 무기 다음에 "방패" 칸(Slot Shield). 지금은 화살통만 들어간다 (EquipmentDefs.QuiverOrder, Order와 따로 둬서 장비 아이콘 제작 스크립트에 안 섞임). 가방 분류 "무기"
  - 나무 화살통(화살 30) / 철 화살통(화살 60). 사냥꾼 "활" 탭 아래에서 통나무 잔뜩 + 골드 조금 (Config.Quiver.Items, ShopAction "BuyQuiver"). 여러 개 살 수 있고, 안 끼고 있으면 사자마자 낀다
  - 서버 EquipmentService가 끼운 화살통의 남은 화살을 센다 (속성 Arrows). 활 한 발에 1개 (CombatService → useArrow). 몹 없이 쏜 화살도 AttackRequest(nil)로 1개. 화살이 없으면 클라가 쏘지 않고 "화살통이 필요해요"/"화살이 없어요"
  - 0개가 되면 화살통이 가방에서 사라지고 "화살을 다 썼어요", 가방에 다른 화살통이 있으면 저절로 바꿔 낀다. 덜 쓴 화살통을 빼면 종류마다 남은 수를 기억(stash)해서 다시 끼우면 그 수로
  - 저장: DataService 칸 "Quivers" = { Arrows(끼운 것), Stash }
  - 모양: GearVisualService가 등에 비스듬히(Config.Quiver.Tilt) 가죽 화살통 + 금속 입구 테·띠·바느질 + 가슴을 가로지르는 어깨끈·버클. 화살(나무대 + 빨강/파랑·흰 깃)이 min(남은 수, 7)개 꽂혀 보이고 줄면 같이 줄어든다
  - 아이콘: Studio 아이콘 모델이 없으면 ItemIcon이 부품으로 화살통 아이콘을 짓는다. 장비 창 방패 칸에 "🏹남은 수"
  - Studio 테스트: Config.Debug.GiveQuivers(처음 들어올 때 종류마다 지급)
- [x] 소리·화면 정리 (2026-10-09)
  - 나무가 다 베이면 "뻐지지직"(나무 찍는 소리를 빠르게 겹침, Config.HitFeel.TreeCrack) + 쓰러지는 소리는 작게
  - 몹 비명 Config.MobDeathSounds (슬라임 뀍 = splat 높게, 스켈레톤·좀비·사이클롭스 = uuhhh 낮게, 케르베로스 깨갱 = uuhhh 높게 두 번). TODO: 전용 소리
  - 장비 벽 알림 창 삭제 (바위 "단단해!"·몹 "흠집도 안 나!" 문구만)
  - 체력·마나 바는 오른쪽 맨 위(TOP 8), 그 아래 골드(y 60), 미니맵(y 110). Roblox 리더보드는 끔
  - 모바일: 왼쪽 아래 고정 조이스틱(서버가 DevTouchMovementMode = Thumbstick), 오른쪽 아래 큰 공격 버튼(MobileControls, 누르고 있으면 모으기), 점프 버튼은 그 왼쪽 위로. 기본 ContextAction 공격 버튼은 안 만든다
- [x] 배치: 마을 거리별 난이도·나무 늘리기 (2026-10-09 사용자 요청)
  - 마을(TownArrival)에서 가까우면 쉬운 것(아주 가끔 중간), 조금 멀면 중간, 꽤 멀면 센 것. 띠끼리 거리가 조금 겹쳐 경계가 서서히 바뀐다 (Config.WorldTiers)
  - 제작 스크립트가 맵의 땅 반경을 재서 Config.WorldTiers.MapRadius보다 좁으면 모든 거리(나무·몹)를 그 비율로 줄인다
  - 나무: 맵 나무 자리(속성 MapTreeSpot) + 빈 풀밭(길·건물·물·마을 안전지대·NPC·광산 입구 피함)에 더 심어 맵 나무 수의 약 2.5배(TreeDensity, 90~200그루). 종류는 거리 띠 가중치(Trees): 근처 소나무·참나무(자작 5%) / 중간 자작나무 위주(참나무·단풍 조금) / 멀리 단풍나무 위주(자작 조금). 흑단나무는 먼 곳의 가장 먼 후보 6곳 중 2그루
  - 편집 상태에서 다시 실행해도 전에 만든 맵 나무 자리·맵 나무 모양 템플릿(속성 FromMapTree)을 그대로 쓴다
  - 지상 돌: 마을 근처(Stone.Distance)에 MinCount개가 안 되면 제작 스크립트가 채운다. 광산 층 광석은 층별 그대로
  - 몹: 구역 = 마을 둘레 부채꼴(Distance·Arc). 슬라임 3구역(80~155) / 스켈레톤·좀비(135~210) / 케르베로스·사이클롭스(195~300). 자리마다 Mix 확률로 이웃 단계 몹. 생성 자리 간격 SpawnGap 14 (예전 7), 같은 띠 구역은 방향이 안 겹치게(ArcGap), 나무 자리와 NodeGap
  - Output에 띠마다 나무 종류·몹 수 요약
- [x] 밤낮·먼 곳 안개 (2026-10-09): 서버 DayNightService가 Lighting.ClockTime을 돌림(낮 12분·밤 6분, Config.DayNight). 클라 DayNightController가 시각을 보고 밝기·주변광·Atmosphere를 낮↔밤 사이로(밤은 더 깜깜), 마을에서 멀수록 안개 짙게(Fog.ClearRadius~FullRadius). 광산 안은 MineAtmosphere가 맡고, 나올 때 MineAtmosphereController.outdoorTargets(밤낮 값)로 돌아감. 부엉이(OwlSound)는 Id를 못 찾아 빈 값
- [x] 조합식·상점 아이콘 탭·아이템 상세창 (2026-10-09)
  - 조합식(Config.Recipes, 키 = 결과 아이템): 1단계 도구·무기·장비는 골드 + 재료 조금으로 산다(여러 개 가능, "3개 사기" 버튼). 2~4단계 = 같은 종류(칸) 바로 아래 단계 3개 + 재료 + 골드 (2단계 1~2종, 3단계 3종, 4단계 4종). 실패 확률 없음. 화살통·가방·잡화는 그대로
  - 재료는 직전 단계로 구할 수 있는 것만 (구리 곡괭이에는 구리괴 대신 돌·참나무: 구리는 구리 곡괭이로 캔다)
  - 서버 CraftingService.craft(ShopAction "Craft", 대장장이 = 곡괭이·도끼, 사냥꾼 = 칼·활·방망이·장비): NPC 거리·재료·골드·가방 칸 확인 → 아래 단계 3개를 빼고 1개 넣는다. 끼우던 장비·들던 도구를 다 쓰면 새것을 바로 끼운다(든다)
  - 같은 도구를 여러 개 가질 수 있다: 개수는 가방 아이템, 실제 Tool은 종류마다 하나 (PickaxeService.give·giveIfMissing·removeCount·hold). 시작 도구는 그 종류 도구가 하나도 없을 때만 준다. 장비 "이미 가지고 있어요" 제한 없앰
  - 상점 위쪽 탭은 큰 그림 버튼(대표 아이템 3D 아이콘 + 짧은 이름, ShopDefs Icon, "@Bag"/"@Coin"은 그린 그림). 고른 탭은 금색 테두리. 사냥꾼 탭: 칼·활·방망이·투구·갑옷·신발·장갑·장신구 (넘치면 옆으로 밀기). 창이 낮으면 인사말을 숨기고 탭을 줄인다
  - 목록 줄: 결과 아이콘(가진 개수 x2) · 이름 ★ · 조합식 그림(RecipeView: 재료 아이콘 + 가진/필요 초록·빨강, 아래 단계는 금색 테두리, 골드 동전) · 만들기/사기 버튼. 좁은 화면이면 그림이 줄 전체로 내려간다
  - 아이템 상세 창(ItemDetailUI): 상점 아이콘·재료 그림·가방 칸을 한 번 누르면 뜬다 (가방의 장착 아이템은 더블클릭인지 0.4초 기다렸다 연다. 더블클릭은 장착 그대로). 아이콘 모델이 Config.ItemDetail.SpinSeconds초에 한 바퀴 돈다(카메라는 모델 크기·창 비율에 맞춤). 이름·별·분류, 능력치(도구 힘·캘 수 있는 것·번개 / 무기 공격·간격·사거리·밀쳐 내기·치명타·잘 싸우는 몹 / 장비 공격·방어·체력·치명타·전투력 / 화살 수 / 음식 회복), 판매가, 만드는 법, 이걸로 만들 수 있는 것(누르면 그 아이템으로)
    - 2026-10-09 고침: 창이 빈 상자만 보이던 버그 = Instance.new ScreenGui의 ZIndexBehavior 기본값(Global) + panel.ZIndex 2라 안쪽(ZIndex 1)이 패널 뒤에 그려짐 → ItemDetailGui·InventoryGui는 ZIndexBehavior = Sibling
    - 모양: 어두운 전체 화면 배경 없이, 연 창(가방 창·상점 창) 오른쪽에 붙는 세로 창(Config.ItemDetail.PanelWidth·MinHeight·Gap). 위→아래 돌아가는 모델·이름·별·분류·능력치·가진 개수·판매가·만드는 법·쓰이는 곳, 길면 스크롤. 오른쪽 자리가 모자라면 가방+장비 창(또는 상점 창)을 왼쪽으로 밀고, 그래도 안 되면(휴대폰) 연 창 오른쪽 안에 겹친다(OverlayRatio). 연 창이 움직이거나 화면 크기가 바뀌면 다시 맞추고, 연 창이 닫히면 같이 닫힘. X로 닫기. ItemDetailUI.open(itemId, host, group)
- [x] 항상 달리기·마을 회복·해시계·밤 (2026-10-09)
  - 달리기 버튼 삭제: 항상 Config.Movement.RunSpeed (모으는 중엔 Charge.WalkSpeed). SetSprint 리모트는 안 씀
  - 체력·마나는 마을(TownArrival·ShopNPC 둘레 SafeZoneRadius) 안에서만 Config.TownRegen만큼 찬다. Roblox 기본 Health 스크립트는 캐릭터에서 지움. 속성 InTown
  - 해시계: 체력바 왼쪽 둥근 판(낮 노랑·밤 남색 점), 바늘 = Lighting.ClockTime, 아래 "밤까지 m:ss"/"아침까지 m:ss" (StatusHUD)
  - 밤을 덜 깜깜하게(달빛 푸르스름, Config.DayNight.Night). 밤 음악(Config.Music.Night: 잔잔한 곡을 PlaybackSpeed 0.85·작게), 밤에 마을 밖이면 풀벌레(NightAmbience)·부엉이(OwlSound) — 둘 다 Id를 못 찾아 빈 값
- [x] 횃불: 마을·길 (2026-10-09 사용자 요청: 밤에 너무 깜깜함). 제작 스크립트 `studio/BuildTorches.luau`(게임 시작 때 실행, 다시 실행하면 지우고 새로) → Workspace/Torches (속성 GeneratedBy), 수치 Config.Torches
  - 마을 가로등(따뜻한 주황 등불, 팔에 매단 등): 광장 둘레 + NPC 가판대 옆 + 마을 둘레 고리 3겹(마을 반경 = 가장 먼 NPC + TownMargin). 그림자는 ShadowEvery개마다 하나
  - 길 횃불(나무 기둥 + 쇠 그릇 + 불꽃·Fire): 마을 둘레 RoadScanRadius를 RoadScanStep 격자로 아래로 쏴서 길 칸 = 지형 돌길(Cobblestone·Pavement·Brick·Asphalt·Concrete·WoodPlanks) / 이름에 Road·Path·Street·길·도로가 든 납작한 부품 / 좁은 흙(Ground·Mud) 띠(DirtRoadMaxWidth). 마을에서 가까운 길부터 RoadSpacing 간격, 길 가장자리 바깥에. 물·지붕·건물·광산 구역·도착점·생성 자리·원래 있던 불빛 근처는 피함
  - 길을 거의 못 찾으면(RouteFallbackMin) 마을 → 광산 입구 직선을 따라 지그재그. Output에 개수·못 세운 이유 요약
  - 서버 TorchService가 Lighting.ClockTime을 보고 해 지기 LightBefore시간 전 ~ 해 뜨고 LightAfter시간 뒤에만 불을 켠다 (편집 상태에선 켜진 채)
- [x] 구르기·무기별 스킬 (2026-10-09 사용자 요청)
  - 버튼: 모바일은 공격 버튼 둘레(MobileControls.ringPosition, 각도 Config.MobileControls.JumpAngle·RollAngle·SkillAngle, 지름 SmallSize) = 왼쪽 점프 / 왼쪽 위 🌀 구르기 / 위 스킬 칸(위에 스킬 이름). PC는 오른쪽 아래에 작게(PcSize) [Q] 구르기·[F] 스킬. 패드 X·Y. E키는 ProximityPrompt가 써서 F
  - 쿨다운은 버튼 위 어두운 덮개가 아래로 줄고 남은 초 숫자. 마나가 모자라면 흐리게 (클라 SkillController)
  - 구르기(Config.Roll): 움직이는 쪽(가만히면 바라보는 쪽)으로 Distance 12스터드를 Duration 0.3초에 (클라가 LinearVelocity로 수평 속도만, 벽은 레이로 보고 그 앞까지). 몸통 뿌리 관절(R15 Root·R6 RootJoint) C0를 앞으로 한 바퀴 + 흙먼지 + "휙". 서버 SkillService가 RollRequest(방향)를 받아 쿨다운 1.2초·마나 4를 확인하고 IFrame 0.4초 무적, 다른 사람에게 SkillEffect "Roll"로 구르는 모습
  - 스킬 칸(Config.Skills, Kind로 들고 있는 도구 종류에 맞춤, 아무것도 안 들면 빈 칸). 클라는 SkillRequest(대상)만, 서버 SkillService가 종류·마나·쿨다운·거리·주인·장비 벽·피버를 확인하고 SkillEffect(kind, userId, position, data)를 보내면 연출·쿨다운 시작
    - 칼 🛡 방패 막기(Block): 마나 12·쿨 6초, 1.5초 동안 몹 피해 80% 줄임. 캐릭터 둘레 파란 ForceField 공
    - 방망이 💥 내려찍기(Slam): 마나 15·쿨 7초, 둘레 8스터드 몹에게 무기 데미지 ×1.8 + 밀쳐 내기 6 + 기절 1.5초(MobService.stun: 안 움직이고 공격 안 함). 충격파 고리·흙먼지·쿵 소리·카메라 흔들림, 몹 머리 위 💫. 남의 몹·흠집 못 내는 몹(장비 벽)은 기절 안 함
    - 활 🏹 연사(RapidFire): 마나 12·쿨 6초, 노리는 몹에게 화살 3발을 0.15초 간격(화살 3개 씀, 한 발 ×0.8). 화살은 CombatEffect 11번째 인자 fromSkill로 내 화면에서도 날아감
    - 곡괭이·도끼 ⚒ 강하게 찍기(PowerStrike): 마나 10·쿨 6초, 가까운 바위·나무를 확인하고(맞는 도구·거리·주인·단계) 5초 안의 다음 한 번이 ×3 (MiningService.armPowerStrike, HitEffect "Charged" 연출). 걸리자마자 클라가 한 번 휘두른다
  - 몹 공격 막기: MobService.protect(player, 출처, 줄이는 비율, 초)를 공격 때 확인. MobAttack 4번째 인자 guarded → 클라 "피함!"(0)·"막음! -X"
  - 데미지 계산은 CombatService applyHit 하나로 (보통 공격·CombatService.skillHit 공통: 장비 공격·치명타·장비 벽·연출)
- [x] 광산 3층·미스릴·오리하르콘 (2026-10-09 사용자 요청 "오리하르콘까지, 3층에서 아주 가끔". 7장 판타지 광석 제외 항목을 사용자 요청으로 앞당김)
  - 광석: 미스릴(Mithril, 은빛 파랑, 다이아몬드 곡괭이 T4로 캠, 15G) / 오리하르콘(Orichalcum, 금빛·빛·반짝이, 미스릴 곡괭이 T5로 캠, 60G). HP·리스폰은 Config.Ores
  - 오리하르콘은 흑단나무처럼 희귀 무리: 후보 자리(RandomPool="Orichalcum") 중 Config.RandomPools.Orichalcum.Active(1)개만 서 있고, 캐면 RespawnTime(300초) 뒤 다른 빈 자리에
  - 제작 스크립트 `studio/BuildMineFloor3.luau` (게임 시작 때 MoveMineUnderground 바로 다음): 옮긴 2층보다 Config.MineFloor3.Depth 아래(바닥 최대 y=-160), 다른 층·광산 구역과 안 겹치게 2층 동쪽 옆에 6x6 미로(고정 씨앗 Config.MineFloor3.Seed, 1·2층과 같은 규격)를 지형으로 판다. 시작 방(0,0) 북쪽 오르막 = 2층 길, 2층에 지상 출구가 있으면 서쪽에도. 반대편 구석(5,5) 남쪽 파란빛 내리막 = 4층 길(판자 + "🔒 공사 중" 표지판, Config.Mine.Floors[4] 잠김). 파란 불꽃 벽 횃불·파랑/금색 수정·얼음빛 벽 무늬
  - 같은 스크립트가 철 바위 템플릿·아이콘을 복제해 색을 바꿔 Templates/Ores/{Mithril, Orichalcum}·ItemIcons를 만들고, 2층의 3층 길(TargetFloor=3) 앞 판자를 치운다(없으면 2층 도착점에서 가장 먼 칸 바깥 벽에 새 갱도). Floor3 속성 GeneratedBy·Version이 같으면 다시 안 짓고, 버전이 다르면 지우고 새로
- [x] 5·6단계 미스릴·오리하르콘 장비, 방어구는 몹 재료 (2026-10-09)
  - 단계 공통 정보는 `src/shared/TierDefs.luau` (이름·색·별, Max = 단계 수). 1 가죽·나무 / 2 구리 / 3 철 / 4 다이아몬드 / 5 미스릴(은빛 파랑, 가볍고 빠름) / 6 오리하르콘(금빛, 묵직하고 화려). 단계 수를 가정하던 곳(별 ★☆, 이름 색, TierMultiplier, 타격 효과 표, 어깨 보호대 크기)은 TierDefs.pick으로 "표에 없으면 가장 높은 아래 단계 값"을 쓴다 → 7~9단계(아다만티움·운석철·용뼈)는 TierDefs 한 줄 + 각 표에 데이터만 더하면 됨
  - 도구·무기 10종 추가: 미스릴/오리하르콘 곡괭이·도끼·검(성검)·활(태양궁)·전투망치(거인망치). 장비 12종 추가(칸 6개 × 2단계, 모두 36종) + 미스릴 화살통(화살 100). 수치 Config.Pickaxes(Power 4 / 5.5, 도끼 번개 25% / 30%)·Config.Weapons·Config.Equipment.TierMultiplier(… 7, 11, 16)
  - 제련: 미스릴 2 + 석탄 2 → 미스릴괴 / 오리하르콘 2 + 석탄 3 + 미스릴괴 1 → 오리하르콘괴 (Config.Smelting)
  - 조합식 재료 원칙(사용자 결정, Config.Recipes 1~6단계 전부 고침): 도구·무기·장신구 = 광물(괴)·통나무 (+ 무기는 가끔 송곳니·눈알·보스의 증표) / 방어구(헬멧·갑옷·신발·장갑) = 몹 전리품 주재료(젤리 → 뼈·낡은 천 → 케르베로스 털가죽·사이클롭스 가죽 → 보스의 증표) + 묶는 괴 1~2개
  - 몹 두 번째 전리품: Config.Mobs[몹].ExtraLoot { Id, Chance, Count } (케르베로스 털가죽 85%, 사이클롭스 가죽 85%, 보스는 크기만큼 더). 보스는 Config.MobBoss.ExtraLoot로 보스의 증표 1~2개. MobDied 7번째 인자 extras로 클라가 줍기 연출·획득 알림. 상세 창 "얻는 법"도 ExtraLoot·보스 전리품을 본다
  - 모양: 도끼(BuildTreesAndAxes: 미스릴 초승달 도끼 / 오리하르콘 태양 도끼), 곡괭이 5·6단계는 같은 스크립트가 Studio 다이아몬드 곡괭이 Tool을 복제해 머리·자루 색·재질을 바꾸고 빛·반짝이(오리하르콘은 불티)를 붙여 1.06 / 1.15배로. 무기 6종·괴·털가죽·가죽·보스의 증표 아이콘은 BuildWeaponsAndMobs
  - 장비 겉모습(GearVisualService, Config.GearVisual.HighTiers): 미스릴 = 은빛 파란 금속 + 파랗게 빛나는 테두리·가슴 V자 빛줄·이마 빛줄, 오리하르콘 = 금빛 + 주황 보석·큰 볏·투구 큰 날개 두 겹·어깨 뿔·발목 날개·반짝이
  - 타격 연출: Config.HitFeel.TierEffects·AxeTierEffects·Combat.TierEffects [5]·[6]. 오리하르콘은 두 번째 금빛 고리(DoubleRing) + 번쩍임(Flash)
- [x] 조합 개수 줄이기 (2026-10-09): 4단계(다이아)부터는 아래 단계 2개 (2·3단계는 3개). 6단계 하나에 1단계 108개
- [x] 시작 지급 (2026-10-09): 처음엔 돌 곡괭이 하나만(Config.StarterTools). 돌을 캐서 상인에게 팔고 → 돌 도끼(5G + 돌 5) → 통나무로 나머지. Studio 테스트 지급(Config.Debug)도 전부 끔, Studio 저장소는 PlayerData_Studio_v2로 새로 시작
- [x] 바다 생물: 물고기·복어·황금 물고기·낙지·상어 (2026-10-09 사용자 요청 "헤엄칠 수 있는 물에서 낙지·물고기 잡기")
  - 몹 6종 더함 (MobDefs Habitat = "Water", SwimStyle Fish/Pulse, 수치 Config.Mobs Swim = true): 물고기(T1, 떼 3~5마리, 얌전·도망) / 복어(T2, 얌전, 맞으면 PuffTime초 동안 PuffScale배로 부풀고 Range 안에서 때린 사람을 찌름 = Config.Mobs.Pufferfish.Prick) / 황금 물고기(T2, 드묾·빠름·도망, 골드 40~70) / 낙지(T2, 먼저 안 덤비고 맞으면 쫓아와 때림 = Retaliate, 맞으면 가끔 먹물 = Ink) / 해파리(T2, 둥둥 떠다니다 닿으면 쏨 = Drift) / 상어(T3, 물에 들어온 사람에게 돌진해 묾 = ChargeSpeed·ChargeRange, 크기 1.3)
  - 헤엄(서버 MobService.stepSwimmer, 수치 Config.SeaAI): 지형만 보는 광선으로 물 기둥(수면 = 물 안 무시한 광선이 Water에 맞은 높이, 바닥 = 물 무시한 광선)을 ColumnCell 칸마다 한 번 재서 기억. 몸이 수면 아래·바닥 위에 있게 3D로 움직이고 물 밖·얕은 물·안전지대로는 안 간다. 물에 들어온(수면 위 PlayerWaterAbove까지) 플레이어만 노리고, 물 밖으로 나가면 포기. 물고기 떼(생성 자리 속성 School)는 떼 목적지를 같이 쓰고 자기 자리만큼 비켜 헤엄. 물고기는 몸을 좌우로 살랑(WiggleAngle), 낙지·해파리는 위아래로 둥실(PulseBob), 오르내릴 땐 머리를 기울임(MaxPitch)
  - 전투: 기존 흐름 그대로 (CombatService onAttack → MobService.damage, 주인·장비 벽·보스·전리품·줍기 연출). 물 속 몹은 위아래 거리도 본다(물가에서 깊은 바닥 물고기는 칼로 못 침, 클라 조준도 같은 기준). 몹 공격은 hurtPlayer 하나로 (피버 무적·방어구·구르기/방패)
  - 연출: 리모트 MobSpecial(mob, "Ink"|"Puff", userId, position, data) → 클라 CombatController가 먹물 구름(검은 입자) + 맞은 사람 화면이 Blind초 어두워짐 "앗, 먹물!" / 복어 "뿅" + 조각. 비명 Config.MobDeathSounds, 수치 Config.SeaEffects
  - 생성 자리(제작 스크립트 BuildWeaponsAndMobs 5번): 마을 둘레 Config.SeaSpawn.ScanRadius를 ScanStep 격자로 아래로 광선 → 지형 물 칸(깊이 MinDepth 이상, 안전지대·광산 밖)을 모으고, Config.SeaZones 구역(얕은 바다 = 물고기 떼 4 + 복어 3 + 황금 물고기 1 / 낙지 바위 = 낙지 4 + 해파리 3 / 깊은 바다 = 상어 3 + 낙지 1, 모두 약 31마리)마다 깊이가 맞고 물 칸이 많고 마을 거리 범위에 가까운 가운데를 고른다. 속성 MobType·Zone·Habitat·SwimDepth(그 자리 물 깊이)·School·BossSpot. 물을 못 찾으면 Output 경고
  - 전리품·음식: 생선(먹으면 체력 20)·복어 가시·황금 비늘(60G)·낙지 다리(먹으면 체력 35·마나 10, 재료)·먹물 주머니·해파리 젤리·상어 이빨·상어 가죽 (ItemDefs, Config.Foods·SellPrices, 아이콘은 BuildWeaponsAndMobs). 조합식: 다이아몬드 갑옷에 상어 가죽 3(케르베로스 털가죽 10 → 8), 미스릴 검에 상어 이빨 4(케르베로스 송곳니 4 → 2)
  - 지도: 바다 구역도 손그림 얼굴 (MinimapController FACES Fish·GoldenFish·Pufferfish·Octopus·Jellyfish·Shark, 주인 몹은 Config.SeaZones MobType)
  - TODO: 물 속 활 화살 느리게, 낙지 다리 꿈틀(클라 애니메이션), 전용 소리
- [ ] 트로피, 모루 미니게임, 매크로 방어

## 7. MVP에서 제외하는 것 (먼저 확인받기 전에는 구현 금지)

- ~~사냥과 전투~~ (2026-10-09 사용자 결정으로 구현) / 판타지 광석(미스릴, 마나석 등) / 마나 산업화와 문명 단계
- 거래소, 경매, 지역 경제 / 내구도와 수리 / 자유 배치와 꾸미기
- 마을 영지 / 배고픔 외 욕구 / 직업 슬롯과 조합 칭호 / 연금·물약 / 운송과 지역 서버

---

## 8. 미정 사항 (구현 중 마주치면 사람에게 물어볼 것)
- 방치 플레이(AFK) 허용 수준
- 게임 이름
- 개인 부지 방식 최종안 (MVP-2)
