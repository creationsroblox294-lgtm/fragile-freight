-- Depot: display delivered packages for passive Coins, plus offline earnings (GDD §5.2).
-- The Depot building is shared; each client draws its own items on the pedestals.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Depot = require(Shared.Config.Depot)
local DepotMath = require(Shared.DepotMath)
local DataService = require(script.Parent.DataService)
local ProfileSync = require(script.Parent.ProfileSync)

local DepotService = {}

local DISPLAY_WINDOW = 30 -- seconds after a delivery during which "Display" is offered
local REQUEST_COOLDOWN = 0.5

-- The last delivered package per player; only it can be put on display.
local pending: { [Player]: { item: DepotMath.Item, at: number } } = {}
local carry: { [Player]: number } = {} -- fractional coins between ticks
local lastRequest: { [Player]: number } = {}

local function rateLimited(player: Player): boolean
	local now = os.clock()
	if now - (lastRequest[player] or 0) < REQUEST_COOLDOWN then
		return true
	end
	lastRequest[player] = now
	return false
end

function DepotService.offer(player: Player, item: DepotMath.Item)
	pending[player] = { item = item, at = os.clock() }
end

local function display(player: Player)
	local profile = DataService.get(player)
	local offer = pending[player]
	if not profile or not offer or os.clock() - offer.at > DISPLAY_WINDOW then
		return
	end
	pending[player] = nil
	local displayed = profile.depot.displayed
	local slots = math.clamp(profile.depot.slots, 0, Depot.MAX_SLOTS)
	if #displayed < slots then
		table.insert(displayed, offer.item)
	else
		local weakest = DepotMath.weakestIndex(displayed)
		if not weakest or DepotMath.perMinute(displayed[weakest]) >= DepotMath.perMinute(offer.item) then
			return -- full, and the new item wouldn't earn more
		end
		displayed[weakest] = offer.item
	end
	ProfileSync.send(player)
end

local function remove(player: Player, slot: any)
	local profile = DataService.get(player)
	if not profile or type(slot) ~= "number" or slot ~= slot then
		return
	end
	slot = math.floor(slot)
	if slot < 1 or slot > #profile.depot.displayed then
		return
	end
	table.remove(profile.depot.displayed, slot)
	ProfileSync.send(player)
end

local function payOffline(player: Player, profile)
	local items = profile.depot.displayed
	local coins, seconds = DepotMath.offlineEarnings(items, profile.lastOnline, os.time())
	profile.lastOnline = os.time()
	if coins > 0 then
		DataService.addCoins(player, coins)
		Remotes.get("OfflineEarnings"):FireClient(player, coins, seconds)
	end
end

function DepotService.init()
	Remotes.get("RequestDisplay").OnServerEvent:Connect(function(player)
		if not rateLimited(player) then
			display(player)
		end
	end)
	Remotes.get("RequestRemoveDisplay").OnServerEvent:Connect(function(player, slot)
		if not rateLimited(player) then
			remove(player, slot)
		end
	end)

	DataService.onLoaded(function(player, profile)
		-- Drop anything invalid (renamed package ids etc.) before paying.
		local valid = {}
		for _, item in profile.depot.displayed do
			if type(item) == "table" and DepotMath.isValid(item) then
				table.insert(valid, item)
			end
		end
		profile.depot.displayed = valid
		payOffline(player, profile)
		ProfileSync.send(player)
	end)

	task.spawn(function()
		while true do
			task.wait(Depot.TICK_SECONDS)
			for _, player in Players:GetPlayers() do
				local profile = DataService.get(player)
				if profile then
					local earned = DepotMath.totalPerMinute(profile.depot.displayed) * Depot.TICK_SECONDS / 60
						+ (carry[player] or 0)
					local whole = math.floor(earned)
					carry[player] = earned - whole
					if whole > 0 then
						DataService.addCoins(player, whole)
					end
					profile.lastOnline = os.time()
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
		carry[player] = nil
		lastRequest[player] = nil
	end)
end

return DepotService
