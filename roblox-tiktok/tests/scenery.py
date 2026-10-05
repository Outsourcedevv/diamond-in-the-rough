from pathlib import Path
import subprocess, sys
root=Path(__file__).resolve().parents[1]
source=(root/'src/server/Scenery.luau').read_text(encoding='utf-8')
prefix=r'''
local vector={}
vector.__index=function(v,k) if k=="Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end end
local function vec(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0},vector) end
vector.__add=function(a,b) return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vector.__sub=function(a,b) return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
local Vector3={new=vec,zero=vec()}
local cf={}
cf.__mul=function(a,b) return setmetatable({Position=a.Position+b.Position},cf) end
local CFrame={new=function(x,y,z) return setmetatable({Position=if type(x)=="table" then x else vec(x,y,z)},cf) end,Angles=function() return setmetatable({Position=vec()},cf) end}
local Color3={fromRGB=function(r,g,b) return {R=r/255,G=g/255,B=b/255} end}
local Enum={Material=setmetatable({},{__index=function(_,k) return k end}),RaycastFilterType={Include=1}}
local instances={}
local function object(kind)
 local p={ClassName=kind,FindFirstChildOfClass=function() return nil end}
 table.insert(instances,p); return p
end
local Instance={new=object}
local Lighting=object("Lighting")
local game={GetService=function() return Lighting end}
local Random={new=function() return {NextNumber=function(_,a,b) return if a then (a+b)/2 else 0.5 end,NextInteger=function(_,a,b) return math.floor((a+b)/2) end} end}
local RaycastParams={new=function() return {} end}
local terrain=object("Terrain")
terrain.SetMaterialColor=function() end
local terrainCalls=0
for _,method in {"FillBlock","FillBall","FillWedge"} do
 terrain[method]=function() terrainCalls+=1 end
end
local workspace={Terrain=terrain,Raycast=function(_,at) return {Position=vec(at.X,0,at.Z)} end}
local Scenery=(function()
'''
suffix=r'''
end)()
Scenery.build(26.4,Vector3.new(0,0.5,56.4))
local parts,lights=0,0
for _,p in instances do
 if p.ClassName=="Part" or p.ClassName=="WedgePart" or p.ClassName=="CornerWedgePart" then
  parts+=1
  assert(p.Anchored and p.CanQuery==false and p.CanTouch==false,"scenery must not interfere with mining/physics")
  assert(p.Size.X>0 and p.Size.Y>0 and p.Size.Z>0)
 elseif p.ClassName=="PointLight" then lights+=1;assert(not p.Shadows) end
end
assert(parts<1600,"decoration count must remain bounded")
assert(lights==4 and terrainCalls>50)
assert(Lighting.ClockTime==16.4)
print(string.format("PASS: scenery builds, %d static parts, %d local lights, mining queries disabled",parts,lights))
'''
generated=root/'tests/scenery.generated.luau'
try:
 generated.write_text(prefix+source+suffix,encoding='utf-8')
 subprocess.run([sys.argv[1] if len(sys.argv)>1 else 'luau',str(generated)],check=True)
finally:
 generated.unlink(missing_ok=True)
