--!strict
-- The desert canyon theme's own scenery: red sandstone mesas stand round the
-- valley, saguaro and barrel cacti and tumbleweeds dot the sand, palms ring
-- the lake as an oasis, a sandstone gate with fire bowls frames the trail
-- where it leaves the camp, and a stepped sandstone pyramid with a stair up
-- its front, a temple on top and obelisks at its foot stands beside the
-- mountain, facing the camp. The valley's pine forest, meadow flowers and
-- bushes make way (see SceneryThemes). Scenery builds it once, alongside the
-- alpine valley, and keeps it out of view until the theme is chosen (see
-- Scenery.setTheme). Nothing here takes part in mining raycasts or touch
-- events; the pyramid, its stair and the gate can be climbed and bumped into.
local Sakura = require(script.Parent.Sakura)

local Desert = {}

type Kit = Sakura.Kit

local SANDSTONE = { Color3.fromRGB(196, 124, 80), Color3.fromRGB(214, 150, 100), Color3.fromRGB(176, 100, 66), Color3.fromRGB(226, 170, 116) }
local PALE = Color3.fromRGB(226, 196, 146) -- the pyramid's limestone
local GOLD = Color3.fromRGB(232, 182, 72)
local CACTUS = Color3.fromRGB(76, 118, 70)
local PALM_TRUNK = Color3.fromRGB(132, 102, 70)
local FROND = Color3.fromRGB(88, 136, 62)
local DARK = Color3.fromRGB(34, 26, 22)
local CLAY = Color3.fromRGB(176, 96, 62)

Desert.PYRAMID = 30 -- studs across its lowest step
Desert.STEPS = 8 -- steps from the ground to the temple
Desert.STEP_HEIGHT = 3.4

-- Open, fairly flat ground in view of the spawn, to one side of the mountain,
-- for something `size` across facing the camp. Returns its frame (on the
-- highest ground under it) and how far its base must reach down, or nil.
local function site(kit: Kit, random: Random, size: number, gap: number): (CFrame?, number)
	local best: CFrame? = nil
	local bestDrop, bestScore = 0, math.huge
	local half = size / 2
	for attempt = 1, 500 do
		local angle = (if random:NextNumber() < 0.5 then -1 else 1) * random:NextNumber(math.rad(30), math.rad(72))
		local distance = random:NextNumber(75, 150)
		local spot = kit.camp + Vector3.new(math.sin(angle), 0, -math.cos(angle)) * distance
		local centre = kit.ground(spot.X, spot.Z)
		if not kit.clear(centre, half + 8) and centre.Y < 30 and kit.steepness(centre.X, centre.Z) < 0.5 and kit.spaced(centre, gap) then
			local flat = Vector3.new(centre.X, 0, centre.Z)
			local facing = Vector3.new(kit.camp.X - centre.X, 0, kit.camp.Z - centre.Z).Unit
			local base = CFrame.lookAt(flat, flat + facing)
			local low, high = math.huge, -math.huge
			local open = true
			for _, offset in { Vector3.new(-half, 0, -half), Vector3.new(half, 0, -half), Vector3.new(-half, 0, half), Vector3.new(half, 0, half),
				Vector3.new(0, 0, -half - 6), Vector3.zero } do
				local at = base * offset
				local ground = kit.ground(at.X, at.Z)
				low, high = math.min(low, ground.Y), math.max(high, ground.Y)
				if kit.clear(ground, 2) or not kit.spaced(ground, gap * 0.5) then open = false end
			end
			if open and high - low < 6 then
				local score = math.abs(math.abs(angle) - math.rad(48)) * 0.6 + distance / 150 + (high - low) * 0.3
				if score < bestScore then
					bestScore = score
					best = base + Vector3.new(0, high, 0)
					bestDrop = high - low + 1
				end
			end
		end
		if attempt % 50 == 0 then task.wait() end
	end
	return best, bestDrop
end

-- The stepped pyramid, in its own frame (front, with the stair, facing the camp).
local function pyramid(kit: Kit, parent: Instance, base: CFrame, drop: number): Model
	local model = Instance.new("Model")
	model.Name = "Pyramid"
	model.Parent = parent
	local function put(name: string, size: Vector3, offset: CFrame, colour: Color3, material: Enum.Material): BasePart
		return kit.piece(model, name, size, base * offset, colour, material)
	end
	local width, rise = Desert.PYRAMID, Desert.STEP_HEIGHT
	local shrink = (width - 8) / Desert.STEPS -- each step is this much narrower
	for step = 0, Desert.STEPS - 1 do
		local size = width - step * shrink
		local bottom = step * rise
		-- The lowest step reaches down to the lowest ground under it.
		local reach = if step == 0 then drop else 0
		local colour = if step % 2 == 0 then PALE else Color3.fromRGB(212, 180, 128)
		kit.solid(put("PyramidStep", Vector3.new(size, rise + reach, size), CFrame.new(0, bottom + (rise - reach) / 2, 0), colour, Enum.Material.Sandstone))
		-- A dark band of carving round each step's top edge.
		put("PyramidBand", Vector3.new(size + 0.1, 0.3, size + 0.1), CFrame.new(0, bottom + rise - 0.5, 0), Color3.fromRGB(176, 136, 90), Enum.Material.Sandstone)
	end
	-- The stair up the front, steep like a temple's: from the sand in front of
	-- the lowest step to the temple door, each tread solid down to the ground.
	local stairWidth = 5
	local summit = Desert.STEPS * rise
	local top = width - Desert.STEPS * shrink
	local treads = Desert.STEPS * 4
	local foot = -(width / 2 + 4)
	local run = (-(top / 2) - foot) / treads
	for tread = 0, treads - 1 do
		local high = (tread + 1) * rise / 4
		local front = foot + tread * run
		local depth = if tread == treads - 1 then run + 1 else run + 0.05
		kit.solid(put("PyramidStair", Vector3.new(stairWidth, high + drop, depth), CFrame.new(0, (high - drop) / 2, front + depth / 2),
			if tread % 2 == 0 then Color3.fromRGB(200, 166, 116) else Color3.fromRGB(190, 156, 108), Enum.Material.Sandstone))
	end
	-- The temple on top: a dark doorway facing the camp, a gold-banded roof
	-- and a gold capstone.
	kit.solid(put("Temple", Vector3.new(top - 1.6, 5, top - 1.6), CFrame.new(0, summit + 2.5, 0), PALE, Enum.Material.Sandstone))
	put("TempleDoor", Vector3.new(2, 3.4, 0.2), CFrame.new(0, summit + 1.7, -(top - 1.6) / 2 - 0.05), DARK, Enum.Material.Slate)
	put("TempleLintel", Vector3.new(3, 0.5, 0.4), CFrame.new(0, summit + 3.6, -(top - 1.6) / 2 - 0.1), GOLD, Enum.Material.Foil)
	put("TempleRoof", Vector3.new(top, 0.6, top), CFrame.new(0, summit + 5.3, 0), Color3.fromRGB(176, 136, 90), Enum.Material.Sandstone)
	put("TempleGoldBand", Vector3.new(top + 0.1, 0.25, top + 0.1), CFrame.new(0, summit + 5.1, 0), GOLD, Enum.Material.Foil)
	put("Capstone", Vector3.new(3, 1.4, 3), CFrame.new(0, summit + 6.3, 0), GOLD, Enum.Material.Foil)
	put("Capstone", Vector3.new(1.6, 1, 1.6), CFrame.new(0, summit + 7.5, 0), GOLD, Enum.Material.Foil)
	-- Obelisks and fire bowls either side of the foot of the stair.
	for _, side in { -1, 1 } do
		local x = side * (stairWidth / 2 + 3.2)
		local z = -(width / 2 + 3)
		local foot = base * Vector3.new(x, 0, z)
		local low = kit.ground(foot.X, foot.Z).Y - base.Position.Y
		kit.solid(put("ObeliskBase", Vector3.new(2.6, 1.2 - low, 2.6), CFrame.new(x, (1.2 + low) / 2, z), Color3.fromRGB(200, 166, 116), Enum.Material.Sandstone))
		kit.solid(put("Obelisk", Vector3.new(1.5, 9, 1.5), CFrame.new(x, 1.2 + 4.5, z), PALE, Enum.Material.Sandstone))
		put("Obelisk", Vector3.new(1.2, 2, 1.2), CFrame.new(x, 1.2 + 10, z), PALE, Enum.Material.Sandstone)
		put("ObeliskTip", Vector3.new(0.8, 0.8, 0.8), CFrame.new(x, 1.2 + 11.4, z), GOLD, Enum.Material.Foil)
		local bowlX = side * (stairWidth / 2 + 0.9)
		local bowlZ = -(width / 2 + 2.4)
		local bowlFoot = base * Vector3.new(bowlX, 0, bowlZ)
		local bowlLow = kit.ground(bowlFoot.X, bowlFoot.Z).Y - base.Position.Y
		kit.beam(model, "BrazierStand", base * Vector3.new(bowlX, bowlLow - 0.3, bowlZ), base * Vector3.new(bowlX, 2.4, bowlZ), 0.5, DARK, Enum.Material.Metal)
		local bowl = kit.beam(model, "Brazier", base * Vector3.new(bowlX, 2.3, bowlZ), base * Vector3.new(bowlX, 2.9, bowlZ), 1.5, Color3.fromRGB(120, 86, 46), Enum.Material.Metal)
		local fire = Instance.new("Fire")
		fire.Size = 2.2
		fire.Heat = 7
		fire.Color = Color3.fromRGB(255, 160, 60)
		fire.SecondaryColor = Color3.fromRGB(255, 80, 20)
		fire.Parent = bowl
	end
	return model
end

-- A layered sandstone mesa or butte, its stripes in the canyon's reds.
local function mesa(kit: Kit, parent: Instance, at: Vector3, radius: number, random: Random)
	local model = Instance.new("Model")
	model.Name = "Mesa"
	model.Parent = parent
	local layers = random:NextInteger(3, 5)
	local y = at.Y - 14
	local r = radius
	local drift = Vector3.zero
	for layer = 1, layers do
		local tall = random:NextNumber(8, 14) + (if layer == 1 then 14 else 0)
		local centre = Vector3.new(at.X, 0, at.Z) + drift
		kit.beam(model, "MesaLayer", Vector3.new(centre.X, y, centre.Z), Vector3.new(centre.X, y + tall, centre.Z), r * 2, SANDSTONE[(layer - 1) % #SANDSTONE + 1], Enum.Material.Sandstone)
		y += tall
		r *= random:NextNumber(0.82, 0.95)
		drift += Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1)) * radius * 0.06
	end
	-- A flat cap, a shade paler where the sun bleaches it.
	kit.beam(model, "MesaTop", Vector3.new(at.X + drift.X, y, at.Z + drift.Z), Vector3.new(at.X + drift.X, y + 1.2, at.Z + drift.Z), r * 2 - 1, Color3.fromRGB(222, 168, 118), Enum.Material.Sandstone)
end

-- A saguaro: a ribbed trunk with one to three arms turning up.
local function saguaro(kit: Kit, parent: Instance, at: Vector3, height: number, random: Random)
	local model = Instance.new("Model")
	model.Name = "Saguaro"
	model.Parent = parent
	local width = height * 0.12
	local tone = random:NextNumber(0.9, 1.08)
	local colour = Color3.new(CACTUS.R * tone, CACTUS.G * tone, CACTUS.B * tone)
	local top = at + Vector3.new(0, height, 0)
	kit.beam(model, "CactusTrunk", at - Vector3.new(0, 0.5, 0), top, width, colour, Enum.Material.Plastic)
	local cap = kit.piece(model, "CactusTop", Vector3.new(width, width, width), CFrame.new(top), colour, Enum.Material.Plastic) :: Part
	cap.Shape = Enum.PartType.Ball
	local yaw = random:NextNumber(0, math.pi * 2)
	for arm = 1, random:NextInteger(1, 3) do
		local angle = yaw + arm * 2.1
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local from = at + Vector3.new(0, height * random:NextNumber(0.35, 0.55), 0)
		local elbow = from + out * height * 0.22
		local up = elbow + Vector3.new(0, height * random:NextNumber(0.2, 0.32), 0)
		local armWidth = width * 0.75
		kit.beam(model, "CactusArm", from, elbow, armWidth, colour, Enum.Material.Plastic)
		local joint = kit.piece(model, "CactusElbow", Vector3.new(armWidth, armWidth, armWidth), CFrame.new(elbow), colour, Enum.Material.Plastic) :: Part
		joint.Shape = Enum.PartType.Ball
		kit.beam(model, "CactusArm", elbow, up, armWidth, colour, Enum.Material.Plastic)
		local tip = kit.piece(model, "CactusTop", Vector3.new(armWidth, armWidth, armWidth), CFrame.new(up), colour, Enum.Material.Plastic) :: Part
		tip.Shape = Enum.PartType.Ball
	end
end

-- A squat barrel cactus with a pink flower on top.
local function barrel(kit: Kit, parent: Instance, at: Vector3, size: number)
	local body = kit.piece(parent, "BarrelCactus", Vector3.new(size, size, size), CFrame.new(at + Vector3.new(0, size * 0.32, 0)), CACTUS, Enum.Material.Plastic) :: Part
	body.Shape = Enum.PartType.Ball
	kit.piece(parent, "CactusFlower", Vector3.new(size * 0.35, size * 0.12, size * 0.35), CFrame.new(at + Vector3.new(0, size * 0.82, 0)), Color3.fromRGB(236, 104, 146), Enum.Material.SmoothPlastic)
end

-- A date palm leaning over the water, its fronds drooping all round.
local function palm(kit: Kit, parent: Instance, at: Vector3, height: number, lean: Vector3, random: Random)
	local model = Instance.new("Model")
	model.Name = "Palm"
	model.Parent = parent
	local points = {}
	for i = 0, 4 do
		local t = i / 4
		points[i + 1] = at + Vector3.new(0, height * t, 0) + lean * height * 0.28 * t * t
	end
	for i = 1, 4 do
		kit.beam(model, "PalmTrunk", points[i] - (if i == 1 then Vector3.new(0, 0.5, 0) else Vector3.zero), points[i + 1], 0.9 - i * 0.08, PALM_TRUNK, Enum.Material.Wood)
	end
	local crown = points[5]
	local yaw = random:NextNumber(0, math.pi * 2)
	for k = 0, 7 do
		local angle = yaw + k * math.pi / 4
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local tip = crown + out * 4.6 + Vector3.new(0, -1.6 + (k % 2) * 0.6, 0)
		local mid = crown + out * 2.4 + Vector3.new(0, 0.5, 0)
		for _, span in { { crown, mid }, { mid, tip } } do
			local a, b = span[1], span[2]
			kit.piece(model, "PalmFrond", Vector3.new(1.3, 0.12, (b - a).Magnitude + 0.3), CFrame.lookAt((a + b) / 2, b), FROND, Enum.Material.LeafyGrass)
		end
	end
	for k = 1, 3 do
		local angle = yaw + k * 2.1
		local date = kit.piece(model, "Dates", Vector3.new(0.7, 0.7, 0.7), CFrame.new(crown + Vector3.new(math.cos(angle) * 0.6, -0.6, math.sin(angle) * 0.6)), Color3.fromRGB(150, 82, 40), Enum.Material.SmoothPlastic) :: Part
		date.Shape = Enum.PartType.Ball
	end
end

-- The gate where the trail leaves the camp: two tapering sandstone pylons with
-- fire bowls and a gold-banded lintel across.
local function gate(kit: Kit, parent: Instance, frame: CFrame, span: number)
	local model = Instance.new("Model")
	model.Name = "CanyonGate"
	model.Parent = parent
	for _, side in { -1, 1 } do
		local x = side * span / 2
		local foot = frame * Vector3.new(x, 0, 0)
		local low = kit.ground(foot.X, foot.Z).Y - frame.Position.Y
		local y = low - 0.5
		for i, size in { Vector3.new(2.8, 1.5, 2.8), Vector3.new(2.2, 4, 2.2), Vector3.new(1.9, 3.5, 1.9), Vector3.new(1.6, 3, 1.6) } do
			local tall = size.Y + (if i == 1 then -low + 0.5 else 0)
			kit.solid(kit.piece(model, "GatePylon", Vector3.new(size.X, tall, size.Z), frame * CFrame.new(x, y + tall / 2, 0), SANDSTONE[(i - 1) % #SANDSTONE + 1], Enum.Material.Sandstone))
			y += tall
		end
		local bowl = kit.beam(model, "GateBrazier", frame * Vector3.new(x, y + 0.6, 0), frame * Vector3.new(x, y + 1.2, 0), 1.4, Color3.fromRGB(120, 86, 46), Enum.Material.Metal)
		local fire = Instance.new("Fire")
		fire.Size = 2
		fire.Heat = 6
		fire.Color = Color3.fromRGB(255, 160, 60)
		fire.SecondaryColor = Color3.fromRGB(255, 80, 20)
		fire.Parent = bowl
	end
	kit.piece(model, "GateLintel", Vector3.new(span + 3, 1.4, 2.2), frame * CFrame.new(0, 11, 0), SANDSTONE[2], Enum.Material.Sandstone)
	kit.piece(model, "GateGoldBand", Vector3.new(span + 3.1, 0.35, 2.3), frame * CFrame.new(0, 10.6, 0), GOLD, Enum.Material.Foil)
	kit.piece(model, "GateCornice", Vector3.new(span + 4, 0.5, 2.8), frame * CFrame.new(0, 11.9, 0), SANDSTONE[4], Enum.Material.Sandstone)
end

-- A clay water pot.
local function pot(kit: Kit, parent: Instance, at: Vector3, size: number)
	local body = kit.piece(parent, "ClayPot", Vector3.new(size, size, size), CFrame.new(at + Vector3.new(0, size * 0.45, 0)), CLAY, Enum.Material.Slate) :: Part
	body.Shape = Enum.PartType.Ball
	kit.beam(parent, "ClayPotNeck", at + Vector3.new(0, size * 0.8, 0), at + Vector3.new(0, size * 1.05, 0), size * 0.45, CLAY, Enum.Material.Slate)
end

function Desert.build(kit: Kit): Folder
	local folder = Instance.new("Folder")
	folder.Name = "DesertScenery"
	-- Its own seed, so the alpine valley is laid out the same with or without it.
	local random = Random.new(8821)
	local placed: { Vector3 } = {}
	local function roomy(at: Vector3, gap: number): boolean
		for _, other in placed do
			if (Vector3.new(at.X - other.X, 0, at.Z - other.Z)).Magnitude < gap then return false end
		end
		return true
	end

	-- The pyramid goes first, so the cacti grow round it.
	local base, drop = nil, 0
	for _, gap in { 12, 8, 5 } do
		base, drop = site(kit, random, Desert.PYRAMID + 2, gap)
		if base then break end
	end
	if base then
		pyramid(kit, folder, base :: CFrame, drop)
	else
		warn("[DiamondRush] Desert: no open ground for the pyramid, so it is left out.")
	end
	local keepOff = if base then Vector3.new((base :: CFrame).Position.X, 0, (base :: CFrame).Position.Z) else nil
	local function offPyramid(at: Vector3, margin: number): boolean
		return keepOff == nil or (Vector3.new(at.X, 0, at.Z) - (keepOff :: Vector3)).Magnitude > Desert.PYRAMID * 0.75 + 6 + margin
	end

	-- Mesas and buttes round the valley, beyond the trees' meadows.
	local mesas = 0
	for attempt = 1, 400 do
		if mesas >= 9 then break end
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(200, 330)
		local radius = random:NextNumber(14, 30)
		local at = kit.ground(math.cos(angle) * distance, math.sin(angle) * distance)
		if not kit.clear(at, radius + 6) and offPyramid(at, radius) and roomy(at, radius + 34) then
			mesa(kit, folder, at, radius, random)
			table.insert(placed, at)
			mesas += 1
		end
		if attempt % 50 == 0 then task.wait() end
	end
	-- Saguaros across the sand, and barrel cacti among them.
	local saguaros = 0
	for attempt = 1, 2400 do
		if saguaros >= 40 then break end
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(kit.radius + 8, 230)
		local at = kit.ground(math.cos(angle) * distance, math.sin(angle) * distance)
		if not kit.clear(at, 3) and at.Y < 40 and kit.steepness(at.X, at.Z) < 0.6 and kit.spaced(at, 3) and offPyramid(at, 2) and roomy(at, 9) then
			saguaro(kit, folder, at, random:NextNumber(7, 13), random)
			table.insert(placed, at)
			saguaros += 1
		end
		if attempt % 64 == 0 then task.wait() end
	end
	local barrels = 0
	for attempt = 1, 1200 do
		if barrels >= 28 then break end
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(kit.radius + 4, 180)
		local at = kit.ground(math.cos(angle) * distance, math.sin(angle) * distance)
		if not kit.clear(at, 1.5) and at.Y < 40 and kit.steepness(at.X, at.Z) < 0.6 and kit.spaced(at, 2) and offPyramid(at, 1) and roomy(at, 3) then
			barrel(kit, folder, at, random:NextNumber(1.1, 1.8))
			table.insert(placed, at)
			barrels += 1
		end
		if attempt % 64 == 0 then task.wait() end
	end
	-- Tumbleweeds caught in the open.
	local weeds = 0
	for attempt = 1, 600 do
		if weeds >= 14 then break end
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(kit.radius + 4, 160)
		local at = kit.ground(math.cos(angle) * distance, math.sin(angle) * distance)
		if not kit.clear(at, 1) and kit.spaced(at, 2) and offPyramid(at, 1) and roomy(at, 3) then
			local size = random:NextNumber(1.6, 2.6)
			local weed = kit.piece(folder, "Tumbleweed", Vector3.new(size, size, size), CFrame.new(at + Vector3.new(0, size * 0.4, 0)), Color3.fromRGB(150, 116, 74), Enum.Material.Grass) :: Part
			weed.Shape = Enum.PartType.Ball
			table.insert(placed, at)
			weeds += 1
		end
	end
	-- The oasis: palms round the lake, leaning out over the water.
	local palms = 0
	for attempt = 1, 400 do
		if palms >= 9 then break end
		local angle = random:NextNumber(0, math.pi * 2)
		local stretch = random:NextNumber(1.3, 1.6)
		local at = kit.ground(kit.lake.X + math.cos(angle) * 35 * stretch, kit.lake.Z + math.sin(angle) * 27 * stretch)
		if at.Y > 0 and not kit.clear(at, -8) and kit.spaced(at, 2) and roomy(at, 7) then
			local lean = Vector3.new(kit.lake.X - at.X, 0, kit.lake.Z - at.Z).Unit
			palm(kit, folder, at, random:NextNumber(10, 15), lean, random)
			table.insert(placed, at)
			palms += 1
		end
	end
	-- The gate stands just past the spawn, where the trail leaves the camp,
	-- framing the mountain from the camp; its pylons stay beside the trail.
	local gateZ = kit.camp.Z - 9
	gate(kit, folder, CFrame.new(kit.ground(kit.pathCentre(gateZ), gateZ)), 10)
	-- Clay pots by the camp.
	for _, offset in { Vector3.new(-13, 0, -4), Vector3.new(-12, 0, -5.4), Vector3.new(13.5, 0, -4.2) } do
		local spot = kit.camp + offset
		pot(kit, folder, kit.ground(spot.X, spot.Z), if offset.X < -12.5 then 1.6 else 1.2)
	end
	return folder
end

return Desert
