--!strict
-- Static alpine scenery, built once. Decorative parts never participate in
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
 p.CastShadow = false
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
local function pine(parent: Instance, at: Vector3, height: number)
 local model=Instance.new("Model"); model.Name="AlpinePine"; model.Parent=parent
 piece(model,"Trunk",Vector3.new(0.65,height*0.65,0.65),CFrame.new(at+Vector3.new(0,height*0.325,0)),Color3.fromRGB(99,76,57),Enum.Material.Wood)
 local yaw=random:NextNumber(0,math.pi*2)
 local greens={Color3.fromRGB(40,83,73),Color3.fromRGB(52,102,84),Color3.fromRGB(70,119,93)}
 for tier=0,2 do
  local width=height*(0.48-tier*0.105)
  local frame=CFrame.new(at+Vector3.new(0,height*(0.37+tier*0.21),0))*CFrame.Angles(0,yaw,0)
  for side=0,3 do
   piece(model,"Needles",Vector3.new(width,height*0.36,width*0.5),frame*CFrame.Angles(0,side*math.pi/2,0)*CFrame.new(0,0,width*0.25),greens[tier+1],Enum.Material.SmoothPlastic,"WedgePart")
  end
 end
end
function Scenery.build(mountainRadius: number, spawnPosition: Vector3)
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
 -- Broad hills frame the arena without placing terrain inside its growth area.
 for i=1,22 do
  local angle=i/22*math.pi*2
  local distance=random:NextNumber(160,280)
  local radius=random:NextNumber(35,62)
  terrain:FillBall(Vector3.new(math.cos(angle)*distance,-radius*0.67,math.sin(angle)*distance),radius,Enum.Material.Grass)
 end
 -- Overlapping pointed ridges produce an irregular skyline rather than spheres.
 for i=1,16 do
  local angle=i/16*math.pi*2+random:NextNumber(-0.08,0.08)
  local distance=random:NextNumber(350,460)
  local height=random:NextNumber(90,175)
  local base=CFrame.new(math.cos(angle)*distance,0,math.sin(angle)*distance)*CFrame.Angles(0,angle+0.4,0)
  for side=0,1 do
   local rotation=CFrame.Angles(0,side*math.pi,0)
   terrain:FillWedge(base*rotation*CFrame.new(0,height/2,height*0.25),Vector3.new(height*0.8,height,height*0.5),Enum.Material.Rock)
   terrain:FillWedge(base*rotation*CFrame.new(0,height*0.86,height*0.07),Vector3.new(height*0.225,height*0.28,height*0.14),Enum.Material.Snow)
  end
 end
 -- Three overlapping basins give the lake a curved shoreline and shallow banks.
 for _,offset in {Vector3.new(-13,0,0),Vector3.new(8,0,3),Vector3.new(0,0,-12)} do
  local at=lake+offset
  terrain:FillBall(at+Vector3.new(0,-10,0),26,Enum.Material.Sand)
  terrain:FillBall(at+Vector3.new(0,4,0),25,Enum.Material.Air)
  terrain:FillBall(at+Vector3.new(0,-19,0),23,Enum.Material.Water)
  -- Keep all water below the surrounding ground level.
  terrain:FillBlock(CFrame.new(at+Vector3.new(0,16,0)),Vector3.new(48,34,48),Enum.Material.Air)
 end
 terrain.WaterColor=Color3.fromRGB(48,145,151)
 terrain.WaterTransparency=0.35; terrain.WaterReflectance=0.25
 terrain.WaterWaveSize=0.12; terrain.WaterWaveSpeed=4
 -- A gently bending, pale gravel path leads from camp into the digging area.
 for i=0,18 do
  local t=i/18
  local z=camp.Z*(1-t)+(mountainRadius+3)*t
  local x=math.sin(t*math.pi)*4
  piece(folder,"GravelPath",Vector3.new(7,0.08,3),CFrame.new(x,0.055,z)*CFrame.Angles(0,math.cos(t*math.pi)*0.22,0),Color3.fromRGB(177,169,144),Enum.Material.Pebble)
 end
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
  if planted>=85 then break end
  local angle=random:NextNumber(0,math.pi*2)
  local distance=random:NextNumber(clearRadius+15,260)
  local at=ground(math.cos(angle)*distance,math.sin(angle)*distance)
  if not clear(at) then pine(folder,at,random:NextNumber(13,25)); planted+=1 end
 end
 local flowerColours={Color3.fromRGB(198,167,215),Color3.fromRGB(248,215,135),Color3.fromRGB(235,231,208)}
 for _=1,95 do
  local angle=random:NextNumber(0,math.pi*2)
  local distance=random:NextNumber(clearRadius+5,145)
  local at=ground(math.cos(angle)*distance,math.sin(angle)*distance)
  if not clear(at) then
   local height=random:NextNumber(0.45,1.1)
   piece(folder,"MeadowLeaves",Vector3.new(1.1,height,0.7),CFrame.new(at+Vector3.new(0,height/2,0))*CFrame.Angles(0,angle,0),Color3.fromRGB(92,125,77),Enum.Material.Grass,"WedgePart")
   piece(folder,"Wildflowers",Vector3.new(0.6,0.18,0.5),CFrame.new(at+Vector3.new(0,height,0)),flowerColours[random:NextInteger(1,3)],Enum.Material.SmoothPlastic)
  end
 end
 for _=1,32 do
  local angle=random:NextNumber(0,math.pi*2)
  local distance=random:NextNumber(clearRadius+8,180)
  local at=ground(math.cos(angle)*distance,math.sin(angle)*distance)
  if not clear(at) then
   local size=random:NextNumber(2,5)
   piece(folder,"WeatheredBoulder",Vector3.new(size,size*0.65,size*0.8),CFrame.new(at+Vector3.new(0,size*0.22,0))*CFrame.Angles(0,angle,0.15),Color3.fromRGB(126,139,130),Enum.Material.Slate,"CornerWedgePart")
  end
 end
 -- Camp: canvas shelter, supply crates, seats and a restrained amber fire.
 local shelter=camp+Vector3.new(-14,0,5)
 for _,x in {-4,4} do
  piece(folder,"ShelterPost",Vector3.new(0.35,6,0.35),CFrame.new(shelter+Vector3.new(x,3,0)),Color3.fromRGB(103,80,56),Enum.Material.Wood)
 end
 for side=-1,1,2 do
  piece(folder,"CanvasRoof",Vector3.new(5.4,0.15,7),CFrame.new(shelter+Vector3.new(side*2.4,6,0))*CFrame.Angles(0,0,-side*0.35),Color3.fromRGB(210,179,122),Enum.Material.Fabric)
 end
 for i=1,3 do
  solid(piece(folder,"SupplyCrate",Vector3.new(2,2,2),CFrame.new(shelter+Vector3.new(-3+i*1.8,1,1))*CFrame.Angles(0,i*0.2,0),Color3.fromRGB(135,102,67),Enum.Material.WoodPlanks))
 end
 local fireAt=camp+Vector3.new(12,0,5)
 for i=1,10 do
  local angle=i/10*math.pi*2
  piece(folder,"FireRingStone",Vector3.new(0.85,0.55,0.7),CFrame.new(fireAt+Vector3.new(math.cos(angle)*1.6,0.28,math.sin(angle)*1.6))*CFrame.Angles(0,-angle,0),Color3.fromRGB(115,121,121),Enum.Material.Slate)
 end
 local embers=piece(folder,"Embers",Vector3.new(1.8,0.2,1.8),CFrame.new(fireAt+Vector3.new(0,0.2,0)),Color3.fromRGB(236,133,60),Enum.Material.Neon)
 local fire=Instance.new("Fire"); fire.Size=3; fire.Heat=4; fire.Parent=embers
 local glow=Instance.new("PointLight"); glow.Color=Color3.fromRGB(255,180,100); glow.Range=14; glow.Brightness=1.2; glow.Shadows=false; glow.Parent=embers
 for _,offset in {Vector3.new(-4,0,0),Vector3.new(4,0,0),Vector3.new(0,0,4)} do
  solid(piece(folder,"CampBench",Vector3.new(3.6,0.5,1.2),CFrame.new(fireAt+offset+Vector3.new(0,1,0))*CFrame.Angles(0,if offset.X~=0 then math.pi/2 else 0,0),Color3.fromRGB(128,99,69),Enum.Material.WoodPlanks))
 end
 lantern(folder,camp+Vector3.new(-9,0,-8)); lantern(folder,camp+Vector3.new(9,0,-8))
 Lighting.ClockTime=16.4; Lighting.Brightness=2.3
 Lighting.Ambient=Color3.fromRGB(106,112,125); Lighting.OutdoorAmbient=Color3.fromRGB(145,152,158)
 Lighting.ColorShift_Top=Color3.fromRGB(255,224,184)
 Lighting.EnvironmentDiffuseScale=0.65; Lighting.EnvironmentSpecularScale=0.7
 local atmosphere=Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
 atmosphere.Density=0.24; atmosphere.Offset=0.15; atmosphere.Color=Color3.fromRGB(213,228,232)
 atmosphere.Decay=Color3.fromRGB(157,176,189); atmosphere.Haze=1.4; atmosphere.Glare=0.15; atmosphere.Parent=Lighting
 local grade=Instance.new("ColorCorrectionEffect"); grade.Name="AlpineColour"
 grade.Brightness=0.015; grade.Contrast=0.08; grade.Saturation=0.05; grade.TintColor=Color3.fromRGB(255,248,237); grade.Parent=Lighting
 local bloom=Instance.new("BloomEffect"); bloom.Intensity=0.12; bloom.Size=18; bloom.Threshold=1.6; bloom.Parent=Lighting
 local clouds=terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
 clouds.Cover=0.38; clouds.Density=0.45; clouds.Color=Color3.fromRGB(245,241,230); clouds.Parent=terrain
 local sky=Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky")
 sky.SunAngularSize=9; sky.CelestialBodiesShown=true; sky.Parent=Lighting
end
return Scenery
