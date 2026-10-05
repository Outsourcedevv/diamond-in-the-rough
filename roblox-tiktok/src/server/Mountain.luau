--!strict
-- Draws the exposed stones plus one solid layer behind them. The shell advances
-- as digging opens the mountain, without instantiating all 250,000 cells.
local Debris = game:GetService("Debris")

local Grid = require(script.Parent.Grid)
local RockStyle = require(script.Parent.RockStyle)

local Mountain = {}
Mountain.__index = Mountain

local ROCK = {
	Color3.fromRGB(92, 88, 84),
	Color3.fromRGB(110, 106, 100),
	Color3.fromRGB(128, 124, 116),
	Color3.fromRGB(146, 140, 130),
}
local FLYING_LIMIT = 8

-- Fixed-size pages keep numeric part lookups from resizing a large sparse map
-- as gifts move the visible rock surface through tens of thousands of cells.
local function newPartMap(): { [number]: BasePart }
	local pages: { [number]: { BasePart } } = {}
	return setmetatable({}, {
		__index = function(_self, key: number)
			local page = pages[key // 256]
			return if page then page[key % 256 + 1] else nil
		end,
		__newindex = function(_self, key: number, value: BasePart?)
			local index = key // 256
			local page = pages[index]
			if page == nil then
				if value == nil then return end
				page = table.create(256)
				pages[index] = page
			end
			page[key % 256 + 1] = value
		end,
		__iter = function()
			local pageIndex: number? = nil
			local page: { BasePart }? = nil
			local slot = 257
			return function(): (number?, BasePart?)
				while true do
					if slot > 256 then
						pageIndex, page = next(pages, pageIndex)
						if pageIndex == nil then return nil end
						slot = 1
					end
					local value = (page :: { BasePart })[slot]
					local key = (pageIndex :: number) * 256 + slot - 1
					slot += 1
					if value then return key, value end
				end
			end
		end,
	}) :: any
end

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

function Mountain.new(parent: Instance, stones: number, blockSize: number, onDiamondCell: () -> (), building: boolean?): Mountain
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
	folder:SetAttribute("Building", building == true)
	local self = setmetatable({
		grid = grid,
		folder = folder,
		parts = newPartMap(),
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
	for index, key in grid.exposedList do
		self:_drawShell(key)
		if building and index % 300 == 0 then task.wait() end
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
	if not self.grid:isSolid(key) then
		return
	end
	local backing = self.grid.exposedIndex[key] == nil
	if existing ~= nil then
		if backing == (existing:GetAttribute("BackingRock") == true) then return end
		-- The inner stone becomes a faceted, diggable surface stone when uncovered.
		self.keys[existing] = nil
		existing:Destroy()
	end
	local x, y, z = Grid.coords(key)
	local size = self.blockSize
	local style = RockStyle.forCell(key)
	local part = Instance.new(if backing then "Part" else style.shape) :: BasePart
	part.Name = "Stone"
	part.Transparency = if self.folder:GetAttribute("Building") then 1 else 0
	part.Anchored = true
	part.CastShadow = false
	part.Size = Vector3.new(style.x, style.y, style.z) * size
	part.CFrame = CFrame.new(self:cellPosition(x, y, z) + Vector3.new(style.ox, style.oy, style.oz) * size)
		* CFrame.Angles(style.pitch, style.yaw, style.roll)
	if backing then
		-- Flush blocks close sightlines between the larger irregular surface rocks.
		part.Size = Vector3.new(1.02, 1.02, 1.02) * size
		part.CFrame = CFrame.new(self:cellPosition(x, y, z))
		part:SetAttribute("BackingRock", true)
	end
	part.CanCollide = not backing
	part.CanQuery = not backing
	part.CanTouch = false
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
	elseif style.quartz then
		part.Material = Enum.Material.Rock
		part.Color = Color3.fromRGB(166, 161, 150)
	else
		part.Material = if shade > 0.5 then Enum.Material.Slate else Enum.Material.Rock
		part.Color = ROCK[math.clamp(1 + math.floor(y / height * #ROCK + shade), 1, #ROCK)]
	end
	part.Color = Color3.new(math.min(1, part.Color.R * style.shade), math.min(1, part.Color.G * style.shade), math.min(1, part.Color.B * style.shade))
	-- Native stone facets need one instance each, without an extra mesh or light.
	-- Colours stay close together: the one small diamond must be found by eye.
	part.Parent = self.folder
	self.parts[key] = part
	self.keys[part] = key
end

function Mountain._drawShell(self: Mountain, key: number)
	if not self.grid:isSolid(key) then return end
	self:_draw(key)
	for _, neighbour in self.grid:solidNeighbours(key) do
		self:_draw(neighbour)
	end
end

-- Reconcile only the changed cells and the two surrounding rock layers.
function Mountain._restoreBatch(self: Mountain, count: number, near: Vector3?, capacity: number?, checkpoint: (() -> ())?): (number, { any })
	local focus = if near then { x = near.X / self.blockSize, z = near.Z / self.blockSize, radius = 4 / self.blockSize } else nil
	local restored = self.grid:restore(count, focus, checkpoint)
	if capacity and #restored < count then
		local grown = self.grid:grow(count - #restored, capacity, checkpoint)
		for index, key in grown do
			if checkpoint and index % 256 == 0 then checkpoint() end
			table.insert(restored, key)
			local x, y, z = Grid.coords(key)
			local column = Grid.key(x, 0, z)
			self.tops[column] = math.max(self.tops[column] or 0, y)
		end
	end
	-- Visit each changed cell's neighbourhood once, rather than expanding
	-- all six neighbours again for every interior rock in a large refill.
	local firstRing = {}
	for index, key in restored do
		firstRing[key] = true
		for _, neighbour in self.grid:solidNeighbours(key) do firstRing[neighbour] = true end
		if checkpoint and index % 128 == 0 then checkpoint() end
	end
	local affected = {}
	local expanded = 0
	for key in firstRing do
		affected[key] = true
		for _, neighbour in self.grid:solidNeighbours(key) do affected[neighbour] = true end
		expanded += 1
		if checkpoint and expanded % 128 == 0 then checkpoint() end
	end
	local processed = 0
	for key in affected do
		processed += 1
		if checkpoint and processed % 64 == 0 then checkpoint() end
		local needed = self.grid.exposedIndex[key] ~= nil
		if not needed then
			for _, neighbour in self.grid:solidNeighbours(key) do
				if self.grid.exposedIndex[neighbour] then needed = true; break end
			end
		end
		if needed then self:_draw(key)
		elseif self.parts[key] then
			local part = self.parts[key]
			self.keys[part] = nil
			self.parts[key] = nil
			part:Destroy()
		end
	end
	self.grid:takeFresh()
	local samples = {}
	for index, key in restored do
		if checkpoint and index % 128 == 0 then checkpoint() end
		local part = self.parts[key]
		if part and not part:GetAttribute("BackingRock") then
			table.insert(samples, { frame = part.CFrame, size = part.Size, colour = part.Color, part = part })
			if #samples >= 24 then break end
		end
	end
	return #restored, samples
end

-- Commit visible geometry before starting the next batch. Previously the entire
-- gift (up to 1.5 million cells) was computed before the first rock appeared.
function Mountain.restore(self: Mountain, count: number, near: Vector3?, capacity: number?, checkpoint: (() -> ())?): (number, { any })
	local total = 0
	local samples = {}
	while total < count do
		local batch = math.min(2048, count - total)
		local placed, stones = self:_restoreBatch(batch, if total == 0 then near else nil, capacity, checkpoint)
		total += placed
		for _, stone in stones do
			if #samples < 24 then table.insert(samples, stone) end
		end
		if checkpoint then checkpoint() end
		if placed < batch then break end
	end
	return total, samples
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
function Mountain._settle(self: Mountain, removed: { number }, centre: Vector3?, checkpoint: (() -> ())?)
	for index, key in removed do
		if checkpoint and index % 128 == 0 then checkpoint() end
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
	-- Reconcile each surviving surface/backing cell once instead of redrawing
	-- the same neighbour up to six times after a large crater.
	local needed = {}
	for index, key in self.grid:takeFresh() do
		if self.grid:isSolid(key) and self.grid.exposedIndex[key] then
			needed[key] = true
			for _, neighbour in self.grid:solidNeighbours(key) do needed[neighbour] = true end
		end
		if checkpoint and index % 128 == 0 then checkpoint() end
	end
	local drawn = 0
	for key in needed do
		self:_draw(key)
		drawn += 1
		if checkpoint and drawn % 32 == 0 then checkpoint() end
	end
	if not self.revealed and self.grid:isOpenAround(self.diamondKey) then
		self.revealed = true
		self.onDiamondCell()
	end
end

-- Blasts `count` rocks as one crater; returns the crater centre.
function Mountain.blast(self: Mountain, count: number, checkpoint: (() -> ())?, centreKey: number?): Vector3?
	if count <= 0 then
		return nil
	end
	local keys, actualCentre = self.grid:blast(count, centreKey, checkpoint)
	if actualCentre == nil then
		return nil
	end
	local centre = self:keyPosition(actualCentre)
	self:_settle(keys, centre, checkpoint)
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
	self.parts = {}
	table.clear(self.keys)
end

return Mountain
