-- Runs outside Roblox with the Luau CLI: luau tests/run.luau
local HoldTimer = require("../src/shared/HoldTimer")
local Format = require("../src/shared/Format")
local Grid = require("../src/shared/Grid")
local RockStyle = require("../src/shared/RockStyle")
local GiftTier = require("../src/shared/GiftTier")
local Keybinds = require("../src/shared/Keybinds")

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
check(GiftTier.forCoins(30) == 2 and GiftTier.forCoins(1000) == 5, "a combo's effect comes from one gift's coins (it plays as separate gifts)")

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

-- Mountain looks and network packing
local MountainCodec = require("../src/shared/MountainCodec")
-- Looks depend only on the cell, so a rock looks the same whenever it is drawn.
local layersSeen = {}
for x = -40, 40, 3 do
	for y = 0, 50, 5 do
		local key = Grid.key(x, y, 7)
		local layer, r, g, b = RockStyle.look(key, y, 50)
		local again, r2, g2, b2 = RockStyle.look(key, y, 50)
		check(layer == again and r == r2 and g == g2 and b == b2, "uncovered rock keeps its appearance")
		check(r >= 0 and r <= 255 and g >= 0 and g <= 255 and b >= 0 and b <= 255, "colours stay in range")
		layersSeen[layer] = true
	end
end
check(RockStyle.look(Grid.key(0, 49, 0), 49, 50) == RockStyle.SNOW, "the summit surface is snow")
check(RockStyle.look(Grid.key(0, 1, 0), 1, 50) == RockStyle.GRASS, "the foothill surface is grass")
check(RockStyle.look(Grid.key(0, 0, 0), 2, 50) == RockStyle.DIRT, "grass has a dirt layer beneath")
local deep = RockStyle.look(Grid.key(0, 20, 0), 45, 50)
check(deep == RockStyle.ROCK or deep == RockStyle.SLATE, "inside the mountain is rock")
check(layersSeen[RockStyle.SNOW] and layersSeen[RockStyle.GRASS] and layersSeen[RockStyle.CRAG], "the surface mixes snow, grass and crags")
-- Shapes slope towards open air only where that keeps the shell closed.
local slope = Grid.blank()
for x = -3, 3 do
	for z = -3, 3 do
		for y = 0, 3 - math.max(math.abs(x), math.abs(z)) do slope.solid[Grid.key(x, y, z)] = true end
	end
end
check(RockStyle.shape(slope, Grid.key(0, 3, 0)) >= 6, "a lone summit cell is a corner spire")
check(RockStyle.shape(slope, Grid.key(1, 2, 0)) == RockStyle.WEDGE[1], "a ridge slopes down towards open air (+X)")
check(RockStyle.shape(slope, Grid.key(0, 2, -1)) == RockStyle.WEDGE[4], "a ridge slopes down towards open air (-Z)")
check(RockStyle.shape(slope, Grid.key(1, 2, 1)) == RockStyle.CORNER[1], "an outside corner uses a corner wedge")
check(RockStyle.shape(slope, Grid.key(0, 0, 0)) == RockStyle.BLOCK, "covered cells are blocks")
check(RockStyle.kind(1) == 1 and RockStyle.kind(4) == 2 and RockStyle.kind(9) == 3, "shape kinds")
-- Column runs round-trip exactly, in any order, across chunk boundaries.
local cells, expected, order = {}, 0, {}
for x = -20, 20 do
	for z = -20, 20, 3 do
		for y = 0, (x * 7 + z * 3) % 13 do
			if (x + y) % 5 ~= 0 then
				table.insert(order, Grid.key(x, y, z))
				expected += 1
			end
		end
	end
end
for i = #order, 2, -1 do
	local j = (i * 7919) % i + 1
	order[i], order[j] = order[j], order[i]
end
table.insert(order, order[1]) -- duplicates are harmless
local limit = MountainCodec.MaxRuns
MountainCodec.MaxRuns = 50
local chunks = MountainCodec.encode(order)
MountainCodec.MaxRuns = limit
check(#chunks > 1, "large change lists split into several chunks")
local decoded = 0
for _, chunk in chunks do
	MountainCodec.decode(chunk, function(key)
		if not cells[key] then decoded += 1 end
		cells[key] = true
	end)
end
local allPresent = true
for _, key in order do if not cells[key] then allPresent = false end end
check(allPresent and decoded == expected and MountainCodec.count(chunks) == expected, "encoded cells decode to exactly the same set")
local tops = { [5] = 17, [65535] = 3, [300] = 0 }
local seenTops = {}
for _, chunk in MountainCodec.encodePairs(tops) do
	MountainCodec.decodePairs(chunk, function(column, top) seenTops[column] = top end)
end
check(seenTops[5] == 17 and seenTops[65535] == 3 and seenTops[300] == 0, "column tops round-trip")

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
-- Digging a loose rock by hand takes only rock joined to it, never rock elsewhere.
local loose = Grid.new(1234, 1, rand)
local summit = loose.order[1]
for _, key in loose.order do
	if select(2, Grid.coords(key)) > select(2, Grid.coords(summit)) then summit = key end
end
local sx, sy, sz = Grid.coords(summit)
for _, d in { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } } do
	local neighbour = Grid.key(sx + d[1], sy + d[2], sz + d[3])
	if loose:isSolid(neighbour) then loose:remove(neighbour) end
end
local before = 0
for _ in loose.solid do before += 1 end
check(#loose:blast(25, summit, nil, nil, true) == 1, "digging a lone rock breaks just that rock")
local after = 0
for _ in loose.solid do after += 1 end
check(after == before - 1, "nothing else on the mountain went with it")
local growth = Grid.new(5000, 2, rand)
local gemCell = growth:carveHiddenCell()
local original = growth.total
local checkpoints = 0
local function checkpoint() checkpoints += 1 end
local added = growth:grow(2000, original + 3000, checkpoint)
check(#added == 2000 and growth:remaining() == original + 2000, "growth exceeds the original mountain by the exact gifted amount")
check(not growth:isSolid(gemCell), "new growth cannot fill the sealed diamond cell")
check(checkpoints > 0, "growth provides checkpoints for frame pacing")
local growthConsistent = true
local growthSeen = {}
for _, key in growth.order do
	if growthSeen[key] then growthConsistent = false end
	growthSeen[key] = true
	if growth:isSolid(key) and (growth.exposedIndex[key] ~= nil) ~= growth:isExposed(key) then growthConsistent = false end
end
check(growthConsistent, "grown topology has unique cells and an accurate exposed surface")
check(#growth:grow(10000, original + 3000, checkpoint) == 1000, "repeated growth respects the configured size limit")
check(#growth:grow(1, original + 3000) == 0, "growth at the limit is a no-op")
local beforeMiningGrowth = growth:remaining()
local minedGrowth = growth:blast(1200, nil, checkpoint)
check(#minedGrowth == 1200 and growth:remaining() == beforeMiningGrowth - 1200, "grown rocks remain mineable with exact accounting")
check(growth.growthHeap == nil, "mining invalidates the cached growth frontier")
check(#growth:restore(1200, nil, checkpoint) == 1200, "mined growth is restored before adding new cells")
check(growth:remaining() == growth.total and not growth:isSolid(gemCell), "grow dig refill cycle preserves the diamond and stone count")
local paced = Grid.new(1234, 1, function(a, _b) return a or 0.5 end)
local plain = Grid.new(1234, 1, function(a, _b) return a or 0.5 end)
paced:grow(2000, 5000, checkpoint)
plain:grow(2000, 5000)
local same = paced.total == plain.total
for key in paced.solid do if not plain.solid[key] then same = false end end
check(same, "frame pacing does not change growth results")
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

-- Gift keybinds: only free keys, never the game's own or Roblox's zoom keys.
for _, key in { "K", "One", "Zero", "F6", "Z" } do
	check(Keybinds.allowed(key), "a gift can go on " .. key)
end
for _, key in { "W", "A", "S", "D", "Space", "E", "G", "H", "P", "Y", "I", "O", "Slash", "Escape", "", 5 } do
	check(not Keybinds.allowed(key), "keys the game uses stay free: " .. tostring(key))
end
check(Keybinds.label("One") == "1" and Keybinds.label("Zero") == "0" and Keybinds.label("K") == "K", "keys are shown as on the keyboard")

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
	error("tests failed")
end
