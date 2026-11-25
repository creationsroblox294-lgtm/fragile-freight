-- Delivery scoring and anti-exploit validation (GDD §3.3, §5.1). Server only.
-- Coins and lifetime tips go through DataService, which saves them and mirrors leaderstats.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Scoring = require(Shared.Scoring)
local Tips = require(Shared.Config.Tips)
local DataService = require(script.Parent.DataService)
local GachaService = require(script.Parent.GachaService)

local PayoutService = {}

export type Result = {
	delivered: boolean,
	broke: boolean,
	rejected: string?,
	packageName: string,
	packageId: string,
	rarity: string,
	mutation: string,
	condition: number,
	elapsed: number,
	parTime: number,
	payout: number,
	tip: number,
	tipMood: string,
	tipPercent: number,
	total: number,
	timeBonus: number,
	coins: number,
	newIndex: boolean?, -- set by OrderService
}

function PayoutService.award(player: Player, amount: number): number
	return DataService.addCoins(player, amount)
end

type Order = {
	packageId: string,
	packageName: string,
	rarity: string,
	mutation: string,
	baseValue: number,
	rarityMultiplier: number,
	mutationMultiplier: number,
	startedAt: number,
	parTime: number,
	minTime: number,
}

-- condition 0 = broken. flag = anti-exploit reason from PackageService, if any.
export type DamageBreakdown = { impact: number, tilt: number, hits: number }

function PayoutService.score(player: Player, order: Order, condition: number, flag: string?, breakdown: DamageBreakdown?): Result
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
		packageId = order.packageId,
		rarity = order.rarity,
		mutation = order.mutation,
		condition = math.floor(condition + 0.5),
		elapsed = elapsed,
		parTime = order.parTime,
		payout = 0,
		tip = 0,
		tipMood = "None",
		tipPercent = 0,
		total = 0,
		timeBonus = 1,
		coins = 0,
	}

	if rejected then
		warn(string.format("[PayoutService] rejected delivery from %s: %s", player.Name, rejected))
	elseif result.delivered then
		-- The customer's mood is rolled only for real deliveries (GDD §4.3).
		local mood = GachaService.rollTip(condition)
		result.tipMood = mood
		result.tipPercent = Tips.byId[mood].tipPercent
	end

	if not rejected then
		local p = Scoring.payout({
			baseValue = order.baseValue,
			rarityMultiplier = order.rarityMultiplier,
			mutationMultiplier = order.mutationMultiplier,
			condition = condition,
			elapsed = elapsed,
			parTime = order.parTime,
			tipPercent = result.tipPercent,
		})
		result.payout = p.payout
		result.tip = p.tip
		result.total = p.total
		result.timeBonus = p.timeBonus
	end
	result.coins = PayoutService.award(player, result.total)
	DataService.addTips(player, result.tip)
	local profile = DataService.get(player)
	if profile and result.delivered then
		profile.deliveries += 1
	end

	-- GDD §9 per-delivery analytics. Printed for M0 playtests; AnalyticsService in M2.
	print(string.format(
		"[Delivery] %s %s %s/%s tip=%s cond=%d time=%.1fs par=%.1fs broke=%s paid=%d impactDmg=%.0f (%d hits) tiltDmg=%.0f%s",
		player.Name, order.packageName, order.rarity, order.mutation, result.tipMood, result.condition, elapsed, order.parTime,
		tostring(result.broke), result.total,
		breakdown and breakdown.impact or 0, breakdown and breakdown.hits or 0, breakdown and breakdown.tilt or 0,
		rejected and (" REJECTED " .. rejected) or ""
	))
	return result
end

return PayoutService
