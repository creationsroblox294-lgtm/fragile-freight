-- Shared UI look: fonts, colors and small builders so every panel matches.

local Theme = {}

Theme.FONT = Enum.Font.FredokaOne
Theme.BODY_FONT = Enum.Font.GothamMedium
Theme.PANEL = Color3.fromRGB(24, 28, 42)
Theme.PANEL_LIGHT = Color3.fromRGB(38, 44, 64)
Theme.TEXT = Color3.fromRGB(245, 245, 250)
Theme.MUTED = Color3.fromRGB(175, 185, 205)
Theme.GOLD = Color3.fromRGB(255, 215, 90)
Theme.GOOD = Color3.fromRGB(110, 230, 130)
Theme.BAD = Color3.fromRGB(255, 100, 90)

function Theme.corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 12)
	c.Parent = parent
	return c
end

function Theme.stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.new(0, 0, 0)
	s.Thickness = thickness or 2
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = if parent:IsA("TextLabel") or parent:IsA("TextButton")
		then Enum.ApplyStrokeMode.Contextual
		else Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function Theme.gradient(parent: Instance, top: Color3, bottom: Color3)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = 90
	g.Parent = parent
	return g
end

function Theme.panel(parent: Instance, size: UDim2, position: UDim2, anchor: Vector2?): Frame
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = position
	f.AnchorPoint = anchor or Vector2.zero
	f.BackgroundColor3 = Theme.PANEL
	f.BackgroundTransparency = 0.08
	Theme.corner(f, 16)
	Theme.stroke(f, Color3.fromRGB(255, 255, 255), 1.5, 0.85)
	Theme.gradient(f, Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 195, 215))
	f.Parent = parent
	return f
end

function Theme.label(parent: Instance, props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = Theme.FONT
	t.TextColor3 = Theme.TEXT
	t.TextScaled = true
	for k, v in props do
		(t :: any)[k] = v
	end
	t.Parent = parent
	return t
end

function Theme.button(parent: Instance, text: string, color: Color3, props: { [string]: any }?): TextButton
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = color
	b.Font = Theme.FONT
	b.Text = text
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.AutoButtonColor = true
	Theme.corner(b, 12)
	Theme.stroke(b, Color3.new(0, 0, 0), 2, 0.6)
	Theme.gradient(b, Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 200))
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = b
	for k, v in props or {} do
		(b :: any)[k] = v
	end
	b.Parent = parent
	return b
end

-- Formats 1234567 as "1.23M".
function Theme.short(n: number): string
	local abs = math.abs(n)
	if abs >= 1e9 then
		return string.format("%.2fB", n / 1e9)
	elseif abs >= 1e6 then
		return string.format("%.2fM", n / 1e6)
	elseif abs >= 1e4 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(math.floor(n))
end

return Theme
