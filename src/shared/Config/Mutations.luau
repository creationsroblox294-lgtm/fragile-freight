--!strict
-- Mutation table (GDD §4.2). Every mutation except Rainbow changes how the carry feels.

export type MutationDef = {
	id: string,
	displayName: string,
	chance: number, -- percent; the list sums to 100
	payMultiplier: number,
	color: Color3?,
	-- physics
	massMultiplier: number,
	damageMultiplier: number, -- Glass: fragility x2
	elasticity: number?, -- Bouncy: overrides the package's elasticity
	material: Enum.Material?,
	tint: Color3?, -- recolors the visual parts
	haunted: boolean?, -- random impulses + float
	rainbow: boolean?, -- animated hue, cosmetic only
}

local list: { MutationDef } = {
	{ id = "None", displayName = "", chance = 85, payMultiplier = 1, massMultiplier = 1, damageMultiplier = 1 },
	{ id = "Golden", displayName = "Golden", chance = 5, payMultiplier = 2, color = Color3.fromRGB(255, 200, 50), massMultiplier = 1.2, damageMultiplier = 1, material = Enum.Material.Foil, tint = Color3.fromRGB(255, 196, 45) },
	{ id = "Glass", displayName = "Glass", chance = 4, payMultiplier = 3, color = Color3.fromRGB(170, 230, 255), massMultiplier = 1, damageMultiplier = 2, material = Enum.Material.Glass },
	{ id = "Bouncy", displayName = "Bouncy", chance = 3, payMultiplier = 1.5, color = Color3.fromRGB(255, 120, 200), massMultiplier = 1, damageMultiplier = 1, elasticity = 0.9 },
	{ id = "Haunted", displayName = "Haunted", chance = 2, payMultiplier = 2.5, color = Color3.fromRGB(150, 255, 200), massMultiplier = 1, damageMultiplier = 1, haunted = true },
	{ id = "Rainbow", displayName = "Rainbow", chance = 1, payMultiplier = 5, color = Color3.fromRGB(255, 255, 255), massMultiplier = 1, damageMultiplier = 1, rainbow = true },
}

local byId: { [string]: MutationDef } = {}
for _, m in list do
	byId[m.id] = m
end

return {
	list = list,
	byId = byId,
	HAUNTED_INTERVAL = { 1, 3 }, -- seconds between ghost shoves
	HAUNTED_IMPULSE = 9, -- studs/s of velocity change per shove
	HAUNTED_FLOAT = 0.25, -- fraction of gravity cancelled
}
