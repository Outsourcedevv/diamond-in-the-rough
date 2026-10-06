--!strict
-- The sakura theme's own scenery: cherry trees in blossom across the meadows,
-- with fallen petals beneath them, a vermilion torii gate at the camp's
-- entrance framing the mountain, stone lanterns, and a shrine on a meadow in
-- view of the camp, behind its own little torii. Scenery builds it once,
-- alongside the alpine valley, and keeps it out of view until the theme is
-- chosen (see Scenery.setTheme). Like the rest of the scenery, nothing here
-- takes part in mining raycasts or touch events.
local Sakura = {}

-- What Scenery lends the theme: its part makers and where things may go.
export type Kit = {
	piece: (parent: Instance, name: string, size: Vector3, frame: CFrame, colour: Color3, material: Enum.Material, kind: string?) -> BasePart,
	beam: (parent: Instance, name: string, a: Vector3, b: Vector3, width: number, colour: Color3, material: Enum.Material) -> BasePart,
	solid: (BasePart) -> BasePart,
	ground: (x: number, z: number) -> Vector3,
	clear: (at: Vector3, margin: number) -> boolean, -- arena, camp, lake, path or leaderboards
	spaced: (at: Vector3, gap: number) -> boolean, -- clear of the valley's trees and rocks
	steepness: (x: number, z: number) -> number,
	pathCentre: (z: number) -> number,
	camp: Vector3,
	lake: Vector3,
	radius: number, -- the arena's clear radius
}

-- Blossom pinks from pale to deep, a shade richer than the control page's so
-- they stay pink under the game's bright sun and bloom.
local PINKS = {
	Color3.fromRGB(255, 212, 226),
	Color3.fromRGB(255, 194, 214),
	Color3.fromRGB(252, 176, 202),
	Color3.fromRGB(246, 158, 190),
	Color3.fromRGB(236, 140, 176),
}
local BARK = Color3.fromRGB(78, 56, 54)
local VERMILION = Color3.fromRGB(200, 50, 60)
local LACQUER = Color3.fromRGB(34, 28, 30)
local STONE = Color3.fromRGB(150, 146, 138)
local PLASTER = Color3.fromRGB(244, 238, 226)
local TIMBER = Color3.fromRGB(116, 80, 54)
local COPPER = Color3.fromRGB(88, 138, 120) -- a weathered copper roof
local GOLD = Color3.fromRGB(226, 182, 88)
local STRAW = Color3.fromRGB(214, 188, 120)

-- A cherry tree: a dark leaning trunk forking into three or four branches,
-- each ending in a puff of blossom, with a crown over the middle and a carpet
-- of fallen petals on the ground.
local function tree(kit: Kit, parent: Instance, at: Vector3, height: number, random: Random)
	local model = Instance.new("Model")
	model.Name = "SakuraTree"
	model.Parent = parent
	local lean = Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1)) * height * 0.06
	local fork = at + Vector3.new(0, height * 0.4, 0) + lean
	kit.beam(model, "SakuraTrunk", at - Vector3.new(0, 0.6, 0), fork, height * 0.08, BARK, Enum.Material.Wood)
	local tone = random:NextInteger(1, #PINKS - 1)
	local branches = random:NextInteger(3, 4)
	local yaw = random:NextNumber(0, math.pi * 2)
	local spread = height * 0.3
	for k = 1, branches do
		local angle = yaw + k / branches * math.pi * 2 + random:NextNumber(-0.3, 0.3)
		local tip = fork + Vector3.new(math.cos(angle) * spread, height * random:NextNumber(0.2, 0.32), math.sin(angle) * spread)
		kit.beam(model, "SakuraBranch", fork, tip, height * 0.04, BARK, Enum.Material.Wood)
		local size = height * random:NextNumber(0.4, 0.5)
		local colour = PINKS[math.clamp(tone + random:NextInteger(-1, 1), 1, #PINKS)]
		local blossom = kit.piece(model, "Blossom", Vector3.one * size, CFrame.new(tip + Vector3.new(0, size * 0.12, 0)), colour, Enum.Material.LeafyGrass)
		;(blossom :: Part).Shape = Enum.PartType.Ball
	end
	local crown = height * 0.56
	local top = kit.piece(model, "Blossom", Vector3.one * crown, CFrame.new(fork + Vector3.new(0, height * 0.42, 0)), PINKS[tone], Enum.Material.LeafyGrass)
	;(top :: Part).Shape = Enum.PartType.Ball
	-- Fallen petals: a thin pink disc, a little wider than the crown.
	local width = height * random:NextNumber(0.85, 1.05)
	local carpet = kit.piece(model, "FallenPetals", Vector3.new(0.1, width, width), CFrame.new(at + Vector3.new(0, 0.04, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		PINKS[math.min(tone + 1, #PINKS)], Enum.Material.Sand)
	;(carpet :: Part).Shape = Enum.PartType.Cylinder
	carpet.CastShadow = false
end

-- A torii gate standing at `frame`: its beams run along the frame's X axis and
-- its plaque faces the frame's +Z, towards whoever walks through it.
local function torii(kit: Kit, parent: Instance, frame: CFrame, span: number, tall: number?)
	local model = Instance.new("Model")
	model.Name = "Torii"
	model.Parent = parent
	local height = tall or 8.6
	local scale = height / 8.6
	local function at(x: number, y: number, z: number): Vector3
		return frame * Vector3.new(x, y, z)
	end
	for _, side in { -1, 1 } do
		local x = side * span / 2
		kit.solid(kit.beam(model, "ToriiPillar", at(x, -0.5, 0), at(x, height, 0), 0.8 * scale, VERMILION, Enum.Material.SmoothPlastic))
		kit.beam(model, "ToriiBase", at(x, -0.5, 0), at(x, 0.9 * scale, 0), 1.05 * scale, LACQUER, Enum.Material.SmoothPlastic)
	end
	-- The lower tie beam (nuki) runs through the pillars and out past them.
	kit.piece(model, "ToriiNuki", Vector3.new(span + 2.2 * scale, 0.5 * scale, 0.45 * scale), frame * CFrame.new(0, height - 2.1 * scale, 0), VERMILION, Enum.Material.SmoothPlastic)
	-- The top: a vermilion beam (shimaki) under a black lintel (kasagi) whose
	-- two halves sweep up towards their ends.
	kit.piece(model, "ToriiShimaki", Vector3.new(span + 2.8 * scale, 0.5 * scale, 0.75 * scale), frame * CFrame.new(0, height + 0.25 * scale, 0), VERMILION, Enum.Material.SmoothPlastic)
	local half = span / 2 + 2.1 * scale
	for _, side in { -1, 1 } do
		local piece = frame * CFrame.new(side * half / 2, height + 0.78 * scale, 0) * CFrame.Angles(0, 0, side * math.rad(3.5))
		kit.piece(model, "ToriiKasagi", Vector3.new(half + 0.15, 0.6 * scale, 1.05 * scale), piece, LACQUER, Enum.Material.SmoothPlastic)
	end
	-- The central strut carries a plaque with the diamond on it.
	kit.piece(model, "ToriiStrut", Vector3.new(0.45, 1.6, 0.4) * scale, frame * CFrame.new(0, height - 1.05 * scale, 0), VERMILION, Enum.Material.SmoothPlastic)
	local plaque = kit.piece(model, "ToriiPlaque", Vector3.new(1.1, 1.3, 0.12) * scale,
		frame * CFrame.new(0, height - 1.05 * scale, 0.26 * scale) * CFrame.Angles(0, math.pi, 0), LACQUER, Enum.Material.SmoothPlastic)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 1
	gui.Parent = plaque
	-- A gold diamond: a square turned on its corner.
	local mark = Instance.new("Frame")
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.fromScale(0.5, 0.5)
	mark.Size = UDim2.fromScale(0.5, 0.42)
	mark.SizeConstraint = Enum.SizeConstraint.RelativeXX
	mark.Rotation = 45
	mark.BackgroundColor3 = Color3.fromRGB(232, 190, 92)
	mark.BorderSizePixel = 0
	mark.Parent = gui
end

-- A stone lantern (tōrō) with a softly glowing fire box; no light of its own.
local function lantern(kit: Kit, parent: Instance, at: Vector3)
	local model = Instance.new("Model")
	model.Name = "StoneLantern"
	model.Parent = parent
	kit.solid(kit.piece(model, "LanternFoot", Vector3.new(1.5, 0.4, 1.5), CFrame.new(at + Vector3.new(0, 0.15, 0)), STONE, Enum.Material.Slate))
	kit.solid(kit.beam(model, "LanternPost", at + Vector3.new(0, 0.3, 0), at + Vector3.new(0, 2.1, 0), 0.6, STONE, Enum.Material.Slate))
	kit.piece(model, "LanternShelf", Vector3.new(1.3, 0.3, 1.3), CFrame.new(at + Vector3.new(0, 2.2, 0)), STONE, Enum.Material.Slate)
	kit.piece(model, "LanternBox", Vector3.new(0.95, 0.9, 0.95), CFrame.new(at + Vector3.new(0, 2.8, 0)), STONE, Enum.Material.Slate)
	-- The glow shows through windows on all four sides.
	local glow = kit.piece(model, "LanternGlow", Vector3.new(1.0, 0.5, 0.5), CFrame.new(at + Vector3.new(0, 2.82, 0)), Color3.fromRGB(255, 196, 128), Enum.Material.Neon)
	glow.CastShadow = false
	local across = kit.piece(model, "LanternGlow", Vector3.new(0.5, 0.5, 1.0), CFrame.new(at + Vector3.new(0, 2.82, 0)), Color3.fromRGB(255, 196, 128), Enum.Material.Neon)
	across.CastShadow = false
	kit.piece(model, "LanternRoof", Vector3.new(1.9, 0.3, 1.9), CFrame.new(at + Vector3.new(0, 3.38, 0)), STONE, Enum.Material.Slate)
	kit.piece(model, "LanternCap", Vector3.new(1.1, 0.3, 1.1), CFrame.new(at + Vector3.new(0, 3.66, 0)), STONE, Enum.Material.Slate)
	local jewel = kit.piece(model, "LanternJewel", Vector3.one * 0.5, CFrame.new(at + Vector3.new(0, 4.0, 0)), STONE, Enum.Material.Slate)
	;(jewel :: Part).Shape = Enum.PartType.Ball
end

-- A Shinto shrine (a hall with its entrance on the long side) on a stone
-- plinth. `frame` sits on the plinth's top, its front (-Z) facing the camp;
-- `drop` is how far the plinth reaches down to the lowest ground under it.
-- Returns how far in front of the centre its steps end.
local SHRINE_CLEARANCE = 18 -- studs from the shrine's centre kept free of trees
local function shrine(kit: Kit, parent: Instance, frame: CFrame, drop: number): number
	local model = Instance.new("Model")
	model.Name = "Shrine"
	model.Parent = parent
	local function put(name: string, size: Vector3, offset: CFrame, colour: Color3, material: Enum.Material, kind: string?): BasePart
		return kit.piece(model, name, size, frame * offset, colour, material, kind)
	end
	local function rod(name: string, a: Vector3, b: Vector3, width: number, colour: Color3, material: Enum.Material): BasePart
		return kit.beam(model, name, frame * a, frame * b, width, colour, material)
	end
	-- The plinth and the stone steps up to it.
	kit.solid(put("ShrinePlinth", Vector3.new(17, drop, 14), CFrame.new(0, -drop / 2, 0), STONE, Enum.Material.Slate))
	local steps = math.max(2, math.ceil(drop / 0.6))
	for i = 1, steps do
		local top = -i * drop / (steps + 1)
		local depth = top + drop + 0.5
		kit.solid(put("ShrineStep", Vector3.new(6, depth, 0.95), CFrame.new(0, top - depth / 2, -7 - (i - 0.5) * 0.9), STONE, Enum.Material.Slate))
	end
	-- The hall: x from -6 to 6, z from -4 to 5, on a raised plank floor.
	local cz, w, d = 0.5, 6, 4.5
	kit.solid(put("ShrineFloor", Vector3.new(2 * w + 1, 0.5, 2 * d + 1), CFrame.new(0, 0.25, cz), Color3.fromRGB(150, 106, 68), Enum.Material.WoodPlanks))
	local top = 6
	for _, x in { -w, -2, 2, w } do
		for _, z in { cz - d, cz + d } do
			kit.solid(rod("ShrinePillar", Vector3.new(x, 0.5, z), Vector3.new(x, top, z), 0.55, VERMILION, Enum.Material.SmoothPlastic))
		end
	end
	for _, x in { -w, w } do
		kit.solid(rod("ShrinePillar", Vector3.new(x, 0.5, cz), Vector3.new(x, top, cz), 0.55, VERMILION, Enum.Material.SmoothPlastic))
	end
	-- Head beams round the top, and a dark frieze above them.
	for _, z in { cz - d, cz + d } do
		put("ShrineBeam", Vector3.new(2 * w + 0.6, 0.5, 0.45), CFrame.new(0, top, z), VERMILION, Enum.Material.SmoothPlastic)
		put("ShrineFrieze", Vector3.new(2 * w + 0.6, 0.55, 0.4), CFrame.new(0, top + 0.52, z), TIMBER, Enum.Material.Wood)
	end
	for _, x in { -w, w } do
		put("ShrineBeam", Vector3.new(0.45, 0.5, 2 * d + 0.6), CFrame.new(x, top, cz), VERMILION, Enum.Material.SmoothPlastic)
	end
	-- White plaster walls on three sides; the front has paper screens either
	-- side of an open doorway.
	kit.solid(put("ShrineWall", Vector3.new(2 * w, top - 0.5, 0.3), CFrame.new(0, (top + 0.5) / 2, cz + d - 0.05), PLASTER, Enum.Material.Plaster))
	for _, x in { -w, w } do
		kit.solid(put("ShrineWall", Vector3.new(0.3, top - 0.5, 2 * d), CFrame.new(x * 0.99, (top + 0.5) / 2, cz), PLASTER, Enum.Material.Plaster))
	end
	for _, side in { -1, 1 } do
		local x = side * (w + 2) / 2
		kit.solid(put("ShrineScreen", Vector3.new(w - 2.3, 4, 0.15), CFrame.new(x, 2.6, cz - d), Color3.fromRGB(250, 244, 228), Enum.Material.SmoothPlastic))
		put("ShrineTransom", Vector3.new(w - 2.3, 1.15, 0.2), CFrame.new(x, 5.2, cz - d), PLASTER, Enum.Material.Plaster)
		-- The screens' wooden lattice.
		for _, dx in { -0.9, 0, 0.9 } do
			put("ShrineLattice", Vector3.new(0.08, 4, 0.08), CFrame.new(x + dx, 2.6, cz - d - 0.1), TIMBER, Enum.Material.Wood)
		end
		for _, y in { 1.3, 2.6, 3.9 } do
			put("ShrineLattice", Vector3.new(w - 2.3, 0.08, 0.08), CFrame.new(x, y, cz - d - 0.1), TIMBER, Enum.Material.Wood)
		end
	end
	-- Inside: an altar with a round golden mirror, seen through the doorway.
	put("ShrineAltar", Vector3.new(3, 1.1, 1.2), CFrame.new(0, 1.05, cz + d - 1), LACQUER, Enum.Material.Wood)
	local mirror = put("ShrineMirror", Vector3.new(0.12, 1.5, 1.5), CFrame.new(0, 2.6, cz + d - 0.35) * CFrame.Angles(0, math.pi / 2, 0), GOLD, Enum.Material.Foil)
	;(mirror :: Part).Shape = Enum.PartType.Cylinder
	-- The roof: copper, its eaves curving out over each long side (a steeper
	-- upper run and a shallower lower one), closed by timber gables.
	local ridge = 9.4
	local length = 2 * w + 4.4
	for _, side in { -1, 1 } do
		local upper, lower = math.rad(30), math.rad(14)
		local breakY = ridge - 4.6 * math.tan(upper)
		local spans = { { 0, 4.6, ridge, upper }, { 4.6, 6.9, breakY, lower } }
		for _, span in spans do
			local from, to, y0, angle = span[1], span[2], span[3], span[4]
			local run = to - from
			local slope = run / math.cos(angle) + 0.1
			local centre = Vector3.new(0, y0 - run / 2 * math.tan(angle), cz + side * (from + run / 2))
			put("ShrineRoof", Vector3.new(length, 0.35, slope), CFrame.new(centre) * CFrame.Angles(side * angle, 0, 0), COPPER, Enum.Material.RoofShingles)
		end
	end
	local gable = 2.4
	for _, x in { -w, w } do
		for _, side in { -1, 1 } do
			local turn = if side > 0 then CFrame.Angles(0, math.pi, 0) else CFrame.identity
			put("ShrineGable", Vector3.new(0.3, gable, d), CFrame.new(x, ridge - 0.2 - gable / 2, cz + side * d / 2) * turn, TIMBER, Enum.Material.Wood, "WedgePart")
		end
	end
	put("ShrineRidge", Vector3.new(length + 0.6, 0.6, 0.7), CFrame.new(0, ridge + 0.15, cz), LACQUER, Enum.Material.Wood)
	-- Crossed finials (chigi) at both ends of the ridge, and short logs
	-- (katsuogi) along it with gilded ends.
	for _, x in { -length / 2, length / 2 } do
		for _, tilt in { -1, 1 } do
			put("ShrineChigi", Vector3.new(0.22, 3, 0.35), CFrame.new(x, ridge + 0.55, cz) * CFrame.Angles(tilt * math.rad(35), 0, 0), LACQUER, Enum.Material.Wood)
		end
	end
	for _, x in { -3.5, 0, 3.5 } do
		rod("ShrineKatsuogi", Vector3.new(x, ridge + 0.65, cz - 0.7), Vector3.new(x, ridge + 0.65, cz + 0.7), 0.45, LACQUER, Enum.Material.Wood)
		for _, z in { -0.72, 0.72 } do
			rod("ShrineGilt", Vector3.new(x, ridge + 0.65, cz + z - 0.06), Vector3.new(x, ridge + 0.65, cz + z + 0.06), 0.47, GOLD, Enum.Material.Foil)
		end
	end
	-- A sacred straw rope (shimenawa) across the doorway with white paper
	-- streamers (shide), and a bell with its rope.
	local rope = { Vector3.new(-2.4, top - 0.35, cz - d - 0.35), Vector3.new(-1.2, top - 0.75, cz - d - 0.35), Vector3.new(0, top - 0.9, cz - d - 0.35),
		Vector3.new(1.2, top - 0.75, cz - d - 0.35), Vector3.new(2.4, top - 0.35, cz - d - 0.35) }
	for i = 1, #rope - 1 do
		rod("ShrineRope", rope[i], rope[i + 1], 0.38, STRAW, Enum.Material.Fabric)
	end
	for _, x in { -1.6, -0.6, 0.6, 1.6 } do
		local hang = top - (if math.abs(x) < 1 then 1.05 else 0.85)
		for k = 0, 2 do
			put("ShrineShide", Vector3.new(0.26, 0.32, 0.03), CFrame.new(x + (if k % 2 == 0 then 0 else 0.12), hang - 0.2 - k * 0.3, cz - d - 0.38), Color3.fromRGB(252, 252, 248), Enum.Material.SmoothPlastic)
		end
	end
	local bell = put("ShrineBell", Vector3.one * 0.7, CFrame.new(0, top - 1.45, cz - d - 0.6), GOLD, Enum.Material.Foil)
	;(bell :: Part).Shape = Enum.PartType.Ball
	rod("ShrineBellRope", Vector3.new(0, top - 1.8, cz - d - 0.6), Vector3.new(0, 1.7, cz - d - 0.7), 0.14, VERMILION, Enum.Material.Fabric)
	-- An offering box at the top of the steps, and lanterns at the front corners.
	kit.solid(put("ShrineOfferingBox", Vector3.new(2.4, 1, 1), CFrame.new(0, 1, cz - d - 1.6), TIMBER, Enum.Material.WoodPlanks))
	put("ShrineOfferingSlats", Vector3.new(2.3, 0.06, 0.9), CFrame.new(0, 1.53, cz - d - 1.6), LACQUER, Enum.Material.Wood)
	for _, x in { -7.2, 7.2 } do
		lantern(kit, model, frame * Vector3.new(x, 0, -6))
	end
	return 7 + steps * 0.9
end

-- Where the shrine goes: a flat, open meadow ahead of the camp, off to one
-- side of the mountain so it shows from the spawn, facing the camp. Returns
-- the frame on top of its plinth and how deep the plinth goes, or nil.
-- `gap` keeps it that far from the valley's trees, rocks and flowers.
local function shrineSite(kit: Kit, random: Random, gap: number): (CFrame?, number)
	local best: CFrame? = nil
	local bestDrop, bestScore = 0, math.huge
	for attempt = 1, 400 do
		local angle = random:NextNumber(-1, 1) * math.rad(62)
		local distance = random:NextNumber(60, 125)
		local spot = kit.camp + Vector3.new(math.sin(angle), 0, -math.cos(angle)) * distance
		local centre = kit.ground(spot.X, spot.Z)
		if not kit.clear(centre, 13) and centre.Y < 24 and kit.steepness(centre.X, centre.Z) < 0.4 and kit.spaced(centre, gap) then
			local flat = Vector3.new(centre.X, 0, centre.Z)
			local facing = Vector3.new(kit.camp.X - centre.X, 0, kit.camp.Z - centre.Z).Unit
			local base = CFrame.lookAt(flat, flat + facing)
			local gate = base * Vector3.new(0, 0, -14)
			if not kit.clear(kit.ground(gate.X, gate.Z), 3) then
				-- The ground under the plinth's corners, edges and steps.
				local low, high = math.huge, -math.huge
				for _, offset in { Vector3.new(-8.5, 0, -9.7), Vector3.new(8.5, 0, -9.7), Vector3.new(-8.5, 0, 7), Vector3.new(8.5, 0, 7),
					Vector3.new(0, 0, 0), Vector3.new(-8.5, 0, 0), Vector3.new(8.5, 0, 0), Vector3.new(0, 0, 7), Vector3.new(0, 0, -9.7) } do
					local at = base * offset
					local y = kit.ground(at.X, at.Z).Y
					low, high = math.min(low, y), math.max(high, y)
				end
				local score = math.abs(angle) + distance / 150 + (high - low) * 0.3
				if high - low < 2.5 and score < bestScore then
					bestScore = score
					best = base + Vector3.new(0, high + 0.9, 0)
					bestDrop = high + 0.9 - low + 0.6
				end
			end
		end
		if attempt % 64 == 0 then task.wait() end
	end
	return best, bestDrop
end

-- Builds the theme's scenery into a new folder (not yet parented).
function Sakura.build(kit: Kit): Folder
	local folder = Instance.new("Folder")
	folder.Name = "SakuraScenery"
	-- Its own seed, so the alpine valley is laid out the same with or without it.
	local random = Random.new(3903)
	local planted: { Vector3 } = {}
	-- The shrine goes first, so the cherry trees grow round it.
	-- Somewhere wide open if there is room, else among the flowers.
	local site, drop = nil, 0
	for _, gap in { 14, 9, 5 } do
		site, drop = shrineSite(kit, random, gap)
		if site then break end
	end
	if site then
		local approach = shrine(kit, folder, site, drop)
		-- Its own small torii on the approach from the camp, facing the camp.
		local gate = site * Vector3.new(0, 0, -(approach + 2.5))
		torii(kit, folder, CFrame.new(kit.ground(gate.X, gate.Z)) * site.Rotation * CFrame.Angles(0, math.pi, 0), 6, 7)
	else
		warn("[DiamondRush] Sakura: no flat open meadow for the shrine, so it is left out.")
	end
	local function roomy(at: Vector3, gap: number): boolean
		if site and (Vector3.new(at.X - site.Position.X, 0, at.Z - site.Position.Z)).Magnitude < SHRINE_CLEARANCE then return false end
		for _, other in planted do
			if (Vector3.new(at.X - other.X, 0, at.Z - other.Z)).Magnitude < gap then return false end
		end
		return kit.spaced(at, 6)
	end
	local function plant(at: Vector3)
		tree(kit, folder, at, random:NextNumber(11, 16), random)
		table.insert(planted, at)
	end
	-- A ring of blossom just outside the camp frames the view from the spawn.
	for attempt = 1, 160 do
		if #planted >= 12 then break end
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(30, 46)
		local at = kit.ground(kit.camp.X + math.cos(angle) * distance, kit.camp.Z + math.sin(angle) * distance)
		if not kit.clear(at, 4) and at.Y < 20 and kit.steepness(at.X, at.Z) < 0.6 and roomy(at, 10) then plant(at) end
		if attempt % 64 == 0 then task.wait() end
	end
	-- Groves over the low meadows and round the lake.
	for attempt = 1, 2400 do
		if #planted >= 48 then break end
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(kit.radius + 10, 210)
		local at = kit.ground(math.cos(angle) * distance, math.sin(angle) * distance)
		local grove = math.noise(at.X / 70, at.Z / 70, 61) > -0.2
		if grove and not kit.clear(at, 4) and at.Y < 32 and kit.steepness(at.X, at.Z) < 0.6 and roomy(at, 9) then plant(at) end
		if attempt % 64 == 0 then task.wait() end
	end
	-- The torii stands just past the spawn, where the trail leaves the camp,
	-- so it frames the mountain from the camp; its pillars stay beside the trail.
	local gateZ = kit.camp.Z - 9
	torii(kit, folder, CFrame.new(kit.ground(kit.pathCentre(gateZ), gateZ)), 8)
	-- Stone lanterns at the camp's edge and on the lake dock.
	for _, offset in { Vector3.new(-13, 0, -3), Vector3.new(13, 0, -4) } do
		local spot = kit.camp + offset
		lantern(kit, folder, kit.ground(spot.X, spot.Z))
	end
	lantern(kit, folder, kit.lake + Vector3.new(-17, 0.65, 2.3))
	return folder
end

return Sakura
