-- Package spawn, carry constraints, network ownership and server-side damage (GDD §3.2, §3.3).
-- The carrier's client simulates the package (instant feel); the server samples its velocity
-- 20x/s and owns Condition. .Touched is never a damage source.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = require(Shared.Config.Packages)
local Tuning = require(Shared.Config.Tuning)
local Scoring = require(Shared.Scoring)
local Remotes = require(Shared.Remotes)
local CollisionGroups = require(script.Parent.CollisionGroups)

local PackageService = {}

export type Package = {
	id: string,
	def: Packages.PackageDef,
	model: Model,
	root: BasePart,
	owner: Player,
	mutationMultiplier: number,
	condition: number,
	broken: boolean,
	holder: Player?,
	rotated: boolean,

	-- carry constraints (present while held)
	grip: Attachment,
	holdPoint: Attachment?,
	alignPosition: AlignPosition?,
	alignOrientation: AlignOrientation?,
	farSince: number?,
	graceUntil: number,

	-- sampling
	lastVelocity: Vector3,
	lastPosition: Vector3,
	lastSample: number,
	lastConditionSent: number,
	lastConditionSentAt: number,
	maxSpeed: number,
	flag: string?, -- set when an anti-exploit check trips
}

-- Hooks set by OrderService.
PackageService.onSampled = function(_pkg: Package) end
PackageService.onBroken = function(_pkg: Package) end

local active: { [string]: Package } = {}
local packagesFolder: Folder

local HOLD_POINT_NAME = "HoldPoint"
local PICKUP_GRACE = 0.75 -- seconds without impact damage while the grip pulls the package in

local function densityFor(mass: number, size: Vector3): number
	return math.clamp(mass / (size.X * size.Y * size.Z), 0.01, 100)
end

local function buildModel(def: Packages.PackageDef): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = def.id

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = def.rootSize
	root.Transparency = 1
	root.RootPriority = 10
	root.CustomPhysicalProperties = PhysicalProperties.new(
		densityFor(def.mass * (1 - def.ballastFraction), def.rootSize),
		def.friction,
		def.elasticity
	)
	root.Parent = model
	model.PrimaryPart = root

	for _, spec in def.visual do
		local count = spec.count or 1
		local spacing = spec.spacing or 0
		for i = 1, count do
			local p = Instance.new("Part")
			p.Name = spec.name
			p.Shape = spec.shape or Enum.PartType.Block
			p.Size = spec.size
			p.Color = spec.color
			p.Material = spec.material or Enum.Material.SmoothPlastic
			p.Transparency = spec.transparency or 0
			p.CanCollide = false
			p.CanQuery = false
			p.Massless = true
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			local along = (i - (count + 1) / 2) * spacing
			local cf = root.CFrame * CFrame.new(spec.offset + Vector3.new(along, 0, 0))
			if p.Shape == Enum.PartType.Cylinder then
				cf *= CFrame.Angles(0, 0, math.pi / 2) -- cylinders run along X; stand them up
			end
			p.CFrame = cf
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = p
			weld.Parent = p
			p.Parent = model
		end
	end

	if def.ballastFraction > 0 then
		local ballast = Instance.new("Part")
		ballast.Name = "Ballast"
		ballast.Size = Vector3.new(0.5, 0.5, 0.5)
		ballast.Transparency = 1
		ballast.CanCollide = false
		ballast.CanQuery = false
		ballast.CanTouch = false
		ballast.CustomPhysicalProperties = PhysicalProperties.new(densityFor(def.mass * def.ballastFraction, ballast.Size))
		ballast.CFrame = root.CFrame * CFrame.new(def.comOffset)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = ballast
		weld.Parent = ballast
		ballast.Parent = model
	end

	return model, root
end

local function getRootPart(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function setWalkSpeed(player: Player, multiplier: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Tuning.BASE_WALK_SPEED * multiplier
	end
end

local function setPrompt(pkg: Package)
	local prompt = pkg.root:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = pkg.holder == nil and not pkg.broken
	end
end

local function holdCFrame(pkg: Package): CFrame
	local cf = CFrame.new(Tuning.HOLD_OFFSET)
	if pkg.rotated then
		cf *= CFrame.Angles(0, math.pi / 2, 0)
	end
	return cf
end

function PackageService.drop(pkg: Package)
	local holder = pkg.holder
	if not holder then
		return
	end
	pkg.holder = nil
	pkg.farSince = nil
	for _, key in { "alignPosition", "alignOrientation", "holdPoint" } do
		local inst = (pkg :: any)[key]
		if inst then
			inst:Destroy()
			;(pkg :: any)[key] = nil
		end
	end
	pkg.model:SetAttribute("Holder", nil)
	CollisionGroups.setModel(pkg.model, CollisionGroups.Package)
	if pkg.root:IsDescendantOf(workspace) then
		pkg.root:SetNetworkOwner(nil) -- nobody holds it: the server simulates it
	end
	setWalkSpeed(holder, 1)
	setPrompt(pkg)
	Remotes.get("CarryChanged"):FireClient(holder, nil)
end

function PackageService.pickup(pkg: Package, player: Player): boolean
	if pkg.broken or pkg.holder or player ~= pkg.owner or not pkg.root:IsDescendantOf(workspace) then
		return false
	end
	local hrp = getRootPart(player)
	if not hrp then
		return false
	end
	if (hrp.Position - pkg.root.Position).Magnitude > Tuning.PICKUP_RANGE + 2 then
		return false
	end
	-- Only one package in hand at a time.
	for _, other in active do
		if other.holder == player then
			return false
		end
	end

	local holdPoint = Instance.new("Attachment")
	holdPoint.Name = HOLD_POINT_NAME
	holdPoint.CFrame = holdCFrame(pkg)
	holdPoint.Parent = hrp

	local mass = pkg.root.AssemblyMass
	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Attachment0 = pkg.grip
	alignPosition.Attachment1 = holdPoint
	alignPosition.Responsiveness = Tuning.GRIP_RESPONSIVENESS
	alignPosition.MaxForce = mass * workspace.Gravity * Tuning.GRIP_FORCE_PER_MASS
	alignPosition.Parent = pkg.root

	-- Deliberately weak: tall items tip, which is the point.
	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Attachment0 = pkg.grip
	alignOrientation.Attachment1 = holdPoint
	alignOrientation.Responsiveness = pkg.def.orientationResponsiveness
	alignOrientation.MaxTorque = mass * pkg.def.orientationTorque
	alignOrientation.Parent = pkg.root

	pkg.holdPoint = holdPoint
	pkg.alignPosition = alignPosition
	pkg.alignOrientation = alignOrientation
	pkg.holder = player
	pkg.farSince = nil
	pkg.graceUntil = os.clock() + PICKUP_GRACE

	CollisionGroups.setModel(pkg.model, CollisionGroups.CarriedPackage)
	pkg.root:SetNetworkOwner(player)
	pkg.model:SetAttribute("Holder", player.UserId)
	setWalkSpeed(player, pkg.def.walkSpeedMultiplier)
	setPrompt(pkg)
	Remotes.get("CarryChanged"):FireClient(player, pkg.model)
	return true
end

function PackageService.rotate(pkg: Package)
	pkg.rotated = not pkg.rotated
	if pkg.holdPoint then
		pkg.holdPoint.CFrame = holdCFrame(pkg)
		pkg.graceUntil = os.clock() + PICKUP_GRACE
	end
end

function PackageService.spawn(owner: Player, packageId: string, cframe: CFrame, mutationMultiplier: number?): Package
	local def = Packages[packageId]
	assert(def, "Unknown package " .. packageId)
	local model, root = buildModel(def)

	local grip = Instance.new("Attachment")
	grip.Name = "Grip"
	grip.Parent = root

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick Up"
	prompt.ObjectText = def.displayName
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Tuning.PICKUP_RANGE
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = root

	model:PivotTo(cframe)
	model:SetAttribute("PackageId", def.id)
	model:SetAttribute("Owner", owner.UserId)
	CollisionGroups.setModel(model, CollisionGroups.Package)
	model.Parent = packagesFolder

	local pkg: Package = {
		id = HttpService:GenerateGUID(false),
		def = def,
		model = model,
		root = root,
		owner = owner,
		mutationMultiplier = mutationMultiplier or 1,
		condition = 100,
		broken = false,
		holder = nil,
		rotated = false,
		grip = grip,
		holdPoint = nil,
		alignPosition = nil,
		alignOrientation = nil,
		farSince = nil,
		graceUntil = os.clock() + PICKUP_GRACE,
		lastVelocity = Vector3.zero,
		lastPosition = root.Position,
		lastSample = os.clock(),
		lastConditionSent = 100,
		lastConditionSentAt = 0,
		maxSpeed = 0,
		flag = nil,
	}
	model:SetAttribute("Condition", 100)
	active[pkg.id] = pkg

	prompt.Triggered:Connect(function(player)
		PackageService.pickup(pkg, player)
	end)
	return pkg
end

function PackageService.destroy(pkg: Package)
	PackageService.drop(pkg)
	active[pkg.id] = nil
	pkg.model:Destroy()
end

local function breakApart(pkg: Package)
	pkg.broken = true
	PackageService.drop(pkg)
	active[pkg.id] = nil

	-- Break effect: pop the welds and scatter the pieces.
	local center = pkg.root.Position
	local burst = Instance.new("ParticleEmitter")
	burst.Rate = 0
	burst.Speed = NumberRange.new(10, 20)
	burst.Lifetime = NumberRange.new(0.4, 0.8)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Parent = pkg.root
	burst:Emit(40)

	for _, d in pkg.model:GetDescendants() do
		if d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
	for _, d in pkg.model:GetChildren() do
		if d:IsA("BasePart") and d ~= pkg.root and d.Name ~= "Ballast" then
			d.Massless = false
			d.CanCollide = true
			local dir = (d.Position - center)
			if dir.Magnitude < 0.1 then
				dir = Vector3.new(math.random() - 0.5, 1, math.random() - 0.5)
			end
			d.AssemblyLinearVelocity = dir.Unit * 25 + Vector3.new(0, 20, 0)
		end
	end
	pkg.root.CanCollide = false
	pkg.model:SetAttribute("Broken", true)
	Debris:AddItem(pkg.model, 4)

	PackageService.onBroken(pkg)
end

local function sendCondition(pkg: Package, force: boolean?)
	local now = os.clock()
	local rounded = math.floor(pkg.condition + 0.5)
	if not force and (rounded == pkg.lastConditionSent or now - pkg.lastConditionSentAt < 1 / Tuning.CONDITION_UPDATE_RATE) then
		return
	end
	pkg.lastConditionSent = rounded
	pkg.lastConditionSentAt = now
	pkg.model:SetAttribute("Condition", rounded)
	if pkg.owner.Parent then
		Remotes.get("ConditionUpdate"):FireClient(pkg.owner, rounded)
	end
end

local function sample(pkg: Package, now: number)
	local root = pkg.root
	local dt = now - pkg.lastSample
	if dt <= 0 then
		return
	end
	local velocity = root.AssemblyLinearVelocity
	local position = root.Position
	local inGrace = now < pkg.graceUntil

	-- Anti-exploit (GDD §3.3). These void the delivery rather than kick, so a wild physics
	-- fling during playtests shows up in the logs instead of punishing the tester.
	local speed = velocity.Magnitude
	pkg.maxSpeed = math.max(pkg.maxSpeed, speed)
	if not pkg.flag then
		if speed > Tuning.MAX_PACKAGE_SPEED then
			pkg.flag = string.format("speed %.0f", speed)
		elseif not inGrace and (position - pkg.lastPosition).Magnitude > Tuning.MAX_TELEPORT_DISTANCE then
			pkg.flag = string.format("teleport %.0f", (position - pkg.lastPosition).Magnitude)
		end
		if pkg.flag then
			warn(string.format("[PackageService] %s flagged: %s", pkg.owner.Name, pkg.flag))
		end
	end

	local damage = 0
	if not inGrace then
		local deltaV = Scoring.impactDeltaV(pkg.lastVelocity, velocity, dt, workspace.Gravity)
		damage += Scoring.impactDamage(deltaV, pkg.def.fragility, pkg.def.fragilityMultiplier, pkg.mutationMultiplier)
	end
	local tilt = Scoring.tiltAngle(root.CFrame.UpVector)
	damage += Scoring.tiltDamage(tilt, pkg.def.tiltLimit, pkg.def.tiltDamagePerSecond, dt)

	pkg.lastVelocity = velocity
	pkg.lastPosition = position
	pkg.lastSample = now

	if damage > 0 then
		pkg.condition = math.max(0, pkg.condition - damage)
		sendCondition(pkg)
	end

	if pkg.condition <= 0 or position.Y < Tuning.VOID_Y then
		pkg.condition = 0
		sendCondition(pkg, true)
		breakApart(pkg)
		return
	end

	-- Drop rule: grip error too large for too long (stuck on a pole, wedged in a door).
	if pkg.holder and (not pkg.holdPoint or not pkg.holdPoint:IsDescendantOf(workspace)) then
		PackageService.drop(pkg) -- carrier respawned; the hold point went with the old body
	elseif pkg.holder and pkg.holdPoint then
		local err = (pkg.holdPoint.WorldPosition - pkg.grip.WorldPosition).Magnitude
		if err > Tuning.DROP_DISTANCE then
			pkg.farSince = pkg.farSince or now
			if now - pkg.farSince >= Tuning.DROP_DISTANCE_TIME then
				PackageService.drop(pkg)
			end
		else
			pkg.farSince = nil
		end
	end

	PackageService.onSampled(pkg)
end

function PackageService.heldBy(player: Player): Package?
	for _, pkg in active do
		if pkg.holder == player then
			return pkg
		end
	end
	return nil
end

function PackageService.init()
	packagesFolder = Instance.new("Folder")
	packagesFolder.Name = "Packages"
	packagesFolder.Parent = workspace

	Remotes.get("RequestDrop").OnServerEvent:Connect(function(player)
		local pkg = PackageService.heldBy(player)
		if pkg then
			PackageService.drop(pkg)
		end
	end)
	Remotes.get("RequestRotate").OnServerEvent:Connect(function(player)
		local pkg = PackageService.heldBy(player)
		if pkg then
			PackageService.rotate(pkg)
		end
	end)

	local interval = 1 / Tuning.SAMPLE_RATE
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < interval then
			return
		end
		acc = 0
		local now = os.clock()
		for _, pkg in active do
			if pkg.root.Parent and not pkg.broken then
				sample(pkg, now)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		for _, pkg in active do
			if pkg.owner == player then
				PackageService.destroy(pkg)
			elseif pkg.holder == player then
				PackageService.drop(pkg)
			end
		end
	end)
end

return PackageService
