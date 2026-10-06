--!strict
-- The royal spawn area: a white marble court floating in the sky, far from the
-- mountain valley, where every player arrives. A ring of marble columns with
-- gold capitals carries royal blue banners; a royal blue carpet leads from the
-- spawn to a stepped dais where a giant diamond turns slowly (each client
-- spins it, see GamesMenu). Games are joined from the games menu on the side of the screen.
-- A How to Play board beside the carpet opens the on-screen guide.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("DiamondRush")
local DiamondShape = require(Shared:WaitForChild("DiamondShape"))

local Lobby = {}

-- High above, and far enough from the valley that its shadow never reaches it.
Lobby.ORIGIN = Vector3.new(0, 300, 2600)
Lobby.DIAMOND_SIZE = 6
Lobby.DIAMOND_HEIGHT = 10 -- above the floor

local MARBLE = Color3.fromRGB(242, 240, 235)
local MARBLE_SHADE = Color3.fromRGB(222, 218, 210)
local GOLD = Color3.fromRGB(224, 178, 72)
local ROYAL = Color3.fromRGB(34, 52, 140)

export type Built = { model: Model, spawn: SpawnLocation, diamond: Model, board: Model }

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

function Lobby.build(parent: Instance): Built
	local O = Lobby.ORIGIN
	local model = Instance.new("Model")
	model.Name = "Lobby"
	model.Parent = parent

	-- The court: a marble disc with a gold rim, floating on stepped marble tiers.
	disc(model, "Floor", O, O.Y, 124, 4, MARBLE, Enum.Material.Marble, true)
	disc(model, "FloorRim", O, O.Y - 0.3, 126, 3.6, GOLD, Enum.Material.Metal)
	local tiers = { { 112, 3 }, { 92, 4 }, { 66, 4 }, { 40, 4 }, { 16, 4 } }
	local top = O.Y - 4
	for index, tier in tiers do
		disc(model, "Tier", O, top, tier[1], tier[2], if index % 2 == 0 then MARBLE else MARBLE_SHADE, Enum.Material.Marble)
		disc(model, "TierBand", O, top - tier[2] + 0.5, tier[1] + 1, 0.6, GOLD, Enum.Material.Metal)
		top -= tier[2]
	end
	disc(model, "Finial", O, top, 3, 7, GOLD, Enum.Material.Metal)

	-- Gold inlay: an outer ring, an inner ring and eight rays between them.
	disc(model, "InlayRing", O, O.Y + 0.05, 98, 0.05, GOLD, Enum.Material.Metal)
	disc(model, "InlayField", O, O.Y + 0.1, 96, 0.05, MARBLE, Enum.Material.Marble)
	disc(model, "InlayRing", O, O.Y + 0.15, 34, 0.05, GOLD, Enum.Material.Metal)
	disc(model, "InlayField", O, O.Y + 0.2, 32, 0.05, MARBLE, Enum.Material.Marble)
	for k = 0, 7 do
		local angle = k * math.pi / 4 + math.pi / 8
		local direction = Vector3.new(math.sin(angle), 0, math.cos(angle))
		beam(model, "InlayRay", O + direction * 17 + Vector3.new(0, 0.12, 0), O + direction * 47.5 + Vector3.new(0, 0.12, 0), 0.5, 0.05, GOLD, Enum.Material.Metal)
	end

	-- The spawn, on the near side of the court, facing the dais.
	local spawnAt = O + Vector3.new(0, 0.5, 40)
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
	for _, side in { Vector3.new(5.3, 0, 0), Vector3.new(-5.3, 0, 0), Vector3.new(0, 0, 5.3), Vector3.new(0, 0, -5.3) } do
		local long = if side.X ~= 0 then Vector3.new(0.6, 1.1, 11.2) else Vector3.new(11.2, 1.1, 0.6)
		piece(model, "SpawnTrim", long, CFrame.new(spawnAt + side + Vector3.new(0, 0.05, 0)), GOLD, Enum.Material.Metal, true)
	end

	-- A royal blue carpet with gold edges from the spawn to the dais.
	local carpetFrom, carpetTo = O + Vector3.new(0, 0.3, 34.5), O + Vector3.new(0, 0.3, 13.5)
	beam(model, "Carpet", carpetFrom, carpetTo, 7, 0.2, ROYAL, Enum.Material.Fabric)
	for _, x in { -3.7, 3.7 } do
		beam(model, "CarpetEdge", carpetFrom + Vector3.new(x, 0.02, 0), carpetTo + Vector3.new(x, 0.02, 0), 0.5, 0.22, GOLD, Enum.Material.Metal)
	end

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
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(170, 230, 255)
	glow.Range = 22
	glow.Brightness = 1.6
	glow.Shadows = false
	glow.Parent = core
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
		local at = O + Vector3.new(math.sin(angle) * 17, 0, math.cos(angle) * 17)
		disc(model, "LampBase", at, O.Y + 0.6, 1.8, 0.6, GOLD, Enum.Material.Metal, true)
		disc(model, "LampPost", at, O.Y + 7, 0.6, 6.4, GOLD, Enum.Material.Metal, true)
		local lamp = piece(model, "Lamp", Vector3.new(1.3, 1.6, 1.3), CFrame.new(at + Vector3.new(0, 7.8, 0)), Color3.fromRGB(255, 224, 160), Enum.Material.Neon)
		lamp.CastShadow = false
		piece(model, "LampCap", Vector3.new(1.8, 0.4, 1.8), CFrame.new(at + Vector3.new(0, 8.8, 0)), GOLD, Enum.Material.Metal)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 214, 150)
		light.Range = 14
		light.Brightness = 0.9
		light.Shadows = false
		light.Parent = lamp
	end

	-- The colonnade: sixteen marble columns with gold rings, joined by a marble
	-- entablature with a gold frieze.
	local count, radius = 16, 54
	local shaftTop = O.Y + 1.4 + 18
	for k = 0, count - 1 do
		local angle = k / count * math.pi * 2
		local at = O + Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
		piece(model, "ColumnBase", Vector3.new(4.2, 1.4, 4.2), CFrame.new(at + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, angle, 0), MARBLE_SHADE, Enum.Material.Marble, true)
		disc(model, "ColumnRing", at, O.Y + 2, 3.7, 0.6, GOLD, Enum.Material.Metal)
		disc(model, "Column", at, shaftTop, 3, 18, MARBLE, Enum.Material.Marble, true)
		disc(model, "ColumnRing", at, shaftTop - 0.6, 3.7, 0.6, GOLD, Enum.Material.Metal)
		piece(model, "Capital", Vector3.new(4.4, 1.2, 4.4), CFrame.new(at.X, shaftTop + 0.6, at.Z) * CFrame.Angles(0, angle, 0), GOLD, Enum.Material.Metal)
	end
	local entablature = shaftTop + 1.2
	for k = 0, count - 1 do
		local a1, a2 = k / count * math.pi * 2, (k + 1) / count * math.pi * 2
		local p1 = O + Vector3.new(math.sin(a1) * radius, 0, math.cos(a1) * radius)
		local p2 = O + Vector3.new(math.sin(a2) * radius, 0, math.cos(a2) * radius)
		local reach = (p2 - p1).Unit * 1.6
		local y1 = Vector3.new(0, entablature + 1.2 - O.Y, 0)
		beam(model, "Entablature", p1 - reach + y1, p2 + reach + y1, 3.6, 2.4, MARBLE, Enum.Material.Marble)
		beam(model, "Frieze", p1 - reach + y1 + Vector3.new(0, -1.3, 0), p2 + reach + y1 + Vector3.new(0, -1.3, 0), 3.8, 0.4, GOLD, Enum.Material.Metal)
		beam(model, "Cornice", p1 - reach + y1 + Vector3.new(0, 1.4, 0), p2 + reach + y1 + Vector3.new(0, 1.4, 0), 4.2, 0.4, GOLD, Enum.Material.Metal)
		-- Royal blue banners hang between every other pair of columns.
		if k % 2 == 1 then
			local middle = (p1 + p2) / 2 * Vector3.new(1, 0, 1) + Vector3.new(0, entablature - 7, 0)
			local inward = Vector3.new(O.X, middle.Y, O.Z)
			local frame = CFrame.lookAt(middle, inward) * CFrame.new(0, 0, -1)
			local banner = piece(model, "Banner", Vector3.new(5, 12, 0.3), frame, ROYAL, Enum.Material.Fabric)
			piece(model, "BannerRod", Vector3.new(6.2, 0.4, 0.4), frame * CFrame.new(0, 6.2, 0), GOLD, Enum.Material.Metal)
			piece(model, "BannerFringe", Vector3.new(5.2, 0.6, 0.4), frame * CFrame.new(0, -6.1, 0), GOLD, Enum.Material.Metal)
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Front
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 30
			gui.LightInfluence = 0.8
			gui.Parent = banner
			-- Two gold diamonds (squares turned on their corners), large over small.
			for _, mark in { { 0.27, 0.42 }, { 0.66, 0.2 } } do
				local gem = Instance.new("Frame")
				gem.AnchorPoint = Vector2.new(0.5, 0.5)
				gem.Position = UDim2.fromScale(0.5, mark[1])
				gem.Size = UDim2.fromScale(mark[2], mark[2])
				gem.SizeConstraint = Enum.SizeConstraint.RelativeXX
				gem.Rotation = 45
				gem.BackgroundColor3 = GOLD
				gem.BorderSizePixel = 0
				gem.Parent = gui
			end
		end
	end

	-- The How to Play board beside the carpet, angled to the spawn. Its face is
	-- drawn, not lettered (lettered signs render badly): a gold gem over three
	-- list lines. Walking up and pressing E, or clicking it, opens the guide on
	-- screen (see the client's HowToPlay).
	local boardModel = Instance.new("Model")
	boardModel.Name = "HowToPlayBoard"
	boardModel.Parent = model
	local boardAt = O + Vector3.new(9, 0, 30)
	local boardFrame = CFrame.lookAt(boardAt, Vector3.new(spawnAt.X, boardAt.Y, spawnAt.Z))
	for _, x in { -4.3, 4.3 } do
		piece(boardModel, "BoardPost", Vector3.new(0.7, 9, 0.7), boardFrame * CFrame.new(x, 4.5, 0), GOLD, Enum.Material.Metal, true)
	end
	piece(boardModel, "BoardBase", Vector3.new(10, 0.6, 2), boardFrame * CFrame.new(0, 0.3, 0), MARBLE_SHADE, Enum.Material.Marble, true)
	piece(boardModel, "BoardFrame", Vector3.new(8.6, 6, 0.4), boardFrame * CFrame.new(0, 5.6, 0), GOLD, Enum.Material.Metal, true)
	local face = piece(boardModel, "BoardFace", Vector3.new(8, 5.4, 0.5), boardFrame * CFrame.new(0, 5.6, 0), ROYAL, Enum.Material.SmoothPlastic, true)
	piece(boardModel, "BoardCap", Vector3.new(9.4, 0.5, 0.9), boardFrame * CFrame.new(0, 8.85, 0), GOLD, Enum.Material.Metal)
	local drawing = Instance.new("SurfaceGui")
	drawing.Face = Enum.NormalId.Front
	drawing.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	drawing.PixelsPerStud = 30
	drawing.LightInfluence = 0.6
	drawing.Parent = face
	-- Squares (gems, turned on a corner) are sized by the face's height.
	local function mark(x: number, y: number, w: number, h: number, colour: Color3, gem: boolean)
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(x, y)
		frame.Size = UDim2.fromScale(w, h)
		if gem then
			frame.SizeConstraint = Enum.SizeConstraint.RelativeYY
			frame.Rotation = 45
		end
		frame.BackgroundColor3 = colour
		frame.BorderSizePixel = 0
		frame.Parent = drawing
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.2, 0)
		corner.Parent = frame
	end
	mark(0.5, 0.22, 0.2, 0.2, GOLD, true)
	for row = 0, 2 do
		local y = 0.5 + row * 0.15
		mark(0.2, y, 0.08, 0.08, GOLD, true)
		mark(0.55, y, 0.52 - row * 0.08, 0.06, MARBLE, false)
	end
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

	-- A marble balustrade with a gold rail rings the edge; an invisible wall
	-- behind it stops anyone jumping off.
	local edge = 60
	for k = 0, 63 do
		local angle = k / 64 * math.pi * 2
		local at = O + Vector3.new(math.sin(angle) * edge, 0, math.cos(angle) * edge)
		disc(model, "Baluster", at, O.Y + 3, 0.9, 3, MARBLE, Enum.Material.Marble, true)
	end
	for k = 0, 31 do
		local a1, a2 = k / 32 * math.pi * 2, (k + 1) / 32 * math.pi * 2
		local p1 = O + Vector3.new(math.sin(a1) * edge, 3.25, math.cos(a1) * edge)
		local p2 = O + Vector3.new(math.sin(a2) * edge, 3.25, math.cos(a2) * edge)
		local reach = (p2 - p1).Unit * 0.3
		beam(model, "Rail", p1 - reach, p2 + reach, 1.2, 0.5, GOLD, Enum.Material.Metal, true)
		-- 16 studs tall from the floor, just outside the rail.
		local middle = O + ((p1 + p2) / 2 - O) * Vector3.new(1.01, 1, 1.01) + Vector3.new(0, 4.75, 0)
		local wall = piece(model, "EdgeWall", Vector3.new(0.5, 16, (p2 - p1).Magnitude + 0.6), CFrame.lookAt(middle, middle + (p2 - p1)), MARBLE, Enum.Material.SmoothPlastic, true)
		wall.Transparency = 1
		wall.CanQuery = false
		wall.CastShadow = false
	end

	return { model = model, spawn = spawn, diamond = gem.model, board = boardModel }
end

return Lobby
