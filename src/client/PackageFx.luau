-- Local visuals and owner-side physics for packages:
--  * rarity outline (Rare+) and sparkles (Legendary+), a floating name tag
--  * Rainbow: animated hue (cosmetic only)
--  * Haunted: ghost wisps, and random shoves while *you* carry it. The carrier's client owns
--    the package's physics, so only it can push it; the server shoves unheld ones.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Theme = require(script.Parent.UI.Theme)

local PackageFx = {}

local player = Players.LocalPlayer

type Tracked = {
	model: Model,
	root: BasePart,
	rainbowParts: { BasePart }?,
	haunted: boolean,
	nextShove: number,
}
local tracked: { [Model]: Tracked } = {}

local function nameTag(model: Model, root: BasePart, rarity: Rarities.RarityDef, mutation: Mutations.MutationDef)
	local gui = Instance.new("BillboardGui")
	gui.Name = "FF_Tag"
	gui.Size = UDim2.fromOffset(200, 40)
	gui.StudsOffsetWorldSpace = Vector3.new(0, root.Size.Y / 2 + 1.6, 0)
	gui.MaxDistance = 80
	gui.LightInfluence = 0
	local label = Theme.label(gui, {
		Size = UDim2.fromScale(1, 1),
		Text = (if mutation.displayName ~= "" then mutation.displayName .. " " else "") .. rarity.displayName,
		TextColor3 = if mutation.color and mutation.id ~= "Rainbow" then mutation.color else rarity.color,
	})
	Theme.stroke(label, Color3.new(0, 0, 0), 2)
	gui.Adornee = root
	gui.Parent = model
end

local function sparkles(root: BasePart, color: Color3, rate: number)
	local p = Instance.new("ParticleEmitter")
	p.Name = "FF_Sparkle"
	p.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	p.LightEmission = 1
	p.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	p.Speed = NumberRange.new(1, 3)
	p.Lifetime = NumberRange.new(0.6, 1.2)
	p.SpreadAngle = Vector2.new(180, 180)
	p.Rate = rate
	p.Shape = Enum.ParticleEmitterShape.Box
	p.Parent = root -- parented to the part, Box emits across the package's whole volume
	return p
end

local function wisps(root: BasePart)
	local att = Instance.new("Attachment")
	att.Name = "FF_Wisps"
	att.Parent = root
	local p = Instance.new("ParticleEmitter")
	p.Color = ColorSequence.new(Color3.fromRGB(170, 255, 220))
	p.LightEmission = 0.6
	p.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	p.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 1.6) })
	p.Speed = NumberRange.new(0.5, 1.5)
	p.Acceleration = Vector3.new(0, 2, 0)
	p.Lifetime = NumberRange.new(1, 2)
	p.Rate = 6
	p.Parent = att
end

local function track(model: Model)
	if tracked[model] then
		return
	end
	local root = model:WaitForChild("Root", 5) :: BasePart?
	if not root or not model.Parent then
		return
	end
	local rarity = Rarities.byId[model:GetAttribute("Rarity") or "Common"] or Rarities.byId.Common
	local mutation = Mutations.byId[model:GetAttribute("Mutation") or "None"] or Mutations.byId.None
	local rank = Rarities.rank[rarity.id]

	if rank >= 3 or mutation.id ~= "None" then
		local h = Instance.new("Highlight")
		h.Name = "FF_Glow"
		h.FillTransparency = 1
		h.OutlineColor = if mutation.color and rank < 3 then mutation.color else rarity.color
		h.OutlineTransparency = if rank >= 5 then 0 else 0.25
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Adornee = model
		h.Parent = model
	end
	if rank >= 5 then
		sparkles(root, rarity.color, if rank >= 6 then 18 else 9)
	end
	if rank >= 2 or mutation.id ~= "None" then
		nameTag(model, root, rarity, mutation)
	end
	if mutation.haunted then
		wisps(root)
	end

	local entry: Tracked = {
		model = model,
		root = root,
		haunted = mutation.haunted == true,
		nextShove = os.clock() + 2,
	}
	if mutation.rainbow then
		local parts = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				table.insert(parts, d)
			end
		end
		entry.rainbowParts = parts
	end
	tracked[model] = entry
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			tracked[model] = nil
		end
	end)
end

function PackageFx.init()
	local folder = workspace:WaitForChild("Packages")
	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			task.spawn(track, child)
		end
	end)
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			task.spawn(track, child)
		end
	end

	local range = Mutations.HAUNTED_INTERVAL
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for model, entry in tracked do
			if entry.rainbowParts then
				local hue = (now * 0.25) % 1
				for i, part in entry.rainbowParts do
					part.Color = Color3.fromHSV((hue + i * 0.07) % 1, 0.75, 1)
				end
			end
			if entry.haunted and now >= entry.nextShove and model:GetAttribute("Holder") == player.UserId then
				entry.nextShove = now + range[1] + math.random() * (range[2] - range[1])
				local dir = Vector3.new(math.random() - 0.5, 0.5, math.random() - 0.5).Unit
				entry.root:ApplyImpulse(dir * Mutations.HAUNTED_IMPULSE * entry.root.AssemblyMass)
			end
		end
	end)
end

return PackageFx
