-- Delivery scoring and anti-exploit validation (GDD §3.3, §5.1). Server only.
-- M0: no saving, so Coins live in leaderstats for the session.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Scoring = require(Shared.Scoring)

local PayoutService = {}

export type Result = {
	delivered: boolean,
	broke: boolean,
	rejected: string?,
	packageName: string,
	condition: number,
	elapsed: number,
	parTime: number,
	payout: number,
	tip: number,
	tipMood: string,
	total: number,
	timeBonus: number,
	coins: number,
}

local function coinsValue(player: Player): IntValue?
	local stats = player:FindFirstChild("leaderstats")
	return stats and stats:FindFirstChild("Coins") :: IntValue?
end

function PayoutService.award(player: Player, amount: number): number
	local coins = coinsValue(player)
	if not coins then
		return 0
	end
	coins.Value += amount
	return coins.Value
end

type Order = {
	packageName: string,
	baseValue: number,
	rarityMultiplier: number,
	mutationMultiplier: number,
	startedAt: number,
	parTime: number,
	minTime: number,
}

-- condition 0 = broken. flag = anti-exploit reason from PackageService, if any.
function PayoutService.score(player: Player, order: Order, condition: number, flag: string?): Result
	local elapsed = os.clock() - order.startedAt
	local rejected: string? = flag
	if not rejected and condition > 0 and elapsed < order.minTime then
		rejected = string.format("too fast (%.1fs < %.1fs)", elapsed, order.minTime)
	end

	local result: Result = {
		delivered = condition > 0 and rejected == nil,
		broke = condition <= 0,
		rejected = rejected,
		packageName = order.packageName,
		condition = math.floor(condition + 0.5),
		elapsed = elapsed,
		parTime = order.parTime,
		payout = 0,
		tip = 0,
		tipMood = "None", -- M1: GachaService tip roll
		total = 0,
		timeBonus = 1,
		coins = 0,
	}

	if rejected then
		warn(string.format("[PayoutService] rejected delivery from %s: %s", player.Name, rejected))
	else
		local p = Scoring.payout({
			baseValue = order.baseValue,
			rarityMultiplier = order.rarityMultiplier,
			mutationMultiplier = order.mutationMultiplier,
			condition = condition,
			elapsed = elapsed,
			parTime = order.parTime,
			tipPercent = 0,
		})
		result.payout = p.payout
		result.tip = p.tip
		result.total = p.total
		result.timeBonus = p.timeBonus
	end
	result.coins = PayoutService.award(player, result.total)

	-- GDD §9 per-delivery analytics. Printed for M0 playtests; AnalyticsService in M2.
	print(string.format(
		"[Delivery] %s %s cond=%d time=%.1fs par=%.1fs broke=%s paid=%d%s",
		player.Name, order.packageName, result.condition, elapsed, order.parTime,
		tostring(result.broke), result.total, rejected and (" REJECTED " .. rejected) or ""
	))
	return result
end

function PayoutService.init()
	local function setup(player: Player)
		local stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		local coins = Instance.new("IntValue")
		coins.Name = "Coins"
		coins.Parent = stats
		local deliveries = Instance.new("IntValue")
		deliveries.Name = "Deliveries"
		deliveries.Parent = stats
		stats.Parent = player
	end
	Players.PlayerAdded:Connect(setup)
	for _, p in Players:GetPlayers() do
		setup(p)
	end
end


return PayoutService
