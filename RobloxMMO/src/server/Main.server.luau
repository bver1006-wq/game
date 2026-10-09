--!strict
-- 서버 진입점. RemoteEvent를 만들고 서비스를 순서대로 초기화한다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Services = script.Parent.Services
local AntiCheatService = require(Services.AntiCheatService)
local ChargeService = require(Services.ChargeService)
local CombatService = require(Services.CombatService)
local CraftingService = require(Services.CraftingService)
local DataService = require(Services.DataService)
local DayNightService = require(Services.DayNightService)
local EconomyService = require(Services.EconomyService)
local EquipmentService = require(Services.EquipmentService)
local FeverService = require(Services.FeverService)
local InventoryService = require(Services.InventoryService)
local ItemUseService = require(Services.ItemUseService)
local ManaService = require(Services.ManaService)
local MineService = require(Services.MineService)
local MiningService = require(Services.MiningService)
local MobService = require(Services.MobService)
local NpcService = require(Services.NpcService)
local OreService = require(Services.OreService)
local PickaxeService = require(Services.PickaxeService)
local SkillService = require(Services.SkillService)
local TimingService = require(Services.TimingService)
local TorchService = require(Services.TorchService)

Remotes.setup()

-- 도끼·나무 템플릿·스폰 자리를 제작 스크립트(ServerStorage/StudioTools)로 매번 새로 만든다
-- (예전에 저장된 템플릿이 남아 있어도 지금 코드 기준으로 덮어쓴다. 실행 중에 만든 것은 저장되지 않는다)
local studioTools = ServerStorage:FindFirstChild("StudioTools")
-- 광산을 지하로 옮기고(MoveMineUnderground, 광석 자리도 같이 옮기므로 맨 먼저), 무기·몹 템플릿과 몹 생성 자리도 만든다
-- (BuildWeaponsAndMobs는 곡괭이 Tool이 있어야 해서 뒤에 돈다)
for _, name in { "MoveMineUnderground", "BuildTreesAndAxes", "BuildWeaponsAndMobs", "BuildTorches" } do
	local builder = studioTools and studioTools:FindFirstChild(name)
	if builder and builder:IsA("ModuleScript") then
		local ok, err = pcall(require, builder)
		if not ok then
			warn(`[Server] {name} 자동 제작 실패: {err}`)
		end
	end
end

OreService.init()
AntiCheatService.init()
TimingService.init()
FeverService.init()
DataService.init()
DayNightService.init()
TorchService.init()
InventoryService.init()
ManaService.init()
ChargeService.init()
EquipmentService.init()
PickaxeService.init()
MiningService.init()
NpcService.init()
EconomyService.init()
CraftingService.init()
MobService.init()
CombatService.init()
SkillService.init() -- 구르기·무기별 스킬 (MobService·CombatService·MiningService 다음)
MineService.init()
ItemUseService.init()

-- 모바일 이동: 왼쪽 아래 고정 조이스틱(방향 패드)으로 (2026-10-09)
local function setTouchMovement(player: Player)
	player.DevTouchMovementMode = Enum.DevTouchMovementMode.Thumbstick
end
Players.PlayerAdded:Connect(setTouchMovement)
for _, player in Players:GetPlayers() do
	setTouchMovement(player)
end

print("[Server] 초기화 완료")
