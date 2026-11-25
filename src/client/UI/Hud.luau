-- M0 HUD, built in code: coins, order panel + timer, condition meter, Drop / Turn / Get Up
-- buttons (big, for touch), a destination beam, and the delivery result card.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Hud = {}

Hud.onDrop = function() end
Hud.onRotate = function() end
Hud.onGetUp = function() end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tuning = require(ReplicatedStorage:WaitForChild("Shared").Config.Tuning)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Mutations = require(ReplicatedStorage.Shared.Config.Mutations)
local Tips = require(ReplicatedStorage.Shared.Config.Tips)
local Theme = require(script.Parent.Theme)

local player = Players.LocalPlayer
local FONT = Enum.Font.FredokaOne

local gui: ScreenGui
local coinsLabel: TextLabel
local orderPanel: Frame
local orderTitle: TextLabel
local orderTimer: TextLabel
local conditionFill: Frame
local conditionText: TextLabel
local debugText: TextLabel
local dropButton: TextButton
local rotateButton: TextButton
local getUpButton: TextButton
local resultCard: Frame
local resultTitle: TextLabel
local resultBody: TextLabel
local resultTip: TextLabel
local resultNew: TextLabel
local resultActions: Frame
local tipsLabel: TextLabel

local orderStartedAt: number? = nil
local orderPar = 0
local destinationZone: BasePart? = nil
local beam: Beam? = nil
local beamTarget: Attachment? = nil
local highlight: Highlight? = nil
local resultToken = 0

local function corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 12)
	c.Parent = parent
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = FONT
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextScaled = true
	t.TextStrokeTransparency = 0.5
	for k, v in props do
		(t :: any)[k] = v
	end
	t.Parent = parent
	return t
end

local function button(label: string, position: UDim2, color: Color3, callback: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(110, 110)
	b.AnchorPoint = Vector2.new(1, 1)
	b.Position = position
	b.BackgroundColor3 = color
	b.Font = FONT
	b.Text = label
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Visible = false
	b.AutoButtonColor = true
	corner(b, 55)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = b
	b.Activated:Connect(callback)
	b.Parent = gui
	return b
end

local function conditionColor(c: number): Color3
	if c >= 70 then
		return Color3.fromRGB(90, 210, 110)
	elseif c >= 35 then
		return Color3.fromRGB(240, 190, 60)
	end
	return Color3.fromRGB(230, 70, 60)
end

-- Playtest readout: what last cost the package condition, and how much.
function Hud.setDebugHit(hit: { deltaV: number, damage: number, source: string, hit: string }?)
	if not Tuning.DEBUG_HUD or not hit then
		return
	end
	if hit.source == "tilt" then
		debugText.Text = string.format("tilt %.0f° → -%.1f", hit.deltaV, hit.damage)
	else
		debugText.Text = string.format("hit %s at %.0f studs/s → -%.1f", hit.hit, hit.deltaV, hit.damage)
	end
end

function Hud.setCondition(c: number)
	TweenService:Create(conditionFill, TweenInfo.new(0.15), {
		Size = UDim2.fromScale(math.clamp(c / 100, 0, 1), 1),
		BackgroundColor3 = conditionColor(c),
	}):Play()
	conditionText.Text = string.format("%d%%", c)
end

local function clearWaypoint()
	if beam then
		beam:Destroy()
		beam = nil
	end
	if beamTarget then
		beamTarget:Destroy()
		beamTarget = nil
	end
	if highlight then
		highlight:Destroy()
		highlight = nil
	end
end

local function attachWaypoint()
	clearWaypoint()
	local zone = destinationZone
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not zone or not root then
		return
	end
	local from = Instance.new("Attachment")
	from.Name = "FF_BeamFrom"
	from.Parent = root
	beamTarget = Instance.new("Attachment")
	beamTarget.Parent = zone

	local b = Instance.new("Beam")
	b.Attachment0 = from
	b.Attachment1 = beamTarget
	b.Width0 = 0.6
	b.Width1 = 0.6
	b.FaceCamera = true
	b.Color = ColorSequence.new(Color3.fromRGB(120, 255, 140))
	b.Transparency = NumberSequence.new(0.4)
	b.LightEmission = 1
	b.Segments = 1
	b.Parent = from
	beam = b

	local h = Instance.new("Highlight")
	h.FillColor = Color3.fromRGB(120, 255, 140)
	h.FillTransparency = 0.6
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Adornee = zone
	h.Parent = zone -- local-only instance; other players don't see your waypoint
	highlight = h
end

function Hud.getGui(): ScreenGui
	return gui
end

-- Container under the result card text for extra buttons (Depot "Display" lives here).
function Hud.getResultActions(): Frame
	return resultActions
end

function Hud.setOrder(order: { displayName: string, destinationName: string, destination: BasePart, parTime: number, rarity: string?, mutation: string? }?)
	if not order then
		orderPanel.Visible = false
		orderStartedAt = nil
		destinationZone = nil
		clearWaypoint()
		return
	end
	local rarity = Rarities.byId[order.rarity or "Common"] or Rarities.byId.Common
	local mutation = Mutations.byId[order.mutation or "None"] or Mutations.byId.None
	local prefix = rarity.displayName .. " " .. (if mutation.displayName ~= "" then mutation.displayName .. " " else "")
	orderTitle.Text = string.format("%s%s → %s", prefix, order.displayName, order.destinationName)
	orderTitle.TextColor3 = rarity.color
	orderPar = order.parTime
	orderStartedAt = os.clock()
	destinationZone = order.destination
	orderPanel.Visible = true
	debugText.Text = ""
	Hud.setCondition(100)
	attachWaypoint()
end

function Hud.setCarrying(carrying: boolean)
	dropButton.Visible = carrying
	rotateButton.Visible = carrying
end

function Hud.setRagdolled(down: boolean)
	getUpButton.Visible = down
end

-- Counts a label up from `from` to `to` for that slot-machine coin feel.
local function countUp(label: TextLabel, from: number, to: number, format: string, duration: number)
	local t0 = os.clock()
	task.spawn(function()
		while os.clock() - t0 < duration do
			local k = (os.clock() - t0) / duration
			k = 1 - (1 - k) ^ 3
			label.Text = string.format(format, Theme.short(from + (to - from) * k))
			task.wait()
		end
		label.Text = string.format(format, Theme.short(to))
	end)
end
Hud.countUp = countUp

function Hud.showResult(result: { [string]: any })
	Hud.setOrder(nil)
	Hud.setCarrying(false)
	for _, child in resultActions:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	resultTip.Text = ""
	resultNew.Visible = false

	if result.rejected then
		resultTitle.Text = "Delivery rejected"
		resultBody.Text = "Something looked off with that run."
	elseif result.broke then
		resultTitle.Text = "BROKEN!"
		resultBody.Text = string.format("The %s didn't make it.\nConsolation: +%d Coins", result.packageName, result.total)
	else
		local rarity = Rarities.byId[result.rarity or "Common"] or Rarities.byId.Common
		local mutation = Mutations.byId[result.mutation or "None"] or Mutations.byId.None
		resultTitle.Text = "Delivered!"
		local bonus = result.timeBonus > 1.001 and string.format("  ×%.2f speed bonus", result.timeBonus) or ""
		local name = rarity.displayName .. " " .. (if mutation.displayName ~= "" then mutation.displayName .. " " else "") .. result.packageName
		resultBody.Text = string.format(
			"%s\nCondition %d%% · %.1fs (par %ds)%s",
			name, result.condition, result.elapsed, result.parTime, bonus
		)
		local mood = Tips.byId[result.tipMood]
		if mood then
			resultTip.TextColor3 = mood.color
			resultTip.Text = if mood.tipPercent > 0
				then string.format("%s %s customer tipped +%d%%  (+%d)", mood.emoji, mood.id, math.floor(mood.tipPercent * 100 + 0.5), result.tip)
				else string.format("%s %s customer. No tip.", mood.emoji, mood.id)
		end
		resultNew.Visible = result.newIndex == true
		if result.newIndex then
			local s = resultNew:FindFirstChildOfClass("UIScale")
			if s then
				s.Scale = 2.5
				TweenService:Create(s, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			end
		end
	end
	resultTitle.TextColor3 = if result.broke or result.rejected then Theme.BAD else Theme.GOOD
	resultCard.Visible = true
	resultCard.Position = UDim2.fromScale(0.5, 0.42)
	TweenService:Create(resultCard, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0.5, 0.38) }):Play()

	-- Coins land with a count-up on the card.
	local coinsLine = resultCard:FindFirstChild("CoinsLine") :: TextLabel
	countUp(coinsLine, 0, result.total, "+%s Coins", 0.9)

	resultToken += 1
	local token = resultToken
	task.delay(6, function()
		if token == resultToken then
			resultCard.Visible = false
		end
	end)
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "FragileFreightHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Scale the whole HUD to the screen so phones and monitors both read well.
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = gui
	local function rescale()
		local camera = workspace.CurrentCamera
		if camera then
			uiScale.Scale = math.clamp(camera.ViewportSize.Y / 760, 0.6, 1.25)
		end
	end
	rescale()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end

	local wallet = Theme.panel(gui, UDim2.fromOffset(210, 74), UDim2.fromOffset(12, 10))
	coinsLabel = Theme.label(wallet, {
		Size = UDim2.new(1, -20, 0, 36),
		Position = UDim2.fromOffset(10, 4),
		Text = "🪙 0",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.GOLD,
	})
	Theme.stroke(coinsLabel, Color3.new(0, 0, 0), 2)
	tipsLabel = Theme.label(wallet, {
		Size = UDim2.new(1, -20, 0, 24),
		Position = UDim2.fromOffset(10, 42),
		Text = "Lifetime tips: 0",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.MUTED,
	})

	orderPanel = Instance.new("Frame")
	orderPanel.Size = UDim2.fromOffset(380, Tuning.DEBUG_HUD and 130 or 108)
	orderPanel.AnchorPoint = Vector2.new(0.5, 0)
	orderPanel.Position = UDim2.new(0.5, 0, 0, 8)
	orderPanel.BackgroundColor3 = Color3.fromRGB(25, 30, 45)
	orderPanel.BackgroundTransparency = 0.25
	orderPanel.Visible = false
	corner(orderPanel)
	orderPanel.Parent = gui

	orderTitle = text(orderPanel, { Size = UDim2.new(1, -20, 0, 34), Position = UDim2.fromOffset(10, 6) })
	orderTimer = text(orderPanel, {
		Size = UDim2.new(1, -20, 0, 24),
		Position = UDim2.fromOffset(10, 40),
		TextColor3 = Color3.fromRGB(200, 210, 230),
	})

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, -20, 0, 28)
	bar.Position = UDim2.fromOffset(10, 70)
	bar.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	corner(bar, 8)
	bar.Parent = orderPanel
	conditionFill = Instance.new("Frame")
	conditionFill.Size = UDim2.fromScale(1, 1)
	conditionFill.BackgroundColor3 = conditionColor(100)
	corner(conditionFill, 8)
	conditionFill.Parent = bar
	conditionText = text(bar, { Size = UDim2.fromScale(1, 1), Text = "100%", ZIndex = 2 })
	debugText = text(orderPanel, {
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.fromOffset(10, 104),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 200, 120),
		Visible = Tuning.DEBUG_HUD,
	})

	dropButton = button("Drop", UDim2.new(1, -24, 1, -150), Color3.fromRGB(200, 80, 70), function()
		Hud.onDrop()
	end)
	rotateButton = button("Turn", UDim2.new(1, -144, 1, -150), Color3.fromRGB(70, 130, 210), function()
		Hud.onRotate()
	end)
	getUpButton = button("Get Up", UDim2.new(1, -24, 1, -270), Color3.fromRGB(90, 180, 90), function()
		Hud.onGetUp()
	end)

	resultCard = Instance.new("Frame")
	resultCard.Size = UDim2.fromOffset(440, 290)
	resultCard.AnchorPoint = Vector2.new(0.5, 0.5)
	resultCard.Position = UDim2.fromScale(0.5, 0.38)
	resultCard.BackgroundColor3 = Color3.fromRGB(25, 30, 45)
	resultCard.BackgroundTransparency = 0.1
	resultCard.Visible = false
	corner(resultCard, 16)
	resultCard.Parent = gui
	resultTitle = text(resultCard, { Size = UDim2.new(1, -20, 0, 56), Position = UDim2.fromOffset(10, 10) })
	Theme.stroke(resultCard, Color3.new(1, 1, 1), 1.5, 0.8)
	resultBody = text(resultCard, {
		Size = UDim2.new(1, -30, 0, 60),
		Position = UDim2.fromOffset(15, 66),
		TextScaled = false,
		TextSize = 22,
		TextWrapped = true,
		TextStrokeTransparency = 1,
	})
	resultTip = text(resultCard, {
		Size = UDim2.new(1, -30, 0, 26),
		Position = UDim2.fromOffset(15, 130),
		TextStrokeTransparency = 1,
	})
	local coinsLine = text(resultCard, {
		Name = "CoinsLine",
		Size = UDim2.new(1, -30, 0, 40),
		Position = UDim2.fromOffset(15, 160),
		TextColor3 = Theme.GOLD,
	})
	coinsLine.Name = "CoinsLine"
	resultNew = text(resultCard, {
		Size = UDim2.fromOffset(120, 40),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 10, 0, -14),
		Rotation = 12,
		Text = "NEW!",
		TextColor3 = Theme.GOLD,
		Visible = false,
	})
	Instance.new("UIScale").Parent = resultNew
	Theme.stroke(resultNew, Color3.fromRGB(120, 60, 0), 3)
	resultActions = Instance.new("Frame")
	resultActions.BackgroundTransparency = 1
	resultActions.Size = UDim2.new(1, -30, 0, 60)
	resultActions.Position = UDim2.fromOffset(15, 214)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.Parent = resultActions
	resultActions.Parent = resultCard
end

function Hud.init()
	build()

	task.spawn(function()
		local stats = player:WaitForChild("leaderstats")
		local coins = stats:WaitForChild("Coins") :: IntValue
		local tips = stats:WaitForChild("Tips") :: IntValue
		local shown = coins.Value
		coinsLabel.Text = "🪙 " .. Theme.short(shown)
		coins.Changed:Connect(function()
			countUp(coinsLabel, shown, coins.Value, "🪙 %s", 0.8)
			shown = coins.Value
		end)
		local function updateTips()
			tipsLabel.Text = "Lifetime tips: " .. Theme.short(tips.Value)
		end
		tips.Changed:Connect(updateTips)
		updateTips()
	end)

	-- The beam's start attachment lives on the character, so re-attach after a respawn.
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart")
		if destinationZone then
			attachWaypoint()
		end
	end)

	RunService.RenderStepped:Connect(function()
		if orderStartedAt then
			local t = os.clock() - orderStartedAt
			orderTimer.Text = string.format("%.1fs  ·  par %ds", t, orderPar)
			orderTimer.TextColor3 = t <= orderPar and Color3.fromRGB(140, 255, 150) or Color3.fromRGB(200, 210, 230)
		end
	end)
end

return Hud
