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
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
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
	rarity: string,
	mutation: string,
	damageMultiplier: number, -- rarity fragility x mutation (Glass = x2)
	nextHauntAt: number,
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

	-- contact gate + damage telemetry
	lastContactAt: number,
	impactDamageTotal: number,
	tiltDamageTotal: number,
	hits: number,
	lastHit: { deltaV: number, damage: number, source: string, hit: string }?,
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

local function buildModel(def: Packages.PackageDef, mutation: Mutations.MutationDef): (Model, BasePart)
	local mass = def.mass * mutation.massMultiplier
	local model = Instance.new("Model")
	model.Name = def.id

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = def.rootSize
	root.Transparency = 1
	root.RootPriority = 10
	root.CustomPhysicalProperties = PhysicalProperties.new(
		densityFor(mass * (1 - def.ballastFraction), def.rootSize),
		def.friction,
		mutation.elasticity or def.elasticity,
		1,
		if mutation.elasticity then 100 else 1 -- Bouncy wins every contact
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
			p.Color = mutation.tint or spec.color
			p.Material = mutation.material or spec.material or Enum.Material.SmoothPlastic
			p.Transparency = spec.transparency or 0
			if mutation.id == "Glass" then
				p.Transparency = math.max(p.Transparency, 0.35)
			end
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
		ballast.CustomPhysicalProperties = PhysicalProperties.new(densityFor(mass * def.ballastFraction, ballast.Size))
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

export type SpawnOptions = { rarity: string?, mutation: string? }

function PackageService.spawn(owner: Player, packageId: string, cframe: CFrame, options: SpawnOptions?): Package
	local def = Packages[packageId]
	local rarity = Rarities.byId[options and options.rarity or "Common"] or Rarities.byId.Common
	local mutation = Mutations.byId[options and options.mutation or "None"] or Mutations.byId.None
	assert(def, "Unknown package " .. packageId)
	local model, root = buildModel(def, mutation)

	if mutation.haunted then
		-- Ghostly float: cancel part of gravity on the whole assembly.
		local floatAttachment = Instance.new("Attachment")
		floatAttachment.Name = "Float"
		floatAttachment.Parent = root
		local float = Instance.new("VectorForce")
		float.Attachment0 = floatAttachment
		float.RelativeTo = Enum.ActuatorRelativeTo.World
		float.ApplyAtCenterOfMass = true
		float.Parent = root
		task.defer(function()
			float.Force = Vector3.new(0, root.AssemblyMass * workspace.Gravity * Mutations.HAUNTED_FLOAT, 0)
		end)
	end

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
	model:SetAttribute("Rarity", rarity.id)
	model:SetAttribute("Mutation", mutation.id)
	model:SetAttribute("Owner", owner.UserId)
	CollisionGroups.setModel(model, CollisionGroups.Package)
	model.Parent = packagesFolder

	local pkg: Package = {
		id = HttpService:GenerateGUID(false),
		def = def,
		model = model,
		root = root,
		owner = owner,
		rarity = rarity.id,
		mutation = mutation.id,
		damageMultiplier = rarity.fragilityMultiplier * mutation.damageMultiplier,
		nextHauntAt = os.clock() + 2,
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
		lastContactAt = 0,
		impactDamageTotal = 0,
		tiltDamageTotal = 0,
		hits = 0,
		lastHit = nil,
	}
	model:SetAttribute("Condition", 100)
	active[pkg.id] = pkg

	prompt.Triggered:Connect(function(player)
		PackageService.pickup(pkg, player)
	end)
	-- Touched only feeds the contact gate (see touchingSomething); it never deals damage itself.
	root.Touched:Connect(function(other)
		if not other:IsDescendantOf(model) then
			pkg.lastContactAt = os.clock()
		end
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

--[[
	Impact damage only counts while the package is touching something. Walking, stopping and
	turning yank the package around through the grip, which looks like an impact to a pure
	delta-v check (the M0 playtest cake broke in 5.7 s that way). A real hit always comes with
	contact: a pole, a wall, the ground after a drop. The carrier's own body can't count, since
	carried packages don't collide with characters at all.
]]
local contactParams = OverlapParams.new()
contactParams.FilterType = Enum.RaycastFilterType.Exclude
contactParams.RespectCanCollide = true

local function touchingSomething(pkg: Package, now: number): (boolean, string)
	if now - pkg.lastContactAt <= Tuning.CONTACT_WINDOW then
		return true, "touch"
	end
	local exclude: { Instance } = { pkg.model }
	if pkg.holder and pkg.holder.Character then
		table.insert(exclude, pkg.holder.Character)
	end
	contactParams.FilterDescendantsInstances = exclude
	local pad = Vector3.one * Tuning.CONTACT_PADDING
	local parts = workspace:GetPartBoundsInBox(pkg.root.CFrame, pkg.root.Size + pad, contactParams)
	if #parts > 0 then
		return true, parts[1].Name
	end
	return false, ""
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
		Remotes.get("ConditionUpdate"):FireClient(pkg.owner, rounded, pkg.lastHit)
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
		if deltaV > pkg.def.fragility then
			local touching, hitName = touchingSomething(pkg, now)
			if touching then
				local impact = Scoring.impactDamage(deltaV, pkg.def.fragility, pkg.def.fragilityMultiplier, pkg.damageMultiplier)
				damage += impact
				pkg.impactDamageTotal += impact
				pkg.hits += 1
				pkg.lastHit = { deltaV = deltaV, damage = impact, source = "impact", hit = hitName }
			end
		end
	end
	local tilt = Scoring.tiltAngle(root.CFrame.UpVector)
	local tiltDamage = Scoring.tiltDamage(tilt, pkg.def.tiltLimit, pkg.def.tiltDamagePerSecond, dt) * pkg.damageMultiplier
	if tiltDamage > 0 then
		damage += tiltDamage
		pkg.tiltDamageTotal += tiltDamage
		pkg.lastHit = { deltaV = tilt, damage = tiltDamage, source = "tilt", hit = "" }
	end

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

	if pkg.mutation == "Haunted" and not pkg.holder and now >= pkg.nextHauntAt then
		local range = Mutations.HAUNTED_INTERVAL
		pkg.nextHauntAt = now + range[1] + math.random() * (range[2] - range[1])
		local dir = Vector3.new(math.random() - 0.5, 0.6, math.random() - 0.5).Unit
		root:ApplyImpulse(dir * Mutations.HAUNTED_IMPULSE * root.AssemblyMass)
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
