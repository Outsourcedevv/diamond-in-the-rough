-- Runs outside Roblox with the Luau CLI: luau tests/run.luau
local HoldTimer = require("../src/shared/HoldTimer")
local Format = require("../src/shared/Format")
local Grid = require("../src/server/Grid")

local passed, failed = 0, 0
local function check(condition: boolean, message: string)
	if condition then
		passed += 1
	else
		failed += 1
		print("FAIL " .. message)
	end
end

-- Hold countdown: 15 real seconds shown as 10 -> 0, slowing near the end.
check(HoldTimer.display(0, 15, 10, 0.6) == 10, "countdown starts at 10")
check(HoldTimer.display(14.99, 15, 10, 0.6) == 1, "countdown shows 1 just before the end")
check(HoldTimer.display(15, 15, 10, 0.6) == 0, "countdown reaches 0 after 15 s")
local changes: { number } = {}
local last = 10
for tick = 1, 15000 do
	local t = tick / 1000
	local shown = HoldTimer.display(t, 15, 10, 0.6)
	check(shown <= last, "countdown never goes up")
	if shown ~= last then
		table.insert(changes, t)
		last = shown
	end
end
check(#changes == 10, "countdown shows every number from 10 to 0 (" .. #changes .. " changes)")
local firstStep = changes[1]
local lastStep = changes[10] - changes[9]
check(firstStep < 1.2 and lastStep > 2.0, string.format("early numbers are quick (%.2f s), the last is slow (%.2f s)", firstStep, lastStep))
for i = 2, 10 do
	local before = changes[i - 1] - (if i > 2 then changes[i - 2] else 0)
	check(changes[i] - changes[i - 1] >= before - 1e-6, "each number lasts at least as long as the one before")
end
check(HoldTimer.display(7.5, 15, 10, 0) == 5, "slowdown 0 counts evenly")

-- Formatting
check(Format.commas(250000) == "250,000", "commas 250,000")
check(Format.commas(999) == "999" and Format.commas(1000) == "1,000" and Format.commas(0) == "0", "commas small numbers")
check(Format.commas(1234567.4) == "1,234,567", "commas rounds")
check(Format.duration(83.46) == "1:23.5", "duration " .. Format.duration(83.46))
check(Format.duration(5) == "0:05.0", "duration " .. Format.duration(5))
check(Format.duration(3723) == "1:02:03.0", "duration hours " .. Format.duration(3723))
local r, g, b = Format.parseHex("#FF8800")
check(r == 255 and g == 136 and b == 0, "hex colour")
check(Format.parseHex("orange") == nil, "bad colour rejected")
check(Format.wins("WINS", 3, 0) == "WINS: 3" and Format.wins("WINS", 3, 10) == "WINS: 3/10" and Format.wins("", 2, 0) == "2", "win counter text")

-- Mountain grid
local seed = 0
local function rand(a: number?, b: number?): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	local unit = seed / 2147483648
	if a ~= nil and b ~= nil then
		return a + math.floor(unit * (b - a + 1))
	end
	return unit
end
local grid = Grid.new(15, 14, 3.7, rand)
print("mountain blocks", grid.total, "exposed", grid:exposedCount())
check(grid.total > 1500 and grid.total < 6000, "mountain has a sensible number of blocks")
local x, y, z = Grid.coords(Grid.key(-15, 13, 7))
check(x == -15 and y == 13 and z == 7, "keys round-trip coordinates")
local hidden = grid:pickHiddenCell()
check(grid:isSolid(hidden) and not grid:isExposed(hidden), "the diamond starts fully buried")
local removed, centre = grid:blast(40)
check(#removed == 40 and centre ~= nil, "a blast removes the requested number of blocks")
local cx, cy, cz = Grid.coords(centre :: number)
local far = 0
for _, key in removed do
	local bx, by, bz = Grid.coords(key)
	if (bx - cx) ^ 2 + (by - cy) ^ 2 + (bz - cz) ^ 2 > 64 then
		far += 1
	end
end
check(far <= 4, "blast blocks cluster into one crater (" .. far .. " far away)")
-- Exposure stays consistent with the solid cells after many blasts.
for _ = 1, 30 do
	grid:blast(rand(1, 60))
end
local consistent = true
for _, key in grid.order do
	if grid:isSolid(key) then
		local listed = grid.exposedIndex[key] ~= nil
		if listed ~= grid:isExposed(key) then
			consistent = false
		end
	end
end
check(consistent, "exposed list matches the actual exposed blocks")
check(grid:remaining() == grid.total - grid.removed, "remaining count")
-- Blasting everything empties the mountain and reaches the diamond's cell.
local all = grid:blast(grid.total)
check(grid:remaining() == 0 and grid:exposedCount() == 0, "the whole mountain can be blasted away")
check(not grid:isSolid(hidden), "the diamond's cell is eventually opened")
check(grid:supportBelow(0, 5, 0) == -1, "nothing supports a find once the mountain is gone")

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
	error("tests failed")
end
