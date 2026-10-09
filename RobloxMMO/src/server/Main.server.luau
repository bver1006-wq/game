--!strict
-- 서버 진입점. RemoteEvent를 만들고 서비스를 순서대로 초기화한다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
