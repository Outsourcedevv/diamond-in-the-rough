local Grid = require("../src/server/Grid")
local function rand(a,b) return if a then math.floor((a+b)/2) else 0.5 end
local grid = Grid.new(25000,3.7,rand)
local diamond = grid:carveHiddenCell()
local dx,dy,dz = Grid.coords(diamond)
grid:blast(20000)
local missing = table.clone(grid.removedOrder)
local function distance(key)
 local x,y,z=Grid.coords(key)
 return (x-dx)^2+(y-dy)^2+(z-dz)^2
end
local restored=grid:restore(1000,{x=dx,y=dy,z=dz})
assert(#restored==1000)
for i=2,#restored do assert(distance(restored[i])>=distance(restored[i-1]),"must refill nearest first") end
local farthest=distance(restored[#restored])
for _,key in missing do
 if not grid:isSolid(key) then assert(distance(key)>=farthest,"must not skip closer holes") end
end
local nextBatch=grid:restore(1000,{x=dx,y=dy,z=dz})
assert(distance(nextBatch[1])>=farthest)
assert(not grid:isSolid(diamond),"diamond cavity must remain reserved")
print("PASS: rebuild fills from diamond outward, including consecutive gifts")
