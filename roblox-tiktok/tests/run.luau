-- Runs outside Roblox with the Luau CLI: luau tests/run.luau
local HoldTimer = require("../src/shared/HoldTimer")
local Format = require("../src/shared/Format")
local Grid = require("../src/server/Grid")
local RockStyle = require("../src/server/RockStyle")
local GiftTier = require("../src/shared/GiftTier")

local passed, failed = 0, 0
local function check(condition: boolean, message: string)
	if condition then
		passed += 1
	else
		failed += 1
		print("FAIL " .. message)
	end
end

-- Coin tiers apply to total gift value, independent of custom rock-removal rules.
for _, case in { {1, 1}, {9, 1}, {10, 2}, {99, 2}, {100, 3}, {499, 3}, {500, 4}, {999, 4}, {1000, 5}, {9999, 5}, {10000, 6}, {34999, 6}, {1000000000, 6} } do
	check(GiftTier.forCoins(case[1]) == case[2], "gift tier boundary " .. case[1])
end
check(GiftTier.forCoins(30 * 40) == 5, "gift combos scale by their total coin value")

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
-- Visual changes must remain deterministic when a blast uncovers a saved cell,
-- use bounded per-cell geometry and avoid a repeating bead pattern.
local styles = {}
local previousShape = ""
local changesInRow = 0
for x = -128, 127 do
	local key = Grid.key(x, 12, 17)
	local rock = RockStyle.forCell(key)
	local again = RockStyle.forCell(key)
	check(rock.shape == again.shape and rock.yaw == again.yaw and rock.shade == again.shade, "uncovered rock keeps its appearance")
	check(rock.x >= 1.55 and rock.x <= 1.9 and rock.y >= 1.30 and rock.y <= 1.54 and rock.z >= 1.54 and rock.z <= 1.89, "stone sizes stay within the compact rubble envelope")
	check(math.abs(rock.ox) <= 0.06 and math.abs(rock.oz) <= 0.06 and math.abs(rock.oy) <= 0.04, "stone jitter stays tied to its diggable cell")
	styles[rock.shape] = true
	if rock.shape ~= previousShape then changesInRow += 1 end
	previousShape = rock.shape
end
check(styles.Part and styles.WedgePart and styles.CornerWedgePart, "rubble mixes three native faceted shapes")
check(changesInRow > 100, "adjacent rocks do not repeat the same shape in long grid rows")

local seed = 0
local function rand(a: number?, b: number?): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	local unit = seed / 2147483648
	if a ~= nil and b ~= nil then
		return a + math.floor(unit * (b - a + 1))
	end
	return unit
end
local t0 = os.clock()
-- Rebuilds during a hold refill the player's column before distant holes.
local focused = Grid.new(1234, 1, rand)
local column = {}
local distant: number? = nil
for _, key in focused.order do
	local x, y, z = Grid.coords(key)
	if x == 0 and z == 0 then table.insert(column, { key = key, y = y }) end
	if math.abs(x) > 2 then distant = key end
end
table.sort(column, function(a, b) return a.y < b.y end)
check(#column >= 2 and distant ~= nil, "focused rebuild fixture has near and far cells")
focused:remove(column[1].key)
focused:remove(column[2].key)
focused:remove(distant :: number)
local nearRestore = focused:restore(2, { x = 0, z = 0, radius = 1 })
check(nearRestore[1] == column[1].key and nearRestore[2] == column[2].key, "rebuild restores the holder column from bottom upwards")
check(not focused:isSolid(distant :: number), "small rebuild leaves distant excavations unfilled")
check(#focused:restore(100, { x = 10000, z = 10000, radius = 1 }) == 1, "focus outside mountain still restores available rocks")
check(#focused:restore(100, { x = 0, z = 0, radius = 1 }) == 0, "full mountain rebuild is a no-op")
local grid = Grid.new(250000, 3.7, rand)
local hidden = grid:carveHiddenCell()
print(string.format("mountain rocks %d, exposed %d, radius %d, built in %.2f s", grid.total, grid:exposedCount(), grid.radius, os.clock() - t0))
check(grid.total == 250000 - 1, "one rock per stone: exactly 250,000 cells, one carved for the diamond (" .. grid.total .. ")")
check(Grid.new(1234, 1, rand).total == 1234, "any starting stone gives exactly that many rocks")
check(grid:exposedCount() < 40000, "only the outer rocks need parts (" .. grid:exposedCount() .. ")")
local x, y, z = Grid.coords(Grid.key(-15, 13, 7))
check(x == -15 and y == 13 and z == 7, "keys round-trip coordinates")
check(not grid:isSolid(hidden) and not grid:isOpenAround(hidden), "the diamond starts sealed inside the rock")
check(grid.exposedIndex[hidden] == nil, "rock around the diamond does not count as uncovered")
-- Model the rendered shell across a blast; newly exposed cells must bring their
-- backing neighbours forward, and removed cells must never remain in the shell.
local shell = {}
local function drawShell(key)
	if not grid:isSolid(key) then return end
	shell[key] = true
	for _, neighbour in grid:solidNeighbours(key) do shell[neighbour] = true end
end
for _, key in grid.exposedList do drawShell(key) end
local shellCount = 0
for _ in shell do shellCount += 1 end
check(shellCount > grid:exposedCount() and shellCount < 40000, "two layers have a bounded part count: " .. shellCount)
check(not shell[hidden], "backing never fills the diamond cavity")
grid:takeFresh()
local removed, centre = grid:blast(400)
check(#removed == 400 and centre ~= nil, "a blast removes exactly the requested number of rocks")
for _, key in removed do shell[key] = nil end
local fresh = grid:takeFresh()
check(#fresh > 0, "a blast uncovers new rocks to draw")
for _, key in fresh do drawShell(key) end
local backed = true
for _, key in grid.exposedList do
	if not shell[key] then backed = false end
	for _, neighbour in grid:solidNeighbours(key) do
		if not shell[neighbour] then backed = false end
	end
end
check(backed, "every crater surface keeps a second layer after blasting")
for _, key in removed do check(not shell[key], "removed stones do not leave backing behind") end
local cx, cy, cz = Grid.coords(centre :: number)
local far = 0
for _, key in removed do
	local bx, by, bz = Grid.coords(key)
	if (bx - cx) ^ 2 + (by - cy) ^ 2 + (bz - cz) ^ 2 > 100 then
		far += 1
	end
end
check(far <= 20, "blast rocks cluster into one crater (" .. far .. " far away)")
for _ = 1, 30 do
	grid:blast(rand(1, 3000))
end
local consistent = true
for _, key in grid.order do
	if grid:isSolid(key) then
		if (grid.exposedIndex[key] ~= nil) ~= grid:isExposed(key) then
			consistent = false
		end
	end
end
check(consistent, "uncovered list matches the actual uncovered rocks")
check(grid:remaining() == grid.total - grid.removed, "remaining count")
local beforeRestore = grid:remaining()
local restored = grid:restore(1200)
check(#restored == 1200 and grid:remaining() == beforeRestore + 1200, "adding restores exactly the requested excavated rocks")
check(not grid:isSolid(hidden), "restoration never fills the diamond cell")
local exposureMatches = true
for _, key in grid.order do
	if grid:isSolid(key) and (grid.exposedIndex[key] ~= nil) ~= grid:isExposed(key) then exposureMatches = false end
end
check(exposureMatches, "restore updates exposed neighbours correctly")
grid:restore(grid.total * 2)
check(grid:remaining() == grid.total and #grid.removedOrder == 0, "add gifts cannot overfill the original mountain")
check(#grid:restore(50) == 0, "add gift on full mountain is a no-op")
grid:blast(123)
check(#grid:restore(123) == 123, "repeated dig and refill preserves accounting")

t0 = os.clock()
grid:blast(grid.total)
print(string.format("cleared the rest in %.2f s", os.clock() - t0))
check(grid:remaining() == 0 and grid:exposedCount() == 0, "the whole mountain can be blasted away")
check(grid:isOpenAround(hidden), "the diamond is reached once the rock around it is gone")
check(grid:supportBelow(0, 5, 0) == -1, "nothing supports a find once the mountain is gone")

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
	error("tests failed")
end
