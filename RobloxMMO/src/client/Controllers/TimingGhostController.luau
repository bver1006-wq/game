--!strict
-- 타이밍 잔상: 내가 바위를 치면 돌 모양 잔상이 GhostStartScale 크기에서 바위 크기로 줄어든다.
-- 잔상은 ForceField 재질이라 안쪽은 비쳐 보이고 가장자리(테두리)만 빛난다.
-- 잔상 테두리가 바위 모양과 겹치는 순간 흰색으로 번쩍인다 ("지금!"). 그때 치면 Perfect, 조금 어긋나면 Nice.
-- 판정 자체는 서버(TimingService)가 한다.
-- 잔상의 시작 시각과 줄어드는 시간(타격마다 랜덤)은 서버가 HitEffect로 알려준 값(GetServerTimeNow 기준)을 쓴다.
-- (Highlight 테두리는 반투명 물체에는 그려지지 않아서 쓰지 않는다)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local HitFeelController = require(script.Parent.HitFeelController)

local localPlayer = Players.LocalPlayer

local FLASH_TIME = 0.1 -- 바위 크기에 닿는 순간 번쩍이는 시간(초)

type GhostPart = { Part: BasePart, BaseTransparency: number }
type Ghost = {
	Model: Model,
	Rock: Model,
	HitTime: number,
	Duration: number, -- 바위 크기가 되기까지 걸리는 시간 (서버가 정한 값)
	BaseScale: number,
	Pivot: CFrame,
	Parts: { GhostPart },
}

local TimingGhostController = {}

local folder: Folder
local current: Ghost? = nil

-- 지금 보이는 잔상을 지운다
local function clearGhost()
	if current then
		current.Model:Destroy()
		current = nil
	end
end

-- 잔상 모습을 정한다 (바위 자체 색은 건드리지 않는다)
-- flash: 바위 크기에 닿은 순간(흰색), fade: 0이면 평소, 1이면 완전히 사라짐
local function setGhostLook(ghost: Ghost, flash: boolean, fade: number)
	local timing = Config.Timing
	local transparency = timing.GhostTransparency + (1 - timing.GhostTransparency) * fade
	local color = if flash then timing.GhostFlashColor else timing.GhostColor
	for _, entry in ghost.Parts do
		entry.Part.Transparency = 1 - (1 - entry.BaseTransparency) * (1 - transparency)
		entry.Part.Color = color
	end
end

-- 바위를 복제해서 충돌·조준에 안 걸리는 돌 모양 잔상을 만든다
local function createGhost(rock: Model, hitTime: number, duration: number): Ghost
	local timing = Config.Timing
	local model = rock:Clone()
	-- 자동 조준(OreNode 태그·Hp 속성)에 걸리지 않게 지운다
	-- (RBX_로 시작하는 엔진 속성은 스크립트가 못 지우므로 우리 속성만 지운다)
	CollectionService:RemoveTag(model, "OreNode")
	for _, name in { "OreType", "Hp", "MaxHp" } do
		model:SetAttribute(name, nil)
	end

	local parts: { GhostPart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
			-- 텍스처를 벗기고 ForceField 재질로: 안쪽은 비치고 가장자리만 빛나서 테두리처럼 보인다
			descendant.Material = timing.GhostMaterial
			if descendant:IsA("MeshPart") then
				pcall(function()
					descendant.TextureID = ""
				end)
			end
			table.insert(parts, { Part = descendant, BaseTransparency = descendant.Transparency })
		elseif
			descendant:IsA("SurfaceAppearance")
			or descendant:IsA("Decal")
			or descendant:IsA("Light")
			or descendant:IsA("ParticleEmitter")
			or descendant:IsA("Sound")
			or descendant:IsA("Highlight")
		then
			descendant:Destroy()
		end
	end

	local ghost: Ghost = {
		Model = model,
		Rock = rock,
		HitTime = hitTime,
		Duration = duration,
		BaseScale = model:GetScale(),
		Pivot = HitFeelController.getRestPivot(rock),
		Parts = parts,
	}
	setGhostLook(ghost, false, 0)
	model.Parent = folder
	return ghost
end

-- 매 프레임 잔상 크기를 시각에 맞춰 줄인다
local function update()
	local ghost = current
	if not ghost then
		return
	end
	if not ghost.Rock.Parent then
		clearGhost()
		return
	end

	local timing = Config.Timing
	local elapsed = Workspace:GetServerTimeNow() - ghost.HitTime
	local nice = math.max(timing.Windows.PC.Nice, timing.Windows.Mobile.Nice)

	if elapsed >= ghost.Duration + nice then
		clearGhost() -- 판정 시간이 지났으면 사라진다. 다음 타격은 일반 판정
		return
	end

	local progress = math.clamp(elapsed / ghost.Duration, 0, 1)
	local scale = timing.GhostStartScale + (1 - timing.GhostStartScale) * progress -- 일정한 속도로 줄어야 타이밍을 읽기 쉽다
	ghost.Model:ScaleTo(ghost.BaseScale * scale)
	ghost.Model:PivotTo(ghost.Pivot)

	-- 바위 크기에 닿은 순간 흰색으로 번쩍여서 "지금!"을 알려주고, 남은 Nice 시간 동안 서서히 사라진다
	local sinceTarget = elapsed - ghost.Duration
	if sinceTarget < 0 then
		setGhostLook(ghost, false, 0)
	elseif sinceTarget < FLASH_TIME then
		setGhostLook(ghost, true, 0)
	else
		local fade = (sinceTarget - FLASH_TIME) / math.max(nice - FLASH_TIME, 0.01)
		setGhostLook(ghost, false, math.clamp(fade, 0, 1))
	end
end

-- 서버의 HitEffect: 내가 친 타격이면 새 잔상을 시작한다
local function onHitEffect(
	rock: Model?,
	_judgment: string,
	_hitPosition: Vector3,
	attackerUserId: number,
	hitTime: number,
	ghostDuration: number
)
	if attackerUserId ~= localPlayer.UserId then
		return
	end
	clearGhost()
	if not rock or not rock.Parent then
		return
	end
	local hp = rock:GetAttribute("Hp")
	if typeof(hp) == "number" and hp <= 0 then
		return -- 마지막 일격이면 잔상이 필요 없다
	end
	current = createGhost(rock, hitTime, ghostDuration)
end

-- 클라이언트 시작 시 한 번 호출
function TimingGhostController.init()
	local ghostFolder = Instance.new("Folder")
	ghostFolder.Name = "ClientTimingGhosts"
	ghostFolder.Parent = Workspace
	folder = ghostFolder

	RunService.RenderStepped:Connect(update)
	Remotes.get(Remotes.Names.HitEffect).OnClientEvent:Connect(onHitEffect)
end

-- 피버 등으로 잔상을 강제로 지울 때
TimingGhostController.clear = clearGhost

return TimingGhostController
