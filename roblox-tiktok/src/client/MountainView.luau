--!strict
--!native
-- Draws the mountain on this client. The server only keeps the rock grid and
-- sends a snapshot plus compact change lists (MountainCodec). Every exposed cell
-- gets exactly one local part; shapes slope towards open air (RockStyle).
--
-- Local parts cost no replication, collide with the local character and block
-- clicks, exactly like server parts did. All work runs in one worker with a
-- per-frame time budget, so a 100,000-rock gift opens over a few frames
-- instead of freezing the game.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("DiamondRush")
local Grid = require(Shared:WaitForChild("Grid"))
local RockStyle = require(Shared:WaitForChild("RockStyle"))
local Codec = require(Shared:WaitForChild("MountainCodec"))
local PartShapes = require(Shared:WaitForChild("PartShapes"))

local MountainView = {}
MountainView.__index = MountainView

local SPAN, LAYER = Grid.SPAN, Grid.LAYER
local STEPS = Grid.STEPS
local SIDES = { 1, -1, SPAN, -SPAN }
local hasBit = Grid.hasBit
local POOL_LIMIT = 3000
local DEBRIS_PER_CHANGE = 4
local DEBRIS_LIMIT = 24
local REBUILD_LAYERS = 16
local REBUILD_STEP = 0.15 -- seconds between rebuild layers, matching the server

-- Materials per layer for each skin (stone, or hay: see Skin).
local MATERIALS: { [string]: { Enum.Material } } = {}
for skin, palette in RockStyle.SKINS do
	MATERIALS[skin] = {}
	for index, layer in palette.layers do
		MATERIALS[skin][index] = (Enum.Material :: any)[layer.material]
	end
end

-- Rotation for every shape code, so a wedge slopes down towards open air and a
-- corner wedge turns its tall corner away from both open sides.
local function shapeRotations(): { [number]: CFrame }
	local rotations: { [number]: CFrame } = { [RockStyle.BLOCK] = CFrame.identity }
	for code, direction in RockStyle.DIRECTIONS do
		rotations[code] = if code <= 5
			then PartShapes.wedgeToward(Vector3.new(direction[1], 0, direction[2]))
			else PartShapes.cornerToward(-direction[1], -direction[2])
	end
	return rotations
end

export type View = typeof(setmetatable({} :: {
	folder: Folder?,
	grid: Grid.Grid?,
	parts: { [number]: BasePart },
	codes: { [number]: number },
	keys: { [BasePart]: number },
	tops: { [number]: number },
	pool: { { BasePart } },
	templates: { BasePart },
	rotations: { [number]: CFrame },
	queue: { any },
	head: number,
	tail: number,
	round: number,
	height: number,
	blockSize: number,
	skin: string,
	ready: boolean,
	meta: any,
	sliceStart: number,
	debris: { any },
	debrisConnection: RBXScriptConnection?,
	onRebuild: ((any) -> ())?,
	onRestore: ((any) -> ())?,
}, MountainView))

function MountainView.new(): View
	local self = setmetatable({
		folder = nil,
		grid = nil,
		parts = {},
		codes = {},
		keys = {},
		tops = {},
		pool = { {}, {}, {} },
		templates = {},
		rotations = shapeRotations(),
		queue = {},
		head = 1,
		tail = 0,
		round = 0,
		height = 1,
		blockSize = 0.4,
		skin = "stone",
		ready = false,
		meta = nil,
		sliceStart = os.clock(),
		debris = {},
		debrisConnection = nil,
		onRebuild = nil,
		onRestore = nil,
	}, MountainView)
	return self
end

function MountainView._makeTemplates(self: View)
	local size = self.blockSize * 1.02 -- a hair of overlap hides seams between cells
	for kind, className in { "Part", "WedgePart", "CornerWedgePart" } do
		local part = Instance.new(className) :: BasePart
		part.Name = "Stone"
		part.Size = Vector3.new(size, size, size)
		part.Anchored = true
		part.CanCollide = true
		part.CanQuery = true
		part.CanTouch = false
		-- Thousands of small rocks casting shadows cost more than any other
		-- part of the scene; the mountain still takes shadows and shading.
		part.CastShadow = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		self.templates[kind] = part
		self.pool[kind] = {}
	end
end

-- Messages from the server, processed strictly in order.
function MountainView.push(self: View, kind: string, payload: any)
	self.tail += 1
	self.queue[self.tail] = { kind = kind, payload = payload }
end

function MountainView.pending(self: View): number
	return self.tail - self.head + 1
end

-- Yields once this frame's share of work is used up. A backlog earns a
-- slightly larger share so the mountain catches up quickly.
function MountainView._pace(self: View)
	local budget = if self:pending() > 2 or not self.ready then 0.006 else 0.004
	if os.clock() - self.sliceStart >= budget then
		task.wait()
		self.sliceStart = os.clock()
	end
end

function MountainView.start(self: View)
	task.spawn(function()
		while true do
			local message = self.queue[self.head]
			if message == nil then
				self.head, self.tail = 1, 0
				task.wait()
				self.sliceStart = os.clock()
			else
				self.queue[self.head] = nil
				self.head += 1
				local ok, problem = pcall(self._handle, self, message.kind, message.payload)
				if not ok then warn("[DiamondRush] mountain update failed: " .. tostring(problem)) end
			end
		end
	end)
end

function MountainView.keyForPart(self: View, part: Instance): number?
	return if part:IsA("BasePart") then self.keys[part] else nil
end

function MountainView.keyPosition(self: View, key: number): Vector3
	local column = key % LAYER
	local size = self.blockSize
	return Vector3.new((column % SPAN - 128) * size, (key // LAYER) * size + size / 2, (column // SPAN - 128) * size)
end

function MountainView._handle(self: View, kind: string, payload: any)
	if kind == "begin" then
		self:_begin(payload)
	elseif kind == "cells" and self.grid then
		local grid = self.grid :: Grid.Grid
		local count = 0
		Codec.decode(payload, function(key)
			grid.solid[key] = true
			count += 1
			if count % 2048 == 0 then self:_pace() end
		end)
	elseif kind == "tops" then
		Codec.decodePairs(payload, function(column, top) self.tops[column] = top end)
	elseif kind == "end" and self.grid then
		self:_finishSnapshot()
	elseif kind == "diff" and self.grid and self.ready and payload.round == self.round then
		self:_applyDiff(payload)
	elseif kind == "skin" then
		self:_repaint(payload)
	end
end

-- Reskins the mountain (stone or hay, see Skin), in order with the changes
-- from the server.
function MountainView.setSkin(self: View, skin: string)
	if RockStyle.SKINS[skin] == nil then return end
	self:push("skin", skin)
end

-- Every drawn cell keeps its shape and layer and takes the new skin's look.
function MountainView._repaint(self: View, skin: string)
	if skin == self.skin then return end
	self.skin = skin
	local materials = MATERIALS[skin]
	local count = 0
	for key, part in self.parts do
		local layer, r, g, b = RockStyle.look(key, self.tops[key % LAYER], self.height, skin)
		part.Material = materials[layer]
		part.Color = Color3.fromRGB(r, g, b)
		count += 1
		if count % 512 == 0 then self:_pace() end
	end
end

function MountainView._begin(self: View, meta: any)
	-- Drop the previous mountain in one step; it is out of view immediately.
	local old = self.folder
	if old then
		old.Parent = nil
		task.defer(function() old:Destroy() end)
	end
	for _, entry in self.debris do entry.part:Destroy() end
	table.clear(self.debris)
	self.meta = meta
	self.round = meta.round
	self.height = math.max(1, meta.height)
	if meta.blockSize ~= self.blockSize or #self.templates == 0 then
		self.blockSize = meta.blockSize
		self:_makeTemplates()
	end
	self.ready = false
	self.parts, self.codes, self.keys, self.tops = {}, {}, {}, {}
	for kind in self.pool do self.pool[kind] = {} end
	local grid = Grid.blank()
	grid.sealed[meta.diamondKey] = true
	self.grid = grid
	local folder = Instance.new("Folder")
	folder.Name = "Mountain"
	folder.Parent = workspace
	self.folder = folder
end

function MountainView._finishSnapshot(self: View)
	local grid = self.grid :: Grid.Grid
	local exposed: { number } = {}
	local visited = 0
	grid:eachSolid(function(key)
		if grid:isExposed(key) then table.insert(exposed, key) end
		visited += 1
		if visited % 4096 == 0 then self:_pace() end
	end)
	local meta = self.meta
	if meta.animated then
		-- Rise from the base to the summit in waves, with flying stones.
		local layers: { { number } } = {}
		for wave = 1, REBUILD_LAYERS do layers[wave] = {} end
		for _, key in exposed do
			local wave = math.clamp(math.floor((key // LAYER) / self.height * REBUILD_LAYERS) + 1, 1, REBUILD_LAYERS)
			table.insert(layers[wave], key)
		end
		local samples = {}
		for wave, keys in layers do
			for i = 1, math.min(5, #keys) do
				local key = keys[math.max(1, math.floor(i * #keys / 5))]
				local shape = RockStyle.shape(grid, key)
				local _, r, g, b = RockStyle.look(key, self.tops[key % LAYER], self.height, self.skin)
				table.insert(samples, {
					frame = CFrame.new(self:keyPosition(key)) * (self.rotations[shape] or CFrame.identity),
					size = self.templates[1].Size,
					colour = Color3.fromRGB(r, g, b),
					layer = wave,
				})
			end
		end
		if self.onRebuild then self.onRebuild({ stones = samples, start = meta.start }) end
		for wave, keys in layers do
			while workspace:GetServerTimeNow() < meta.start + wave * REBUILD_STEP do task.wait() end
			self.sliceStart = os.clock()
			for index, key in keys do
				self:_refresh(key)
				if index % 64 == 0 then self:_pace() end
			end
		end
	else
		for index, key in exposed do
			self:_refresh(key)
			if index % 64 == 0 then self:_pace() end
		end
	end
	self.ready = true
end

function MountainView._acquire(self: View, kind: number): BasePart
	local pool = self.pool[kind]
	local part = pool[#pool]
	if part then
		pool[#pool] = nil
		return part
	end
	return self.templates[kind]:Clone()
end

function MountainView._release(self: View, part: BasePart, kind: number)
	self.keys[part] = nil
	local pool = self.pool[kind]
	if #pool < POOL_LIMIT then
		part.Parent = nil
		table.insert(pool, part)
	else
		part:Destroy()
	end
end

-- Brings one cell's part in line with the grid: created, reshaped or removed.
function MountainView._refresh(self: View, key: number): BasePart?
	local grid = self.grid :: Grid.Grid
	local old = self.codes[key]
	if not (hasBit(grid.solidPages, key) and grid:isExposed(key)) then
		if old ~= nil then
			self.codes[key] = nil
			local part = self.parts[key]
			if part then
				self.parts[key] = nil
				self:_release(part, RockStyle.kind(old % 16))
			end
		end
		return nil
	end
	local shape = RockStyle.shape(grid, key)
	local layer, r, g, b = RockStyle.look(key, self.tops[key % LAYER], self.height, self.skin)
	local code = shape + layer * 16
	if code == old then return nil end
	local kind = RockStyle.kind(shape)
	local part: BasePart? = self.parts[key]
	if part and (old == nil or RockStyle.kind(old % 16) ~= kind) then
		self:_release(part, RockStyle.kind((old or 0) % 16))
		part = nil
	end
	local fresh = part == nil
	if part == nil then
		local acquired = self:_acquire(kind)
		self.parts[key] = acquired
		self.keys[acquired] = key
		part = acquired
	end
	local stone = part :: BasePart
	stone.CFrame = CFrame.new(self:keyPosition(key)) * self.rotations[shape]
	-- A rock that only changes shape keeps its look: skip the property writes.
	if fresh or old == nil or old // 16 ~= layer then
		stone.Material = MATERIALS[self.skin][layer]
		stone.Color = Color3.fromRGB(r, g, b)
	end
	if fresh then stone.Parent = self.folder end
	self.codes[key] = code
	return if fresh then stone else nil
end

function MountainView._applyDiff(self: View, diff: any)
	local grid = self.grid :: Grid.Grid
	local changed: { number } = {}
	local added: { number } = {}
	local flying: { BasePart } = {}
	local count = 0
	for _, chunk in diff.removed or {} do
		Codec.decode(chunk, function(key)
			if hasBit(grid.solidPages, key) then
				grid.solid[key] = nil
				table.insert(changed, key)
				local part = self.parts[key]
				if part and #flying < DEBRIS_PER_CHANGE and #self.debris + #flying < DEBRIS_LIMIT and diff.effect ~= nil then
					-- This rock flies off as rubble instead of vanishing.
					self.parts[key] = nil
					self.keys[part] = nil
					self.codes[key] = nil
					table.insert(flying, part)
				end
			end
			count += 1
			if count % 1024 == 0 then self:_pace() end
		end)
	end
	for _, chunk in diff.added or {} do
		Codec.decode(chunk, function(key)
			if not hasBit(grid.solidPages, key) then
				grid.solid[key] = true
				table.insert(changed, key)
				table.insert(added, key)
				local column = key % LAYER
				local y = key // LAYER
				if (self.tops[column] or -1) < y then self.tops[column] = y end
			end
			count += 1
			if count % 1024 == 0 then self:_pace() end
		end)
	end
	if #flying > 0 then self:_throwDebris(flying, diff.at) end
	self:_reconcile(changed)
	if diff.effect == "restore" and self.onRestore and #added > 0 then
		local stones = {}
		for _, key in added do
			local part = self.parts[key]
			if part and part.Parent then
				table.insert(stones, { frame = part.CFrame, size = part.Size, colour = part.Color, part = part })
				if #stones >= 24 then break end
			end
		end
		self.onRestore({ stones = stones })
	end
end

-- Re-checks every cell whose shape can depend on the changed cells: the cells
-- themselves, their neighbours (air or exposure changed) and the side
-- neighbours of those (whose shapes test neighbour exposure).
function MountainView._reconcile(self: View, changed: { number })
	local grid = self.grid :: Grid.Grid
	local pages = grid.solidPages
	local marks, markPages = Grid.cellMap()
	local list: { number } = {}
	local function touch(key: number)
		if not hasBit(markPages, key) then
			marks[key] = true
			table.insert(list, key)
		end
	end
	for index, key in changed do
		touch(key)
		for _, step in STEPS do
			local neighbour = key + step
			if neighbour >= 0 and hasBit(pages, neighbour) then
				touch(neighbour)
				for _, side in SIDES do
					local beside = neighbour + side
					if hasBit(pages, beside) then touch(beside) end
				end
			end
		end
		if index % 256 == 0 then self:_pace() end
	end
	for index, key in list do
		self:_refresh(key)
		if index % 64 == 0 then self:_pace() end
	end
end

-- A few removed rocks tumble away from the blast or dig, then return to the pool.
function MountainView._throwDebris(self: View, parts: { BasePart }, at: Vector3?)
	local random = Random.new()
	for _, part in parts do
		part.CanCollide = false
		part.CanQuery = false
		local away = if at then part.Position - at else Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1))
		if away.Magnitude < 0.05 then away = Vector3.new(random:NextNumber(-1, 1), 0.5, random:NextNumber(-1, 1)) end
		table.insert(self.debris, {
			part = part,
			kind = if part:IsA("CornerWedgePart") then 3 elseif part:IsA("WedgePart") then 2 else 1,
			velocity = away.Unit * random:NextNumber(8, 16) + Vector3.new(0, random:NextNumber(9, 16), 0),
			spin = Vector3.new(random:NextNumber(-9, 9), random:NextNumber(-9, 9), random:NextNumber(-9, 9)),
			age = 0,
		})
	end
	if self.debrisConnection then return end
	self.debrisConnection = RunService.RenderStepped:Connect(function(dt)
		for index = #self.debris, 1, -1 do
			local entry = self.debris[index]
			entry.age += dt
			entry.velocity += Vector3.new(0, -50 * dt, 0)
			local part = entry.part
			part.CFrame = (part.CFrame + entry.velocity * dt) * CFrame.Angles(entry.spin.X * dt, entry.spin.Y * dt, entry.spin.Z * dt)
			part.Transparency = math.clamp((entry.age - 0.55) / 0.35, 0, 1)
			if entry.age >= 0.9 then
				table.remove(self.debris, index)
				part.Transparency = 0
				part.CanCollide = true
				part.CanQuery = true
				if part.Parent == self.folder then
					self:_release(part, entry.kind)
				else
					part:Destroy()
				end
			end
		end
		if #self.debris == 0 and self.debrisConnection then
			self.debrisConnection:Disconnect()
			self.debrisConnection = nil
		end
	end)
end

return MountainView
