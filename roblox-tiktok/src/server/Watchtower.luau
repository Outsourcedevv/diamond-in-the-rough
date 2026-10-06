--!strict
-- A timber fire lookout on a hillside beside the mountain, in the alpine theme
-- only: four tapering log legs braced with crossed timbers, a ladder up to a
-- plank lookout with half walls and open windows, a shingle roof with a flag,
-- and a warm lamp inside. It faces the camp and stands where the spawn can
-- see it, on the other side of the mountain from the sakura shrine. Each leg
-- reaches down to the ground under it, so it stands true on a slope.
local Sakura = require(script.Parent.Sakura)

local Watchtower = {}

type Kit = Sakura.Kit

local LOG = Color3.fromRGB(104, 76, 52)
local BRACE = Color3.fromRGB(92, 68, 48)
local PLANK = Color3.fromRGB(138, 104, 72)
local SHINGLE = Color3.fromRGB(70, 62, 58)

Watchtower.HEIGHT = 15 -- studs from the highest leg's ground to the lookout floor

-- Where it goes: open ground ahead of the camp and to the left of the
-- mountain, preferring higher ground for the view. `gap` keeps it that far
-- from the valley's trees and rocks. Returns its frame (on the highest
-- ground under its legs, its front facing the camp), or nil.
local function site(kit: Kit, random: Random, gap: number): CFrame?
	local best: CFrame? = nil
	local bestScore = math.huge
	for attempt = 1, 400 do
		local angle = -random:NextNumber(math.rad(25), math.rad(70))
		local distance = random:NextNumber(65, 130)
		local spot = kit.camp + Vector3.new(math.sin(angle), 0, -math.cos(angle)) * distance
		local centre = kit.ground(spot.X, spot.Z)
		if not kit.clear(centre, 7) and centre.Y < 40 and kit.steepness(centre.X, centre.Z) < 0.8 and kit.spaced(centre, gap) then
			local flat = Vector3.new(centre.X, 0, centre.Z)
			local facing = Vector3.new(kit.camp.X - centre.X, 0, kit.camp.Z - centre.Z).Unit
			local turn = CFrame.lookAt(flat, flat + facing)
			local high, low = -math.huge, math.huge
			for _, x in { -2.8, 2.8 } do
				for _, z in { -3.2, 2.8 } do
					local foot = turn * Vector3.new(x, 0, z)
					local y = kit.ground(foot.X, foot.Z).Y
					high, low = math.max(high, y), math.min(low, y)
				end
			end
			-- Higher ground gives the lookout its view; a gentle slope is fine.
			local score = math.abs(angle + math.rad(45)) + distance / 200 - centre.Y / 50
			if high - low < 4 and score < bestScore then
				bestScore = score
				best = turn + Vector3.new(0, high, 0)
			end
		end
		if attempt % 64 == 0 then task.wait() end
	end
	return best
end

-- Builds the tower into `parent`. Returns the model, or nil when there is
-- nowhere open enough for it.
function Watchtower.build(kit: Kit, parent: Instance): Model?
	local random = Random.new(5527)
	local frame: CFrame? = nil
	for _, gap in { 8, 5, 3 } do
		frame = site(kit, random, gap)
		if frame then break end
	end
	if frame == nil then
		warn("[DiamondRush] Scenery: no open ground for the watchtower, so it is left out.")
		return nil
	end
	local base = frame :: CFrame
	local model = Instance.new("Model")
	model.Name = "Watchtower"
	model.Parent = parent
	local h = Watchtower.HEIGHT
	local function at(x: number, y: number, z: number): Vector3
		return base * Vector3.new(x, y, z)
	end
	local function put(name: string, size: Vector3, offset: CFrame, colour: Color3, material: Enum.Material, kind: string?): BasePart
		return kit.piece(model, name, size, base * offset, colour, material, kind)
	end
	local function log(name: string, a: Vector3, b: Vector3, width: number, colour: Color3): BasePart
		return kit.beam(model, name, a, b, width, colour, Enum.Material.Wood)
	end
	-- Where a point of a leg is: the legs taper from 2.8 studs out at the
	-- ground to 2.2 under the floor. `y` is the height above the frame.
	local function leg(sx: number, sz: number, y: number): Vector3
		local spread = 2.8 - 0.6 * math.clamp(y / h, 0, 1)
		return at(sx * spread, y, sz * spread)
	end
	-- The legs, each reaching down into the ground under it.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local foot = leg(sx, sz, 0)
			local ground = kit.ground(foot.X, foot.Z).Y - base.Position.Y
			kit.solid(log("TowerLeg", leg(sx, sz, ground - 0.6), leg(sx, sz, h + 0.2), 0.62, LOG))
			kit.solid(put("TowerFooting", Vector3.new(1.3, 0.8, 1.3), CFrame.new(sx * 2.8, ground + 0.2, sz * 2.8), Color3.fromRGB(128, 124, 116), Enum.Material.Cobblestone))
		end
	end
	-- Horizontal girts and crossed braces on every side, in three bays.
	local levels = { 1.2, 5.8, 10.4, h - 0.2 }
	local sides = { { { -1, -1 }, { 1, -1 } }, { { 1, -1 }, { 1, 1 } }, { { 1, 1 }, { -1, 1 } }, { { -1, 1 }, { -1, -1 } } }
	for _, pair in sides do
		local a, b = pair[1], pair[2]
		for i, y in levels do
			if i > 1 then
				log("TowerGirt", leg(a[1], a[2], y), leg(b[1], b[2], y), 0.34, BRACE)
			end
			local up = levels[i + 1]
			if up then
				log("TowerBrace", leg(a[1], a[2], y), leg(b[1], b[2], up), 0.26, BRACE)
				log("TowerBrace", leg(b[1], b[2], y), leg(a[1], a[2], up), 0.26, BRACE)
			end
		end
	end
	-- The lookout: a plank floor, half walls with a gap for the ladder, corner
	-- posts up to the roof, and a warm lamp.
	local half = 2.9
	kit.solid(put("TowerFloor", Vector3.new(2 * half + 0.4, 0.4, 2 * half + 0.4), CFrame.new(0, h + 0.4, 0), PLANK, Enum.Material.WoodPlanks))
	local wall = 1.25
	local wallY = h + 0.6 + wall / 2
	local gap = 1.4
	-- Back and sides are whole; the front leaves a gap where the ladder arrives.
	kit.solid(put("TowerWall", Vector3.new(2 * half, wall, 0.22), CFrame.new(0, wallY, half), PLANK, Enum.Material.WoodPlanks))
	for _, side in { -1, 1 } do
		kit.solid(put("TowerWall", Vector3.new(0.22, wall, 2 * half), CFrame.new(side * half, wallY, 0), PLANK, Enum.Material.WoodPlanks))
		local width = half - gap / 2
		kit.solid(put("TowerWall", Vector3.new(width, wall, 0.22), CFrame.new(side * (gap / 2 + width / 2), wallY, -half), PLANK, Enum.Material.WoodPlanks))
	end
	local roofBase = h + 3.9
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			kit.solid(log("TowerPost", at(sx * half, h + 0.6, sz * half), at(sx * half, roofBase, sz * half), 0.32, LOG))
		end
	end
	for _, side in { -1, 1 } do
		log("TowerRail", at(-half, roofBase - 0.1, side * half), at(half, roofBase - 0.1, side * half), 0.28, BRACE)
		log("TowerRail", at(side * half, roofBase - 0.1, -half), at(side * half, roofBase - 0.1, half), 0.28, BRACE)
	end
	local lamp = put("TowerLamp", Vector3.new(0.45, 0.6, 0.45), CFrame.new(0, roofBase - 0.6, 0), Color3.fromRGB(255, 196, 118), Enum.Material.Neon)
	lamp.CastShadow = false
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 120)
	light.Range = 12
	light.Brightness = 0.8
	light.Shadows = false
	light.Parent = lamp
	-- A gabled shingle roof, its ridge running front to back over the ladder.
	local rise = 2.2
	local span = half + 0.9
	local pitch = math.atan2(rise, span)
	for _, side in { -1, 1 } do
		local length = math.sqrt(rise * rise + span * span) + 0.2
		put("TowerRoof", Vector3.new(length, 0.3, 2 * half + 1.6), CFrame.new(side * span / 2, roofBase + rise / 2 + 0.15, 0) * CFrame.Angles(0, 0, -side * pitch), SHINGLE, Enum.Material.RoofShingles)
	end
	for _, z in { -half, half } do
		for _, side in { -1, 1 } do
			-- Each gable is two wedges, rising to the ridge from either side.
			local turn = if side > 0 then CFrame.Angles(0, -math.pi / 2, 0) else CFrame.Angles(0, math.pi / 2, 0)
			put("TowerGable", Vector3.new(0.25, rise, half), CFrame.new(side * half / 2, roofBase + rise / 2, z) * turn, PLANK, Enum.Material.WoodPlanks, "WedgePart")
		end
	end
	put("TowerRidge", Vector3.new(0.4, 0.4, 2 * half + 1.8), CFrame.new(0, roofBase + rise + 0.2, 0), BRACE, Enum.Material.Wood)
	-- A flag flies from the back of the ridge.
	log("TowerFlagpole", at(0, roofBase + rise, half + 0.5), at(0, roofBase + rise + 4, half + 0.5), 0.14, Color3.fromRGB(210, 206, 196))
	put("TowerFlag", Vector3.new(0.05, 1.1, 1.7), CFrame.new(0, roofBase + rise + 3.35, half + 1.38), Color3.fromRGB(200, 48, 52), Enum.Material.Fabric)
	-- The ladder runs up the front, from the ground to the gap in the wall.
	local front = -3.3
	local foot = at(0, 0, front)
	local bottom = kit.ground(foot.X, foot.Z).Y - base.Position.Y - 0.3
	for _, x in { -0.55, 0.55 } do
		kit.solid(log("TowerLadderRail", at(x, bottom, front), at(x, h + 1.7, front), 0.18, LOG))
	end
	local y = bottom + 0.6
	while y < h + 1.4 do
		log("TowerRung", at(-0.55, y, front), at(0.55, y, front), 0.12, BRACE)
		y += 0.8
	end
	-- A short landing joins the ladder to the floor.
	kit.solid(put("TowerLanding", Vector3.new(1.4, 0.3, 0.8), CFrame.new(0, h + 0.45, -half - 0.35), PLANK, Enum.Material.WoodPlanks))
	return model
end

return Watchtower
