-- Latest ProfileSync snapshot from the server, with change listeners. Read-only mirror.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)

local ProfileCache = {}

ProfileCache.data = nil :: { [string]: any }?
local listeners: { (any) -> () } = {}

function ProfileCache.onChanged(fn: (any) -> ())
	table.insert(listeners, fn)
	if ProfileCache.data then
		task.spawn(fn, ProfileCache.data)
	end
end

function ProfileCache.init()
	Remotes.get("ProfileSync").OnClientEvent:Connect(function(snapshot)
		ProfileCache.data = snapshot
		for _, fn in listeners do
			task.spawn(fn, snapshot)
		end
	end)
end

return ProfileCache
