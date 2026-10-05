--!strict
--!native
-- Unpacks data stored in scripts: base64 text and raw DEFLATE streams (RFC 1951,
-- as written by Python's zlib with wbits=-15). A small, table-free version of
-- Mark Adler's puff decoder, used for the Blender scenery pack's mesh data.
local Inflate = {}

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local SEXTET = table.create(256, -1)
for i = 1, #ALPHABET do
	SEXTET[string.byte(ALPHABET, i) + 1] = i - 1
end

-- Decodes base64, skipping line breaks, spaces and padding.
function Inflate.base64(text: string): buffer
	local out = buffer.create(#text * 3 // 4 + 3)
	local size, acc, bits = 0, 0, 0
	for i = 1, #text do
		local value = SEXTET[string.byte(text, i) + 1]
		if value >= 0 then
			acc = bit32.bor(bit32.lshift(acc, 6), value)
			bits += 6
			if bits >= 8 then
				bits -= 8
				buffer.writeu8(out, size, bit32.band(bit32.rshift(acc, bits), 0xFF))
				size += 1
			end
		end
	end
	local result = buffer.create(size)
	buffer.copy(result, 0, out, 0, size)
	return result
end

local LENGTH_BASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LENGTH_EXTRA = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DISTANCE_BASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
	8193, 12289, 16385, 24577 }
local DISTANCE_EXTRA = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local CODE_LENGTH_ORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

-- A canonical Huffman code: how many codes have each length (1-15), and the
-- symbols in code order.
type Huffman = { count: { number }, symbol: { number } }

-- `lengths` is 0-based: lengths[symbol] for symbols first .. first + n - 1.
local function huffman(lengths: { [number]: number }, first: number, n: number): Huffman
	local count = table.create(16, 0)
	for s = first, first + n - 1 do
		local length = lengths[s]
		count[length + 1] += 1
	end
	local offsets = table.create(16, 0)
	for length = 1, 14 do
		offsets[length + 2] = offsets[length + 1] + count[length + 1]
	end
	local symbol = table.create(n, 0)
	for s = first, first + n - 1 do
		local length = lengths[s]
		if length ~= 0 then
			offsets[length + 1] += 1
			symbol[offsets[length + 1]] = s - first
		end
	end
	return { count = count, symbol = symbol }
end

local fixedLength: Huffman, fixedDistance: Huffman
do
	local lengths = {}
	for s = 0, 287 do
		lengths[s] = if s < 144 then 8 elseif s < 256 then 9 elseif s < 280 then 7 else 8
	end
	fixedLength = huffman(lengths, 0, 288)
	for s = 0, 29 do
		lengths[s] = 5
	end
	fixedDistance = huffman(lengths, 0, 30)
end

-- Unpacks a raw DEFLATE stream whose unpacked size is known. `pause`, if given,
-- is called now and then, so long work can be spread over frames.
function Inflate.inflate(input: buffer, size: number, pause: (() -> ())?): buffer
	local out = buffer.create(size)
	local at, inAt, inSize = 0, 0, buffer.len(input)
	local bitBuffer, bitCount = 0, 0

	local function bits(need: number): number
		local value = bitBuffer
		while bitCount < need do
			if inAt >= inSize then error("Inflate: the data ends early") end
			value = bit32.bor(value, bit32.lshift(buffer.readu8(input, inAt), bitCount))
			inAt += 1
			bitCount += 8
		end
		bitBuffer = bit32.rshift(value, need)
		bitCount -= need
		return bit32.band(value, bit32.lshift(1, need) - 1)
	end

	local function decode(code: Huffman): number
		local count, symbol = code.count, code.symbol
		local value, first, index = 0, 0, 0
		for length = 1, 15 do
			if bitCount == 0 then
				if inAt >= inSize then error("Inflate: the data ends early") end
				bitBuffer = buffer.readu8(input, inAt)
				inAt += 1
				bitCount = 8
			end
			value = bit32.bor(value, bit32.band(bitBuffer, 1))
			bitBuffer = bit32.rshift(bitBuffer, 1)
			bitCount -= 1
			local here = count[length + 1]
			if value - here < first then
				return symbol[index + value - first + 1]
			end
			index += here
			first = (first + here) * 2
			value *= 2
		end
		error("Inflate: bad code")
	end

	local symbols = 0
	local function codes(lengthCode: Huffman, distanceCode: Huffman)
		while true do
			local s = decode(lengthCode)
			symbols += 1
			if pause and symbols % 4096 == 0 then pause() end
			if s < 256 then
				if at >= size then error("Inflate: more data than expected") end
				buffer.writeu8(out, at, s)
				at += 1
			elseif s == 256 then
				return
			else
				s -= 256
				if s > 29 then error("Inflate: bad length") end
				local length = LENGTH_BASE[s] + bits(LENGTH_EXTRA[s])
				local d = decode(distanceCode) + 1
				if d > 30 then error("Inflate: bad distance") end
				local distance = DISTANCE_BASE[d] + bits(DISTANCE_EXTRA[d])
				if distance > at then error("Inflate: distance too far back") end
				if at + length > size then error("Inflate: more data than expected") end
				if distance >= length then
					buffer.copy(out, at, out, at - distance, length)
					at += length
				else
					-- Overlapping copies repeat the recent bytes.
					for _ = 1, length do
						buffer.writeu8(out, at, buffer.readu8(out, at - distance))
						at += 1
					end
				end
			end
		end
	end

	local lengths: { [number]: number } = {}
	repeat
		local last = bits(1)
		local kind = bits(2)
		if kind == 0 then
			bitBuffer, bitCount = 0, 0
			if inAt + 4 > inSize then error("Inflate: the data ends early") end
			local length = buffer.readu16(input, inAt)
			if bit32.bxor(length, 0xFFFF) ~= buffer.readu16(input, inAt + 2) then error("Inflate: bad stored block") end
			inAt += 4
			if inAt + length > inSize or at + length > size then error("Inflate: bad stored block") end
			buffer.copy(out, at, input, inAt, length)
			inAt += length
			at += length
		elseif kind == 1 then
			codes(fixedLength, fixedDistance)
		elseif kind == 2 then
			local literals = bits(5) + 257
			local distances = bits(5) + 1
			local lengthCodes = bits(4) + 4
			if literals > 286 or distances > 30 then error("Inflate: bad code counts") end
			for i = 0, 18 do
				lengths[CODE_LENGTH_ORDER[i + 1]] = if i < lengthCodes then bits(3) else 0
			end
			local codeLengths = huffman(lengths, 0, 19)
			local i = 0
			while i < literals + distances do
				local s = decode(codeLengths)
				if s < 16 then
					lengths[i] = s
					i += 1
				else
					local repeated, times = 0, 0
					if s == 16 then
						if i == 0 then error("Inflate: repeat with no previous length") end
						repeated = lengths[i - 1]
						times = 3 + bits(2)
					elseif s == 17 then
						times = 3 + bits(3)
					else
						times = 11 + bits(7)
					end
					if i + times > literals + distances then error("Inflate: too many lengths") end
					for _ = 1, times do
						lengths[i] = repeated
						i += 1
					end
				end
			end
			codes(huffman(lengths, 0, literals), huffman(lengths, literals, distances))
		else
			error("Inflate: bad block type")
		end
	until last == 1
	if at ~= size then error("Inflate: less data than expected") end
	return out
end

return Inflate
