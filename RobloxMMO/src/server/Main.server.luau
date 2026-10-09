--!strict
-- 서버 진입점. RemoteEvent를 만들고 서비스를 순서대로 초기화한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Services = script.Parent.Services
local AntiCheatService = require(Services.AntiCheatService)
local CraftingService = require(Services.CraftingService)
local EconomyService = require(Services.EconomyService)
local FeverService = require(Services.FeverService)
local InventoryService = require(Services.InventoryService)
local ItemUseService = require(Services.ItemUseService)
local MineService = require(Services.MineService)
local MiningService = require(Services.MiningService)
local NpcService = require(Services.NpcService)
local OreService = require(Services.OreService)
local PickaxeService = require(Services.PickaxeService)
local TimingService = require(Services.TimingService)

Remotes.setup()

-- 도끼·나무 템플릿이 아직 없으면 제작 스크립트(ServerStorage/StudioTools)로 이번 실행 동안만 만든다
-- Studio 편집 상태에서 직접 실행해 저장해 두면 이 단계는 건너뛴다
local templates = ServerStorage:FindFirstChild("Templates")
local hasAxe = templates ~= nil and templates:FindFirstChild("Pickaxes") ~= nil and (templates :: any).Pickaxes:FindFirstChild("StoneAxe") ~= nil
local hasTree = templates ~= nil and templates:FindFirstChild("Ores") ~= nil and (templates :: any).Ores:FindFirstChild("Pine") ~= nil
local studioTools = ServerStorage:FindFirstChild("StudioTools")
local builder = studioTools and studioTools:FindFirstChild("BuildTreesAndAxes")
if not (hasAxe and hasTree) and builder and builder:IsA("ModuleScript") then
	local ok, err = pcall(require, builder)
	if not ok then
		warn(`[Server] 나무·도끼 자동 제작 실패: {err}`)
	end
end

OreService.init()
AntiCheatService.init()
TimingService.init()
FeverService.init()
InventoryService.init()
PickaxeService.init()
MiningService.init()
NpcService.init()
EconomyService.init()
CraftingService.init()
MineService.init()
ItemUseService.init()

print("[Server] 초기화 완료")
