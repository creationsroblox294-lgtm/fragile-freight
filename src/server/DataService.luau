-- Player data: load/save with session locking (GDD §6.3).
--
-- Each record is { data = <profile>, lock = { jobId, time } | nil }. A server only loads a
-- profile after writing its own lock, and only saves while it still owns the lock, so a
-- player who server-hops can't run two copies of their data. Locks older than
-- LOCK_STALE_AFTER belong to a crashed server and may be taken over.
--
-- In Studio with "Enable Studio Access to API Services" off, DataStores error; the service
-- then runs from memory for the session and warns once.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DataConfig = require(Shared.Config.DataConfig)

local DataService = {}

export type Profile = typeof(DataConfig.TEMPLATE)

local profiles: { [Player]: Profile } = {}
local loadedSignal = Instance.new("BindableEvent")
local releasing: { [Player]: boolean } = {}

-- A Studio test session has no JobId; give it a unique one so its locks are distinguishable.
local JOB_ID = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)

local store: DataStore? = nil
local memoryMode = false

local function enterMemoryMode(reason: string)
	if not memoryMode then
		memoryMode = true
		warn("[DataService] Saving is OFF for this session (" .. reason .. "). "
			.. "In Studio, enable Game Settings > Security > Enable Studio Access to API Services.")
	end
end

do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(DataConfig.STORE_NAME)
	end)
	if ok then
		store = result
	else
		enterMemoryMode(tostring(result))
	end
end

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value :: any do
		copy[k] = deepCopy(v)
	end
	return copy :: any
end

-- Fill in keys added to the template since this profile was saved.
local function reconcile(data: { [any]: any }, template: { [any]: any })
	for k, v in template do
		if data[k] == nil then
			data[k] = deepCopy(v)
		elseif type(v) == "table" and type(data[k]) == "table" and next(v) ~= nil then
			reconcile(data[k], v)
		end
	end
end

-- Schema migrations: bump DataConfig.VERSION and add a step here.
local MIGRATIONS: { [number]: (any) -> () } = {
	-- [1] = function(data) ... end, -- v1 -> v2
}

local function migrate(data: any)
	data.version = data.version or 1
	while data.version < DataConfig.VERSION do
		local step = MIGRATIONS[data.version]
		if step then
			step(data)
		end
		data.version += 1
	end
end

local function isApiAccessError(err: string): boolean
	return err:find("StudioAccessToApisNotAllowed") ~= nil or err:find("API Services") ~= nil
		or err:find("403") ~= nil or err:find("publish") ~= nil
end

-- Calls fn with exponential backoff. Returns ok, result.
local function withRetries(label: string, fn: () -> any): (boolean, any)
	local delay = 1
	local lastErr
	for attempt = 1, DataConfig.RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = tostring(result)
		if isApiAccessError(lastErr) then
			enterMemoryMode(lastErr)
			return false, lastErr
		end
		warn(string.format("[DataService] %s failed (attempt %d): %s", label, attempt, lastErr))
		if attempt < DataConfig.RETRIES then
			task.wait(delay)
			delay *= 2
		end
	end
	return false, lastErr
end

local function keyFor(player: Player): string
	return "u_" .. player.UserId
end

type Record = { data: any, lock: { jobId: string, time: number }? }

-- Returns the profile, "locked" if another live server still owns it, or nil on failure.
local function tryLoad(player: Player): (Profile | string | nil)
	local loaded: any = nil
	local lockedBy: string? = nil
	local ok = withRetries("load " .. player.UserId, function()
		lockedBy = nil
		;(store :: DataStore):UpdateAsync(keyFor(player), function(record: Record?)
			local now = os.time()
			if record and record.lock and record.lock.jobId ~= JOB_ID
				and now - record.lock.time < DataConfig.LOCK_STALE_AFTER then
				lockedBy = record.lock.jobId
				return nil -- abort: don't touch someone else's live session
			end
			local data = if record and record.data then record.data else deepCopy(DataConfig.TEMPLATE)
			loaded = data
			return { data = data, lock = { jobId = JOB_ID, time = now } }
		end)
	end)
	if not ok then
		return nil
	end
	if lockedBy then
		return "locked"
	end
	return loaded
end

local function save(player: Player, release: boolean): boolean
	local profile = profiles[player]
	if not profile or memoryMode or not store then
		return memoryMode
	end
	profile.lastOnline = os.time()
	local lostLock = false
	local ok = withRetries("save " .. player.UserId, function()
		lostLock = false
		;(store :: DataStore):UpdateAsync(keyFor(player), function(record: Record?)
			if record and record.lock and record.lock.jobId ~= JOB_ID then
				lostLock = true
				return nil -- another server took over; never overwrite its data
			end
			return {
				data = profile,
				lock = if release then nil else { jobId = JOB_ID, time = os.time() },
			}
		end)
	end)
	if lostLock then
		warn("[DataService] lost session lock for " .. player.UserId .. "; not saving")
	end
	return ok and not lostLock
end

local function onPlayerAdded(player: Player)
	local profile: Profile? = nil
	if memoryMode or not store then
		profile = deepCopy(DataConfig.TEMPLATE)
	else
		for _ = 1, DataConfig.LOAD_ATTEMPTS do
			local result = tryLoad(player)
			if memoryMode then
				profile = deepCopy(DataConfig.TEMPLATE)
				break
			end
			if type(result) == "table" then
				profile = result
				break
			end
			if result == nil then
				break -- hard failure after retries
			end
			task.wait(DataConfig.LOCK_WAIT) -- "locked": the old server is probably still saving
		end
	end

	if not player.Parent then
		-- Left while loading: hand the lock straight back.
		if profile and not memoryMode then
			profiles[player] = profile
			save(player, true)
			profiles[player] = nil
		end
		return
	end
	if not profile then
		player:Kick("Fragile Freight couldn't load your data. Please rejoin in a minute.")
		return
	end

	reconcile(profile, DataConfig.TEMPLATE)
	migrate(profile)
	profiles[player] = profile

	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = profile.coins
	coins.Parent = stats
	local tips = Instance.new("IntValue")
	tips.Name = "Tips"
	tips.Value = profile.lifetimeTips
	tips.Parent = stats
	stats.Parent = player

	player:SetAttribute("DataLoaded", true)
	loadedSignal:Fire(player, profile)
end

local function onPlayerRemoving(player: Player)
	if releasing[player] then
		return
	end
	releasing[player] = true
	if profiles[player] then
		save(player, true)
	end
	profiles[player] = nil
	releasing[player] = nil
end

--== Public API ==--

function DataService.get(player: Player): Profile?
	return profiles[player]
end

-- Yields until the player's data is loaded; nil if they left first.
function DataService.waitFor(player: Player): Profile?
	while player.Parent and not profiles[player] do
		task.wait(0.1)
	end
	return profiles[player]
end

-- fn(player, profile) for everyone already loaded and everyone who loads later.
function DataService.onLoaded(fn: (Player, Profile) -> ())
	for player, profile in profiles do
		task.spawn(fn, player, profile)
	end
	loadedSignal.Event:Connect(fn)
end

local function mirror(player: Player, name: string, value: number)
	local stats = player:FindFirstChild("leaderstats")
	local v = stats and stats:FindFirstChild(name) :: IntValue?
	if v then
		v.Value = value
	end
end

function DataService.addCoins(player: Player, amount: number): number
	local profile = profiles[player]
	if not profile then
		return 0
	end
	profile.coins = math.max(0, math.floor(profile.coins + amount))
	mirror(player, "Coins", profile.coins)
	return profile.coins
end

function DataService.addTips(player: Player, amount: number)
	local profile = profiles[player]
	if not profile or amount <= 0 then
		return
	end
	profile.lifetimeTips += math.floor(amount)
	mirror(player, "Tips", profile.lifetimeTips)
end

function DataService.isMemoryMode(): boolean
	return memoryMode
end

function DataService.init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	task.spawn(function()
		while true do
			task.wait(DataConfig.AUTOSAVE_INTERVAL)
			for player in profiles do
				task.spawn(save, player, false)
			end
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() and memoryMode then
			return
		end
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				onPlayerRemoving(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
