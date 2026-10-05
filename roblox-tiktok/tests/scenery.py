"""Builds the scenery under the Luau CLI with a Roblox stand-in and checks the
terrain, part budget, tree geometry and lighting.

    python3 tests/scenery.py [path/to/luau]
"""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]


def module(path: str) -> str:
    source = (root / path).read_text(encoding="utf-8")
    source = source.replace('require(ReplicatedStorage:WaitForChild("DiamondRush"):WaitForChild("PartShapes"))', "PartShapes")
    return "(function()\n" + source + "\nend)()"


setup = r'''
local Lighting = Instance.new("Lighting")
game = { GetService = function(_, name)
	if name == "Lighting" then return Lighting end
	return { WaitForChild = function() return {} end }
end }
local terrain = Instance.new("Terrain")
local fills, balls, chunks, snow, rockSteep, water, air = 0, 0, 0, 0, 0, 0, 0
terrain.SetMaterialColor = function() end
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
workspace.Raycast = function(_, at) return { Position = Vector3.new(at.X, 0, at.Z) } end
'''

checks = r'''
Scenery.build(26.4, Vector3.new(0, 0.5, 56.4))
local parts, lights, conifers, birches, outward = 0, 0, 0, 0, 0
for _, p in instances do
	if p.Name == "Conifer" then conifers += 1 end
	if p.Name == "Birch" then birches += 1 end
	if p.ClassName == "Part" or p.ClassName == "WedgePart" or p.ClassName == "CornerWedgePart" then
		if p.Parent ~= nil then
			parts += 1
			assert(p.Anchored and p.CanQuery == false and p.CanTouch == false, "scenery must not interfere with mining/physics: " .. tostring(p.Name))
			assert(p.Size.X > 0 and p.Size.Y > 0 and p.Size.Z > 0, "positive size: " .. tostring(p.Name))
		end
	elseif p.ClassName == "PointLight" then
		lights += 1
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

generated = root / "tests/scenery.generated.luau"
try:
    mock = (root / "tests/roblox-mock.luau").read_text(encoding="utf-8")
    body = (
        mock + setup
        + "\nlocal PartShapes = " + module("src/shared/PartShapes.luau")
        + "\nlocal Scenery = " + module("src/server/Scenery.luau")
        + "\n" + checks
    )
    generated.write_text(body, encoding="utf-8")
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(generated)], check=True)
finally:
    generated.unlink(missing_ok=True)
