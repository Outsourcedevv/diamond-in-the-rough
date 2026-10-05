--!strict
-- The scenery pack made in Blender (art/scenery_assets.py): mesh mountains,
-- trees, rocks, cliffs, bushes, flowers, logs and stumps. Scenery lays it out
-- in one of two ways:
--
-- * Built in game (the usual way, nothing to import): the meshes ship as data
--   in ScenePackData, and each player's game builds them with EditableMesh
--   (client SceneryView), where the server publishes the placements. This works
--   in Studio, and in a published game once Mesh / Image APIs are enabled.
-- * Imported: if art/DiamondRushScenery.fbx was imported into Studio, its
--   MeshParts are placed by the server like any other part, which works in any
--   published game.
--
-- With neither, Scenery falls back to its built-in parts.
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Shared = ReplicatedStorage:WaitForChild("DiamondRush")
local MeshPack = require(Shared:WaitForChild("MeshPack"))
local ScenePackData: { [string]: MeshPack.Entry } = require(Shared:WaitForChild("ScenePackData")) :: any

local ScenePack = {}

ScenePack.NAME = "DiamondRushScenery"
-- Where the server publishes the placements for the built-in-game pack.
ScenePack.PLACEMENTS = "DiamondRushSceneryPlacements"
-- A known asset calibrates an import: its authored height (art/manifest.json)
-- against its imported size gives the scale, whatever units the importer used.
ScenePack.REFERENCE = { name = "Pine_A", height = 25.7 }

export type Pack = {
	generated: boolean, -- built in game from ScenePackData, not imported
	meshes: { [string]: MeshPart }, -- imported meshes
	unit: number, -- imported studs per authored stud
	upright: boolean, -- false if the importer laid the pack on its back (Z up)
	fix: CFrame,
	placements: { MeshPack.Placement }, -- built in game: what the clients build
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
		warn("[DiamondRush] " .. ScenePack.NAME .. " has no " .. ScenePack.REFERENCE.name .. " mesh, so it is not used.")
		return nil
	end
	local size = (reference :: MeshPart).Size
	local upright = size.Y >= math.max(size.X, size.Z)
	local vertical = if upright then size.Y else size.Z
	return {
		generated = false,
		meshes = meshes,
		unit = vertical / ScenePack.REFERENCE.height,
		upright = upright,
		-- Turns a pack imported with Z up so its tops point to the sky.
		fix = if upright then CFrame.identity else CFrame.Angles(-math.pi / 2, 0, 0),
		placements = {},
	}
end

-- The pack built in game, if EditableMesh can be used here: always in Studio;
-- in a published game only once the owner has turned on Mesh / Image APIs
-- (Creator Dashboard, after age and ID verification).
function ScenePack.generated(): Pack?
	local ok, mesh = pcall(function()
		return AssetService:CreateEditableMesh()
	end)
	if not ok or mesh == nil then return nil end
	local probe: EditableMesh = mesh
	probe:Destroy()
	return { generated = true, meshes = {}, unit = 1, upright = true, fix = CFrame.identity, placements = {} }
end

export type Options = { sink: number?, collide: boolean?, shadow: boolean?, tilt: number? }

-- Places a copy of `name` standing on `ground`, `scale` times its authored size,
-- turned by `yaw`. Returns the imported copy (nil when built in game, or when
-- the pack lacks that mesh).
function ScenePack.place(pack: Pack, parent: Instance, name: string, ground: Vector3, scale: number, yaw: number, options: Options?): MeshPart?
	local settings: Options = options or {}
	local tilt, sink = settings.tilt or 0, settings.sink or 0
	if pack.generated then
		if ScenePackData[name] then
			table.insert(pack.placements, {
				name = name,
				ground = ground,
				scale = scale,
				yaw = yaw,
				tilt = tilt,
				sink = sink,
				collide = settings.collide == true,
				shadow = settings.shadow ~= false,
			})
		end
		return nil
	end
	local found: MeshPart? = pack.meshes[name]
	if found == nil then return nil end
	local template = found :: MeshPart
	local copy = template:Clone()
	copy.Size = template.Size / pack.unit * scale
	local height = if pack.upright then copy.Size.Y else copy.Size.Z
	copy.CFrame = MeshPack.frame(ground, height, yaw, tilt, sink) * pack.fix
	MeshPack.dress(copy, settings.collide == true, settings.shadow ~= false)
	copy.Parent = parent
	return copy
end

-- Authored height of a pack mesh, in studs.
function ScenePack.height(pack: Pack, name: string): number
	if pack.generated then
		local entry = ScenePackData[name]
		return if entry then entry.size[2] else 0
	end
	local found: MeshPart? = pack.meshes[name]
	if found == nil then return 0 end
	local template = found :: MeshPart
	return (if pack.upright then template.Size.Y else template.Size.Z) / pack.unit
end

-- Sends the placements of a pack built in game to every player's game.
function ScenePack.publish(pack: Pack)
	if not pack.generated then return end
	local value = Instance.new("StringValue")
	value.Name = ScenePack.PLACEMENTS
	value.Value = MeshPack.encodePlacements(pack.placements)
	value.Parent = ReplicatedStorage
end

return ScenePack
