--!strict
-- The optional scenery pack made in Blender (art/scenery_assets.py): mesh
-- mountains, trees, rocks, cliffs, bushes, flowers, logs and stumps. The
-- streamer imports art/DiamondRushScenery.fbx into Studio once (see README);
-- Scenery uses it when present and falls back to its built-in parts if not.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ScenePack = {}

ScenePack.NAME = "DiamondRushScenery"
-- A known asset calibrates the import: its authored height (art/manifest.json)
-- against its imported size gives the scale, whatever units the importer used.
ScenePack.REFERENCE = { name = "Pine_A", height = 25.7 }

export type Pack = {
	meshes: { [string]: MeshPart },
	unit: number, -- imported studs per authored stud
	upright: boolean, -- false if the importer laid the pack on its back (Z up)
	fix: CFrame,
}

-- Finds the imported pack (in ServerStorage, ReplicatedStorage or the
-- Workspace, where Studio's importer puts it) and keeps the originals out of view.
function ScenePack.find(): Pack?
	local container: Instance? = nil
	for _, place in { ServerStorage, ReplicatedStorage, workspace } :: { Instance } do
		container = place:FindFirstChild(ScenePack.NAME)
		if container then break end
	end
	if container == nil then return nil end
	if container:IsDescendantOf(workspace) then
		container.Parent = ServerStorage
	end
	local meshes: { [string]: MeshPart } = {}
	for _, item in container:GetDescendants() do
		if item:IsA("MeshPart") then
			-- Blender-style ".001" suffixes are ignored.
			local name = string.gsub(item.Name, "%.%d+$", "")
			meshes[name] = meshes[name] or item
		end
	end
	local reference: MeshPart? = meshes[ScenePack.REFERENCE.name]
	if reference == nil then
		warn("[DiamondRush] " .. ScenePack.NAME .. " has no " .. ScenePack.REFERENCE.name .. " mesh; using the built-in scenery.")
		return nil
	end
	local size = (reference :: MeshPart).Size
	local upright = size.Y >= math.max(size.X, size.Z)
	local vertical = if upright then size.Y else size.Z
	return {
		meshes = meshes,
		unit = vertical / ScenePack.REFERENCE.height,
		upright = upright,
		-- Turns a pack imported with Z up so its tops point to the sky.
		fix = if upright then CFrame.identity else CFrame.Angles(-math.pi / 2, 0, 0),
	}
end

export type Options = { sink: number?, collide: boolean?, shadow: boolean?, tilt: number? }

-- Places a copy of `name` standing on `ground`, `scale` times its authored size,
-- turned by `yaw`. Returns the copy, or nil when the pack lacks that mesh.
function ScenePack.place(pack: Pack, parent: Instance, name: string, ground: Vector3, scale: number, yaw: number, options: Options?): MeshPart?
	local found: MeshPart? = pack.meshes[name]
	if found == nil then return nil end
	local template = found :: MeshPart
	local settings: Options = options or {}
	local copy = template:Clone()
	copy.Size = template.Size / pack.unit * scale
	local height = if pack.upright then copy.Size.Y else copy.Size.Z
	local tilt = settings.tilt or 0
	copy.CFrame = CFrame.new(ground + Vector3.new(0, height / 2 - (settings.sink or 0), 0))
		* CFrame.Angles(0, yaw, 0) * CFrame.Angles(tilt, 0, tilt * 0.6) * pack.fix
	copy.Anchored = true
	copy.CanCollide = settings.collide == true
	copy.CanQuery = false
	copy.CanTouch = false
	copy.CastShadow = settings.shadow ~= false
	-- The colours live in the mesh (vertex colours); keep the part untinted.
	copy.Material = Enum.Material.SmoothPlastic
	copy.Color = Color3.new(1, 1, 1)
	copy.Parent = parent
	return copy
end

-- Authored height of a pack mesh, in studs.
function ScenePack.height(pack: Pack, name: string): number
	local found: MeshPart? = pack.meshes[name]
	if found == nil then return 0 end
	local template = found :: MeshPart
	return (if pack.upright then template.Size.Y else template.Size.Z) / pack.unit
end

return ScenePack
