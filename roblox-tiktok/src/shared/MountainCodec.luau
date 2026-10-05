--!strict
--!native
-- Packs mountain cells for the network. Craters and refills are mostly
-- vertical runs of rock, so cells travel as column runs:
--   u16 column, u16 first layer, u16 run length  (6 bytes per run)
-- A 100,000-rock blast becomes a few thousand runs instead of 100,000 parts.
local MountainCodec = {}

local LAYER = 65536 -- Grid key = column + layer * 65536
local RUN_BYTES = 6
local PAIR_BYTES = 4
-- Keeps every remote payload small enough to send without stalling a client.
MountainCodec.MaxRuns = 8000

-- Packs cell keys (any order, no duplicates needed) into one or more buffers.
function MountainCodec.encode(keys: { number }, checkpoint: (() -> ())?): { buffer }
	local columns: { [number]: { number } } = {}
	local order: { number } = {}
	for index, key in keys do
		local column = key % LAYER
		local list = columns[column]
		if list == nil then
			list = {}
			columns[column] = list
			table.insert(order, column)
		end
		table.insert(list, key // LAYER)
		if checkpoint and index % 4096 == 0 then checkpoint() end
	end
	local runs: { number } = {} -- flat triples: column, first, length
	for index, column in order do
		local layers = columns[column]
		table.sort(layers)
		local first, last = layers[1], layers[1]
		for i = 2, #layers do
			local y = layers[i]
			if y == last + 1 then
				last = y
			elseif y ~= last then
				table.insert(runs, column); table.insert(runs, first); table.insert(runs, last - first + 1)
				first, last = y, y
			end
		end
		table.insert(runs, column); table.insert(runs, first); table.insert(runs, last - first + 1)
		if checkpoint and index % 1024 == 0 then checkpoint() end
	end
	local chunks: { buffer } = {}
	local total = #runs // 3
	local start = 0
	while start < total do
		local count = math.min(MountainCodec.MaxRuns, total - start)
		local chunk = buffer.create(count * RUN_BYTES)
		for i = 0, count - 1 do
			local at = (start + i) * 3
			buffer.writeu16(chunk, i * RUN_BYTES, runs[at + 1])
			buffer.writeu16(chunk, i * RUN_BYTES + 2, runs[at + 2])
			buffer.writeu16(chunk, i * RUN_BYTES + 4, runs[at + 3])
		end
		table.insert(chunks, chunk)
		start += count
	end
	return chunks
end

-- Calls visit(key) for every cell in one encoded buffer. visit may yield.
function MountainCodec.decode(chunk: buffer, visit: (number) -> ())
	for offset = 0, buffer.len(chunk) - RUN_BYTES, RUN_BYTES do
		local column = buffer.readu16(chunk, offset)
		local first = buffer.readu16(chunk, offset + 2)
		for y = first, first + buffer.readu16(chunk, offset + 4) - 1 do
			visit(column + y * LAYER)
		end
	end
end

-- How many cells a list of encoded buffers holds.
function MountainCodec.count(chunks: { buffer }): number
	local cells = 0
	for _, chunk in chunks do
		for offset = 4, buffer.len(chunk) - 2, RUN_BYTES do
			cells += buffer.readu16(chunk, offset)
		end
	end
	return cells
end

-- Column -> number pairs (the original column tops), u16 + u16 each.
function MountainCodec.encodePairs(values: { [number]: number }): { buffer }
	local flat: { number } = {}
	for column, value in values do
		table.insert(flat, column)
		table.insert(flat, value)
	end
	local chunks: { buffer } = {}
	local perChunk = MountainCodec.MaxRuns
	local total = #flat // 2
	local start = 0
	while start < total do
		local count = math.min(perChunk, total - start)
		local chunk = buffer.create(count * PAIR_BYTES)
		for i = 0, count - 1 do
			buffer.writeu16(chunk, i * PAIR_BYTES, flat[(start + i) * 2 + 1])
			buffer.writeu16(chunk, i * PAIR_BYTES + 2, math.clamp(flat[(start + i) * 2 + 2], 0, 65535))
		end
		table.insert(chunks, chunk)
		start += count
	end
	return chunks
end

function MountainCodec.decodePairs(chunk: buffer, visit: (number, number) -> ())
	for offset = 0, buffer.len(chunk) - PAIR_BYTES, PAIR_BYTES do
		visit(buffer.readu16(chunk, offset), buffer.readu16(chunk, offset + 2))
	end
end

return MountainCodec
