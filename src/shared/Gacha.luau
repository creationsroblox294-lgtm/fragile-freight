--!strict
-- Pure roll logic (GDD §4). No Roblox services: pass in any RNG with :NextNumber() so the
-- specs can seed it. The server wraps this in GachaService; the odds screen reuses the odds
-- functions so what players see is exactly what the server rolls.

local Rarities = require(script.Parent.Config.Rarities)
local Mutations = require(script.Parent.Config.Mutations)
local Tips = require(script.Parent.Config.Tips)

export type Rng = { NextNumber: (self: any) -> number }
export type Odds = { { id: string, chance: number } } -- chance in 0..1, sums to 1

local Gacha = {}

local function pick<T>(rng: Rng, entries: { T }, weightOf: (T) -> number): T
	local total = 0
	for _, e in entries do
		total += math.max(weightOf(e), 0)
	end
	local r = rng:NextNumber() * total
	for _, e in entries do
		local w = math.max(weightOf(e), 0)
		if r < w then
			return e
		end
		r -= w
	end
	return entries[#entries] -- floating point leftovers
end

local function rarityWeight(r: Rarities.RarityDef, luck: number, pityActive: boolean): number
	if pityActive and Rarities.rank[r.id] < Rarities.rank[Rarities.PITY_MIN_RARITY] then
		return 0
	end
	if r.id == "Common" then
		return r.weight
	end
	return r.weight * (1 + math.max(luck, 0))
end

-- Pity is the count of orders since the last Epic-or-better. Returns the new count.
function Gacha.rollRarity(rng: Rng, luck: number, pity: number): (string, number, boolean)
	local pityActive = pity >= Rarities.PITY_THRESHOLD
	local rarity = pick(rng, Rarities.list, function(r)
		return rarityWeight(r, luck, pityActive)
	end)
	local hit = Rarities.rank[rarity.id] >= Rarities.rank[Rarities.PITY_MIN_RARITY]
	return rarity.id, if hit then 0 else pity + 1, pityActive
end

function Gacha.rollMutation(rng: Rng): string
	return pick(rng, Mutations.list, function(m)
		return m.chance
	end).id
end

local function moodAllowed(m: Tips.MoodDef, condition: number): boolean
	return m.minCondition == nil or condition >= m.minCondition
end

-- Gated moods (Jackpot below 90 condition) can't come up; their share is spread over the rest.
function Gacha.rollTip(rng: Rng, condition: number): string
	return pick(rng, Tips.list, function(m)
		return if moodAllowed(m, condition) then m.chance else 0
	end).id
end

function Gacha.rarityOdds(luck: number, pity: number): Odds
	local pityActive = pity >= Rarities.PITY_THRESHOLD
	local total = 0
	for _, r in Rarities.list do
		total += rarityWeight(r, luck, pityActive)
	end
	local odds = {}
	for _, r in Rarities.list do
		table.insert(odds, { id = r.id, chance = rarityWeight(r, luck, pityActive) / total })
	end
	return odds
end

function Gacha.mutationOdds(): Odds
	local odds = {}
	for _, m in Mutations.list do
		table.insert(odds, { id = m.id, chance = m.chance / 100 })
	end
	return odds
end

function Gacha.tipOdds(condition: number): Odds
	local total = 0
	for _, m in Tips.list do
		total += if moodAllowed(m, condition) then m.chance else 0
	end
	local odds = {}
	for _, m in Tips.list do
		table.insert(odds, { id = m.id, chance = (if moodAllowed(m, condition) then m.chance else 0) / total })
	end
	return odds
end

-- Index key for a delivered package, e.g. "cake_Rare_Golden" (GDD §6.3).
function Gacha.indexKey(packageId: string, rarity: string, mutation: string): string
	return string.format("%s_%s_%s", packageId, rarity, mutation)
end

return Gacha
