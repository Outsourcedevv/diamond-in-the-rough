--!strict
-- The authoritative mountain: the rock grid plus a record of every change.
-- No rock parts exist on the server. Each client draws the rock itself
-- (MountainView) from a snapshot and compact change lists, so a huge gift
-- costs a few kilobytes of network traffic instead of replicating thousands
-- of parts, and the server never touches rendering.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("DiamondRush")
local Grid = require(Shared:WaitForChild("Grid"))
local Codec = require(Shared:WaitForChild("MountainCodec"))

local Mountain = {}
Mountain.__index = Mountain

local LAYER = Grid.LAYER
local rounds = 0

export type Mountain = typeof(setmetatable(
	{} :: {
		grid: Grid.Grid,
		blockSize: number,
		random: Random,
		diamondKey: number,
		revealed: boolean,
		onDiamondCell: (boolean) -> (),
		tops: { [number]: number },
		height: number,
		round: number,
		removedKeys: { number },
		addedKeys: { number },
	},
	Mountain
))

function Mountain.new(stones: number, blockSize: number, onDiamondCell: (boolean) -> (), checkpoint: (() -> ())?): Mountain
	local random = Random.new()
	local function rand(a: number?, b: number?): number
		if a ~= nil and b ~= nil then
			return random:NextInteger(a, b)
		end
		return random:NextNumber()
	end
	local grid = Grid.new(stones, random:NextNumber(0, 1000), rand, checkpoint)
	local diamondKey = grid:carveHiddenCell(checkpoint)
	grid:takeFresh()
	-- Original column summits: snow and grass only grow on the first surface.
	local tops: { [number]: number } = {}
	for index, key in grid.order do
		local column, y = key % LAYER, key // LAYER
		if (tops[column] or -1) < y then tops[column] = y end
		if checkpoint and index % 16384 == 0 then checkpoint() end
	end
	rounds += 1
	return setmetatable({
		grid = grid,
		blockSize = blockSize,
		random = random,
		diamondKey = diamondKey,
		revealed = false,
		onDiamondCell = onDiamondCell,
		tops = tops,
		height = grid.height,
		round = rounds,
		removedKeys = {},
		addedKeys = {},
	}, Mountain)
end

function Mountain.cellPosition(self: Mountain, x: number, y: number, z: number): Vector3
	local size = self.blockSize
	return Vector3.new(x * size, y * size + size / 2, z * size)
end

function Mountain.keyPosition(self: Mountain, key: number): Vector3
	local x, y, z = Grid.coords(key)
	return self:cellPosition(x, y, z)
end

-- The cell containing a world position, or nil outside the grid.
function Mountain.keyAt(self: Mountain, position: Vector3): number?
	local size = self.blockSize
	local x = math.floor(position.X / size + 0.5)
	local z = math.floor(position.Z / size + 0.5)
	local y = math.floor(position.Y / size)
	if y < 0 or math.abs(x) > 124 or math.abs(z) > 124 then return nil end
	return Grid.key(x, y, z)
end

-- Ordered messages describing the whole mountain for a client.
function Mountain.snapshot(self: Mountain, animated: boolean?, start: number?): { { any } }
	local messages: { { any } } = {
		{ "begin", {
			round = self.round,
			blockSize = self.blockSize,
			diamondKey = self.diamondKey,
			height = self.height,
			animated = animated == true,
			start = start or 0,
		} },
	}
	local keys = table.create(self.grid:remaining())
	self.grid:eachSolid(function(key) table.insert(keys, key) end)
	for _, chunk in Codec.encode(keys) do table.insert(messages, { "cells", chunk } :: { any }) end
	for _, chunk in Codec.encodePairs(self.tops) do table.insert(messages, { "tops", chunk } :: { any }) end
	table.insert(messages, { "end", true } :: { any })
	return messages
end

-- The net change since the last flush. When work overlaps (a gift blasting
-- rock a rebuild has only just added, or a player digging during a gift), a
-- cell can change both ways in one batch. Clients apply removals before
-- additions, so each cell is sent once, by what it is now: otherwise a rock
-- added and blasted again would reach them as removed-then-added and stay on
-- screen after the server destroyed it.
local function netChanges(grid: Grid.Grid, removedKeys: { number }, addedKeys: { number }): ({ number }, { number })
	-- One-way batches need no filtering: a cell is only removed while solid
	-- and only added while empty, so without the other list nothing repeats.
	if #removedKeys == 0 or #addedKeys == 0 then return removedKeys, addedKeys end
	local pages = grid.solidPages
	local seen, seenPages = Grid.cellMap()
	local removed, added = {}, {}
	for _, key in removedKeys do
		if not Grid.hasBit(seenPages, key) and not Grid.hasBit(pages, key) then
			seen[key] = true
			table.insert(removed, key)
		end
	end
	for _, key in addedKeys do
		if not Grid.hasBit(seenPages, key) and Grid.hasBit(pages, key) then
			seen[key] = true
			table.insert(added, key)
		end
	end
	return removed, added
end

-- Change lists since the last flush, at most one encoded chunk each, or an
-- empty list when nothing changed.
function Mountain.flush(self: Mountain, effect: string?, at: Vector3?): { any }
	local diffs: { any } = {}
	local removed, added = netChanges(self.grid, self.removedKeys, self.addedKeys)
	self.removedKeys, self.addedKeys = {}, {}
	if #removed > 0 then
		for _, chunk in Codec.encode(removed) do
			table.insert(diffs, { round = self.round, removed = { chunk }, effect = effect, at = at })
		end
	end
	if #added > 0 then
		for _, chunk in Codec.encode(added) do
			table.insert(diffs, { round = self.round, added = { chunk }, effect = effect, at = at })
		end
	end
	return diffs
end

function Mountain.hasChanges(self: Mountain): boolean
	return #self.removedKeys > 0 or #self.addedKeys > 0
end

-- Exposure can change in both directions: rebuilding can bury a previously
-- uncovered diamond, and digging must be able to announce it again afterward.
function Mountain._syncDiamond(self: Mountain)
	local open = self.grid:isOpenAround(self.diamondKey)
	if open ~= self.revealed then
		self.revealed = open
		self.onDiamondCell(open)
	end
end

-- Refills dug cells from the diamond outward, then grows new rock up to
-- `capacity`. Returns how many rocks were added and where the refill started.
-- Long work checks the diamond as it goes, so it shows the moment a gift
-- uncovers it (and hides again when a rebuild covers it), not only at the end.
function Mountain._watching(self: Mountain, checkpoint: (() -> ())?): () -> ()
	return function()
		self:_syncDiamond()
		if checkpoint then checkpoint() end
	end
end

function Mountain.restore(self: Mountain, count: number, capacity: number?, checkpoint: (() -> ())?): (number, Vector3?)
	checkpoint = self:_watching(checkpoint)
	local dx, dy, dz = Grid.coords(self.diamondKey)
	-- Look the list up on every call: a flush during the work replaces it.
	local function record(key: number) table.insert(self.addedKeys, key) end
	local restored = self.grid:restore(count, { x = dx, y = dy, z = dz }, checkpoint, record)
	local total = #restored
	local first = restored[1]
	if capacity and total < count then
		local grown = self.grid:grow(count - total, capacity, checkpoint, record)
		for index, key in grown do
			local column, y = key % LAYER, key // LAYER
			if (self.tops[column] or -1) < y then self.tops[column] = y end
			if checkpoint and index % 1024 == 0 then checkpoint() end
		end
		total += #grown
		first = first or grown[1]
	end
	self.grid:takeFresh()
	self:_syncDiamond()
	return total, if first then self:keyPosition(first) else nil
end

function Mountain.total(self: Mountain): number
	return self.grid.total
end

function Mountain.remaining(self: Mountain): number
	return self.grid:remaining()
end

function Mountain.isExposed(self: Mountain, key: number): boolean
	return self.grid:isSolid(key) and self.grid.exposedIndex[key] ~= nil
end

-- Blasts `count` rocks as one crater; returns the crater centre.
function Mountain.blast(self: Mountain, count: number, checkpoint: (() -> ())?, centreKey: number?): Vector3?
	if count <= 0 then
		return nil
	end
	-- Look the list up on every call: a flush during the work replaces it.
	local _, actualCentre = self.grid:blast(count, centreKey, self:_watching(checkpoint), function(key) table.insert(self.removedKeys, key) end)
	self.grid:takeFresh()
	self:_syncDiamond()
	return if actualCentre then self:keyPosition(actualCentre) else nil
end

-- Digs up to `count` rocks by hand around an uncovered rock. Returns how many broke.
function Mountain.dig(self: Mountain, key: number, count: number): number
	if count <= 0 or not self:isExposed(key) then
		return 0
	end
	local keys = self.grid:blast(count, key, nil, function(cell) table.insert(self.removedKeys, cell) end)
	self.grid:takeFresh()
	self:_syncDiamond()
	return #keys
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

-- True when rock stands between two points. Rock is drawn with sloped faces
-- that do not fill their whole cell, so one grazed cell is allowed.
function Mountain.lineBlocked(self: Mountain, from: Vector3, to: Vector3): boolean
	local delta = to - from
	local steps = math.max(1, math.ceil(delta.Magnitude / (self.blockSize * 0.25)))
	local seen: { [number]: boolean } = {}
	local blocked = 0
	for i = 0, steps do
		local key = self:keyAt(from + delta * (i / steps))
		if key and not seen[key] and key ~= self.diamondKey and self.grid:isSolid(key) then
			seen[key] = true
			blocked += 1
			if blocked > 1 then return true end
		end
	end
	return false
end

-- If rock fills the space between `bottom` and `top` at or around `position`
-- (a character buried by a rebuild), the height of the rock surface above it.
local AROUND = { { 0, 0 }, { 0.7, 0 }, { -0.7, 0 }, { 0, 0.7 }, { 0, -0.7 } }
local CENTRE = { { 0, 0 } }
function Mountain.coveredTop(self: Mountain, position: Vector3, bottom: number, top: number, centreOnly: boolean?): number?
	local size = self.blockSize
	local grid = self.grid
	local best: number? = nil
	-- `centreOnly` checks the column the body is in, not the rock beside it.
	for _, offset in (if centreOnly then CENTRE else AROUND) do
		local x = math.floor((position.X + offset[1]) / size + 0.5)
		local z = math.floor((position.Z + offset[2]) / size + 0.5)
		if math.abs(x) <= 124 and math.abs(z) <= 124 then
			for y = math.max(0, math.floor(bottom / size)), math.floor(top / size) do
				if grid:isSolid(Grid.key(x, y, z)) then
					local surface = y
					while grid:isSolid(Grid.key(x, surface + 1, z)) or grid.sealed[Grid.key(x, surface + 1, z)] do
						surface += 1
					end
					local lift = (surface + 1) * size
					if best == nil or lift > best then best = lift end
					break
				end
			end
		end
	end
	return best
end

-- The top of the highest uncovered rock.
function Mountain.summit(self: Mountain): Vector3?
	local best: number? = nil
	for _, key in self.grid.exposedList do
		if best == nil or key // LAYER > (best :: number) // LAYER then best = key end
	end
	if best == nil then return nil end
	return self:keyPosition(best) + Vector3.new(0, self.blockSize / 2, 0)
end

function Mountain.destroy(_self: Mountain)
	-- Nothing to clean up: the grid is plain data and clients drop their parts
	-- when the next snapshot arrives.
end

return Mountain
