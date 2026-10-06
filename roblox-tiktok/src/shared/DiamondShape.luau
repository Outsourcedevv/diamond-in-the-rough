--!strict
-- An eight-sided brilliant-cut gem, made from native triangular facets.
-- Light crown, deeper blue pavilion and a bright table give it the familiar
-- diamond silhouette against any background, including the open sky.
--
-- The haystack skin (see Skin) swaps the gem for a needle: a slim steel shaft
-- with a sharp point, an open eye and a red thread, lying at a slant. A root
-- part's "GemKind" attribute ("diamond" or "needle") says which it shows.
local DiamondShape = {}

-- `shape` is the part shape: a triangular facet (the default, a WedgePart),
-- or "Block", "Cylinder" (along X) or "Ball".
export type Facet = { offset: CFrame, size: Vector3, colour: Color3, material: Enum.Material, shape: string? }

local THICKNESS = 0.006

local STEEL = Color3.fromRGB(206, 212, 220)
local THREAD = Color3.fromRGB(214, 40, 52)

-- A needle about 1.3 x `scale` studs long, slanting through its centre.
local function needle(scale: number): { Facet }
	local list: { Facet } = {}
	local along = Vector3.new(math.sin(math.rad(50)), math.cos(math.rad(50)), 0)
	local across = Vector3.new(0, 0, 1)
	local side = along:Cross(across).Unit
	local function rod(name: string, from: number, to: number, width: number, colour: Color3, material: Enum.Material, shift: Vector3?)
		local centre = along * ((from + to) / 2) + (shift or Vector3.zero)
		table.insert(list, {
			offset = CFrame.fromMatrix(centre * scale, along, side),
			size = Vector3.new(to - from, width, width) * scale,
			colour = colour,
			material = material,
			shape = name,
		})
	end
	-- The shaft, then a point that narrows in steps.
	rod("Cylinder", -0.34, 0.46, 0.09, STEEL, Enum.Material.Metal)
	rod("Cylinder", -0.5, -0.33, 0.06, STEEL, Enum.Material.Metal)
	rod("Cylinder", -0.62, -0.49, 0.032, STEEL, Enum.Material.Metal)
	-- A bright glint runs down the shaft, so the needle catches the eye.
	rod("Block", -0.3, 0.3, 0.022, Color3.fromRGB(240, 250, 255), Enum.Material.Neon, side * 0.04)
	-- The eye: two flat prongs either side of a slot, joined by a rounded head.
	for _, offset in { -0.032, 0.032 } do
		rod("Block", 0.45, 0.63, 0.026, STEEL, Enum.Material.Metal, side * offset)
	end
	table.insert(list, {
		offset = CFrame.new(along * 0.63 * scale),
		size = Vector3.one * 0.09 * scale,
		colour = STEEL,
		material = Enum.Material.Metal,
		shape = "Ball",
	})
	-- A red thread through the eye, trailing down in a loose loop.
	local eye = along * 0.55
	local points = { eye, eye + Vector3.new(0.16, -0.22, 0.08), eye + Vector3.new(0.3, -0.5, 0.12), eye + Vector3.new(0.42, -0.62, 0.02) }
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local direction = (b - a).Unit
		local up = if math.abs(direction.Y) > 0.99 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
		table.insert(list, {
			offset = CFrame.fromMatrix((a + b) / 2 * scale, direction, direction:Cross(up):Cross(direction).Unit),
			size = Vector3.new((b - a).Magnitude + 0.02, 0.026, 0.026) * scale,
			colour = THREAD,
			material = Enum.Material.Fabric,
			shape = "Cylinder",
		})
	end
	return list
end

-- Facet layout for a gem whose bounding size is `scale` studs, relative to its
-- centre. `kind` is "diamond" (the default) or "needle".
function DiamondShape.facets(scale: number, kind: string?): { Facet }
	if kind == "needle" then return needle(scale) end
	local list: { Facet } = {}
	local function triangle(a: Vector3, b: Vector3, c: Vector3, colour: Color3, material: Enum.Material)
		local ab, ac, bc = b - a, c - a, c - b
		if ab.Magnitude > ac.Magnitude and ab.Magnitude > bc.Magnitude then c, a = a, c
		elseif ac.Magnitude > bc.Magnitude then a, b = b, a end
		ab, ac, bc = b - a, c - a, c - b
		local right = ac:Cross(ab).Unit
		local up = bc:Cross(right).Unit
		local back = bc.Unit
		local height = math.abs(ab:Dot(up))
		for _, spec in { { (a + b) / 2, right, back, math.abs(ab:Dot(back)) }, { (a + c) / 2, -right, -back, math.abs(ac:Dot(back)) } } do
			if spec[4] < 0.0001 then continue end
			table.insert(list, {
				offset = CFrame.fromMatrix(spec[1] * scale, spec[2], up, spec[3]),
				size = Vector3.new(THICKNESS, height, spec[4]) * scale,
				colour = colour,
				material = material,
			})
		end
	end
	for i = 0, 7 do
		local a, b = i * math.pi / 4, (i + 1) * math.pi / 4
		local rimA = Vector3.new(math.cos(a) * 0.5, 0.08, math.sin(a) * 0.5)
		local rimB = Vector3.new(math.cos(b) * 0.5, 0.08, math.sin(b) * 0.5)
		local topA = Vector3.new(math.cos(a) * 0.26, 0.34, math.sin(a) * 0.26)
		local topB = Vector3.new(math.cos(b) * 0.26, 0.34, math.sin(b) * 0.26)
		local alternate = i % 2
		-- Pavilion: the long point underneath, in deeper blues.
		triangle(Vector3.new(0, -0.55, 0), rimA, rimB, Color3.fromRGB(62 + alternate * 34, 150 + alternate * 30, 232 + alternate * 12), Enum.Material.SmoothPlastic)
		-- Crown: pale, alternating facets catch the light.
		triangle(rimA, topA, topB, Color3.fromRGB(175 + alternate * 45, 232 + alternate * 16, 255), Enum.Material.SmoothPlastic)
		triangle(rimA, topB, rimB, Color3.fromRGB(140 + alternate * 40, 214 + alternate * 20, 252), Enum.Material.SmoothPlastic)
		-- Table: the flat top glints.
		triangle(Vector3.new(0, 0.34, 0), topB, topA, Color3.fromRGB(215, 248, 255), Enum.Material.Neon)
	end
	return list
end

local function facetPart(facet: Facet): Part
	local face = Instance.new(if facet.shape == nil then "WedgePart" else "Part") :: any
	if facet.shape == "Cylinder" then face.Shape = Enum.PartType.Cylinder
	elseif facet.shape == "Ball" then face.Shape = Enum.PartType.Ball end
	face.Name = "Facet"
	face.Size = facet.size
	face.Color = facet.colour
	face.Material = facet.material
	face.Reflectance = if facet.material == Enum.Material.Neon or facet.material == Enum.Material.Fabric then 0 else 0.3
	face.CanCollide = false
	face.CanQuery = false
	face.CanTouch = false
	face.Massless = true
	face.CastShadow = false
	return face
end

-- Welds visible facets to an invisible root part (the server's world gem).
-- The root must already be in the workspace so the welds keep these offsets.
function DiamondShape.attach(root: BasePart)
	root.Transparency = 1
	root.Reflectance = 0
	root.Material = Enum.Material.SmoothPlastic
	local facets = Instance.new("Folder")
	facets.Name = "Facets"
	facets.Parent = root
	local kind = root:GetAttribute("GemKind")
	for _, facet in DiamondShape.facets(root.Size.X, if type(kind) == "string" then kind else nil) do
		local face = facetPart(facet)
		face.CFrame = root.CFrame * facet.offset
		face.Parent = facets
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = face
		weld.Parent = face
	end
end

-- An unwelded, anchored gem for local effects. Move it with DiamondShape.place:
-- welds made while a part is outside the workspace keep stale offsets, which
-- left the old held gem's facets behind at the world origin.
export type Gem = { model: Model, parts: { BasePart }, offsets: { CFrame }, frames: { CFrame } }

function DiamondShape.build(size: number, name: string, kind: string?): Gem
	local model = Instance.new("Model")
	model.Name = name
	local parts: { BasePart }, offsets: { CFrame }, frames: { CFrame } = {}, {}, {}
	for _, facet in DiamondShape.facets(size, kind) do
		local face = facetPart(facet)
		face.Anchored = true
		face.Parent = model
		table.insert(parts, face)
		table.insert(offsets, facet.offset)
		table.insert(frames, facet.offset)
	end
	return { model = model, parts = parts, offsets = offsets, frames = frames }
end

-- Moves every facet of a built gem in one engine call.
function DiamondShape.place(gem: Gem, frame: CFrame)
	local frames = gem.frames
	for index, offset in gem.offsets do
		frames[index] = frame * offset
	end
	workspace:BulkMoveTo(gem.parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Facets are independent welded parts; resizing only the invisible root does
-- not resize the visible gem. Rebuild them only when its size actually changes.
function DiamondShape.resize(root: BasePart, size: Vector3)
	if root.Size == size then return end
	local visible = root:GetAttribute("GemVisible") == true
	local facets = root:FindFirstChild("Facets")
	if facets then facets:Destroy() end
	root.Size = size
	DiamondShape.attach(root)
	root:SetAttribute("GemVisible", nil)
	DiamondShape.visible(root, visible)
end

-- Switches a world gem between the diamond and the needle, keeping its size
-- and whether it shows.
function DiamondShape.setKind(root: BasePart, kind: string)
	if (root:GetAttribute("GemKind") or "diamond") == kind then return end
	root:SetAttribute("GemKind", kind)
	local visible = root:GetAttribute("GemVisible") == true
	local facets = root:FindFirstChild("Facets")
	if facets then facets:Destroy() end
	DiamondShape.attach(root)
	root:SetAttribute("GemVisible", nil)
	DiamondShape.visible(root, visible)
end

function DiamondShape.visible(root: BasePart, visible: boolean)
	if root:GetAttribute("GemVisible") == visible then return end
	root:SetAttribute("GemVisible", visible)
	root.Transparency = 1
	local facets = root:FindFirstChild("Facets")
	if facets == nil then return end
	for _, face in facets:GetChildren() do
		(face :: BasePart).Transparency = if visible then 0 else 1
	end
end

return DiamondShape
