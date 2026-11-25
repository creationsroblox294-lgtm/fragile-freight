-- Builds the M0 gray-box street from code so the whole level lives in Git (GDD §8, M0).
-- Street runs from the depot (z = +30) toward -Z. Road in the middle, sidewalks with curbs on
-- both sides, three customers at increasing distance, and a handful of hazards.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Depot = require(Shared.Config.Depot)
local DepotMath = require(Shared.DepotMath)

local MapBuilder = {}

export type Destination = { name: string, zone: BasePart, color: Color3 }
export type Map = {
	dispatchBoard: BasePart,
	destinations: { Destination },
}

local GRAY = Color3.fromRGB(150, 150, 155)
local DARK = Color3.fromRGB(55, 55, 60)
local GRASS = Color3.fromRGB(95, 160, 80)

local mapFolder: Folder

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.Color = GRAY
	for k, v in props do
		(p :: any)[k] = v
	end
	if not props.Parent then
		p.Parent = mapFolder
	end
	return p
end

local function label(adornee: BasePart, text: string, color: Color3?)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 50)
	gui.StudsOffset = Vector3.new(0, adornee.Size.Y / 2 + 3, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 250
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.TextColor3 = color or Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.3
	t.Parent = gui
	gui.Parent = adornee
end

local function dropZone(name: string, position: Vector3, color: Color3): Destination
	local zone = part({
		Name = name .. "Zone",
		Size = Vector3.new(10, 6, 10),
		Position = position,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		Transparency = 0.85,
		Color = color,
		Material = Enum.Material.Neon,
	})
	zone:SetAttribute("DestinationName", name)
	label(zone, name, color)
	return { name = name, zone = zone, color = color }
end

local function buildStreet()
	part({ Name = "Ground", Size = Vector3.new(140, 2, 490), Position = Vector3.new(0, -1, -195), Color = GRASS, Material = Enum.Material.Grass })
	part({ Name = "Road", Size = Vector3.new(24, 0.2, 470), Position = Vector3.new(0, 0.1, -195), Color = DARK })
	for _, side in { -1, 1 } do
		-- 0.8-stud curb: the humanoid steps it, packages feel it
		part({ Name = "Sidewalk", Size = Vector3.new(8, 0.8, 470), Position = Vector3.new(16 * side, 0.4, -195) })
		for z = -20, -400, -30 do
			part({ Name = "LampPost", Size = Vector3.new(0.8, 12, 0.8), Position = Vector3.new(13.2 * side, 6.8, z), Color = DARK })
			part({ Name = "LampHead", Size = Vector3.new(2, 0.8, 2), Position = Vector3.new(13.2 * side, 13, z), Color = Color3.fromRGB(255, 240, 180), Material = Enum.Material.Neon })
		end
	end
	-- Speed bumps across the road
	for _, z in { -70, -260 } do
		part({ Name = "SpeedBump", Shape = Enum.PartType.Cylinder, Size = Vector3.new(24, 1.4, 1.4), Position = Vector3.new(0, 0.15, z), Color = Color3.fromRGB(230, 200, 40) })
	end
end

local function buildDepot(): BasePart
	part({ Name = "DepotFloor", Size = Vector3.new(40, 0.4, 24), Position = Vector3.new(0, 0.2, 32), Color = Color3.fromRGB(200, 170, 120) })
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.Position = Vector3.new(0, 0.6, 38)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(255, 170, 60)
	spawn.Parent = mapFolder

	local board = part({
		Name = "DispatchBoard",
		Size = Vector3.new(10, 7, 1),
		Position = Vector3.new(0, 3.9, 26),
		Color = Color3.fromRGB(40, 90, 160),
	})
	-- Players spawn on the +Z side looking toward -Z, so they see the board's Back face.
	for _, face in { Enum.NormalId.Back, Enum.NormalId.Front } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(400, 280)
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Text = "FRAGILE FREIGHT\nDISPATCH"
		t.TextScaled = true
		t.Font = Enum.Font.FredokaOne
		t.TextColor3 = Color3.new(1, 1, 1)
		t.Parent = gui
		gui.Parent = board
	end
	return board
end

-- Depot (GDD §5.2): open-fronted hall with a pedestal grid. Shared by everyone; each client
-- draws its own displayed packages on the pedestals.
local function buildDepotHall()
	local o = Depot.ORIGIN
	local width, depth, height = 34, 30, 14
	local wall = Color3.fromRGB(235, 225, 205)
	local folder = Instance.new("Folder")
	folder.Name = "Depot"
	folder.Parent = mapFolder

	part({ Name = "DepotFloor", Size = Vector3.new(width, 0.4, depth), Position = o + Vector3.new(0, 0.2, 0), Color = Color3.fromRGB(120, 100, 85), Material = Enum.Material.WoodPlanks, Parent = folder })
	part({ Name = "DepotBack", Size = Vector3.new(1, height, depth), Position = o + Vector3.new(-width / 2, height / 2, 0), Color = wall, Parent = folder })
	for _, side in { -1, 1 } do
		part({ Name = "DepotSide", Size = Vector3.new(width, height, 1), Position = o + Vector3.new(0, height / 2, side * depth / 2), Color = wall, Parent = folder })
	end
	part({ Name = "DepotRoof", Size = Vector3.new(width + 2, 1, depth + 2), Position = o + Vector3.new(0, height + 0.5, 0), Color = Color3.fromRGB(70, 110, 170), Parent = folder })

	local sign = part({ Name = "DepotSign", Size = Vector3.new(1, 4, 20), Position = o + Vector3.new(width / 2, height - 2, 0), Color = Color3.fromRGB(40, 90, 160), Parent = folder })
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Right
	gui.CanvasSize = Vector2.new(500, 100)
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = "MY DEPOT"
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.TextColor3 = Color3.new(1, 1, 1)
	t.Parent = gui
	gui.Parent = sign

	for i = 1, Depot.MAX_SLOTS do
		local pos = DepotMath.pedestalPosition(i)
		local pedestal = part({
			Name = "Pedestal_" .. i,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.2, 3.6, 3.6),
			CFrame = CFrame.new(pos + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = Color3.fromRGB(215, 215, 225),
			Material = Enum.Material.Marble,
			Parent = folder,
		})
		pedestal:SetAttribute("Slot", i)
	end
end

local function buildBlueHouse(): Destination
	local color = Color3.fromRGB(80, 140, 255)
	part({ Name = "BlueHouse", Size = Vector3.new(20, 12, 16), Position = Vector3.new(46, 6, -110), Color = color })
	return dropZone("Blue House", Vector3.new(30, 3, -110), color)
end

-- Enclosed shop with a 7-stud doorway: the 11-stud ladder has to be turned to fit.
local function buildBakery(): Destination
	local color = Color3.fromRGB(240, 150, 90)
	local x0, x1 = -56, -36 -- back wall x, front wall x
	local zc, depth, height, door = -205, 24, 12, 7
	part({ Name = "BakeryBack", Size = Vector3.new(1, height, depth), Position = Vector3.new(x0, height / 2, zc), Color = color })
	for _, side in { -1, 1 } do
		part({ Name = "BakerySide", Size = Vector3.new(x1 - x0, height, 1), Position = Vector3.new((x0 + x1) / 2, height / 2, zc + side * depth / 2), Color = color })
		local wallLen = (depth - door) / 2
		part({ Name = "BakeryFront", Size = Vector3.new(1, height, wallLen), Position = Vector3.new(x1, height / 2, zc + side * (door / 2 + wallLen / 2)), Color = color })
	end
	part({ Name = "BakeryLintel", Size = Vector3.new(1, height - 8, door), Position = Vector3.new(x1, 8 + (height - 8) / 2, zc), Color = color })
	part({ Name = "BakeryRoof", Size = Vector3.new(x1 - x0 + 2, 1, depth + 2), Position = Vector3.new((x0 + x1) / 2, height + 0.5, zc), Color = Color3.fromRGB(150, 70, 50) })
	return dropZone("Bakery", Vector3.new(-46, 3, zc), color)
end

-- Raised porch with stairs: tilt test for the fish tank.
local function buildPetShop(): Destination
	local color = Color3.fromRGB(170, 100, 220)
	local z = -320
	for i = 0, 4 do
		local h = (i + 1) * 0.8
		part({ Name = "Step", Size = Vector3.new(1.4, h, 10), Position = Vector3.new(21.7 + i * 1.4, h / 2, z) })
	end
	part({ Name = "Porch", Size = Vector3.new(16, 4, 16), Position = Vector3.new(36, 2, z), Color = Color3.fromRGB(160, 120, 80), Material = Enum.Material.WoodPlanks })
	part({ Name = "PetShop", Size = Vector3.new(16, 16, 20), Position = Vector3.new(52, 8, z), Color = color })
	return dropZone("Pet Shop", Vector3.new(37, 7, z), color)
end

type Hazard = { part: BasePart, impulse: (BasePart, Vector3) -> Vector3 }

local function buildHazards(): { Hazard }
	local hazards = {}

	-- Sweeper: spinning bar across the road. Sidewalks are the safe (but pole-filled) route.
	local sweeperCenter = Vector3.new(0, 1.6, -150)
	part({ Name = "SweeperPole", Size = Vector3.new(1.2, 3.2, 1.2), Position = sweeperCenter, Color = DARK })
	local bar = part({ Name = "SweeperBar", Size = Vector3.new(22, 1.2, 1.2), Position = sweeperCenter, Color = Color3.fromRGB(220, 50, 50) })
	local sweeperSpeed = 1.4 -- rad/s
	table.insert(hazards, {
		part = bar,
		impulse = function(_, pos)
			local offset = pos - sweeperCenter
			local tangent = Vector3.yAxis:Cross(offset)
			if tangent.Magnitude < 1e-3 then
				tangent = Vector3.xAxis
			end
			return tangent.Unit * 55 + Vector3.new(0, 35, 0)
		end,
	})

	-- Crossing car: slides across the whole street, sidewalks included.
	local car = part({ Name = "Car", Size = Vector3.new(10, 4, 6), Position = Vector3.new(-30, 2.3, -235), Color = Color3.fromRGB(240, 220, 60) })
	local carSpeed, carRange = 18, 30
	local carDir = 1
	table.insert(hazards, {
		part = car,
		impulse = function()
			return Vector3.new(carDir * 70, 40, 0)
		end,
	})

	-- Kinematic motion: move by CFrame AND set the assembly velocity, so the physics solver
	-- treats these anchored parts as moving and actually shoves whatever they hit.
	RunService.Heartbeat:Connect(function(dt)
		bar.CFrame = bar.CFrame * CFrame.Angles(0, sweeperSpeed * dt, 0)
		bar.AssemblyAngularVelocity = Vector3.new(0, sweeperSpeed, 0)

		local x = car.Position.X + carDir * carSpeed * dt
		if math.abs(x) > carRange then
			carDir = -carDir
			x = math.clamp(x, -carRange, carRange)
		end
		car.Position = Vector3.new(x, car.Position.Y, car.Position.Z)
		car.AssemblyLinearVelocity = Vector3.new(carDir * carSpeed, 0, 0)
	end)

	return hazards
end

-- onHit(player, impulse) is called at most 20x/s per hazard overlap; the receiver debounces.
local function watchHazards(hazards: { Hazard }, onHit: (Player, Vector3) -> ())
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.05 then
			return
		end
		acc = 0
		local characters = {}
		for _, player in Players:GetPlayers() do
			if player.Character then
				table.insert(characters, player.Character)
			end
		end
		if #characters == 0 then
			return
		end
		params.FilterDescendantsInstances = characters
		for _, hazard in hazards do
			local hitPlayers = {}
			for _, hit in workspace:GetPartsInPart(hazard.part, params) do
				local player = Players:GetPlayerFromCharacter(hit.Parent)
				if player and not hitPlayers[player] then
					hitPlayers[player] = true
					onHit(player, hazard.impulse(hazard.part, hit.Position))
				end
			end
		end
	end)
end

function MapBuilder.build(onHazardHit: (Player, Vector3) -> ()): Map
	local existing = workspace:FindFirstChild("Map")
	if existing then
		existing:Destroy()
	end
	mapFolder = Instance.new("Folder")
	mapFolder.Name = "Map"
	mapFolder.Parent = workspace

	buildStreet()
	local board = buildDepot()
	buildDepotHall()
	local destinations = { buildBlueHouse(), buildBakery(), buildPetShop() }
	watchHazards(buildHazards(), onHazardHit)

	return { dispatchBoard = board, destinations = destinations }
end

return MapBuilder
