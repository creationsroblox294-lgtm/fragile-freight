--!strict
-- Rarity table (GDD §4.1). Order matters: index 1 is the most common.

export type RarityDef = {
	id: string,
	displayName: string,
	weight: number, -- base roll weight
	valueMultiplier: number, -- payout and Depot income
	fragilityMultiplier: number, -- multiplies impact and tilt damage
	color: Color3,
	announce: boolean, -- server-wide banner on roll
}

local list: { RarityDef } = {
	{ id = "Common", displayName = "Common", weight = 60, valueMultiplier = 1, fragilityMultiplier = 1.0, color = Color3.fromRGB(200, 200, 205), announce = false },
	{ id = "Uncommon", displayName = "Uncommon", weight = 25, valueMultiplier = 1.8, fragilityMultiplier = 1.1, color = Color3.fromRGB(95, 215, 105), announce = false },
	{ id = "Rare", displayName = "Rare", weight = 10, valueMultiplier = 3.5, fragilityMultiplier = 1.25, color = Color3.fromRGB(70, 150, 255), announce = false },
	{ id = "Epic", displayName = "Epic", weight = 4, valueMultiplier = 8, fragilityMultiplier = 1.4, color = Color3.fromRGB(180, 90, 255), announce = false },
	{ id = "Legendary", displayName = "Legendary", weight = 0.9, valueMultiplier = 25, fragilityMultiplier = 1.6, color = Color3.fromRGB(255, 180, 40), announce = true },
	{ id = "Mythic", displayName = "Mythic", weight = 0.1, valueMultiplier = 100, fragilityMultiplier = 1.8, color = Color3.fromRGB(255, 60, 120), announce = true },
}

local byId: { [string]: RarityDef } = {}
local rank: { [string]: number } = {}
for i, r in list do
	byId[r.id] = r
	rank[r.id] = i
end

return {
	list = list,
	byId = byId,
	rank = rank, -- Common = 1 ... Mythic = 6
	PITY_THRESHOLD = 40, -- orders without PITY_MIN_RARITY or better before a guarantee
	PITY_MIN_RARITY = "Epic",
}
