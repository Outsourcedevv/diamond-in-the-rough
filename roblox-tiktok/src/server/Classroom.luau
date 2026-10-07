--!strict
-- Chalkboard Count's classroom, built once on startup far off in the sky:
-- a wooden floor, three walls with windows and a clock, the big chalkboard
-- with its frame and chalk tray, a teacher's desk, rows of school desks,
-- a bookshelf, a plant and ceiling lamps. Everything a theme recolours is
-- tagged with a "Role" attribute, and each theme's extra decorations (gold
-- trim and a diamond, blossom branches, neon strips) are kept in ServerStorage
-- until that theme is chosen. No lettering anywhere: the chalk is drawn by
-- each player's game (see ChalkView).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("DiamondRush")
local ChalkBoard = require(Shared:WaitForChild("ChalkBoard"))
local DiamondShape = require(Shared:WaitForChild("DiamondShape"))

local Classroom = {}

local WOOD = Color3.fromRGB(150, 104, 62)
local DARK_WOOD = Color3.fromRGB(96, 66, 42)
local METAL = Color3.fromRGB(120, 124, 132)
local WHITE = Color3.fromRGB(246, 246, 240)
local GOLD = Color3.fromRGB(224, 178, 72)
local PINK = Color3.fromRGB(255, 176, 204)
Classroom.WIDTH, Classroom.DEPTH, Classroom.WALL_HEIGHT = 64, 56, 22

export type Built = {
	model: Model,
	spawn: SpawnLocation,
	decor: { [string]: Folder },
	store: Instance,
	theme: string,
}

local function piece(parent: Instance, name: string, size: Vector3, frame: CFrame, colour: Color3, material: Enum.Material, solid: boolean?, role: string?): Part
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
	if role then p:SetAttribute("Role", role) end
	p.Parent = parent
	return p
end

-- A box from its bottom middle, in classroom coordinates (from the floor's middle).
local function box(parent: Instance, name: string, size: Vector3, at: Vector3, colour: Color3, material: Enum.Material, solid: boolean?, role: string?): Part
	local O = ChalkBoard.ORIGIN
	return piece(parent, name, size, CFrame.new(O + at + Vector3.new(0, size.Y / 2, 0)), colour, material, solid, role)
end

local function lamp(parent: Instance, at: Vector3)
	local O = ChalkBoard.ORIGIN
	piece(parent, "LampCord", Vector3.new(0.15, 4, 0.15), CFrame.new(O + at + Vector3.new(0, 2.6, 0)), METAL, Enum.Material.Metal)
	local shade = piece(parent, "LampShade", Vector3.new(1.4, 3.2, 3.2), CFrame.new(O + at) * CFrame.Angles(0, 0, math.pi / 2), METAL, Enum.Material.Metal)
	shade.Shape = Enum.PartType.Cylinder
	local bulb = piece(parent, "LampBulb", Vector3.new(1.4, 1.4, 1.4), CFrame.new(O + at - Vector3.new(0, 0.8, 0)), Color3.fromRGB(255, 244, 222), Enum.Material.Neon, nil, "Bulb")
	bulb.Shape = Enum.PartType.Ball
	local glow = Instance.new("PointLight")
	glow.Name = "LampLight"
	glow.Range = 34
	glow.Brightness = 1.3
	glow.Shadows = false
	glow.Color = Color3.fromRGB(255, 244, 222)
	glow.Parent = bulb
end

-- A school desk and chair, seen from behind by the camera.
local function desk(parent: Instance, at: Vector3)
	box(parent, "DeskTop", Vector3.new(4, 0.3, 2.6), at + Vector3.new(0, 2.5, 0), WOOD, Enum.Material.Wood, true)
	for _, x in { -1.8, 1.8 } do
		for _, z in { -1.1, 1.1 } do
			box(parent, "DeskLeg", Vector3.new(0.2, 2.5, 0.2), at + Vector3.new(x, 0, z), METAL, Enum.Material.Metal)
		end
	end
	box(parent, "ChairSeat", Vector3.new(2.4, 0.25, 2.2), at + Vector3.new(0, 1.6, 2.6), DARK_WOOD, Enum.Material.Wood)
	box(parent, "ChairBack", Vector3.new(2.4, 2, 0.25), at + Vector3.new(0, 1.85, 3.6), DARK_WOOD, Enum.Material.Wood)
	for _, x in { -1, 1 } do
		box(parent, "ChairLeg", Vector3.new(0.18, 1.6, 0.18), at + Vector3.new(x, 0, 2.6), METAL, Enum.Material.Metal)
	end
end

function Classroom.build(parent: Instance, store: Instance, theme: string?): Built
	local O = ChalkBoard.ORIGIN
	local model = Instance.new("Model")
	model.Name = "Classroom"
	model.Parent = parent
	local W, D, H = Classroom.WIDTH, Classroom.DEPTH, Classroom.WALL_HEIGHT
	local boardZ = ChalkBoard.BOARD_Z

	-- Floor and walls (the side behind the camera stays open).
	box(model, "Floor", Vector3.new(W, 1, D), Vector3.new(0, -1, 0), WOOD, Enum.Material.WoodPlanks, true, "Floor")
	box(model, "BackWall", Vector3.new(W, H, 1), Vector3.new(0, 0, boardZ - 1.5), WHITE, Enum.Material.SmoothPlastic, true, "Wall")
	for _, side in { -1, 1 } do
		local x = side * (W / 2 - 0.5)
		-- Each side wall in pieces round two windows.
		box(model, "SideWall", Vector3.new(1, 5, D), Vector3.new(x, 0, 0), WHITE, Enum.Material.SmoothPlastic, true, "Wall")
		box(model, "SideWall", Vector3.new(1, H - 15, D), Vector3.new(x, 15, 0), WHITE, Enum.Material.SmoothPlastic, true, "Wall")
		-- Between and beside the windows (at z -15..-7 and -1..7).
		for _, span in { { -D / 2, -15 }, { -7, -1 }, { 7, D / 2 } } do
			box(model, "SideWall", Vector3.new(1, 10, span[2] - span[1]), Vector3.new(x, 5, (span[1] + span[2]) / 2), WHITE, Enum.Material.SmoothPlastic, true, "Wall")
		end
		for _, z in { -11, 3 } do
			local pane = box(model, "Window", Vector3.new(0.3, 10, 8), Vector3.new(x, 5, z), Color3.fromRGB(190, 220, 240), Enum.Material.Glass, true)
			pane.Transparency = 0.55
			box(model, "WindowBar", Vector3.new(0.5, 0.3, 8), Vector3.new(x, 9.85, z), WOOD, Enum.Material.Wood, nil, "Trim")
			box(model, "WindowBar", Vector3.new(0.5, 10, 0.3), Vector3.new(x, 5, z), WOOD, Enum.Material.Wood, nil, "Trim")
		end
		-- A skirting board along the bottom.
		box(model, "Skirting", Vector3.new(1.2, 1, D), Vector3.new(x - side * 0.1, 0, 0), WOOD, Enum.Material.Wood, nil, "Trim")
	end
	box(model, "Skirting", Vector3.new(W, 1, 1.2), Vector3.new(0, 0, boardZ - 1.1), WOOD, Enum.Material.Wood, nil, "Trim")

	-- The chalkboard, its frame and the chalk tray.
	local bw, bh, bt = ChalkBoard.BOARD_WIDTH, ChalkBoard.BOARD_HEIGHT, ChalkBoard.BOARD_THICKNESS
	local bottom = ChalkBoard.BOARD_BOTTOM
	box(model, "Board", Vector3.new(bw, bh, bt), Vector3.new(0, bottom, boardZ), ChalkBoard.THEMES.classic.board, Enum.Material.Slate, true, "Board")
	local frame = 0.9
	box(model, "BoardFrame", Vector3.new(bw + frame * 2, frame, bt + 0.4), Vector3.new(0, bottom + bh, boardZ), WOOD, Enum.Material.Wood, true, "Frame")
	box(model, "BoardFrame", Vector3.new(bw + frame * 2, frame, bt + 0.4), Vector3.new(0, bottom - frame, boardZ), WOOD, Enum.Material.Wood, true, "Frame")
	for _, side in { -1, 1 } do
		box(model, "BoardFrame", Vector3.new(frame, bh, bt + 0.4), Vector3.new(side * (bw / 2 + frame / 2), bottom, boardZ), WOOD, Enum.Material.Wood, true, "Frame")
	end
	box(model, "ChalkTray", Vector3.new(bw, 0.3, 1.2), Vector3.new(0, bottom - frame - 0.05, boardZ + 0.8), WOOD, Enum.Material.Wood, true, "Frame")
	for k, x in { -12, -11.2, -10.5, 9 } do
		local stick = piece(model, "TrayChalk", Vector3.new(1.1, 0.22, 0.22),
			CFrame.new(O + Vector3.new(x, bottom - frame + 0.36, boardZ + 0.8)) * CFrame.Angles(0, k * 0.4, 0), WHITE, Enum.Material.SmoothPlastic, nil, "Chalk")
		stick.Shape = Enum.PartType.Cylinder
	end
	box(model, "Eraser", Vector3.new(2.2, 0.5, 0.8), Vector3.new(12, bottom - frame + 0.25, boardZ + 0.8), DARK_WOOD, Enum.Material.Wood)
	box(model, "EraserFelt", Vector3.new(2.2, 0.2, 0.8), Vector3.new(12, bottom - frame + 0.05, boardZ + 0.8), Color3.fromRGB(60, 62, 70), Enum.Material.Fabric)

	-- A clock on the wall over the board (a face and two hands, no numbers).
	local clockAt = O + Vector3.new(0, bottom + bh + 3.4, boardZ - 0.9)
	local face = piece(model, "ClockFace", Vector3.new(0.3, 3.4, 3.4), CFrame.new(clockAt) * CFrame.Angles(0, math.pi / 2, 0), WHITE, Enum.Material.SmoothPlastic)
	face.Shape = Enum.PartType.Cylinder
	local rim = piece(model, "ClockRim", Vector3.new(0.25, 3.8, 3.8), CFrame.new(clockAt - Vector3.new(0, 0, 0.05)) * CFrame.Angles(0, math.pi / 2, 0), DARK_WOOD, Enum.Material.Wood, nil, "Trim")
	rim.Shape = Enum.PartType.Cylinder
	piece(model, "ClockHand", Vector3.new(0.15, 1.2, 0.08), CFrame.new(clockAt + Vector3.new(0.2, 0.45, 0.2)) * CFrame.Angles(0, 0, -0.5), Color3.fromRGB(30, 30, 30), Enum.Material.SmoothPlastic)
	piece(model, "ClockHand", Vector3.new(0.12, 1.5, 0.08), CFrame.new(clockAt + Vector3.new(-0.35, -0.3, 0.2)) * CFrame.Angles(0, 0, 1.1), Color3.fromRGB(30, 30, 30), Enum.Material.SmoothPlastic)

	-- The teacher's desk on the left, school desks facing the board, a bookshelf and a plant.
	box(model, "TeacherDesk", Vector3.new(8, 3, 3.6), Vector3.new(-17, 0, boardZ + 7), DARK_WOOD, Enum.Material.Wood, true)
	box(model, "TeacherDeskTop", Vector3.new(8.6, 0.3, 4.2), Vector3.new(-17, 3, boardZ + 7), WOOD, Enum.Material.Wood, true)
	box(model, "Apple", Vector3.new(0.7, 0.7, 0.7), Vector3.new(-14.5, 3.3, boardZ + 7), Color3.fromRGB(210, 40, 40), Enum.Material.SmoothPlastic).Shape = Enum.PartType.Ball
	for k = 0, 2 do
		box(model, "Book", Vector3.new(1.6, 0.35, 1.1), Vector3.new(-19, 3.3 + k * 0.35, boardZ + 7), ({ Color3.fromRGB(180, 50, 50), Color3.fromRGB(50, 90, 170), Color3.fromRGB(60, 140, 80) })[k + 1], Enum.Material.SmoothPlastic)
	end
	for row = 0, 1 do
		for col = -1, 1 do
			if not (row == 0 and col == 0) then
				desk(model, Vector3.new(col * 10 - 4, 0, boardZ + 15 + row * 9))
			end
		end
	end
	box(model, "Bookshelf", Vector3.new(2.4, 9, 7), Vector3.new(W / 2 - 2.4, 0, boardZ + 6), DARK_WOOD, Enum.Material.Wood, true)
	for shelf = 0, 3 do
		for k = 0, 5 do
			box(model, "ShelfBook", Vector3.new(1.6, 1.6, 0.7), Vector3.new(W / 2 - 3.2, 0.6 + shelf * 2.1, boardZ + 3.6 + k * 1),
				({ Color3.fromRGB(180, 60, 60), Color3.fromRGB(60, 100, 180), Color3.fromRGB(230, 180, 70), Color3.fromRGB(70, 150, 90) })[(shelf + k) % 4 + 1], Enum.Material.SmoothPlastic)
		end
	end
	box(model, "PlantPot", Vector3.new(2, 2, 2), Vector3.new(-W / 2 + 3, 0, boardZ + 2), Color3.fromRGB(186, 98, 60), Enum.Material.SmoothPlastic)
	for k = 0, 4 do
		local leaf = box(model, "PlantLeaf", Vector3.new(2.2, 2.2, 2.2), Vector3.new(-W / 2 + 3 + math.cos(k * 1.3) * 0.8, 2 + k * 0.7, boardZ + 2 + math.sin(k * 1.3) * 0.8),
			Color3.fromRGB(70, 150, 70), Enum.Material.Grass)
		leaf.Shape = Enum.PartType.Ball
	end
	for _, at in { Vector3.new(-12, H - 4, boardZ + 10), Vector3.new(12, H - 4, boardZ + 10), Vector3.new(0, H - 4, boardZ + 24) } do
		lamp(model, at)
	end

	-- Where the writer stands, and respawns.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "ChalkStart"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Enabled = false
	spawn.Size = Vector3.new(4, 0.4, 4)
	spawn.CFrame = ChalkBoard.standFrame() - Vector3.new(0, 2.8, 0)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.CanTouch = false
	spawn.Parent = model

	-- Each theme's own decorations, stored until chosen.
	local decor: { [string]: Folder } = {}
	local function folder(name: string): Folder
		local f = Instance.new("Folder")
		f.Name = "ChalkDecor_" .. name
		f.Parent = store
		decor[name] = f
		return f
	end
	local royal = folder("royal")
	local gem = DiamondShape.build(2.6, "BoardDiamond")
	gem.model.Parent = royal
	DiamondShape.place(gem, CFrame.new(O + Vector3.new(0, bottom + bh + 3.4, boardZ - 0.2)))
	for _, facet in gem.parts do
		facet.CanCollide = false
		facet.CanQuery = false
		facet.CanTouch = false
	end
	for _, side in { -1, 1 } do
		box(royal, "GoldPillar", Vector3.new(1.4, H - 2, 1.4), Vector3.new(side * (bw / 2 + 4), 0, boardZ - 0.6), GOLD, Enum.Material.Foil)
		box(royal, "Banner", Vector3.new(4, 9, 0.2), Vector3.new(side * (bw / 2 + 8), 6, boardZ - 0.8), Color3.fromRGB(34, 52, 140), Enum.Material.Fabric)
	end
	local sakura = folder("sakura")
	for _, side in { -1, 1 } do
		for k = 0, 6 do
			local blossom = piece(sakura, "Blossom", Vector3.new(2.4, 2.4, 2.4),
				CFrame.new(O + Vector3.new(side * (W / 2 - 1.6), 9 + math.sin(k * 1.7) * 1.4, -11 + k * 2.3 - 2)), PINK, Enum.Material.SmoothPlastic)
			blossom.Shape = Enum.PartType.Ball
		end
		piece(sakura, "Branch", Vector3.new(0.5, 0.5, 15), CFrame.new(O + Vector3.new(side * (W / 2 - 1.4), 8.6, -5)) * CFrame.Angles(0.15, 0, 0), DARK_WOOD, Enum.Material.Wood)
		for k = 0, 3 do
			local lantern = piece(sakura, "PaperLantern", Vector3.new(1.4, 1.8, 1.8), CFrame.new(O + Vector3.new(side * 14, H - 6 - (k % 2), boardZ + 4 + k * 8)) * CFrame.Angles(0, 0, math.pi / 2),
				Color3.fromRGB(240, 70, 80), Enum.Material.Neon)
			lantern.Shape = Enum.PartType.Cylinder
		end
	end
	local neon = folder("neon")
	for _, side in { -1, 1 } do
		piece(neon, "NeonStrip", Vector3.new(0.3, 0.3, D), CFrame.new(O + Vector3.new(side * (W / 2 - 1.1), 0.2, 0)), Color3.fromRGB(70, 230, 255), Enum.Material.Neon)
		piece(neon, "NeonStrip", Vector3.new(0.3, 0.3, D), CFrame.new(O + Vector3.new(side * (W / 2 - 1.1), H - 1, 0)), Color3.fromRGB(255, 70, 200), Enum.Material.Neon)
	end
	piece(neon, "NeonStrip", Vector3.new(W, 0.3, 0.3), CFrame.new(O + Vector3.new(0, H - 1, boardZ - 0.9)), Color3.fromRGB(70, 230, 255), Enum.Material.Neon)
	for k = -2, 2 do
		piece(neon, "NeonStar", Vector3.new(0.6, 0.6, 0.6), CFrame.new(O + Vector3.new(k * 6, bottom + bh + 2.4 + (k % 2), boardZ - 0.8)) * CFrame.Angles(0, 0, math.pi / 4),
			if k % 2 == 0 then Color3.fromRGB(255, 70, 200) else Color3.fromRGB(70, 230, 255), Enum.Material.Neon)
	end

	local built: Built = { model = model, spawn = spawn, decor = decor, store = store, theme = "" }
	Classroom.setTheme(built, theme or "classic")
	return built
end

-- Recolours the classroom for a theme and swaps in its decorations.
function Classroom.setTheme(built: Built, name: string)
	local theme = ChalkBoard.theme(name)
	local key = if ChalkBoard.THEMES[name] then name else "classic"
	built.theme = key
	for _, item in built.model:GetDescendants() do
		if item:IsA("BasePart") then
			local role = item:GetAttribute("Role")
			if role == "Board" then
				item.Color, item.Material = theme.board, theme.boardMaterial
			elseif role == "Frame" then
				item.Color, item.Material = theme.frame, theme.frameMaterial
			elseif role == "Wall" then
				item.Color = theme.wall
			elseif role == "Trim" then
				item.Color = theme.trim
			elseif role == "Floor" then
				item.Color, item.Material = theme.floor, theme.floorMaterial
			elseif role == "Chalk" then
				item.Color = theme.chalk
			elseif role == "Bulb" then
				item.Color = theme.light
			end
		elseif item:IsA("PointLight") and item.Name == "LampLight" then
			item.Color = theme.light
		end
	end
	for themeName, folder in built.decor do
		folder.Parent = if themeName == key then built.model else built.store
	end
end

return Classroom
