--!strict
-- An alpine valley around the mountain arena, built once on startup: rolling
-- meadows, forested hills, a lake, a ring of snow-capped peaks and a log-cabin
-- mining camp. Decorative parts never take part in mining raycasts or touch
-- events, and the central arena stays clear and flat for mountain growth.
--
-- Natural shapes come from smooth terrain (hills, peaks, boulders) and
-- low-poly wedge geometry (trees), not plastic balls. The look relies on the
-- place's Future lighting and 2022 materials (see default.project.json).
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PartShapes = require(ReplicatedStorage:WaitForChild("DiamondRush"):WaitForChild("PartShapes"))

local Scenery = {}
local random = Random.new(4207)

local function piece(parent: Instance, name: string, size: Vector3, frame: CFrame, colour: Color3, material: Enum.Material, kind: string?): BasePart
	local p = Instance.new(kind or "Part") :: BasePart
	p.Name = name
	p.Size = size
	p.CFrame = frame
	p.Color = colour
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function solid(p: BasePart): BasePart
	p.CanCollide = true
	return p
end

-- A cylinder between two points.
local function beam(parent: Instance, name: string, a: Vector3, b: Vector3, width: number, colour: Color3, material: Enum.Material): BasePart
	local delta = b - a
	local p = piece(parent, name, Vector3.new(delta.Magnitude, width, width), CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0), colour, material)
	local cylinder = p :: Part
	cylinder.Shape = Enum.PartType.Cylinder
	return p
end

local function shade(colour: Color3, amount: number): Color3
	return Color3.new(math.clamp(colour.R * amount, 0, 1), math.clamp(colour.G * amount, 0, 1), math.clamp(colour.B * amount, 0, 1))
end

local function lantern(parent: Instance, at: Vector3)
	piece(parent, "LanternPost", Vector3.new(0.3, 5, 0.3), CFrame.new(at + Vector3.new(0, 2.5, 0)), Color3.fromRGB(78, 62, 48), Enum.Material.Wood)
	piece(parent, "LanternArm", Vector3.new(0.9, 0.18, 0.18), CFrame.new(at + Vector3.new(0.45, 4.9, 0)), Color3.fromRGB(42, 44, 46), Enum.Material.Metal)
	piece(parent, "LanternCap", Vector3.new(0.7, 0.16, 0.7), CFrame.new(at + Vector3.new(0.85, 4.75, 0)), Color3.fromRGB(42, 44, 46), Enum.Material.Metal)
	local lamp = piece(parent, "WarmLantern", Vector3.new(0.42, 0.55, 0.42), CFrame.new(at + Vector3.new(0.85, 4.38, 0)), Color3.fromRGB(255, 196, 118), Enum.Material.Neon)
	lamp.CastShadow = false
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 120)
	light.Range = 14
	light.Brightness = 0.9
	light.Shadows = false
	light.Parent = lamp
end

-- A low-poly conifer: a trunk and stacked hexagonal cones, each cone six
-- wedges sloping outward. Higher trees carry snow on their top tier.
local function conifer(parent: Instance, at: Vector3, height: number, snowy: boolean)
	local model = Instance.new("Model")
	model.Name = "Conifer"
	model.Parent = parent
	local yaw = random:NextNumber(0, math.pi)
	beam(model, "Trunk", at - Vector3.new(0, 0.6, 0), at + Vector3.new(0, height * 0.55, 0), height * 0.05, Color3.fromRGB(84, 62, 44), Enum.Material.Wood)
	local tone = random:NextInteger(-6, 8)
	local needles = Color3.fromRGB(44 + tone, 80 + tone, 50 + tone)
	local skirt = height * 0.22
	for tier = 1, 3 do
		local t = (tier - 1) / 3
		local base = skirt + (height - skirt) * t * 0.78
		local tall = (height - skirt) * (0.5 - t * 0.12)
		local radius = height * (0.32 - t * 0.15)
		local width = 2 * radius * math.tan(math.pi / 6) * 1.06
		local top = tier == 3 and snowy
		local colour = if top then Color3.fromRGB(226, 233, 240) else shade(needles, 0.92 + tier * 0.06)
		for k = 0, 5 do
			local angle = yaw + tier * math.pi / 6 + k * math.pi / 3
			local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local centre = at + Vector3.new(0, base + tall / 2, 0) + direction * (radius / 2)
			piece(model, "Needles", Vector3.new(width, tall, radius), CFrame.new(centre) * PartShapes.wedgeToward(direction), colour,
				if top then Enum.Material.Snow else Enum.Material.LeafyGrass, "WedgePart")
		end
	end
end

-- A faceted broadleaf canopy: a hexagonal cone over an inverted one.
local function canopy(parent: Instance, centre: Vector3, radius: number, colour: Color3, yaw: number)
	local width = 2 * radius * math.tan(math.pi / 6) * 1.06
	local up, down = radius * 0.7, radius * 0.45
	for k = 0, 5 do
		local angle = yaw + k * math.pi / 3
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local rotation = PartShapes.wedgeToward(direction)
		piece(parent, "Leaves", Vector3.new(width, up, radius), CFrame.new(centre + Vector3.new(0, up / 2, 0) + direction * (radius / 2)) * rotation, colour, Enum.Material.LeafyGrass, "WedgePart")
		-- Flipped about its slope direction, the same wedge forms the underside.
		local under = CFrame.new(centre - Vector3.new(0, down / 2, 0) + direction * (radius / 2)) * CFrame.fromAxisAngle(direction, math.pi) * rotation
		piece(parent, "Leaves", Vector3.new(width, down, radius), under, shade(colour, 0.82), Enum.Material.LeafyGrass, "WedgePart")
	end
end

local function birch(parent: Instance, at: Vector3, height: number)
	local model = Instance.new("Model")
	model.Name = "Birch"
	model.Parent = parent
	local lean = Vector3.new(random:NextNumber(-0.6, 0.6), 0, random:NextNumber(-0.6, 0.6))
	local top = at + Vector3.new(0, height * 0.72, 0) + lean
	beam(model, "Trunk", at - Vector3.new(0, 0.5, 0), top, height * 0.055, Color3.fromRGB(214, 210, 196), Enum.Material.Wood)
	local tone = random:NextInteger(-8, 10)
	local leaves = Color3.fromRGB(116 + tone, 146 + tone, 62 + tone)
	canopy(model, top + Vector3.new(0, height * 0.05, 0), height * 0.32, leaves, random:NextNumber(0, math.pi))
	if random:NextNumber() < 0.6 then
		local side = Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1)).Unit * height * 0.18
		canopy(model, top + side - Vector3.new(0, height * 0.12, 0), height * 0.2, shade(leaves, 1.06), random:NextNumber(0, math.pi))
	end
end

-- Terrain height (studs) at a point, before the arena, camp, lake and path are cut in.
local function hillHeight(x: number, z: number, radius: number): number
	local distance = math.sqrt(x * x + z * z)
	local fade = math.clamp((distance - radius) / 60, 0, 1)
	fade = fade * fade * (3 - 2 * fade)
	local hills = math.noise(x / 140, z / 140, 12) * 22 + math.noise(x / 52, z / 52, 8) * 7 + math.noise(x / 19, z / 19, 4) * 1.4
	-- A ring of sharp ridged peaks closes the valley.
	local ring = math.clamp((distance - 200) / 150, 0, 1)
	ring = ring * ring * (3 - 2 * ring)
	local ridged = 1 - math.abs(math.noise(x / 95, z / 95, 17)) * 2
	local peaks = ring * (50 + ridged * 75 + math.noise(x / 41, z / 41, 23) * 16)
	return fade * (8 + hills) + peaks
end

export type Site = { radius: number, camp: Vector3, lake: Vector3 }

local function terrainHeight(x: number, z: number, site: Site): number
	local radius, camp, lake = site.radius, site.camp, site.lake
	local distance = math.sqrt(x * x + z * z)
	if distance < radius then return 0 end
	local height = hillHeight(x, z, radius)
	local campDistance = math.sqrt((x - camp.X) ^ 2 + (z - camp.Z) ^ 2)
	height *= math.clamp((campDistance - 27) / 22, 0, 1)
	local shore = math.sqrt(((x - lake.X) / 35) ^ 2 + ((z - lake.Z) / 27) ^ 2) + math.noise(x / 16, z / 16, 3) * 0.08
	if shore < 1.25 then height = math.min(height, -9 + math.clamp(shore, 0, 1.25) ^ 3 * 8) end
	return height
end

local function onPath(x: number, z: number, site: Site): boolean
	local camp = site.camp
	local pathX = math.sin(math.clamp((camp.Z - z) / (camp.Z - 26), 0, 1) * math.pi) * 4
	return z >= 26 and z <= camp.Z + 5 and math.abs(x - pathX) < 3.3 + math.noise(z / 7, 0, 3) * 0.8
end

local EXTENT = 384 -- terrain reaches this far from the mountain in every direction
local FLOOR, CEILING = -24, 184

local function landscape(terrain: Terrain, site: Site)
	-- Smooth connected terrain in 64-stud voxel chunks, written once on startup.
	-- Materials follow height and slope: snow above the snowline, rock on steep
	-- faces, alpine scrub, grass meadows with leafy patches, dirt paths.
	local resolution = 4
	local layers = (CEILING - FLOOR) // resolution
	for cx = -EXTENT, EXTENT - 1, 64 do
		for cz = -EXTENT, EXTENT - 1, 64 do
			local materials, occupancies = {}, {}
			for ix = 1, 16 do
				materials[ix] = {}
				occupancies[ix] = {}
				for iy = 1, layers do
					materials[ix][iy] = {}
					occupancies[ix][iy] = {}
				end
				for iz = 1, 16 do
					local x, z = cx + (ix - 0.5) * 4, cz + (iz - 0.5) * 4
					local distance = math.sqrt(x * x + z * z)
					local height = terrainHeight(x, z, site)
					local slope = math.sqrt((terrainHeight(x + 3, z, site) - terrainHeight(x - 3, z, site)) ^ 2
						+ (terrainHeight(x, z + 3, site) - terrainHeight(x, z - 3, site)) ^ 2) / 6
					local campDistance = math.sqrt((x - site.camp.X) ^ 2 + (z - site.camp.Z) ^ 2)
					local shore = math.sqrt(((x - site.lake.X) / 35) ^ 2 + ((z - site.lake.Z) / 27) ^ 2) + math.noise(x / 16, z / 16, 3) * 0.08
					local snowLine = 98 + math.noise(x / 60, z / 60, 31) * 22
					local patch = math.noise(x / 30, z / 30, 41)
					local surface
					if distance < site.radius then
						surface = Enum.Material.LeafyGrass
					elseif shore < 1.08 then
						surface = Enum.Material.Mud
					elseif shore < 1.2 or onPath(x, z, site) or campDistance < 10 then
						surface = Enum.Material.Ground
					elseif height > snowLine and slope < 1.3 then
						surface = Enum.Material.Snow
					elseif slope > 0.95 or height > snowLine + 18 then
						surface = Enum.Material.Rock
					elseif slope > 0.6 then
						surface = if patch > 0 then Enum.Material.Rock else Enum.Material.Ground
					elseif height > 72 then
						surface = if patch > 0.15 then Enum.Material.Rock elseif patch > -0.1 then Enum.Material.Ground else Enum.Material.Grass
					else
						surface = if patch > 0.22 then Enum.Material.LeafyGrass else Enum.Material.Grass
					end
					for iy = 1, layers do
						local y = FLOOR + (iy - 0.5) * resolution
						local occupancy = math.clamp((height - y) / 4 + 0.5, 0, 1)
						local material = if y < height - 5 then Enum.Material.Rock else surface
						if shore < 1.12 and y > height and y < 1 then
							local water = math.clamp((-1 - y) / 4 + 0.5, 0, 1)
							if water > occupancy then
								material = Enum.Material.Water
								occupancy = water
							end
						end
						materials[ix][iy][iz] = if occupancy > 0 then material else Enum.Material.Air
						occupancies[ix][iy][iz] = occupancy
					end
				end
			end
			terrain:WriteVoxels(Region3.new(Vector3.new(cx, FLOOR, cz), Vector3.new(cx + 64, CEILING, cz + 64)), resolution, materials, occupancies)
			task.wait()
		end
	end
end

-- `reserved` keeps trees and boulders out of circles (the leaderboards stand there).
function Scenery.build(mountainRadius: number, spawnPosition: Vector3, reserved: { { at: Vector3, radius: number } }?)
	-- Animated grass is enabled in the place/project: Decoration and GrassLength
	-- are editor-only properties. LeafyGrass keeps the central arena blade-free.
	local terrain = workspace.Terrain
	local folder = Instance.new("Folder")
	folder.Name = "Scenery"
	folder.Parent = workspace
	local clearRadius = math.max(mountainRadius + 14, 55)
	local camp = Vector3.new(spawnPosition.X, 0, spawnPosition.Z)
	local lake = Vector3.new(clearRadius + 72, 0, camp.Z + 15)
	local site: Site = { radius = clearRadius, camp = camp, lake = lake }
	local keepClear: { { at: Vector3, radius: number } } = reserved or {}
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { terrain }
	local function ground(x: number, z: number): Vector3
		local hit = workspace:Raycast(Vector3.new(x, CEILING + 20, z), Vector3.new(0, -(CEILING + 60), 0), params)
		return if hit then hit.Position else Vector3.new(x, 0, z)
	end
	local function clear(at: Vector3, margin: number): boolean
		local flat = Vector3.new(at.X, 0, at.Z)
		return flat.Magnitude < clearRadius + margin
			or (flat - camp).Magnitude < 25 + margin
			or (flat - lake).Magnitude < 40 + margin
			or onPath(at.X, at.Z, site)
			or (function()
				for _, spot in keepClear do
					if (flat - Vector3.new(spot.at.X, 0, spot.at.Z)).Magnitude < spot.radius + margin then return true end
				end
				return false
			end)()
	end
	local function steepness(x: number, z: number): number
		return math.abs(terrainHeight(x + 3, z, site) - terrainHeight(x - 3, z, site)) / 6
			+ math.abs(terrainHeight(x, z + 3, site) - terrainHeight(x, z - 3, site)) / 6
	end

	terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(102, 126, 64))
	terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(86, 110, 56))
	terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(112, 94, 70))
	terrain:SetMaterialColor(Enum.Material.Mud, Color3.fromRGB(84, 72, 58))
	terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(116, 116, 112))
	terrain:SetMaterialColor(Enum.Material.Snow, Color3.fromRGB(238, 242, 247))
	terrain:FillBlock(CFrame.new(0, -8, 0), Vector3.new(EXTENT * 4, 16, EXTENT * 4), Enum.Material.Grass)
	landscape(terrain, site)
	terrain.WaterColor = Color3.fromRGB(46, 92, 96)
	terrain.WaterTransparency = 0.62
	terrain.WaterReflectance = 0.45
	terrain.WaterWaveSize = 0.06
	terrain.WaterWaveSpeed = 4

	-- Weathered boulders and outcrops are smooth terrain rock, half buried.
	local boulders = 0
	for _ = 1, 400 do
		if boulders >= 34 then break end
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(clearRadius + 10, 230)
		local at = ground(math.cos(angle) * distance, math.sin(angle) * distance)
		if not clear(at, 4) and at.Y < 90 then
			local size = random:NextNumber(2.6, if distance > 140 then 7.5 else 4.5)
			for i = 1, random:NextInteger(1, 3) do
				local offset = Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1)) * size * 0.8
				terrain:FillBall(at + offset - Vector3.new(0, size * 0.35, 0), size * (1 - i * 0.18), Enum.Material.Rock)
			end
			boulders += 1
		end
	end

	-- A lakeside timber dock, supported above the shallow water.
	local dock = lake + Vector3.new(-34, 0.5, 0)
	for i = 0, 11 do
		solid(piece(folder, "DockPlank", Vector3.new(1.55, 0.3, 7), CFrame.new(dock + Vector3.new(i * 1.62, 0, 0)) * CFrame.Angles(0, 0, math.rad(random:NextNumber(-1, 1))), shade(Color3.fromRGB(134, 104, 74), 0.92 + (i % 3) * 0.05), Enum.Material.WoodPlanks))
	end
	for _, x in { 0, 8, 16 } do
		for _, z in { -3.2, 3.2 } do
			beam(folder, "DockPost", dock + Vector3.new(x, -4.5, z), dock + Vector3.new(x, 1.1, z), 0.55, Color3.fromRGB(80, 66, 52), Enum.Material.Wood)
		end
	end
	lantern(folder, dock + Vector3.new(0, 0, -4.2))

	-- Forests grow in clumps on the hills, thinning out towards the treeline.
	local trees: { Vector3 } = {}
	local function spaced(at: Vector3, gap: number): boolean
		for _, other in trees do
			if (at - other).Magnitude < gap then return false end
		end
		return true
	end
	local conifers = 0
	for attempt = 1, 2400 do
		if conifers >= 120 then break end
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(clearRadius + 26, 300)
		local x, z = math.cos(angle) * distance, math.sin(angle) * distance
		local density = math.noise(x / 90, z / 90, 51) + (if distance > 120 then 0.2 else 0)
		if density > -0.12 and steepness(x, z) < 0.9 then
			local at = ground(x, z)
			if at.Y < 96 and not clear(at, 6) and spaced(at, 7.5) then
				conifer(folder, at, random:NextNumber(15, 30), at.Y > 58)
				table.insert(trees, at)
				conifers += 1
			end
		end
		if attempt % 64 == 0 then task.wait() end
	end
	local birches = 0
	for _ = 1, 600 do
		if birches >= 16 then break end
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(clearRadius + 12, 160)
		local at = ground(math.cos(angle) * distance, math.sin(angle) * distance)
		if at.Y < 30 and not clear(at, 3) and spaced(at, 9) then
			birch(folder, at, random:NextNumber(12, 19))
			table.insert(trees, at)
			birches += 1
		end
	end

	-- The log cabin: stacked round logs, a shingle roof and warm windows.
	local cabin = camp + Vector3.new(-18, 0, 15)
	local logColour = Color3.fromRGB(112, 82, 56)
	local logSize = 0.8
	local function log(name: string, a: Vector3, b: Vector3, row: number)
		solid(beam(folder, name, cabin + a, cabin + b, logSize, shade(logColour, 0.9 + (row % 3) * 0.06), Enum.Material.Wood))
	end
	for row = 0, 7 do
		local y = 0.9 + row * logSize * 0.92
		log("BackLog", Vector3.new(-5.6, y, 4.5), Vector3.new(5.6, y, 4.5), row)
		for _, x in { -5, 5 } do
			log("SideLog", Vector3.new(x, y + 0.37, -5.1), Vector3.new(x, y + 0.37, 5.1), row + 1)
		end
		-- The front wall leaves room for a door and two windows.
		local window = row >= 2 and row <= 4
		local spans: { { number } } = if row >= 6 then { { -5.6, 5.6 } }
			elseif window then { { -5.6, -4.3 }, { -2.1, -1.3 }, { 1.3, 2.1 }, { 4.3, 5.6 } }
			else { { -5.6, -1.3 }, { 1.3, 5.6 } }
		for _, span in spans do
			log("FrontLog", Vector3.new(span[1], y, -4.5), Vector3.new(span[2], y, -4.5), row)
		end
	end
	local wallTop = 0.9 + 8 * logSize * 0.92
	-- Gable ends: two wedges each, rising to the ridge.
	local ridge = 3.2
	for _, z in { -4.5, 4.5 } do
		for _, side in { -1, 1 } do
			local centre = cabin + Vector3.new(side * 2.75, wallTop + ridge / 2, z)
			piece(folder, "Gable", Vector3.new(0.6, ridge, 5.5), CFrame.new(centre) * PartShapes.wedgeToward(Vector3.new(side, 0, 0)), logColour, Enum.Material.WoodPlanks, "WedgePart")
		end
	end
	local pitch = math.atan2(ridge, 5.5)
	for _, side in { -1, 1 } do
		local length = math.sqrt(ridge * ridge + 5.5 * 5.5) + 0.9
		piece(folder, "Roof", Vector3.new(length, 0.35, 12.4), CFrame.new(cabin + Vector3.new(side * 2.75, wallTop + ridge / 2 + 0.3, 0)) * CFrame.Angles(0, 0, -side * pitch), Color3.fromRGB(70, 62, 58), Enum.Material.RoofShingles)
	end
	piece(folder, "RidgeBeam", Vector3.new(0.5, 0.5, 12.8), CFrame.new(cabin + Vector3.new(0, wallTop + ridge + 0.35, 0)), Color3.fromRGB(78, 58, 40), Enum.Material.Wood)
	local chimney = piece(folder, "StoneChimney", Vector3.new(1.5, 5.5, 1.5), CFrame.new(cabin + Vector3.new(3, wallTop + 2.4, 2.2)), Color3.fromRGB(116, 112, 104), Enum.Material.Cobblestone)
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(160, 160, 152)
	smoke.Opacity = 0.07
	smoke.Size = 2.5
	smoke.RiseVelocity = 2.5
	smoke.Parent = chimney
	solid(piece(folder, "CabinFloor", Vector3.new(11, 0.5, 9.4), CFrame.new(cabin + Vector3.new(0, 0.3, 0)), Color3.fromRGB(122, 94, 66), Enum.Material.WoodPlanks))
	piece(folder, "Door", Vector3.new(2.5, 4.6, 0.25), CFrame.new(cabin + Vector3.new(0, 2.85, -4.4)), Color3.fromRGB(96, 68, 46), Enum.Material.WoodPlanks)
	piece(folder, "DoorHandle", Vector3.new(0.12, 0.12, 0.3), CFrame.new(cabin + Vector3.new(0.85, 2.8, -4.62)), Color3.fromRGB(52, 50, 48), Enum.Material.Metal)
	piece(folder, "DoorLintel", Vector3.new(3.4, 0.6, 0.9), CFrame.new(cabin + Vector3.new(0, 5.4, -4.5)), Color3.fromRGB(86, 62, 42), Enum.Material.Wood)
	for _, x in { -3.2, 3.2 } do
		local glow = piece(folder, "WarmWindow", Vector3.new(2.2, 2.2, 0.1), CFrame.new(cabin + Vector3.new(x, 3.25, -4.35)), Color3.fromRGB(240, 176, 96), Enum.Material.Neon)
		glow.CastShadow = false
		piece(folder, "WindowCrossbar", Vector3.new(2.3, 0.12, 0.14), CFrame.new(cabin + Vector3.new(x, 3.25, -4.45)), Color3.fromRGB(60, 46, 34), Enum.Material.Wood)
		piece(folder, "WindowMullion", Vector3.new(0.12, 2.3, 0.14), CFrame.new(cabin + Vector3.new(x, 3.25, -4.45)), Color3.fromRGB(60, 46, 34), Enum.Material.Wood)
		piece(folder, "WindowSill", Vector3.new(2.6, 0.18, 0.5), CFrame.new(cabin + Vector3.new(x, 2.05, -4.75)), Color3.fromRGB(86, 62, 42), Enum.Material.Wood)
	end
	local hearth = Instance.new("PointLight")
	hearth.Color = Color3.fromRGB(255, 176, 96)
	hearth.Range = 10
	hearth.Brightness = 0.8
	hearth.Shadows = false
	hearth.Parent = folder:FindFirstChild("WarmWindow")
	-- Porch with a small roof on two posts.
	solid(piece(folder, "Porch", Vector3.new(7, 0.35, 3), CFrame.new(cabin + Vector3.new(0, 0.25, -6.2)), Color3.fromRGB(128, 98, 70), Enum.Material.WoodPlanks))
	solid(piece(folder, "PorchStep", Vector3.new(3.4, 0.3, 1.2), CFrame.new(cabin + Vector3.new(0, 0.12, -8.2)), Color3.fromRGB(118, 90, 64), Enum.Material.WoodPlanks))
	for _, x in { -3.2, 3.2 } do
		beam(folder, "PorchPost", cabin + Vector3.new(x, 0.4, -7.4), cabin + Vector3.new(x, 5.6, -7.4), 0.4, Color3.fromRGB(96, 70, 48), Enum.Material.Wood)
	end
	piece(folder, "PorchRoof", Vector3.new(7.6, 0.25, 3.6), CFrame.new(cabin + Vector3.new(0, 5.85, -6.3)) * CFrame.Angles(math.rad(-14), 0, 0), Color3.fromRGB(70, 62, 58), Enum.Material.RoofShingles)
	lantern(folder, cabin + Vector3.new(4.6, 0, -8.6))

	-- Woodpile, barrels, crates and a pickaxe make it a working mining camp.
	for row = 0, 2 do
		for i = 0, 3 - row do
			local y = 0.4 + row * 0.68
			local x = -6.9 - (i + row * 0.5) * 0.72
			beam(folder, "Firewood", cabin + Vector3.new(x, y, -1.4), cabin + Vector3.new(x, y, 1.4), 0.7, shade(Color3.fromRGB(128, 94, 62), 0.9 + ((i + row) % 3) * 0.06), Enum.Material.Wood)
		end
	end
	local yard = camp + Vector3.new(-9, 0, 4)
	for i, offset in { Vector3.new(0, 0, 0), Vector3.new(1.4, 0, 0.6) } do
		local barrel = beam(folder, "Barrel", yard + offset, yard + offset + Vector3.new(0, 1.6, 0), 1.2, Color3.fromRGB(118, 80, 50), Enum.Material.WoodPlanks)
		solid(barrel)
		beam(folder, "BarrelHoop", yard + offset + Vector3.new(0, 0.35 + i * 0.02, 0), yard + offset + Vector3.new(0, 0.45, 0), 1.26, Color3.fromRGB(58, 58, 60), Enum.Material.Metal)
		beam(folder, "BarrelHoop", yard + offset + Vector3.new(0, 1.15, 0), yard + offset + Vector3.new(0, 1.25, 0), 1.26, Color3.fromRGB(58, 58, 60), Enum.Material.Metal)
	end
	for i, frame in { CFrame.new(yard + Vector3.new(-1.8, 0.6, -1.2)), CFrame.new(yard + Vector3.new(-1.6, 1.8, -1.0)) * CFrame.Angles(0, 0.3, 0), CFrame.new(yard + Vector3.new(-3.0, 0.6, -0.4)) * CFrame.Angles(0, -0.2, 0) } do
		solid(piece(folder, "Crate", Vector3.new(1.2, 1.2, 1.2), frame, shade(Color3.fromRGB(150, 116, 76), 0.92 + i * 0.04), Enum.Material.WoodPlanks))
	end
	local leanAt = yard + Vector3.new(-2.9, 0, 0.6)
	beam(folder, "PickaxeHandle", leanAt, leanAt + Vector3.new(0.4, 2.6, 0.5), 0.16, Color3.fromRGB(122, 84, 52), Enum.Material.Wood)
	piece(folder, "PickaxeHead", Vector3.new(1.5, 0.22, 0.22), CFrame.new(leanAt + Vector3.new(0.4, 2.55, 0.5)) * CFrame.Angles(0, 0.9, 0.25), Color3.fromRGB(150, 154, 158), Enum.Material.Metal)

	-- A trail sign points the way to the mountain.
	local signAt = camp + Vector3.new(4.5, 0, -11)
	beam(folder, "SignPost", signAt, signAt + Vector3.new(0, 4.2, 0), 0.35, Color3.fromRGB(92, 68, 46), Enum.Material.Wood)
	-- The lettered face looks back towards the camp, where players spawn.
	local board = piece(folder, "SignBoard", Vector3.new(4.4, 1.1, 0.2), CFrame.lookAt(signAt + Vector3.new(0, 3.5, 0), signAt + Vector3.new(0, 3.5, 1)), Color3.fromRGB(132, 100, 66), Enum.Material.WoodPlanks)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 1
	gui.Parent = board
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(250, 236, 206)
	text.Text = "⛏  DIAMOND MOUNTAIN"
	text.Parent = gui

	-- Festoon lights over the camp, without a light per bulb.
	for i = 0, 14 do
		local t = i / 14
		local at = camp + Vector3.new(-10 + t * 20, 7 - 1.4 * math.sin(t * math.pi), -6)
		local wire = piece(folder, "FestoonWire", Vector3.new(1.5, 0.035, 0.035), CFrame.new(at), Color3.fromRGB(48, 44, 35), Enum.Material.Metal)
		wire.CastShadow = false
		if i % 2 == 0 then
			local bulb = piece(folder, "FestoonBulb", Vector3.new(0.18, 0.27, 0.18), CFrame.new(at + Vector3.new(0, -0.2, 0)), Color3.fromRGB(255, 191, 102), Enum.Material.Neon)
			bulb.CastShadow = false
		end
	end
	for _, x in { -10, 10 } do
		beam(folder, "FestoonPost", camp + Vector3.new(x, 0, -6), camp + Vector3.new(x, 7.2, -6), 0.25, Color3.fromRGB(96, 70, 48), Enum.Material.Wood)
	end

	-- The campfire: a stone ring, crossed logs and log benches.
	local fireAt = camp + Vector3.new(12, 0, 5)
	for i = 1, 11 do
		local angle = i / 11 * math.pi * 2
		local size = random:NextNumber(0.6, 0.85)
		piece(folder, "FireRingStone", Vector3.new(size * 1.2, size * 0.7, size), CFrame.new(fireAt + Vector3.new(math.cos(angle) * 1.6, size * 0.3, math.sin(angle) * 1.6))
			* CFrame.Angles(random:NextNumber(-0.3, 0.3), -angle, random:NextNumber(-0.3, 0.3)), Color3.fromRGB(110 + i % 3 * 8, 112 + i % 3 * 8, 110 + i % 3 * 8), Enum.Material.Slate)
	end
	for i = 1, 4 do
		local angle = i * math.pi / 2 + 0.4
		local foot = fireAt + Vector3.new(math.cos(angle) * 0.9, 0.1, math.sin(angle) * 0.9)
		beam(folder, "FireLog", foot, fireAt + Vector3.new(0, 1.3, 0), 0.32, Color3.fromRGB(70, 50, 36), Enum.Material.Wood)
	end
	local embers = piece(folder, "Embers", Vector3.new(1.6, 0.18, 1.6), CFrame.new(fireAt + Vector3.new(0, 0.12, 0)), Color3.fromRGB(236, 120, 52), Enum.Material.Neon)
	embers.CastShadow = false
	local fire = Instance.new("Fire")
	fire.Size = 3.2
	fire.Heat = 6
	fire.Color = Color3.fromRGB(255, 150, 60)
	fire.SecondaryColor = Color3.fromRGB(255, 70, 20)
	fire.Parent = embers
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 170, 90)
	glow.Range = 16
	glow.Brightness = 1.4
	glow.Shadows = false
	glow.Parent = embers
	for _, offset in { Vector3.new(-4, 0, 0), Vector3.new(4, 0, 0), Vector3.new(0, 0, 4) } do
		local across = if offset.X ~= 0 then Vector3.new(0, 0, 1.8) else Vector3.new(1.8, 0, 0)
		solid(beam(folder, "BenchLog", fireAt + offset + Vector3.new(0, 0.5, 0) - across, fireAt + offset + Vector3.new(0, 0.5, 0) + across, 1, Color3.fromRGB(104, 78, 54), Enum.Material.Wood))
	end
	lantern(folder, camp + Vector3.new(-9, 0, -8))
	lantern(folder, camp + Vector3.new(9, 0, -8))

	-- Light: a clear late-afternoon sun, soft sky light, aerial haze and a
	-- gentle filmic grade. Technology is Future (set in the place file).
	Lighting.ClockTime = 15.6
	Lighting.GeographicLatitude = 38
	Lighting.Brightness = 2.6
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.22
	Lighting.Ambient = Color3.fromRGB(74, 78, 88)
	Lighting.OutdoorAmbient = Color3.fromRGB(126, 130, 140)
	Lighting.ColorShift_Top = Color3.fromRGB(30, 18, 6)
	Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 0.85
	Lighting.ExposureCompensation = 0.1
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.22
	atmosphere.Color = Color3.fromRGB(198, 214, 230)
	atmosphere.Decay = Color3.fromRGB(110, 126, 150)
	atmosphere.Glare = 0.35
	atmosphere.Haze = 1.6
	atmosphere.Parent = Lighting
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "AlpineGrade"
	grade.Brightness = 0
	grade.Contrast = 0.08
	grade.Saturation = 0.08
	grade.TintColor = Color3.fromRGB(255, 249, 240)
	grade.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.45
	bloom.Size = 24
	bloom.Threshold = 1.3
	bloom.Parent = Lighting
	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.05
	rays.Spread = 0.75
	rays.Parent = Lighting
	local clouds = terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = 0.42
	clouds.Density = 0.5
	clouds.Color = Color3.fromRGB(250, 248, 242)
	clouds.Parent = terrain
	local sky = Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky")
	sky.SunAngularSize = 12
	sky.CelestialBodiesShown = true
	sky.Parent = Lighting
end

return Scenery
