--!strict
--!native
-- The Blender scenery pack (art/scenery_assets.py) as meshes the game builds by
-- itself: unpacks a mesh from ScenePackData and builds it as an EditableMesh,
-- so nothing has to be imported into Studio. Also the placement list the server
-- sends to clients, and the placement maths shared with an imported pack.
local Inflate = require(script.Parent:WaitForChild("Inflate"))

local MeshPack = {}

export type Entry = { size: { number }, triangles: number, bytes: number, data: string }

export type Mesh = {
	size: Vector3, -- bounding box in studs; the positions are centred on it
	positions: { Vector3 },
	corners: { number }, -- three vertex indices per triangle, front faces counter-clockwise
	palette: { Color3 },
	colours: { number }, -- palette index per vertex (perVertex) or per triangle
	perVertex: boolean,
	smooth: { boolean }, -- per triangle: shared vertex normals, or a flat facet
}

local HEADER = 17

-- Unpacks one ScenePackData entry (see pack_mesh in art/scenery_assets.py).
-- `pause` is called now and then, so the work can be spread over frames.
function MeshPack.unpack(entry: Entry, pause: (() -> ())?): Mesh
	local data = Inflate.inflate(Inflate.base64(entry.data), entry.bytes, pause)
	local at = HEADER
	local function varint(): number
		local value, scale = 0, 1
		while true do
			local byte = buffer.readu8(data, at)
			at += 1
			if byte < 0x80 then
				value += byte * scale
				break
			end
			value += (byte - 0x80) * scale
			scale *= 128
		end
		-- Zigzag: 0, -1, 1, -2, 2 ... are stored as 0, 1, 2, 3, 4 ...
		return if value % 2 == 0 then value // 2 else -((value + 1) // 2)
	end
	local vertexCount = buffer.readu16(data, 0)
	local triangleCount = buffer.readu16(data, 2)
	local paletteCount = buffer.readu16(data, 4)
	local perVertex = buffer.readu8(data, 6) == 1
	local step = buffer.readf32(data, 7)
	local ex, ey, ez = buffer.readu16(data, 11), buffer.readu16(data, 13), buffer.readu16(data, 15)

	local positions = table.create(vertexCount)
	local x, y, z = 0, 0, 0
	for i = 1, vertexCount do
		x += varint()
		y += varint()
		z += varint()
		positions[i] = Vector3.new((x - ex / 2) * step, (y - ey / 2) * step, (z - ez / 2) * step)
		if pause and i % 2048 == 0 then pause() end
	end
	local corners = table.create(triangleCount * 3)
	local index = 0
	for i = 1, triangleCount * 3 do
		index += varint()
		corners[i] = index + 1
		if pause and i % 6144 == 0 then pause() end
	end
	local palette = table.create(paletteCount)
	for i = 1, paletteCount do
		palette[i] = Color3.fromRGB(buffer.readu8(data, at), buffer.readu8(data, at + 1), buffer.readu8(data, at + 2))
		at += 3
	end
	local colourCount = if perVertex then vertexCount else triangleCount
	local colours = table.create(colourCount)
	for i = 1, colourCount do
		colours[i] = varint() + 1
	end
	local smooth = table.create(triangleCount)
	for i = 0, triangleCount - 1 do
		smooth[i + 1] = bit32.btest(buffer.readu8(data, at + i // 8), bit32.lshift(1, i % 8))
	end
	at += (triangleCount + 7) // 8
	if at ~= buffer.len(data) then error("MeshPack: the mesh data has the wrong length") end
	return {
		size = Vector3.new(ex * step, ey * step, ez * step),
		positions = positions,
		corners = corners,
		palette = palette,
		colours = colours,
		perVertex = perVertex,
		smooth = smooth,
	}
end

-- Builds `mesh` as an EditableMesh. Smooth triangles share one normal per
-- vertex; flat ones get their own, so facets stay crisp. `pause` is called
-- now and then, so the work can be spread over frames.
function MeshPack.build(mesh: Mesh, assets: AssetService, pause: (() -> ())?): EditableMesh
	local editable = assets:CreateEditableMesh()
	local vertices = table.create(#mesh.positions)
	for i, position in mesh.positions do
		vertices[i] = editable:AddVertex(position)
	end
	local colours = table.create(#mesh.palette)
	for i, colour in mesh.palette do
		colours[i] = editable:AddColor(colour, 1)
	end
	local normals: { [number]: number } = {}
	local function smoothNormal(vertex: number): number
		local normal = normals[vertex]
		if normal == nil then
			-- With no value given, the normal is worked out from its triangles.
			normal = editable:AddNormal()
			normals[vertex] = normal
		end
		return normal :: number
	end
	local corners, colourOf, perVertex = mesh.corners, mesh.colours, mesh.perVertex
	for t = 1, #corners // 3 do
		local a, b, c = corners[3 * t - 2], corners[3 * t - 1], corners[3 * t]
		local face = editable:AddTriangle(vertices[a], vertices[b], vertices[c])
		if mesh.smooth[t] then
			editable:SetFaceNormals(face, { smoothNormal(a), smoothNormal(b), smoothNormal(c) })
		else
			local flat = editable:AddNormal()
			editable:SetFaceNormals(face, { flat, flat, flat })
		end
		if perVertex then
			editable:SetFaceColors(face, { colours[colourOf[a]], colours[colourOf[b]], colours[colourOf[c]] })
		else
			local colour = colours[colourOf[t]]
			editable:SetFaceColors(face, { colour, colour, colour })
		end
		if pause and t % 256 == 0 then pause() end
	end
	-- Drops the normals and colours AddTriangle made before they were replaced.
	editable:RemoveUnused()
	return editable
end

-- Where a pack mesh `height` studs tall stands: on `ground`, sunk by `sink`,
-- turned by `yaw` and leaning by `tilt`.
function MeshPack.frame(ground: Vector3, height: number, yaw: number, tilt: number, sink: number): CFrame
	return CFrame.new(ground + Vector3.new(0, height / 2 - sink, 0)) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(tilt, 0, tilt * 0.6)
end

-- Pack meshes are static scenery, coloured by their vertex colours.
function MeshPack.dress(part: MeshPart, collide: boolean, shadow: boolean)
	part.Anchored = true
	part.CanCollide = collide
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = shadow
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.new(1, 1, 1)
end

export type Placement = {
	name: string,
	ground: Vector3,
	scale: number,
	yaw: number,
	tilt: number,
	sink: number,
	collide: boolean,
	shadow: boolean,
}

-- One line per placement: name, ground x y z, scale, yaw, tilt, sink, flags.
function MeshPack.encodePlacements(list: { Placement }): string
	local lines = table.create(#list)
	for i, p in list do
		local flags = (if p.collide then 1 else 0) + (if p.shadow then 2 else 0)
		lines[i] = string.format("%s %.2f %.2f %.2f %.3f %.3f %.3f %.2f %d", p.name, p.ground.X, p.ground.Y, p.ground.Z,
			p.scale, p.yaw, p.tilt, p.sink, flags)
	end
	return table.concat(lines, "\n")
end

function MeshPack.decodePlacements(text: string): { Placement }
	local list = {}
	for line in string.gmatch(text, "[^\n]+") do
		local f = string.split(line, " ")
		local numbers = table.create(8, 0)
		for i = 2, 9 do
			numbers[i - 1] = tonumber(f[i]) or 0
		end
		table.insert(list, {
			name = f[1],
			ground = Vector3.new(numbers[1], numbers[2], numbers[3]),
			scale = numbers[4],
			yaw = numbers[5],
			tilt = numbers[6],
			sink = numbers[7],
			collide = numbers[8] % 2 == 1,
			shadow = numbers[8] // 2 % 2 == 1,
		})
	end
	return list
end

return MeshPack
