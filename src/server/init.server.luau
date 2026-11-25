-- Server entry point. Rule (GDD §6): the server decides everything that pays.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
require(ReplicatedStorage:WaitForChild("Shared").Remotes) -- create remotes before anyone waits on them

local CollisionGroups = require(script.CollisionGroups)
local MapBuilder = require(script.MapBuilder)
local CharacterService = require(script.CharacterService)
local PackageService = require(script.PackageService)
local DataService = require(script.DataService)
local OrderService = require(script.OrderService)

CollisionGroups.init()
DataService.init()
PackageService.init()
CharacterService.init()

-- Tripping drops whatever you're holding (GDD §3.2 drop rules; Sticky mutation is M1).
CharacterService.onRagdolled = function(player)
	local pkg = PackageService.heldBy(player)
	if pkg then
		PackageService.drop(pkg)
	end
end

local map = MapBuilder.build(CharacterService.hazardHit)
OrderService.init(map)

print("[FragileFreight] server ready")
