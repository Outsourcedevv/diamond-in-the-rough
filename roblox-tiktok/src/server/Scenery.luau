--!strict
-- Scenery around the mountain: rolling grassy hills, a ring of snowy peaks in
-- the distance, a lake, pine forest, boulders, a dirt path, clouds and a
-- campfire at the camp. Built once with Terrain and a few hundred parts.
local Lighting = game:GetService("Lighting")

local Scenery = {}

local random = Random.new(4207)

local function avoid(position: Vector3, keepClear: { { centre: Vector3, radius: number } }): boolean
	for _, zone in keepClear do
		local flat = Vector3.new(position.X - zone.centre.X, 0, position.Z - zone.centre.Z)
		if flat.Magnitude < zone.radius then
			return true
		end
	end
	return false
end

local function part(parent: Instance, size: Vector3, cframe: CFrame, colour: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = colour
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

-- A low-poly pine: a trunk and four stacked, shrinking, turned tiers.
local function pine(parent: Instance, base: Vector3, height: number)
	local tree = Instance.new("Model")
	tree.Name = "Pine"
	local trunkHeight = height * 0.28
	part(tree, Vector3.new(trunkHeight, height * 0.08, height * 0.08), CFrame.new(base + Vector3.new(0, trunkHeight / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(96, 66, 42), Enum.Material.Wood, Enum.PartType.Cylinder)
	local greens = { Color3.fromRGB(46, 92, 58), Color3.fromRGB(56, 106, 66), Color3.fromRGB(40, 82, 52) }
	for tier = 0, 3 do
		local width = height * (0.55 - tier * 0.12)
		local y = trunkHeight + tier * height * 0.17
		part(tree, Vector3.new(width, height * 0.2, width), CFrame.new(base + Vector3.new(0, y + height * 0.1, 0)) * CFrame.Angles(0, math.rad(45 * tier + random:NextNumber(0, 30)), 0), greens[random:NextInteger(1, #greens)], Enum.Material.Grass)
	end
	tree.Parent = parent
end

function Scenery.build(mountainRadius: number, spawnPosition: Vector3)
	local terrain = workspace.Terrain
	local folder = Instance.new("Folder")
	folder.Name = "Scenery"

	-- Places that must stay clear: the mountain, the camp and the walk between.
	local keepClear = {
		{ centre = Vector3.zero, radius = mountainRadius + 14 },
		{ centre = spawnPosition, radius = 22 },
		{ centre = spawnPosition * 0.5, radius = 14 },
	}

	-- Ground and a dirt path from the camp to the foot of the mountain.
	terrain:FillBlock(CFrame.new(0, -6, 0), Vector3.new(1600, 12, 1600), Enum.Material.Grass)
	local pathLength = (spawnPosition - Vector3.zero).Magnitude - mountainRadius
	terrain:FillBlock(CFrame.lookAt(Vector3.new(0, -0.5, 0), Vector3.new(spawnPosition.X, -0.5, spawnPosition.Z)) * CFrame.new(0, 0, -(mountainRadius + pathLength / 2)), Vector3.new(6, 1, pathLength + 6), Enum.Material.Ground)

	-- Rolling hills beyond the forest.
	for _ = 1, 26 do
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(150, 330)
		local radius = random:NextNumber(30, 60)
		local centre = Vector3.new(math.cos(angle) * distance, -radius * 0.65, math.sin(angle) * distance)
		if not avoid(centre, keepClear) then
			terrain:FillBall(centre, radius, Enum.Material.Grass)
		end
	end

	-- A ring of big snowy peaks on the horizon.
	for index = 1, 11 do
		local angle = index / 11 * math.pi * 2 + random:NextNumber(-0.2, 0.2)
		local distance = random:NextNumber(470, 560)
		local height = random:NextNumber(120, 210)
		local base = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local width = height * 0.75
		for layer = 0, 7 do
			local t = layer / 8
			local radius = width * (1 - t)
			local material = if t > 0.55 then Enum.Material.Snow elseif t > 0.3 then Enum.Material.Slate else Enum.Material.Rock
			terrain:FillBall(base + Vector3.new(0, t * height, 0), math.max(radius, 8), material)
		end
	end

	-- A small lake to one side of the camp.
	local lake = Vector3.new(spawnPosition.X + 70, 0, spawnPosition.Z * 0.2 + 10)
	terrain:FillBlock(CFrame.new(lake + Vector3.new(0, -3, 0)), Vector3.new(56, 6, 40), Enum.Material.Air)
	terrain:FillBlock(CFrame.new(lake + Vector3.new(0, -3.5, 0)), Vector3.new(56, 5, 40), Enum.Material.Water)
	terrain:FillBlock(CFrame.new(lake + Vector3.new(0, -6.5, 0)), Vector3.new(60, 1, 44), Enum.Material.Sand)
	table.insert(keepClear, { centre = lake, radius = 36 })

	-- Pine forest, thickest a little away from the mountain.
	local planted = 0
	local attempts = 0
	while planted < 170 and attempts < 2000 do
		attempts += 1
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(mountainRadius + 22, 260)
		local base = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		if not avoid(base, keepClear) then
			pine(folder, base, random:NextNumber(14, 28))
			planted += 1
		end
	end

	-- Boulders scattered on the grass.
	for _ = 1, 45 do
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(mountainRadius + 16, 220)
		local centre = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		if not avoid(centre, keepClear) then
			terrain:FillBall(centre, random:NextNumber(2, 5.5), if random:NextNumber() < 0.5 then Enum.Material.Rock else Enum.Material.Slate)
		end
	end

	-- A campfire with logs to sit on at the camp.
	local fireAt = spawnPosition + Vector3.new(10, 0, 4)
	for index = 0, 5 do
		local angle = index / 6 * math.pi * 2
		part(folder, Vector3.new(0.6, 0.6, 3), CFrame.new(fireAt + Vector3.new(math.cos(angle) * 1.6, 0.3, math.sin(angle) * 1.6)) * CFrame.Angles(0, -angle, 0) * CFrame.Angles(math.rad(25), 0, 0), Color3.fromRGB(110, 74, 46), Enum.Material.Wood)
	end
	local embers = part(folder, Vector3.new(1.2, 0.4, 1.2), CFrame.new(fireAt + Vector3.new(0, 0.2, 0)), Color3.fromRGB(255, 140, 40), Enum.Material.Neon)
	embers.CanCollide = false
	local fire = Instance.new("Fire")
	fire.Size = 5
	fire.Heat = 9
	fire.Parent = embers
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 160, 80)
	glow.Range = 18
	glow.Brightness = 2
	glow.Parent = embers
	for _, offset in { Vector3.new(4, 0.6, 0), Vector3.new(-4, 0.6, 0), Vector3.new(0, 0.6, 4.5) } do
		part(folder, Vector3.new(5, 1.2, 1.2), CFrame.new(fireAt + offset) * CFrame.Angles(0, math.atan2(offset.X, offset.Z) + math.pi / 2, math.rad(90)), Color3.fromRGB(120, 82, 52), Enum.Material.Wood, Enum.PartType.Cylinder)
	end

	-- Clouds and a softer sky.
	if terrain:FindFirstChildOfClass("Clouds") == nil then
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.55
		clouds.Density = 0.6
		clouds.Parent = terrain
	end
	terrain.WaterColor = Color3.fromRGB(60, 130, 160)
	terrain.WaterTransparency = 0.6
	if Lighting:FindFirstChildOfClass("Sky") == nil then
		local sky = Instance.new("Sky")
		sky.SunAngularSize = 14
		sky.Parent = Lighting
	end

	folder.Parent = workspace
end

return Scenery
