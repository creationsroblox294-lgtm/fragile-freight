-- Collision groups. A carried package must not collide with its carrier's body, or it shoves
-- them around; a dropped package collides with everything, so you can kick it (comedy).

local PhysicsService = game:GetService("PhysicsService")

local CollisionGroups = {
	Characters = "Characters",
	CarriedPackage = "CarriedPackage",
	Package = "Package",
}

function CollisionGroups.init()
	for _, name in { CollisionGroups.Characters, CollisionGroups.CarriedPackage, CollisionGroups.Package } do
		PhysicsService:RegisterCollisionGroup(name)
	end
	PhysicsService:CollisionGroupSetCollidable(CollisionGroups.Characters, CollisionGroups.CarriedPackage, false)
end

function CollisionGroups.setModel(model: Instance, group: string)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = group
		end
	end
	if model:IsA("BasePart") then
		model.CollisionGroup = group
	end
end

return CollisionGroups
