--!strict
--!native
-- Pure block-grid logic for the mountain, with no Roblox instances, so it can be
-- tested outside Roblox. The server owns the real grid; each client keeps a
-- replica to draw the rock. Cells are keyed by one integer; a cell is "exposed"
-- when at least one of its six neighbours is open air, and only exposed cells
-- can be blasted away.
local Grid = {}
Grid.__index = Grid

local OFFSET = 128
local SPAN = 256
local LAYER = SPAN * SPAN
local NEIGHBOURS = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }
-- The same six neighbours as key offsets. x and z never reach the edge of the
-- key space, so only a step below layer 0 can leave it.
local STEPS = { 1, -1, LAYER, -LAYER, SPAN, -SPAN }
Grid.SPAN = SPAN
Grid.LAYER = LAYER
Grid.STEPS = STEPS

-- Reads one bit straight from the pages behind a cell map, skipping the
-- metatable call that the dictionary interface needs.
local function hasBit(pages: { [number]: buffer }, key: number): boolean
	local page = pages[key // 4096]
	return page ~= nil and bit32.btest(buffer.readu8(page, (key % 4096) // 8), bit32.lshift(1, key % 8))
end
Grid.hasBit = hasBit

-- Bit-packed pages avoid resizing a million-entry hash table during a gift.
-- The dictionary interface keeps all callers using the same cell keys.
local function newCellMap(): ({ [number]: boolean }, { [number]: buffer })
	local pages: { [number]: buffer } = {}
	local masks = { 1, 2, 4, 8, 16, 32, 64, 128 }
	return setmetatable({}, {
		__index = function(_self, key: number)
			local page = pages[key // 4096]
			if page == nil then return nil end
			return if bit32.band(buffer.readu8(page, (key % 4096) // 8), masks[key % 8 + 1]) ~= 0 then true else nil
		end,
		__newindex = function(_self, key: number, value: boolean?)
			local index = key // 4096
			local page = pages[index]
			if page == nil then
				if not value then return end
				page = buffer.create(512)
				pages[index] = page
			end
			local offset, mask = (key % 4096) // 8, masks[key % 8 + 1]
			local byte = buffer.readu8(page, offset)
			buffer.writeu8(page, offset, if value then bit32.bor(byte, mask) else bit32.band(byte, bit32.bnot(mask)))
		end,
		__iter = function()
			local pageIndex: number? = nil
			local page: buffer? = nil
			local slot = 4096
			return function(): (number?, boolean?)
				while true do
					if slot >= 4096 then
						pageIndex, page = next(pages, pageIndex)
						if pageIndex == nil then return nil end
						slot = 0
					end
					local bit = slot
					slot += 1
					if bit32.band(buffer.readu8(page :: buffer, bit // 8), masks[bit % 8 + 1]) ~= 0 then
						return (pageIndex :: number) * 4096 + bit, true
					end
				end
			end
		end,
	}) :: any, pages
end

-- A bit-packed set of cell keys, plus its pages for hasBit.
Grid.cellMap = newCellMap

-- Surface indices change continuously as the frontier moves. Paging these
-- numbers also avoids hash-table expansion pauses around large surface sizes.
local function newIndexMap(): { [number]: number }
	local pages: { [number]: buffer } = {}
	return setmetatable({}, {
		__index = function(_self, key: number)
			local page = pages[key // 256]
			if page == nil then return nil end
			local value = buffer.readu32(page, key % 256 * 4)
			return if value ~= 0 then value else nil
		end,
		__newindex = function(_self, key: number, value: number?)
			local index = key // 256
			local page = pages[index]
			if page == nil then
				if value == nil then return end
				page = buffer.create(1024)
				pages[index] = page
			end
			buffer.writeu32(page, key % 256 * 4, value or 0)
		end,
	}) :: any
end

export type Grid = typeof(setmetatable(
	{} :: {
		radius: number,
		height: number,
		solid: { [number]: boolean },
		solidPages: { [number]: buffer },
		order: { number },
		total: number,
		removed: number,
		removedOrder: { number },
		exposedList: { number },
		exposedIndex: { [number]: number },
		rand: (number?, number?) -> number,
		fresh: { number },
		sealed: { [number]: boolean },
		growthHeap: { number }?,
		growthScores: { number }?,
		growthQueued: { [number]: boolean }?,
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

local function empty(rand: (number?, number?) -> number): Grid
	local solid, pages = newCellMap()
	return setmetatable({
		radius = 0,
		height = 0,
		solid = solid,
		solidPages = pages,
		order = {},
		total = 0,
		removed = 0,
		removedOrder = {},
		exposedList = {},
		exposedIndex = newIndexMap(),
		rand = rand,
		fresh = {},
		sealed = {},
		growthHeap = nil,
		growthScores = nil,
		growthQueued = nil,
	}, Grid)
end

-- An empty replica for a client. Clients only flip cells and ask whether they
-- are exposed; the server's bookkeeping lists stay empty.
function Grid.blank(): Grid
	return empty(function(a: number?, _b: number?): number return a or 0 end)
end

-- Builds a mountain of exactly `target` cells (one cell = one stone).
-- rand(): a number in [0, 1); rand(a, b): a whole number from a to b.
-- checkpoint, when given, is called regularly so the caller can yield.
function Grid.new(target: number, seed: number, rand: (number?, number?) -> number, checkpoint: (() -> ())?): Grid
	target = math.max(1, math.floor(target))
	-- Allocate the rock budget across tapered columns. Removing excess rocks
	-- from the highest layers would cut the summit into a broad flat stump.
	local radius = math.clamp(math.ceil((target * 1.06 / 0.94) ^ (1 / 3)), 3, OFFSET - 4)
	local height = math.max(2, math.floor(radius * 1.05 + 0.5))
	local self = empty(rand)
	self.radius = radius
	self.height = height
	local scale = 15 / radius
	local columns = {}
	local weightTotal = 0
	for z = -radius, radius do
		for x = -radius, radius do
			local distance = math.sqrt(x * x + z * z) / radius
			if distance <= 1 then
				local bumps = math.noise(x * 0.16 * scale, z * 0.16 * scale, seed) * 2.6 + math.noise(x * 0.4 * scale, z * 0.4 * scale, seed + 7.3) * 0.9
				-- Slopes continue almost to the centre, leaving a small summit.
				local profile = math.min(1, (1 - distance) / 0.94) ^ 1.05
				local weight = math.max(0, height * profile + bumps * (1 - distance * 0.6) / math.sqrt(scale))
				table.insert(columns, { x = x, z = z, weight = weight, height = 0, fraction = 0 })
				weightTotal += weight
			end
		end
	end
	local count = 0
	for _, column in columns do
		local exact = target * column.weight / weightTotal
		column.height = math.floor(exact)
		column.fraction = exact - column.height
		count += column.height
	end
	-- Spread rounding remainders across columns instead of shaving the summit.
	table.sort(columns, function(a, b)
		if a.fraction ~= b.fraction then return a.fraction > b.fraction end
		if a.z ~= b.z then return a.z < b.z end
		return a.x < b.x
	end)
	for i = 1, target - count do columns[i].height += 1 end
	self.height = 0
	local order = table.create(target)
	self.order = order
	for index, column in columns do
		self.height = math.max(self.height, column.height)
		for y = 0, column.height - 1 do
			local key = Grid.key(column.x, y, column.z)
			self.solid[key] = true
			table.insert(order, key)
		end
		if checkpoint and index % 512 == 0 then checkpoint() end
	end
	self.total = #order
	for index, key in order do
		if self:isExposed(key) then
			self:_expose(key)
		end
		if checkpoint and index % 4096 == 0 then checkpoint() end
	end
	table.clear(self.fresh)
	return self
end

function Grid.isSolid(self: Grid, key: number): boolean
	return hasBit(self.solidPages, key)
end

-- Open air: not rock, not the sealed diamond cavity and not the ground below layer 0.
function Grid.isAir(self: Grid, key: number): boolean
	return key >= 0 and not hasBit(self.solidPages, key) and not self.sealed[key]
end

-- Visits every solid cell in ascending key order (layer by layer). The visitor
-- may yield; the grid must not change until the walk finishes.
function Grid.eachSolid(self: Grid, visit: (number) -> ())
	local pages = self.solidPages
	local indices = {}
	for index in pages do table.insert(indices, index) end
	table.sort(indices)
	for _, index in indices do
		local page = pages[index]
		local base = index * 4096
		for byte = 0, 511 do
			local bits = buffer.readu8(page, byte)
			if bits ~= 0 then
				for bit = 0, 7 do
					if bit32.btest(bits, bit32.lshift(1, bit)) then visit(base + byte * 8 + bit) end
				end
			end
		end
	end
end

-- One solid layer behind a surface cell, excluding ground and the diamond cavity.
function Grid.solidNeighbours(self: Grid, key: number): { number }
	local pages = self.solidPages
	local result = {}
	for _, step in STEPS do
		local neighbour = key + step
		if neighbour >= 0 and hasBit(pages, neighbour) then
			table.insert(result, neighbour)
		end
	end
	return result
end

function Grid.remaining(self: Grid): number
	return self.total - self.removed
end

function Grid.isExposed(self: Grid, key: number): boolean
	local pages, sealed = self.solidPages, self.sealed
	for _, step in STEPS do
		local neighbour = key + step
		-- The ground under the mountain (below layer 0) counts as solid.
		if neighbour >= 0 and not hasBit(pages, neighbour) and not sealed[neighbour] then
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
	self.growthHeap = nil
	self.growthScores = nil
	self.growthQueued = nil
	self.removed += 1
	table.insert(self.removedOrder, key)
	self:_unexpose(key)
	local pages = self.solidPages
	for _, step in STEPS do
		local neighbour = key + step
		if neighbour >= 0 and hasBit(pages, neighbour) then
			self:_expose(neighbour)
		end
	end
	return true
end

-- Refill recently excavated cells in reverse order, never the sealed diamond cell.
function Grid.restore(self: Grid, count: number, focus: { x: number, y: number?, z: number, radius: number? }?, checkpoint: (() -> ())?, onAdded: ((number) -> ())?): { number }
	-- Bucket integer squared distances so large refills avoid sorting every
	-- missing rock. Pop nearest buckets first, leaving the gem cell reserved.
	-- Sorting yields, and players may dig meanwhile: cells dug after this point
	-- are added back to the refill order once it is rebuilt.
	local source, sourceCount = self.removedOrder, #self.removedOrder
	if focus and focus.y ~= nil then
		local buckets = {}
		local distances = {}
		for index = 1, sourceCount do
			local key = source[index]
			local x, y, z = Grid.coords(key)
			local distance = (x - focus.x)^2 + (y - focus.y)^2 + (z - focus.z)^2
			if buckets[distance] == nil then
				buckets[distance] = {}
				table.insert(distances, distance)
			end
			table.insert(buckets[distance], key)
			if checkpoint and index % 256 == 0 then checkpoint() end
		end
		table.sort(distances, function(a, b) return a > b end)
		local ordered = {}
		for _, distance in distances do
			for _, key in buckets[distance] do
				table.insert(ordered, key)
				if checkpoint and #ordered % 256 == 0 then checkpoint() end
			end
		end
		for index = sourceCount + 1, #source do table.insert(ordered, source[index]) end
		self.removedOrder = ordered
	elseif focus then
		local distant, nearby = {}, {}
		for index = 1, sourceCount do
			local key = source[index]
			if checkpoint and index % 256 == 0 then checkpoint() end
			local x, y, z = Grid.coords(key)
			local distance = (x - focus.x) ^ 2 + (z - focus.z) ^ 2
			if distance <= (focus.radius or 0) ^ 2 then
				table.insert(nearby, { key = key, y = y, distance = distance })
			else
				table.insert(distant, key)
			end
		end
		-- restore pops from the end: closest column first, lowest cell first.
		table.sort(nearby, function(a, b)
			if a.distance ~= b.distance then return a.distance > b.distance end
			if a.y ~= b.y then return a.y > b.y end
			return a.key > b.key
		end)
		for _, cell in nearby do table.insert(distant, cell.key) end
		for index = sourceCount + 1, #source do table.insert(distant, source[index]) end
		self.removedOrder = distant
	end
	local restored = {}
	-- Bit-packed sets: plain tables rehash with long stalls at this size.
	local affected = (newCellMap())
	while #restored < count and #self.removedOrder > 0 do
		local key = table.remove(self.removedOrder) :: number
		if not self.solid[key] and not self.sealed[key] then
			self.solid[key] = true
			self.removed -= 1
			table.insert(restored, key)
			if onAdded then onAdded(key) end
			if checkpoint and #restored % 256 == 0 then checkpoint() end
			affected[key] = true
			for _, neighbour in self:solidNeighbours(key) do affected[neighbour] = true end
		end
	end
	local processed = 0
	local pages = self.solidPages
	for key in affected do
		processed += 1
		if checkpoint and processed % 256 == 0 then checkpoint() end
		-- A player may have dug this cell again while the refill was working.
		if hasBit(pages, key) and self:isExposed(key) then self:_expose(key) else self:_unexpose(key) end
	end
	if #restored > 0 then self.growthHeap = nil; self.growthScores = nil; self.growthQueued = nil end
	return restored
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
function Grid.blast(self: Grid, count: number, centre: number?, checkpoint: (() -> ())?, onRemoved: ((number) -> ())?): ({ number }, number?)
	local removed: { number } = {}
	local start = if centre ~= nil and self.solid[centre] and self.exposedIndex[centre] then centre else self:randomExposed()
	if start == nil then
		return removed, nil
	end
	local cx, cy, cz = Grid.coords(start)
	local heap: { { number } } = {}
	local queued = (newCellMap())
	local pages = self.solidPages
	local function enqueue(key: number)
		if queued[key] or not hasBit(pages, key) then
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
			if onRemoved then onRemoved(key) end
			if checkpoint and #removed % 256 == 0 then checkpoint() end
			for _, step in STEPS do
				local neighbour = key + step
				if neighbour >= 0 then enqueue(neighbour) end
			end
		end
	end
	return removed, start
end

-- Expand the rock's surface without generating a replacement mountain.
-- Existing tunnels are restored first by Mountain.restore; the sealed diamond
-- cell is never filled. The cached frontier keeps consecutive growth gifts cheap.
function Grid.grow(self: Grid, count: number, capacity: number, checkpoint: (() -> ())?, onAdded: ((number) -> ())?): { number }
	count = math.min(math.max(0, math.floor(count)), math.max(0, capacity - self.total))
	local added = {}
	if count == 0 then return added end
	local heap = self.growthHeap or {}
	local scores = self.growthScores or {}
	local queued = self.growthQueued or (newCellMap())
	-- Parallel numeric arrays avoid allocating a tiny table for every new cell.
	local function pushCandidate(key: number, score: number)
		local i = #heap + 1
		while i > 1 do
			local parent = i // 2
			if scores[parent] <= score then break end
			heap[i], scores[i] = heap[parent], scores[parent]
			i = parent
		end
		heap[i], scores[i] = key, score
	end
	local function popCandidate(): number?
		local count = #heap
		if count == 0 then return nil end
		local key = heap[1]
		local last, lastScore = heap[count], scores[count]
		heap[count], scores[count] = nil, nil
		count -= 1
		if count > 0 then
			local i = 1
			while i * 2 <= count do
				local child = i * 2
				if child + 1 <= count and scores[child + 1] < scores[child] then child += 1 end
				if lastScore <= scores[child] then break end
				heap[i], scores[i] = heap[child], scores[child]
				i = child
			end
			heap[i], scores[i] = last, lastScore
		end
		queued[key] = nil
		return key
	end
	local function enqueue(x: number, y: number, z: number)
		if y < 0 or x * x + z * z > (OFFSET - 4) ^ 2 then return end
		local key = Grid.key(x, y, z)
		if self.solid[key] or self.sealed[key] or queued[key] then return end
		queued[key] = true
		pushCandidate(key, x * x + z * z + (y * 1.6) ^ 2)
	end
	if self.growthHeap == nil then
		for index, key in self.exposedList do
			local x, y, z = Grid.coords(key)
			for _, step in NEIGHBOURS do enqueue(x + step[1], y + step[2], z + step[3]) end
			if checkpoint and index % 256 == 0 then checkpoint() end
		end
		-- A cleared mountain can still be rebuilt (normally restore handles it).
		if #heap == 0 then enqueue(0, 0, 0) end
	end
	self.growthHeap, self.growthScores, self.growthQueued = heap, scores, queued
	while #added < count do
		local key = popCandidate()
		if key == nil then break end
		if self.solid[key] or self.sealed[key] then continue end
		self.solid[key] = true
		self.total += 1
		table.insert(self.order, key)
		table.insert(added, key)
		local x, y, z = Grid.coords(key)
		self.radius = math.max(self.radius, math.ceil(math.sqrt(x * x + z * z)))
		self.height = math.max(self.height, y + 1)
		if self:isExposed(key) then self:_expose(key) end
		for _, step in NEIGHBOURS do
			local nx, ny, nz = x + step[1], y + step[2], z + step[3]
			if ny >= 0 then
				local neighbour = Grid.key(nx, ny, nz)
				if self.solid[neighbour] and not self:isExposed(neighbour) then self:_unexpose(neighbour) end
				enqueue(nx, ny, nz)
			end
		end
		if onAdded then onAdded(key) end
		if checkpoint and #added % 256 == 0 then checkpoint() end
	end
	return added
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
function Grid.carveHiddenCell(self: Grid, checkpoint: (() -> ())?): number
	local key = self:pickHiddenCell(checkpoint)
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

function Grid.pickHiddenCell(self: Grid, checkpoint: (() -> ())?): number
	local buried: { number } = {}
	local low, high, reach = math.max(1, math.floor(self.height * 0.15)), self.height * 0.35, (self.radius * 0.3) ^ 2
	for index, key in self.order do
		local x, y, z = Grid.coords(key)
		-- Cheap position tests first; only central cells need the exposure test.
		if y >= low and y <= high and x * x + z * z <= reach and self:isSolid(key) and not self:isExposed(key) then
			table.insert(buried, key)
		end
		if checkpoint and index % 8192 == 0 then checkpoint() end
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
