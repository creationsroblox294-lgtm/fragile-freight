--!strict
-- Pure Depot income math (GDD §5.2). No Roblox services; specs in tests/.

local Packages = require(script.Parent.Config.Packages)
local Rarities = require(script.Parent.Config.Rarities)
local Mutations = require(script.Parent.Config.Mutations)
local Depot = require(script.Parent.Config.Depot)

export type Item = { id: string, rarity: string, mutation: string }

local DepotMath = {}

function DepotMath.isValid(item: Item): boolean
	return Packages[item.id] ~= nil and Rarities.byId[item.rarity] ~= nil and Mutations.byId[item.mutation] ~= nil
end

function DepotMath.perMinute(item: Item): number
	if not DepotMath.isValid(item) then
		return 0
	end
	return Packages[item.id].baseValue
		* Rarities.byId[item.rarity].valueMultiplier
		* Mutations.byId[item.mutation].payMultiplier
		* Depot.INCOME_FACTOR
end

function DepotMath.totalPerMinute(items: { Item }): number
	local total = 0
	for _, item in items do
		total += DepotMath.perMinute(item)
	end
	return total
end

-- Coins earned while away, capped at 8 hours. Clock skew (now < lastOnline) earns nothing.
function DepotMath.offlineEarnings(items: { Item }, lastOnline: number, now: number): (number, number)
	if lastOnline <= 0 then
		return 0, 0
	end
	local seconds = math.clamp(now - lastOnline, 0, Depot.OFFLINE_CAP_SECONDS)
	return math.floor(DepotMath.totalPerMinute(items) * seconds / 60), seconds
end

-- Index of the lowest-earning item, for "replace weakest" when the Depot is full.
function DepotMath.weakestIndex(items: { Item }): number?
	local best, bestRate = nil, math.huge
	for i, item in items do
		local rate = DepotMath.perMinute(item)
		if rate < bestRate then
			best, bestRate = i, rate
		end
	end
	return best
end

function DepotMath.pedestalPosition(index: number): Vector3
	local col = (index - 1) % Depot.COLUMNS
	local row = math.floor((index - 1) / Depot.COLUMNS)
	local half = (Depot.COLUMNS - 1) / 2
	return Depot.ORIGIN + Vector3.new((col - half) * Depot.SPACING, 0, (row - 1.5) * Depot.SPACING)
end

return DepotMath
