--!strict
-- Single place that names every remote (GDD §6.2). The server creates them; clients wait for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	-- client -> server
	"RequestDrop", -- ()
	"RequestRagdoll", -- (reason: string) client detected a trip on its own character
	"RequestGetUp", -- ()
	"RequestRotate", -- () turn the carried package 90 degrees (fit ladders through doors)
	"RequestDisplay", -- () put your last delivered package on a Depot pedestal (replaces the weakest if full)
	"RequestRemoveDisplay", -- (slot: number) take an item off a pedestal
	-- server -> client
	"OrderRolled", -- (order: {packageId, displayName, destinationName, destination: BasePart, parTime})
	"ConditionUpdate", -- (condition: number, lastHit: {deltaV, damage, source, hit}?)
	"DeliveryResult", -- (result: {...})
	"ForceRagdoll", -- (impulse: Vector3) a hazard hit you; the client applies the fling
	"CarryChanged", -- (package: Model?) you picked up / lost the package
	"OrderRevealing", -- (reveal: {rarity, mutation, packageId, displayName, pityUsed}) crate-open starts
	"Announcement", -- (text: string, color: Color3) server-wide banner
	"OfflineEarnings", -- (coins: number, seconds: number) "While you were gone"
	"ProfileSync", -- (snapshot) coins, tips, index, depot, pity, luck — for Index/Depot/odds UI
}

local FOLDER_NAME = "Remotes"

local Remotes = {}

local folder: Folder
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing then
		folder = existing :: Folder
	else
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for _, name in EVENTS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

function Remotes.get(name: string): RemoteEvent
	assert(table.find(EVENTS, name), "Unknown remote: " .. name)
	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
