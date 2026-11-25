--!strict
-- Package archetypes and item data (GDD §3.4). M0 set: cake, fish tank, ladder.

export type PartSpec = {
	name: string,
	size: Vector3,
	offset: Vector3, -- relative to the package root
	color: Color3,
	material: Enum.Material?,
	transparency: number?,
	shape: Enum.PartType?,
	count: number?, -- repeat this part along X...
	spacing: number?, -- ...this many studs apart, centered on offset
}

export type PackageDef = {
	id: string,
	displayName: string,
	archetype: "Tall" | "Liquid" | "Long" | "Heavy" | "Alive" | "Coop",
	baseValue: number,

	-- physics
	rootSize: Vector3, -- invisible collision/root part
	mass: number,
	comOffset: Vector3, -- center-of-mass shift via a hidden ballast part
	ballastFraction: number, -- share of total mass placed at comOffset
	friction: number,
	elasticity: number,
	orientationResponsiveness: number, -- AlignOrientation; low = tips easily
	orientationTorque: number, -- MaxTorque multiplier (x mass)
	walkSpeedMultiplier: number,

	-- damage
	fragility: number, -- delta-v threshold, studs/s
	fragilityMultiplier: number, -- damage per stud/s above threshold
	tiltLimit: number?, -- degrees from vertical before tilt damage (Tall/Liquid only)
	tiltDamagePerSecond: number?, -- at 90 degrees past the limit; scales linearly

	visual: { PartSpec },
}

local Packages: { [string]: PackageDef } = {
	cake = {
		id = "cake",
		displayName = "Wedding Cake",
		archetype = "Tall",
		baseValue = 60,

		rootSize = Vector3.new(2.6, 3.6, 2.6),
		mass = 5,
		comOffset = Vector3.new(0, 1.2, 0), -- top-heavy
		ballastFraction = 0.4,
		friction = 0.4,
		elasticity = 0.05,
		orientationResponsiveness = 10,
		orientationTorque = 120,
		walkSpeedMultiplier = 0.95,

		fragility = 16,
		fragilityMultiplier = 3.5,
		tiltLimit = 30,
		tiltDamagePerSecond = 40,

		visual = {
			{ name = "Tier1", size = Vector3.new(1.2, 2.6, 2.6), offset = Vector3.new(0, -1.2, 0), color = Color3.fromRGB(255, 248, 235), shape = Enum.PartType.Cylinder },
			{ name = "Tier2", size = Vector3.new(1.1, 2.0, 2.0), offset = Vector3.new(0, -0.05, 0), color = Color3.fromRGB(255, 240, 245), shape = Enum.PartType.Cylinder },
			{ name = "Tier3", size = Vector3.new(1.0, 1.4, 1.4), offset = Vector3.new(0, 1.0, 0), color = Color3.fromRGB(255, 248, 235), shape = Enum.PartType.Cylinder },
			{ name = "Topper", size = Vector3.new(0.4, 0.6, 0.2), offset = Vector3.new(0, 1.8, 0), color = Color3.fromRGB(255, 120, 160), material = Enum.Material.Neon },
		},
	},

	fishTank = {
		id = "fishTank",
		displayName = "Fish Tank",
		archetype = "Liquid",
		baseValue = 80,

		rootSize = Vector3.new(3.4, 2.4, 2.2),
		mass = 10,
		comOffset = Vector3.new(0, -0.3, 0),
		ballastFraction = 0.3,
		friction = 0.3,
		elasticity = 0.1,
		orientationResponsiveness = 18,
		orientationTorque = 200,
		walkSpeedMultiplier = 0.85,

		fragility = 14,
		fragilityMultiplier = 3,
		tiltLimit = 18,
		tiltDamagePerSecond = 55,

		visual = {
			{ name = "Glass", size = Vector3.new(3.4, 2.4, 2.2), offset = Vector3.zero, color = Color3.fromRGB(200, 235, 255), material = Enum.Material.Glass, transparency = 0.6 },
			{ name = "Water", size = Vector3.new(3.2, 1.8, 2.0), offset = Vector3.new(0, -0.2, 0), color = Color3.fromRGB(60, 150, 230), transparency = 0.4 },
			{ name = "Fish", size = Vector3.new(0.6, 0.35, 0.15), offset = Vector3.new(0.4, -0.1, 0), color = Color3.fromRGB(255, 140, 0), material = Enum.Material.Neon },
		},
	},

	ladder = {
		id = "ladder",
		displayName = "Ladder",
		archetype = "Long",
		baseValue = 45,

		-- long on X so it is carried sideways and catches doorways and poles
		rootSize = Vector3.new(11, 0.5, 1.4),
		mass = 7,
		comOffset = Vector3.zero,
		ballastFraction = 0,
		friction = 0.6,
		elasticity = 0.15,
		orientationResponsiveness = 20,
		orientationTorque = 260,
		walkSpeedMultiplier = 0.9,

		fragility = 22,
		fragilityMultiplier = 1.6,

		visual = {
			{ name = "RailA", size = Vector3.new(11, 0.4, 0.25), offset = Vector3.new(0, 0, -0.55), color = Color3.fromRGB(170, 120, 70), material = Enum.Material.Wood },
			{ name = "RailB", size = Vector3.new(11, 0.4, 0.25), offset = Vector3.new(0, 0, 0.55), color = Color3.fromRGB(170, 120, 70), material = Enum.Material.Wood },
			{ name = "Rungs", size = Vector3.new(0.25, 0.25, 1.1), offset = Vector3.zero, color = Color3.fromRGB(150, 100, 55), material = Enum.Material.Wood, count = 9, spacing = 1.2 },
		},
	},
}

return Packages
