--!strict
-- The royal spawn: a closed marble palace floating in the sky, far from the
-- mountain valley, where every player arrives. Walls and ceilings all round,
-- so no sky shows anywhere inside; chandeliers, sconces and lamps light it.
--
--   * The grand hallway: players spawn at one end and look down a long royal
--     blue carpet, between marble columns with gold sconces and royal blue
--     banners, under a row of chandeliers, to the throne room.
--   * Four rooms open off the hallway, two on each side, one per game:
--     Diamond in the Rough and Chalkboard Count on the left, Diamond Climb
--     and a Coming soon room (behind a closed gold gate) on the right. Each
--     game's room is dressed for it and has a glowing portal at the back:
--     walk into it, or press E at it, to join that game (another way to join
--     besides the games menu on the side of the screen). A drawn emblem over
--     each door says which game it is.
--   * The throne room: a round, domed hall at the far end where the giant
--     diamond turns slowly over a stepped dais (each client spins it, see
--     LobbyView).
-- A How to Play board beside the carpet opens the on-screen guide. Nothing in
-- the palace is lettered (lettered signs render badly): emblems are drawn.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("DiamondRush")
local DiamondShape = require(Shared:WaitForChild("DiamondShape"))

local Lobby = {}

-- High above, and far enough from the valley that its shadow never reaches it.
Lobby.ORIGIN = Vector3.new(0, 300, 2600)
Lobby.DIAMOND_SIZE = 6
Lobby.DIAMOND_HEIGHT = 10 -- above the floor

-- The palace's plan, in studs from ORIGIN (the throne room's centre, on the
-- floor). The hallway runs along +Z from the throne room to the entrance end.
Lobby.HALL_WIDTH = 44 -- wall to wall
Lobby.HALL_HEIGHT = 36
Lobby.HALL_START = 34 -- where the hallway meets the throne room
Lobby.HALL_END = 214 -- the entrance end wall
Lobby.THRONE_RADIUS = 40 -- the throne room's inner wall
Lobby.THRONE_HEIGHT = 44
Lobby.ROOM_DEPTH = 50 -- from the hallway wall to a room's back wall
Lobby.ROOM_LENGTH = 52 -- along the hallway
Lobby.ROOM_HEIGHT = 30
Lobby.DOOR_WIDTH = 18
Lobby.DOOR_HEIGHT = 22
Lobby.SPAWN_Z = 196
-- The rooms: which side (-1 left, +1 right, seen from the spawn looking down
-- the hallway), how far along it, and the game its portal joins (nil: the
-- Coming soon room, closed off by a gate).
export type Room = { key: string, name: string, side: number, z: number, place: string?, colour: Color3 }
Lobby.ROOMS = {
	{ key = "rough", name = "Diamond in the Rough", side = -1, z = 166, place = "rough", colour = Color3.fromRGB(110, 220, 255) },
	{ key = "climb", name = "Diamond Climb", side = 1, z = 166, place = "climb", colour = Color3.fromRGB(176, 128, 255) },
	{ key = "chalk", name = "Chalkboard Count", side = -1, z = 96, place = "chalk", colour = Color3.fromRGB(120, 230, 150) },
	{ key = "soon", name = "Coming soon", side = 1, z = 96, place = nil, colour = Color3.fromRGB(224, 178, 72) },
} :: { Room }

local MARBLE = Color3.fromRGB(242, 240, 235)
local MARBLE_SHADE = Color3.fromRGB(222, 218, 210)
local MARBLE_DARK = Color3.fromRGB(196, 190, 182)
local GOLD = Color3.fromRGB(224, 178, 72)
local ROYAL = Color3.fromRGB(34, 52, 140)
local WARM = Color3.fromRGB(255, 214, 150)
local FLAME = Color3.fromRGB(255, 224, 160)

export type Portal = { part: BasePart, prompt: ProximityPrompt, place: string }
export type Built = { model: Model, spawn: SpawnLocation, diamond: Model, board: Model, portals: { Portal } }

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

-- A straight beam from `a` to `b`, `width` wide and `height` tall.
local function beam(parent: Instance, name: string, a: Vector3, b: Vector3, width: number, height: number, colour: Color3, material: Enum.Material, solid: boolean?): Part
	local length = (b - a).Magnitude
	return piece(parent, name, Vector3.new(width, height, length), CFrame.lookAt((a + b) / 2, b), colour, material, solid)
end

local function light(parent: Instance, colour: Color3, range: number, brightness: number): PointLight
	local glow = Instance.new("PointLight")
	glow.Color = colour
	glow.Range = range
	glow.Brightness = brightness
	glow.Shadows = false
	glow.Parent = parent
	return glow
end

-- A drawing on a part's front face: frames placed by scale (x, y, w, h).
-- `gem` turns a square on its corner; `round` rounds it off.
type Mark = { x: number, y: number, w: number, h: number, colour: Color3, gem: boolean?, round: boolean?, square: boolean?, rotation: number? }
local function draw(part: BasePart, marks: { Mark }, pixels: number?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixels or 30
	gui.LightInfluence = 0.6
	gui.Parent = part
	for _, mark in marks do
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(mark.x, mark.y)
		frame.Size = UDim2.fromScale(mark.w, mark.h)
		if mark.gem or mark.square then frame.SizeConstraint = Enum.SizeConstraint.RelativeYY end
		frame.Rotation = if mark.gem then 45 else mark.rotation or 0
		frame.BackgroundColor3 = mark.colour
		frame.BorderSizePixel = 0
		frame.Parent = gui
		if mark.round then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.2, 0)
			corner.Parent = frame
		end
	end
end

-- Each room's emblem over its door: drawn, not lettered.
local EMBLEMS: { [string]: { Mark } } = {
	-- A mountain (a grey square on its corner, its lower half under the
	-- ground line) with snow on its peak and the diamond beside it.
	rough = {
		{ x = 0.42, y = 0.78, w = 0.9, h = 0.9, colour = Color3.fromRGB(128, 128, 136), gem = true },
		{ x = 0.42, y = 0.33, w = 0.26, h = 0.26, colour = Color3.fromRGB(250, 250, 255), gem = true },
		{ x = 0.5, y = 0.92, w = 1, h = 0.18, colour = Color3.fromRGB(28, 34, 60) },
		{ x = 0.76, y = 0.42, w = 0.22, h = 0.22, colour = Color3.fromRGB(110, 220, 255), gem = true },
	},
	-- Stepped platforms climbing to a violet crystal.
	climb = {
		{ x = 0.2, y = 0.8, w = 0.2, h = 0.08, colour = GOLD },
		{ x = 0.38, y = 0.64, w = 0.2, h = 0.08, colour = GOLD },
		{ x = 0.56, y = 0.48, w = 0.2, h = 0.08, colour = GOLD },
		{ x = 0.74, y = 0.32, w = 0.2, h = 0.08, colour = GOLD },
		{ x = 0.74, y = 0.16, w = 0.16, h = 0.16, colour = Color3.fromRGB(176, 128, 255), gem = true },
	},
	-- A green chalkboard in a wooden frame with chalk tally marks.
	chalk = {
		{ x = 0.5, y = 0.5, w = 0.84, h = 0.78, colour = Color3.fromRGB(150, 104, 62) },
		{ x = 0.5, y = 0.5, w = 0.76, h = 0.64, colour = Color3.fromRGB(44, 86, 62) },
		{ x = 0.26, y = 0.48, w = 0.03, h = 0.34, colour = Color3.fromRGB(240, 240, 232) },
		{ x = 0.32, y = 0.48, w = 0.03, h = 0.34, colour = Color3.fromRGB(240, 240, 232) },
		{ x = 0.38, y = 0.48, w = 0.03, h = 0.34, colour = Color3.fromRGB(240, 240, 232) },
		{ x = 0.44, y = 0.48, w = 0.03, h = 0.34, colour = Color3.fromRGB(240, 240, 232) },
		{ x = 0.35, y = 0.48, w = 0.3, h = 0.03, colour = Color3.fromRGB(240, 240, 232), rotation = -30 },
		{ x = 0.64, y = 0.48, w = 0.03, h = 0.34, colour = Color3.fromRGB(240, 240, 232) },
		{ x = 0.7, y = 0.48, w = 0.03, h = 0.34, colour = Color3.fromRGB(240, 240, 232) },
	},
	-- Three gold dots: more to come.
	soon = {
		{ x = 0.3, y = 0.5, w = 0.16, h = 0.16, colour = GOLD, square = true, round = true },
		{ x = 0.5, y = 0.5, w = 0.16, h = 0.16, colour = GOLD, square = true, round = true },
		{ x = 0.7, y = 0.5, w = 0.16, h = 0.16, colour = GOLD, square = true, round = true },
	},
}

function Lobby.build(parent: Instance): Built
	local O = Lobby.ORIGIN
	local function at(x: number, y: number, z: number): Vector3
		return O + Vector3.new(x, y, z)
	end
	-- An axis-aligned block between two corners (in studs from ORIGIN).
	local function block(into: Instance, name: string, a: Vector3, b: Vector3, colour: Color3, material: Enum.Material, solid: boolean?): Part
		local low = Vector3.new(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
		local high = Vector3.new(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
		return piece(into, name, high - low, CFrame.new(O + (low + high) / 2), colour, material, solid)
	end
	local model = Instance.new("Model")
	model.Name = "Lobby"
	model.Parent = parent

	local W = Lobby.HALL_WIDTH / 2 -- the hallway's inner walls stand at x = ±W
	local H = Lobby.HALL_HEIGHT
	local Z0, Z1 = Lobby.HALL_START, Lobby.HALL_END
	local R = Lobby.THRONE_RADIUS
	local RH = Lobby.THRONE_HEIGHT
	local DOOR = Lobby.DOOR_WIDTH / 2

	-- The throne room ----------------------------------------------------------
	-- The floor, sunk 0.05 below the hallway's so the two never flicker where
	-- they meet.
	disc(model, "Floor", O, O.Y, (R + 4) * 2, 4, MARBLE, Enum.Material.Marble, true)
	-- Gold inlay: an outer ring, an inner ring and eight rays between them.
	disc(model, "InlayRing", O, O.Y + 0.05, 70, 0.05, GOLD, Enum.Material.Metal)
	disc(model, "InlayField", O, O.Y + 0.1, 68, 0.05, MARBLE, Enum.Material.Marble)
	disc(model, "InlayRing", O, O.Y + 0.15, 34, 0.05, GOLD, Enum.Material.Metal)
	disc(model, "InlayField", O, O.Y + 0.2, 32, 0.05, MARBLE, Enum.Material.Marble)
	for k = 0, 7 do
		local angle = k * math.pi / 4 + math.pi / 8
		local direction = Vector3.new(math.sin(angle), 0, math.cos(angle))
		beam(model, "InlayRay", O + direction * 17 + Vector3.new(0, 0.12, 0), O + direction * 33.5 + Vector3.new(0, 0.12, 0), 0.5, 0.05, GOLD, Enum.Material.Metal)
	end
	-- The round wall, in 28 straight panels, open towards the hallway. Every
	-- other panel has a marble pilaster with a gold capital and a sconce; the
	-- ones between carry royal blue banners.
	local panels = 28
	-- Panels wholly inside the hallway's width are left out; the ones at its
	-- edges stay, so they meet the hallway's walls with no gap.
	local opening = math.asin(W / R) - math.pi / panels * 0.5
	for k = 0, panels - 1 do
		local angle = k / panels * math.pi * 2
		local wrapped = if angle > math.pi then angle - math.pi * 2 else angle
		if math.abs(wrapped) < opening then continue end
		local direction = Vector3.new(math.sin(angle), 0, math.cos(angle))
		local mid = O + direction * (R + 1) + Vector3.new(0, (RH - 4) / 2, 0)
		local chord = 2 * (R + 2) * math.sin(math.pi / panels) + 1
		piece(model, "Wall", Vector3.new(chord, RH + 4, 2), CFrame.lookAt(mid, Vector3.new(O.X, mid.Y, O.Z)), MARBLE_SHADE, Enum.Material.Marble, true)
		-- On the floor just inside the wall, facing the centre.
		local face = CFrame.lookAt(O + direction * (R - 0.6), O)
		-- A gold frieze round the top of the wall, and a skirting at the floor.
		piece(model, "Frieze", Vector3.new(chord, 1.2, 0.8), face * CFrame.new(0, RH - 4, 0), GOLD, Enum.Material.Metal)
		piece(model, "Skirting", Vector3.new(chord, 1, 0.8), face * CFrame.new(0, 0.5, 0), GOLD, Enum.Material.Metal)
		if k % 2 == 0 then
			local base = face * CFrame.new(0, 0, -0.8)
			piece(model, "PilasterBase", Vector3.new(4, 1.4, 1.6), base * CFrame.new(0, 0.7, 0), MARBLE_DARK, Enum.Material.Marble, true)
			piece(model, "Pilaster", Vector3.new(3, RH - 7, 1.2), base * CFrame.new(0, (RH - 7) / 2 + 1.4, 0), MARBLE, Enum.Material.Marble, true)
			piece(model, "Capital", Vector3.new(4.2, 1.4, 1.8), base * CFrame.new(0, RH - 5, 0), GOLD, Enum.Material.Metal)
			piece(model, "SconceArm", Vector3.new(0.4, 0.4, 1.6), base * CFrame.new(0, 12, -1.2), GOLD, Enum.Material.Metal)
			local flame = piece(model, "Sconce", Vector3.new(0.9, 1.3, 0.9), base * CFrame.new(0, 12.8, -1.9), FLAME, Enum.Material.Neon)
			flame.CastShadow = false
			light(flame, WARM, 18, 0.8)
		else
			local frame = face * CFrame.new(0, 22, -0.6)
			piece(model, "Banner", Vector3.new(5, 14, 0.3), frame, ROYAL, Enum.Material.Fabric)
			piece(model, "BannerRod", Vector3.new(6.2, 0.4, 0.4), frame * CFrame.new(0, 7.2, 0), GOLD, Enum.Material.Metal)
			piece(model, "BannerFringe", Vector3.new(5.2, 0.6, 0.4), frame * CFrame.new(0, -7.1, 0), GOLD, Enum.Material.Metal)
		end
	end
	-- The dome: a marble ceiling with gold rings, the rings stepping down
	-- towards the middle like a coffered dome.
	disc(model, "Ceiling", O, O.Y + RH + 2, (R + 4) * 2, 2, MARBLE, Enum.Material.Marble, true)
	for index, ring in { 70, 52, 34, 16 } do
		local under = O.Y + RH - (index - 1) * 0.6
		disc(model, "DomeRing", O, under, ring + 1.2, 0.6, GOLD, Enum.Material.Metal)
		disc(model, "Dome", O, under, ring, 0.6, if index % 2 == 0 then MARBLE else MARBLE_SHADE, Enum.Material.Marble)
	end
	-- Over the hallway's opening, the wall carries on above the hallway's ceiling.
	block(model, "Wall", Vector3.new(-W - 4, H, Z0), Vector3.new(W + 4, RH + 2, Z0 + 2), MARBLE_SHADE, Enum.Material.Marble, true)
	-- The grand arch into the throne room: gold-clad piers and a lintel.
	for _, side in { -1, 1 } do
		block(model, "ArchPier", Vector3.new(side * (W - 2.4), -0.05, Z0 - 1), Vector3.new(side * W, H, Z0 + 2), GOLD, Enum.Material.Metal, true)
	end
	block(model, "ArchLintel", Vector3.new(-W, H - 2.4, Z0 - 1), Vector3.new(W, H, Z0 + 2), GOLD, Enum.Material.Metal)

	-- The dais: three marble steps with gold edges, a gold pedestal and the diamond.
	local step = 0
	for _, diameter in { 28, 22, 16 } do
		step += 1
		disc(model, "DaisGold", O, O.Y + step - 0.15, diameter + 0.6, 1, GOLD, Enum.Material.Metal, true)
		disc(model, "Dais", O, O.Y + step, diameter, 1, MARBLE, Enum.Material.Marble, true)
	end
	disc(model, "Pedestal", O, O.Y + 6, 4, 3, GOLD, Enum.Material.Metal, true)
	disc(model, "PedestalCap", O, O.Y + 6.5, 5, 0.5, MARBLE, Enum.Material.Marble, true)
	local gem = DiamondShape.build(Lobby.DIAMOND_SIZE, "LobbyDiamond")
	local gemFrame = CFrame.new(O + Vector3.new(0, Lobby.DIAMOND_HEIGHT, 0))
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
	light(core, Color3.fromRGB(170, 230, 255), 26, 1.8)
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 230, 255))
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Transparency = NumberSequence.new(0, 1)
	sparkles.Lifetime = NumberRange.new(0.6, 1.2)
	sparkles.Rate = 14
	sparkles.Speed = NumberRange.new(1, 2.5)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Parent = core

	-- Gold lamp posts around the dais.
	for k = 0, 3 do
		local angle = k * math.pi / 2 + math.pi / 4
		local spot = O + Vector3.new(math.sin(angle) * 19, 0, math.cos(angle) * 19)
		disc(model, "LampBase", spot, O.Y + 0.6, 1.8, 0.6, GOLD, Enum.Material.Metal, true)
		disc(model, "LampPost", spot, O.Y + 7, 0.6, 6.4, GOLD, Enum.Material.Metal, true)
		local lamp = piece(model, "Lamp", Vector3.new(1.3, 1.6, 1.3), CFrame.new(spot + Vector3.new(0, 7.8, 0)), FLAME, Enum.Material.Neon)
		lamp.CastShadow = false
		piece(model, "LampCap", Vector3.new(1.8, 0.4, 1.8), CFrame.new(spot + Vector3.new(0, 8.8, 0)), GOLD, Enum.Material.Metal)
		light(lamp, WARM, 16, 0.9)
	end

	-- A chandelier hanging `drop` studs from the ceiling at `top`: a gold rod,
	-- two gold rings of candles and crystal drops, and a glowing heart.
	local function chandelier(top: Vector3, drop: number, size: number, range: number)
		local hub = top - Vector3.new(0, drop, 0)
		piece(model, "ChandelierRod", Vector3.new(0.4, drop, 0.4), CFrame.new(top - Vector3.new(0, drop / 2, 0)), GOLD, Enum.Material.Metal)
		disc(model, "ChandelierRing", hub, hub.Y, size, 0.5, GOLD, Enum.Material.Metal)
		disc(model, "ChandelierRing", hub, hub.Y + 2.4, size * 0.55, 0.4, GOLD, Enum.Material.Metal)
		local heart = piece(model, "ChandelierHeart", Vector3.new(1.4, 1.4, 1.4), CFrame.new(hub + Vector3.new(0, 1, 0)), FLAME, Enum.Material.Neon)
		heart.Shape = Enum.PartType.Ball
		heart.CastShadow = false
		light(heart, WARM, range, 1.6)
		local candles = math.max(6, math.floor(size * 1.2))
		for k = 0, candles - 1 do
			local angle = k / candles * math.pi * 2
			local spot = hub + Vector3.new(math.sin(angle), 0, math.cos(angle)) * (size / 2 - 0.3)
			local candle = piece(model, "Candle", Vector3.new(0.35, 0.9, 0.35), CFrame.new(spot + Vector3.new(0, 0.7, 0)), FLAME, Enum.Material.Neon)
			candle.CastShadow = false
			local crystal = piece(model, "Crystal", Vector3.new(0.3, 0.9, 0.3), CFrame.new(spot - Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, angle, math.rad(45)), Color3.fromRGB(220, 240, 255), Enum.Material.Glass)
			crystal.Transparency = 0.2
			crystal.CastShadow = false
		end
	end
	chandelier(at(0, RH, 0), 10, 12, 60)

	-- The grand hallway ------------------------------------------------------------
	block(model, "Floor", Vector3.new(-W, -4, Z0 + 4), Vector3.new(W, -0.05, Z1 + 2), MARBLE, Enum.Material.Marble, true)
	-- Darker marble borders along the walls, and gold bands across the floor.
	for _, side in { -1, 1 } do
		block(model, "FloorBorder", Vector3.new(side * (W - 3), -0.1, Z0 + 4), Vector3.new(side * W, 0.02, Z1), MARBLE_DARK, Enum.Material.Marble)
	end
	for z = Z0 + 14, Z1 - 4, 18 do
		block(model, "FloorBand", Vector3.new(-W + 3, -0.1, z - 0.3), Vector3.new(W - 3, 0.03, z + 0.3), GOLD, Enum.Material.Metal)
	end
	block(model, "Ceiling", Vector3.new(-W - 2, H, Z0), Vector3.new(W + 2, H + 2, Z1 + 2), MARBLE, Enum.Material.Marble, true)
	-- Gold beams across the ceiling, between the chandeliers.
	for z = Z0 + 18, Z1 - 4, 36 do
		block(model, "CeilingBeam", Vector3.new(-W, H - 1.6, z - 1), Vector3.new(W, H, z + 1), GOLD, Enum.Material.Metal)
	end
	block(model, "Cornice", Vector3.new(-W, H - 1, Z0 + 2), Vector3.new(-W + 1.2, H, Z1), GOLD, Enum.Material.Metal)
	block(model, "Cornice", Vector3.new(W - 1.2, H - 1, Z0 + 2), Vector3.new(W, H, Z1), GOLD, Enum.Material.Metal)
	-- The entrance end wall, with a tall royal blue hanging and the crest.
	block(model, "Wall", Vector3.new(-W - 2, -4, Z1), Vector3.new(W + 2, H, Z1 + 2), MARBLE_SHADE, Enum.Material.Marble, true)
	local hanging = piece(model, "Banner", Vector3.new(12, 22, 0.3), CFrame.lookAt(at(0, 20, Z1 - 0.4), at(0, 20, 0)), ROYAL, Enum.Material.Fabric)
	draw(hanging, {
		{ x = 0.5, y = 0.32, w = 0.42, h = 0.42, colour = GOLD, gem = true },
		{ x = 0.5, y = 0.32, w = 0.24, h = 0.24, colour = Color3.fromRGB(170, 230, 255), gem = true },
		{ x = 0.5, y = 0.72, w = 0.7, h = 0.03, colour = GOLD },
	}, 20)
	piece(model, "BannerRod", Vector3.new(14, 0.5, 0.5), hanging.CFrame * CFrame.new(0, 11.2, 0), GOLD, Enum.Material.Metal)
	piece(model, "BannerFringe", Vector3.new(12.4, 0.8, 0.5), hanging.CFrame * CFrame.new(0, -11.2, 0), GOLD, Enum.Material.Metal)

	-- The side walls, with a doorway for each room.
	local doors: { [number]: { { number } } } = { [-1] = {}, [1] = {} }
	for _, room in Lobby.ROOMS do
		table.insert(doors[room.side], { room.z - DOOR, room.z + DOOR })
	end
	for _, side in { -1, 1 } do
		table.sort(doors[side], function(a, b) return a[1] < b[1] end)
		local from = Z0
		for _, door in doors[side] do
			block(model, "Wall", Vector3.new(side * W, -4, from), Vector3.new(side * (W + 2), H, door[1]), MARBLE_SHADE, Enum.Material.Marble, true)
			block(model, "Wall", Vector3.new(side * W, Lobby.DOOR_HEIGHT, door[1]), Vector3.new(side * (W + 2), H, door[2]), MARBLE_SHADE, Enum.Material.Marble, true)
			from = door[2]
		end
		block(model, "Wall", Vector3.new(side * W, -4, from), Vector3.new(side * (W + 2), H, Z1 + 2), MARBLE_SHADE, Enum.Material.Marble, true)
		block(model, "Skirting", Vector3.new(side * (W - 0.6), 0, Z0 + 2), Vector3.new(side * W, 1, Z1), GOLD, Enum.Material.Metal)
	end

	-- Columns along both walls, between the doors, each with a gold sconce;
	-- royal blue banners hang between them.
	local columnZ = { 46, 64, 80, 112, 130, 148, 182, 202 }
	for _, side in { -1, 1 } do
		local x = side * (W - 1.8)
		for _, z in columnZ do
			local spot = at(x, 0, z)
			piece(model, "ColumnBase", Vector3.new(3.6, 1.4, 3.6), CFrame.new(spot + Vector3.new(0, 0.7, 0)), MARBLE_DARK, Enum.Material.Marble, true)
			disc(model, "ColumnRing", spot, O.Y + 2, 3.2, 0.6, GOLD, Enum.Material.Metal)
			disc(model, "Column", spot, O.Y + H - 2, 2.6, H - 3.4, MARBLE, Enum.Material.Marble, true)
			disc(model, "ColumnRing", spot, O.Y + H - 2.6, 3.2, 0.6, GOLD, Enum.Material.Metal)
			piece(model, "Capital", Vector3.new(3.8, 1.2, 3.8), CFrame.new(spot + Vector3.new(0, H - 1.6, 0)), GOLD, Enum.Material.Metal)
			local facing = CFrame.lookAt(spot, at(0, 0, z))
			piece(model, "SconceArm", Vector3.new(0.4, 0.4, 1.4), facing * CFrame.new(0, 13, -1.8), GOLD, Enum.Material.Metal)
			local flame = piece(model, "Sconce", Vector3.new(0.8, 1.2, 0.8), facing * CFrame.new(0, 13.8, -2.5), FLAME, Enum.Material.Neon)
			flame.CastShadow = false
			light(flame, WARM, 18, 0.8)
		end
		for _, z in { 55, 121, 139, 192 } do
			local frame = CFrame.lookAt(at(side * (W - 0.4), 21, z), at(0, 21, z))
			local banner = piece(model, "Banner", Vector3.new(5, 13, 0.3), frame, ROYAL, Enum.Material.Fabric)
			piece(model, "BannerRod", Vector3.new(6.2, 0.4, 0.4), frame * CFrame.new(0, 6.7, 0), GOLD, Enum.Material.Metal)
			piece(model, "BannerFringe", Vector3.new(5.2, 0.6, 0.4), frame * CFrame.new(0, -6.6, 0), GOLD, Enum.Material.Metal)
			draw(banner, {
				{ x = 0.5, y = 0.27, w = 0.42, h = 0.42, colour = GOLD, gem = true },
				{ x = 0.5, y = 0.66, w = 0.2, h = 0.2, colour = GOLD, gem = true },
			})
		end
	end

	-- Chandeliers down the middle of the hallway.
	for _, z in { 64, 96, 130, 166, 198 } do
		chandelier(at(0, H, z), 7, 8, 50)
	end

	-- A royal blue carpet with gold edges from the spawn to the dais.
	local carpetFrom, carpetTo = at(0, 0.25, Z1 - 4), at(0, 0.25, 15)
	beam(model, "Carpet", carpetFrom, carpetTo, 9, 0.2, ROYAL, Enum.Material.Fabric)
	for _, x in { -4.7, 4.7 } do
		beam(model, "CarpetEdge", carpetFrom + Vector3.new(x, 0.02, 0), carpetTo + Vector3.new(x, 0.02, 0), 0.5, 0.22, GOLD, Enum.Material.Metal)
	end

	-- The spawn, near the entrance end, facing down the hallway to the dais.
	local spawnAt = at(0, 0.5, Lobby.SPAWN_Z)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.lookAt(spawnAt, Vector3.new(O.X, spawnAt.Y, O.Z))
	spawn.Material = Enum.Material.Marble
	spawn.Color = MARBLE
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = model
	for _, offset in { Vector3.new(5.3, 0, 0), Vector3.new(-5.3, 0, 0), Vector3.new(0, 0, 5.3), Vector3.new(0, 0, -5.3) } do
		local long = if offset.X ~= 0 then Vector3.new(0.6, 1.1, 11.2) else Vector3.new(11.2, 1.1, 0.6)
		piece(model, "SpawnTrim", long, CFrame.new(spawnAt + offset + Vector3.new(0, 0.05, 0)), GOLD, Enum.Material.Metal, true)
	end

	-- The How to Play board beside the carpet, angled to the spawn. Its face is
	-- drawn, not lettered: a gold gem over three list lines. Walking up and
	-- pressing E, or clicking it, opens the guide on screen (see HowToPlay).
	local boardModel = Instance.new("Model")
	boardModel.Name = "HowToPlayBoard"
	boardModel.Parent = model
	local boardAt = at(11, 0, Lobby.SPAWN_Z - 12)
	local boardFrame = CFrame.lookAt(boardAt, Vector3.new(spawnAt.X, boardAt.Y, spawnAt.Z))
	for _, x in { -4.3, 4.3 } do
		piece(boardModel, "BoardPost", Vector3.new(0.7, 9, 0.7), boardFrame * CFrame.new(x, 4.5, 0), GOLD, Enum.Material.Metal, true)
	end
	piece(boardModel, "BoardBase", Vector3.new(10, 0.6, 2), boardFrame * CFrame.new(0, 0.3, 0), MARBLE_SHADE, Enum.Material.Marble, true)
	piece(boardModel, "BoardFrame", Vector3.new(8.6, 6, 0.4), boardFrame * CFrame.new(0, 5.6, 0), GOLD, Enum.Material.Metal, true)
	local face = piece(boardModel, "BoardFace", Vector3.new(8, 5.4, 0.5), boardFrame * CFrame.new(0, 5.6, 0), ROYAL, Enum.Material.SmoothPlastic, true)
	piece(boardModel, "BoardCap", Vector3.new(9.4, 0.5, 0.9), boardFrame * CFrame.new(0, 8.85, 0), GOLD, Enum.Material.Metal)
	local boardMarks: { Mark } = { { x = 0.5, y = 0.22, w = 0.2, h = 0.2, colour = GOLD, gem = true, round = true } }
	for row = 0, 2 do
		local y = 0.5 + row * 0.15
		table.insert(boardMarks, { x = 0.2, y = y, w = 0.08, h = 0.08, colour = GOLD, gem = true, round = true })
		table.insert(boardMarks, { x = 0.55, y = y, w = 0.52 - row * 0.08, h = 0.06, colour = MARBLE, round = true })
	end
	draw(face, boardMarks)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HowToPlay"
	prompt.ActionText = "How to play"
	prompt.ObjectText = "Guide"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = face
	local click = Instance.new("ClickDetector")
	click.Name = "HowToPlayClick"
	click.MaxActivationDistance = 40
	click.Parent = boardModel

	-- The rooms ----------------------------------------------------------------------
	local portals: { Portal } = {}
	local D, L, RHt = Lobby.ROOM_DEPTH, Lobby.ROOM_LENGTH / 2, Lobby.ROOM_HEIGHT
	for _, room in Lobby.ROOMS do
		local s, zc = room.side, room.z
		local folder = Instance.new("Model")
		folder.Name = "Room"
		folder:SetAttribute("Game", room.key)
		folder.Parent = model
		local inner = W + D -- the back wall's inner face
		local mid = W + D / 2
		-- Shell: floor, ceiling, back wall and two side walls.
		block(folder, "Floor", Vector3.new(s * W, -4, zc - L - 2), Vector3.new(s * (inner + 2), 0, zc + L + 2),
			if room.key == "rough" then Color3.fromRGB(120, 118, 116) elseif room.key == "climb" then Color3.fromRGB(46, 40, 86)
				elseif room.key == "chalk" then Color3.fromRGB(150, 104, 62) else MARBLE_SHADE,
			if room.key == "rough" then Enum.Material.Slate elseif room.key == "chalk" then Enum.Material.WoodPlanks else Enum.Material.Marble, true)
		block(folder, "Ceiling", Vector3.new(s * W, RHt, zc - L - 2), Vector3.new(s * (inner + 2), RHt + 2, zc + L + 2), MARBLE, Enum.Material.Marble, true)
		-- Each room's walls suit its game: mine rock, a violet crystal hall, a
		-- cream classroom, or plain marble for the room still to come.
		local wallColour = if room.key == "rough" then Color3.fromRGB(108, 100, 92) elseif room.key == "climb" then Color3.fromRGB(74, 60, 132)
			elseif room.key == "chalk" then Color3.fromRGB(236, 226, 200) else MARBLE_SHADE
		local wallMaterial = if room.key == "rough" then Enum.Material.Slate elseif room.key == "chalk" then Enum.Material.SmoothPlastic else Enum.Material.Marble
		block(folder, "Wall", Vector3.new(s * inner, -4, zc - L - 2), Vector3.new(s * (inner + 2), RHt, zc + L + 2), wallColour, wallMaterial, true)
		for _, end_ in { -1, 1 } do
			block(folder, "Wall", Vector3.new(s * W, -4, zc + end_ * L), Vector3.new(s * (inner + 2), RHt, zc + end_ * (L + 2)), wallColour, wallMaterial, true)
			block(folder, "Skirting", Vector3.new(s * (W + 2), 0, zc + end_ * (L - 0.6)), Vector3.new(s * inner, 1, zc + end_ * L), GOLD, Enum.Material.Metal)
		end
		block(folder, "Skirting", Vector3.new(s * (inner - 0.6), 0, zc - L), Vector3.new(s * inner, 1, zc + L), GOLD, Enum.Material.Metal)
		block(folder, "Cornice", Vector3.new(s * (inner - 1), RHt - 1, zc - L), Vector3.new(s * inner, RHt, zc + L), GOLD, Enum.Material.Metal)
		-- The game's colour runs round the room in a glowing band.
		for _, end_ in { -1, 1 } do
			local band = block(folder, "GlowBand", Vector3.new(s * (W + 2), RHt - 3, zc + end_ * (L - 0.3)), Vector3.new(s * inner, RHt - 2.6, zc + end_ * L), room.colour, Enum.Material.Neon)
			band.CastShadow = false
		end
		-- Two ceiling lamps in the game's colour, and warm light.
		for _, offset in { -12, 12 } do
			local lamp = block(folder, "CeilingLamp", Vector3.new(s * (mid - 4), RHt - 0.4, zc + offset - 4), Vector3.new(s * (mid + 4), RHt, zc + offset + 4), FLAME, Enum.Material.Neon)
			lamp.CastShadow = false
			-- The darker rooms (rock and violet) get brighter lamps.
			light(lamp, WARM, 40, if room.key == "rough" or room.key == "climb" then 1.8 else 1.3)
		end
		-- The doorway: gold jambs and lintel, a threshold, and the emblem above.
		for _, end_ in { -1, 1 } do
			block(model, "DoorJamb", Vector3.new(s * (W - 0.8), -0.05, zc + end_ * DOOR), Vector3.new(s * (W + 2.4), Lobby.DOOR_HEIGHT, zc + end_ * (DOOR + 1.2)), GOLD, Enum.Material.Metal, true)
		end
		block(model, "DoorLintel", Vector3.new(s * (W - 0.8), Lobby.DOOR_HEIGHT, zc - DOOR - 1.2), Vector3.new(s * (W + 2.4), Lobby.DOOR_HEIGHT + 1.4, zc + DOOR + 1.2), GOLD, Enum.Material.Metal)
		block(model, "Threshold", Vector3.new(s * (W - 0.6), -0.1, zc - DOOR), Vector3.new(s * (W + 2.6), 0.04, zc + DOOR), GOLD, Enum.Material.Metal)
		local plaqueFrame = CFrame.lookAt(at(s * (W - 0.4), Lobby.DOOR_HEIGHT + 6, zc), at(0, Lobby.DOOR_HEIGHT + 6, zc))
		piece(model, "EmblemFrame", Vector3.new(12, 8, 0.3), plaqueFrame * CFrame.new(0, 0, 0.1), GOLD, Enum.Material.Metal)
		local plaque = piece(model, "Emblem", Vector3.new(11, 7, 0.3), plaqueFrame * CFrame.new(0, 0, -0.1), Color3.fromRGB(28, 34, 60), Enum.Material.SmoothPlastic)
		plaque:SetAttribute("Game", room.key)
		draw(plaque, EMBLEMS[room.key])

		-- What's in the room.
		local back = s * (inner - 1) -- just in front of the back wall
		local function spot(x: number, y: number, z: number): Vector3
			-- x counts outward from the hallway wall
			return at(s * (W + x), y, zc + z)
		end
		if room.key == "rough" then
			-- A little mountain of stone blocks with snow on top and the
			-- diamond on its peak, and a mine cart full of rock opposite.
			local layers: { { width: number, colour: Color3 } } = {
				{ width = 16, colour = Color3.fromRGB(96, 140, 74) }, { width = 13, colour = Color3.fromRGB(120, 116, 112) },
				{ width = 10, colour = Color3.fromRGB(132, 128, 124) }, { width = 7.5, colour = Color3.fromRGB(146, 142, 138) },
				{ width = 5, colour = Color3.fromRGB(240, 244, 250) }, { width = 2.5, colour = Color3.fromRGB(250, 252, 255) },
			}
			for index, layer in layers do
				local centre = spot(26, (index - 0.5) * 2.4, 15)
				piece(folder, "Rock", Vector3.new(layer.width, 2.4, layer.width), CFrame.new(centre) * CFrame.Angles(0, math.rad(index * 17), 0), layer.colour,
					if index >= 5 then Enum.Material.Snow else Enum.Material.Slate, true)
			end
			local small = DiamondShape.build(1.6, "RoomGem")
			small.model.Parent = folder
			DiamondShape.place(small, CFrame.new(spot(26, 6 * 2.4 + 1.6, 15)))
			for _, facet in small.parts do facet.CanCollide = false; facet.CanQuery = false end
			local gemGlow = piece(folder, "GemGlow", Vector3.new(0.2, 0.2, 0.2), CFrame.new(spot(26, 6 * 2.4 + 1.6, 15)), MARBLE, Enum.Material.SmoothPlastic)
			gemGlow.Transparency = 1
			light(gemGlow, room.colour, 16, 1.2)
			for k, rock in { { 18, -12, 2.2 }, { 22, -16, 1.6 }, { 30, -14, 2.6 }, { 34, -20, 1.4 } } do
				piece(folder, "Rock", Vector3.new(rock[3], rock[3], rock[3]), CFrame.new(spot(rock[1], rock[3] / 2, rock[2])) * CFrame.Angles(0, k, 0.3), Color3.fromRGB(118, 114, 110), Enum.Material.Slate, true)
			end
			-- Timber mine supports along both side walls, glowing crystals in
			-- the rock and two hanging lanterns.
			local TIMBER = Color3.fromRGB(110, 78, 48)
			for _, end_ in { -1, 1 } do
				local wallZ = end_ * (L - 0.7)
				for _, out in { 6, 20, 34, 46 } do
					piece(folder, "MinePost", Vector3.new(1.2, 18, 1.2), CFrame.new(spot(out, 9, wallZ)), TIMBER, Enum.Material.Wood, true)
				end
				piece(folder, "MineBeam", Vector3.new(1.4, 1.4, 42), CFrame.new(spot(26, 18.5, wallZ)) * CFrame.Angles(0, math.pi / 2, 0), TIMBER, Enum.Material.Wood)
				for k, out in { 13, 27, 40 } do
					local cluster = spot(out, 6 + k * 3, end_ * (L - 0.3))
					for shard = 0, 2 do
						local glint = piece(folder, "WallCrystal", Vector3.new(0.7, 2.4 - shard * 0.5, 0.7),
							CFrame.new(cluster) * CFrame.Angles(math.rad(-end_ * (35 + shard * 20)), math.rad(shard * 50), math.rad((shard - 1) * 25)), room.colour, Enum.Material.Neon)
						glint.CastShadow = false
					end
				end
			end
			for _, z in { -8, 8 } do
				piece(folder, "LanternChain", Vector3.new(0.2, 6, 0.2), CFrame.new(spot(14, RHt - 3, z)), Color3.fromRGB(60, 60, 64), Enum.Material.Metal)
				local lantern = piece(folder, "Lantern", Vector3.new(1.2, 1.6, 1.2), CFrame.new(spot(14, RHt - 6.8, z)), Color3.fromRGB(255, 190, 110), Enum.Material.Neon)
				lantern.CastShadow = false
				piece(folder, "LanternCap", Vector3.new(1.6, 0.4, 1.6), CFrame.new(spot(14, RHt - 5.8, z)), Color3.fromRGB(60, 60, 64), Enum.Material.Metal)
				light(lantern, Color3.fromRGB(255, 190, 110), 16, 0.9)
			end
			local cart = CFrame.new(spot(26, 2.4, -14))
			piece(folder, "Cart", Vector3.new(6, 3, 4), cart, Color3.fromRGB(120, 84, 52), Enum.Material.Wood, true)
			piece(folder, "CartLoad", Vector3.new(5.4, 1.2, 3.4), cart * CFrame.new(0, 1.8, 0), Color3.fromRGB(110, 106, 102), Enum.Material.Slate)
			for _, wheel in { { -2, -2.1 }, { 2, -2.1 }, { -2, 2.1 }, { 2, 2.1 } } do
				local w = piece(folder, "CartWheel", Vector3.new(0.5, 1.8, 1.8), cart * CFrame.new(wheel[1], -1.5, wheel[2]) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(70, 70, 76), Enum.Material.Metal)
				w.Shape = Enum.PartType.Cylinder
			end
		elseif room.key == "climb" then
			-- A crystal tower with platforms spiralling round it, and real
			-- steps up the side wall to hop along.
			local towerAt = spot(26, 0, 14)
			disc(folder, "TowerBase", towerAt, O.Y + 1, 8, 1, GOLD, Enum.Material.Metal, true)
			local crystal = disc(folder, "TowerCrystal", towerAt, O.Y + 24, 3.2, 23, Color3.fromRGB(196, 170, 255), Enum.Material.Glass, true)
			crystal.Transparency = 0.15
			for k = 0, 11 do
				local angle = k * 0.75
				local platform = towerAt + Vector3.new(math.sin(angle) * 3.6, 2 + k * 1.8, math.cos(angle) * 3.6)
				piece(folder, "TowerStep", Vector3.new(2.6, 0.5, 2.6), CFrame.new(platform) * CFrame.Angles(0, angle, 0),
					if k % 2 == 0 then GOLD else MARBLE, if k % 2 == 0 then Enum.Material.Metal else Enum.Material.Marble, true)
			end
			local top = DiamondShape.build(1.6, "RoomGem")
			top.model.Parent = folder
			DiamondShape.place(top, CFrame.new(towerAt + Vector3.new(0, 26.5, 0)))
			for _, facet in top.parts do facet.CanCollide = false; facet.CanQuery = false end
			local glowAt = piece(folder, "GemGlow", Vector3.new(0.2, 0.2, 0.2), CFrame.new(towerAt + Vector3.new(0, 20, 0)), MARBLE, Enum.Material.SmoothPlastic)
			glowAt.Transparency = 1
			light(glowAt, room.colour, 22, 1.2)
			-- Violet crystal shards grow out of the walls.
			for _, end_ in { -1, 1 } do
				for k, out in { 8, 20, 32, 44 } do
					local cluster = spot(out, 4 + (k % 2) * 10, end_ * (L - 0.3))
					for shard = 0, 2 do
						local glint = piece(folder, "WallCrystal", Vector3.new(0.9, 3.2 - shard * 0.7, 0.9),
							CFrame.new(cluster) * CFrame.Angles(math.rad(-end_ * (30 + shard * 22)), math.rad(shard * 60), math.rad((shard - 1) * 30)), room.colour, Enum.Material.Neon)
						glint.CastShadow = false
					end
				end
			end
			for k = 0, 5 do
				local padAt = spot(10 + k * 5, 2 + k * 2.2, -20)
				local pad = piece(folder, "ClimbPad", Vector3.new(4, 0.6, 4), CFrame.new(padAt), if k % 2 == 0 then MARBLE else GOLD,
					if k % 2 == 0 then Enum.Material.Marble else Enum.Material.Metal, true)
				pad.CanQuery = true
			end
		elseif room.key == "chalk" then
			-- A chalkboard covering the side wall, chalk tallies on it, and a
			-- teacher's desk with books and an apple.
			local boardZ = zc + L - 0.4
			local boardFace = piece(folder, "Chalkboard", Vector3.new(28, 12, 0.4), CFrame.lookAt(at(s * (W + 25), 12, boardZ), at(s * (W + 25), 12, zc)), Color3.fromRGB(44, 86, 62), Enum.Material.Slate)
			piece(folder, "ChalkboardFrame", Vector3.new(29.4, 13.4, 0.3), boardFace.CFrame * CFrame.new(0, 0, 0.2), Color3.fromRGB(150, 104, 62), Enum.Material.Wood)
			piece(folder, "ChalkTray", Vector3.new(28, 0.4, 1), boardFace.CFrame * CFrame.new(0, -6.2, -0.5), Color3.fromRGB(150, 104, 62), Enum.Material.Wood)
			local tallies: { Mark } = {}
			for group = 0, 3 do
				local x0 = 0.12 + group * 0.2
				for line = 0, 3 do
					table.insert(tallies, { x = x0 + line * 0.025, y = 0.45, w = 0.008, h = 0.26, colour = Color3.fromRGB(240, 240, 232) })
				end
				table.insert(tallies, { x = x0 + 0.037, y = 0.45, w = 0.11, h = 0.012, colour = Color3.fromRGB(240, 240, 232), rotation = -35 })
			end
			table.insert(tallies, { x = 0.5, y = 0.8, w = 0.6, h = 0.012, colour = Color3.fromRGB(240, 240, 232) })
			draw(boardFace, tallies, 20)
			local desk = CFrame.new(spot(30, 1.6, -10))
			piece(folder, "Desk", Vector3.new(10, 0.6, 5), desk * CFrame.new(0, 1.6, 0), Color3.fromRGB(120, 82, 50), Enum.Material.Wood, true)
			for _, leg in { { -4.5, -2 }, { 4.5, -2 }, { -4.5, 2 }, { 4.5, 2 } } do
				piece(folder, "DeskLeg", Vector3.new(0.6, 3.2, 0.6), desk * CFrame.new(leg[1], 0, leg[2]), Color3.fromRGB(96, 66, 42), Enum.Material.Wood, true)
			end
			for k, colour in { Color3.fromRGB(170, 52, 52), Color3.fromRGB(52, 90, 170), Color3.fromRGB(60, 130, 70) } do
				piece(folder, "Book", Vector3.new(2.4, 0.5, 1.8), desk * CFrame.new(-3, 2.15 + (k - 1) * 0.5, 0) * CFrame.Angles(0, k * 0.2, 0), colour, Enum.Material.SmoothPlastic)
			end
			local apple = piece(folder, "Apple", Vector3.new(0.9, 0.9, 0.9), desk * CFrame.new(2.5, 2.35, 0), Color3.fromRGB(200, 30, 40), Enum.Material.SmoothPlastic)
			apple.Shape = Enum.PartType.Ball
			-- Green wood panelling round the lower walls.
			local PANEL = Color3.fromRGB(78, 120, 92)
			for _, end_ in { -1, 1 } do
				block(folder, "Wainscot", Vector3.new(s * (W + 2), 0, zc + end_ * (L - 0.5)), Vector3.new(s * inner, 6, zc + end_ * L), PANEL, Enum.Material.Wood)
			end
			block(folder, "Wainscot", Vector3.new(s * (inner - 0.5), 0, zc - L), Vector3.new(s * inner, 6, zc - 8), PANEL, Enum.Material.Wood)
			block(folder, "Wainscot", Vector3.new(s * (inner - 0.5), 0, zc + 8), Vector3.new(s * inner, 6, zc + L), PANEL, Enum.Material.Wood)
			-- A wall clock opposite the board (drawn: a face and two hands).
			local clockFrame = CFrame.lookAt(at(s * (W + 25), 18, zc - L + 0.5), at(s * (W + 25), 18, zc))
			local rim = piece(folder, "ClockRim", Vector3.new(0.5, 5.4, 5.4), clockFrame * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(96, 66, 42), Enum.Material.Wood)
			rim.Shape = Enum.PartType.Cylinder
			local dial = piece(folder, "Clock", Vector3.new(4.6, 4.6, 0.2), clockFrame * CFrame.new(0, 0, -0.3), Color3.fromRGB(250, 248, 240), Enum.Material.SmoothPlastic)
			draw(dial, {
				{ x = 0.5, y = 0.32, w = 0.05, h = 0.36, colour = Color3.fromRGB(30, 30, 34) },
				{ x = 0.64, y = 0.5, w = 0.28, h = 0.05, colour = Color3.fromRGB(30, 30, 34) },
				{ x = 0.5, y = 0.5, w = 0.1, h = 0.1, colour = Color3.fromRGB(176, 40, 40), square = true, round = true },
			}, 20)
			-- A bookshelf by the door.
			local shelf = CFrame.lookAt(at(s * (W + 8), 0, zc - L + 1.2), at(s * (W + 8), 0, zc))
			piece(folder, "Bookshelf", Vector3.new(8, 10, 2), shelf * CFrame.new(0, 5, 0), Color3.fromRGB(110, 76, 46), Enum.Material.Wood, true)
			local spines = { Color3.fromRGB(170, 52, 52), Color3.fromRGB(52, 90, 170), Color3.fromRGB(60, 130, 70), Color3.fromRGB(210, 170, 60), Color3.fromRGB(120, 60, 140) }
			for row = 0, 2 do
				for k = 0, 8 do
					local tall = 1.8 + ((k * 7 + row * 3) % 4) * 0.2
					piece(folder, "Book", Vector3.new(0.6, tall, 1.4), shelf * CFrame.new(-3.4 + k * 0.82, 1.2 + row * 3 + tall / 2, -0.4), spines[(k + row) % #spines + 1], Enum.Material.SmoothPlastic)
				end
			end
		else
			-- Coming soon: a covered shape on a gold pedestal under a
			-- spotlight, seen through the gate.
			local pedestal = spot(26, 0, 0)
			disc(folder, "Pedestal", pedestal, O.Y + 3, 8, 3, GOLD, Enum.Material.Metal, true)
			piece(folder, "Covered", Vector3.new(6, 7, 6), CFrame.new(pedestal + Vector3.new(0, 6.5, 0)) * CFrame.Angles(0, math.rad(20), 0), Color3.fromRGB(120, 24, 40), Enum.Material.Fabric, true)
			-- Gold posts and red velvet ropes keep everyone back.
			local posts = {}
			for k = 0, 5 do
				local angle = k / 6 * math.pi * 2
				local post = pedestal + Vector3.new(math.sin(angle) * 8, 0, math.cos(angle) * 8)
				disc(folder, "RopePost", post, O.Y + 3.4, 0.5, 3.4, GOLD, Enum.Material.Metal, true)
				local knob = piece(folder, "RopeKnob", Vector3.new(0.8, 0.8, 0.8), CFrame.new(post + Vector3.new(0, 3.6, 0)), GOLD, Enum.Material.Metal)
				knob.Shape = Enum.PartType.Ball
				table.insert(posts, post)
			end
			for k, post in posts do
				local nextPost = posts[k % #posts + 1]
				beam(folder, "Rope", post + Vector3.new(0, 3, 0), nextPost + Vector3.new(0, 3, 0), 0.35, 0.35, Color3.fromRGB(150, 20, 36), Enum.Material.Fabric)
			end
			local spotlight = piece(folder, "Spotlight", Vector3.new(1.4, 0.6, 1.4), CFrame.new(pedestal + Vector3.new(0, RHt - 0.4, 0)), FLAME, Enum.Material.Neon)
			spotlight.CastShadow = false
			local beamLight = Instance.new("SpotLight")
			beamLight.Face = Enum.NormalId.Bottom
			beamLight.Angle = 50
			beamLight.Range = 32
			beamLight.Brightness = 3
			beamLight.Color = WARM
			beamLight.Shadows = false
			beamLight.Parent = spotlight
		end

		if room.place then
			-- The portal at the back: a gold arch round a glowing veil. Walking
			-- into it, or pressing E at it, joins the game (see the server).
			local portalFace = CFrame.lookAt(at(back, 0, zc), at(0, 0, zc))
			for _, end_ in { -1, 1 } do
				piece(folder, "PortalPillar", Vector3.new(1.6, 20, 1.6), portalFace * CFrame.new(end_ * 7.4, 10, 0), GOLD, Enum.Material.Metal, true)
			end
			piece(folder, "PortalArch", Vector3.new(16.4, 1.8, 1.8), portalFace * CFrame.new(0, 20.6, 0), GOLD, Enum.Material.Metal, true)
			local keystone = piece(folder, "PortalKeystone", Vector3.new(2.2, 2.2, 0.6), portalFace * CFrame.new(0, 20.6, -1) * CFrame.Angles(0, 0, math.rad(45)), room.colour, Enum.Material.Neon)
			keystone.CastShadow = false
			local veil = piece(folder, "Portal", Vector3.new(13.2, 19, 2), portalFace * CFrame.new(0, 10, -0.6), room.colour, Enum.Material.Neon)
			veil.Transparency = 0.35
			veil.CastShadow = false
			veil.CanCollide = false
			veil.CanQuery = true
			veil.CanTouch = true
			veil:SetAttribute("Game", room.place)
			light(veil, room.colour, 24, 1.4)
			local swirl = Instance.new("ParticleEmitter")
			swirl.Color = ColorSequence.new(Color3.new(1, 1, 1), room.colour)
			swirl.LightEmission = 1
			swirl.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
			swirl.Transparency = NumberSequence.new(0.2, 1)
			swirl.Lifetime = NumberRange.new(0.8, 1.6)
			swirl.Rate = 20
			swirl.Speed = NumberRange.new(1, 3)
			swirl.SpreadAngle = Vector2.new(60, 60)
			swirl.Parent = veil
			local glow = piece(folder, "PortalFloor", Vector3.new(0.2, 14, 14), CFrame.new(at(back - s * 6, 0.06, zc)) * CFrame.Angles(0, 0, math.pi / 2), room.colour, Enum.Material.Neon)
			glow.Shape = Enum.PartType.Cylinder
			glow.Transparency = 0.5
			glow.CastShadow = false
			local join = Instance.new("ProximityPrompt")
			join.Name = "JoinGame"
			join.ActionText = "Join"
			join.ObjectText = room.name
			join.KeyboardKeyCode = Enum.KeyCode.E
			join.HoldDuration = 0
			join.MaxActivationDistance = 16
			join.RequiresLineOfSight = false
			join.Parent = veil
			table.insert(portals, { part = veil :: BasePart, prompt = join, place = room.place :: string })
		else
			-- A closed gold gate fills the doorway: the room can be seen, not entered.
			for k = 0, 12 do
				local z = zc - DOOR + 0.7 + k * (Lobby.DOOR_WIDTH - 1.4) / 12
				block(model, "GateBar", Vector3.new(s * (W + 0.6), 0, z - 0.25), Vector3.new(s * (W + 1.1), Lobby.DOOR_HEIGHT, z + 0.25), GOLD, Enum.Material.Metal)
			end
			for _, y in { 2, 11, 20 } do
				block(model, "GateRail", Vector3.new(s * (W + 0.5), y - 0.3, zc - DOOR), Vector3.new(s * (W + 1.2), y + 0.3, zc + DOOR), GOLD, Enum.Material.Metal)
			end
			local stop = block(model, "GateBlocker", Vector3.new(s * W, 0, zc - DOOR), Vector3.new(s * (W + 2), Lobby.DOOR_HEIGHT, zc + DOOR), GOLD, Enum.Material.SmoothPlastic, true)
			stop.Transparency = 1
			stop.CanQuery = false
			stop.CastShadow = false
		end
	end

	return { model = model, spawn = spawn, diamond = gem.model, board = boardModel, portals = portals }
end

return Lobby
