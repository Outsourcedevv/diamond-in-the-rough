--!strict
-- An eight-sided brilliant-cut gem, made from native triangular facets.
local DiamondShape = {}
function DiamondShape.attach(root: BasePart)
	root.Transparency = 1
	local scale = root.Size.X
	local facets = Instance.new("Folder")
	facets.Name = "Facets"
	facets.Parent = root
	local function triangle(a: Vector3, b: Vector3, c: Vector3, shade: number)
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
			local face = Instance.new("WedgePart")
			face.Name = "Facet"
			face.Size = Vector3.new(0.005, height, spec[4]) * scale
			face.CFrame = root.CFrame * CFrame.fromMatrix(spec[1] * scale, spec[2], up, spec[3])
			face.Color = Color3.fromRGB(100 + shade * 100, 195 + shade * 50, 245)
			face.Material = Enum.Material.Glass
			face.Reflectance = 0.18
			face.Transparency = 0.08
			face.CanCollide = false
			face.CanQuery = false
			face.CanTouch = false
			face.Massless = true
			face.CastShadow = false
			face.Parent = facets
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = face
			weld.Parent = face
		end
	end
	for i = 0, 7 do
		local a, b = i * math.pi / 4, (i + 1) * math.pi / 4
		local rimA = Vector3.new(math.cos(a) * 0.5, 0.08, math.sin(a) * 0.5)
		local rimB = Vector3.new(math.cos(b) * 0.5, 0.08, math.sin(b) * 0.5)
		local topA = Vector3.new(math.cos(a) * 0.26, 0.34, math.sin(a) * 0.26)
		local topB = Vector3.new(math.cos(b) * 0.26, 0.34, math.sin(b) * 0.26)
		triangle(Vector3.new(0, -0.55, 0), rimA, rimB, 0.25 + i % 3 * 0.2)
		triangle(rimA, topA, topB, 0.55 + i % 2 * 0.3)
		triangle(rimA, topB, rimB, 0.4 + i % 3 * 0.2)
		triangle(Vector3.new(0, 0.34, 0), topB, topA, 0.9)
	end
end
function DiamondShape.visible(root: BasePart, visible: boolean)
	if root:GetAttribute("GemVisible") == visible then return end
	root:SetAttribute("GemVisible", visible)
	root.Transparency = 1
	for _, face in root.Facets:GetChildren() do
		(face :: BasePart).Transparency = if visible then 0.08 else 1
	end
end
return DiamondShape
