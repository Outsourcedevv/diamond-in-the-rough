"""Builds the scenery under the Luau CLI with a Roblox stand-in and checks the
terrain, part budget, tree geometry and lighting: once with the built-in
scenery (a published game that cannot use EditableMesh), once with the Blender
pack built in game (the server lays it out, then the client's SceneryView
builds every mesh with a stand-in EditableMesh), and twice with a stand-in for
an imported pack (at true size, and at 1/100 scale lying on its back) to check
sizing and orientation.

    python3 tests/scenery.py [path/to/luau]
    python3 tests/scenery.py [path/to/luau] --dump   (writes art/previews/layout.txt
                                                      for the game-view preview render)
"""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]


def module(path: str) -> str:
    source = (root / path).read_text(encoding="utf-8")
    source = source.replace('require(ReplicatedStorage:WaitForChild("DiamondRush"):WaitForChild("PartShapes"))', "PartShapes")
    source = source.replace("require(script.Parent.ScenePack)", "ScenePack")
    source = source.replace("require(script.Parent.Sakura)", "Sakura")
    source = source.replace("require(script.Parent.Watchtower)", "Watchtower")
    source = source.replace("require(script.Parent.Farm)", "Farm")
    source = source.replace("require(script.Parent.Desert)", "Desert")
    source = source.replace("require(script.Parent.Haunted)", "Haunted")
    source = source.replace('require(ReplicatedStorage:WaitForChild("DiamondRush"):WaitForChild("SceneryThemes"))', "SceneryThemes")
    source = source.replace('require(Shared:WaitForChild("SceneryThemes"))', "SceneryThemes")
    source = source.replace('require(script.Parent:WaitForChild("Inflate"))', "Inflate")
    source = source.replace('local Shared = ReplicatedStorage:WaitForChild("DiamondRush")\n', "")
    source = source.replace('require(Shared:WaitForChild("MeshPack"))', "MeshPack")
    source = source.replace('require(Shared:WaitForChild("ScenePackData"))', "ScenePackData")
    return "(function()\n" + source + "\nend)()"


setup = r'''
local Lighting = Instance.new("Lighting")
local ServerStorage = Instance.new("Folder")
local Replicated = Instance.new("Folder")
Replicated.WaitForChild = function(self, name) return self:FindFirstChild(name) end
-- EditableMesh works in Studio ("generated"), and fails in a published game
-- that has not turned on Mesh / Image APIs (the other modes).
local editableMeshes, meshParts = 0, 0
local AssetService = {
	CreateEditableMesh = function()
		if PACK_MODE ~= "generated" then error("EditableMesh is not enabled for this experience") end
		editableMeshes += 1
		local m = { low = Vector3.new(math.huge, math.huge, math.huge), high = Vector3.new(-math.huge, -math.huge, -math.huge), faces = 0, n = 0 }
		function m:AddVertex(p)
			self.low = Vector3.new(math.min(self.low.X, p.X), math.min(self.low.Y, p.Y), math.min(self.low.Z, p.Z))
			self.high = Vector3.new(math.max(self.high.X, p.X), math.max(self.high.Y, p.Y), math.max(self.high.Z, p.Z))
			self.n += 1
			return self.n
		end
		function m:AddColor() self.n += 1; return self.n end
		function m:AddNormal() self.n += 1; return self.n end
		function m:AddTriangle() self.faces += 1; return self.faces end
		function m:SetFaceNormals() end
		function m:SetFaceColors() end
		function m:RemoveUnused() end
		function m:Destroy() end
		return m
	end,
	CreateMeshPartAsync = function(_, content, options)
		assert(content.SourceType == "ContentSourceType.Object", "meshes are made from the EditableMesh")
		assert(options.CollisionFidelity ~= nil, "collision fidelity is chosen")
		meshParts += 1
		local part = Instance.new("MeshPart")
		part.Name = "MeshPart"
		part.MeshContent = content
		part.Size = content.Object.high - content.Object.low
		return part
	end,
}
local Content = { fromObject = function(object) return { SourceType = "ContentSourceType.Object", Object = object } end }
game = { GetService = function(_, name)
	if name == "Lighting" then return Lighting end
	if name == "ServerStorage" then return ServerStorage end
	if name == "ReplicatedStorage" then return Replicated end
	if name == "AssetService" then return AssetService end
	return { WaitForChild = function() return {} end }
end }
workspace.FindFirstChild = function(_, name)
	for _, other in instances do
		if other.Parent == workspace and other.Name == name then return other end
	end
	return nil
end
local highest = -math.huge
local DUMP = os.getenv and os.getenv("SCENERY_DUMP") ~= nil or false
local surface = {}
local terrain = Instance.new("Terrain")
local fills, balls, chunks, snow, rockSteep, water, air = 0, 0, 0, 0, 0, 0, 0
local materialColours = {}
terrain.SetMaterialColor = function(_, material, colour) materialColours[material] = colour end
terrain.FillBlock = function() fills += 1 end
terrain.FillBall = function(_, centre, radius, material)
	balls += 1
	assert(Vector3.new(centre.X, 0, centre.Z).Magnitude > 55 + radius - 8, "boulders stay out of the arena")
	assert(material == "Material.Rock")
end
local Region3 = { new = function(a, b) return { minimum = a, maximum = b } end }
terrain.WriteVoxels = function(_, region, resolution, materials, occupancies)
	chunks += 1
	assert(resolution == 4)
	local layers = (region.maximum.Y - region.minimum.Y) // 4
	for x = 1, 16 do
		for y = 1, layers do
			for z = 1, 16 do
				local value = occupancies[x][y][z]
				local material = materials[x][y][z]
				assert(value >= 0 and value <= 1 and value == value)
				if material == "Material.Snow" then snow += 1 end
				if value > 0.5 then highest = math.max(highest, region.minimum.Y + (y - 0.5) * 4) end
				if value > 0 and material ~= "Material.Air" then
					local key = (region.minimum.X + (x - 0.5) * 4) .. "," .. (region.minimum.Z + (z - 0.5) * 4)
					local top = surface[key]
					local wyTop = region.minimum.Y + (y - 1) * 4 + value * 4
					if top == nil or wyTop > top[1] then surface[key] = { wyTop, material } end
				end
				if material == "Material.Water" then water += 1 end
				if material == "Material.Air" then air += 1 end
				local wx, wz = region.minimum.X + (x - 0.5) * 4, region.minimum.Z + (z - 0.5) * 4
				local wy = region.minimum.Y + (y - 0.5) * 4
				if wx * wx + wz * wz < 55 * 55 then
					assert(value == (if wy < 0 then 1 else 0), "keep mountain growth area flat and clear")
					if value > 0 and wy > -4 then assert(material == "Material.LeafyGrass", "arena floor has no grass blades") end
				end
			end
		end
	end
end
workspace.Terrain = terrain
-- Rays find the generated terrain surface (the nearest 4-stud column), or 0 outside it.
workspace.Raycast = function(_, at)
	local cx, cz = math.floor(at.X / 4) * 4 + 2, math.floor(at.Z / 4) * 4 + 2
	local top = surface[cx .. "," .. cz]
	return { Position = Vector3.new(at.X, if top and math.abs(at.Y) < 1000 then top[1] else 0, at.Z) }
end
'''

checks = r'''
-- The leaderboards' ground (as placed by the server) must stay clear.
local reserved = { { at = Vector3.new(-30.6, 0, -81), radius = 30 }, { at = Vector3.new(30.6, 0, -81), radius = 30 } }
local function inReserved(at): boolean
	for _, spot in reserved do
		if (Vector3.new(at.X, 0, at.Z) - spot.at).Magnitude < spot.radius then return true end
	end
	return false
end
terrain.FillBall = function(_, centre, radius, material)
	balls += 1
	assert(Vector3.new(centre.X, 0, centre.Z).Magnitude > 55 + radius - 8, "boulders stay out of the arena")
	assert(not inReserved(centre), "boulders stay off the leaderboard sites")
	assert(material == "Material.Rock")
end
-- A stand-in for the imported Blender pack, sized from art/manifest.json.
local pack = nil
if PACK_MODE == "studs" or PACK_MODE == "tiny-zup" then
	pack = Instance.new("Model")
	pack.Name = "DiamondRushScenery"
	pack.Parent = workspace
	for name, size in MANIFEST do
		local mesh = Instance.new("MeshPart")
		mesh.Name = name
		-- Blender is Z up; a correct import is Y up. "tiny-zup" mimics a bad import.
		mesh.Size = if PACK_MODE == "tiny-zup" then Vector3.new(size[1], size[2], size[3]) * 0.01 else Vector3.new(size[1], size[3], size[2])
		mesh.Parent = pack
	end
end
Scenery.build(26.4, Vector3.new(0, 0.5, 56.4), reserved)

-- Themes: the alpine default, and sakura switched on and off live.
local sceneryFolder = workspace:FindFirstChild("Scenery")
local alpineOnly = sceneryFolder:FindFirstChild("AlpineOnly")
local festoon = alpineOnly:FindFirstChild("Festoon")
local tower = alpineOnly:FindFirstChild("Watchtower")
local sakura = ServerStorage:FindFirstChild("SakuraScenery")
-- No lettered signs anywhere in the scenery: their text renders badly (the
-- leaderboards are built elsewhere and keep theirs).
for _, holder in { sceneryFolder, sakura, ServerStorage:FindFirstChild("FarmScenery"), ServerStorage:FindFirstChild("DesertScenery"), ServerStorage:FindFirstChild("HauntedScenery") } do
	for _, object in holder:GetDescendants() do
		assert(object.ClassName ~= "TextLabel", "no lettered signs in the scenery: " .. tostring(object.Parent and object.Parent.Parent and object.Parent.Parent.Name))
	end
end
assert(Scenery.theme() == "default" and festoon ~= nil and alpineOnly.Parent == sceneryFolder, "the valley starts alpine, festoon lights up")
-- The watchtower: beside the mountain, off the arena, camp and boards, facing
-- the camp, every leg in the ground and its lookout high above it.
assert(tower ~= nil, "the alpine theme has a watchtower")
local legs, rungs, towerParts, towerLights = {}, 0, 0, 0
local floor = tower:FindFirstChild("TowerFloor")
for _, p in tower:GetDescendants() do
	if p.Name == "TowerLeg" then table.insert(legs, p) end
	if p.Name == "TowerRung" then rungs += 1 end
	if p.ClassName == "Part" or p.ClassName == "WedgePart" then
		towerParts += 1
		assert(p.Anchored and p.CanQuery == false and p.CanTouch == false, "the tower must not interfere with mining/physics: " .. p.Name)
	end
	if p.ClassName == "PointLight" then towerLights += 1 end
end
assert(#legs == 4 and rungs >= 15 and floor ~= nil and towerLights == 1, "legs, a ladder, a floor and a lamp: " .. #legs .. " " .. rungs)
assert(towerParts < 160, "the tower stays light: " .. towerParts)
local towerAt = Vector3.new(floor.CFrame.Position.X, 0, floor.CFrame.Position.Z)
assert(towerAt.Magnitude > 55 + 6 and (towerAt - Vector3.new(0, 0, 56.4)).Magnitude > 25 + 6 and not inReserved(towerAt), "the tower stands clear of the arena, camp and boards")
assert(towerAt.X < 0, "it stands to the left of the mountain from the spawn, away from the sakura shrine")
local look = floor.CFrame.LookVector
local toward = (Vector3.new(0, 0, 56.4) - towerAt).Unit
assert(look.X * toward.X + look.Z * toward.Z > 0.99, "the lookout faces the camp")
for _, p in legs do
	-- A leg is a cylinder along X: its two ends.
	local axis = p.CFrame.RightVector * (p.Size.X / 2)
	local a, b = p.CFrame.Position - axis, p.CFrame.Position + axis
	local low = if a.Y < b.Y then a else b
	assert(workspace:Raycast(Vector3.new(low.X, 300, low.Z)).Position.Y > low.Y, "every leg reaches into the ground")
end
local groundHere = workspace:Raycast(Vector3.new(towerAt.X, 300, towerAt.Z)).Position.Y
assert(floor.CFrame.Position.Y - groundHere > 20, "the lookout is high above the ground")
assert(math.abs(floor.Size.X - (2 * 2.9 + 0.4) * Watchtower.SCALE) < 1e-6, "the tower is drawn " .. Watchtower.SCALE .. " times bigger")
assert(sakura ~= nil, "the sakura scenery waits out of view")
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
local grade = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
local clouds = terrain:FindFirstChildOfClass("Clouds")
local function look()
	return {
		Lighting.ClockTime, Lighting.Brightness, Lighting.Ambient, Lighting.OutdoorAmbient, Lighting.ColorShift_Top, Lighting.ExposureCompensation,
		atmosphere.Density, atmosphere.Offset, atmosphere.Color, atmosphere.Decay, atmosphere.Glare, atmosphere.Haze,
		grade.Contrast, grade.Saturation, grade.TintColor, bloom.Intensity, bloom.Size, bloom.Threshold, rays.Intensity,
		clouds.Cover, clouds.Density, clouds.Color, terrain.WaterColor,
		materialColours["Material.Grass"], materialColours["Material.LeafyGrass"], materialColours["Material.Ground"],
		materialColours["Material.Mud"], materialColours["Material.Rock"], materialColours["Material.Snow"],
	}
end
local alpine = look()
-- The alpine look is the one the valley always had.
assert(Lighting.ClockTime == 15.6 and atmosphere.Density == 0.3 and atmosphere.Haze == 1.6 and grade.TintColor == Color3.fromRGB(255, 249, 240)
	and bloom.Threshold == 1.3 and clouds.Cover == 0.42 and terrain.WaterColor == Color3.fromRGB(46, 92, 96)
	and materialColours["Material.Grass"] == Color3.fromRGB(102, 126, 64) and materialColours["Material.Snow"] == Color3.fromRGB(238, 242, 247),
	"the alpine look is unchanged")
for i = 1, 29 do assert(alpine[i] ~= nil, "every themed setting is set: " .. i) end
-- What the sakura theme brings.
local camp = Vector3.new(0, 0, 56.4)
local trees, blossoms, carpets, torii, lanterns, sakuraParts = 0, 0, 0, 0, 0, 0
for _, p in sakura:GetDescendants() do
	if p.Name == "SakuraTree" then trees += 1 end
	if p.Name == "Blossom" then
		blossoms += 1
		assert(p.Shape == "PartType.Ball" and p.Size.X > 3, "blossoms are round puffs")
	end
	if p.Name == "Torii" then torii += 1 end
	if p.Name == "StoneLantern" then lanterns += 1 end
	if p.Name == "SakuraTrunk" or p.Name == "FallenPetals" then
		local flat = Vector3.new(p.CFrame.Position.X, 0, p.CFrame.Position.Z)
		assert(flat.Magnitude > 55 and (flat - camp).Magnitude > 25 and not inReserved(flat), "cherry trees stay off the arena, camp and boards")
		if p.Name == "FallenPetals" then carpets += 1 end
	end
	if p.Name == "ToriiPillar" and (Vector3.new(p.CFrame.Position.X, 0, p.CFrame.Position.Z) - camp).Magnitude < 20 then
		local at = p.CFrame.Position
		assert(at.Z < 56.4 - 7 and at.Z > 56.4 - 11, "the torii stands just past the spawn pad: " .. at.Z)
	end
	if p.ClassName == "Part" then
		sakuraParts += 1
		assert(p.Anchored and p.CanQuery == false and p.CanTouch == false, "sakura scenery must not interfere with mining/physics: " .. tostring(p.Name))
		assert(p.Size.X > 0 and p.Size.Y > 0 and p.Size.Z > 0, "positive size: " .. tostring(p.Name))
	end
	assert(p.ClassName ~= "PointLight", "the sakura theme adds no lights")
end
assert(trees >= 40 and trees <= 48 and carpets == trees and blossoms >= trees * 4, "cherry groves: " .. trees)
assert(torii == 2 and lanterns == 5, "two torii (camp and shrine) and five stone lanterns")
assert(sakuraParts < 850, "the sakura scenery stays light: " .. sakuraParts)
-- The shrine: on a flat meadow off the arena, camp and boards, facing the camp,
-- with no cherry tree inside its grounds and its plinth reaching the ground.
local shrines = {}
for _, p in sakura:GetDescendants() do if p.Name == "Shrine" then table.insert(shrines, p) end end
assert(#shrines == 1, "one shrine")
local plinth = shrines[1]:FindFirstChild("ShrinePlinth")
local roof, pillars = 0, 0
for _, p in shrines[1]:GetDescendants() do
	if p.Name == "ShrineRoof" then roof += 1 end
	if p.Name == "ShrinePillar" then pillars += 1 end
end
assert(plinth ~= nil and roof == 4 and pillars == 10, "plinth, curved roof and pillars")
assert(math.abs(plinth.Size.X - 17 * Sakura.SHRINE_SCALE) < 1e-6 and Sakura.SHRINE_SCALE >= 1.5, "the shrine is enlarged: " .. plinth.Size.X)
local centre = plinth.CFrame.Position
local flatCentre = Vector3.new(centre.X, 0, centre.Z)
assert(flatCentre.Magnitude > 55 + 12 and (flatCentre - camp).Magnitude > 25 + 12 and not inReserved(flatCentre), "the shrine stands clear of the arena, camp and boards")
local facing = plinth.CFrame.LookVector
local toCamp = (camp - flatCentre).Unit
assert(facing.X * toCamp.X + facing.Z * toCamp.Z > 0.99, "the shrine faces the camp")
local bottom = centre.Y - plinth.Size.Y / 2
for _, offset in { Vector3.new(-8.5, 0, -7), Vector3.new(8.5, 0, -7), Vector3.new(-8.5, 0, 7), Vector3.new(8.5, 0, 7) } do
	local corner = plinth.CFrame * offset
	assert(workspace:Raycast(Vector3.new(corner.X, 300, corner.Z)).Position.Y > bottom, "the plinth reaches the ground at every corner")
end
for _, p in sakura:GetDescendants() do
	if p.Name == "SakuraTrunk" then
		local at = p.CFrame.Position
		assert((Vector3.new(at.X, 0, at.Z) - flatCentre).Magnitude > 17, "no cherry tree grows inside the shrine grounds")
	end
end
-- The farm theme: a ranch fence round the arena, open only where the trail
-- comes in under the gate, and a barn with its yard beyond it.
local farm = ServerStorage:FindFirstChild("FarmScenery")
assert(farm ~= nil, "the farm scenery waits out of view")
local ranch = farm:FindFirstChild("RanchFence")
local posts, gateposts, farmParts, farmLights, signs = {}, {}, 0, 0, 0
for _, p in farm:GetDescendants() do
	if p.ClassName == "Part" or p.ClassName == "WedgePart" then
		farmParts += 1
		assert(p.Anchored and p.CanQuery == false and p.CanTouch == false, "farm scenery must not interfere with mining/physics: " .. tostring(p.Name))
		if p.Name == "FencePost" then table.insert(posts, p.CFrame.Position) end
		if p.Name == "GatePost" then table.insert(gateposts, p.CFrame.Position) end
		if p.Name == "FencePost" or p.Name == "FenceRail" or p.Name == "GatePost" then assert(p.CanCollide, "the fence can be bumped into") end
		local flat = Vector3.new(p.CFrame.Position.X, 0, p.CFrame.Position.Z)
		if p.Parent ~= ranch then assert(flat.Magnitude > 55, "only the fence stands in the arena: " .. tostring(p.Name)) end
	end
	if p.ClassName == "PointLight" then farmLights += 1 end
	if p.Name == "RanchSign" then signs += 1 end
end
assert(#gateposts == 2 and signs == 0, "a gate arch with no sign (sign text renders badly)")
assert(#posts > 40, "posts all the way round: " .. #posts)
local ring = {}
for _, at in posts do table.insert(ring, at) end
for _, at in gateposts do table.insert(ring, at) end
for _, at in ring do
	local r = Vector3.new(at.X, 0, at.Z).Magnitude
	assert(math.abs(r - 52) < 0.5, "the fence circles the arena inside its edge: " .. r)
end
table.sort(ring, function(a, b) return math.atan2(a.X, a.Z) < math.atan2(b.X, b.Z) end)
local wide = 0
for i, at in ring do
	local nextAt = ring[i % #ring + 1]
	local gap = (Vector3.new(at.X, 0, at.Z) - Vector3.new(nextAt.X, 0, nextAt.Z)).Magnitude
	if gap > 7.5 then
		wide += 1
		assert(math.abs(gap - 9) < 0.6, "the one opening is the gate: " .. gap)
	end
end
assert(wide == 1, "the fence is closed but for the gate: " .. wide)
-- The trail runs through the gate, and the spawn is outside it.
local g1, g2 = gateposts[1], gateposts[2]
local middle = (g1 + g2) / 2
local trailX = math.sin(math.clamp((56.4 - middle.Z) / (56.4 - 26), 0, 1) * math.pi) * 4
assert(math.abs(middle.X - trailX) < 0.6 and middle.Z > 50, "the gate is on the trail, in front of the spawn")
assert(Vector3.new(0, 0, 56.4).Magnitude > 52, "players spawn outside the corral and walk in")
-- The barn: clear of the arena, camp and boards, facing the camp, its
-- foundation reaching the ground, with a silo, corn, cows and a light.
local barns = {}
for _, p in farm:GetDescendants() do if p.Name == "Barn" then table.insert(barns, p) end end
assert(#barns == 1, "one barn")
local foundation = barns[1]:FindFirstChild("BarnFoundation")
assert(foundation ~= nil and barns[1]:FindFirstChild("Silo") ~= nil and barns[1]:FindFirstChild("SiloDome") ~= nil, "a barn with a silo")
assert(math.abs(foundation.Size.X - (15 + 0.8) * Farm.BARN_SCALE) < 1e-6 and Farm.BARN_SCALE >= 1.5, "the barn is enlarged: " .. foundation.Size.X)
do
	local silo = barns[1]:FindFirstChild("Silo")
	local axis = silo.CFrame.RightVector * (silo.Size.X / 2)
	local a, b = silo.CFrame.Position - axis, silo.CFrame.Position + axis
	local low = if a.Y < b.Y then a else b
	assert(workspace:Raycast(Vector3.new(low.X, 300, low.Z)).Position.Y > low.Y, "the enlarged silo still stands in the ground")
end
local barnAt = foundation.CFrame.Position
local barnFlat = Vector3.new(barnAt.X, 0, barnAt.Z)
assert(barnFlat.Magnitude > 55 + 15 and (barnFlat - camp).Magnitude > 25 + 15 and not inReserved(barnFlat), "the barn stands clear of the arena, camp and boards")
local barnLook = foundation.CFrame.LookVector
local barnToCamp = (camp - barnFlat).Unit
assert(barnLook.X * barnToCamp.X + barnLook.Z * barnToCamp.Z > 0.99, "the barn faces the camp")
assert(math.atan2(math.abs(barnFlat.X - camp.X), camp.Z - barnFlat.Z) > math.rad(30), "the barn stands to one side, where the mountain does not hide it from the spawn")
local barnBottom = barnAt.Y - foundation.Size.Y / 2
for _, offset in { Vector3.new(-7.5, 0, -10.5), Vector3.new(7.5, 0, -10.5), Vector3.new(-7.5, 0, 10.5), Vector3.new(7.5, 0, 10.5) } do
	local corner = foundation.CFrame * offset
	assert(workspace:Raycast(Vector3.new(corner.X, 300, corner.Z)).Position.Y > barnBottom, "the barn's foundation reaches the ground at every corner")
end
local corn, cows = 0, 0
for _, p in farm:GetDescendants() do
	if p.Name == "Corn" then corn += 1 end
	if p.Name == "Cow" then cows += 1 end
end
assert(corn >= 6 and cows >= 2, "a cornfield and cows: " .. corn .. " " .. cows)
assert(farmLights == 1, "one warm lamp over the barn doors")
assert(farmParts < 900, "the farm scenery stays light: " .. farmParts)
assert(Scenery.setTheme("farm") and Scenery.theme() == "farm", "farm can be chosen")
assert(farm.Parent == workspace and sakura.Parent == ServerStorage and alpineOnly.Parent == ServerStorage, "the ranch shows; the festoon and watchtower make way")
assert(Lighting.ClockTime == Scenery.LOOKS.farm.clock and atmosphere.Color == Scenery.LOOKS.farm.atmosphere.color
	and materialColours["Material.Grass"] == Scenery.LOOKS.farm.terrain["Material.Grass"], "the farm light and colours apply")
-- Switching to sakura and back is instant and exact.
assert(Scenery.setTheme("sakura") and Scenery.theme() == "sakura", "sakura can be chosen")
assert(sakura.Parent == workspace and alpineOnly.Parent == ServerStorage and farm.Parent == ServerStorage, "the blossoms show; the ranch, festoon and watchtower make way")
assert(Lighting.ClockTime == Scenery.LOOKS.sakura.clock and atmosphere.Color == Scenery.LOOKS.sakura.atmosphere.color
	and materialColours["Material.Grass"] == Scenery.LOOKS.sakura.terrain["Material.Grass"], "the sakura light and colours apply")
assert(not Scenery.setTheme("winter") and Scenery.theme() == "sakura", "unknown themes are refused")
assert(Scenery.setTheme("default") and Scenery.theme() == "default", "alpine can be chosen again")
assert(sakura.Parent == ServerStorage and alpineOnly.Parent == sceneryFolder, "the sakura scenery goes back out of view; the watchtower returns")
local back = look()
for i = 1, 29 do assert(back[i] == alpine[i], "the alpine look comes back exactly: " .. i) end

-- Checks every part of a theme's scenery, and counts parts, lights and names.
local function survey(holder, label)
	local count, lights, names = 0, 0, {}
	for _, p in holder:GetDescendants() do
		if p.Name then names[p.Name] = (names[p.Name] or 0) + 1 end
		if p.ClassName == "Part" or p.ClassName == "WedgePart" then
			count += 1
			assert(p.Anchored and p.CanQuery == false and p.CanTouch == false, label .. " scenery must not interfere with mining/physics: " .. tostring(p.Name))
			assert(p.Size.X > 0 and p.Size.Y > 0 and p.Size.Z > 0, label .. " parts have a positive size: " .. tostring(p.Name))
			assert(p.Size.Magnitude >= 3 or not p.CastShadow, label .. " small props cast no shadow: " .. p.Name)
			local flat = Vector3.new(p.CFrame.Position.X, 0, p.CFrame.Position.Z)
			assert(flat.Magnitude > 40, label .. " scenery stays off the mountain: " .. p.Name)
			assert(not inReserved(flat), label .. " scenery stays off the leaderboards: " .. p.Name)
		elseif p.ClassName == "PointLight" then
			lights += 1
			assert(not p.Shadows, "point lights skip shadows")
		end
	end
	return count, lights, names
end
-- A building's frame faces the camp and stands to one side of the mountain.
local function facesCamp(frame, label)
	local flat = Vector3.new(frame.Position.X, 0, frame.Position.Z)
	local toCamp = (camp - flat).Unit
	assert(frame.LookVector.X * toCamp.X + frame.LookVector.Z * toCamp.Z > 0.99, label .. " faces the camp")
	assert(flat.Magnitude > 55 + 12 and (flat - camp).Magnitude > 25 + 12, label .. " stands clear of the arena and camp")
	assert(math.atan2(math.abs(flat.X - camp.X), camp.Z - flat.Z) > math.rad(25), label .. " stands to one side, where the mountain does not hide it")
end
-- The gate where the trail leaves the camp: its two sides either side of the trail.
local function besideTrail(holder, gateName, sideName, label)
	local gateModel = holder:FindFirstChild(gateName)
	assert(gateModel ~= nil, label .. " has its gate")
	local xs = {}
	for _, p in gateModel:GetChildren() do
		if p.Name == sideName then
			local at = p.CFrame.Position
			local trailX = math.sin(math.clamp((56.4 - at.Z) / (56.4 - 26), 0, 1) * math.pi) * 4
			assert(math.abs(at.X - trailX) - p.Size.X / 2 > 3.4, label .. " gate keeps the trail open")
			xs[if at.X < trailX then 1 else 2] = true
		end
	end
	assert(xs[1] and xs[2], label .. " gate stands either side of the trail")
end

-- The desert theme: mesas, cacti, an oasis and a stepped pyramid.
local desert = ServerStorage:FindFirstChild("DesertScenery")
assert(desert ~= nil, "the desert scenery waits out of view")
local desertParts, desertLights, desertNames = survey(desert, "desert")
assert((desertNames.Mesa or 0) >= 6, "mesas round the valley: " .. tostring(desertNames.Mesa))
assert((desertNames.Saguaro or 0) >= 25 and (desertNames.BarrelCactus or 0) >= 15, "saguaros and barrel cacti: " .. tostring(desertNames.Saguaro) .. " " .. tostring(desertNames.BarrelCactus))
assert((desertNames.Palm or 0) >= 5, "palms round the oasis: " .. tostring(desertNames.Palm))
assert((desertNames.Tumbleweed or 0) >= 8 and (desertNames.ClayPot or 0) == 3, "tumbleweeds and clay pots")
assert(desertLights == 0 and desertParts < 1100, "the desert stays light: " .. desertParts .. " parts, " .. desertLights .. " lights")
besideTrail(desert, "CanyonGate", "GatePylon", "the desert")
local pyramid = desert:FindFirstChild("Pyramid")
assert(pyramid ~= nil, "a pyramid")
local steps, stairs, lowest, highestStair = {}, {}, nil, -math.huge
for _, p in pyramid:GetChildren() do
	if p.Name == "PyramidStep" then table.insert(steps, p) end
	if p.Name == "PyramidStair" then
		table.insert(stairs, p)
		highestStair = math.max(highestStair, p.CFrame.Position.Y + p.Size.Y / 2)
		assert(p.CanCollide, "the stair can be climbed")
	end
end
assert(#steps == Desert.STEPS and #stairs == Desert.STEPS * 4, "eight steps and a stair up the front")
table.sort(steps, function(a, b) return a.Size.X > b.Size.X end)
lowest = steps[1]
assert(lowest.Size.X == Desert.PYRAMID and lowest.CanCollide, "the pyramid can be climbed: " .. lowest.Size.X)
facesCamp(lowest.CFrame, "the pyramid")
local pyramidBottom = lowest.CFrame.Position.Y - lowest.Size.Y / 2
local half = Desert.PYRAMID / 2
for _, offset in { Vector3.new(-half, 0, -half), Vector3.new(half, 0, -half), Vector3.new(-half, 0, half), Vector3.new(half, 0, half) } do
	local corner = lowest.CFrame * offset
	assert(workspace:Raycast(Vector3.new(corner.X, 300, corner.Z)).Position.Y >= pyramidBottom - 1e-6, "the pyramid reaches the ground at every corner")
end
local summitY = lowest.CFrame.Position.Y + lowest.Size.Y / 2 + (Desert.STEPS - 1) * Desert.STEP_HEIGHT
assert(math.abs(highestStair - summitY) < 1e-6, "the stair reaches the temple: " .. highestStair .. " " .. summitY)
for _, p in stairs do
	local foot = p.CFrame.Position - Vector3.new(0, p.Size.Y / 2, 0)
	assert(workspace:Raycast(Vector3.new(foot.X, 300, foot.Z)).Position.Y >= foot.Y - 1e-6, "every tread is solid down to the ground")
end
assert(pyramid:FindFirstChild("Temple") ~= nil and pyramid:FindFirstChild("Capstone") ~= nil and #pyramid:GetChildren() > 40, "a temple and gold capstone on top")
-- Palms stand on dry ground round the lake.
for _, p in desert:GetDescendants() do
	if p.Name == "Palm" then
		local trunk = p:FindFirstChild("PalmTrunk")
		local distance = (Vector3.new(trunk.CFrame.Position.X, 0, trunk.CFrame.Position.Z) - Vector3.new(26.4 + 14 + 72 + 0.6, 0, 56.4 + 15)).Magnitude
		assert(distance < 70, "palms ring the lake: " .. distance)
	end
end

-- The haunted theme: a mausoleum and graveyard, dead trees, jack-o'-lanterns.
local haunted = ServerStorage:FindFirstChild("HauntedScenery")
assert(haunted ~= nil, "the haunted scenery waits out of view")
local hauntedParts, hauntedLights, hauntedNames = survey(haunted, "haunted")
assert((hauntedNames.DeadTree or 0) >= 20, "dead trees: " .. tostring(hauntedNames.DeadTree))
assert((hauntedNames.Grave or 0) >= 10, "a graveyard: " .. tostring(hauntedNames.Grave))
assert((hauntedNames.JackOLantern or 0) >= 7, "jack-o'-lanterns: " .. tostring(hauntedNames.JackOLantern))
assert((hauntedNames.WillOWisp or 0) == 8, "will-o'-wisps over the graves and the lake")
assert(hauntedLights >= 3 and hauntedLights <= 6, "a few local lights: " .. hauntedLights)
assert(hauntedParts < 1300, "the haunted scenery stays light: " .. hauntedParts)
besideTrail(haunted, "CemeteryGate", "GatePillar", "the haunted")
local mausoleum = haunted:FindFirstChild("Mausoleum")
assert(mausoleum ~= nil and mausoleum:FindFirstChild("CryptDoor") ~= nil and mausoleum:FindFirstChild("CryptGlow") ~= nil, "a mausoleum with a glowing door")
local plinth = mausoleum:FindFirstChild("CryptPlinth")
assert(plinth.CanCollide, "the mausoleum can be bumped into")
local walls = mausoleum:FindFirstChild("CryptWalls")
facesCamp(walls.CFrame, "the mausoleum")
local plinthBottom = plinth.CFrame.Position.Y - plinth.Size.Y / 2
for _, offset in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) } do
	local corner = plinth.CFrame * Vector3.new(offset.X * plinth.Size.X / 2, 0, offset.Z * plinth.Size.Z / 2)
	assert(workspace:Raycast(Vector3.new(corner.X, 300, corner.Z)).Position.Y > plinthBottom, "the mausoleum's plinth reaches the ground at every corner")
end
local fencePosts = 0
for _, p in haunted:GetDescendants() do
	if p.Name == "FencePost" then
		fencePosts += 1
		assert(p.CanCollide, "the graveyard fence can be bumped into")
	end
end
assert(fencePosts >= 20, "a fence round the graveyard: " .. fencePosts)

-- The forest makes way in the desert, the flowers at night, and both come back.
local function shown(kind)
	local count = 0
	for _, p in instances do
		if p.Parent ~= nil and p.Parent == sceneryFolder and SceneryThemes.kind(p.Name) == kind then count += 1 end
	end
	return count
end
local treeKind = if PACK_MODE == "none" then "Conifer" elseif PACK_MODE == "generated" then nil else "Pine"
local treesBefore = if treeKind then shown(treeKind) else 0
local flowersBefore = shown("Flowers")
local rocksBefore = shown("Rock")
assert(Scenery.setTheme("desert") and Scenery.theme() == "desert", "the desert can be chosen")
assert(desert.Parent == workspace and haunted.Parent == ServerStorage and farm.Parent == ServerStorage and sakura.Parent == ServerStorage and alpineOnly.Parent == ServerStorage,
	"the desert shows; the other themes, the festoon and watchtower make way")
assert(Lighting.ClockTime == Scenery.LOOKS.desert.clock and materialColours["Material.Grass"] == Scenery.LOOKS.desert.terrain["Material.Grass"], "the desert light and sand apply")
if treeKind then
	assert(treesBefore > 0 and shown(treeKind) == 0 and shown("Flowers") == 0, "no forest or flowers in the desert")
	assert(shown("Rock") == rocksBefore, "the rocks stay")
	if PACK_MODE == "none" then assert(shown("Birch") == 0, "the birches make way too") end
end
assert(Scenery.setTheme("haunted") and Scenery.theme() == "haunted", "the haunted night can be chosen")
assert(haunted.Parent == workspace and desert.Parent == ServerStorage and alpineOnly.Parent == ServerStorage, "the graveyard shows")
assert(Lighting.ClockTime == 0 and Lighting:FindFirstChildOfClass("Sky").MoonAngularSize == Scenery.LOOKS.haunted.moon, "a full moon at midnight")
if treeKind then
	assert(shown(treeKind) == treesBefore and shown("Flowers") == 0 and shown("Birch") == 0 and shown("Oak") == 0, "the dark pines stay at night; the flowers and leafy trees make way")
end
assert(Scenery.setTheme("default"), "alpine again")
assert(desert.Parent == ServerStorage and haunted.Parent == ServerStorage and alpineOnly.Parent == sceneryFolder, "the new themes go back out of view")
if treeKind then assert(shown(treeKind) == treesBefore and shown("Flowers") == flowersBefore and shown("Birch") > 0, "every tree and flower comes back") end
assert(Lighting:FindFirstChildOfClass("Sky").MoonAngularSize == 11, "the moon goes back to its usual size")
local again = look()
for i = 1, 29 do assert(again[i] == alpine[i], "the alpine look comes back exactly after the new themes: " .. i) end
-- Petals stay in the box round the camera, wherever it is and however long they fall.
for _, centre in { Vector3.new(0, 6, 56), Vector3.new(-300, 80, 120) } do
	for _, t in { 0, 1.5, 60, 4000.25 } do
		local petal = { seed = Vector3.new(12, 30, 70), fall = 2.4, sway = 1, phase = 0.5, spin = Vector3.new(1, 1, 1) }
		local at = PetalView.frame(petal, t, centre).Position - centre
		assert(math.abs(at.X) <= 40 and math.abs(at.Y) <= 20 and math.abs(at.Z) <= 40, "petals stay round the camera")
	end
end
print(string.format("themes: %d cherry trees, %d blossoms, %d sakura parts; farm: %d fence posts, %d corn rows, %d cows, %d farm parts", trees, blossoms, sakuraParts, #posts, corn, cows, farmParts))
print(string.format("desert: %d mesas, %d saguaros, %d palms, %d parts; haunted: %d graves, %d dead trees, %d lanterns, %d parts, %d lights",
	desertNames.Mesa, desertNames.Saguaro, desertNames.Palm, desertParts, hauntedNames.Grave, hauntedNames.DeadTree, hauntedNames.JackOLantern, hauntedParts, hauntedLights))
local published = Replicated:FindFirstChild("DiamondRushSceneryPlacements")
if PACK_MODE == "generated" then
	-- The server only lays the pack out; each player's game builds it.
	assert(published ~= nil and #published.Value > 1000, "the placements are sent to the players")
	for _, p in instances do
		assert(p.ClassName ~= "MeshPart", "the server builds no meshes itself")
	end
	-- The client follows the theme: start in the desert, then go back to alpine.
	local stateObject = Instance.new("Configuration")
	stateObject.Name = "DiamondRushState"
	stateObject.Parent = Replicated
	stateObject:SetAttribute("Theme", "desert")
	local themeChanged = nil
	stateObject.GetAttributeChangedSignal = function(_, key)
		assert(key == "Theme")
		return { Connect = function(_, handler) themeChanged = handler end }
	end
	local started = os.clock()
	SceneryView.start()
	local function clientShown(kind)
		local count = 0
		for _, p in instances do
			if p.ClassName == "MeshPart" and p.Parent ~= nil and p.Parent.Name == "SceneryMeshes" and SceneryThemes.kind(p.Name) == kind then count += 1 end
		end
		return count
	end
	assert(themeChanged ~= nil and clientShown("Pine") == 0 and clientShown("Flowers") == 0 and clientShown("Rock") >= 30, "the client builds the desert without its forest")
	stateObject:SetAttribute("Theme", "default")
	themeChanged()
	assert(clientShown("Pine") >= 150 and clientShown("Flowers") >= 120, "the forest comes back with the alpine theme")
	-- One EditableMesh is the server's check that they can be used here.
	assert(editableMeshes == 1 + 25 and meshParts == 25, "each mesh is built once and shared by its copies: " .. editableMeshes .. " " .. meshParts)
	print(string.format("client built the pack in %.0f ms", (os.clock() - started) * 1000))
else
	assert(published == nil and editableMeshes == 0, "nothing is sent when the pack is imported or cannot be built")
end
if PACK_MODE ~= "none" then
	if pack then assert(pack.Parent == ServerStorage, "the imported pack is moved out of view") end
	local counts = {}
	local camp = Vector3.new(0, 0, 56.4)
	for _, p in instances do
		if p.ClassName == "MeshPart" and p.Parent ~= nil and p.Parent ~= pack then
			assert(p.Parent.Name == (if PACK_MODE == "generated" then "SceneryMeshes" else "Scenery"), "meshes go in the scenery folder")
			local kind = string.match(p.Name, "^(%a+)")
			counts[kind] = (counts[kind] or 0) + 1
			assert(p.Anchored and p.CanQuery == false and p.CanTouch == false and p.Material == "Material.SmoothPlastic", "pack meshes are static, untinted scenery")
			-- World height of the placed mesh against its authored height.
			local r = p.CFrame.r
			local tall = math.abs(r[4]) * p.Size.X + math.abs(r[5]) * p.Size.Y + math.abs(r[6]) * p.Size.Z
			local ratio = tall / MANIFEST[p.Name][3]
			local flat = Vector3.new(p.CFrame.Position.X, 0, p.CFrame.Position.Z)
			if kind == "Mountain" then
				assert(ratio > 0.9 and ratio < 1.35, "mountains are sized from the pack calibration: " .. ratio)
				assert(flat.Magnitude > 380, "mountains ring the valley beyond the terrain")
			else
				-- Distant rocks grow to 1.8x and tilt, which adds height to wide, flat rocks.
				local most = if kind == "Rock" then 2.6 else 1.9
				assert(ratio > 0.65 and ratio < most, "props are sized from the pack calibration: " .. p.Name .. " " .. ratio)
				assert(flat.Magnitude > 55 and (flat - camp).Magnitude > 25 and not inReserved(flat), "props stay off the arena, camp and boards: " .. p.Name)
			end
		end
	end
	assert(counts.Mountain == 12, "twelve mountains ring the valley")
	assert((counts.Pine or 0) >= 150 and (counts.Birch or 0) + (counts.Oak or 0) >= 15, "forest from the pack: " .. tostring(counts.Pine))
	assert((counts.Rock or 0) >= 30 and (counts.Cliff or 0) >= 5 and (counts.Bush or 0) >= 40, "rocks, cliffs and bushes")
	assert((counts.Flowers or 0) >= 120 and (counts.Log or 0) + (counts.Stump or 0) >= 10, "flowers, logs and stumps")
	local wedgeTrees = 0
	for _, p in instances do if p.Name == "Conifer" then wedgeTrees += 1 end end
	assert(wedgeTrees == 0 and balls == 0, "the built-in trees and boulders are replaced")
	assert(highest < 90, "terrain peaks become foothills behind the mesh mountains: " .. highest)
	assert(fills == 1 and chunks == 144 and water > 0, "terrain and lake are still built")
	if DUMP_PLACEMENTS then
		-- One line per placed mesh and terrain column, for art/preview.py's game view.
		for _, p in instances do
			if p.ClassName == "MeshPart" and p.Parent ~= nil and p.Parent ~= pack then
				local c, r = p.CFrame.p, p.CFrame.r
				print(string.format("MESH %s %.3f %.3f %.3f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f", p.Name, c.X, c.Y, c.Z,
					r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], p.Size.X, p.Size.Y, p.Size.Z))
			end
		end
		for key, top in surface do
			print(string.format("GROUND %s %.2f %s", key, top[1], top[2]))
		end
	end
	print(string.format("PASS (%s pack): %d mountains, %d pines, %d broadleaf, %d rocks, %d cliffs, %d bushes, %d flowers, %d logs/stumps",
		PACK_MODE, counts.Mountain, counts.Pine, (counts.Birch or 0) + (counts.Oak or 0), counts.Rock, counts.Cliff, counts.Bush, counts.Flowers, (counts.Log or 0) + (counts.Stump or 0)))
	return
end
assert(highest > 110, "without the pack the terrain keeps its snowy peaks")
local parts, lights, conifers, birches, outward = 0, 0, 0, 0, 0
for _, p in instances do
	if p.Name == "Conifer" then conifers += 1 end
	if p.Name == "Birch" then birches += 1 end
	if p.Name == "Trunk" then assert(not inReserved(p.CFrame.Position), "trees stay off the leaderboard sites") end
	if p.ClassName == "Part" or p.ClassName == "WedgePart" or p.ClassName == "CornerWedgePart" then
		-- The themes' own scenery waits in ServerStorage, counted on its own above.
		if p.Parent ~= nil and not p:IsDescendantOf(ServerStorage) then
			parts += 1
			assert(p.Anchored and p.CanQuery == false and p.CanTouch == false, "scenery must not interfere with mining/physics: " .. tostring(p.Name))
			assert(p.Size.X > 0 and p.Size.Y > 0 and p.Size.Z > 0, "positive size: " .. tostring(p.Name))
		end
	elseif p.ClassName == "PointLight" then
		if not p:IsDescendantOf(ServerStorage) then lights += 1 end
		assert(not p.Shadows, "point lights skip shadows")
	end
	-- Conifer wedges slope down away from their (upright) trunk.
	if p.Name == "Needles" then
		local axis = p.Parent:FindFirstChild("Trunk").CFrame.Position
		local away = Vector3.new(p.CFrame.Position.X - axis.X, 0, p.CFrame.Position.Z - axis.Z).Unit
		local low = p.CFrame.LookVector * -PartShapes.wedgeFront()
		assert(Vector3.new(low.X, 0, low.Z).Unit:Dot(away) > 0.99, "conifer wedges slope down outward")
		outward += 1
	end
end
-- Each birch canopy is twelve wedges: six over six, all facing out from its centre.
local canopies = {}
for _, p in instances do
	if p.Name == "Leaves" then
		local list = canopies[#canopies]
		if list == nil or #list == 12 then
			list = {}
			table.insert(canopies, list)
		end
		table.insert(list, p)
	end
end
for _, list in canopies do
	assert(#list == 12, "canopies are complete")
	local centre = Vector3.zero
	for _, p in list do centre += p.CFrame.Position / 12 end
	for _, p in list do
		local away = Vector3.new(p.CFrame.Position.X - centre.X, 0, p.CFrame.Position.Z - centre.Z).Unit
		local low = p.CFrame.LookVector * -PartShapes.wedgeFront()
		assert(Vector3.new(low.X, 0, low.Z).Unit:Dot(away) > 0.99, "canopy wedges thin out towards the rim")
	end
end
assert(#canopies >= birches, "every birch has a canopy")
assert(parts < 4000, "decoration count must remain bounded: " .. parts)
-- Only parts big enough to throw a visible shadow cast one.
local casters = 0
for _, p in workspace:FindFirstChild("Scenery"):GetDescendants() do
	if p.ClassName == "Part" or p.ClassName == "WedgePart" then
		if p.CastShadow then casters += 1 end
		assert(p.Size.Magnitude >= 3 or not p.CastShadow, "small props cast no shadow: " .. p.Name)
	end
end
print(string.format("shadows: %d of %d static parts cast one", casters, parts))
assert(conifers >= 100 and conifers <= 120, "forest reaches its target: " .. conifers)
assert(birches >= 10 and birches <= 16, "birches dot the meadows: " .. birches)
assert(outward == conifers * 18, "every conifer wedge was checked")
assert(lights >= 5 and lights <= 8, "local lights stay few: " .. lights)
assert(fills == 1 and chunks == 144, "terrain chunks: " .. chunks)
assert(balls >= 30, "terrain boulders replace plastic balls: " .. balls)
assert(snow > 0 and water > 0 and air > 0, "peaks carry snow and the lake holds water")
assert(Lighting.ClockTime == 15.6 and Lighting.EnvironmentDiffuseScale == 1 and Lighting.GlobalShadows, "lighting is set up")
print(string.format("PASS: %d conifers, %d birches, %d static parts, %d local lights, %d terrain boulders, %d snow voxels",
	conifers, birches, parts, lights, balls, snow))
'''

import json

manifest = json.loads((root / "art/manifest.json").read_text(encoding="utf-8"))
table = "local MANIFEST = {\n" + "".join(f'\t["{name}"] = {{ {info["size"][0]}, {info["size"][1]}, {info["size"][2]} }},\n' for name, info in manifest.items()) + "}\n"
generated = root / "tests/scenery.generated.luau"
try:
    mock = (root / "tests/roblox-mock.luau").read_text(encoding="utf-8")
    dump = "--dump" in sys.argv
    modes = ("generated",) if dump else ("none", "generated", "studs", "tiny-zup")
    for mode in modes:
        flags = f'local PACK_MODE = "{mode}"\nlocal DUMP_PLACEMENTS = {"true" if dump else "false"}\n'
        body = (
            mock + flags + table + setup.replace('os.getenv and os.getenv("SCENERY_DUMP") ~= nil or false', "true" if dump else "false")
            + "\nlocal PartShapes = " + module("src/shared/PartShapes.luau")
            + "\nlocal Inflate = " + module("src/shared/Inflate.luau")
            + "\nlocal MeshPack = " + module("src/shared/MeshPack.luau")
            + "\nlocal ScenePackData = " + module("src/shared/ScenePackData.luau")
            + "\nlocal SceneryThemes = " + module("src/shared/SceneryThemes.luau")
            + "\nlocal ScenePack = " + module("src/server/ScenePack.luau")
            + "\nlocal SceneryView = " + module("src/client/SceneryView.luau")
            + "\nlocal Sakura = " + module("src/server/Sakura.luau")
            + "\nlocal Watchtower = " + module("src/server/Watchtower.luau")
            + "\nlocal Farm = " + module("src/server/Farm.luau")
            + "\nlocal Desert = " + module("src/server/Desert.luau")
            + "\nlocal Haunted = " + module("src/server/Haunted.luau")
            + "\nlocal PetalView = " + module("src/client/PetalView.luau")
            + "\nlocal Scenery = " + module("src/server/Scenery.luau")
            + "\n" + checks
        )
        generated.write_text(body, encoding="utf-8")
        luau = next((arg for arg in sys.argv[1:] if not arg.startswith("--")), "luau")
        if dump:
            result = subprocess.run([luau, str(generated)], check=True, capture_output=True, text=True)
            lines = [line for line in result.stdout.splitlines() if line.startswith(("MESH ", "GROUND "))]
            (root / "art/previews/layout.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
            print(f"Wrote art/previews/layout.txt ({len(lines)} lines)")
        else:
            subprocess.run([luau, str(generated)], check=True)
finally:
    generated.unlink(missing_ok=True)
