--!strict
-- Saved data schema (GDD §6.3) and DataStore settings.

local DataConfig = {}

DataConfig.STORE_NAME = "PlayerData_v1"
DataConfig.VERSION = 1
DataConfig.AUTOSAVE_INTERVAL = 120 -- seconds
DataConfig.LOCK_STALE_AFTER = 10 * 60 -- seconds; a lock older than this is from a dead server
DataConfig.LOAD_ATTEMPTS = 6 -- tries while another server still holds the lock
DataConfig.LOCK_WAIT = 4 -- seconds between those tries
DataConfig.RETRIES = 5 -- DataStore call retries (exponential backoff)

-- Fresh data for a new player. Never mutate this table; DataService deep-copies it.
DataConfig.TEMPLATE = {
	version = 1,
	coins = 0,
	lifetimeTips = 0,
	deliveries = 0,
	upgrades = { grip = 0, balance = 0, sneakers = 0, luckyHat = 0, handTruck = false },
	districts = { suburbs = true },
	index = {} :: { [string]: number }, -- indexKey -> times delivered
	depot = {
		slots = 3,
		displayed = {} :: { { id: string, rarity: string, mutation: string } },
	},
	pity = 0,
	lastOnline = 0,
}

return DataConfig
