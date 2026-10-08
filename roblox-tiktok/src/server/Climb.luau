--!strict
-- Diamond Climb's tower, built once on startup from ClimbPath: a start island,
-- 1000 gem platforms spiralling up round a tall crystal pillar (a gold ring
-- round the pillar at every hundredth platform, which is bigger and
-- gold-rimmed), and the diamond turning over a gold platform at the top.
-- Every platform is solid and can be found by raycasts; its "ClimbIndex"
-- attribute says which it is. The pillar and trim are only for show.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("DiamondRush")
local ClimbPath = require(Shared:WaitForChild("ClimbPath"))
local DiamondShape = require(Shared:WaitForChild("DiamondShape"))

local Climb = {}

local GOLD = Color3.fromRGB(232, 186, 76)
local MARBLE = Color3.fromRGB(242, 240, 235)
local CRYSTAL = Color3.fromRGB(196, 230, 255)
Climb.DIAMOND_SIZE = 7
Climb.DIAMOND_HEIGHT = 9 -- above the top platform

export type Built = { model: Model, platforms: Folder, spawn: SpawnLocation, diamond: Model }

local function piece(parent: Instance, name: string, size: Vector3, frame: CFrame, colour: Color3, material: Enum.Material, solid: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = frame
	p.Color = colour
	p.Material = material
	p.Anchored = true
	p.CanCollide = solid == true
	p.CanQuery = solid == true
	p.CanTouch = false
	p.CastShadow = solid == true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A flat round slab whose top is at `top`.
local function disc(parent: Instance, name: string, centre: Vector3, top: number, diameter: number, height: number, colour: Color3, material: Enum.Material, solid: boolean?): Part
	local p = piece(parent, name, Vector3.new(height, diameter, diameter),
		CFrame.new(centre.X, top - height / 2, centre.Z) * CFrame.Angles(0, 0, math.pi / 2), colour, material, solid)
	p.Shape = Enum.PartType.Cylinder
	return p
end

function Climb.build(parent: Instance): Built
	local model = Instance.new("Model")
	model.Name = "DiamondClimb"
	model.Parent = parent
	local O = ClimbPath.ORIGIN
	local summit = ClimbPath.height(ClimbPath.TOP)

	-- The crystal pillar, in sections (a part can be at most 2048 studs long),
	-- with a gold ring at every hundredth platform's height.
	local pillarBottom, pillarTop = O.Y - 60, O.Y + summit + 30
	local sections = math.ceil((pillarTop - pillarBottom) / 400)
	for i = 0, sections - 1 do
		local a = pillarBottom + (pillarTop - pillarBottom) * i / sections
		local b = pillarBottom + (pillarTop - pillarBottom) * (i + 1) / sections
		local section = disc(model, "Pillar", O, b, 10, b - a, CRYSTAL, Enum.Material.Glass)
		section.Transparency = 0.2
		section.CastShadow = false
	end
	for n = ClimbPath.MILESTONE, ClimbPath.TOP, ClimbPath.MILESTONE do
		local y = O.Y + ClimbPath.height(n)
		local ring = disc(model, "PillarRing", O, y + 1, 12.5, 2, GOLD, Enum.Material.Foil)
		ring.CastShadow = false
		local glow = disc(model, "PillarGlow", O, y - 1.2, 11, 0.6, ClimbPath.colour(n), Enum.Material.Neon)
		glow.CastShadow = false
	end
	local cap = piece(model, "PillarCap", Vector3.new(6, 6, 6), CFrame.new(O + Vector3.new(0, summit + 33, 0)), GOLD, Enum.Material.Foil)
	cap.Shape = Enum.PartType.Ball

	-- The start island: a marble disc with a gold rim, over stepped tiers.
	local startTop = ClimbPath.top(0)
	disc(model, "StartIsland", startTop, startTop.Y, ClimbPath.START_SIZE, 3, MARBLE, Enum.Material.Marble, true):SetAttribute("ClimbIndex", 0)
	disc(model, "StartRim", startTop, startTop.Y - 0.6, ClimbPath.START_SIZE + 1, 1.2, GOLD, Enum.Material.Foil)
	disc(model, "StartTier", startTop, startTop.Y - 3, ClimbPath.START_SIZE - 3, 3, MARBLE, Enum.Material.Marble)
	disc(model, "StartTier", startTop, startTop.Y - 6, ClimbPath.START_SIZE - 8, 3, MARBLE, Enum.Material.Marble)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "ClimbStart"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Enabled = false
	spawn.Size = Vector3.new(6, 0.4, 6)
	spawn.CFrame = CFrame.new(startTop + Vector3.new(0, 0.2, 0))
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.CanTouch = false
	spawn.Parent = model

	-- The wall behind the start island: gifts that push past platform 0 hit it.
	local wall = piece(model, "ClimbWall", ClimbPath.WALL_SIZE, ClimbPath.wallFrame(), Color3.fromRGB(150, 132, 118), Enum.Material.Brick, true)
	wall.CanQuery = true
	piece(model, "WallCap", ClimbPath.WALL_SIZE + Vector3.new(0.6, 0, 0.6) - Vector3.new(0, ClimbPath.WALL_SIZE.Y - 0.8, 0),
		ClimbPath.wallFrame() * CFrame.new(0, ClimbPath.WALL_SIZE.Y / 2 + 0.4, 0), GOLD, Enum.Material.Foil)

	-- The platforms.
	local platforms = Instance.new("Folder")
	platforms.Name = "Platforms"
	platforms.Parent = model
	for n = 1, ClimbPath.TOP do
		local top = ClimbPath.top(n)
		local size = ClimbPath.size(n)
		local colour = ClimbPath.colour(n)
		local special = n % ClimbPath.MILESTONE == 0
		local platform = disc(platforms, "Platform", top, top.Y, size, ClimbPath.THICKNESS, if n == ClimbPath.TOP then GOLD else colour,
			if n == ClimbPath.TOP then Enum.Material.Foil else Enum.Material.SmoothPlastic, true)
		platform.Reflectance = if special then 0 else 0.08
		platform:SetAttribute("ClimbIndex", n)
		-- A glowing gem edge under it, gold on the milestones.
		local rim = disc(platform, "Rim", top, top.Y - ClimbPath.THICKNESS + 0.05, size + (if special then 1.4 else 0.7), if special then 0.6 else 0.35,
			if special then GOLD else colour, if special then Enum.Material.Foil else Enum.Material.Neon)
		rim.CastShadow = false
		if n % 50 == 0 then task.wait() end
	end

	-- The diamond over the top platform (each player's game turns it, see ClimbView).
	local finish = ClimbPath.top(ClimbPath.TOP)
	local gem = DiamondShape.build(Climb.DIAMOND_SIZE, "ClimbDiamond")
	local gemFrame = CFrame.new(finish + Vector3.new(0, Climb.DIAMOND_HEIGHT, 0))
	gem.model.Parent = model
	DiamondShape.place(gem, gemFrame)
	for _, facet in gem.parts do
		facet.CanCollide = false
		facet.CanQuery = false
		facet.CanTouch = false
	end
	gem.model:SetAttribute("Centre", gemFrame.Position)
	local core = piece(gem.model, "Core", Vector3.new(0.2, 0.2, 0.2), gemFrame, MARBLE, Enum.Material.SmoothPlastic)
	core.Transparency = 1
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(170, 230, 255)
	glow.Range = 28
	glow.Brightness = 2
	glow.Shadows = false
	glow.Parent = core
	-- Gold posts round the top platform, each with a glowing orb.
	for k = 0, 5 do
		local angle = k * math.pi / 3
		local ring = ClimbPath.size(ClimbPath.TOP) / 2 - 1.2
		local at = finish + Vector3.new(math.cos(angle) * ring, 0, math.sin(angle) * ring)
		-- Not solid, so they never block the last jump.
		piece(model, "FinishPost", Vector3.new(0.6, 3, 0.6), CFrame.new(at + Vector3.new(0, 1.5, 0)), GOLD, Enum.Material.Foil)
		local orb = piece(model, "FinishOrb", Vector3.new(1, 1, 1), CFrame.new(at + Vector3.new(0, 3.4, 0)), CRYSTAL, Enum.Material.Neon)
		orb.Shape = Enum.PartType.Ball
	end

	return { model = model, platforms = platforms, spawn = spawn, diamond = gem.model }
end

return Climb
