-- Dispatch board and the order lifecycle (GDD §2 steps 1-4): roll, reveal, carry, deliver,
-- collect. Package type and destination are uniform; rarity and mutation come from
-- GachaService. The tip is rolled in PayoutService at delivery.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = require(Shared.Config.Packages)
local Tuning = require(Shared.Config.Tuning)
local Remotes = require(Shared.Remotes)
local Gacha = require(Shared.Gacha)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local PackageService = require(script.Parent.PackageService)
local PayoutService = require(script.Parent.PayoutService)
local GachaService = require(script.Parent.GachaService)
local DataService = require(script.Parent.DataService)

local OrderService = {}

local REVEAL_TIME = 1.5 -- seconds of crate-open before the package lands in your hands

-- Every package in Config/Packages can be ordered; sorted so rolls are reproducible.
local ORDERABLE: { string } = {}
for id in Packages do
	table.insert(ORDERABLE, id)
end
table.sort(ORDERABLE)
local ROUTE_FACTOR = 1.3 -- straight-line distance -> rough walking distance

type Destination = { name: string, zone: BasePart, color: Color3 }
type Order = {
	player: Player,
	package: PackageService.Package,
	packageId: string,
	rarity: string,
	mutation: string,
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
local revealing: { [Player]: boolean } = {}
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
	local profile = DataService.get(order.player)
	if result.delivered and profile then
		-- Collection Index (GDD §2 step 4): first delivery of type + rarity + mutation.
		local key = Gacha.indexKey(order.packageId, order.rarity, order.mutation)
		result.newIndex = profile.index[key] == nil
		profile.index[key] = (profile.index[key] or 0) + 1
	end
	OrderService.syncProfile(order.player)
	if not order.package.broken then
		PackageService.destroy(order.package)
	end
	Remotes.get("DeliveryResult"):FireClient(order.player, result)
end

local function takeOrder(player: Player, board: BasePart)
	if orders[player] or revealing[player] then
		return
	end
	if os.clock() - (lastOrderAt[player] or 0) < Tuning.ORDER_COOLDOWN then
		return
	end
	if not DataService.get(player) then
		return -- data still loading; the pity counter must be real before we roll
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp or (hrp.Position - board.Position).Magnitude > 16 then
		return
	end

	local packageId = ORDERABLE[rng:NextInteger(1, #ORDERABLE)]
	local def = Packages[packageId]
	local destination = destinations[rng:NextInteger(1, #destinations)]
	local roll = GachaService.rollOrder(player)
	local rarity = Rarities.byId[roll.rarity]
	local mutation = Mutations.byId[roll.mutation]

	-- Crate-open reveal (GDD §4.1). The roll is final before the animation starts.
	revealing[player] = true
	Remotes.get("OrderRevealing"):FireClient(player, {
		packageId = packageId,
		displayName = def.displayName,
		rarity = roll.rarity,
		mutation = roll.mutation,
		pityUsed = roll.pityUsed,
		duration = REVEAL_TIME,
	})
	if rarity.announce then
		local name = (if mutation.displayName ~= "" then mutation.displayName .. " " else "") .. rarity.displayName
		Remotes.get("Announcement"):FireAllClients(
			string.format("%s rolled a %s %s!", player.DisplayName, name, def.displayName),
			rarity.color
		)
	end
	task.wait(REVEAL_TIME)
	revealing[player] = nil

	character = player.Character
	hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not player.Parent or not hrp then
		return
	end

	-- Spawn at the hold point so the grip has nothing to yank.
	local spawnCFrame = hrp.CFrame * CFrame.new(Tuning.HOLD_OFFSET)
	local pkg = PackageService.spawn(player, packageId, spawnCFrame, {
		rarity = roll.rarity,
		mutation = roll.mutation,
	})

	local distance = (destination.zone.Position - hrp.Position).Magnitude
	local order: Order = {
		player = player,
		package = pkg,
		packageId = packageId,
		rarity = roll.rarity,
		mutation = roll.mutation,
		destination = destination,
		packageName = def.displayName,
		baseValue = def.baseValue,
		rarityMultiplier = rarity.valueMultiplier,
		mutationMultiplier = mutation.payMultiplier,
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
		rarity = roll.rarity,
		mutation = roll.mutation,
		destinationName = destination.name,
		destination = destination.zone,
		parTime = order.parTime,
	})
	OrderService.syncProfile(player)
end

-- Snapshot of saved state the UI needs (Index, Depot, odds). Read-only on the client.
function OrderService.syncProfile(player: Player)
	local profile = DataService.get(player)
	if not profile or not player.Parent then
		return
	end
	Remotes.get("ProfileSync"):FireClient(player, {
		coins = profile.coins,
		lifetimeTips = profile.lifetimeTips,
		deliveries = profile.deliveries,
		index = profile.index,
		depot = profile.depot,
		pity = profile.pity,
		luck = GachaService.getLuck(player),
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

	DataService.onLoaded(function(player)
		OrderService.syncProfile(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		revealing[player] = nil
		local order = orders[player]
		if order then
			orderByPackage[order.package.id] = nil
		end
		orders[player] = nil
		lastOrderAt[player] = nil
	end)
end

return OrderService
