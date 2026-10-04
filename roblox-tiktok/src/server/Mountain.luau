--!strict
-- Draws the mountain: one small rock per stone. To keep Roblox fast only the
-- rocks on the outside exist as parts; rocks inside are tracked by the grid
-- and get a part the moment digging uncovers them, so it looks solid.
local Debris = game:GetService("Debris")

local Grid = require(script.Parent.Grid)

local Mountain = {}
Mountain.__index = Mountain

local ROCK = {
	Color3.fromRGB(92, 88, 84),
	Color3.fromRGB(110, 106, 100),
	Color3.fromRGB(128, 124, 116),
	Color3.fromRGB(146, 140, 130),
}
local ORES = {
	Color3.fromRGB(240, 196, 64), -- gold
	Color3.fromRGB(46, 196, 120), -- emerald
	Color3.fromRGB(224, 52, 76), -- ruby
	Color3.fromRGB(60, 110, 230), -- sapphire
	Color3.fromRGB(160, 90, 220), -- amethyst
	Color3.fromRGB(205, 120, 60), -- copper
}
local FLYING_LIMIT = 40

export type Mountain = typeof(setmetatable(
	{} :: {
		grid: Grid.Grid,
		folder: Folder,
		parts: { [number]: BasePart },
		keys: { [BasePart]: number },
		tops: { [number]: number },
		blockSize: number,
		random: Random,
		diamondKey: number,
		revealed: boolean,
		onDiamondCell: () -> (),
	},
	Mountain
))

function Mountain.new(parent: Instance, stones: number, blockSize: number, onDiamondCell: () -> ()): Mountain
	local random = Random.new()
	local function rand(a: number?, b: number?): number
		if a ~= nil and b ~= nil then
			return random:NextInteger(a, b)
		end
		return random:NextNumber()
	end
	local grid = Grid.new(stones, random:NextNumber(0, 1000), rand)
	local diamondKey = grid:carveHiddenCell()
	local folder = Instance.new("Folder")
	folder.Name = "Mountain"
	local self = setmetatable({
		grid = grid,
		folder = folder,
		parts = {},
		keys = {},
		tops = {},
		blockSize = blockSize,
		random = random,
		diamondKey = diamondKey,
		revealed = false,
		onDiamondCell = onDiamondCell,
	}, Mountain)
	for _, key in grid.order do
		local x, y, z = Grid.coords(key)
		local column = Grid.key(x, 0, z)
		self.tops[column] = math.max(self.tops[column] or 0, y)
	end
	for _, key in grid.exposedList do
		self:_draw(key)
	end
	grid:takeFresh()
	folder.Parent = parent
	return self
end

function Mountain.cellPosition(self: Mountain, x: number, y: number, z: number): Vector3
	local size = self.blockSize
	return Vector3.new(x * size, y * size + size / 2, z * size)
end

function Mountain.keyPosition(self: Mountain, key: number): Vector3
	local x, y, z = Grid.coords(key)
	return self:cellPosition(x, y, z)
end

function Mountain._draw(self: Mountain, key: number)
	local existing: BasePart? = self.parts[key]
	if existing ~= nil or not self.grid:isSolid(key) then
		return
	end
	local x, y, z = Grid.coords(key)
	local size = self.blockSize
	local part = Instance.new("Part")
	part.Name = "Stone"
	part.Anchored = true
	part.CastShadow = false
	part.Size = Vector3.new(size, size, size)
	part.Position = self:cellPosition(x, y, z)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	local height = self.grid.height
	local top = self.tops[Grid.key(x, 0, z)] or 0
	-- Colour depends only on the cell, so a rock looks the same whenever it appears.
	local shade = (math.noise(x * 0.37, y * 0.41, z * 0.29) + 1) / 2
	if y == top and y >= height * 0.7 then
		part.Material = Enum.Material.Snow
		part.Color = Color3.fromRGB(236, 240, 245)
	elseif y == top and y <= height * 0.18 then
		part.Material = Enum.Material.Grass
		part.Color = Color3.fromRGB(88, 140, 70)
	elseif (key * 2654435761) % 1000 < 60 then
		part.Material = Enum.Material.Marble
		part.Color = ORES[(key % #ORES) + 1]
	else
		part.Material = if shade > 0.5 then Enum.Material.Slate else Enum.Material.Rock
		part.Color = ROCK[math.clamp(1 + math.floor(y / height * #ROCK + shade), 1, #ROCK)]
	end
	-- A rounded pebble instead of a cube: a slightly squashed sphere with a
	-- random tilt, a little oversized so neighbours close the gaps.
	local pebble = Instance.new("SpecialMesh")
	pebble.MeshType = Enum.MeshType.Sphere
	local r1 = ((key * 7919) % 97) / 97
	local r2 = ((key * 104729) % 89) / 89
	local r3 = ((key * 1299709) % 83) / 83
	pebble.Scale = Vector3.new(1.18 + r1 * 0.22, 1.02 + r2 * 0.2, 1.18 + r3 * 0.22)
	pebble.Parent = part
	-- Only turn around the vertical axis so the collision boxes stay level to walk on.
	part.CFrame = CFrame.new(part.Position) * CFrame.Angles(0, r2 * math.pi, 0)
	part.Parent = self.folder
	self.parts[key] = part
	self.keys[part] = key
end

function Mountain.total(self: Mountain): number
	return self.grid.total
end

function Mountain.remaining(self: Mountain): number
	return self.grid:remaining()
end

function Mountain.keyForPart(self: Mountain, part: Instance): number?
	if part:IsA("BasePart") then
		return self.keys[part]
	end
	return nil
end

function Mountain.isExposed(self: Mountain, key: number): boolean
	return self.grid:isSolid(key) and self.grid.exposedIndex[key] ~= nil
end

-- After rocks are removed: drop their parts (a few fly off as rubble), draw the
-- rocks that were uncovered, and check whether the diamond is now in the open.
function Mountain._settle(self: Mountain, removed: { number }, centre: Vector3?)
	for index, key in removed do
		local part: BasePart? = self.parts[key]
		if part ~= nil then
			self.parts[key] = nil
			self.keys[part] = nil
			if index <= FLYING_LIMIT then
				local away = if centre then (part.Position - centre) else Vector3.new(0, 1, 0)
				if away.Magnitude < 0.1 then
					away = Vector3.new(self.random:NextNumber(-1, 1), 1, self.random:NextNumber(-1, 1))
				end
				part.Anchored = false
				part.CanCollide = false
				part.CanQuery = false
				part.AssemblyLinearVelocity = away.Unit * self.random:NextNumber(20, 40) + Vector3.new(0, self.random:NextNumber(15, 30), 0)
				part.AssemblyAngularVelocity = Vector3.new(self.random:NextNumber(-8, 8), self.random:NextNumber(-8, 8), self.random:NextNumber(-8, 8))
				Debris:AddItem(part, 1.4)
			else
				part:Destroy()
			end
		end
	end
	for _, key in self.grid:takeFresh() do
		self:_draw(key)
	end
	if not self.revealed and self.grid:isOpenAround(self.diamondKey) then
		self.revealed = true
		self.onDiamondCell()
	end
end

-- Blasts `count` rocks as one crater; returns the crater centre.
function Mountain.blast(self: Mountain, count: number): Vector3?
	if count <= 0 then
		return nil
	end
	local keys, centreKey = self.grid:blast(count)
	if centreKey == nil then
		return nil
	end
	local centre = self:keyPosition(centreKey)
	self:_settle(keys, centre)
	return centre
end

-- Digs up to `count` rocks by hand around an uncovered rock. Returns how many broke.
function Mountain.dig(self: Mountain, key: number, count: number): number
	if count <= 0 or not self:isExposed(key) then
		return 0
	end
	local keys = self.grid:blast(count, key)
	self:_settle(keys, self:keyPosition(key))
	return #keys
end

-- Digs out one uncovered rock by hand. Returns true when it broke.
function Mountain.mine(self: Mountain, key: number): boolean
	if not self:isExposed(key) then
		return false
	end
	self.grid:remove(key)
	self:_settle({ key }, nil)
	return true
end

-- Where a loose find at `position` comes to rest: on top of the highest rock
-- below it in its column, or on the ground.
function Mountain.restingHeight(self: Mountain, position: Vector3): number
	local size = self.blockSize
	local x = math.floor(position.X / size + 0.5)
	local z = math.floor(position.Z / size + 0.5)
	local y = math.floor(position.Y / size)
	local below = self.grid:supportBelow(x, y + 1, z)
	return (below + 1) * size
end

function Mountain.destroy(self: Mountain)
	self.folder:Destroy()
	table.clear(self.parts)
	table.clear(self.keys)
end

return Mountain
