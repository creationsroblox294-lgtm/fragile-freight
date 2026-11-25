-- Character setup and the server side of ragdolling (GDD §3.1).
-- The owning client detects trips on its own character (it simulates it, so it sees impacts
-- first) and asks to ragdoll. Hazards ragdoll from the server. Either way the server swaps
-- joints so everyone sees the same fall, and drops whatever the player was carrying.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RagdollService = require(Shared.RagdollService)
local Remotes = require(Shared.Remotes)
local Tuning = require(Shared.Config.Tuning)
local CollisionGroups = require(script.Parent.CollisionGroups)

local CharacterService = {}

-- Set by init.server: called whenever a player goes limp.
CharacterService.onRagdolled = function(_player: Player) end

type State = { ragdolledAt: number?, endedAt: number, token: number }
local states: { [Player]: State } = {}

local function getState(player: Player): State
	local s = states[player]
	if not s then
		s = { ragdolledAt = nil, endedAt = 0, token = 0 }
		states[player] = s
	end
	return s
end

function CharacterService.isRagdolled(player: Player): boolean
	return getState(player).ragdolledAt ~= nil
end

local function getUp(player: Player)
	local s = getState(player)
	if not s.ragdolledAt then
		return
	end
	s.ragdolledAt = nil
	s.endedAt = os.clock()
	local character = player.Character
	if character then
		RagdollService.setLimp(character, false)
		character:SetAttribute("Ragdolled", false)
	end
end

-- Returns false if the player is already down or still in post-get-up immunity.
local function ragdoll(player: Player): boolean
	local character = player.Character
	local s = getState(player)
	if not character or s.ragdolledAt or os.clock() - s.endedAt < Tuning.RAGDOLL_COOLDOWN then
		return false
	end
	s.ragdolledAt = os.clock()
	s.token += 1
	RagdollService.setLimp(character, true)
	character:SetAttribute("Ragdolled", true)
	CharacterService.onRagdolled(player)

	-- Safety net: the client normally gets up on its own timer; never leave someone limp
	-- forever if that message is lost.
	local token = s.token
	task.delay(Tuning.RAGDOLL_TIME + 1.5, function()
		if s.token == token then
			getUp(player)
		end
	end)
	return true
end

function CharacterService.hazardHit(player: Player, impulse: Vector3)
	if ragdoll(player) then
		Remotes.get("ForceRagdoll"):FireClient(player, impulse)
	end
end

local function onCharacterAdded(player: Player, character: Model)
	getUp(player)
	states[player] = nil
	character:WaitForChild("Humanoid")
	RagdollService.setup(character)
	CollisionGroups.setModel(character, CollisionGroups.Characters)
	character.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = CollisionGroups.Characters
		end
	end)
end

function CharacterService.init()
	Remotes.get("RequestRagdoll").OnServerEvent:Connect(function(player)
		ragdoll(player)
	end)
	Remotes.get("RequestGetUp").OnServerEvent:Connect(function(player)
		local s = getState(player)
		if s.ragdolledAt and os.clock() - s.ragdolledAt >= Tuning.RAGDOLL_MIN_TIME then
			getUp(player)
		end
	end)

	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			onCharacterAdded(player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

return CharacterService
