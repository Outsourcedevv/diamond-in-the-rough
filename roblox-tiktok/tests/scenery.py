"""Builds the scenery under the Luau CLI with a Roblox stand-in and checks the
terrain, part budget, tree geometry and lighting: once with the built-in
scenery, and twice with a stand-in for the imported Blender pack (at true
size, and at 1/100 scale lying on its back) to check sizing and orientation.

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
    return "(function()\n" + source + "\nend)()"


setup = r'''
local Lighting = Instance.new("Lighting")
local ServerStorage = Instance.new("Folder")
local Replicated = Instance.new("Folder")
game = { GetService = function(_, name)
	if name == "Lighting" then return Lighting end
	if name == "ServerStorage" then return ServerStorage end
	if name == "ReplicatedStorage" then return Replicated end
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
if PACK_MODE ~= "none" then
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
if PACK_MODE ~= "none" then
	assert(pack.Parent == ServerStorage, "the imported pack is moved out of view")
	local counts = {}
	local camp = Vector3.new(0, 0, 56.4)
	for _, p in instances do
		if p.ClassName == "MeshPart" and p.Parent ~= nil and p.Parent ~= pack then
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

import json

manifest = json.loads((root / "art/manifest.json").read_text(encoding="utf-8"))
table = "local MANIFEST = {\n" + "".join(f'\t["{name}"] = {{ {info["size"][0]}, {info["size"][1]}, {info["size"][2]} }},\n' for name, info in manifest.items()) + "}\n"
generated = root / "tests/scenery.generated.luau"
try:
    mock = (root / "tests/roblox-mock.luau").read_text(encoding="utf-8")
    dump = "--dump" in sys.argv
    modes = ("studs",) if dump else ("none", "studs", "tiny-zup")
    for mode in modes:
        flags = f'local PACK_MODE = "{mode}"\nlocal DUMP_PLACEMENTS = {"true" if dump else "false"}\n'
        body = (
            mock + flags + table + setup.replace('os.getenv and os.getenv("SCENERY_DUMP") ~= nil or false', "true" if dump else "false")
            + "\nlocal PartShapes = " + module("src/shared/PartShapes.luau")
            + "\nlocal ScenePack = " + module("src/server/ScenePack.luau")
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
