--!strict
-- 마나와 달리기 모드.
-- 마나는 플레이어 속성 Mana·MaxMana로 클라이언트에 보인다. 스킬·차징 스매시(나중에)·달리기에 쓴다.
-- 달리기 모드(속성 Sprinting)는 클라이언트 버튼이 켜고 끄지만, 속도와 마나 소모는 서버가 정한다.
-- 움직이는 동안만 마나가 줄고, 마나가 바닥나면 달리기가 저절로 꺼진다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local NotifyService = require(script.Parent.NotifyService)

local ManaService = {}

local lastSpend: { [Player]: number } = {}

local function getMana(player: Player): number
	local mana = player:GetAttribute("Mana")
	return if typeof(mana) == "number" then mana else 0
end

local function setMana(player: Player, value: number)
	local clamped = math.clamp(value, 0, Config.Mana.Max)
	-- 속성 복제를 줄이려고 소수 첫째 자리까지만
	player:SetAttribute("Mana", math.floor(clamped * 10 + 0.5) / 10)
end

-- 지금 마나
function ManaService.get(player: Player): number
	return getMana(player)
end

-- 마나를 쓴다. 모자라면 쓰지 않고 false (스킬·차징 스매시용)
function ManaService.spend(player: Player, amount: number): boolean
	if getMana(player) < amount then
		return false
	end
	setMana(player, getMana(player) - amount)
	lastSpend[player] = os.clock()
	return true
end

-- 마나를 채운다 (음식 등). 실제로 채운 양을 돌려준다
function ManaService.add(player: Player, amount: number): number
	local before = getMana(player)
	setMana(player, before + amount)
	return getMana(player) - before
end

-- 마나가 가득 찼는지
function ManaService.isFull(player: Player): boolean
	return getMana(player) >= Config.Mana.Max
end

-- 달리기 끄기·켜기
local function setSprint(player: Player, on: boolean)
	if on and getMana(player) <= 0 then
		NotifyService.send(player, "마나가 없어서 달릴 수 없어요.", "bad")
		on = false
	end
	player:SetAttribute("Sprinting", on)
end

-- 매 프레임: 달리는 중이면 속도를 올리고 마나를 쓰고, 아니면 마나를 채운다
local function step(dt: number)
	local now = os.clock()
	local movement = Config.Movement
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and root and root:IsA("BasePart") and humanoid.Health > 0 then
			local sprinting = player:GetAttribute("Sprinting") == true
			local velocity = root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
			local moving = velocity.Magnitude > movement.MovingThreshold
			local speed = if sprinting then movement.SprintSpeed else movement.WalkSpeed
			if humanoid.WalkSpeed ~= speed then
				humanoid.WalkSpeed = speed
			end
			if sprinting and moving then
				setMana(player, getMana(player) - movement.SprintManaPerSecond * dt)
				lastSpend[player] = now
				if getMana(player) <= 0 then
					player:SetAttribute("Sprinting", false)
					NotifyService.send(player, "마나가 바닥나서 달리기를 멈췄어요.", "info")
				end
			elseif now - (lastSpend[player] or 0) >= Config.Mana.RegenDelay and not ManaService.isFull(player) then
				setMana(player, getMana(player) + Config.Mana.Regen * dt)
			end
		end
	end
end

-- 서버 시작 시 한 번 호출
function ManaService.init()
	local function onPlayerAdded(player: Player)
		player:SetAttribute("MaxMana", Config.Mana.Max)
		player:SetAttribute("Mana", Config.Mana.Max)
		player:SetAttribute("Sprinting", false)
		-- 다시 태어나면 마나를 채우고 달리기는 끈다
		player.CharacterAdded:Connect(function()
			player:SetAttribute("Mana", Config.Mana.Max)
			player:SetAttribute("Sprinting", false)
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastSpend[player] = nil
	end)
	Remotes.get(Remotes.Names.SetSprint).OnServerEvent:Connect(function(player, on)
		setSprint(player, on == true)
	end)
	RunService.Heartbeat:Connect(step)
end

return ManaService
