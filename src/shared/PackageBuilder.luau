--!nonstrict
-- Builds a package model from its data (Config/Packages + a mutation). Shared so the server
-- spawns real packages and the client can show identical copies on Depot pedestals.

local Packages = require(script.Parent.Config.Packages)
local Mutations = require(script.Parent.Config.Mutations)

local PackageBuilder = {}

local function densityFor(mass: number, size: Vector3): number
	return math.clamp(mass / (size.X * size.Y * size.Z), 0.01, 100)
end

function PackageBuilder.build(def: Packages.PackageDef, mutation: Mutations.MutationDef): (Model, BasePart)
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

-- Anchored, non-colliding copy for displays.
function PackageBuilder.buildDisplay(def: Packages.PackageDef, mutation: Mutations.MutationDef): (Model, BasePart)
	local model, root = PackageBuilder.build(def, mutation)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
	return model, root
end

return PackageBuilder
