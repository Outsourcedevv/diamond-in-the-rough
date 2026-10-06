--!strict
-- The haunted night theme's own scenery: an iron cemetery gate between stone
-- pillars where the trail leaves the camp, a graveyard of crooked headstones
-- and crosses behind a spiked iron fence, a stone mausoleum with columns and
-- a green glow under its iron door, bare dead trees across the meadows,
-- glowing jack-o'-lanterns and pale will-o'-wisps floating in the mist, all
-- under a full moon (the light is Scenery.LOOKS.haunted). The meadow flowers
-- and leafy trees make way (see SceneryThemes). Scenery builds it once, alongside the alpine
-- valley, and keeps it out of view until the theme is chosen (see
-- Scenery.setTheme). Nothing here takes part in mining raycasts or touch
-- events; the gate pillars, fence and mausoleum can be bumped into.
local Sakura = require(script.Parent.Sakura)

local Haunted = {}

type Kit = Sakura.Kit

local STONE = Color3.fromRGB(104, 106, 112)
local DARK_STONE = Color3.fromRGB(72, 74, 80)
local MOSS = Color3.fromRGB(70, 84, 62)
local IRON = Color3.fromRGB(30, 30, 34)
local DEAD_WOOD = Color3.fromRGB(64, 54, 48)
local PUMPKIN = Color3.fromRGB(222, 112, 28)
local CANDLE = Color3.fromRGB(255, 196, 80)
local GHOST = Color3.fromRGB(150, 255, 200) -- the crypt's and the gate lantern's green glow
local WISP = Color3.fromRGB(176, 226, 255)

Haunted.CRYPT = Vector3.new(14, 12, 16) -- the mausoleum's width, height to the ridge and depth
Haunted.GRAVES = { columns = 4, rows = 4, spacing = 4.2 }

local function light(parent: Instance, colour: Color3, range: number, brightness: number)
	local glow = Instance.new("PointLight")
	glow.Color = colour
	glow.Range = range
	glow.Brightness = brightness
	glow.Shadows = false
	glow.Parent = parent
end

-- Where the mausoleum goes: open, fairly flat ground in view of the spawn, to
-- one side of the mountain, with room for the graveyard beside it. Returns
-- its frame (front facing the camp) and how far its plinth must reach down.
local YARD = 22 -- the graveyard's width beside the crypt
local function cryptSite(kit: Kit, random: Random, gap: number): (CFrame?, number)
	local best: CFrame? = nil
	local bestDrop, bestScore = 0, math.huge
	local w, d = Haunted.CRYPT.X + 2, Haunted.CRYPT.Z + 6
	for attempt = 1, 500 do
		local angle = (if random:NextNumber() < 0.5 then -1 else 1) * random:NextNumber(math.rad(30), math.rad(70))
		local distance = random:NextNumber(70, 140)
		local spot = kit.camp + Vector3.new(math.sin(angle), 0, -math.cos(angle)) * distance
		local centre = kit.ground(spot.X, spot.Z)
		if not kit.clear(centre, 16) and centre.Y < 28 and kit.steepness(centre.X, centre.Z) < 0.5 and kit.spaced(centre, gap) then
			local flat = Vector3.new(centre.X, 0, centre.Z)
			local facing = Vector3.new(kit.camp.X - centre.X, 0, kit.camp.Z - centre.Z).Unit
			local base = CFrame.lookAt(flat, flat + facing)
			local low, high = math.huge, -math.huge
			for _, offset in { Vector3.new(-w / 2, 0, -d / 2), Vector3.new(w / 2, 0, -d / 2), Vector3.new(-w / 2, 0, d / 2), Vector3.new(w / 2, 0, d / 2), Vector3.zero } do
				local at = base * offset
				local y = kit.ground(at.X, at.Z).Y
				low, high = math.min(low, y), math.max(high, y)
			end
			if high - low < 4 then
				-- How much of the graveyard beside it is open ground.
				local open = 0
				for i = 0, 3 do
					for j = 0, 3 do
						local at = base * Vector3.new(-(w / 2 + 4 + YARD * i / 3), 0, -d / 2 + d * j / 3)
						local ground = kit.ground(at.X, at.Z)
						if not kit.clear(ground, 1) and kit.spaced(ground, 2) and kit.steepness(at.X, at.Z) < 0.7 then open += 1 end
					end
				end
				local score = math.abs(math.abs(angle) - math.rad(46)) * 0.6 + distance / 150 + (high - low) * 0.3 + (16 - open) * 0.15
				if score < bestScore then
					bestScore = score
					best = base + Vector3.new(0, high + 0.4, 0)
					bestDrop = high + 0.4 - low + 0.6
				end
			end
		end
		if attempt % 50 == 0 then task.wait() end
	end
	return best, bestDrop
end

-- The mausoleum, in its own frame (front facing the camp).
local function crypt(kit: Kit, parent: Instance, base: CFrame, drop: number): Model
	local model = Instance.new("Model")
	model.Name = "Mausoleum"
	model.Parent = parent
	local w, h, d = Haunted.CRYPT.X, Haunted.CRYPT.Y, Haunted.CRYPT.Z
	local function put(name: string, size: Vector3, offset: CFrame, colour: Color3, material: Enum.Material, kind: string?): BasePart
		return kit.piece(model, name, size, base * offset, colour, material, kind)
	end
	local plinth = 1.4
	kit.solid(put("CryptPlinth", Vector3.new(w + 2, plinth + drop, d + 5), CFrame.new(0, (plinth - drop) / 2, -1.5), DARK_STONE, Enum.Material.Cobblestone))
	-- Steps up to the portico.
	for step = 1, 3 do
		local high = plinth * step / 3
		kit.solid(put("CryptStep", Vector3.new(6, high + drop, 1), CFrame.new(0, (high - drop) / 2, -(d / 2 + 4) - (3 - step) * 1 - 0.5), DARK_STONE, Enum.Material.Cobblestone))
	end
	local wallTop = plinth + h * 0.62
	kit.solid(put("CryptWalls", Vector3.new(w, wallTop - plinth, d), CFrame.new(0, (plinth + wallTop) / 2, 0), STONE, Enum.Material.Slate))
	-- Moss creeping up the walls.
	put("CryptMoss", Vector3.new(w + 0.1, 1.2, d + 0.1), CFrame.new(0, plinth + 0.6, 0), MOSS, Enum.Material.Grass)
	-- The portico: four columns, an entablature and a pediment.
	local front = -(d / 2 + 2.6)
	for _, x in { -w / 2 + 1, -w / 6, w / 6, w / 2 - 1 } do
		kit.solid(kit.beam(model, "CryptColumn", base * Vector3.new(x, plinth, front), base * Vector3.new(x, wallTop, front), 1.3, STONE, Enum.Material.Marble))
		put("ColumnBase", Vector3.new(1.8, 0.4, 1.8), CFrame.new(x, plinth + 0.2, front), DARK_STONE, Enum.Material.Slate)
		put("ColumnCap", Vector3.new(1.8, 0.4, 1.8), CFrame.new(x, wallTop - 0.2, front), DARK_STONE, Enum.Material.Slate)
	end
	put("Entablature", Vector3.new(w + 0.6, 1.2, d + 3.4), CFrame.new(0, wallTop + 0.6, -1.3), DARK_STONE, Enum.Material.Slate)
	local ridge = h - (wallTop + 1.2)
	local roofBase = wallTop + 1.2
	for _, z in { front - 0.8, d / 2 + 0.2 } do
		for _, side in { -1, 1 } do
			-- Each wedge rises towards the middle (as the farm's barn gables do).
			local turn = if side > 0 then CFrame.Angles(0, -math.pi / 2, 0) else CFrame.Angles(0, math.pi / 2, 0)
			put("Pediment", Vector3.new(0.8, ridge, w / 2 + 0.3), CFrame.new(side * (w / 4 + 0.15), roofBase + ridge / 2, z) * turn, STONE, Enum.Material.Slate, "WedgePart")
		end
	end
	local pitch = math.atan2(ridge, w / 2)
	local slope = math.sqrt(ridge * ridge + (w / 2) * (w / 2)) + 0.8
	for _, side in { -1, 1 } do
		put("CryptRoof", Vector3.new(slope, 0.5, d + 4.6), CFrame.new(side * w / 4, roofBase + ridge / 2 + 0.25, -1.3) * CFrame.Angles(0, 0, -side * pitch), DARK_STONE, Enum.Material.Slate)
	end
	-- A stone cross on the ridge over the portico.
	put("CryptCross", Vector3.new(0.5, 2.6, 0.5), CFrame.new(0, h + 1.3, front - 0.6), STONE, Enum.Material.Marble)
	put("CryptCross", Vector3.new(1.6, 0.5, 0.5), CFrame.new(0, h + 1.8, front - 0.6), STONE, Enum.Material.Marble)
	-- The iron door, with an eerie green glow leaking round it.
	local doorZ = -d / 2 - 0.1
	put("CryptGlow", Vector3.new(3.8, 5.8, 0.1), CFrame.new(0, plinth + 2.9, doorZ + 0.02), GHOST, Enum.Material.Neon)
	put("CryptDoor", Vector3.new(3.4, 5.4, 0.25), CFrame.new(0, plinth + 2.7, doorZ - 0.1), IRON, Enum.Material.DiamondPlate)
	put("CryptDoorRing", Vector3.new(0.5, 0.5, 0.15), CFrame.new(0.9, plinth + 2.8, doorZ - 0.3), Color3.fromRGB(110, 96, 70), Enum.Material.Metal)
	local glowPart = put("CryptLamp", Vector3.new(0.4, 0.4, 0.4), CFrame.new(0, plinth + 3, doorZ - 1.2), GHOST, Enum.Material.Neon)
	glowPart.Transparency = 1
	light(glowPart, GHOST, 16, 1.4)
	-- Stone urns at the plinth's front corners.
	for _, side in { -1, 1 } do
		local at = CFrame.new(side * (w / 2 + 0.4), plinth, -(d / 2 + 3.4))
		put("UrnFoot", Vector3.new(1, 0.6, 1), at * CFrame.new(0, 0.3, 0), DARK_STONE, Enum.Material.Slate)
		local urn = put("Urn", Vector3.new(1.3, 1.3, 1.3), at * CFrame.new(0, 1.2, 0), STONE, Enum.Material.Marble) :: Part
		urn.Shape = Enum.PartType.Ball
	end
	return model
end

-- A headstone of one of three shapes, leaning a little.
local function headstone(kit: Kit, parent: Instance, frame: CFrame, kind: number, random: Random)
	local model = Instance.new("Model")
	model.Name = "Grave"
	model.Parent = parent
	local tone = random:NextNumber(0.85, 1.12)
	local colour = Color3.new(STONE.R * tone, STONE.G * tone, STONE.B * tone)
	local lean = frame * CFrame.Angles(random:NextNumber(-0.14, 0.1), 0, random:NextNumber(-0.1, 0.1))
	if kind == 1 then
		-- A round-topped headstone.
		kit.piece(model, "Headstone", Vector3.new(2, 2.2, 0.45), lean * CFrame.new(0, 0.6, 0), colour, Enum.Material.Slate)
		local top = kit.piece(model, "HeadstoneTop", Vector3.new(0.45, 2, 2), lean * CFrame.new(0, 1.7, 0) * CFrame.Angles(0, math.pi / 2, 0), colour, Enum.Material.Slate) :: Part
		top.Shape = Enum.PartType.Cylinder
	elseif kind == 2 then
		-- A stone cross.
		kit.piece(model, "GraveCross", Vector3.new(0.45, 3.4, 0.45), lean * CFrame.new(0, 1.2, 0), colour, Enum.Material.Marble)
		kit.piece(model, "GraveCross", Vector3.new(1.8, 0.45, 0.45), lean * CFrame.new(0, 2.1, 0), colour, Enum.Material.Marble)
	else
		-- A tall slab with a stepped top.
		kit.piece(model, "Headstone", Vector3.new(1.7, 2.8, 0.5), lean * CFrame.new(0, 0.9, 0), colour, Enum.Material.Slate)
		kit.piece(model, "HeadstoneTop", Vector3.new(1.2, 0.5, 0.55), lean * CFrame.new(0, 2.5, 0), colour, Enum.Material.Slate)
	end
	-- The grave in front of it.
	kit.piece(model, "GraveMound", Vector3.new(1.8, 0.4, 3.4), frame * CFrame.new(0, 0, -2), Color3.fromRGB(70, 58, 46), Enum.Material.Ground)
end

-- A bare, crooked dead tree with forked branches.
local function deadTree(kit: Kit, parent: Instance, at: Vector3, height: number, random: Random)
	local model = Instance.new("Model")
	model.Name = "DeadTree"
	model.Parent = parent
	local lean = Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1)) * height * 0.08
	local middle = at + Vector3.new(0, height * 0.5, 0) + lean
	local top = middle + Vector3.new(0, height * 0.45, 0) - lean * 0.6
	local width = height * 0.07
	kit.beam(model, "DeadTrunk", at - Vector3.new(0, 0.6, 0), middle, width, DEAD_WOOD, Enum.Material.Wood)
	kit.beam(model, "DeadTrunk", middle, top, width * 0.7, DEAD_WOOD, Enum.Material.Wood)
	local yaw = random:NextNumber(0, math.pi * 2)
	for branch = 1, random:NextInteger(3, 5) do
		local angle = yaw + branch * 2.3
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local t = random:NextNumber(0.45, 0.95)
		local from = if t < 0.5 then at + (middle - at) * (t * 2) else middle + (top - middle) * ((t - 0.5) * 2)
		local length = height * random:NextNumber(0.22, 0.38)
		local tip = from + out * length + Vector3.new(0, length * random:NextNumber(0.3, 0.8), 0)
		kit.beam(model, "DeadBranch", from, tip, width * 0.4, DEAD_WOOD, Enum.Material.Wood)
		-- Each branch forks into a twig or two.
		for twig = 1, random:NextInteger(1, 2) do
			local turn = angle + (if twig == 1 then 0.7 else -0.7)
			local twigTip = tip + Vector3.new(math.cos(turn), 0, math.sin(turn)) * length * 0.45 + Vector3.new(0, length * random:NextNumber(0.1, 0.45), 0)
			kit.beam(model, "DeadTwig", tip, twigTip, width * 0.22, DEAD_WOOD, Enum.Material.Wood)
		end
	end
end

-- A carved pumpkin with a candle-lit face, turned to `facing`.
local function pumpkin(kit: Kit, parent: Instance, at: Vector3, facing: Vector3, size: number, lit: boolean)
	local model = Instance.new("Model")
	model.Name = "JackOLantern"
	model.Parent = parent
	local frame = CFrame.lookAt(at + Vector3.new(0, size * 0.42, 0), at + Vector3.new(facing.X, size * 0.42, facing.Z))
	local body = kit.piece(model, "Pumpkin", Vector3.new(size, size, size), frame, PUMPKIN, Enum.Material.SmoothPlastic) :: Part
	body.Shape = Enum.PartType.Ball
	kit.piece(model, "PumpkinStem", Vector3.new(size * 0.14, size * 0.3, size * 0.14), frame * CFrame.new(0, size * 0.52, 0) * CFrame.Angles(0, 0, 0.25), Color3.fromRGB(86, 96, 46), Enum.Material.Wood)
	-- Eyes, a nose and a jagged grin glowing from inside.
	local depth = -size * 0.47
	for _, x in { -0.2, 0.2 } do
		kit.piece(model, "PumpkinEye", Vector3.new(size * 0.18, size * 0.16, 0.12), frame * CFrame.new(x * size, size * 0.1, depth) * CFrame.Angles(0, 0, x * 2), CANDLE, Enum.Material.Neon)
	end
	kit.piece(model, "PumpkinNose", Vector3.new(size * 0.1, size * 0.1, 0.12), frame * CFrame.new(0, -size * 0.03, depth - 0.02), CANDLE, Enum.Material.Neon)
	kit.piece(model, "PumpkinGrin", Vector3.new(size * 0.5, size * 0.1, 0.12), frame * CFrame.new(0, -size * 0.18, depth + 0.05), CANDLE, Enum.Material.Neon)
	for _, x in { -0.12, 0.12 } do
		kit.piece(model, "PumpkinTooth", Vector3.new(size * 0.08, size * 0.06, 0.13), frame * CFrame.new(x * size, -size * 0.13, depth + 0.03), PUMPKIN, Enum.Material.SmoothPlastic)
	end
	if lit then light(body, Color3.fromRGB(255, 150, 60), 9, 1) end
end

-- The cemetery gate where the trail leaves the camp: stone pillars with ball
-- finials, an iron arch with spikes and a green lantern, its two iron doors
-- swung wide open beside the trail.
local function gate(kit: Kit, parent: Instance, frame: CFrame, span: number)
	local model = Instance.new("Model")
	model.Name = "CemeteryGate"
	model.Parent = parent
	local pillar = 8
	for _, side in { -1, 1 } do
		local x = side * (span / 2 + 0.9)
		local foot = frame * Vector3.new(x, 0, 0)
		local low = kit.ground(foot.X, foot.Z).Y - frame.Position.Y
		kit.solid(kit.piece(model, "GatePillar", Vector3.new(1.8, pillar - low + 0.5, 1.8), frame * CFrame.new(x, (pillar + low - 0.5) / 2, 0), DARK_STONE, Enum.Material.Cobblestone))
		kit.piece(model, "PillarCap", Vector3.new(2.3, 0.5, 2.3), frame * CFrame.new(x, pillar + 0.25, 0), STONE, Enum.Material.Slate)
		local finial = kit.piece(model, "PillarFinial", Vector3.new(1.3, 1.3, 1.3), frame * CFrame.new(x, pillar + 1.1, 0), STONE, Enum.Material.Slate) :: Part
		finial.Shape = Enum.PartType.Ball
		-- The doors, swung open towards the camp.
		local hinge = frame * CFrame.new(side * span / 2, 0, 0) * CFrame.Angles(0, side * math.rad(-82), 0)
		local door = span / 2 - 0.2
		for bar = 0, 5 do
			local bx = -side * (0.2 + bar * door / 5)
			kit.piece(model, "GateBar", Vector3.new(0.14, 6.2, 0.14), hinge * CFrame.new(bx, 3.3, 0), IRON, Enum.Material.Metal)
			kit.piece(model, "GateSpike", Vector3.new(0.3, 0.45, 0.3), hinge * CFrame.new(bx, 6.6, 0) * CFrame.Angles(0, math.pi / 4, 0), IRON, Enum.Material.Metal)
		end
		for _, y in { 1, 5.6 } do
			kit.piece(model, "GateRail", Vector3.new(door, 0.16, 0.16), hinge * CFrame.new(-side * (0.2 + door / 2), y, 0), IRON, Enum.Material.Metal)
		end
	end
	-- The arch: a curve of iron between the pillar tops, spiked along its crown.
	local segments = 8
	local radius = span / 2 + 0.9
	local rise = 2.6
	local previous: Vector3? = nil
	for i = 0, segments do
		local t = i / segments
		local angle = math.pi * t
		local point = frame * Vector3.new(-math.cos(angle) * radius, pillar + 1.6 + math.sin(angle) * rise, 0)
		if previous then
			kit.beam(model, "GateArch", previous, point, 0.22, IRON, Enum.Material.Metal)
			kit.beam(model, "GateArch", previous - Vector3.new(0, 0.6, 0), point - Vector3.new(0, 0.6, 0), 0.14, IRON, Enum.Material.Metal)
		end
		if i > 0 and i < segments then
			kit.piece(model, "ArchSpike", Vector3.new(0.12, 0.8, 0.12), CFrame.new(point + Vector3.new(0, 0.5, 0)), IRON, Enum.Material.Metal)
		end
		previous = point
	end
	-- The lantern hanging from the top of the arch.
	local hang = frame * Vector3.new(0, pillar + 1.6 + rise, 0)
	kit.piece(model, "LanternChain", Vector3.new(0.08, 1.2, 0.08), CFrame.new(hang - Vector3.new(0, 0.6, 0)), IRON, Enum.Material.Metal)
	kit.piece(model, "LanternCage", Vector3.new(0.8, 0.12, 0.8), CFrame.new(hang - Vector3.new(0, 1.25, 0)), IRON, Enum.Material.Metal)
	local lamp = kit.piece(model, "GhostLantern", Vector3.new(0.55, 0.8, 0.55), CFrame.new(hang - Vector3.new(0, 1.75, 0)), GHOST, Enum.Material.Neon)
	lamp.CastShadow = false
	light(lamp, GHOST, 14, 1.2)
end

-- A stretch of spiked iron fence from `a` to `b`, standing on the ground.
local function fence(kit: Kit, parent: Instance, a: Vector3, b: Vector3)
	local length = (b - a).Magnitude
	local count = math.max(1, math.ceil(length / 2.4))
	local tops: { Vector3 } = {}
	for i = 0, count do
		local at = a + (b - a) * (i / count)
		local ground = kit.ground(at.X, at.Z)
		kit.solid(kit.piece(parent, "FencePost", Vector3.new(0.22, 3.6, 0.22), CFrame.new(ground + Vector3.new(0, 1.5, 0)), IRON, Enum.Material.Metal))
		kit.piece(parent, "FenceSpike", Vector3.new(0.34, 0.5, 0.34), CFrame.new(ground + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, math.pi / 4, 0), IRON, Enum.Material.Metal)
		tops[i + 1] = ground
	end
	for i = 1, count do
		local from, to = tops[i], tops[i + 1]
		for _, y in { 0.7, 2.7 } do
			local p, q = from + Vector3.new(0, y, 0), to + Vector3.new(0, y, 0)
			kit.solid(kit.piece(parent, "FenceRail", Vector3.new(0.12, 0.12, (q - p).Magnitude + 0.1), CFrame.lookAt((p + q) / 2, q), IRON, Enum.Material.Metal))
		end
	end
end

function Haunted.build(kit: Kit): Folder
	local folder = Instance.new("Folder")
	folder.Name = "HauntedScenery"
	-- Its own seed, so the alpine valley is laid out the same with or without it.
	local random = Random.new(1031)
	local placed: { Vector3 } = {}
	local function roomy(at: Vector3, gap: number): boolean
		for _, other in placed do
			if (Vector3.new(at.X - other.X, 0, at.Z - other.Z)).Magnitude < gap then return false end
		end
		return true
	end
	local lit = 0
	local function lantern(at: Vector3, facing: Vector3, size: number)
		-- A few of them cast light; the rest just glow.
		pumpkin(kit, folder, at, facing, size, lit < 3 and size > 1.6)
		if size > 1.6 and lit < 3 then lit += 1 end
		table.insert(placed, at)
	end

	-- The mausoleum and its graveyard first, so the dead trees stand round them.
	local base, drop = nil, 0
	for _, gap in { 12, 8, 5 } do
		base, drop = cryptSite(kit, random, gap)
		if base then break end
	end
	if base then
		local frame = base :: CFrame
		crypt(kit, folder, frame, drop)
		table.insert(placed, frame.Position)
		local w, d = Haunted.CRYPT.X + 2, Haunted.CRYPT.Z + 6
		local toCamp = Vector3.new(kit.camp.X - frame.Position.X, 0, kit.camp.Z - frame.Position.Z).Unit
		-- Somewhere open on the ground near the crypt, in its frame, or nil.
		local function spot(x: number, z: number, margin: number): Vector3?
			local at = frame * Vector3.new(x, 0, z)
			local ground = kit.ground(at.X, at.Z)
			if kit.clear(ground, margin) or not kit.spaced(ground, margin) or kit.steepness(at.X, at.Z) > 0.8 then return nil end
			return ground
		end
		-- The graveyard beside it: rows of headstones facing the camp, behind
		-- a spiked iron fence with an opening at the front.
		local yard = Instance.new("Model")
		yard.Name = "Graveyard"
		yard.Parent = folder
		local spacing = Haunted.GRAVES.spacing
		local left = -(w / 2 + 3)
		local right = left - Haunted.GRAVES.columns * spacing - 1
		local front, back = -d / 2 + 1, -d / 2 + 1 + Haunted.GRAVES.rows * spacing + 1
		for column = 0, Haunted.GRAVES.columns - 1 do
			for row = 0, Haunted.GRAVES.rows - 1 do
				local x = left - 0.5 - spacing / 2 - column * spacing + random:NextNumber(-0.4, 0.4)
				local z = front + 3.4 + row * spacing + random:NextNumber(-0.3, 0.3)
				local at = spot(x, z, 1.2)
				if at then
					local turn = random:NextNumber(-0.12, 0.12)
					headstone(kit, yard, CFrame.new(at :: Vector3) * frame.Rotation * CFrame.Angles(0, turn, 0), random:NextInteger(1, 3), random)
				end
			end
		end
		-- The fence runs round the yard, open in the middle of its front.
		local corners = { frame * Vector3.new(left, 0, front), frame * Vector3.new(right, 0, front), frame * Vector3.new(right, 0, back), frame * Vector3.new(left, 0, back) }
		local gapAt = (left + right) / 2
		fence(kit, yard, frame * Vector3.new(left, 0, front), frame * Vector3.new(gapAt + 1.6, 0, front))
		fence(kit, yard, frame * Vector3.new(gapAt - 1.6, 0, front), corners[2])
		fence(kit, yard, corners[2], corners[3])
		fence(kit, yard, corners[3], corners[4])
		fence(kit, yard, corners[4], corners[1])
		-- Jack-o'-lanterns on the crypt steps and at the graveyard's opening.
		for _, offset in { Vector3.new(-3.6, 0, -(d / 2 + 2)), Vector3.new(3.6, 0, -(d / 2 + 2)), Vector3.new(gapAt - 2.4, 0, front - 1), Vector3.new(gapAt + 2.6, 0, front - 1.2) } do
			local at = spot(offset.X, offset.Z, 0.5)
			if at then lantern(at :: Vector3, toCamp, if offset.Z < -(d / 2 + 1) then 1.8 else 1.4) end
		end
		-- Will-o'-wisps drifting over the graves.
		for i = 1, 4 do
			local at = frame * Vector3.new(random:NextNumber(right + 1, left - 1), 0, random:NextNumber(front + 2, back - 1))
			local wisp = kit.piece(folder, "WillOWisp", Vector3.new(0.6, 0.6, 0.6), CFrame.new(kit.ground(at.X, at.Z) + Vector3.new(0, random:NextNumber(2.5, 4.5), 0)), WISP, Enum.Material.Neon) :: Part
			wisp.Shape = Enum.PartType.Ball
			wisp.Transparency = 0.2
			if i == 1 then
				local sparkle = Instance.new("ParticleEmitter")
				sparkle.Name = "WispGlow"
				sparkle.Rate = 6
				sparkle.Lifetime = NumberRange.new(1, 2)
				sparkle.Speed = NumberRange.new(0.2, 0.6)
				sparkle.Color = ColorSequence.new(WISP)
				sparkle.LightEmission = 1
				sparkle.Size = NumberSequence.new(0.25, 0)
				sparkle.Parent = wisp
			end
		end
	else
		warn("[DiamondRush] Haunted: no open ground for the mausoleum, so it is left out.")
	end

	-- Dead trees across the meadows and round the camp.
	local trees = 0
	for attempt = 1, 2400 do
		if trees >= 32 then break end
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(kit.radius + 8, 220)
		local at = kit.ground(math.cos(angle) * distance, math.sin(angle) * distance)
		local farFromCrypt = base == nil or (Vector3.new(at.X, 0, at.Z) - Vector3.new((base :: CFrame).Position.X, 0, (base :: CFrame).Position.Z)).Magnitude > 34
		if farFromCrypt and not kit.clear(at, 4) and at.Y < 36 and kit.steepness(at.X, at.Z) < 0.6 and kit.spaced(at, 5) and roomy(at, 10) then
			deadTree(kit, folder, at, random:NextNumber(9, 16), random)
			table.insert(placed, at)
			trees += 1
		end
		if attempt % 64 == 0 then task.wait() end
	end
	-- Wisps drifting over the lake.
	for i = 1, 4 do
		local angle = i * math.pi / 2 + random:NextNumber(-0.4, 0.4)
		local at = kit.lake + Vector3.new(math.cos(angle) * random:NextNumber(6, 20), random:NextNumber(2, 4), math.sin(angle) * random:NextNumber(5, 15))
		local wisp = kit.piece(folder, "WillOWisp", Vector3.new(0.6, 0.6, 0.6), CFrame.new(at), WISP, Enum.Material.Neon) :: Part
		wisp.Shape = Enum.PartType.Ball
		wisp.Transparency = 0.2
	end
	-- The gate stands just past the spawn, where the trail leaves the camp,
	-- framing the mountain from the camp; its pillars stay beside the trail.
	local gateZ = kit.camp.Z - 9
	local gateAt = kit.ground(kit.pathCentre(gateZ), gateZ)
	local span = 7
	gate(kit, folder, CFrame.new(gateAt), span)
	-- Jack-o'-lanterns outside the gate pillars and round the camp, looking at the spawn.
	local spots = { gateAt + Vector3.new(-(span / 2 + 3), 0, 1.2), gateAt + Vector3.new(span / 2 + 3, 0, 1.2) }
	for _, offset in { Vector3.new(-13, 0, -3.5), Vector3.new(13, 0, -4.5), Vector3.new(-11.6, 0, -4.4) } do
		table.insert(spots, kit.camp + offset)
	end
	for index, spot in spots do
		local at = kit.ground(spot.X, spot.Z)
		lantern(at, Vector3.new(kit.camp.X - at.X, 0, kit.camp.Z + 2 - at.Z), if index == 3 or index == 4 then 1.8 else 1.4)
	end
	return folder
end

return Haunted
