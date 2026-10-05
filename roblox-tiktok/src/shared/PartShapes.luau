--!strict
-- Which way Roblox's native wedge shapes face, measured once by raycasting a
-- hidden sample of each rather than assumed. Rock slopes and low-poly trees
-- both depend on it: a wedge turned the wrong way would leave holes or grow
-- upside-down trees.
local PartShapes = {}

local wedgeFront: number? = nil
local cornerTall: { number }? = nil

-- Index of the probe point where the sample's top sits highest, or nil.
local function probe(className: string, points: { { number } }): number?
	local ok, result = pcall(function(): number?
		local sample = Instance.new(className) :: BasePart
		sample.Size = Vector3.new(4, 4, 4)
		sample.Anchored = true
		sample.CanCollide = false
		sample.CanTouch = false
		sample.CastShadow = false
		sample.Transparency = 1
		sample.CFrame = CFrame.new(0, 4000, 0)
		sample.Parent = workspace
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { sample }
		local best, bestIndex = -math.huge, nil
		for index, point in points do
			local hit = workspace:Raycast(Vector3.new(point[1], 4010, point[2]), Vector3.new(0, -20, 0), params)
			if hit and hit.Position.Y > best + 0.05 then
				best, bestIndex = hit.Position.Y, index
			end
		end
		sample:Destroy()
		return bestIndex
	end)
	return if ok then result else nil
end

-- -1 when a wedge slopes down towards its LookVector (-Z), +1 for +Z.
function PartShapes.wedgeFront(): number
	if wedgeFront == nil then
		wedgeFront = if probe("WedgePart", { { 0, 1.5 }, { 0, -1.5 } }) == 2 then 1 else -1
	end
	return wedgeFront :: number
end

-- A wedge rotation (no position) sloping down towards a horizontal direction.
function PartShapes.wedgeToward(direction: Vector3): CFrame
	return CFrame.lookAt(Vector3.zero, direction * -PartShapes.wedgeFront())
end

-- The local (x, z) signs of a corner wedge's tall corner.
function PartShapes.cornerTall(): { number }
	if cornerTall == nil then
		local corners = { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
		cornerTall = corners[probe("CornerWedgePart", corners) or 2]
	end
	return cornerTall :: { number }
end

-- A corner wedge rotation whose tall corner points along (x, z) signs.
function PartShapes.cornerToward(x: number, z: number): CFrame
	local tall = PartShapes.cornerTall()
	for turn = 0, 3 do
		local rotation = CFrame.Angles(0, turn * math.pi / 2, 0)
		local corner = rotation:VectorToWorldSpace(Vector3.new(tall[1], 0, tall[2]))
		if math.abs(corner.X - x) < 0.1 and math.abs(corner.Z - z) < 0.1 then
			return rotation
		end
	end
	return CFrame.identity
end

return PartShapes
