--!strict
-- Two giant wooden leaderboards behind the mountain: top gifters (blue trim,
-- gift box on the roof) and top likers (red trim, heart on the roof). Totals
-- are tallied per TikTok viewer and saved with the streamer's settings.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("DiamondRush")
local Format = require(Shared:WaitForChild("Format"))
local PartShapes = require(Shared:WaitForChild("PartShapes"))

local Leaderboards = {}

Leaderboards.ROWS = 10
local KEEP = 1000 -- viewers remembered per board after pruning
local PRUNE_AT = 5000

-- Tally ------------------------------------------------------------------------
export type Entry = { key: string, name: string, value: number }
export type Tally = {
	add: (key: string, name: string, amount: number) -> (),
	top: (count: number) -> { Entry },
	serialize: (count: number) -> { { u: string, n: string, v: number } },
	reset: () -> (),
	size: () -> number,
}

-- Running totals per viewer. `saved` is a list from serialize().
function Leaderboards.tally(saved: any): Tally
	local entries: { [string]: Entry } = {}
	local count = 0
	local function top(limit: number): { Entry }
		local list = {}
		for _, entry in entries do table.insert(list, entry) end
		table.sort(list, function(a, b)
			if a.value ~= b.value then return a.value > b.value end
			return a.key < b.key
		end)
		for i = #list, limit + 1, -1 do list[i] = nil end
		return list
	end
	local self: Tally
	self = {
		add = function(key: string, name: string, amount: number)
			if amount <= 0 or key == "" then return end
			local entry = entries[key]
			if entry == nil then
				entry = { key = key, name = name, value = 0 }
				entries[key] = entry
				count += 1
			end
			entry.value += amount
			if name ~= "" then entry.name = name end
			if count > PRUNE_AT then
				-- Keep memory bounded over a long stream: drop the smallest totals.
				local kept = top(KEEP)
				table.clear(entries)
				for _, survivor in kept do entries[survivor.key] = survivor end
				count = #kept
			end
		end,
		top = top,
		serialize = function(limit: number)
			local out = {}
			for _, entry in top(limit) do table.insert(out, { u = entry.key, n = entry.name, v = entry.value }) end
			return out
		end,
		reset = function()
			table.clear(entries)
			count = 0
		end,
		size = function() return count end,
	}
	if type(saved) == "table" then
		for _, row in saved do
			if type(row) == "table" and type(row.u) == "string" and type(row.n) == "string" and type(row.v) == "number" and row.v > 0 then
				self.add(string.sub(row.u, 1, 40), string.sub(row.n, 1, 40), math.floor(row.v))
			end
		end
	end
	return self
end

-- The 3D boards ----------------------------------------------------------------
export type Style = {
	title: string,
	unit: string,
	trim: Color3,
	valueColour: Color3,
	emblem: string, -- "gift" or "heart"
	empty: string,
}
export type Board = { model: Model, show: (entries: { Entry }) -> () }

local WIDTH, HEIGHT = 36, 28
local WOOD_DARK = Color3.fromRGB(86, 62, 42)
local WOOD = Color3.fromRGB(122, 90, 60)
local WOOD_FACE = Color3.fromRGB(158, 120, 82)
local GOLD = Color3.fromRGB(232, 184, 56)
local MEDALS = { Color3.fromRGB(255, 202, 64), Color3.fromRGB(206, 212, 222), Color3.fromRGB(205, 128, 56) }

local function piece(parent: Instance, name: string, size: Vector3, frame: CFrame, colour: Color3, material: Enum.Material, kind: string?): BasePart
	local p = Instance.new(kind or "Part") :: BasePart
	p.Name = name
	p.Size = size
	p.CFrame = frame
	p.Color = colour
	p.Material = material
	p.Anchored = true
	p.CanCollide = true
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function log(parent: Instance, name: string, a: Vector3, b: Vector3, width: number, colour: Color3): BasePart
	local delta = b - a
	local p = piece(parent, name, Vector3.new(delta.Magnitude, width, width), CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0), colour, Enum.Material.Wood)
	local cylinder = p :: Part
	cylinder.Shape = Enum.PartType.Cylinder
	return p
end

local function surfaceGui(part: BasePart, pixelsPerStud: number): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = 0.2
	gui.Brightness = 1.4
	gui.MaxDistance = 2000
	gui.Parent = part
	return gui
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(255, 244, 222)
	text.TextStrokeColor3 = Color3.fromRGB(40, 24, 12)
	text.TextStrokeTransparency = 0.2
	for key, value in props do (text :: any)[key] = value end
	text.Parent = parent
	return text
end

-- A gift box with a gold ribbon and bow, or a chunky wooden heart.
local function emblem(parent: Instance, kind: string, at: CFrame, colour: Color3)
	if kind == "gift" then
		piece(parent, "GiftBox", Vector3.new(4.6, 4.6, 4.6), at, colour, Enum.Material.Wood)
		piece(parent, "Ribbon", Vector3.new(4.8, 4.8, 0.9), at, GOLD, Enum.Material.Metal)
		piece(parent, "Ribbon", Vector3.new(0.9, 4.8, 4.8), at, GOLD, Enum.Material.Metal)
		for _, side in { -1, 1 } do
			piece(parent, "Bow", Vector3.new(1.8, 0.9, 1.1), at * CFrame.new(side * 0.8, 2.75, 0) * CFrame.Angles(0, 0, side * math.rad(35)), GOLD, Enum.Material.Metal)
		end
	else
		local size = 3.6
		piece(parent, "Heart", Vector3.new(size, size, 1.6), at * CFrame.Angles(0, 0, math.rad(45)), colour, Enum.Material.Wood)
		local offset = size / (2 * math.sqrt(2))
		for _, side in { -1, 1 } do
			local lobe = piece(parent, "HeartLobe", Vector3.new(1.6, size, size), at * CFrame.new(side * offset, offset, 0) * CFrame.Angles(0, math.pi / 2, 0), colour, Enum.Material.Wood)
			local cylinder = lobe :: Part
			cylinder.Shape = Enum.PartType.Cylinder
		end
	end
end

-- Builds one board standing on the ground at `base`, facing `facing`, with its
-- list panel raised `lift` studs. `ground(position)` gives the terrain height.
function Leaderboards.build(parent: Instance, base: Vector3, facing: Vector3, lift: number, style: Style, ground: (Vector3) -> number): Board
	local model = Instance.new("Model")
	model.Name = style.title
	model.Parent = parent
	local look = Vector3.new(facing.X, 0, facing.Z).Unit
	local right = look:Cross(Vector3.new(0, 1, 0)).Unit
	local postOffsets = { -(WIDTH / 2 - 4), WIDTH / 2 - 4 }
	local floor = -math.huge
	for _, offset in postOffsets do
		floor = math.max(floor, ground(base + right * offset))
	end
	local centre = Vector3.new(base.X, floor + lift + HEIGHT / 2, base.Z)
	local frame = CFrame.lookAt(centre, centre + look)

	-- The panel: dark backing, light planks for the list, painted trim.
	piece(model, "Backing", Vector3.new(WIDTH + 1, HEIGHT + 1, 1.2), frame * CFrame.new(0, 0, 0.6), WOOD_DARK, Enum.Material.WoodPlanks)
	local face = piece(model, "Face", Vector3.new(WIDTH - 2.4, HEIGHT - 2.4, 0.3), frame * CFrame.new(0, 0, -0.15), WOOD_FACE, Enum.Material.WoodPlanks)
	local trimWidth = 1.7
	local outerW, outerH = WIDTH + 1, HEIGHT + 1
	for _, side in { -1, 1 } do
		piece(model, "Trim", Vector3.new(outerW, trimWidth, 1), frame * CFrame.new(0, side * (outerH / 2 - trimWidth / 2), -0.5), style.trim, Enum.Material.Wood)
		piece(model, "Trim", Vector3.new(trimWidth, outerH - trimWidth * 2, 1), frame * CFrame.new(side * (outerW / 2 - trimWidth / 2), 0, -0.5), style.trim, Enum.Material.Wood)
		for _, vertical in { -1, 1 } do
			piece(model, "TrimCorner", Vector3.new(2.3, 2.3, 1.3), frame * CFrame.new(side * (outerW / 2 - 1), vertical * (outerH / 2 - 1), -0.6), style.trim:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.Wood)
		end
	end

	-- A title plank on top, edged in the trim colour, under a shingle roof.
	local headerY = HEIGHT / 2 + 0.5 + 3.4
	piece(model, "TitleEdge", Vector3.new(WIDTH * 0.74 + 1.4, 6.6, 0.8), frame * CFrame.new(0, headerY, 0.3), style.trim, Enum.Material.Wood)
	local title = piece(model, "Title", Vector3.new(WIDTH * 0.74, 5.4, 1.2), frame * CFrame.new(0, headerY, -0.3), WOOD, Enum.Material.WoodPlanks)
	local roofY = headerY + 3.3 + 1.3
	for _, side in { -1, 1 } do
		local slope = look * -side
		piece(model, "Roof", Vector3.new(WIDTH + 4, 2.6, 2.6), CFrame.new((frame * CFrame.new(0, roofY, side * 1.3)).Position) * PartShapes.wedgeToward(slope),
			Color3.fromRGB(70, 60, 56), Enum.Material.RoofShingles, "WedgePart")
	end
	piece(model, "RoofRidge", Vector3.new(WIDTH + 4.4, 0.6, 0.6), frame * CFrame.new(0, roofY + 1.3, 0), WOOD_DARK, Enum.Material.Wood)
	emblem(model, style.emblem, frame * CFrame.new(0, roofY + 1.6 + 2.5, 0), style.trim)

	-- Log posts behind the panel, X-braced underneath, on stone footings.
	local top = (frame * CFrame.new(0, headerY + 3, 0)).Position.Y
	local postFeet = {}
	for _, offset in postOffsets do
		local spot = base + right * offset + look * -1.9
		local foot = ground(spot)
		table.insert(postFeet, Vector3.new(spot.X, foot, spot.Z))
		log(model, "Post", Vector3.new(spot.X, foot - 2, spot.Z), Vector3.new(spot.X, top, spot.Z), 1.9, WOOD)
		piece(model, "Footing", Vector3.new(3.4, 1.6, 3.4), CFrame.lookAt(Vector3.new(spot.X, foot + 0.4, spot.Z), Vector3.new(spot.X, foot + 0.4, spot.Z) + look), Color3.fromRGB(118, 114, 106), Enum.Material.Cobblestone)
	end
	local panelBottom = centre.Y - HEIGHT / 2 - 1
	local a, b = postFeet[1], postFeet[2]
	log(model, "Brace", Vector3.new(a.X, a.Y + 2, a.Z), Vector3.new(b.X, panelBottom, b.Z), 0.9, WOOD_DARK)
	log(model, "Brace", Vector3.new(b.X, b.Y + 2, b.Z), Vector3.new(a.X, panelBottom, a.Z), 0.9, WOOD_DARK)
	log(model, "Rail", Vector3.new(a.X, panelBottom, a.Z), Vector3.new(b.X, panelBottom, b.Z), 1.1, WOOD)

	-- Title and rows.
	local titleGui = surfaceGui(title, 24)
	label(titleGui, { Size = UDim2.fromScale(0.94, 0.86), Position = UDim2.fromScale(0.03, 0.07), Text = style.title })
	local gui = surfaceGui(face, 20)
	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Size = UDim2.fromScale(0.94, 0.94)
	list.Position = UDim2.fromScale(0.03, 0.03)
	list.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.008, 0)
	layout.Parent = list
	local rows = {}
	for rank = 1, Leaderboards.ROWS do
		local row = Instance.new("Frame")
		row.LayoutOrder = rank
		row.Size = UDim2.fromScale(1, 1 / Leaderboards.ROWS - 0.008)
		row.BackgroundColor3 = Color3.fromRGB(46, 30, 18)
		row.BackgroundTransparency = if rank % 2 == 1 then 0.3 else 0.42
		row.BorderSizePixel = 0
		row.Parent = list
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.25, 0)
		corner.Parent = row
		local badge = Instance.new("Frame")
		badge.Size = UDim2.fromScale(0.08, 0.84)
		badge.Position = UDim2.fromScale(0.012, 0.08)
		badge.BackgroundColor3 = MEDALS[rank] or Color3.fromRGB(96, 70, 46)
		badge.BorderSizePixel = 0
		badge.Parent = row
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(1, 0)
		round.Parent = badge
		local ratio = Instance.new("UIAspectRatioConstraint")
		ratio.Parent = badge
		label(badge, { Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1), Text = tostring(rank),
			TextColor3 = if rank <= 3 then Color3.fromRGB(60, 36, 12) else Color3.fromRGB(255, 244, 222), TextStrokeTransparency = if rank <= 3 then 1 else 0.2 })
		local name = label(row, { Size = UDim2.fromScale(0.56, 0.74), Position = UDim2.fromScale(0.12, 0.13), TextXAlignment = Enum.TextXAlignment.Left, Text = "" })
		local value = label(row, { Size = UDim2.fromScale(0.3, 0.7), Position = UDim2.fromScale(0.685, 0.15), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = style.valueColour, Text = "" })
		table.insert(rows, { row = row, name = name, value = value })
	end
	local empty = label(gui, { Size = UDim2.fromScale(0.8, 0.22), Position = UDim2.fromScale(0.1, 0.39), Text = style.empty })

	local function show(entries: { Entry })
		for rank, row in rows do
			local entry = entries[rank]
			row.row.Visible = entry ~= nil
			if entry then
				row.name.Text = entry.name
				row.value.Text = Format.commas(entry.value) .. " " .. style.unit
			end
		end
		empty.Visible = #entries == 0
	end
	show({})
	return { model = model, show = show }
end

-- Where the boards stand: behind the mountain as seen from the camp, either
-- side of the summit, angled towards the camp.
function Leaderboards.spots(arenaRadius: number, mountainRadius: number, camp: Vector3): { { at: Vector3, facing: Vector3 } }
	local z = -(arenaRadius + 26)
	local x = mountainRadius * 0.4 + 20
	local spots = {}
	for _, side in { -1, 1 } do
		local at = Vector3.new(side * x, 0, z)
		table.insert(spots, { at = at, facing = Vector3.new(camp.X - at.X, 0, camp.Z - at.Z).Unit })
	end
	return spots
end

return Leaderboards
