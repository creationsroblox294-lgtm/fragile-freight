-- Client side of ragdolling (GDD §3.1). Detects trips on the local character (the client
-- simulates it, so it sees impacts first), owns the Humanoid state change, and handles Get Up.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RagdollService = require(Shared.RagdollService)
local Remotes = require(Shared.Remotes)
local Tuning = require(Shared.Config.Tuning)

local RagdollController = {}

-- Set by init.client.
RagdollController.onChanged = function(_ragdolled: boolean) end

local player = Players.LocalPlayer
local ragdolled = false
local ragdolledAt = 0
local endedAt = 0
local token = 0

local function getParts(): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	return character, character:FindFirstChildOfClass("Humanoid"), character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function enter(impulse: Vector3?)
	local character, humanoid, root = getParts()
	if ragdolled or not character or not humanoid then
		return
	end
	ragdolled = true
	ragdolledAt = os.clock()
	token += 1
	RagdollService.setLimp(character, true)
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	if impulse and root then
		root:ApplyImpulse(impulse * root.AssemblyMass)
	end
	RagdollController.onChanged(true)

	local myToken = token
	task.delay(Tuning.RAGDOLL_TIME, function()
		if token == myToken then
			RagdollController.getUp()
		end
	end)
end

local function leave(tellServer: boolean)
	local character, humanoid = getParts()
	if not ragdolled then
		return
	end
	ragdolled = false
	endedAt = os.clock()
	token += 1
	if character and humanoid then
		RagdollService.setLimp(character, false)
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	if tellServer then
		Remotes.get("RequestGetUp"):FireServer()
	end
	RagdollController.onChanged(false)
end

function RagdollController.isRagdolled(): boolean
	return ragdolled
end

function RagdollController.trip(reason: string)
	if ragdolled or os.clock() - endedAt < Tuning.RAGDOLL_COOLDOWN then
		return
	end
	enter(nil)
	Remotes.get("RequestRagdoll"):FireServer(reason)
end

function RagdollController.getUp()
	if ragdolled and os.clock() - ragdolledAt >= Tuning.RAGDOLL_MIN_TIME then
		leave(true)
	end
end

local function watchCharacter(character: Model)
	ragdolled = false
	token += 1
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart

	-- Fall trips: track the highest point of each airborne stretch.
	local peakY: number? = nil
	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Freefall then
			peakY = root.Position.Y
		elseif new == Enum.HumanoidStateType.Landed and peakY then
			local fell = peakY - root.Position.Y
			peakY = nil
			if fell > Tuning.TRIP_FALL_HEIGHT then
				RagdollController.trip("fall")
			end
		end
	end)

	-- The server can end a ragdoll (safety timeout) or start one we didn't (hazard).
	character:GetAttributeChangedSignal("Ragdolled"):Connect(function()
		if character:GetAttribute("Ragdolled") == false and ragdolled then
			leave(false)
		end
	end)

	-- Impact trips. A frame's horizontal velocity change only counts when the new velocity
	-- is also far from what the Humanoid is steering toward, so snapping from full speed
	-- forward to full speed backward (which the Humanoid does on its own) never trips you.
	local lastH = Vector3.zero
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not character.Parent then
			conn:Disconnect()
			return
		end
		local v = root.AssemblyLinearVelocity
		if peakY then
			peakY = math.max(peakY, root.Position.Y)
		end
		local h = Vector3.new(v.X, 0, v.Z)
		if not ragdolled then
			local target = humanoid.MoveDirection * humanoid.WalkSpeed
			local change = (h - lastH).Magnitude
			local deviation = (h - Vector3.new(target.X, 0, target.Z)).Magnitude
			if change > Tuning.TRIP_IMPACT_SPEED and deviation > Tuning.TRIP_IMPACT_SPEED then
				RagdollController.trip("impact")
			end
		end
		lastH = h
	end)
end

function RagdollController.init()
	Remotes.get("ForceRagdoll").OnClientEvent:Connect(function(impulse: Vector3)
		enter(impulse)
	end)
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
end

return RagdollController
