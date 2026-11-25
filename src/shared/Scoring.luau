--!strict
-- Pure scoring math (GDD §3.3, §5.1). No Roblox services, so it can be unit tested anywhere.

local Tuning = require(script.Parent.Config.Tuning)

local Scoring = {}

local GRAVITY_STEP_EPSILON = 1e-6

--[[
	Velocity change that counts as an impact between two samples.

	A package in free fall gains g*dt of speed every sample, and one resting on a table has
	zero change. Neither should hurt. Comparing the raw change and the gravity-compensated
	change and taking the smaller one makes both read ~0, while a real impact still reads
	high on both.
]]
function Scoring.impactDeltaV(lastVelocity: Vector3, velocity: Vector3, dt: number, gravity: number): number
	local raw = velocity - lastVelocity
	local expectedFall = Vector3.new(0, -gravity * math.max(dt, GRAVITY_STEP_EPSILON), 0)
	local compensated = raw - expectedFall
	return math.min(raw.Magnitude, compensated.Magnitude)
end

function Scoring.impactDamage(deltaV: number, fragility: number, fragilityMultiplier: number, mutationMultiplier: number): number
	if deltaV <= fragility then
		return 0
	end
	return (deltaV - fragility) * fragilityMultiplier * mutationMultiplier
end

-- Degrees between the package's up vector and world up.
function Scoring.tiltAngle(upVector: Vector3): number
	local dot = math.clamp(upVector.Unit:Dot(Vector3.yAxis), -1, 1)
	return math.deg(math.acos(dot))
end

function Scoring.tiltDamage(angle: number, limit: number?, damagePerSecond: number?, dt: number): number
	if not limit or not damagePerSecond or angle <= limit then
		return 0
	end
	local excess = math.min(angle - limit, 90) / 90
	return excess * damagePerSecond * dt
end

-- 1.25 at or under par, falling linearly to 1.0 at 2x par, 1.0 after.
function Scoring.timeBonus(elapsed: number, parTime: number): number
	if parTime <= 0 or elapsed <= parTime then
		return Tuning.TIME_BONUS_MAX
	end
	local t = math.clamp((elapsed - parTime) / parTime, 0, 1)
	return Tuning.TIME_BONUS_MAX + (1 - Tuning.TIME_BONUS_MAX) * t
end

export type PayoutInput = {
	baseValue: number,
	rarityMultiplier: number,
	mutationMultiplier: number,
	condition: number, -- 0..100
	elapsed: number,
	parTime: number,
	tipPercent: number, -- 0, 0.1, 0.3, 2.0
}

export type PayoutResult = {
	payout: number,
	tip: number,
	total: number,
	timeBonus: number,
}

function Scoring.payout(input: PayoutInput): PayoutResult
	if input.condition <= 0 then
		local consolation = math.floor(input.baseValue * Tuning.BROKEN_PAYOUT + 0.5)
		return { payout = consolation, tip = 0, total = consolation, timeBonus = 1 }
	end
	local bonus = Scoring.timeBonus(input.elapsed, input.parTime)
	local conditionFactor = (math.clamp(input.condition, 0, 100) / 100) ^ Tuning.CONDITION_EXPONENT
	local payout = input.baseValue * input.rarityMultiplier * input.mutationMultiplier * conditionFactor * bonus
	payout = math.floor(payout + 0.5)
	local tip = math.floor(payout * input.tipPercent + 0.5)
	return { payout = payout, tip = tip, total = payout + tip, timeBonus = bonus }
end

return Scoring
