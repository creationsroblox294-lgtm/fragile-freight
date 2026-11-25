-- Server-wide banner for Legendary+ rolls (GDD §4.1) and other big moments.

local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.Theme)

local Announcer = {}

local gui: ScreenGui
local queue: { { text: string, color: Color3 } } = {}
local showing = false

local function showNext()
	local item = table.remove(queue, 1)
	if not item then
		showing = false
		return
	end
	showing = true
	local bar = Theme.panel(gui, UDim2.new(0.5, 0, 0, 48), UDim2.new(0.5, 0, 0, -60), Vector2.new(0.5, 0))
	bar.Size = UDim2.new(0, 520, 0, 48)
	local stroke = bar:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = item.color
		stroke.Transparency = 0
		stroke.Thickness = 2.5
	end
	local label = Theme.label(bar, {
		Size = UDim2.new(1, -24, 1, -10),
		Position = UDim2.fromOffset(12, 5),
		Text = item.text,
		TextColor3 = item.color,
	})
	Theme.stroke(label, Color3.new(0, 0, 0), 2)

	TweenService:Create(bar, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 124),
	}):Play()
	task.delay(3.5, function()
		local out = TweenService:Create(bar, TweenInfo.new(0.3), { Position = UDim2.new(0.5, 0, 0, -60) })
		out:Play()
		out.Completed:Wait()
		bar:Destroy()
		showNext()
	end)
end

function Announcer.show(text: string, color: Color3?)
	table.insert(queue, { text = text, color = color or Theme.GOLD })
	if not showing then
		showNext()
	end
end

function Announcer.init(parentGui: ScreenGui)
	gui = parentGui
end

return Announcer
