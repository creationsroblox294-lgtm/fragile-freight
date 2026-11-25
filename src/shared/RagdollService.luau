--!strict
-- Shared ragdoll joint swap (GDD §3.1). The server calls setup() once per character and
-- ragdoll()/unragdoll() to replicate to everyone; the owning client also calls them locally
-- so the fall starts on the same frame as the trip instead of one round trip later.
-- Humanoid state changes must happen on the owning client (see RagdollController).

local RagdollService = {}

-- UpperAngle per joint (degrees). Anything not listed uses DEFAULT_ANGLE.
local JOINT_ANGLES: { [string]: number } = {
	LeftKnee = 45,
	RightKnee = 45,
	LeftElbow = 45,
	RightElbow = 45,
	LeftShoulder = 70,
	RightShoulder = 70,
	LeftHip = 70,
	RightHip = 70,
	Neck = 30,
	Waist = 25,
	LeftWrist = 30,
	RightWrist = 30,
	LeftAnkle = 30,
	RightAnkle = 30,
}
local DEFAULT_ANGLE = 40
local TWIST_ANGLE = 25

local SOCKET_NAME = "RagdollSocket"

local function forEachMotor(character: Model, fn: (Motor6D) -> ())
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") and d.Name ~= "Root" then
			fn(d)
		end
	end
end

function RagdollService.setup(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false

	forEachMotor(character, function(motor)
		local part0, part1 = motor.Part0, motor.Part1
		if not part0 or not part1 or motor:FindFirstChild(SOCKET_NAME) then
			return
		end

		local a0 = Instance.new("Attachment")
		a0.Name = "Ragdoll" .. motor.Name .. "0"
		a0.CFrame = motor.C0
		a0.Parent = part0

		local a1 = Instance.new("Attachment")
		a1.Name = "Ragdoll" .. motor.Name .. "1"
		a1.CFrame = motor.C1
		a1.Parent = part1

		local socket = Instance.new("BallSocketConstraint")
		socket.Name = SOCKET_NAME
		socket.Attachment0 = a0
		socket.Attachment1 = a1
		socket.LimitsEnabled = true
		socket.UpperAngle = JOINT_ANGLES[motor.Name] or DEFAULT_ANGLE
		socket.TwistLimitsEnabled = true
		socket.TwistLowerAngle = -TWIST_ANGLE
		socket.TwistUpperAngle = TWIST_ANGLE
		socket.Enabled = false
		socket.Parent = motor

		-- Adjacent limbs overlap at the joint; without this they fight each other and jitter.
		local noCollide = Instance.new("NoCollisionConstraint")
		noCollide.Part0 = part0
		noCollide.Part1 = part1
		noCollide.Parent = socket
	end)
end

--[[
	Swap Motor6Ds for the ball sockets (limp = true) or back (limp = false).
	This only touches joints and collision. Who is "ragdolled" is game state: the server keeps
	it in the character's "Ragdolled" attribute (CharacterService) and the owning client keeps
	its own copy (RagdollController), so a local swap never fights a replicated attribute.
]]
function RagdollService.setLimp(character: Model, limp: boolean)
	forEachMotor(character, function(motor)
		local socket = motor:FindFirstChild(SOCKET_NAME) :: BallSocketConstraint?
		if socket then
			socket.Enabled = limp
			motor.Enabled = not limp
		end
	end)

	for _, d in character:GetChildren() do
		if d:IsA("BasePart") then
			if limp then
				-- R15 limbs don't collide while animated; they must while limp or they sink
				-- into the floor. The root stays non-colliding so it doesn't prop the body up.
				if d:GetAttribute("RagdollCanCollide") == nil then
					d:SetAttribute("RagdollCanCollide", d.CanCollide)
				end
				d.CanCollide = d.Name ~= "HumanoidRootPart"
			else
				local original = d:GetAttribute("RagdollCanCollide")
				if typeof(original) == "boolean" then
					d.CanCollide = original
				end
			end
		end
	end
end

return RagdollService
