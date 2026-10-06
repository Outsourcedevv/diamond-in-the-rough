--!strict
-- The farm theme's own scenery: the mountain stands in a ranch corral, a
-- timber board fence all the way round the arena except for the opening
-- where the trail comes in from the camp, under a log arch. Beyond the fence, in view of the spawn, is a red
-- gambrel-roofed barn with a silo, a cornfield with a scarecrow, a windpump,
-- a tractor, hay bales and cows grazing by a water trough. Scenery builds it
-- once, alongside the alpine valley, and keeps it out of view until the theme
-- is chosen (see Scenery.setTheme). Nothing here takes part in mining
-- raycasts or touch events; the fence, gate, barn and silo can be bumped into
-- (the fence is low enough to hop).
local Sakura = require(script.Parent.Sakura)

local Farm = {}

type Kit = Sakura.Kit

local BARN_RED = Color3.fromRGB(156, 46, 38)
local TRIM = Color3.fromRGB(240, 234, 220)
local ROOF = Color3.fromRGB(76, 72, 70)
local TIMBER = Color3.fromRGB(132, 104, 76)
local LOG = Color3.fromRGB(108, 80, 54)
local STONE = Color3.fromRGB(128, 124, 116)
local HAY = Color3.fromRGB(224, 188, 96)
local DARK = Color3.fromRGB(46, 36, 30)

Farm.GATE = 9 -- studs of open trail between the gateposts
Farm.BARN = Vector3.new(15, 15, 21) -- the barn's width, height to the ridge and depth, as drawn
Farm.BARN_SCALE = 1.5 -- then made this much bigger (the silo with it)
local S = Farm.BARN_SCALE

-- Where the trail crosses the fence's ring: the angle round the arena (from
-- +Z, towards +X), so the opening sits on the trail wherever it bends.
local function gateAngle(kit: Kit, radius: number): number
	local x = 0
	for _ = 1, 4 do
		x = kit.pathCentre(math.sqrt(radius * radius - x * x))
	end
	return math.atan2(x, math.sqrt(radius * radius - x * x))
end

-- The ranch fence round the arena, and its gate arch over the trail.
local function fence(kit: Kit, parent: Instance, random: Random)
	local model = Instance.new("Model")
	model.Name = "RanchFence"
	model.Parent = parent
	local radius = kit.radius - 3
	local gate = gateAngle(kit, radius)
	local half = math.asin(Farm.GATE / 2 / radius)
	local arc = math.pi * 2 - half * 2
	local count = math.ceil(arc * radius / 6.5)
	local posts: { Vector3 } = {}
	for i = 0, count do
		local angle = gate + half + arc * i / count
		posts[i + 1] = kit.ground(math.sin(angle) * radius, math.cos(angle) * radius)
	end
	for i, at in posts do
		local centre = Vector3.new(0, at.Y + 1.8, 0)
		if i > 1 and i < #posts then
			kit.solid(kit.piece(model, "FencePost", Vector3.new(0.5, 4.4, 0.5), CFrame.lookAt(at + Vector3.new(0, 1.8, 0), centre), LOG, Enum.Material.Wood))
		end
		local nextAt = posts[i + 1]
		if nextAt then
			-- Three boards nailed on the outside of the posts.
			local mid = (at + nextAt) / 2
			local outward = Vector3.new(mid.X, 0, mid.Z).Unit * 0.32
			for _, y in { 1.0, 2.1, 3.2 } do
				local a, b = at + outward + Vector3.new(0, y, 0), nextAt + outward + Vector3.new(0, y, 0)
				local tone = random:NextNumber(0.88, 1.06)
				local colour = Color3.new(TIMBER.R * tone, TIMBER.G * tone, TIMBER.B * tone)
				kit.solid(kit.piece(model, "FenceRail", Vector3.new((b - a).Magnitude + 0.3, 0.45, 0.16), CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0), colour, Enum.Material.WoodPlanks))
			end
		end
	end
	-- The gate: two tall log posts at the ends of the fence and a log beam
	-- across them with knee braces.
	local left, right = posts[1], posts[#posts]
	local across = Vector3.new(right.X - left.X, 0, right.Z - left.Z).Unit
	for _, at in { left, right } do
		kit.solid(kit.beam(model, "GatePost", at - Vector3.new(0, 0.6, 0), at + Vector3.new(0, 11, 0), 0.95, LOG, Enum.Material.Wood))
		kit.piece(model, "GateCap", Vector3.new(1.3, 0.3, 1.3), CFrame.new(at + Vector3.new(0, 11.1, 0)), DARK, Enum.Material.Wood)
	end
	local top = math.max(left.Y, right.Y) + 10.3
	local a, b = Vector3.new(left.X, top, left.Z) - across * 1.2, Vector3.new(right.X, top, right.Z) + across * 1.2
	kit.beam(model, "GateBeam", a, b, 0.75, LOG, Enum.Material.Wood)
	kit.beam(model, "GateBrace", Vector3.new(left.X, top - 2.2, left.Z), Vector3.new(left.X, top - 0.2, left.Z) + across * 2, 0.35, LOG, Enum.Material.Wood)
	kit.beam(model, "GateBrace", Vector3.new(right.X, top - 2.2, right.Z), Vector3.new(right.X, top - 0.2, right.Z) - across * 2, 0.35, LOG, Enum.Material.Wood)
end

-- Where the barn goes: open, fairly flat ground in view of the spawn (to one
-- side of the mountain), off the arena, camp and boards, with room for its cornfield beside it. Returns its
-- frame (on the highest ground under it, front facing the camp) and how far
-- its foundation must reach down, or nil.
local FIELD = { width = 22, from = -12, to = 16 } -- beside the barn, along its depth
local function barnSite(kit: Kit, random: Random, gap: number): (CFrame?, number)
	local best: CFrame? = nil
	local bestDrop, bestScore = 0, math.huge
	local w, d = Farm.BARN.X * S, Farm.BARN.Z * S
	local siloOffset = Vector3.new(w / 2 + 4.8 * S, 0, d / 2 - 4.5 * S)
	for attempt = 1, 500 do
		-- To one side of the mountain, so it does not hide the barn from the spawn.
		local angle = (if random:NextNumber() < 0.5 then -1 else 1) * random:NextNumber(math.rad(32), math.rad(72))
		local distance = random:NextNumber(70, 140)
		local spot = kit.camp + Vector3.new(math.sin(angle), 0, -math.cos(angle)) * distance
		local centre = kit.ground(spot.X, spot.Z)
		if not kit.clear(centre, 16 * S) and centre.Y < 26 and kit.steepness(centre.X, centre.Z) < 0.45 and kit.spaced(centre, gap) then
			local flat = Vector3.new(centre.X, 0, centre.Z)
			local facing = Vector3.new(kit.camp.X - centre.X, 0, kit.camp.Z - centre.Z).Unit
			local base = CFrame.lookAt(flat, flat + facing)
			local low, high = math.huge, -math.huge
			for _, offset in { Vector3.new(-w / 2, 0, -d / 2), Vector3.new(w / 2, 0, -d / 2), Vector3.new(-w / 2, 0, d / 2), Vector3.new(w / 2, 0, d / 2),
				Vector3.new(0, 0, 0), siloOffset } do
				local at = base * offset
				local y = kit.ground(at.X, at.Z).Y
				low, high = math.min(low, y), math.max(high, y)
			end
			local silo = base * siloOffset
			if high - low < 4 and not kit.clear(silo, 5 * S) and kit.spaced(silo, 4 * S) then
				-- How much of the cornfield beside it is open ground.
				local open = 0
				for i = 0, 3 do
					for j = 0, 3 do
						local at = base * Vector3.new(-(w / 2 + 5 + FIELD.width * i / 3), 0, FIELD.from + (FIELD.to - FIELD.from) * j / 3)
						local ground = kit.ground(at.X, at.Z)
						if not kit.clear(ground, 1) and kit.spaced(ground, 2) and kit.steepness(at.X, at.Z) < 0.7 then open += 1 end
					end
				end
				-- And whether a tree stands in front of it, hiding it from the camp.
				local hidden = 0
				for _, z in { -d / 2 - 5, -d / 2 - 11, -d / 2 - 17 } do
					for _, x in { -5, 0, 5 } do
						if not kit.spaced(kit.ground((base * Vector3.new(x, 0, z)).X, (base * Vector3.new(x, 0, z)).Z), 4) then hidden += 1 end
					end
				end
				local score = math.abs(math.abs(angle) - math.rad(48)) * 0.6 + distance / 150 + (high - low) * 0.3 + (16 - open) * 0.12 + hidden * 0.35
				if score < bestScore then
					bestScore = score
					best = base + Vector3.new(0, high + 0.6, 0)
					bestDrop = high + 0.6 - low + 0.6
				end
			end
		end
		if attempt % 64 == 0 then task.wait() end
	end
	return best, bestDrop
end

-- The barn and its silo, built in `base`'s frame: the floor at its origin,
-- the front (with the big doors and the hayloft) facing -Z. It is drawn at
-- Farm.BARN's size, its foundation reaching down `worldDrop` once enlarged,
-- then made BARN_SCALE times bigger.
local function barn(kit: Kit, parent: Instance, base: CFrame, worldDrop: number): Model
	local model = Instance.new("Model")
	model.Name = "Barn"
	model.Parent = parent
	local drop = worldDrop / S
	-- A height in the world, as drawn before the barn is enlarged.
	local function drawn(y: number): number
		return base.Position.Y + (y - base.Position.Y) / S
	end
	local w, d = Farm.BARN.X, Farm.BARN.Z
	local eave, breakX, breakY, ridge = 8, 5, 12.6, Farm.BARN.Y
	local function put(name: string, size: Vector3, offset: CFrame, colour: Color3, material: Enum.Material, kind: string?): BasePart
		return kit.piece(model, name, size, base * offset, colour, material, kind)
	end
	local function wall(name: string, size: Vector3, offset: CFrame)
		kit.solid(put(name, size, offset, BARN_RED, Enum.Material.WoodPlanks))
	end
	-- A board from (x1, y1) to (x2, y2) across the barn's width, `depth` long,
	-- raised `lift` off the line on its upper side.
	local function slab(name: string, x1: number, y1: number, x2: number, y2: number, z: number, depth: number, thick: number, lift: number, colour: Color3, material: Enum.Material)
		local angle = math.atan2(y2 - y1, x2 - x1)
		local up = Vector3.new(-math.sin(angle), math.cos(angle), 0) * lift
		local length = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) + 0.3
		put(name, Vector3.new(length, thick, depth), CFrame.new((x1 + x2) / 2 + up.X, (y1 + y2) / 2 + up.Y, z) * CFrame.Angles(0, 0, angle), colour, material)
	end
	kit.solid(put("BarnFoundation", Vector3.new(w + 0.8, drop, d + 0.8), CFrame.new(0, -drop / 2, 0), STONE, Enum.Material.Cobblestone))
	-- Walls, with the big door opening in the front.
	wall("BarnWall", Vector3.new(w, eave, 0.4), CFrame.new(0, eave / 2, d / 2))
	for _, side in { -1, 1 } do
		wall("BarnWall", Vector3.new(0.4, eave, d), CFrame.new(side * w / 2, eave / 2, 0))
		wall("BarnWall", Vector3.new((w - 7) / 2, eave, 0.4), CFrame.new(side * (3.5 + (w - 7) / 4), eave / 2, -d / 2))
	end
	wall("BarnWall", Vector3.new(7, eave - 7, 0.4), CFrame.new(0, 7 + (eave - 7) / 2, -d / 2))
	-- Gambrel gables front and back: a middle panel and four wedges.
	for _, z in { -d / 2, d / 2 } do
		wall("BarnGable", Vector3.new(breakX * 2, breakY - eave, 0.4), CFrame.new(0, (eave + breakY) / 2, z))
		for _, side in { -1, 1 } do
			-- Each wedge rises towards the middle of the barn.
			local turn = if side > 0 then CFrame.Angles(0, -math.pi / 2, 0) else CFrame.Angles(0, math.pi / 2, 0)
			kit.solid(put("BarnGable", Vector3.new(0.4, breakY - eave, w / 2 - breakX), CFrame.new(side * (breakX + (w / 2 - breakX) / 2), (eave + breakY) / 2, z) * turn, BARN_RED, Enum.Material.WoodPlanks, "WedgePart"))
			kit.solid(put("BarnGable", Vector3.new(0.4, ridge - breakY, breakX), CFrame.new(side * breakX / 2, (breakY + ridge) / 2, z) * turn, BARN_RED, Enum.Material.WoodPlanks, "WedgePart"))
		end
	end
	-- The roof: steep lower slopes and shallow upper ones, overhanging the walls.
	for _, side in { -1, 1 } do
		local outer, inner = side * (w / 2 + 0.7), side * breakX
		local x1, y1, x2, y2 = math.min(outer, inner), if side < 0 then eave - 0.5 else breakY, math.max(outer, inner), if side < 0 then breakY else eave - 0.5
		slab("BarnRoof", x1, y1, x2, y2, 0, d + 1.6, 0.35, 0.3, ROOF, Enum.Material.RoofShingles)
		local u1, v1, u2, v2 = math.min(inner, 0), if side < 0 then breakY else ridge, math.max(inner, 0), if side < 0 then ridge else breakY
		slab("BarnRoof", u1, v1, u2, v2, 0, d + 1.6, 0.35, 0.3, ROOF, Enum.Material.RoofShingles)
		-- White trim along the front gable's edge.
		slab("BarnTrim", x1, y1, x2, y2, -d / 2 - 0.25, 0.2, 0.4, 0, TRIM, Enum.Material.WoodPlanks)
		slab("BarnTrim", u1, v1, u2, v2, -d / 2 - 0.25, 0.2, 0.4, 0, TRIM, Enum.Material.WoodPlanks)
	end
	put("BarnRidge", Vector3.new(0.6, 0.35, d + 1.8), CFrame.new(0, ridge + 0.35, 0), ROOF, Enum.Material.Wood)
	put("BarnTrim", Vector3.new(w + 0.2, 0.4, 0.2), CFrame.new(0, eave, -d / 2 - 0.25), TRIM, Enum.Material.WoodPlanks)
	for _, x in { -w / 2, w / 2 } do
		for _, z in { -d / 2, d / 2 } do
			put("BarnTrim", Vector3.new(0.55, eave, 0.55), CFrame.new(x, eave / 2, z), TRIM, Enum.Material.WoodPlanks)
		end
	end
	-- The big doors: closed, framed in white with a white X on each leaf.
	local front = -d / 2 - 0.22
	put("BarnDoor", Vector3.new(7, 7, 0.2), CFrame.new(0, 3.5, front + 0.12), Color3.fromRGB(140, 40, 34), Enum.Material.WoodPlanks)
	put("BarnTrim", Vector3.new(7.5, 0.35, 0.16), CFrame.new(0, 7.05, front), TRIM, Enum.Material.WoodPlanks)
	for _, x in { -3.6, 0, 3.6 } do
		put("BarnTrim", Vector3.new(0.35, 7, 0.16), CFrame.new(x, 3.5, front), TRIM, Enum.Material.WoodPlanks)
	end
	local cross = math.atan2(6.6, 3.2)
	for _, x in { -1.8, 1.8 } do
		for _, sign in { -1, 1 } do
			put("BarnTrim", Vector3.new(math.sqrt(6.6 ^ 2 + 3.2 ^ 2), 0.3, 0.12), CFrame.new(x, 3.5, front - 0.02) * CFrame.Angles(0, 0, sign * cross), TRIM, Enum.Material.WoodPlanks)
		end
	end
	put("DoorTrack", Vector3.new(15, 0.25, 0.3), CFrame.new(0, 7.45, front - 0.1), DARK, Enum.Material.Metal)
	-- The hayloft: an open door with hay showing, and a hoist beam above it.
	local loft = (eave + breakY) / 2 + 0.3
	put("Hayloft", Vector3.new(3, 3.2, 0.1), CFrame.new(0, loft, front + 0.1), DARK, Enum.Material.Wood)
	for _, x in { -1.6, 1.6 } do
		put("BarnTrim", Vector3.new(0.3, 3.6, 0.16), CFrame.new(x, loft, front), TRIM, Enum.Material.WoodPlanks)
	end
	put("BarnTrim", Vector3.new(3.5, 0.3, 0.16), CFrame.new(0, loft + 1.75, front), TRIM, Enum.Material.WoodPlanks)
	put("HayBale", Vector3.new(2.6, 1.1, 1.2), CFrame.new(0, loft - 1.05, front + 0.2), HAY, Enum.Material.Grass)
	put("HoistBeam", Vector3.new(0.5, 0.5, 2.6), CFrame.new(0, ridge - 0.7, -d / 2 - 1.1), LOG, Enum.Material.Wood)
	put("HoistRope", Vector3.new(0.08, 2.6, 0.08), CFrame.new(0, ridge - 2.2, -d / 2 - 2.1), Color3.fromRGB(196, 170, 120), Enum.Material.Fabric)
	-- Windows down each side.
	for _, side in { -1, 1 } do
		for _, z in { -d / 4, d / 4 } do
			put("BarnTrim", Vector3.new(0.12, 2.4, 2.4), CFrame.new(side * (w / 2 + 0.22), 4.8, z), TRIM, Enum.Material.WoodPlanks)
			put("BarnWindow", Vector3.new(0.14, 1.8, 1.8), CFrame.new(side * (w / 2 + 0.25), 4.8, z), Color3.fromRGB(52, 60, 70), Enum.Material.Glass)
		end
	end
	-- A cupola with a weathervane on the ridge.
	put("Cupola", Vector3.new(2.2, 1.8, 2.2), CFrame.new(0, ridge + 1.3, 0), TRIM, Enum.Material.WoodPlanks)
	for _, side in { -1, 1 } do
		slab("CupolaRoof", if side < 0 then -1.6 else 0, if side < 0 then ridge + 2.1 else ridge + 3.1, if side < 0 then 0 else 1.6, if side < 0 then ridge + 3.1 else ridge + 2.1, 0, 2.8, 0.25, 0.15, ROOF, Enum.Material.RoofShingles)
	end
	put("VanePole", Vector3.new(0.12, 2.2, 0.12), CFrame.new(0, ridge + 4.2, 0), DARK, Enum.Material.Metal)
	put("VaneArrow", Vector3.new(0.12, 0.12, 2), CFrame.new(0, ridge + 4.7, 0) * CFrame.Angles(0, 0.6, 0), DARK, Enum.Material.Metal)
	put("VaneCross", Vector3.new(1.2, 0.08, 0.08), CFrame.new(0, ridge + 4.1, 0), DARK, Enum.Material.Metal)
	-- A warm lamp over the doors.
	put("LampArm", Vector3.new(0.15, 0.15, 1), CFrame.new(0, 8.2, -d / 2 - 0.6), DARK, Enum.Material.Metal)
	local lamp = put("BarnLamp", Vector3.new(0.6, 0.35, 0.6), CFrame.new(0, 7.95, -d / 2 - 1.05), Color3.fromRGB(255, 200, 124), Enum.Material.Neon)
	lamp.CastShadow = false
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 192, 122)
	light.Range = 14
	light.Brightness = 0.8
	light.Shadows = false
	light.Parent = lamp
	-- The silo behind one side: concrete staves, iron hoops and a domed cap.
	local siloAt = base * Vector3.new(w / 2 + 4.8, 0, d / 2 - 4.5)
	-- Its foot reaches the ground where the silo stands once enlarged.
	local siloFinal = base * Vector3.new((w / 2 + 4.8) * S, 0, (d / 2 - 4.5) * S)
	local foot = drawn(kit.ground(siloFinal.X, siloFinal.Z).Y - 0.6)
	local height = base.Position.Y + 21
	kit.solid(kit.beam(model, "Silo", Vector3.new(siloAt.X, foot, siloAt.Z), Vector3.new(siloAt.X, height, siloAt.Z), 7, Color3.fromRGB(196, 190, 178), Enum.Material.Concrete))
	for _, y in { 4, 9, 14, 19 } do
		local at = base.Position.Y + y
		kit.beam(model, "SiloHoop", Vector3.new(siloAt.X, at, siloAt.Z), Vector3.new(siloAt.X, at + 0.25, siloAt.Z), 7.16, Color3.fromRGB(70, 70, 72), Enum.Material.Metal)
	end
	local dome = kit.piece(model, "SiloDome", Vector3.new(7.1, 7.1, 7.1), CFrame.new(siloAt.X, height, siloAt.Z), Color3.fromRGB(178, 182, 186), Enum.Material.Metal) :: Part
	dome.Shape = Enum.PartType.Ball
	put("SiloChute", Vector3.new(1.1, 17, 1.1), CFrame.new(w / 2 + 1.5, 8.5, d / 2 - 4.5), BARN_RED, Enum.Material.WoodPlanks)
	kit.enlarge(model, base.Position, S)
	return model
end

-- A blocky cow at `at` on the ground, facing `facing`; grazing ones lower their heads.
local function cow(kit: Kit, parent: Instance, at: Vector3, facing: Vector3, grazing: boolean)
	local model = Instance.new("Model")
	model.Name = "Cow"
	model.Parent = parent
	local frame = CFrame.lookAt(at, at + facing)
	local white, black, pink = Color3.fromRGB(238, 234, 226), Color3.fromRGB(38, 34, 34), Color3.fromRGB(232, 162, 160)
	local function put(name: string, size: Vector3, offset: CFrame, colour: Color3)
		kit.piece(model, name, size, frame * offset, colour, Enum.Material.SmoothPlastic)
	end
	put("CowBody", Vector3.new(1.6, 1.5, 3.2), CFrame.new(0, 2.05, 0), white)
	put("CowPatch", Vector3.new(1.66, 0.8, 1), CFrame.new(0, 2.3, -0.6), black)
	put("CowPatch", Vector3.new(1.66, 0.7, 0.8), CFrame.new(0, 1.85, 0.9), black)
	for _, x in { -0.55, 0.55 } do
		for _, z in { -1.2, 1.2 } do
			put("CowLeg", Vector3.new(0.4, 1.4, 0.4), CFrame.new(x, 0.7, z), white)
		end
	end
	local head = if grazing then CFrame.new(0, 1.35, -1.95) * CFrame.Angles(math.rad(-35), 0, 0) else CFrame.new(0, 2.6, -1.95)
	put("CowHead", Vector3.new(1, 1, 1.1), head, white)
	put("CowSnout", Vector3.new(0.9, 0.5, 0.3), head * CFrame.new(0, -0.2, -0.65), pink)
	for _, x in { -0.65, 0.65 } do
		put("CowEar", Vector3.new(0.4, 0.15, 0.22), head * CFrame.new(x, 0.35, 0.2), black)
	end
	put("CowTail", Vector3.new(0.14, 1.2, 0.14), CFrame.new(0, 2, 1.65), black)
	put("CowUdder", Vector3.new(0.6, 0.3, 0.6), CFrame.new(0, 1.2, 0.7), pink)
end

-- A little red tractor, its front facing -Z of `frame`.
local function tractor(kit: Kit, parent: Instance, frame: CFrame)
	local model = Instance.new("Model")
	model.Name = "Tractor"
	model.Parent = parent
	local red, black, yellow = Color3.fromRGB(176, 40, 32), Color3.fromRGB(34, 32, 32), Color3.fromRGB(232, 184, 52)
	local function put(name: string, size: Vector3, offset: CFrame, colour: Color3, material: Enum.Material)
		kit.piece(model, name, size, frame * offset, colour, material)
	end
	local function wheel(x: number, y: number, z: number, size: number, width: number)
		kit.beam(model, "TractorWheel", frame * Vector3.new(x - width / 2, y, z), frame * Vector3.new(x + width / 2, y, z), size, black, Enum.Material.Rubber)
		kit.beam(model, "TractorHub", frame * Vector3.new(x - width / 2 - 0.03, y, z), frame * Vector3.new(x + width / 2 + 0.03, y, z), size * 0.45, yellow, Enum.Material.Metal)
	end
	put("TractorBody", Vector3.new(1.5, 1, 3.6), CFrame.new(0, 1.7, 0), red, Enum.Material.Metal)
	put("TractorHood", Vector3.new(1.3, 1, 2.1), CFrame.new(0, 2.6, -0.75), red, Enum.Material.Metal)
	put("TractorGrille", Vector3.new(1.2, 0.9, 0.1), CFrame.new(0, 2.6, -1.82), black, Enum.Material.Metal)
	put("TractorSeat", Vector3.new(0.9, 0.25, 0.8), CFrame.new(0, 2.75, 1.15), black, Enum.Material.Fabric)
	put("TractorSeat", Vector3.new(0.9, 0.9, 0.2), CFrame.new(0, 3.2, 1.55), black, Enum.Material.Fabric)
	put("TractorWheelArch", Vector3.new(3.6, 0.2, 2), CFrame.new(0, 3.1, 1.1), red, Enum.Material.Metal)
	kit.beam(model, "TractorStack", frame * Vector3.new(0.35, 3, -1.2), frame * Vector3.new(0.35, 4.4, -1.2), 0.22, black, Enum.Material.Metal)
	kit.beam(model, "TractorSteering", frame * Vector3.new(0, 3.3, 0.35), frame * Vector3.new(0, 3.45, 0.55), 0.8, black, Enum.Material.Metal)
	wheel(-1.35, 1.5, 1.1, 3, 0.8)
	wheel(1.35, 1.5, 1.1, 3, 0.8)
	wheel(-0.85, 0.7, -1.5, 1.4, 0.45)
	wheel(0.85, 0.7, -1.5, 1.4, 0.45)
end

-- A windpump: a steel lattice tower with a bladed wheel and tail vane, the
-- wheel facing -Z of `frame` (on the ground).
local function windpump(kit: Kit, parent: Instance, frame: CFrame)
	local model = Instance.new("Model")
	model.Name = "Windpump"
	model.Parent = parent
	local steel, blade = Color3.fromRGB(150, 152, 150), Color3.fromRGB(200, 200, 194)
	local h = 17
	local function leg(sx: number, sz: number, y: number): Vector3
		local spread = 2.2 - 1.7 * y / h
		return frame * Vector3.new(sx * spread, y, sz * spread)
	end
	local corners = { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }
	for i, c in corners do
		local foot = leg(c[1], c[2], 0)
		local ground = kit.ground(foot.X, foot.Z).Y - frame.Position.Y
		kit.solid(kit.beam(model, "PumpLeg", leg(c[1], c[2], ground - 0.4), leg(c[1], c[2], h), 0.25, steel, Enum.Material.Metal))
		local n = corners[i % 4 + 1]
		for _, y in { 4.5, 9, 13.5 } do
			kit.beam(model, "PumpGirt", leg(c[1], c[2], y), leg(n[1], n[2], y), 0.14, steel, Enum.Material.Metal)
		end
	end
	kit.piece(model, "PumpPlatform", Vector3.new(1.8, 0.2, 1.8), frame * CFrame.new(0, h, 0), steel, Enum.Material.Metal)
	local hub = frame * CFrame.new(0, h + 1.2, -0.9)
	kit.beam(model, "PumpHub", hub * Vector3.new(0, 0, -0.3), hub * Vector3.new(0, 0, 0.6), 0.6, Color3.fromRGB(70, 70, 72), Enum.Material.Metal)
	for k = 0, 11 do
		kit.piece(model, "PumpBlade", Vector3.new(0.7, 2.4, 0.08), hub * CFrame.Angles(0, 0, k * math.pi / 6) * CFrame.new(0, 1.85, -0.2) * CFrame.Angles(0, 0.35, 0), blade, Enum.Material.Metal)
	end
	kit.beam(model, "PumpBoom", hub * Vector3.new(0, 0, 0.3), hub * Vector3.new(0, 0, 4.2), 0.16, steel, Enum.Material.Metal)
	kit.piece(model, "PumpVane", Vector3.new(0.08, 1.6, 2.2), hub * CFrame.new(0, 0.2, 4.6), Color3.fromRGB(176, 40, 32), Enum.Material.Metal)
	kit.beam(model, "PumpRod", frame * Vector3.new(0, 0.6, 0), frame * Vector3.new(0, h, 0), 0.1, Color3.fromRGB(70, 70, 72), Enum.Material.Metal)
end

-- Builds the theme's scenery into a new folder (not yet parented).
function Farm.build(kit: Kit): Folder
	local folder = Instance.new("Folder")
	folder.Name = "FarmScenery"
	-- Its own seed, so the alpine valley is laid out the same with or without it.
	local random = Random.new(6131)
	fence(kit, folder, random)
	local site, drop = nil, 0
	for _, gap in { 12, 8, 5 } do
		site, drop = barnSite(kit, random, gap)
		if site then break end
	end
	if site == nil then
		warn("[DiamondRush] Farm: no open ground for the barn, so it is left out.")
		return folder
	end
	local base = site :: CFrame
	barn(kit, folder, base, drop)
	-- The yard is laid out round the barn's enlarged size.
	local w, d = Farm.BARN.X * S, Farm.BARN.Z * S
	local flatLook = Vector3.new(base.LookVector.X, 0, base.LookVector.Z)
	-- A point's place in the barn's frame (across, along), ignoring height.
	local function toLocal(at: Vector3): Vector3
		local offset, right = at - base.Position, base.RightVector
		return Vector3.new(offset.X * right.X + offset.Z * right.Z, 0, -(offset.X * flatLook.X + offset.Z * flatLook.Z))
	end
	-- Somewhere open on the ground near the barn, in its frame, or nil.
	local function spot(x: number, z: number, margin: number): Vector3?
		local at = base * Vector3.new(x, 0, z)
		local ground = kit.ground(at.X, at.Z)
		if kit.clear(ground, margin) or not kit.spaced(ground, margin) or kit.steepness(at.X, at.Z) > 0.8 then return nil end
		return ground
	end
	-- The cornfield beside the barn: rows of corn on ridged earth, broken
	-- where a tree or rock stands in the way, with a scarecrow keeping watch.
	local field = Instance.new("Model")
	field.Name = "Cornfield"
	field.Parent = folder
	local rows = 10
	for i = 0, rows - 1 do
		local x = -(w / 2 + 5 + FIELD.width * i / (rows - 1))
		local run: { Vector3 } = {}
		local function plant()
			if #run >= 3 then
				local a, b = run[1], run[#run]
				local corn = Color3.fromRGB(92 + (i % 3) * 6, 132 + (i % 2) * 8, 50)
				local length = (b - a).Magnitude + 2
				local along = CFrame.lookAt((a + b) / 2, b)
				kit.piece(field, "FieldRidge", Vector3.new(1.6, 0.6, length + 0.6), along, Color3.fromRGB(104, 78, 54), Enum.Material.Ground)
				kit.piece(field, "Corn", Vector3.new(1, 2.8, length), along * CFrame.new(0, 1.5, 0), corn, Enum.Material.LeafyGrass)
				kit.piece(field, "CornTassels", Vector3.new(0.6, 0.3, length - 0.4), along * CFrame.new(0, 3.05, 0), Color3.fromRGB(222, 192, 104), Enum.Material.Grass)
			end
			run = {}
		end
		for z = FIELD.from, FIELD.to, 2 do
			local at = spot(x, z, 1.5)
			if at then table.insert(run, at) else plant() end
		end
		plant()
		if i % 3 == 2 then task.wait() end
	end
	local scarecrowAt = spot(-(w / 2 + 5 + FIELD.width / 2) + 1.2, FIELD.from - 2.5, 1)
	if scarecrowAt then
		local at = scarecrowAt :: Vector3
		local frame = CFrame.lookAt(at, at + flatLook)
		local model = Instance.new("Model")
		model.Name = "Scarecrow"
		model.Parent = field
		kit.piece(model, "ScarecrowPost", Vector3.new(0.25, 5.4, 0.25), frame * CFrame.new(0, 2.4, 0), LOG, Enum.Material.Wood)
		kit.piece(model, "ScarecrowArms", Vector3.new(3.4, 0.25, 0.25), frame * CFrame.new(0, 3.9, 0), LOG, Enum.Material.Wood)
		kit.piece(model, "ScarecrowShirt", Vector3.new(1.3, 1.6, 0.6), frame * CFrame.new(0, 3.5, 0), Color3.fromRGB(70, 96, 150), Enum.Material.Fabric)
		kit.piece(model, "ScarecrowHead", Vector3.new(0.9, 0.95, 0.9), frame * CFrame.new(0, 4.85, 0), HAY, Enum.Material.Grass)
		kit.beam(model, "ScarecrowHat", frame * Vector3.new(0, 5.3, 0), frame * Vector3.new(0, 5.4, 0), 1.9, Color3.fromRGB(196, 160, 92), Enum.Material.Fabric)
		kit.beam(model, "ScarecrowHat", frame * Vector3.new(0, 5.35, 0), frame * Vector3.new(0, 5.95, 0), 1, Color3.fromRGB(196, 160, 92), Enum.Material.Fabric)
	end
	-- The windpump at the field's far corner, its wheel to the camp.
	for _, offset in { Vector3.new(-(w / 2 + 2), 0, d / 2 + 7), Vector3.new(-(w / 2 + 8), 0, FIELD.to + 6), Vector3.new(-3, 0, d / 2 + 8) } do
		local at = spot(offset.X, offset.Z, 3)
		if at then
			windpump(kit, folder, CFrame.lookAt(at :: Vector3, (at :: Vector3) + flatLook))
			break
		end
	end
	-- A tractor by the barn, square bales stacked at its door and cows
	-- grazing round a water trough.
	local tractorAt = spot(w / 2 + 3.5, -d / 2 - 3, 2.5)
	if tractorAt then
		tractor(kit, folder, CFrame.new(tractorAt :: Vector3) * base.Rotation * CFrame.Angles(0, math.rad(-25), 0))
	end
	local balesAt = spot(-w / 2 + 1.5, -d / 2 - 2.8, 1.5)
	if balesAt then
		local frame = CFrame.new(balesAt :: Vector3) * base.Rotation
		for row, count in { 3, 2, 1 } do
			for k = 1, count do
				local x = (k - (count + 1) / 2) * 2.5
				kit.piece(folder, "HayBale", Vector3.new(2.4, 1.15, 1.3), frame * CFrame.new(x, 0.45 + (row - 1) * 1.15, 0) * CFrame.Angles(0, random:NextNumber(-0.06, 0.06), 0), HAY, Enum.Material.Grass)
			end
		end
	end
	-- The pasture: in front of the barn if it is open there, else beside or behind it.
	local pasture: Vector3? = nil
	for _, offset in { Vector3.new(2, 0, -d / 2 - 13), Vector3.new(4, 0, -d / 2 - 9), Vector3.new(w / 2 + 13, 0, -6), Vector3.new(w / 2 + 12, 0, d / 2 + 8), Vector3.new(-4, 0, d / 2 + 12) } do
		if spot(offset.X, offset.Z, 2) then
			pasture = offset
			break
		end
	end
	local troughAt = pasture and spot((pasture :: Vector3).X, (pasture :: Vector3).Z, 2)
	if pasture and troughAt then
		local centre = pasture :: Vector3
		local frame = CFrame.new(troughAt :: Vector3) * base.Rotation
		kit.solid(kit.piece(folder, "WaterTrough", Vector3.new(3.8, 1, 1.5), frame * CFrame.new(0, 0.45, 0), TIMBER, Enum.Material.WoodPlanks))
		kit.piece(folder, "TroughWater", Vector3.new(3.4, 0.1, 1.1), frame * CFrame.new(0, 0.92, 0), Color3.fromRGB(70, 118, 132), Enum.Material.Glass)
		local cows = 0
		for attempt = 1, 40 do
			if cows >= 4 then break end
			local angle = attempt * 2.4
			local distance = 3.5 + (attempt % 4) * 2.2
			local local_ = centre + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
			local at = spot(local_.X, local_.Z, 2)
			if at then
				-- Roughly towards the trough, each at its own angle.
				local turn = angle + math.pi + random:NextNumber(-0.6, 0.6)
				cow(kit, folder, at :: Vector3, base:VectorToWorldSpace(Vector3.new(math.cos(turn), 0, math.sin(turn))), cows % 2 == 0)
				cows += 1
			end
		end
	end
	-- Round bales lie about in the grass, clear of the barn, field and pasture.
	local placed = 0
	for attempt = 1, 60 do
		if placed >= 5 then break end
		local at = spot(random:NextNumber(-w / 2 - 20, w / 2 + 14), random:NextNumber(-d / 2 - 22, d / 2 + 12), 2.5)
		local local_ = at and toLocal(at :: Vector3)
		if at and local_ and not (math.abs(local_.X) < w / 2 + 9 and math.abs(local_.Z) < d / 2 + 6) and local_.X > -(w / 2 + 3)
			and (pasture == nil or (local_ - (pasture :: Vector3)).Magnitude > 16) then
			local ground = at :: Vector3
			local roll = Vector3.new(math.cos(attempt), 0, math.sin(attempt)) * 1.5
			kit.beam(folder, "RoundBale", ground + Vector3.new(0, 1.4, 0) - roll, ground + Vector3.new(0, 1.4, 0) + roll, 3, Color3.fromRGB(206, 170, 84), Enum.Material.Grass)
			placed += 1
		end
	end
	return folder
end

return Farm
