-- Draws *your* displayed packages on the shared Depot pedestals, with income labels, and
-- offers "Display in Depot" on the delivery result card.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Packages = require(Shared.Config.Packages)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Depot = require(Shared.Config.Depot)
local DepotMath = require(Shared.DepotMath)
local PackageBuilder = require(Shared.PackageBuilder)
local ProfileCache = require(script.Parent.ProfileCache)
local Theme = require(script.Parent.UI.Theme)

local DepotView = {}

local player = Players.LocalPlayer
local shown: { [number]: { key: string, model: Model, base: CFrame } } = {}
local folder: Folder

local function keyOf(item): string
	return item.id .. "|" .. item.rarity .. "|" .. item.mutation
end

local function label(model: Model, root: BasePart, item)
	local rarity = Rarities.byId[item.rarity]
	local mutation = Mutations.byId[item.mutation]
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(170, 52)
	gui.StudsOffsetWorldSpace = Vector3.new(0, root.Size.Y / 2 + 1.8, 0)
	gui.MaxDistance = 60
	gui.Adornee = root
	local name = Theme.label(gui, {
		Size = UDim2.fromScale(1, 0.55),
		Text = (if mutation.displayName ~= "" then mutation.displayName .. " " else "") .. rarity.displayName,
		TextColor3 = rarity.color,
	})
	Theme.stroke(name, Color3.new(0, 0, 0), 2)
	local rate = Theme.label(gui, {
		Size = UDim2.fromScale(1, 0.45),
		Position = UDim2.fromScale(0, 0.55),
		Text = string.format("+%s / min", Theme.short(DepotMath.perMinute(item))),
		TextColor3 = Theme.GOLD,
	})
	Theme.stroke(rate, Color3.new(0, 0, 0), 2)
	gui.Parent = model
end

local function render(snapshot)
	local hall = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Depot")
	if not hall then
		return
	end
	local displayed = snapshot.depot.displayed
	for slot = 1, Depot.MAX_SLOTS do
		local item = displayed[slot]
		local current = shown[slot]
		if current and (not item or current.key ~= keyOf(item)) then
			current.model:Destroy()
			shown[slot] = nil
		end
		if item and not shown[slot] and DepotMath.isValid(item) then
			local def = Packages[item.id]
			local model, root = PackageBuilder.buildDisplay(def, Mutations.byId[item.mutation])
			local top = DepotMath.pedestalPosition(slot) + Vector3.new(0, 1.6 + def.rootSize.Y / 2, 0)
			-- Long items would hang over neighbours; shrink their footprint on the pedestal.
			local base = CFrame.new(top)
			model:PivotTo(base)
			if def.rootSize.X > 6 then
				model:ScaleTo(6 / def.rootSize.X)
				model:PivotTo(base)
			end
			label(model, root, item)
			model:SetAttribute("Rarity", item.rarity)
			model:SetAttribute("Mutation", item.mutation)
			model.Parent = folder
			shown[slot] = { key = keyOf(item), model = model, base = base }
		end

		local pedestal = hall:FindFirstChild("Pedestal_" .. slot) :: BasePart?
		if pedestal then
			local unlocked = slot <= snapshot.depot.slots
			pedestal.LocalTransparencyModifier = if unlocked then 0 else 0.7
		end
	end

	local sign = hall:FindFirstChild("DepotSign")
	local text = sign and sign:FindFirstChild("SignGui") and sign.SignGui:FindFirstChild("Text")
	if text then
		text.Text = string.format("%s's DEPOT · Tips %s", string.upper(player.DisplayName), Theme.short(snapshot.lifetimeTips))
	end
end

function DepotView.offerDisplay(actions: Frame, result)
	local snapshot = ProfileCache.data
	if not snapshot or not result.delivered then
		return
	end
	local item = { id = result.packageId, rarity = result.rarity, mutation = result.mutation }
	local displayed = snapshot.depot.displayed
	local text
	if #displayed < snapshot.depot.slots then
		text = string.format("Display in Depot (+%s/min)", Theme.short(DepotMath.perMinute(item)))
	else
		local weakest = DepotMath.weakestIndex(displayed)
		if not weakest or DepotMath.perMinute(displayed[weakest]) >= DepotMath.perMinute(item) then
			return -- Depot full of better stuff
		end
		text = "Swap into Depot (weakest out)"
	end
	local b = Theme.button(actions, text, Color3.fromRGB(70, 130, 220), {
		Size = UDim2.fromOffset(300, 48),
	})
	b.Activated:Connect(function()
		Remotes.get("RequestDisplay"):FireServer()
		b.Text = "Displayed!"
		b.Active = false
		b.AutoButtonColor = false
		b.BackgroundColor3 = Color3.fromRGB(80, 160, 90)
	end)
end

function DepotView.init()
	folder = Instance.new("Folder")
	folder.Name = "FF_MyDepot"
	folder.Parent = workspace
	ProfileCache.onChanged(render)

	-- Slow spin on the displays.
	RunService.RenderStepped:Connect(function()
		local angle = (os.clock() * 0.6) % (math.pi * 2)
		for _, entry in shown do
			entry.model:PivotTo(entry.base * CFrame.Angles(0, angle, 0))
		end
	end)
end

return DepotView
