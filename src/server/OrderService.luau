-- Dispatch board and the order lifecycle (GDD §2 steps 1-4).
-- M0: package and destination are picked at random; rarity/mutation/tip rolls arrive with
-- GachaService in M1 (the multipliers are already threaded through as 1).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = require(Shared.Config.Packages)
local Tuning = require(Shared.Config.Tuning)
local Remotes = require(Shared.Remotes)
local PackageService = require(script.Parent.PackageService)
local PayoutService = require(script.Parent.PayoutService)

local OrderService = {}

local M0_PACKAGES = { "cake", "fishTank", "ladder" }
local ROUTE_FACTOR = 1.3 -- straight-line distance -> rough walking distance

type Destination = { name: string, zone: BasePart, color: Color3 }
type Order = {
	player: Player,
	package: PackageService.Package,
	destination: Destination,
	packageName: string,
	baseValue: number,
	rarityMultiplier: number,
	mutationMultiplier: number,
	startedAt: number,
	parTime: number,
	minTime: number,
}

local orders: { [Player]: Order } = {}
local lastOrderAt: { [Player]: number } = {}
local orderByPackage: { [string]: Order } = {}
local destinations: { Destination } = {}
local rng = Random.new()

local function inZone(zone: BasePart, position: Vector3): boolean
	local p = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
end

local function finish(order: Order, condition: number)
	orders[order.player] = nil
	orderByPackage[order.package.id] = nil
	lastOrderAt[order.player] = os.clock()

	local pkg = order.package
	local result = PayoutService.score(order.player, order, condition, pkg.flag, {
		impact = pkg.impactDamageTotal,
		tilt = pkg.tiltDamageTotal,
		hits = pkg.hits,
	})
	if result.delivered then
		local stats = order.player:FindFirstChild("leaderstats")
		local deliveries = stats and stats:FindFirstChild("Deliveries") :: IntValue?
		if deliveries then
			deliveries.Value += 1
		end
	end
	if not order.package.broken then
		PackageService.destroy(order.package)
	end
	Remotes.get("DeliveryResult"):FireClient(order.player, result)
end

local function takeOrder(player: Player, board: BasePart)
	if orders[player] then
		return
	end
	if os.clock() - (lastOrderAt[player] or 0) < Tuning.ORDER_COOLDOWN then
		return
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp or (hrp.Position - board.Position).Magnitude > 16 then
		return
	end

	local packageId = M0_PACKAGES[rng:NextInteger(1, #M0_PACKAGES)]
	local def = Packages[packageId]
	local destination = destinations[rng:NextInteger(1, #destinations)]

	-- Spawn at the hold point so the grip has nothing to yank.
	local spawnCFrame = hrp.CFrame * CFrame.new(Tuning.HOLD_OFFSET)
	local pkg = PackageService.spawn(player, packageId, spawnCFrame, 1)

	local distance = (destination.zone.Position - hrp.Position).Magnitude
	local order: Order = {
		player = player,
		package = pkg,
		destination = destination,
		packageName = def.displayName,
		baseValue = def.baseValue,
		rarityMultiplier = 1,
		mutationMultiplier = 1,
		startedAt = os.clock(),
		parTime = math.floor(distance * ROUTE_FACTOR / Tuning.PAR_SPEED + 0.5),
		minTime = distance / Tuning.MIN_ROUTE_SPEED,
	}
	orders[player] = order
	orderByPackage[pkg.id] = order

	PackageService.pickup(pkg, player)
	Remotes.get("OrderRolled"):FireClient(player, {
		packageId = packageId,
		displayName = def.displayName,
		archetype = def.archetype,
		baseValue = def.baseValue,
		destinationName = destination.name,
		destination = destination.zone,
		parTime = order.parTime,
	})
end

function OrderService.init(map: { dispatchBoard: BasePart, destinations: { Destination } })
	destinations = map.destinations

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Take Order"
	prompt.ObjectText = "Dispatch"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = map.dispatchBoard
	prompt.Triggered:Connect(function(player)
		takeOrder(player, map.dispatchBoard)
	end)

	PackageService.onSampled = function(pkg)
		local order = orderByPackage[pkg.id]
		if order and inZone(order.destination.zone, pkg.root.Position) then
			finish(order, pkg.condition)
		end
	end
	PackageService.onBroken = function(pkg)
		local order = orderByPackage[pkg.id]
		if order then
			finish(order, 0)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		local order = orders[player]
		if order then
			orderByPackage[order.package.id] = nil
		end
		orders[player] = nil
		lastOrderAt[player] = nil
	end)
end

return OrderService
