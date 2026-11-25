--!strict
-- Depot passive income (GDD §5.2).

return {
	INCOME_FACTOR = 0.02, -- coins per minute = BaseValue x RarityMult x MutationMult x this
	START_SLOTS = 3,
	MAX_SLOTS = 20,
	OFFLINE_CAP_SECONDS = 8 * 60 * 60,
	TICK_SECONDS = 5, -- how often online income is paid out
	-- Pedestal grid inside the Depot building (MapBuilder places them, the client fills them).
	ORIGIN = Vector3.new(-46, 0, 32), -- center of the Depot floor
	COLUMNS = 5,
	SPACING = 6,
}
