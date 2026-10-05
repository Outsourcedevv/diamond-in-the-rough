"""Checks the scenery pack the game builds itself, under the Luau CLI: the
base64 and DEFLATE unpacker against Python's zlib, every mesh in
src/shared/ScenePackData.luau (sizes and triangle counts against
art/manifest.json, closed outward-facing surfaces, colours, and a cross-check
with an independent Python reading of the same bytes), building each mesh with
a stand-in EditableMesh, and the placement list the server sends to clients.

    python3 tests/scene-pack.py [path/to/luau]
"""
from pathlib import Path
import base64
import json
import random
import re
import struct
import subprocess
import sys
import zlib

root = Path(__file__).resolve().parents[1]


def module(path: str) -> str:
    source = (root / path).read_text(encoding="utf-8")
    source = source.replace('require(script.Parent:WaitForChild("Inflate"))', "Inflate")
    return "(function()\n" + source + "\nend)()"


def deflate(data: bytes, level: int = 9, strategy: int = zlib.Z_DEFAULT_STRATEGY) -> bytes:
    packer = zlib.compressobj(level, zlib.DEFLATED, -15, 9, strategy)
    return packer.compress(data) + packer.flush()


# Inflate cases: every block type, long and overlapping copies, many blocks.
rng = random.Random(7)
text = (root / "README.md").read_bytes()
noise = bytes(rng.randrange(256) for _ in range(70000))
cases = [
    ("empty", b"", 9, zlib.Z_DEFAULT_STRATEGY),
    ("one byte", b"x", 9, zlib.Z_DEFAULT_STRATEGY),
    ("repeated byte", b"a" * 5000, 9, zlib.Z_DEFAULT_STRATEGY),
    ("stored blocks", noise, 0, zlib.Z_DEFAULT_STRATEGY),
    ("incompressible", noise[:9000], 9, zlib.Z_DEFAULT_STRATEGY),
    ("text fast", text, 1, zlib.Z_DEFAULT_STRATEGY),
    ("text best", text, 9, zlib.Z_DEFAULT_STRATEGY),
    ("fixed codes", text[:20000], 9, zlib.Z_FIXED),
    ("huffman only", text[:20000], 9, zlib.Z_HUFFMAN_ONLY),
    ("run lengths", bytes(i // 7 % 5 for i in range(30000)), 9, zlib.Z_RLE),
]
inflate_cases = "local INFLATE_CASES = {\n" + "".join(
    f'\t{{ name = "{name}", packed = "{base64.b64encode(deflate(data, level, strategy)).decode()}", raw = "{base64.b64encode(data).decode()}", size = {len(data)} }},\n'
    for name, data, level, strategy in cases
) + "}\n"


# An independent reading of each packed mesh, to cross-check the Luau one.
def read_mesh(data: bytes):
    vertices, triangles, colours, flags, step, ex, ey, ez = struct.unpack_from("<HHHBf3H", data, 0)
    at = 17

    def varint():
        nonlocal at
        value, shift = 0, 0
        while True:
            byte = data[at]
            at += 1
            value |= (byte & 0x7F) << shift
            shift += 7
            if byte < 0x80:
                return value >> 1 if value % 2 == 0 else -((value + 1) >> 1)

    x = y = z = 0
    total = [0.0, 0.0, 0.0]
    for _ in range(vertices):
        x += varint()
        y += varint()
        z += varint()
        total[0] += (x - ex / 2) * step
        total[1] += (y - ey / 2) * step
        total[2] += (z - ez / 2) * step
    index, corner_sum = 0, 0
    for _ in range(triangles * 3):
        index += varint()
        corner_sum += index + 1
    return {"vertices": vertices, "triangles": triangles, "sum": total, "corners": corner_sum}


data_source = (root / "src/shared/ScenePackData.luau").read_text(encoding="utf-8")
expected = {}
for name, size, triangles, length, payload in re.findall(
    r"\t(\w+) = \{ size = \{ ([^}]*) \}, triangles = (\d+), bytes = (\d+), data = \[\[\n(.*?)\]\] \}", data_source, re.S
):
    raw = zlib.decompress(base64.b64decode(payload.replace("\n", "")), -15)
    assert len(raw) == int(length), name
    expected[name] = read_mesh(raw)
manifest = json.loads((root / "art/manifest.json").read_text(encoding="utf-8"))
assert sorted(expected) == sorted(manifest), "the game data and the manifest list the same meshes"
reference = "local REFERENCE = {\n" + "".join(
    f'\t{name} = {{ vertices = {e["vertices"]}, triangles = {e["triangles"]}, corners = {e["corners"]}, '
    f'sum = {{ {e["sum"][0]!r}, {e["sum"][1]!r}, {e["sum"][2]!r} }}, '
    f'authored = {{ {manifest[name]["size"][0]}, {manifest[name]["size"][2]}, {manifest[name]["size"][1]} }} }},\n'
    for name, e in expected.items()
) + "}\n"

test = r'''
local passed = 0
local function check(condition: boolean, message: string)
	if not condition then error("FAIL " .. message, 2) end
	passed += 1
end

-- Base64 and DEFLATE match Python's zlib on every kind of block.
check(buffer.tostring(Inflate.base64("SGVs\nbG8s IHdvcmxkIQ==")) == "Hello, world!", "base64 skips line breaks, spaces and padding")
for _, case in INFLATE_CASES do
	local raw = buffer.tostring(Inflate.base64(case.raw))
	check(#raw == case.size, case.name .. ": base64 length")
	check(buffer.tostring(Inflate.inflate(Inflate.base64(case.packed), case.size)) == raw, case.name .. ": unpacks exactly")
end
local sample = INFLATE_CASES[7]
local packed = buffer.tostring(Inflate.base64(sample.packed))
check(not pcall(Inflate.inflate, buffer.fromstring(string.sub(packed, 1, #packed // 2)), sample.size), "cut-short data is an error")
check(not pcall(Inflate.inflate, buffer.fromstring(packed), sample.size - 1), "a wrong size is an error")

-- Every mesh in the pack.
local started = os.clock()
local meshes = {}
local unpackPauses = 0
for name, entry in ScenePackData do
	meshes[name] = MeshPack.unpack(entry, function() unpackPauses += 1 end)
end
local unpackTime = os.clock() - started
check(unpackPauses > 50, "unpacking pauses now and then for the frame budget")
local count = 0
for name, mesh in meshes do
	count += 1
	local entry, want = ScenePackData[name], REFERENCE[name]
	local triangles = #mesh.corners // 3
	check(triangles == want.triangles and triangles == entry.triangles and #mesh.positions == want.vertices, name .. ": triangle and vertex counts")
	check(triangles <= 20000 and #mesh.positions <= 60000, name .. ": within the EditableMesh limits")
	-- Sizes agree with the authored size (Blender's depth and height swap for Y up).
	for axis, value in { mesh.size.X, mesh.size.Y, mesh.size.Z } do
		check(math.abs(value - want.authored[axis]) < 0.15, name .. ": size matches the manifest on axis " .. axis)
		check(math.abs(value - entry.size[axis]) < 0.01, name .. ": size matches its entry on axis " .. axis)
	end
	-- Same numbers as the independent Python reading of the bytes.
	local sum, cornerSum = Vector3.zero, 0
	local low, high = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, p in mesh.positions do
		sum += p
		low = Vector3.new(math.min(low.X, p.X), math.min(low.Y, p.Y), math.min(low.Z, p.Z))
		high = Vector3.new(math.max(high.X, p.X), math.max(high.Y, p.Y), math.max(high.Z, p.Z))
	end
	for _, c in mesh.corners do cornerSum += c end
	check(math.abs(sum.X - want.sum[1]) < 0.05 and math.abs(sum.Y - want.sum[2]) < 0.05 and math.abs(sum.Z - want.sum[3]) < 0.05, name .. ": positions agree with Python")
	check(cornerSum == want.corners, name .. ": triangle corners agree with Python")
	-- Centred on its bounding box, which is where a MeshPart has its origin.
	local centre = (low + high) / 2
	check(math.abs(centre.X) < 0.01 and math.abs(centre.Y) < 0.01 and math.abs(centre.Z) < 0.01, name .. ": centred on its bounding box")
	-- Closed: every edge is shared by exactly two triangles, running opposite
	-- ways. Outward: the enclosed volume is positive with counter-clockwise front
	-- faces, so the faces Roblox draws are the outside ones.
	local edges = {}
	local volume = 0
	local vertices = #mesh.positions
	for t = 0, triangles - 1 do
		local a, b, c = mesh.corners[3 * t + 1], mesh.corners[3 * t + 2], mesh.corners[3 * t + 3]
		check(a >= 1 and a <= vertices and b >= 1 and b <= vertices and c >= 1 and c <= vertices and a ~= b and b ~= c and a ~= c, name .. ": triangle corners are valid")
		for _, edge in { { a, b }, { b, c }, { c, a } } do
			local key = edge[1] * 65536 + edge[2]
			check(edges[key] == nil, name .. ": no edge is used twice the same way")
			edges[key] = true
		end
		local pa, pb, pc = mesh.positions[a], mesh.positions[b], mesh.positions[c]
		volume += pa:Dot(pb:Cross(pc)) / 6
		check((pb - pa):Cross(pc - pa).Magnitude > 1e-9, name .. ": no triangle collapses when positions are rounded")
	end
	for key in edges do
		local a, b = key // 65536, key % 65536
		check(edges[b * 65536 + a] == true, name .. ": every edge has a partner, so the mesh is closed")
	end
	local box = mesh.size.X * mesh.size.Y * mesh.size.Z
	check(volume > box * 0.01 and volume < box, name .. ": faces point outward (volume " .. math.floor(volume) .. ")")
	-- Colours: per vertex on the smooth mountains, per facet elsewhere.
	check(#mesh.colours == (if mesh.perVertex then vertices else triangles), name .. ": one colour per vertex or per triangle")
	for _, k in mesh.colours do check(k >= 1 and k <= #mesh.palette, name .. ": colour indices are valid") end
	check(#mesh.palette >= 20, name .. ": shaded with many colours")
	if string.match(name, "^Mountain") then
		check(mesh.perVertex, name .. ": mountain colours blend across the surface")
		local smooth = 0
		for _, s in mesh.smooth do if s then smooth += 1 end end
		check(smooth == triangles, name .. ": mountains are smooth shaded")
	end
end
check(count == 25, "all 25 meshes are in the pack")
-- The snowy peaks are white, the forest pines green.
local function average(mesh, per): Color3
	local r, g, b = 0, 0, 0
	for _, k in mesh.colours do
		local c = mesh.palette[k]
		r += c.R; g += c.G; b += c.B
	end
	return Color3.new(r / #mesh.colours, g / #mesh.colours, b / #mesh.colours)
end
local pine = average(meshes.Pine_A)
check(pine.G > pine.R and pine.G > pine.B, "pines are green")
local snowiest = 0
for _, c in meshes.Mountain_A.palette do
	if c.R > 0.9 and c.G > 0.9 and c.B > 0.9 then snowiest += 1 end
end
check(snowiest > 20, "mountains carry snow")

-- Building with a stand-in EditableMesh: every triangle gets its normals and
-- colours, flat facets get their own normal, smooth ones share per vertex.
local function fakeMesh()
	local m = { vertices = {}, faces = {}, normals = 0, colours = {}, faceNormals = {}, faceColours = {}, cleaned = false }
	function m:AddVertex(p) table.insert(self.vertices, p); return #self.vertices end
	function m:AddColor(c, alpha) assert(alpha == 1); table.insert(self.colours, c); return #self.colours end
	function m:AddNormal(n) assert(n == nil, "normals are worked out by the engine"); self.normals += 1; return self.normals end
	function m:AddTriangle(a, b, c) table.insert(self.faces, { a, b, c }); return #self.faces end
	function m:SetFaceNormals(f, ids) assert(#ids == 3); self.faceNormals[f] = ids end
	function m:SetFaceColors(f, ids) assert(#ids == 3); self.faceColours[f] = ids end
	function m:RemoveUnused() self.cleaned = true end
	return m
end
local assets = { CreateEditableMesh = function() return fakeMesh() end }
local pauses = 0
for _, name in { "Mountain_B", "Pine_Snow_A", "Birch_A", "Rock_C", "Log_A" } do
	local mesh = meshes[name]
	local built = MeshPack.build(mesh, assets, function() pauses += 1 end)
	local triangles = #mesh.corners // 3
	check(#built.vertices == #mesh.positions and #built.faces == triangles and built.cleaned, name .. ": every vertex and triangle is built")
	local owner = {}
	for t, face in built.faces do
		local normals, colours = built.faceNormals[t], built.faceColours[t]
		check(normals ~= nil and colours ~= nil, name .. ": each triangle has normals and colours")
		for i = 1, 3 do
			local v = face[i]
			check(v == mesh.corners[3 * (t - 1) + i], name .. ": triangle corners in order")
			local want = if mesh.perVertex then mesh.colours[v] else mesh.colours[t]
			check(built.colours[colours[i]] == mesh.palette[want], name .. ": corner colour")
			local key = normals[i]
			local tag = if mesh.smooth[t] then "v" .. v else "f" .. t
			check(owner[key] == nil or owner[key] == tag, name .. ": normals are shared only within a vertex or a facet")
			owner[key] = tag
		end
		if not mesh.smooth[t] then check(normals[1] == normals[2] and normals[2] == normals[3], name .. ": flat facets have one normal") end
	end
end
check(pauses > 40, "building pauses now and then for the frame budget")

-- Placements survive the trip to the clients.
local list = {
	{ name = "Pine_A", ground = Vector3.new(101.237, 12.5, -88.004), scale = 1.1234, yaw = 2.5, tilt = 0, sink = 0.4, collide = false, shadow = true },
	{ name = "Rock_C", ground = Vector3.new(-5, -3.2, 7), scale = 0.8, yaw = -0.25, tilt = 0.11, sink = 2.25, collide = true, shadow = true },
	{ name = "Flowers_White", ground = Vector3.new(0, 0, 0), scale = 1.5, yaw = 6.2, tilt = 0, sink = 0.1, collide = false, shadow = false },
}
local back = MeshPack.decodePlacements(MeshPack.encodePlacements(list))
check(#back == 3, "every placement is sent")
for i, p in list do
	local q = back[i]
	check(q.name == p.name and (q.ground - p.ground).Magnitude < 0.01 and math.abs(q.scale - p.scale) < 0.001 and math.abs(q.yaw - p.yaw) < 0.001
		and math.abs(q.tilt - p.tilt) < 0.001 and math.abs(q.sink - p.sink) < 0.01 and q.collide == p.collide and q.shadow == p.shadow, "placement " .. i .. " round trip")
end
check(#MeshPack.decodePlacements("") == 0, "no placements")
-- A placed mesh stands on the ground, sunk by `sink`.
local frame = MeshPack.frame(Vector3.new(3, 10, 4), 20, 1.2, 0, 1.5)
check((frame.Position - Vector3.new(3, 18.5, 4)).Magnitude < 1e-6 and math.abs(frame.UpVector.Y - 1) < 1e-9, "placed upright on the ground")

print(string.format("PASS: %d scenery pack checks (unpacked %d meshes in %.0f ms)", passed, count, unpackTime * 1000))
'''

generated = root / "tests/scene-pack.generated.luau"
try:
    mock = (root / "tests/roblox-mock.luau").read_text(encoding="utf-8")
    body = (
        mock + inflate_cases + reference
        + "\nlocal Inflate = " + module("src/shared/Inflate.luau")
        + "\nlocal MeshPack = " + module("src/shared/MeshPack.luau")
        + "\nlocal ScenePackData = " + module("src/shared/ScenePackData.luau")
        + "\n" + test
    )
    generated.write_text(body, encoding="utf-8")
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(generated)], check=True)
finally:
    generated.unlink(missing_ok=True)
