--!strict
-- Turns the block grid into Roblox parts and plays the blast effects.
local Debris = game:GetService("Debris")

local Grid = require(script.Parent.Grid)

local Mountain = {}
Mountain.__index = Mountain

-- Rock tones from the foot to the summit, plus a few colourful ore flecks.
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
local FLYING_LIMIT = 36

export type Mountain = typeof(setmetatable(
	{} :: {
		grid: Grid.Grid,
		folder: Folder,
		parts: { [number]: BasePart },
		keys: { [BasePart]: number },
		blockSize: number,
		random: Random,
		diamondKey: number,
		onDiamondCell: () -> (),
	},
	Mountain
))

function Mountain.new(parent: Instance, radius: number, height: number, blockSize: number, onDiamondCell: () -> ()): Mountain
	local random = Random.new()
	local function rand(a: number?, b: number?): number
		if a ~= nil and b ~= nil then
			return random:NextInteger(a, b)
		end
		return random:NextNumber()
	end
	local grid = Grid.new(radius, height, random:NextNumber(0, 1000), rand)
	local folder = Instance.new("Folder")
	folder.Name = "Mountain"
	local self = setmetatable({
		grid = grid,
		folder = folder,
		parts = {},
		keys = {},
		blockSize = blockSize,
		random = random,
		diamondKey = grid:pickHiddenCell(),
		onDiamondCell = onDiamondCell,
	}, Mountain)
	local tops: { [number]: number } = {}
	for _, key in grid.order do
		local x, y, z = Grid.coords(key)
		local column = Grid.key(x, 0, z)
		tops[column] = math.max(tops[column] or 0, y)
	end
	for _, key in grid.order do
		local x, y, z = Grid.coords(key)
		local part = Instance.new("Part")
		part.Name = "Stone"
		part.Anchored = true
		part.Size = Vector3.new(blockSize, blockSize, blockSize)
		part.Position = self:cellPosition(x, y, z)
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		local top = tops[Grid.key(x, 0, z)]
		if y == top and y >= height * 0.72 then
			part.Material = Enum.Material.Snow
			part.Color = Color3.fromRGB(236, 240, 245)
		elseif y == top and y <= 2 then
			part.Material = Enum.Material.Grass
			part.Color = Color3.fromRGB(88, 140, 70)
		elseif random:NextNumber() < 0.07 then
			part.Material = Enum.Material.Marble
			part.Color = ORES[random:NextInteger(1, #ORES)]
		else
			part.Material = if random:NextNumber() < 0.5 then Enum.Material.Slate else Enum.Material.Rock
			local tone = ROCK[math.clamp(1 + math.floor(y / height * #ROCK + random:NextNumber() * 1.2), 1, #ROCK)]
			part.Color = tone
		end
		part.Parent = folder
		self.parts[key] = part
		self.keys[part] = key
	end
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

function Mountain.total(self: Mountain): number
	return self.grid.total
end

function Mountain.removedCount(self: Mountain): number
	return self.grid.removed
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

-- Removes blocks from the scene; the first few fly off as rubble.
function Mountain._clear(self: Mountain, keys: { number }, centre: Vector3?)
	for index, key in keys do
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
				part.Size *= 0.7
				part.AssemblyLinearVelocity = away.Unit * self.random:NextNumber(30, 60) + Vector3.new(0, self.random:NextNumber(25, 45), 0)
				part.AssemblyAngularVelocity = Vector3.new(self.random:NextNumber(-8, 8), self.random:NextNumber(-8, 8), self.random:NextNumber(-8, 8))
				Debris:AddItem(part, 1.6)
			else
				part:Destroy()
			end
		end
		if key == self.diamondKey then
			self.onDiamondCell()
		end
	end
end

-- Blasts `count` blocks as one crater; returns the crater centre.
function Mountain.blast(self: Mountain, count: number): Vector3?
	if count <= 0 then
		return nil
	end
	local keys, centreKey = self.grid:blast(count)
	if centreKey == nil then
		return nil
	end
	local centre = self:keyPosition(centreKey)
	self:_clear(keys, centre)
	return centre
end

-- Mines one exposed block (pickaxe). Returns true when it broke.
function Mountain.mine(self: Mountain, key: number): boolean
	if not self:isExposed(key) then
		return false
	end
	self.grid:remove(key)
	self:_clear({ key }, nil)
	return true
end

-- Where a loose find at `position` comes to rest: on top of the highest block
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
