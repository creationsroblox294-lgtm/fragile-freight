-- Client carry input (GDD §3.2). The physics itself is AlignPosition/AlignOrientation created
-- by the server; this client owns the package's network simulation while holding it.
-- Inputs: Drop (Q / ButtonX / HUD button), Turn (R / ButtonY / HUD button).

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local CarryController = {}

CarryController.onChanged = function(_package: Model?) end

local current: Model? = nil

function CarryController.getPackage(): Model?
	return current
end

function CarryController.drop()
	if current then
		Remotes.get("RequestDrop"):FireServer()
	end
end

function CarryController.rotate()
	if current then
		Remotes.get("RequestRotate"):FireServer()
	end
end

local function bind()
	ContextActionService:BindAction("FF_Drop", function(_, state)
		if state == Enum.UserInputState.Begin then
			CarryController.drop()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonX)
	ContextActionService:BindAction("FF_Rotate", function(_, state)
		if state == Enum.UserInputState.Begin then
			CarryController.rotate()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.R, Enum.KeyCode.ButtonY)
end

local function unbind()
	ContextActionService:UnbindAction("FF_Drop")
	ContextActionService:UnbindAction("FF_Rotate")
end

function CarryController.init()
	Remotes.get("CarryChanged").OnClientEvent:Connect(function(package: Model?)
		current = package
		if package then
			bind()
		else
			unbind()
		end
		CarryController.onChanged(package)
	end)
end

return CarryController
