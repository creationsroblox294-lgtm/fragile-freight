--!strict
-- Customer tip roll at delivery (GDD §4.3).

export type MoodDef = {
	id: string,
	chance: number, -- percent
	tipPercent: number,
	minCondition: number?, -- gated moods re-roll into the others below this
	color: Color3,
	emoji: string,
}

local list: { MoodDef } = {
	{ id = "Grumpy", chance = 40, tipPercent = 0, color = Color3.fromRGB(160, 160, 170), emoji = "😒" },
	{ id = "Normal", chance = 45, tipPercent = 0.10, color = Color3.fromRGB(200, 220, 255), emoji = "🙂" },
	{ id = "Generous", chance = 13, tipPercent = 0.30, color = Color3.fromRGB(120, 255, 150), emoji = "😄" },
	{ id = "Jackpot", chance = 2, tipPercent = 2.00, minCondition = 90, color = Color3.fromRGB(255, 215, 60), emoji = "🤑" },
}

local byId: { [string]: MoodDef } = {}
for _, m in list do
	byId[m.id] = m
end

return { list = list, byId = byId }
