--!strict
-- Smooth woodland landscape and a warm cabin camp, built once. Decorative parts never participate in
-- mining raycasts or physics; the central arena stays clear for mountain growth.
local Lighting = game:GetService("Lighting")
local Scenery = {}
local random = Random.new(4207)
local function piece(parent: Instance, name: string, size: Vector3, frame: CFrame, colour: Color3, material: Enum.Material, kind: string?): BasePart
 local p = Instance.new(kind or "Part") :: BasePart
 p.Name = name
 p.Size = size
 p.CFrame = frame
 p.Color = colour
 p.Material = material
 p.Anchored = true
 p.CanCollide = false
 p.CanQuery = false
 p.CanTouch = false
 p.CastShadow = true
 p.Parent = parent
 return p
end
local function solid(p: BasePart): BasePart
 p.CanCollide = true
 return p
end
local function lantern(parent: Instance, at: Vector3)
 piece(parent,"LanternPost",Vector3.new(0.3,5,0.3),CFrame.new(at+Vector3.new(0,2.5,0)),Color3.fromRGB(83,67,53),Enum.Material.Wood)
 piece(parent,"LanternCap",Vector3.new(1,0.18,1),CFrame.new(at+Vector3.new(0,5.25,0)),Color3.fromRGB(42,53,57),Enum.Material.Metal)
 local lamp=piece(parent,"WarmLantern",Vector3.new(0.5,0.7,0.5),CFrame.new(at+Vector3.new(0,4.8,0)),Color3.fromRGB(255,201,122),Enum.Material.Neon)
 local light=Instance.new("PointLight")
 light.Color=lamp.Color; light.Range=13; light.Brightness=0.8; light.Shadows=false; light.Parent=lamp
end
local function rounded(parent: Instance, name: string, size: Vector3, frame: CFrame, colour: Color3, material: Enum.Material): BasePart
 local p=piece(parent,name,size,frame,colour,material)
 local roundPart = p :: Part
 roundPart.Shape=Enum.PartType.Ball
 return p
end
local function woodlandTree(parent: Instance, at: Vector3, height: number)
 local model=Instance.new("Model"); model.Name="WoodlandTree"; model.Parent=parent
 local trunk=piece(model,"Bark",Vector3.new(height*0.72,0.8,0.8),CFrame.new(at+Vector3.new(0,height*0.36,0))*CFrame.Angles(0,0,math.pi/2),Color3.fromRGB(86,77,62),Enum.Material.Wood)
 local trunkPart = trunk :: Part
 trunkPart.Shape=Enum.PartType.Cylinder
 -- Irregular overlapping leaf masses, with branching silhouettes and textured
 -- foliage rather than stacked geometric tiers. Variation stays deterministic.
 for i=1,13 do
  local angle=i*2.39996+random:NextNumber(-0.3,0.3)
  local spread=height*random:NextNumber(0.12,0.27)
  local level=height*random:NextNumber(0.58,0.89)
  local width=height*random:NextNumber(0.22,0.37)
  local shade=random:NextInteger(-9,12)
  rounded(model,"Foliage",Vector3.new(width,width*0.65,width*0.85),CFrame.new(at+Vector3.new(math.cos(angle)*spread,level,math.sin(angle)*spread))*CFrame.Angles(random:NextNumber(-0.3,0.3),angle,0),Color3.fromRGB(66+shade,88+shade,52+shade),Enum.Material.LeafyGrass)
 end
end
local function landscape(terrain: Terrain, lake: Vector3, camp: Vector3, radius: number)
 -- Smooth connected terrain, generated in small voxel chunks once on startup.
 -- No spherical hills, wedge mountains, square lake cuts or tiled part paths.
 local resolution=4
 for cx=-320,319,64 do
  for cz=-320,319,64 do
   local materials,occupancies={},{}
   for ix=1,16 do
    materials[ix]={}; occupancies[ix]={}
    for iy=1,40 do materials[ix][iy]={}; occupancies[ix][iy]={} end
    for iz=1,16 do
     local x,z=cx+(ix-0.5)*4,cz+(iz-0.5)*4
     local distance=math.sqrt(x*x+z*z)
     local fade=math.clamp((distance-radius)/65,0,1)
     fade=fade*fade*(3-2*fade)
     local broad=math.noise(x/135,z/135,12)*22+math.noise(x/49,z/49,8)*7+math.noise(x/19,z/19,4)*1.5
     local ridge=math.clamp((distance-160)/125,0,1)
     local height=fade*(7+broad+ridge*(48+math.noise(x/83,z/83,17)*35))
     local campDistance=math.sqrt((x-camp.X)^2+(z-camp.Z)^2)
     height*=math.clamp((campDistance-27)/22,0,1)
     local shore=math.sqrt(((x-lake.X)/35)^2+((z-lake.Z)/27)^2)+math.noise(x/16,z/16,3)*0.08
     if shore<1.25 then height=math.min(height,-9+math.clamp(shore,0,1.25)^3*8) end
     if distance<radius then height=0 end
     local pathX=math.sin(math.clamp((camp.Z-z)/(camp.Z-26),0,1)*math.pi)*4
     local path=z>=26 and z<=camp.Z+5 and math.abs(x-pathX)<3.3+math.noise(z/7,0,3)*0.8
     local surface=if distance<radius then Enum.Material.LeafyGrass elseif shore<1.2 then Enum.Material.Ground elseif path or campDistance<10 then Enum.Material.Ground elseif height>65 then Enum.Material.Rock else Enum.Material.Grass
     for iy=1,40 do
      local y=-24+(iy-0.5)*4
      local occupancy=math.clamp((height-y)/4+0.5,0,1)
      local material=if y<height-5 then Enum.Material.Rock else surface
      if shore<1.12 and y>height and y<1 then
       local water=math.clamp((-1-y)/4+0.5,0,1)
       if water>occupancy then material=Enum.Material.Water; occupancy=water end
      end
      materials[ix][iy][iz]=if occupancy>0 then material else Enum.Material.Air
      occupancies[ix][iy][iz]=occupancy
     end
    end
   end
   terrain:WriteVoxels(Region3.new(Vector3.new(cx,-24,cz),Vector3.new(cx+64,136,cz+64)),resolution,materials,occupancies)
   task.wait()
  end
 end
end
function Scenery.build(mountainRadius: number, spawnPosition: Vector3)
 -- Animated grass is enabled in the place/project: Decoration and GrassLength
 -- are editor-only properties. LeafyGrass keeps the central arena blade-free.
 local terrain=workspace.Terrain
 local folder=Instance.new("Folder"); folder.Name="Scenery"; folder.Parent=workspace
 local clearRadius=math.max(mountainRadius+14,55)
 local camp=Vector3.new(spawnPosition.X,0,spawnPosition.Z)
 local lake=Vector3.new(clearRadius+72,0,camp.Z+15)
 local params=RaycastParams.new(); params.FilterType=Enum.RaycastFilterType.Include; params.FilterDescendantsInstances={terrain}
 local function ground(x: number,z: number): Vector3
  local hit=workspace:Raycast(Vector3.new(x,180,z),Vector3.new(0,-220,0),params)
  return if hit then hit.Position else Vector3.new(x,0,z)
 end
 local function clear(at: Vector3): boolean
  return Vector3.new(at.X,0,at.Z).Magnitude < clearRadius
   or (Vector3.new(at.X,0,at.Z)-camp).Magnitude<25
   or (Vector3.new(at.X,0,at.Z)-lake).Magnitude<40
 end
 terrain:SetMaterialColor(Enum.Material.Grass,Color3.fromRGB(103,134,91))
 terrain:SetMaterialColor(Enum.Material.Ground,Color3.fromRGB(125,111,88))
 terrain:SetMaterialColor(Enum.Material.Rock,Color3.fromRGB(106,119,122))
 terrain:FillBlock(CFrame.new(0,-8,0),Vector3.new(1400,16,1400),Enum.Material.Grass)
 landscape(terrain,lake,camp,clearRadius)
 terrain.WaterColor=Color3.fromRGB(58,94,83)
 terrain.WaterTransparency=0.45; terrain.WaterReflectance=0.3
 terrain.WaterWaveSize=0.08; terrain.WaterWaveSpeed=3
 -- A lakeside timber dock, supported above the shallow water.
 local dock=lake+Vector3.new(-34,0.5,0)
 for i=0,11 do
  solid(piece(folder,"DockPlank",Vector3.new(1.6,0.35,7),CFrame.new(dock+Vector3.new(i*1.65,0,0)),Color3.fromRGB(137+i%3*7,106+i%3*5,76),Enum.Material.WoodPlanks))
 end
 for _,x in {0,16} do
  for _,z in {-3.2,3.2} do
   piece(folder,"DockPost",Vector3.new(0.6,6,0.6),CFrame.new(dock+Vector3.new(x,-1.8,z)),Color3.fromRGB(86,74,58),Enum.Material.Wood)
  end
 end
 lantern(folder,dock+Vector3.new(0,0,-4.2))
 -- Ground sampling prevents trees and flowers floating over the rolling hills.
 local planted=0
 for _=1,600 do
  if planted>=72 then break end
  local angle=random:NextNumber(0,math.pi*2)
  local distance=random:NextNumber(clearRadius+15,260)
  local at=ground(math.cos(angle)*distance,math.sin(angle)*distance)
  if not clear(at) then woodlandTree(folder,at,random:NextNumber(17,29)); planted+=1 end
 end
 local flowerColours={Color3.fromRGB(198,167,215),Color3.fromRGB(248,215,135),Color3.fromRGB(235,231,208)}
 for _=1,95 do
  local angle=random:NextNumber(0,math.pi*2)
  local distance=random:NextNumber(clearRadius+5,145)
  local at=ground(math.cos(angle)*distance,math.sin(angle)*distance)
  if not clear(at) then
   local height=random:NextNumber(0.45,1.1)
   rounded(folder,"MeadowLeaves",Vector3.new(1.1,height,0.7),CFrame.new(at+Vector3.new(0,height/2,0))*CFrame.Angles(0,angle,0),Color3.fromRGB(92,125,77),Enum.Material.LeafyGrass)
   rounded(folder,"Wildflowers",Vector3.new(0.6,0.18,0.5),CFrame.new(at+Vector3.new(0,height,0)),flowerColours[random:NextInteger(1,3)],Enum.Material.SmoothPlastic)
  end
 end
 for _=1,32 do
  local angle=random:NextNumber(0,math.pi*2)
  local distance=random:NextNumber(clearRadius+8,180)
  local at=ground(math.cos(angle)*distance,math.sin(angle)*distance)
  if not clear(at) then
   local size=random:NextNumber(2,5)
   rounded(folder,"WeatheredBoulder",Vector3.new(size,size*0.65,size*0.8),CFrame.new(at+Vector3.new(0,size*0.22,0))*CFrame.Angles(0,angle,0.15),Color3.fromRGB(126,139,130),Enum.Material.Rock)
  end
 end
 -- A timber cabin gives the campsite a sheltered, lived-in focal point.
 local cabin=camp+Vector3.new(-18,0,15)
 local wood=Color3.fromRGB(105,81,60)
 solid(piece(folder,"CabinDeck",Vector3.new(13,0.5,12),CFrame.new(cabin+Vector3.new(0,0.35,-1)),wood,Enum.Material.WoodPlanks))
 for _,x in {-5,5} do
  solid(piece(folder,"CabinSide",Vector3.new(0.35,7,9),CFrame.new(cabin+Vector3.new(x,3.8,0)),wood,Enum.Material.WoodPlanks))
 end
 solid(piece(folder,"CabinBack",Vector3.new(10,7,0.35),CFrame.new(cabin+Vector3.new(0,3.8,4.5)),wood,Enum.Material.WoodPlanks))
 for _,x in {-3.5,3.5} do
  solid(piece(folder,"CabinFront",Vector3.new(3,7,0.35),CFrame.new(cabin+Vector3.new(x,3.8,-4.5)),wood,Enum.Material.WoodPlanks))
  piece(folder,"WindowFrame",Vector3.new(2.3,2.7,0.2),CFrame.new(cabin+Vector3.new(x,4.3,-4.75)),Color3.fromRGB(60,57,48),Enum.Material.Wood)
  piece(folder,"WarmWindow",Vector3.new(1.95,2.3,0.12),CFrame.new(cabin+Vector3.new(x,4.3,-4.9)),Color3.fromRGB(214,159,85),Enum.Material.Neon)
  piece(folder,"WindowCrossbar",Vector3.new(1.95,0.12,0.15),CFrame.new(cabin+Vector3.new(x,4.3,-5)),wood,Enum.Material.Wood)
  piece(folder,"WindowMullion",Vector3.new(0.12,2.3,0.15),CFrame.new(cabin+Vector3.new(x,4.3,-5)),wood,Enum.Material.Wood)
 end
 for side=-1,1,2 do
  piece(folder,"SlateRoof",Vector3.new(6.4,0.25,11),CFrame.new(cabin+Vector3.new(side*2.9,8.1,0))*CFrame.Angles(0,0,-side*0.35),Color3.fromRGB(58,65,63),Enum.Material.Slate)
 end
 local chimney=piece(folder,"StoneChimney",Vector3.new(1.4,4,1.5),CFrame.new(cabin+Vector3.new(3,8.5,2)),Color3.fromRGB(102,98,88),Enum.Material.Cobblestone)
 local smoke=Instance.new("Smoke"); smoke.Color=Color3.fromRGB(153,153,143); smoke.Opacity=0.08; smoke.Size=2.5; smoke.RiseVelocity=2; smoke.Parent=chimney
 piece(folder,"DoorLintel",Vector3.new(4,1.3,0.4),CFrame.new(cabin+Vector3.new(0,6.65,-4.5)),wood,Enum.Material.Wood)
 solid(piece(folder,"PorchStep",Vector3.new(4,0.3,2),CFrame.new(cabin+Vector3.new(0,0.15,-7)),wood,Enum.Material.WoodPlanks))
 piece(folder,"WovenRug",Vector3.new(5,0.04,5),CFrame.new(cabin+Vector3.new(0,0.62,0)),Color3.fromRGB(148,92,65),Enum.Material.Fabric)
 lantern(folder,cabin+Vector3.new(4,0,-5.5))
 -- Sagging festoon wire and small amber bulbs, without a light per bulb.
 for i=0,14 do
  local t=i/14
  local at=camp+Vector3.new(-10+t*20,7-1.4*math.sin(t*math.pi),-6)
  piece(folder,"FestoonWire",Vector3.new(1.5,0.035,0.035),CFrame.new(at),Color3.fromRGB(48,44,35),Enum.Material.Metal)
  if i%2==0 then rounded(folder,"FestoonBulb",Vector3.new(0.18,0.27,0.18),CFrame.new(at+Vector3.new(0,-0.2,0)),Color3.fromRGB(255,191,102),Enum.Material.Neon) end
 end
 for _,x in {-10,10} do piece(folder,"FestoonPost",Vector3.new(0.2,7,0.2),CFrame.new(camp+Vector3.new(x,3.5,-6)),wood,Enum.Material.Wood) end
 local fireAt=camp+Vector3.new(12,0,5)
 for i=1,10 do
  local angle=i/10*math.pi*2
  rounded(folder,"FireRingStone",Vector3.new(0.85,0.55,0.7),CFrame.new(fireAt+Vector3.new(math.cos(angle)*1.6,0.28,math.sin(angle)*1.6))*CFrame.Angles(0,-angle,0),Color3.fromRGB(115,121,121),Enum.Material.Slate)
 end
 local embers=piece(folder,"Embers",Vector3.new(1.8,0.2,1.8),CFrame.new(fireAt+Vector3.new(0,0.2,0)),Color3.fromRGB(236,133,60),Enum.Material.Neon)
 local fire=Instance.new("Fire"); fire.Size=3; fire.Heat=4; fire.Parent=embers
 local glow=Instance.new("PointLight"); glow.Color=Color3.fromRGB(255,180,100); glow.Range=14; glow.Brightness=1.2; glow.Shadows=false; glow.Parent=embers
 for _,offset in {Vector3.new(-4,0,0),Vector3.new(4,0,0),Vector3.new(0,0,4)} do
  local seat=CFrame.new(fireAt+offset)*CFrame.Angles(0,if offset.X~=0 then math.pi/2 else 0,0)
  solid(piece(folder,"CampBench",Vector3.new(3.6,0.35,1.2),seat*CFrame.new(0,1,0),Color3.fromRGB(128,99,69),Enum.Material.WoodPlanks))
  for _,side in {-1.3,1.3} do piece(folder,"BenchLeg",Vector3.new(0.35,0.85,0.85),seat*CFrame.new(side,0.425,0),wood,Enum.Material.Wood) end
  piece(folder,"SeatPad",Vector3.new(2.8,0.12,1.1),seat*CFrame.new(0,1.24,0),Color3.fromRGB(121,100,78),Enum.Material.Fabric)
 end
 lantern(folder,camp+Vector3.new(-9,0,-8)); lantern(folder,camp+Vector3.new(9,0,-8))
 Lighting.ClockTime=17.1; Lighting.Brightness=2
 Lighting.GlobalShadows=true; Lighting.ShadowSoftness=0.45
 Lighting.Ambient=Color3.fromRGB(69,76,82); Lighting.OutdoorAmbient=Color3.fromRGB(111,119,119)
 Lighting.ColorShift_Top=Color3.fromRGB(25,15,6)
 Lighting.EnvironmentDiffuseScale=0.65; Lighting.EnvironmentSpecularScale=0.7
 local atmosphere=Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
 atmosphere.Density=0.3; atmosphere.Offset=0.15; atmosphere.Color=Color3.fromRGB(213,228,232)
 atmosphere.Decay=Color3.fromRGB(157,176,189); atmosphere.Haze=1.8; atmosphere.Glare=0.15; atmosphere.Parent=Lighting
 local grade=Instance.new("ColorCorrectionEffect"); grade.Name="AlpineColour"
 grade.Brightness=0.015; grade.Contrast=0.08; grade.Saturation=0.3; grade.TintColor=Color3.fromRGB(255,248,237); grade.Parent=Lighting
 local bloom=Instance.new("BloomEffect"); bloom.Intensity=0.12; bloom.Size=18; bloom.Threshold=1.6; bloom.Parent=Lighting
 local clouds=terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
 clouds.Cover=0.38; clouds.Density=0.45; clouds.Color=Color3.fromRGB(245,241,230); clouds.Parent=terrain
 local sky=Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky")
 sky.SunAngularSize=4; sky.CelestialBodiesShown=true; sky.Parent=Lighting
end
return Scenery
