--!strict
-- 저장(DataStore): 골드·가방·가방 칸·장비·빠른 칸을 플레이어마다 저장하고 다시 들어오면 불러온다 (2026-10-09)
-- 다른 서비스는 register로 "저장할 칸"을 등록한다 (InventoryService → "Inventory", EquipmentService → "Equipped")
-- 빠른 칸 배치는 클라이언트가 SaveHotbar로 보내고, 들어올 때 플레이어 속성 SavedHotbar(쉼표로 이은 Id)로 돌려준다
--
-- 안전장치
--   - 불러오기에 실패하면 이번 접속은 저장하지 않는다 (빈 데이터로 덮어써서 날리지 않게) + 알림
--   - 세션 잠금: 다른 서버가 쓰고 있으면(Lock) 잠깐 기다렸다가 다시 시도, 오래된 잠금은 넘겨받는다
--   - 자동 저장 AutoSaveInterval초마다, 나갈 때, 서버가 꺼질 때(BindToClose)
-- Studio에서 쓰려면: 게임을 게시하고 Game Settings → Security → "Enable Studio Access to API Services" 켜기
-- Studio는 테스트용 지급(Config.Debug)이 섞이지 않게 다른 저장소(StudioStoreName)를 쓴다

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local ItemDefs = require(ReplicatedStorage.Shared.ItemDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local NotifyService = require(script.Parent.NotifyService)

local DATA_VERSION = 1

type Session = {
	Data: { [string]: any }, -- 불러온 원본 (모르는 칸도 그대로 다시 저장한다)
	CanSave: boolean, -- 불러오기에 성공했을 때만 true
	IsNew: boolean, -- 처음 들어온 플레이어
	Hotbar: { string },
	Saving: boolean,
	Released: boolean,
}

local DataService = {}

local sessions: { [Player]: Session } = {}
local sections: { [string]: (player: Player) -> any } = {} -- 칸 이름 → 지금 값을 돌려주는 함수
local store: DataStore? = nil
local jobId = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)

local function keyFor(player: Player): string
	return `Player_{player.UserId}`
end

-- 실패하면 몇 번 다시 시도한다 (DataStore는 가끔 실패한다)
local function retry<T>(label: string, fn: () -> T): (boolean, T?)
	local lastError: any = nil
	for attempt = 1, Config.Save.Retries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = result
		warn(`[DataService] {label} 실패 ({attempt}/{Config.Save.Retries}): {result}`)
		-- Studio에서 API 접근이 꺼져 있거나 게시 안 된 게임이면 다시 해도 소용없다
		local message = tostring(result)
		if string.find(message, "403") or string.find(message, "Studio") or string.find(message, "publish") then
			break
		end
		task.wait(attempt * 1.5)
	end
	warn(`[DataService] {label} 포기: {lastError}`)
	return false, nil
end

-- 저장소 준비 (Studio에서 API 접근이 꺼져 있으면 실패한다)
local function getStore(): DataStore?
	if store then
		return store
	end
	local name = if RunService:IsStudio() then Config.Save.StudioStoreName else Config.Save.StoreName
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(name)
	end)
	if ok then
		store = result
		return result
	end
	warn(`[DataService] 저장소를 열 수 없어요: {result}`)
	return nil
end

-- 지금 상태를 저장용 표로 모은다
local function collect(player: Player, session: Session): { [string]: any }
	local data = table.clone(session.Data)
	for name, getter in sections do
		local ok, value = pcall(getter, player)
		if ok and value ~= nil then
			data[name] = value
		end
	end
	data.Hotbar = table.clone(session.Hotbar)
	data.Version = DATA_VERSION
	return data
end

-- 저장한다. release면 잠금도 푼다 (나갈 때)
local function save(player: Player, session: Session, release: boolean, snapshot: { [string]: any }?)
	if not session.CanSave or session.Released then
		return
	end
	local dataStore = getStore()
	if not dataStore then
		return
	end
	if release then
		session.Released = true
	end
	local data = snapshot or collect(player, session)
	data.Lock = if release then nil else { JobId = jobId, Time = os.time() }
	data.SavedAt = os.time()
	session.Saving = true
	retry(`{player.Name} 저장`, function()
		dataStore:UpdateAsync(keyFor(player), function(old: any)
			-- 자동 저장이 늦게 도착했는데 그사이 나가서 잠금을 풀었으면, 다시 잠그지 않게 건너뛴다
			if not release and session.Released then
				return nil
			end
			-- 다른 서버가 잠금을 넘겨받았으면 덮어쓰지 않는다
			if typeof(old) == "table" and typeof(old.Lock) == "table" and old.Lock.JobId ~= jobId then
				return nil
			end
			return data
		end)
		return true
	end)
	session.Saving = false
end

-- 불러온 표가 표가 아니면 빈 표로 (칸별 정리는 각 서비스가 한다)
local function sanitize(raw: any): { [string]: any }
	local data: { [string]: any } = if typeof(raw) == "table" then raw else {}
	return data
end

-- 불러오기 (세션 잠금 포함). 성공하면 (true, data, isNew)
local function load(player: Player): (boolean, { [string]: any }, boolean)
	local dataStore = getStore()
	if not dataStore then
		return false, {}, true
	end
	local result: any = nil
	local isNew = false
	for _ = 1, Config.Save.LockWaitTries do
		local locked = false
		local ok = retry(`{player.Name} 불러오기`, function()
			dataStore:UpdateAsync(keyFor(player), function(old: any)
				local lock = typeof(old) == "table" and old.Lock
				if typeof(lock) == "table" and lock.JobId ~= jobId and os.time() - (tonumber(lock.Time) or 0) < Config.Save.LockTimeout then
					-- 다른 서버가 아직 쓰는 중 (방금 옮겨 왔을 때). 잠깐 뒤에 다시
					locked = true
					result = nil
					return nil
				end
				locked = false
				isNew = typeof(old) ~= "table"
				local data = if typeof(old) == "table" then old else { Version = DATA_VERSION }
				data.Lock = { JobId = jobId, Time = os.time() }
				result = data
				return data
			end)
			return true
		end)
		if not ok then
			return false, {}, true
		end
		if not locked then
			return true, sanitize(result), isNew
		end
		task.wait(Config.Save.LockWaitSeconds)
	end
	-- 계속 잠겨 있으면 (서버가 죽어서 잠금이 남은 경우) 넘겨받는다
	local ok = retry(`{player.Name} 잠금 넘겨받기`, function()
		dataStore:UpdateAsync(keyFor(player), function(old: any)
			isNew = typeof(old) ~= "table"
			local data = if typeof(old) == "table" then old else { Version = DATA_VERSION }
			data.Lock = { JobId = jobId, Time = os.time() }
			result = data
			return data
		end)
		return true
	end)
	if not ok then
		return false, {}, true
	end
	return true, sanitize(result), isNew
end

-- 빠른 칸 배치 정리 (Id 문자열 목록, 빈 칸은 "")
local function cleanHotbar(raw: any): { string }
	local hotbar: { string } = {}
	if typeof(raw) ~= "table" then
		return hotbar
	end
	for index = 1, Config.Inventory.HotbarSlots do
		local id = raw[index]
		hotbar[index] = if typeof(id) == "string" and ItemDefs.Items[id] then id else ""
	end
	return hotbar
end

-- 저장할 칸을 등록한다. getter는 지금 값(저장 가능한 표·숫자·문자열)을 돌려준다
function DataService.register(name: string, getter: (player: Player) -> any)
	sections[name] = getter
end

-- 플레이어 데이터를 불러온다 (InventoryService가 들어올 때 부른다. 잠깐 멈출 수 있다)
-- 돌려주는 값: 저장된 표 (처음이거나 실패면 빈 표)
function DataService.load(player: Player): { [string]: any }
	local existing = sessions[player]
	if existing then
		return existing.Data
	end
	local ok, data, isNew = load(player)
	if not player.Parent then
		-- 불러오는 동안 나갔다: 잠금만 풀어 둔다
		if ok then
			local session: Session = { Data = data, CanSave = true, IsNew = isNew, Hotbar = cleanHotbar(data.Hotbar), Saving = false, Released = false }
			task.spawn(save, player, session, true, data)
		end
		return {}
	end
	if not ok then
		data = {}
		isNew = true
		NotifyService.send(player, "저장된 기록을 불러오지 못했어요. 이번 접속은 저장되지 않아요.", "bad")
	end
	local session: Session = {
		Data = data,
		CanSave = ok,
		IsNew = isNew,
		Hotbar = cleanHotbar(data.Hotbar),
		Saving = false,
		Released = false,
	}
	sessions[player] = session
	player:SetAttribute("SavedHotbar", table.concat(session.Hotbar, ","))
	print(`[DataService] {player.Name} 불러오기 {if ok then "성공" else "실패"}{if isNew then " (처음)" else ""}`)
	return data
end

-- 처음 들어온 플레이어인가 (테스트 지급은 처음에만)
function DataService.isNew(player: Player): boolean
	local session = sessions[player]
	return session == nil or session.IsNew
end

-- 지금 바로 저장 (중요한 거래 직후 등)
function DataService.saveNow(player: Player)
	local session = sessions[player]
	if session and not session.Saving then
		task.spawn(save, player, session, false)
	end
end

-- 서버 시작 시 한 번 호출 (다른 서비스보다 먼저)
function DataService.init()
	getStore()

	-- 클라이언트가 보내는 빠른 칸 배치
	Remotes.get(Remotes.Names.SaveHotbar).OnServerEvent:Connect(function(player, raw)
		local session = sessions[player]
		if session and typeof(raw) == "table" then
			session.Hotbar = cleanHotbar(raw)
		end
	end)

	-- 나갈 때: 상태를 바로 모아 두고(다른 서비스가 정리하기 전에) 저장 + 잠금 풀기
	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if not session then
			return
		end
		local snapshot = collect(player, session)
		save(player, session, true, snapshot)
		sessions[player] = nil
	end)

	-- 자동 저장
	task.spawn(function()
		while true do
			task.wait(Config.Save.AutoSaveInterval)
			for player, session in sessions do
				if not session.Saving then
					task.spawn(save, player, session, false)
				end
			end
		end
	end)

	-- 서버가 꺼질 때 남은 사람 모두 저장
	game:BindToClose(function()
		local pending = 0
		for player, session in sessions do
			pending += 1
			task.spawn(function()
				save(player, session, true, collect(player, session))
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.1)
		end
	end)
end

return DataService
