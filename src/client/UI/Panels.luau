-- Index (collection) and Odds panels, plus the side menu that opens them.

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = require(Shared.Config.Packages)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Tips = require(Shared.Config.Tips)
local Gacha = require(Shared.Gacha)
local Theme = require(script.Parent.Theme)
local ProfileCache = require(script.Parent.Parent.ProfileCache)

local Panels = {}

local gui: ScreenGui
local open: Frame? = nil

local PACKAGE_IDS: { string } = {}
for id in Packages do
	table.insert(PACKAGE_IDS, id)
end
table.sort(PACKAGE_IDS, function(a, b)
	return Packages[a].displayName < Packages[b].displayName
end)

local function closeOpen()
	if open then
		open:Destroy()
		open = nil
	end
end

local function window(title: string, width: number, height: number): (Frame, ScrollingFrame)
	closeOpen()
	local frame = Theme.panel(gui, UDim2.fromOffset(width, height), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	frame.ZIndex = 10
	local scale = Instance.new("UIScale")
	scale.Scale = 0.85
	scale.Parent = frame
	TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()

	local t = Theme.label(frame, {
		Size = UDim2.new(1, -80, 0, 40),
		Position = UDim2.fromOffset(16, 10),
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	Theme.stroke(t, Color3.new(0, 0, 0), 2)
	local close = Theme.button(frame, "X", Theme.BAD, {
		Size = UDim2.fromOffset(44, 44),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
	})
	close.Activated:Connect(closeOpen)

	local body = Instance.new("ScrollingFrame")
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Size = UDim2.new(1, -24, 1, -70)
	body.Position = UDim2.fromOffset(12, 60)
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.CanvasSize = UDim2.new()
	body.ScrollBarThickness = 6
	body.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = body

	open = frame
	return frame, body
end

local function row(parent: Instance, height: number, order: number): Frame
	local r = Instance.new("Frame")
	r.BackgroundColor3 = Theme.PANEL_LIGHT
	r.BackgroundTransparency = 0.2
	r.Size = UDim2.new(1, -8, 0, height)
	r.LayoutOrder = order
	Theme.corner(r, 10)
	r.Parent = parent
	return r
end

--== Index ==--

function Panels.openIndex()
	local snapshot = ProfileCache.data
	local index = snapshot and snapshot.index or {}
	local frame, body = window("Collection Index", 640, 460)

	local total, found = 0, 0
	for _, id in PACKAGE_IDS do
		for _, r in Rarities.list do
			for _, m in Mutations.list do
				total += 1
				if index[Gacha.indexKey(id, r.id, m.id)] then
					found += 1
				end
			end
		end
	end
	local pct = Theme.label(frame, {
		Size = UDim2.fromOffset(200, 30),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -64, 0, 16),
		Text = string.format("%d / %d  (%d%%)", found, total, math.floor(found / math.max(total, 1) * 100)),
		TextColor3 = Theme.GOLD,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	Theme.stroke(pct, Color3.new(0, 0, 0), 2)

	for i, id in PACKAGE_IDS do
		local def = Packages[id]
		local r = row(body, 92, i)
		Theme.label(r, {
			Size = UDim2.fromOffset(130, 30),
			Position = UDim2.fromOffset(10, 31),
			Text = def.displayName,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		for j, rarity in Rarities.list do
			local cell = Instance.new("Frame")
			cell.Size = UDim2.fromOffset(72, 76)
			cell.Position = UDim2.fromOffset(140 + (j - 1) * 78, 8)
			cell.BackgroundColor3 = Color3.fromRGB(20, 22, 32)
			Theme.corner(cell, 8)
			cell.Parent = r

			local count, mutationsFound = 0, {}
			for _, m in Mutations.list do
				local n = index[Gacha.indexKey(id, rarity.id, m.id)]
				if n then
					count += n
					table.insert(mutationsFound, m)
				end
			end
			local have = count > 0
			Theme.stroke(cell, rarity.color, 2, if have then 0 else 0.7)
			local name = Theme.label(cell, {
				Size = UDim2.new(1, -6, 0, 20),
				Position = UDim2.fromOffset(3, 4),
				Text = rarity.displayName,
				TextColor3 = if have then rarity.color else Color3.fromRGB(90, 90, 100),
			})
			name.ZIndex = 2
			Theme.label(cell, {
				Size = UDim2.new(1, -6, 0, 26),
				Position = UDim2.fromOffset(3, 24),
				Text = if have then "×" .. count else "?",
				TextColor3 = if have then Theme.TEXT else Color3.fromRGB(70, 70, 80),
			})
			-- One pip per mutation collected at this rarity.
			for k, m in mutationsFound do
				if m.id ~= "None" then
					local pip = Instance.new("Frame")
					pip.Size = UDim2.fromOffset(9, 9)
					pip.Position = UDim2.fromOffset(4 + (k - 1) * 11, 60)
					pip.BackgroundColor3 = m.color or Color3.new(1, 1, 1)
					Theme.corner(pip, 5)
					pip.Parent = cell
				end
			end
		end
	end
end

--== Odds ==--

local function oddsRows(body: ScrollingFrame, title: string, odds, nameOf: (string) -> (string, Color3), extra: ((string) -> string)?, order: number)
	local header = Theme.label(body, {
		Size = UDim2.new(1, -8, 0, 30),
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.GOLD,
		LayoutOrder = order,
	})
	Theme.stroke(header, Color3.new(0, 0, 0), 2)
	for i, o in odds do
		local r = row(body, 34, order + i)
		local name, color = nameOf(o.id)
		Theme.label(r, {
			Size = UDim2.new(0.45, 0, 1, -8),
			Position = UDim2.fromOffset(12, 4),
			Text = name,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local pct = o.chance * 100
		Theme.label(r, {
			Size = UDim2.new(0.2, 0, 1, -8),
			Position = UDim2.fromScale(0.45, 0) + UDim2.fromOffset(0, 4),
			Text = if pct >= 1 then string.format("%.1f%%", pct) else string.format("%.2f%%", pct),
		})
		if extra then
			Theme.label(r, {
				Size = UDim2.new(0.33, -12, 1, -8),
				Position = UDim2.fromScale(0.65, 0) + UDim2.fromOffset(0, 4),
				Text = extra(o.id),
				TextColor3 = Theme.MUTED,
				TextXAlignment = Enum.TextXAlignment.Right,
			})
		end
	end
end

function Panels.openOdds()
	local snapshot = ProfileCache.data
	local luck = snapshot and snapshot.luck or 0
	local pity = snapshot and snapshot.pity or 0
	local _, body = window("Odds", 520, 520)

	local info = Theme.label(body, {
		Size = UDim2.new(1, -8, 0, 44),
		Text = string.format("Your luck: +%d%%  ·  Pity: %d / %d (Epic+ guaranteed at %d)", math.floor(luck * 100 + 0.5), pity, Rarities.PITY_THRESHOLD, Rarities.PITY_THRESHOLD),
		TextColor3 = Theme.MUTED,
		Font = Theme.BODY_FONT,
		TextWrapped = true,
		LayoutOrder = 0,
	})
	info.TextScaled = true

	oddsRows(body, "Package rarity (with your luck)", Gacha.rarityOdds(luck, pity), function(id)
		local r = Rarities.byId[id]
		return r.displayName, r.color
	end, function(id)
		return string.format("%g× value", Rarities.byId[id].valueMultiplier)
	end, 10)
	oddsRows(body, "Mutation", Gacha.mutationOdds(), function(id)
		local m = Mutations.byId[id]
		return if m.displayName ~= "" then m.displayName else "None", m.color or Theme.TEXT
	end, function(id)
		return string.format("%g× pay", Mutations.byId[id].payMultiplier)
	end, 30)
	oddsRows(body, "Customer tip (condition 90%+)", Gacha.tipOdds(100), function(id)
		local m = Tips.byId[id]
		return m.emoji .. " " .. m.id, m.color
	end, function(id)
		local m = Tips.byId[id]
		return string.format("+%d%%", math.floor(m.tipPercent * 100 + 0.5))
			.. (if m.minCondition then string.format(" (needs %d%%+)", m.minCondition) else "")
	end, 50)
end

--== Menu ==--

function Panels.init(parentGui: ScreenGui)
	gui = parentGui
	local menu = Instance.new("Frame")
	menu.BackgroundTransparency = 1
	menu.Size = UDim2.fromOffset(110, 120)
	menu.Position = UDim2.fromOffset(12, 96)
	menu.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = menu
	local index = Theme.button(menu, "Index", Color3.fromRGB(180, 110, 230), { Size = UDim2.fromOffset(110, 48) })
	index.Activated:Connect(function()
		if open and open:GetAttribute("Kind") == "Index" then
			closeOpen()
		else
			Panels.openIndex()
			if open then
				open:SetAttribute("Kind", "Index")
			end
		end
	end)
	local odds = Theme.button(menu, "Odds", Color3.fromRGB(70, 160, 200), { Size = UDim2.fromOffset(110, 48) })
	odds.Activated:Connect(function()
		if open and open:GetAttribute("Kind") == "Odds" then
			closeOpen()
		else
			Panels.openOdds()
			if open then
				open:SetAttribute("Kind", "Odds")
			end
		end
	end)

	-- The dispatch board's "View Odds" prompt (GDD §4.4) opens the same panel.
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "OddsPrompt" then
			Panels.openOdds()
		end
	end)
end

return Panels
