--!strict
-- Builds the Blender scenery pack on this computer when the server lays it out
-- in game (see the server's ScenePack): each mesh is unpacked from
-- ScenePackData once, built as an EditableMesh and shared by all of its copies.
-- The work is spread over frames, smallest meshes first, so the game keeps
-- running smoothly while the valley fills in over a few seconds.
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("DiamondRush")
local MeshPack = require(Shared:WaitForChild("MeshPack"))

local SceneryView = {}

local PLACEMENTS = "DiamondRushSceneryPlacements" -- published by the server's ScenePack
local BUDGET = 0.004 -- seconds of building per frame

-- Built meshes and their templates stay referenced while their copies show.
local kept: { any } = {}

local function build(data: { [string]: MeshPack.Entry }, placements: { MeshPack.Placement })
	local byName: { [string]: { MeshPack.Placement } } = {}
	local names: { string } = {}
	for _, placement in placements do
		if data[placement.name] then
			local list = byName[placement.name]
			if list == nil then
				list = {}
				byName[placement.name] = list
				table.insert(names, placement.name)
			end
			table.insert(list, placement)
		end
	end
	-- Smallest first: if this computer ran short of mesh memory, the trees and
	-- rocks would still show.
	table.sort(names, function(a, b)
		return data[a].triangles < data[b].triangles
	end)
	local folder = Instance.new("Folder")
	folder.Name = "SceneryMeshes"
	folder.Parent = workspace
	local started = os.clock()
	local function pause()
		if os.clock() - started > BUDGET then
			task.wait()
			started = os.clock()
		end
	end
	local built, copies = 0, 0
	for _, name in names do
		local list = byName[name]
		local ok, problem = pcall(function()
			local mesh = MeshPack.unpack(data[name], pause)
			pause()
			local editable = MeshPack.build(mesh, AssetService, pause)
			table.insert(kept, editable)
			local collide = false
			for _, placement in list do
				collide = collide or placement.collide
			end
			local content = Content.fromObject(editable)
			local options = {
				CollisionFidelity = if collide then Enum.CollisionFidelity.Hull else Enum.CollisionFidelity.Box,
				-- The far mountains keep their full detail.
				RenderFidelity = if mesh.size.X > 200 then Enum.RenderFidelity.Precise else Enum.RenderFidelity.Automatic,
			}
			local template = AssetService:CreateMeshPartAsync(content, options)
			table.insert(kept, template)
			for _, placement in list do
				local copy = template:Clone()
				local source = copy.MeshContent
				if source.SourceType ~= Enum.ContentSourceType.Object or source.Object == nil then
					-- A copy that lost the mesh gets its own part for it.
					copy:Destroy()
					copy = AssetService:CreateMeshPartAsync(content, options)
				end
				copy.Name = name
				local size = mesh.size * placement.scale
				copy.Size = size
				copy.CFrame = MeshPack.frame(placement.ground, size.Y, placement.yaw, placement.tilt, placement.sink)
				MeshPack.dress(copy, placement.collide, placement.shadow)
				copy.Parent = folder
				copies += 1
				pause()
			end
		end)
		if not ok then
			warn("[DiamondRush] Could not build the scenery mesh " .. name .. " on this computer: " .. tostring(problem)
				.. (if built == 0 then " To show the Blender scenery anyway, import art/DiamondRushScenery.fbx (see the README)." else ""))
			-- Larger meshes would not fit either.
			break
		end
		built += 1
	end
	print(string.format("[DiamondRush] Scenery: built %d of %d Blender meshes, %d copies.", built, #names, copies))
end

function SceneryView.start()
	task.spawn(function()
		-- Only published when the server builds the pack in game.
		local value = ReplicatedStorage:WaitForChild(PLACEMENTS, math.huge) :: StringValue
		local data: { [string]: MeshPack.Entry } = require(Shared:WaitForChild("ScenePackData")) :: any
		build(data, MeshPack.decodePlacements(value.Value))
	end)
end

return SceneryView
