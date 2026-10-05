--!strict
-- A gold statue honouring a gifter: a Roblox figure raising a diamond high on
-- a marble pedestal, with an engraved brass plaque showing their name and
-- coins. Statues are placed from the streamer's settings panel and saved.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("DiamondRush")
local DiamondShape = require(Shared:WaitForChild("DiamondShape"))
local Format = require(Shared:WaitForChild("Format"))

local Statue = {}

export type Spec = { name: string, coins: number, position: Vector3, yaw: number }

local GOLD = Color3.fromRGB(236, 186, 58)
local MARBLE = Color3.fromRGB(228, 224, 216)
local PEDESTAL_HEIGHT = 6.6

local function piece(parent: Instance, name: string, size: Vector3, frame: CFrame, colour: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = frame
	p.Color = colour
	p.Material = material
	p.Anchored = true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then p.Shape = shape end
	if material == Enum.Material.Metal then p.Reflectance = 0.18 end
	p.Parent = parent
	return p
end

-- Builds the statue standing on the ground at spec.position, facing along yaw.
function Statue.build(parent: Instance, spec: Spec): Model
	local model = Instance.new("Model")
	model.Name = "GoldStatue"
	model.Parent = parent
	local base = CFrame.new(spec.position) * CFrame.Angles(0, spec.yaw, 0)

	-- Stepped marble pedestal with gold bands, on a foundation sunk into slopes.
	piece(model, "Foundation", Vector3.new(7.6, 3, 7.6), base * CFrame.new(0, -1.2, 0), MARBLE:Lerp(Color3.new(0, 0, 0), 0.18), Enum.Material.Marble)
	piece(model, "Plinth", Vector3.new(7.2, 1, 7.2), base * CFrame.new(0, 0.5, 0), MARBLE:Lerp(Color3.new(0, 0, 0), 0.08), Enum.Material.Marble)
	piece(model, "Step", Vector3.new(6.2, 0.8, 6.2), base * CFrame.new(0, 1.4, 0), MARBLE, Enum.Material.Marble)
	piece(model, "Column", Vector3.new(5, 4, 5), base * CFrame.new(0, 3.8, 0), MARBLE, Enum.Material.Marble)
	piece(model, "Cap", Vector3.new(6.2, 0.8, 6.2), base * CFrame.new(0, 6.2, 0), MARBLE, Enum.Material.Marble)
	for _, y in { 2.05, 5.55 } do
		piece(model, "GoldBand", Vector3.new(5.2, 0.25, 5.2), base * CFrame.new(0, y, 0), GOLD, Enum.Material.Metal)
	end

	-- The figure: blocky Roblox proportions at 1.6x scale, right arm raised.
	local figure = base * CFrame.new(0, PEDESTAL_HEIGHT, 0)
	for _, side in { -1, 1 } do
		piece(model, "Leg", Vector3.new(1.55, 3.2, 1.55), figure * CFrame.new(side * 0.8, 1.6, 0), GOLD, Enum.Material.Metal)
	end
	piece(model, "Torso", Vector3.new(3.2, 3.2, 1.6), figure * CFrame.new(0, 4.8, 0), GOLD, Enum.Material.Metal)
	piece(model, "Head", Vector3.new(2.3, 2.3, 2.3), figure * CFrame.new(0, 7.55, 0), GOLD, Enum.Material.Metal, Enum.PartType.Ball)
	-- Cylinders run along X: stand the neck upright.
	piece(model, "Neck", Vector3.new(0.5, 1.1, 1.1), figure * CFrame.new(0, 6.5, 0) * CFrame.Angles(0, 0, math.pi / 2), GOLD, Enum.Material.Metal, Enum.PartType.Cylinder)
	piece(model, "Arm", Vector3.new(1.55, 3.2, 1.55), figure * CFrame.new(-2.4, 4.8, 0) * CFrame.Angles(0, 0, math.rad(-6)), GOLD, Enum.Material.Metal)
	-- The raised arm pivots at the shoulder and leans slightly outward.
	local tilt = math.rad(-14)
	local shoulder = figure * CFrame.new(2.4, 5.6, 0)
	local up = shoulder * CFrame.Angles(0, 0, tilt)
	piece(model, "RaisedArm", Vector3.new(1.55, 3.2, 1.55), up * CFrame.new(0, 1.6, 0), GOLD, Enum.Material.Metal)

	-- A real diamond held aloft, with a gentle sparkle.
	local gem = DiamondShape.build(1.9, "HeldDiamond")
	gem.model.Parent = model
	-- Upright in the world despite the leaning arm, resting point-down in the hand.
	DiamondShape.place(gem, up * CFrame.new(0, 4.25, 0) * CFrame.Angles(0, 0, -tilt) * CFrame.Angles(0, math.rad(22.5), 0))
	local sparkleAt = Instance.new("Attachment")
	sparkleAt.Position = Vector3.new(0, 2.6, 0)
	sparkleAt.Parent = model:FindFirstChild("RaisedArm")
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(160, 235, 255))
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Transparency = NumberSequence.new(0.1, 1)
	sparkles.Lifetime = NumberRange.new(0.5, 1)
	sparkles.Rate = 4
	sparkles.Speed = NumberRange.new(0.4, 1.2)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Parent = sparkleAt

	-- The plaque: a brass plate in a dark frame on the front of the column.
	piece(model, "PlaqueFrame", Vector3.new(4.4, 2.9, 0.2), base * CFrame.new(0, 3.8, -2.55), Color3.fromRGB(70, 48, 28), Enum.Material.Wood)
	local plate = piece(model, "Plaque", Vector3.new(4, 2.5, 0.2), base * CFrame.new(0, 3.8, -2.7), Color3.fromRGB(214, 170, 76), Enum.Material.Metal)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0.6
	gui.Parent = plate
	local function engrave(text: string, y: number, height: number, font: Enum.Font)
		local line = Instance.new("TextLabel")
		line.BackgroundTransparency = 1
		line.Size = UDim2.fromScale(0.9, height)
		line.Position = UDim2.fromScale(0.05, y)
		line.Font = font
		line.TextScaled = true
		line.TextColor3 = Color3.fromRGB(58, 38, 18)
		line.Text = text
		line.Parent = gui
	end
	engrave("★  IN HONOUR OF  ★", 0.06, 0.16, Enum.Font.GothamBold)
	engrave(spec.name, 0.25, 0.42, Enum.Font.FredokaOne)
	engrave(Format.commas(spec.coins) .. " COINS", 0.7, 0.22, Enum.Font.GothamBold)
	return model
end

-- Which saved statue ({ x, z } on the ground) stands nearest to `position`,
-- within `reach` studs across the ground; nil if none is that close.
function Statue.nearest(statues: { { x: number, z: number } }, position: Vector3, reach: number): number?
	local best, bestDistance = nil, reach
	for index, statue in statues do
		local distance = math.sqrt((statue.x - position.X) ^ 2 + (statue.z - position.Z) ^ 2)
		if distance <= bestDistance then
			best, bestDistance = index, distance
		end
	end
	return best
end

return Statue
