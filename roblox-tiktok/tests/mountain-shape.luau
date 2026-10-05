local Grid = require("../src/server/Grid")
local function rand(a,b) return if a then math.floor((a+b)/2) else 0.5 end
for _, count in {1, 1000, 25000, 250000} do
 for _, seed in {0, 3.7, 91} do
  local grid = Grid.new(count, seed, rand)
  assert(grid.total == count, "shape must preserve exact rock budget")
  local top, footprint = 0, 0
  for _, key in grid.order do
   local x,y,z = Grid.coords(key)
   if y==0 then footprint+=1 end
   if y==grid.height-1 then top+=1 end
   if y>0 then assert(grid:isSolid(Grid.key(x,y-1,z)), "no floating rocks") end
  end
  if count>=25000 then
   assert(grid.height/grid.radius>0.7, "summit should rise above broad slopes")
   assert(top/footprint<0.03, "summit must remain a small fraction of footprint")
  end
  print(string.format("%d rocks seed %.1f: height %d, radius %d, flat summit %.2f%%",count,seed,grid.height,grid.radius,top/footprint*100))
 end
end
