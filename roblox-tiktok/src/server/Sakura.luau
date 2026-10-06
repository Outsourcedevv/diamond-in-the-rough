--!strict
-- The sakura theme's own scenery: cherry trees in blossom across the meadows,
-- with fallen petals beneath them, a vermilion torii gate at the camp's
-- entrance framing the mountain, and stone lanterns. Scenery builds it once,
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

-- A torii gate across the trail, beams along X, its plaque facing the camp.
local function torii(kit: Kit, parent: Instance, centre: Vector3, span: number)
	local model = Instance.new("Model")
	model.Name = "Torii"
	model.Parent = parent
	local tall = 8.6
	for _, side in { -1, 1 } do
		local foot = centre + Vector3.new(side * span / 2, 0, 0)
		kit.solid(kit.beam(model, "ToriiPillar", foot - Vector3.new(0, 0.5, 0), foot + Vector3.new(0, tall, 0), 0.8, VERMILION, Enum.Material.SmoothPlastic))
		kit.beam(model, "ToriiBase", foot - Vector3.new(0, 0.5, 0), foot + Vector3.new(0, 0.9, 0), 1.05, LACQUER, Enum.Material.SmoothPlastic)
	end
	-- The lower tie beam (nuki) runs through the pillars and out past them.
	kit.piece(model, "ToriiNuki", Vector3.new(span + 2.2, 0.5, 0.45), CFrame.new(centre + Vector3.new(0, tall - 2.1, 0)), VERMILION, Enum.Material.SmoothPlastic)
	-- The top: a vermilion beam (shimaki) under a black lintel (kasagi) whose
	-- two halves sweep up towards their ends.
	kit.piece(model, "ToriiShimaki", Vector3.new(span + 2.8, 0.5, 0.75), CFrame.new(centre + Vector3.new(0, tall + 0.25, 0)), VERMILION, Enum.Material.SmoothPlastic)
	local half = span / 2 + 2.1
	for _, side in { -1, 1 } do
		local frame = CFrame.new(centre + Vector3.new(side * half / 2, tall + 0.78, 0)) * CFrame.Angles(0, 0, side * math.rad(3.5))
		kit.piece(model, "ToriiKasagi", Vector3.new(half + 0.15, 0.6, 1.05), frame, LACQUER, Enum.Material.SmoothPlastic)
	end
	-- The central strut carries a plaque with the diamond on it.
	kit.piece(model, "ToriiStrut", Vector3.new(0.45, 1.6, 0.4), CFrame.new(centre + Vector3.new(0, tall - 1.05, 0)), VERMILION, Enum.Material.SmoothPlastic)
	local plaque = kit.piece(model, "ToriiPlaque", Vector3.new(1.1, 1.3, 0.12),
		CFrame.lookAt(centre + Vector3.new(0, tall - 1.05, 0.26), centre + Vector3.new(0, tall - 1.05, 1)), LACQUER, Enum.Material.SmoothPlastic)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 1
	gui.Parent = plaque
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Text = "💎"
	text.Parent = gui
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

-- Builds the theme's scenery into a new folder (not yet parented).
function Sakura.build(kit: Kit): Folder
	local folder = Instance.new("Folder")
	folder.Name = "SakuraScenery"
	-- Its own seed, so the alpine valley is laid out the same with or without it.
	local random = Random.new(3903)
	local planted: { Vector3 } = {}
	local function roomy(at: Vector3, gap: number): boolean
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
	torii(kit, folder, kit.ground(kit.pathCentre(gateZ), gateZ), 8)
	-- Stone lanterns at the camp's edge and on the lake dock.
	for _, offset in { Vector3.new(-13, 0, -3), Vector3.new(13, 0, -4) } do
		local spot = kit.camp + offset
		lantern(kit, folder, kit.ground(spot.X, spot.Z))
	end
	lantern(kit, folder, kit.lake + Vector3.new(-17, 0.65, 2.3))
	return folder
end

return Sakura
