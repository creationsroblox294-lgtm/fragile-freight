-- Server side of the luck layer (GDD §4). All rolls happen here with a server Random; the
-- client only ever sees results. Pity lives in the player's saved profile.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gacha = require(Shared.Gacha)
local DataService = require(script.Parent.DataService)

local GachaService = {}

local rng = Random.new()
local serverLuck = 0 -- Server Rush Hour (M3)

export type OrderRoll = { rarity: string, mutation: string, pityUsed: boolean }

-- Luck = upgrades + passes + server boost (GDD §4.1). Upgrades/passes arrive in M2/M3; the
-- "LuckBonus" attribute is the hook for them and for playtest tuning.
function GachaService.getLuck(player: Player): number
	local bonus = player:GetAttribute("LuckBonus")
	return serverLuck + (if type(bonus) == "number" then bonus else 0)
end

function GachaService.rollOrder(player: Player): OrderRoll
	local profile = DataService.get(player)
	local pity = if profile then profile.pity else 0
	local rarity, newPity, pityUsed = Gacha.rollRarity(rng, GachaService.getLuck(player), pity)
	if profile then
		profile.pity = newPity
	end
	return { rarity = rarity, mutation = Gacha.rollMutation(rng), pityUsed = pityUsed }
end

function GachaService.rollTip(condition: number): string
	return Gacha.rollTip(rng, condition)
end

function GachaService.setServerLuck(luck: number)
	serverLuck = math.max(0, luck)
	for _, p in Players:GetPlayers() do
		p:SetAttribute("ServerLuck", serverLuck)
	end
end

return GachaService
