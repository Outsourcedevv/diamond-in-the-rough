--!strict
-- An eight-sided brilliant-cut gem, made from native triangular facets.
-- Light crown, deeper blue pavilion and a bright table give it the familiar
-- diamond silhouette against any background, including the open sky.
local DiamondShape = {}

export type Facet = { offset: CFrame, size: Vector3, colour: Color3, material: Enum.Material }

local THICKNESS = 0.006

-- Facet layout for a gem whose bounding size is `scale` studs, relative to its centre.
function DiamondShape.facets(scale: number): { Facet }
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
	local face = Instance.new("WedgePart") :: any
	face.Name = "Facet"
	face.Size = facet.size
	face.Color = facet.colour
	face.Material = facet.material
	face.Reflectance = if facet.material == Enum.Material.Neon then 0 else 0.3
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
	for _, facet in DiamondShape.facets(root.Size.X) do
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

function DiamondShape.build(size: number, name: string): Gem
	local model = Instance.new("Model")
	model.Name = name
	local parts: { BasePart }, offsets: { CFrame }, frames: { CFrame } = {}, {}, {}
	for _, facet in DiamondShape.facets(size) do
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

function DiamondShape.visible(root: BasePart, visible: boolean)
	if root:GetAttribute("GemVisible") == visible then return end
	root:SetAttribute("GemVisible", visible)
	root.Transparency = 1
	for _, face in root.Facets:GetChildren() do
		(face :: BasePart).Transparency = if visible then 0 else 1
	end
end

return DiamondShape
