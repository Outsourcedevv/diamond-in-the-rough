--!strict
-- Builds the Blender scenery pack on this computer when the server lays it out
-- in game (see the server's ScenePack): each mesh is unpacked from
-- ScenePackData once, built as an EditableMesh and shared by all of its copies.
-- The work is spread over frames, smallest meshes first, so the game keeps
-- running smoothly while the valley fills in over a few seconds. Trees and
-- plants a map theme hides (see SceneryThemes) are taken out of view while
-- that theme shows.
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("DiamondRush")
local MeshPack = require(Shared:WaitForChild("MeshPack"))
local SceneryThemes = require(Shared:WaitForChild("SceneryThemes"))

local SceneryView = {}

local PLACEMENTS = "DiamondRushSceneryPlacements" -- published by the server's ScenePack
local BUDGET = 0.004 -- seconds of building per frame

-- Built meshes and their templates stay referenced while their copies show.
local kept: { any } = {}
-- Copies some theme may hide, and the theme showing now.
local themed: { MeshPart } = {}
local theme: string? = nil
local folder: Folder? = nil

-- Takes the copies the theme hides out of view and puts the rest back.
local function applyTheme()
	for _, copy in themed do
		copy.Parent = if SceneryThemes.hides(theme, copy.Name) then nil else folder
	end
end

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
	local meshes = Instance.new("Folder")
	meshes.Name = "SceneryMeshes"
	meshes.Parent = workspace
	folder = meshes
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
				if SceneryThemes.themed(name) then
					table.insert(themed, copy)
					copy.Parent = if SceneryThemes.hides(theme, name) then nil else meshes
				else
					copy.Parent = meshes
				end
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
		-- Follow the map theme (the server's State "Theme").
		local state = ReplicatedStorage:FindFirstChild("DiamondRushState") or ReplicatedStorage:WaitForChild("DiamondRushState", 10)
		if state then
			local function refresh()
				local value = state:GetAttribute("Theme")
				theme = if type(value) == "string" then value else nil
				applyTheme()
			end
			state:GetAttributeChangedSignal("Theme"):Connect(refresh)
			refresh()
		end
		build(data, MeshPack.decodePlacements(value.Value))
	end)
end

return SceneryView
