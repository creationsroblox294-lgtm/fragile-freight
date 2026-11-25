--!strict
-- Global tuning knobs. Every number here is a starting value for playtests (GDD §3, §5).

local Tuning = {
	-- Ragdoll (GDD §3.1)
	TRIP_IMPACT_SPEED = 28, -- studs/s of horizontal velocity change in one frame
	TRIP_FALL_HEIGHT = 12, -- studs fallen before landing trips you
	RAGDOLL_TIME = 1.2, -- seconds before auto get-up
	RAGDOLL_MIN_TIME = 0.4, -- earliest the Get Up button works
	RAGDOLL_COOLDOWN = 0.75, -- immunity after getting up, so you don't chain-trip

	-- Carry (GDD §3.2)
	HOLD_OFFSET = Vector3.new(0, 0.6, -2.6), -- hold point relative to HumanoidRootPart
	GRIP_RESPONSIVENESS = 25,
	GRIP_FORCE_PER_MASS = 4, -- AlignPosition MaxForce = assembly mass * gravity * this
	DROP_DISTANCE = 4, -- studs of AlignPosition error...
	DROP_DISTANCE_TIME = 0.5, -- ...held this long drops the package
	PICKUP_RANGE = 10,

	-- Damage (GDD §3.3)
	SAMPLE_RATE = 20, -- server velocity samples per second
	CONDITION_UPDATE_RATE = 5, -- ConditionUpdate remote, max per second
	CONTACT_WINDOW = 0.15, -- seconds a Touched contact keeps the impact gate open
	CONTACT_PADDING = 0.5, -- studs added to the package box when checking for contact
	DEBUG_HUD = true, -- show last hit / damage source under the condition bar (playtests)
	MAX_PACKAGE_SPEED = 90, -- studs/s; faster than this voids the delivery
	MAX_TELEPORT_DISTANCE = 25, -- studs between two samples
	VOID_Y = -60, -- package below this height breaks
	BROKEN_PAYOUT = 0.1, -- consolation fraction of BaseValue

	-- Economy (GDD §5.1)
	CONDITION_EXPONENT = 1.5,
	TIME_BONUS_MAX = 1.25, -- at or under par
	PAR_SPEED = 11, -- studs/s used to compute par time from route length
	MIN_ROUTE_SPEED = 40, -- studs/s; arriving faster than distance/this is rejected

	-- Orders
	ORDER_COOLDOWN = 2,
	BASE_WALK_SPEED = 16,
}

return Tuning
