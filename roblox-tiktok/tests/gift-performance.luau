-- Reports CPU intervals between cooperative checkpoints; not a Roblox FPS test.
local Grid = require("../src/shared/Grid")
local function rand(a, b) return if a then math.floor((a + b) / 2) else 0.5 end
local grid = Grid.new(250000, 3.7, rand)
grid:carveHiddenCell()
local function measure(label, operation)
 local start, previous, longest, checks = os.clock(), os.clock(), 0, 0
 local function checkpoint()
  local now = os.clock()
  longest = math.max(longest, now - previous)
  previous = now
  checks += 1
 end
 operation(checkpoint)
 longest = math.max(longest, os.clock() - previous)
 print(string.format("%s: %.3f s total CPU, %d checkpoints, %.2f ms longest interval", label, os.clock()-start, checks, longest*1000))
 assert(checks > 0, label .. " must allow frame pacing")
end
measure("100,000-rock blast", function(checkpoint) grid:blast(100000, nil, checkpoint) end)
measure("100,000-rock restore", function(checkpoint) grid:restore(100000, {x=0,z=0,radius=10}, checkpoint) end)
local before = grid:remaining()
measure("100,000 new growth rocks", function(checkpoint) grid:grow(100000, 1500000, checkpoint) end)
assert(grid:remaining() == before+100000)
