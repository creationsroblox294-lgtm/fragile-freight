-- Sends the client a read-only snapshot of saved state (Index, Depot, odds UI).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)
local DataService = require(script.Parent.DataService)
local GachaService = require(script.Parent.GachaService)

local ProfileSync = {}

function ProfileSync.send(player: Player)
	local profile = DataService.get(player)
	if not profile or not player.Parent then
		return
	end
	Remotes.get("ProfileSync"):FireClient(player, {
		coins = profile.coins,
		lifetimeTips = profile.lifetimeTips,
		deliveries = profile.deliveries,
		index = profile.index,
		depot = profile.depot,
		pity = profile.pity,
		luck = GachaService.getLuck(player),
	})
end

return ProfileSync
