from pathlib import Path
import subprocess, sys
root=Path(__file__).resolve().parents[1]
prefix=r'''
local Grid = require("../src/server/Grid")
local RockStyle = require("../src/server/RockStyle")
local vector = {}
vector.__index = function(v,k)
 if k == "Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
 if k == "Unit" then return v / v.Magnitude end
end
local function vec(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0},vector) end
vector.__add=function(a,b) return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vector.__sub=function(a,b) return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vector.__mul=function(a,b) return vec(a.X*b,a.Y*b,a.Z*b) end
vector.__div=function(a,b) return vec(a.X/b,a.Y/b,a.Z/b) end
local Vector3={new=vec}
local cf={}
cf.__mul=function(a,b) return setmetatable({Position=a.Position+b.Position},cf) end
local CFrame={new=function(v) return setmetatable({Position=v or vec()},cf) end,Angles=function() return setmetatable({Position=vec()},cf) end}
local Color3={new=function(r,g,b) return {R=r,G=g,B=b} end,fromRGB=function(r,g,b) return {R=r/255,G=g/255,B=b/255} end}
local Enum={SurfaceType={Smooth=0},Material={Snow=0,Grass=1,Rock=2,Slate=3}}
local instances={}
local Instance={new=function(kind)
 local attrs={}
 local p={ClassName=kind,SetAttribute=function(_,k,v) attrs[k]=v end,GetAttribute=function(_,k) return attrs[k] end}
 p.Destroy=function(self) self.destroyed=true;self.Parent=nil end
 setmetatable(p,{__index=function(self,k) if k=="Position" then return self.CFrame.Position end end})
 table.insert(instances,p)
 return p
end}
local Random={new=function() return {NextNumber=function(_,a,b) return if a then (a+b)/2 else 0.5 end,NextInteger=function(_,a,b) return math.floor((a+b)/2) end} end}
local Debris={AddItem=function(_,p) p:Destroy() end}
local task={wait=function() end}
local Mountain=(function()
'''
s=(root/'src/server/Mountain.luau').read_text().replace('local Debris = game:GetService("Debris")','').replace('local Grid = require(script.Parent.Grid)','').replace('local RockStyle = require(script.Parent.RockStyle)','')
suffix=r'''
end)()
local mountain=Mountain.new({},25000,1,function() end,false)
mountain:blast(10000)
local start=mountain:remaining()
local removedKeys=table.clone(mountain.grid.removedOrder)
local incremental=false
local checks=0
local restored=mountain:restore(10000,nil,50000,function()
 checks+=1
 if mountain:remaining() > start and mountain:remaining() < start+10000 then
  for _,key in removedKeys do
   local part=mountain.parts[key]
   if part and not part.destroyed and part.Parent == mountain.folder and part.Transparency == 0 then incremental=true;break end
  end
 end
end)
assert(restored==10000 and mountain:remaining()==start+10000)
local function verify()
 for _,key in mountain.grid.exposedList do
  local p=mountain.parts[key]
  assert(p and not p.destroyed and p.Parent==mountain.folder and p.Transparency==0, "missing visible surface rock")
  assert(p.CanCollide and not p:GetAttribute("BackingRock"), "surface must be usable")
 end
 assert(not mountain.grid:isSolid(mountain.diamondKey),"diamond cell remains empty")
end
verify()
local grown=mountain:restore(4096,nil,50000)
assert(grown==4096)
verify()
assert(incremental and checks>0)
local x,y,z=Grid.coords(mountain.diamondKey)
assert(y>=1 and y<=mountain.grid.height*0.35 and x*x+z*z <= (mountain.grid.radius*0.3)^2)
print("PASS: rendered restoration, growth, exposed collision, reserved lower central diamond and checkpoints")
'''
generated=root/'tests/rebuild-rendering.generated.luau'
try:
 generated.write_text(prefix+s+suffix, encoding='utf-8')
 subprocess.run([sys.argv[1] if len(sys.argv)>1 else 'luau', str(generated)], check=True)
finally:
 generated.unlink(missing_ok=True)
