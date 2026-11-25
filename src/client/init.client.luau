-- Client entry point: input, carry feel and UI. Nothing here decides what pays.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)
local Hud = require(script.UI.Hud)
local Reveal = require(script.UI.Reveal)
local Announcer = require(script.UI.Announcer)
local CarryController = require(script.CarryController)
local RagdollController = require(script.RagdollController)
local PackageFx = require(script.PackageFx)
local ProfileCache = require(script.ProfileCache)
local DepotView = require(script.DepotView)
local Panels = require(script.UI.Panels)
local Theme = require(script.UI.Theme)

Hud.init()
Reveal.init(Hud.getGui())
Announcer.init(Hud.getGui())
CarryController.init()
RagdollController.init()
task.spawn(PackageFx.init)
ProfileCache.init()
task.spawn(DepotView.init)
Panels.init(Hud.getGui())

Hud.onDrop = CarryController.drop
Hud.onRotate = CarryController.rotate
Hud.onGetUp = RagdollController.getUp

CarryController.onChanged = function(package)
	Hud.setCarrying(package ~= nil)
end

-- Space / ButtonA gets you up, but only while you're down, so it never steals Jump.
RagdollController.onChanged = function(down)
	Hud.setRagdolled(down)
	if down then
		ContextActionService:BindAction("FF_GetUp", function(_, state)
			if state == Enum.UserInputState.Begin then
				RagdollController.getUp()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	else
		ContextActionService:UnbindAction("FF_GetUp")
	end
end

Remotes.get("OrderRevealing").OnClientEvent:Connect(function(info)
	Reveal.play(info)
end)
Remotes.get("Announcement").OnClientEvent:Connect(function(text, color)
	Announcer.show(text, color)
end)
Remotes.get("OrderRolled").OnClientEvent:Connect(function(order)
	Hud.setOrder(order)
end)
Remotes.get("ConditionUpdate").OnClientEvent:Connect(function(condition, lastHit)
	Hud.setCondition(condition)
	Hud.setDebugHit(lastHit)
end)
Remotes.get("DeliveryResult").OnClientEvent:Connect(function(result)
	Hud.showResult(result)
	DepotView.offerDisplay(Hud.getResultActions(), result)
end)
Remotes.get("OfflineEarnings").OnClientEvent:Connect(function(coins, seconds)
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	Announcer.show(
		string.format("While you were gone (%dh %dm), your Depot earned +%s Coins!", hours, minutes, Theme.short(coins)),
		Theme.GOLD
	)
end)
