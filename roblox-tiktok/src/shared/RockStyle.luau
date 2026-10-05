--!strict
--!native
-- How each visible cell of rock is drawn. Pure data, shared by the client
-- renderer and the tests.
--
-- Shape: surface cells slope towards open air with native wedge shapes, so the
-- mountain reads as smooth faceted rock instead of a pile of cubes. A shape is
-- only chosen when every face it leaves open borders air or another drawn
-- (exposed) cell. That keeps the drawn shell watertight with exactly one part
-- per exposed cell, so no hidden backing layer is needed behind it.
--
-- Look: snow caps, grassy foothills with a dirt layer beneath, weathered crags
-- and layered strata inside. Colours stay close together in the rock: the one
-- small diamond must still be found by eye.
local RockStyle = {}

local SPAN = 256
local LAYER = SPAN * SPAN

RockStyle.NONE = 0
RockStyle.BLOCK = 1
-- Wedges slope down towards the named side: +X, -X, +Z, -Z.
RockStyle.WEDGE = { 2, 3, 4, 5 }
-- Corner wedges slope down towards two open sides; their tall corner faces away.
RockStyle.CORNER = { [1] = 6, [2] = 7, [3] = 8, [4] = 9 } -- (+X+Z), (+X-Z), (-X+Z), (-X-Z)

-- Direction vectors for the shape codes (x, z of the open side or sides).
RockStyle.DIRECTIONS = {
	[2] = { 1, 0 }, [3] = { -1, 0 }, [4] = { 0, 1 }, [5] = { 0, -1 },
	[6] = { 1, 1 }, [7] = { 1, -1 }, [8] = { -1, 1 }, [9] = { -1, -1 },
}

-- 1 block, 2 wedge, 3 corner wedge.
function RockStyle.kind(shape: number): number
	if shape <= 1 then return shape end
	return if shape <= 5 then 2 else 3
end

local function sample(key: number, salt: number): number
	local value = bit32.bxor(key, salt)
	value = (value * 1664525 + 1013904223) % 4294967296
	value = bit32.bxor(value, bit32.rshift(value, 16))
	value = (value * 1664525 + 1013904223) % 4294967296
	value = bit32.bxor(value, bit32.lshift(value, 13))
	value = bit32.bxor(value, bit32.rshift(value, 17))
	value = bit32.bxor(value, bit32.lshift(value, 5))
	return value / 4294967296
end
RockStyle.sample = sample

export type Cells = {
	isAir: (any, number) -> boolean,
	isSolid: (any, number) -> boolean,
	isExposed: (any, number) -> boolean,
}

-- The shape for a solid, exposed cell. `cells` is a Grid (or anything with the
-- same three queries).
function RockStyle.shape(cells: any, key: number): number
	local function drawn(n: number): boolean
		-- Air, or a solid neighbour that is drawn because it is exposed itself.
		return cells:isAir(n) or (cells:isSolid(n) and cells:isExposed(n))
	end
	if not cells:isAir(key + LAYER) then return RockStyle.BLOCK end
	if key >= LAYER and cells:isAir(key - LAYER) then return RockStyle.BLOCK end
	local east, west = cells:isAir(key + 1), cells:isAir(key - 1)
	local north, south = cells:isAir(key + SPAN), cells:isAir(key - SPAN)
	local open = (if east then 1 else 0) + (if west then 1 else 0) + (if north then 1 else 0) + (if south then 1 else 0)
	if open == 0 then return RockStyle.BLOCK end
	if open == 4 then
		-- A lone spire: every face is open air, so any corner works.
		return 6 + math.floor(sample(key, 3141) * 4)
	end
	if open == 3 then
		-- Slope away from the single solid side.
		if not east then return 3 elseif not west then return 2 elseif not north then return 5 else return 4 end
	end
	if open == 1 then
		-- Both side faces of a wedge are part-open triangles.
		if east or west then
			if drawn(key + SPAN) and drawn(key - SPAN) then return if east then 2 else 3 end
		else
			if drawn(key + 1) and drawn(key - 1) then return if north then 4 else 5 end
		end
		return RockStyle.BLOCK
	end
	-- Two open sides.
	if (east and west) or (north and south) then return RockStyle.BLOCK end
	local sx = if east then 1 else -1
	local sz = if north then 1 else -1
	local backX, backZ = key - sx, key - sz * SPAN
	local backXDrawn, backZDrawn = drawn(backX), drawn(backZ)
	if backXDrawn and backZDrawn then
		return if sx > 0 then (if sz > 0 then 6 else 7) else (if sz > 0 then 8 else 9)
	end
	-- A wedge towards one open side leaves its side faces on the other open side
	-- and on the opposite back cell.
	if backZDrawn then return if sx > 0 then 2 else 3 end
	if backXDrawn then return if sz > 0 then 4 else 5 end
	return RockStyle.BLOCK
end

-- Looks: index into RockStyle.LAYERS.
RockStyle.SNOW, RockStyle.GRASS, RockStyle.DIRT, RockStyle.CRAG, RockStyle.ROCK, RockStyle.SLATE = 1, 2, 3, 4, 5, 6
RockStyle.LAYERS = {
	{ name = "Snow", material = "Snow", colour = { 236, 241, 246 } },
	{ name = "Grass", material = "Grass", colour = { 96, 124, 60 } },
	{ name = "Dirt", material = "Ground", colour = { 108, 86, 62 } },
	{ name = "Crag", material = "Rock", colour = { 136, 131, 123 } },
	{ name = "Rock", material = "Rock", colour = { 113, 108, 102 } },
	{ name = "Slate", material = "Slate", colour = { 98, 96, 97 } },
}

-- The layer and colour for a cell. `top` is the column's original summit
-- layer, `height` the original mountain height in layers.
function RockStyle.look(key: number, top: number?, height: number): (number, number, number, number)
	local column = key % LAYER
	local x, y, z = column % SPAN - 128, key // LAYER, column // SPAN - 128
	local h = y / math.max(1, height)
	local depth = (top or y) - y
	local bands = math.noise(x * 0.09, z * 0.09, 4.2)
	local snowLine = 0.64 + bands * 0.18
	local grassLine = 0.18 + bands * 0.14
	local layer
	if depth <= 0 then
		layer = if h >= snowLine then RockStyle.SNOW elseif h <= grassLine then RockStyle.GRASS else RockStyle.CRAG
	elseif depth <= 1 and h >= snowLine then
		layer = RockStyle.SNOW
	elseif depth <= 2 and h <= grassLine + 0.06 then
		layer = RockStyle.DIRT
	else
		-- Tilted strata show in crater walls.
		layer = if math.noise(x * 0.05, y * 0.22 + x * 0.03, z * 0.05) > 0.1 then RockStyle.SLATE else RockStyle.ROCK
	end
	local base = RockStyle.LAYERS[layer].colour
	local shade = 0.9 + sample(key, 7321441) * 0.18
	local r, g, b = base[1] * shade, base[2] * shade, base[3] * shade
	if layer == RockStyle.GRASS then
		-- Sunlit patches drift towards a warmer green.
		local warm = math.clamp(math.noise(x * 0.21, z * 0.21, 9.1) + 0.5, 0, 1)
		r, g, b = r + warm * 18, g + warm * 12, b + warm * 4
	elseif layer >= RockStyle.ROCK and sample(key, 517927) > 0.985 then
		-- Rare pale quartz flecks keep the rock from looking flat.
		r, g, b = 165, 160, 150
	end
	return layer, math.min(255, r), math.min(255, g), math.min(255, b)
end

return RockStyle
