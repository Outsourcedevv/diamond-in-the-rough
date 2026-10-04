--!strict
-- Stable, irregular chips: neighbouring cells never look like a row of beads.
-- Pure data keeps newly uncovered stones consistent with the mountain surface.
local RockStyle = {}

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

function RockStyle.forCell(key: number)
	local a = sample(key, 7321441)
	local b = sample(key, 92837163)
	local c = sample(key, 517927)
	local d = sample(key, 1812433253)
	local shape = if a < 0.48 then "WedgePart" elseif a < 0.68 then "CornerWedgePart" else "Part"
	return {
		shape = shape,
		-- Overlap closes seams while offsets, tilts and unequal axes break the grid.
		x = 1.55 + b * 0.35,
		y = 1.30 + c * 0.24,
		z = 1.54 + d * 0.35,
		ox = (c - 0.5) * 0.12,
		oy = (a - 0.5) * 0.08,
		oz = (b - 0.5) * 0.12,
		pitch = (d - 0.5) * 0.34,
		yaw = c * math.pi * 2,
		roll = (b - 0.5) * 0.34,
		shade = 0.82 + a * 0.28,
		quartz = d > 0.975,
	}
end

return RockStyle
