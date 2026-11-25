-- Crate-open reveal (GDD §4.1): a crate appears in front of you, shakes, bursts open in the
-- rarity color, and the rarity name slams onto the screen. Purely local; the server already
-- decided the roll and spawns the package when the reveal ends.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Theme = require(script.Parent.Theme)

local Reveal = {}

local player = Players.LocalPlayer
local gui: ScreenGui

local function crateParts(at: CFrame): (Model, BasePart, BasePart)
	local model = Instance.new("Model")
	model.Name = "RevealCrate"
	local box = Instance.new("Part")
	box.Size = Vector3.new(3, 2.4, 3)
	box.CFrame = at
	box.Material = Enum.Material.WoodPlanks
	box.Color = Color3.fromRGB(176, 128, 78)
	box.Anchored = true
	box.CanCollide = false
	box.CanQuery = false
	box.Parent = model
	for _, x in { -1, 1 } do
		local band = Instance.new("Part")
		band.Size = Vector3.new(0.3, 2.5, 3.1)
		band.CFrame = at * CFrame.new(x * 1.1, 0, 0)
		band.Material = Enum.Material.Metal
		band.Color = Color3.fromRGB(90, 90, 100)
		band.Anchored = true
		band.CanCollide = false
		band.CanQuery = false
		band.Parent = model
	end
	local lid = Instance.new("Part")
	lid.Size = Vector3.new(3.2, 0.4, 3.2)
	lid.CFrame = at * CFrame.new(0, 1.4, 0)
	lid.Material = Enum.Material.WoodPlanks
	lid.Color = Color3.fromRGB(150, 105, 60)
	lid.Anchored = true
	lid.CanCollide = false
	lid.CanQuery = false
	lid.Parent = model
	model.Parent = workspace
	return model, box, lid
end

local function burst(at: Vector3, color: Color3, big: boolean)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.Position = at
	holder.Parent = workspace

	local att = Instance.new("Attachment")
	att.Parent = holder
	local p = Instance.new("ParticleEmitter")
	p.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	p.LightEmission = 1
	p.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	p.Speed = NumberRange.new(14, if big then 34 else 22)
	p.Lifetime = NumberRange.new(0.5, 1)
	p.SpreadAngle = Vector2.new(180, 180)
	p.Drag = 3
	p.Rate = 0
	p.Parent = att
	p:Emit(if big then 120 else 50)

	-- Expanding flash sphere
	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = color
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.Size = Vector3.one * 1
	flash.Position = at
	flash.Transparency = 0.1
	flash.Parent = workspace
	TweenService:Create(flash, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * (if big then 14 else 8),
		Transparency = 1,
	}):Play()

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 18
	light.Brightness = 4
	light.Parent = holder
	TweenService:Create(light, TweenInfo.new(0.8), { Brightness = 0 }):Play()

	Debris:AddItem(flash, 0.5)
	Debris:AddItem(holder, 1.5)
end

local function banner(rarity: Rarities.RarityDef, mutation: Mutations.MutationDef, packageName: string, pityUsed: boolean)
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.3)
	frame.Size = UDim2.fromScale(0.6, 0.2)
	frame.Parent = gui

	local scale = Instance.new("UIScale")
	scale.Scale = 2.2
	scale.Parent = frame

	local title = Theme.label(frame, {
		Size = UDim2.fromScale(1, 0.55),
		Text = string.upper(rarity.displayName) .. "!",
		TextColor3 = rarity.color,
	})
	Theme.stroke(title, Color3.new(0, 0, 0), 4)

	local subText = packageName
	if mutation.displayName ~= "" then
		subText = mutation.displayName .. " " .. subText
	end
	if pityUsed then
		subText ..= "  (pity!)"
	end
	local sub = Theme.label(frame, {
		Size = UDim2.fromScale(1, 0.35),
		Position = UDim2.fromScale(0, 0.6),
		Text = subText,
		TextColor3 = mutation.color or Theme.TEXT,
	})
	Theme.stroke(sub, Color3.new(0, 0, 0), 3)

	if mutation.rainbow then
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 60)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 255, 120)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 160, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 90, 255)),
		})
		g.Parent = sub
		TweenService:Create(g, TweenInfo.new(1.5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Offset = Vector2.new(1, 0) }):Play()
	end

	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(1.6, function()
		TweenService:Create(title, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		TweenService:Create(sub, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		task.wait(0.45)
		frame:Destroy()
	end)
end

local function shakeCamera(strength: number, duration: number)
	local camera = workspace.CurrentCamera
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not camera or not humanoid then
		return
	end
	local t0 = os.clock()
	task.spawn(function()
		while os.clock() - t0 < duration do
			local k = 1 - (os.clock() - t0) / duration
			humanoid.CameraOffset = Vector3.new(
				(math.random() - 0.5) * strength * k,
				(math.random() - 0.5) * strength * k,
				0
			)
			task.wait()
		end
		humanoid.CameraOffset = Vector3.zero
	end)
end

Reveal.shakeCamera = shakeCamera

function Reveal.play(info: { rarity: string, mutation: string, displayName: string, pityUsed: boolean, duration: number })
	local rarity = Rarities.byId[info.rarity] or Rarities.byId.Common
	local mutation = Mutations.byId[info.mutation] or Mutations.byId.None
	local rank = Rarities.rank[rarity.id]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local at = root.CFrame * CFrame.new(0, 0.2, -3.5)
	local model, box, lid = crateParts(at)
	local openAt = math.max(info.duration - 0.55, 0.3)

	-- Shake harder the rarer it is (the crate "knows").
	local t0 = os.clock()
	task.spawn(function()
		while os.clock() - t0 < openAt and model.Parent do
			local k = (os.clock() - t0) / openAt
			local amp = (0.05 + 0.04 * rank) * (0.4 + k)
			local jitter = CFrame.new((math.random() - 0.5) * amp * 2, 0, (math.random() - 0.5) * amp * 2)
				* CFrame.Angles(0, 0, (math.random() - 0.5) * amp * 0.6)
			for _, part in model:GetChildren() do
				if part:IsA("BasePart") then
					local base = part:GetAttribute("Base") :: CFrame?
					if not base then
						base = part.CFrame
						part:SetAttribute("Base", base)
					end
					part.CFrame = at * jitter * (at:Inverse() * base)
				end
			end
			task.wait()
		end
	end)

	task.delay(openAt, function()
		TweenService:Create(lid, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = lid.CFrame * CFrame.new(0, 6, -2) * CFrame.Angles(math.rad(-120), 0, math.rad(25)),
			Transparency = 1,
		}):Play()
		burst(box.Position + Vector3.new(0, 1, 0), rarity.color, rank >= 4)
		banner(rarity, mutation, info.displayName, info.pityUsed)
		if rank >= 4 then
			shakeCamera(0.15 + 0.08 * (rank - 4), 0.4)
		end
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") and part ~= lid then
				TweenService:Create(part, TweenInfo.new(0.4), { Transparency = 1 }):Play()
			end
		end
		Debris:AddItem(model, 0.6)
	end)
end

function Reveal.init(parentGui: ScreenGui)
	gui = parentGui
end

return Reveal
