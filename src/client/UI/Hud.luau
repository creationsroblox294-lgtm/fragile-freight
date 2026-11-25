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

function Hud.setOrder(order: { displayName: string, destinationName: string, destination: BasePart, parTime: number }?)
	if not order then
		orderPanel.Visible = false
		orderStartedAt = nil
		destinationZone = nil
		clearWaypoint()
		return
	end
	orderTitle.Text = string.format("%s → %s", order.displayName, order.destinationName)
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

function Hud.showResult(result: { [string]: any })
	Hud.setOrder(nil)
	Hud.setCarrying(false)
	if result.rejected then
		resultTitle.Text = "Delivery rejected"
		resultBody.Text = "Something looked off with that run."
	elseif result.broke then
		resultTitle.Text = "BROKEN!"
		resultBody.Text = string.format("The %s didn't make it.\nConsolation: +%d Coins", result.packageName, result.total)
	else
		resultTitle.Text = "Delivered!"
		local bonus = result.timeBonus > 1.001 and string.format("  (×%.2f speed bonus)", result.timeBonus) or ""
		resultBody.Text = string.format(
			"%s · Condition %d%%\nTime %.1fs (par %ds)%s\n+%d Coins",
			result.packageName, result.condition, result.elapsed, result.parTime, bonus, result.total
		)
	end
	resultTitle.TextColor3 = result.broke and Color3.fromRGB(255, 110, 100) or Color3.fromRGB(140, 255, 150)
	resultCard.Visible = true
	resultCard.Position = UDim2.fromScale(0.5, 0.42)
	TweenService:Create(resultCard, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0.5, 0.38) }):Play()

	resultToken += 1
	local token = resultToken
	task.delay(4.5, function()
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

	coinsLabel = text(gui, {
		Size = UDim2.fromOffset(220, 44),
		Position = UDim2.new(0, 16, 0, 12),
		Text = "Coins: 0",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 220, 90),
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
	resultCard.Size = UDim2.fromOffset(420, 190)
	resultCard.AnchorPoint = Vector2.new(0.5, 0.5)
	resultCard.Position = UDim2.fromScale(0.5, 0.38)
	resultCard.BackgroundColor3 = Color3.fromRGB(25, 30, 45)
	resultCard.BackgroundTransparency = 0.1
	resultCard.Visible = false
	corner(resultCard, 16)
	resultCard.Parent = gui
	resultTitle = text(resultCard, { Size = UDim2.new(1, -20, 0, 56), Position = UDim2.fromOffset(10, 10) })
	resultBody = text(resultCard, {
		Size = UDim2.new(1, -30, 0, 104),
		Position = UDim2.fromOffset(15, 72),
		TextScaled = false,
		TextSize = 22,
		TextWrapped = true,
		TextStrokeTransparency = 1,
	})
end

function Hud.init()
	build()

	task.spawn(function()
		local stats = player:WaitForChild("leaderstats")
		local coins = stats:WaitForChild("Coins") :: IntValue
		local function update()
			coinsLabel.Text = "Coins: " .. coins.Value
		end
		coins.Changed:Connect(update)
		update()
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
