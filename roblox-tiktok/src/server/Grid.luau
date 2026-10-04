--!strict
-- Pure block-grid logic for the mountain, with no Roblox instances, so it can be
-- tested outside Roblox. Cells are keyed by one integer; a cell is "exposed"
-- when at least one of its six neighbours is open air, and only exposed cells
-- can be blasted away.
local Grid = {}
Grid.__index = Grid

local OFFSET = 128
local SPAN = 256
local NEIGHBOURS = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }

export type Grid = typeof(setmetatable(
	{} :: {
		radius: number,
		height: number,
		solid: { [number]: boolean },
		order: { number },
		total: number,
		removed: number,
		exposedList: { number },
		exposedIndex: { [number]: number },
		rand: (number?, number?) -> number,
		fresh: { number },
		sealed: { [number]: boolean },
	},
	Grid
))

function Grid.key(x: number, y: number, z: number): number
	return (x + OFFSET) + (z + OFFSET) * SPAN + y * SPAN * SPAN
end

function Grid.coords(key: number): (number, number, number)
	local y = key // (SPAN * SPAN)
	local rest = key % (SPAN * SPAN)
	return (rest % SPAN) - OFFSET, y, (rest // SPAN) - OFFSET
end

-- Builds a mountain of exactly `target` cells (one cell = one stone).
-- rand(): a number in [0, 1); rand(a, b): a whole number from a to b.
function Grid.new(target: number, seed: number, rand: (number?, number?) -> number): Grid
	target = math.max(1, math.floor(target))
	-- A cone of volume ~pi r^2 h / 3 with h = 0.9 r, a little oversized so it
	-- can be trimmed down to the exact number of cells.
	local radius = math.clamp(math.ceil((target * 1.06 / 0.94) ^ (1 / 3)), 3, OFFSET - 4)
	local height = math.max(2, math.floor(radius * 0.9 + 0.5))
	local self = setmetatable({
		radius = radius,
		height = height,
		solid = {},
		order = {},
		total = 0,
		removed = 0,
		exposedList = {},
		exposedIndex = {},
		rand = rand,
		fresh = {},
		sealed = {},
	}, Grid)
	local scale = 15 / radius
	for z = -radius, radius do
		for x = -radius, radius do
			local distance = math.sqrt(x * x + z * z) / radius
			if distance <= 1 then
				local bumps = math.noise(x * 0.16 * scale, z * 0.16 * scale, seed) * 2.6 + math.noise(x * 0.4 * scale, z * 0.4 * scale, seed + 7.3) * 0.9
				local top = height * (1 - distance) ^ 0.85 + bumps * (1 - distance * 0.6) / math.sqrt(scale)
				local columnHeight = math.clamp(math.floor(top + 0.5), if distance < 0.85 then 1 else 0, height * 2)
				for y = 0, columnHeight - 1 do
					local key = Grid.key(x, y, z)
					self.solid[key] = true
					table.insert(self.order, key)
				end
			end
		end
	end
	-- Shave the highest rocks first until exactly `target` cells remain, so the
	-- surface stays smooth. Column tops are bucketed by height.
	local count = #self.order
	if count > target then
		local buckets: { [number]: { number } } = {}
		local highest = 0
		for _, key in self.order do
			local x, y, z = Grid.coords(key)
			if not self.solid[Grid.key(x, y + 1, z)] then
				buckets[y] = buckets[y] or {}
				table.insert(buckets[y], key)
				highest = math.max(highest, y)
			end
		end
		local level = highest
		while count > target and level >= 0 do
			local bucket = buckets[level]
			if bucket == nil or #bucket == 0 then
				level -= 1
				continue
			end
			local index = rand(1, #bucket)
			local key = bucket[index]
			bucket[index] = bucket[#bucket]
			bucket[#bucket] = nil
			self.solid[key] = nil
			count -= 1
			local x, y, z = Grid.coords(key)
			if y > 0 then
				buckets[y - 1] = buckets[y - 1] or {}
				table.insert(buckets[y - 1], Grid.key(x, y - 1, z))
			end
		end
		local kept: { number } = {}
		for _, key in self.order do
			if self.solid[key] then
				table.insert(kept, key)
			end
		end
		self.order = kept
	end
	self.total = #self.order
	for _, key in self.order do
		if self:isExposed(key) then
			self:_expose(key)
		end
	end
	table.clear(self.fresh)
	return self
end

function Grid.isSolid(self: Grid, key: number): boolean
	return self.solid[key] == true
end

function Grid.remaining(self: Grid): number
	return self.total - self.removed
end

function Grid.isExposed(self: Grid, key: number): boolean
	local x, y, z = Grid.coords(key)
	for _, step in NEIGHBOURS do
		local ny = y + step[2]
		-- The ground under the mountain counts as solid.
		local neighbour = Grid.key(x + step[1], ny, z + step[3])
		if ny >= 0 and not self.solid[neighbour] and not self.sealed[neighbour] then
			return true
		end
	end
	return false
end

function Grid._expose(self: Grid, key: number)
	if self.exposedIndex[key] == nil then
		table.insert(self.exposedList, key)
		self.exposedIndex[key] = #self.exposedList
		table.insert(self.fresh, key)
	end
end

function Grid._unexpose(self: Grid, key: number)
	local index = self.exposedIndex[key]
	if index == nil then
		return
	end
	local last = self.exposedList[#self.exposedList]
	self.exposedList[index] = last
	self.exposedIndex[last] = index
	self.exposedList[#self.exposedList] = nil
	self.exposedIndex[key] = nil
end

function Grid.exposedCount(self: Grid): number
	return #self.exposedList
end

-- Removes one solid cell; its solid neighbours become exposed.
function Grid.remove(self: Grid, key: number): boolean
	if not self.solid[key] then
		return false
	end
	self.solid[key] = nil
	self.removed += 1
	self:_unexpose(key)
	local x, y, z = Grid.coords(key)
	for _, step in NEIGHBOURS do
		local ny = y + step[2]
		if ny >= 0 then
			local neighbour = Grid.key(x + step[1], ny, z + step[3])
			if self.solid[neighbour] then
				self:_expose(neighbour)
			end
		end
	end
	return true
end

function Grid.randomExposed(self: Grid): number?
	local count = #self.exposedList
	if count == 0 then
		return nil
	end
	return self.exposedList[self.rand(1, count)]
end

-- A minimal binary heap of {distance, key} pairs, nearest first.
local function push(heap: { { number } }, item: { number })
	table.insert(heap, item)
	local i = #heap
	while i > 1 do
		local parent = i // 2
		if heap[parent][1] <= heap[i][1] then
			break
		end
		heap[parent], heap[i] = heap[i], heap[parent]
		i = parent
	end
end

local function pop(heap: { { number } }): { number }?
	local count = #heap
	if count == 0 then
		return nil
	end
	local top = heap[1]
	heap[1] = heap[count]
	heap[count] = nil
	count -= 1
	local i = 1
	while true do
		local left, right, smallest = i * 2, i * 2 + 1, i
		if left <= count and heap[left][1] < heap[smallest][1] then
			smallest = left
		end
		if right <= count and heap[right][1] < heap[smallest][1] then
			smallest = right
		end
		if smallest == i then
			break
		end
		heap[smallest], heap[i] = heap[i], heap[smallest]
		i = smallest
	end
	return top
end

-- Blasts up to `count` cells as one crater around a random exposed cell (or
-- `centre`): the nearest cells to the centre go first, and the crater only
-- grows through cells it has opened up. Returns the removed keys and the centre.
function Grid.blast(self: Grid, count: number, centre: number?): ({ number }, number?)
	local removed: { number } = {}
	local start = if centre ~= nil and self.solid[centre] and self.exposedIndex[centre] then centre else self:randomExposed()
	if start == nil then
		return removed, nil
	end
	local cx, cy, cz = Grid.coords(start)
	local heap: { { number } } = {}
	local queued: { [number]: boolean } = {}
	local function enqueue(key: number)
		if queued[key] or not self.solid[key] then
			return
		end
		queued[key] = true
		local x, y, z = Grid.coords(key)
		-- Craters dig a little more readily downwards and outwards than up.
		local dy = (y - cy) * (if y > cy then 1.15 else 0.9)
		push(heap, { (x - cx) ^ 2 + dy * dy + (z - cz) ^ 2 + self.rand() * 0.6, key })
	end
	enqueue(start)
	while #removed < count do
		local item = pop(heap)
		if item == nil then
			-- The crater ran out of reachable rock: carry on from a new spot.
			local nextStart = self:randomExposed()
			if nextStart == nil then
				break
			end
			cx, cy, cz = Grid.coords(nextStart)
			enqueue(nextStart)
			continue
		end
		local key = item[2]
		if self:remove(key) then
			table.insert(removed, key)
			local x, y, z = Grid.coords(key)
			for _, step in NEIGHBOURS do
				local ny = y + step[2]
				if ny >= 0 then
					enqueue(Grid.key(x + step[1], ny, z + step[3]))
				end
			end
		end
	end
	return removed, start
end

-- Newly exposed cells since the last call (for drawing them).
function Grid.takeFresh(self: Grid): { number }
	local fresh = self.fresh
	self.fresh = {}
	return fresh
end

-- True once any of the cell's six neighbours is open air.
function Grid.isOpenAround(self: Grid, key: number): boolean
	return self:isExposed(key)
end

-- Takes a buried cell out of the rock for the diamond (all six neighbours
-- solid, in the lower two thirds so it is not found straight away). The
-- diamond is not stone: it does not count towards the total.
function Grid.carveHiddenCell(self: Grid): number
	local key = self:pickHiddenCell()
	if self.solid[key] then
		-- Sealed: not stone, but it still counts as rock around it until the
		-- digging reaches it.
		self.solid[key] = nil
		self.sealed[key] = true
		self:_unexpose(key)
		self.total -= 1
		local index = table.find(self.order, key)
		if index then
			table.remove(self.order, index)
		end
	end
	return key
end

function Grid.pickHiddenCell(self: Grid): number
	local buried: { number } = {}
	for _, key in self.order do
		local _, y, _ = Grid.coords(key)
		if self.solid[key] and not self:isExposed(key) and y < self.height * 2 / 3 then
			table.insert(buried, key)
		end
	end
	if #buried == 0 then
		for _, key in self.order do
			if self.solid[key] then
				table.insert(buried, key)
			end
		end
	end
	return buried[self.rand(1, #buried)]
end

-- The height of the highest solid cell in column (x, z) below layer y, or -1.
function Grid.supportBelow(self: Grid, x: number, y: number, z: number): number
	for level = y - 1, 0, -1 do
		if self.solid[Grid.key(x, level, z)] then
			return level
		end
	end
	return -1
end

return Grid
