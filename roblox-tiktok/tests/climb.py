"""Checks Diamond Climb under the Luau CLI with a Roblox stand-in: the path of
1000 platforms (every jump a short, easy hop, each a little higher, with head
room under the turn above and clear of the pillar), how far gifts move the
climber, the saved climb's clean-up, the tower the server builds (solid,
numbered platforms, no lettered signs), the climb's display helpers, and
every send-up and send-down gift ride on a simulated clock: each carries the
climber to their new platform, lets go of them and the camera, keeps its
part, light and particle budgets and leaves nothing behind.

    python3 tests/climb.py [path/to/luau]
"""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
luau = sys.argv[1] if len(sys.argv) > 1 else "luau"


def module(path: str) -> str:
    """A module as an expression, with its game modules passed in as locals."""
    source = (root / path).read_text(encoding="utf-8")
    source = re.sub(r'local Shared = [^\n]*\n', "", source)
    source = re.sub(r'require\((?:Shared|script\.Parent|script):WaitForChild\("(\w+)"\)\)', r'\1', source)
    return "(function()\n" + source + "\nend)()"


def modules(*paths: str) -> str:
    return "".join(f"\nlocal {Path(p).stem} = {module(p)}" for p in paths)


def run(name: str, body: str):
    generated = root / f"tests/{name}.generated.luau"
    try:
        generated.write_text(body, encoding="utf-8")
        subprocess.run([luau, str(generated)], check=True)
    finally:
        generated.unlink(missing_ok=True)


mock = (root / "tests/roblox-mock.luau").read_text(encoding="utf-8")

path_test = r'''
local passed = 0
local function check(condition: boolean, message: string)
	if not condition then error("FAIL " .. message, 2) end
	passed += 1
end
local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- The path: 1000 platforms, each an easy hop from the one before.
check(ClimbPath.TOP == 1000, "1000 platforms to the top")
local widestGap, steepest, lowestHead = 0, 0, math.huge
local lastRise = 0
for n = 1, ClimbPath.TOP do
	local a, b = ClimbPath.top(n - 1), ClimbPath.top(n)
	local rise = b.Y - a.Y
	check(rise > 0 and rise >= lastRise - 1e-9, "platform " .. n .. " is a little higher than the last")
	lastRise = rise
	local gap = flat(a, b) - ClimbPath.size(n - 1) / 2 - ClimbPath.size(n) / 2
	widestGap = math.max(widestGap, gap)
	steepest = math.max(steepest, rise)
	-- Clear of the crystal pillar (10 wide) in the middle.
	check(flat(b, ClimbPath.ORIGIN) - ClimbPath.size(n) / 2 > 6, "platform " .. n .. " clears the pillar")
	-- Head room: nothing in the turns above hangs low over this platform.
	for m = n + 1, math.min(ClimbPath.TOP, n + 60) do
		local c = ClimbPath.top(m)
		if flat(b, c) < ClimbPath.size(n) / 2 + ClimbPath.size(m) / 2 + 2 and m > n + 2 then
			lowestHead = math.min(lowestHead, c.Y - ClimbPath.THICKNESS - b.Y)
		end
	end
end
check(widestGap <= 3.5, string.format("every gap is a short hop (widest %.2f studs)", widestGap))
check(steepest <= ClimbPath.RISE_HIGH + 1e-6 and steepest <= ClimbPath.JUMP.default - 3, string.format("every step is easy with the default jump (highest %.2f)", steepest))
check(ClimbPath.rise(1) < 2.1 and math.abs(ClimbPath.rise(ClimbPath.TOP) - ClimbPath.RISE_HIGH) < 1e-6, "the steps grow from about 2 to 3.5 studs")
-- Clear of a climber at the highest jump (15 studs plus a 5-stud body) and of the camera.
check(lowestHead >= 30, string.format("head room under the turn above (%.1f studs)", lowestHead))
check(math.abs(ClimbPath.height(ClimbPath.TOP) - (ClimbPath.top(ClimbPath.TOP).Y - ClimbPath.ORIGIN.Y)) < 1e-6, "height matches the top")
check(ClimbPath.height(ClimbPath.TOP) > 2500 and ClimbPath.height(ClimbPath.TOP) < 3000, string.format("the tower is about %.0f studs tall", ClimbPath.height(ClimbPath.TOP)))
check(ClimbPath.size(100) > ClimbPath.size(99) and ClimbPath.size(ClimbPath.TOP) > ClimbPath.size(100), "milestones and the top are bigger")
check(ClimbPath.colour(1) == ClimbPath.GEMS[1] and ClimbPath.colour(100) == ClimbPath.GEMS[1] and ClimbPath.colour(101) == ClimbPath.GEMS[2] and ClimbPath.colour(1000) == ClimbPath.GEMS[10], "a new gem colour every hundred")
-- The start island sits clear of the platforms.
check(flat(ClimbPath.top(0), ClimbPath.top(1)) - ClimbPath.START_SIZE / 2 - ClimbPath.size(1) / 2 < 1, "the first platform is a step from the start island")

-- Standing and landing.
for _, n in { 0, 1, 57, 100, 999, 1000 } do
	local stand = ClimbPath.standFrame(n)
	check(math.abs(stand.Position.Y - ClimbPath.top(n).Y - 3) < 1e-6 and flat(stand.Position, ClimbPath.top(n)) < 1e-6, "stand on platform " .. n)
	check(ClimbPath.isOn(n, ClimbPath.top(n) + Vector3.new(1, 0, 0)), "standing on platform " .. n)
	check(not ClimbPath.isOn(n, ClimbPath.top(n) + Vector3.new(0, 9, 0)), "high above platform " .. n .. " is not on it")
	check(not ClimbPath.isOn(n, ClimbPath.top(n) + Vector3.new(ClimbPath.size(n), 0, 0)), "beside platform " .. n .. " is not on it")
end
check(ClimbPath.isOn(50, ClimbPath.top(50) + Vector3.new(0, 7, 0), 4) and not ClimbPath.isOn(50, ClimbPath.top(50) + Vector3.new(0, 7, 0)), "slack for the server")
local ahead = ClimbPath.standFrame(10)
check((ahead.Position + ahead.LookVector * 10 - ClimbPath.top(11)).Magnitude < (ahead.Position - ClimbPath.top(11)).Magnitude, "standing facing the next platform")

-- The wall behind the start: pushes past platform 0 hit it.
check(ClimbPath.WALL.default == 5000, "the wall starts with 5,000 health")
check(ClimbPath.wallDamage(0, -20) == 20 and ClimbPath.wallDamage(5, -20) == 15 and ClimbPath.wallDamage(30, -20) == 0 and ClimbPath.wallDamage(0, 20) == 0, "only the push past platform 0 hits the wall")
local wallAt = ClimbPath.wallFrame().Position
check((wallAt - ClimbPath.top(1)).Magnitude > (ClimbPath.top(0) - ClimbPath.top(1)).Magnitude, "the wall is behind the start, away from platform 1")
check(math.abs(wallAt.Y - ClimbPath.WALL_SIZE.Y / 2 - ClimbPath.top(0).Y) < 1e-6, "the wall stands on the start island's level")
local flatToWall = Vector3.new(wallAt.X - ClimbPath.top(0).X, 0, wallAt.Z - ClimbPath.top(0).Z).Magnitude
check(flatToWall > ClimbPath.START_SIZE / 2, "the wall is at the island's edge, not on it")
local walled = ClimbGame.clean({ wall = 99999, wallMax = 2000 })
check(walled.wallMax == 2000 and walled.wall == 2000, "a saved wall is kept within its health")
check(ClimbGame.clean(nil).wall == 5000 and ClimbGame.clean({ wallMax = 1 }).wallMax == ClimbPath.WALL.min, "a new climb has a whole wall")

-- Gifts: more platforms for bigger gifts.
check(ClimbPath.giftPlatforms(1) == 2 and ClimbPath.giftPlatforms(10) == 6 and ClimbPath.giftPlatforms(100) == 20
	and ClimbPath.giftPlatforms(500) == 45 and ClimbPath.giftPlatforms(1000) == 63 and ClimbPath.giftPlatforms(10000) == 200, "platforms per gift")
check(ClimbPath.giftPlatforms(100, 2) == 40 and ClimbPath.giftPlatforms(100, 0.5) == 10 and ClimbPath.giftPlatforms(1, 0.5) == 1, "gift strength")
for tier = 2, 6 do
	check(ClimbPath.GIFT_SECONDS[tier] > ClimbPath.GIFT_SECONDS[tier - 1], "bigger gifts ride longer")
end
check(ClimbPath.giftSeconds(1000) == ClimbPath.GIFT_SECONDS[5], "a galaxy's ride")
check(ClimbGame.giftMove(100, 100, 1, 1) == 20 and ClimbGame.giftMove(-5000, 100, 1, 1) == -20 and ClimbGame.giftMove(0, 100, 1, 1) == 0, "breaking gifts go up, adding gifts down")
check(ClimbGame.giftMove(1, 1, 3, 1) == 6, "a combo counts each gift")

-- A saved climb is cleaned up.
local clean = ClimbGame.clean({ checkpoint = 2000, best = 5, wins = -3, speed = 99, jump = 1, strength = 7 })
check(clean.checkpoint == 0 and clean.best == 1000 and clean.wins == -3 and clean.speed == ClimbPath.SPEED.max and clean.jump == ClimbPath.JUMP.min and clean.strength == 1,
	"out of range saves are put right (a climb saved at the top starts again)")
local kept = ClimbGame.clean({ checkpoint = 321.7, best = 400, wins = 2, speed = 24, jump = 9.5, strength = 2 })
check(kept.checkpoint == 321 and kept.best == 400 and kept.wins == 2 and kept.speed == 24 and kept.jump == 9.5 and kept.strength == 2, "a good save is kept")
check(ClimbGame.clean(nil).checkpoint == 0 and ClimbGame.clean("x").speed == ClimbPath.SPEED.default, "no save starts fresh")

-- The display.
check(ClimbView.platformText(0) == "PLATFORM 0 / 1,000" and ClimbView.platformText(1000) == "PLATFORM 1,000 / 1,000", "platform text")
check(ClimbView.pitch(10) < ClimbView.pitch(19) and ClimbView.pitch(20) == ClimbView.pitch(10), "the chime climbs through each ten")
local first, last = ClimbView.numberRange(0)
check(first == 1 and last == ClimbView.NUMBERS_ABOVE, "numbers over the first platforms from the start island")
first, last = ClimbView.numberRange(500)
check(first == 500 - ClimbView.NUMBERS_BELOW and last == 500 + ClimbView.NUMBERS_ABOVE, "numbers round the climber")
first, last = ClimbView.numberRange(ClimbPath.TOP)
check(last == ClimbPath.TOP and last - first == ClimbView.NUMBERS_BELOW, "numbers stop at the top")
for _, n in { 1, 57, 100, 1000 } do
	local point = ClimbView.numberPoint(n)
	local top = ClimbPath.top(n)
	local flatOut = Vector3.new(point.X - top.X, 0, point.Z - top.Z).Magnitude
	check(point.Y > top.Y + 1 and point.Y < top.Y + 3, "platform " .. n .. "'s number hangs just above it")
	check(flatOut > ClimbPath.size(n) / 2 - 2 and flatOut <= ClimbPath.size(n) / 2, "at its outer edge, clear of the climber")
	local fromPillar = Vector3.new(point.X - ClimbPath.ORIGIN.X, 0, point.Z - ClimbPath.ORIGIN.Z).Magnitude
	check(fromPillar > Vector3.new(top.X - ClimbPath.ORIGIN.X, 0, top.Z - ClimbPath.ORIGIN.Z).Magnitude, "on the outside of the spiral")
	-- Never inside another platform.
	for m = math.max(1, n - 40), math.min(ClimbPath.TOP, n + 40) do
		if m ~= n then
			local other = ClimbPath.top(m)
			local inside = Vector3.new(point.X - other.X, 0, point.Z - other.Z).Magnitude < ClimbPath.size(m) / 2
				and point.Y > other.Y - ClimbPath.THICKNESS - 1 and point.Y < other.Y + 1
			check(not inside, "platform " .. n .. "'s number is not inside platform " .. m)
		end
	end
end
check(ClimbView.pace(0) == 1 and ClimbView.pace(2) > 1 and ClimbView.pace(50) == 3, "queued rides play faster")

-- The tower.
local parent = newInstance("Workspace")
local built = Climb.build(parent)
local platforms, solid, lettered, lights = 0, 0, 0, 0
local seen = {}
for _, object in instances do
	if object:IsDescendantOf(built.model) then
		if object.ClassName == "Part" and object.Name == "Platform" then
			platforms += 1
			local index = object:GetAttribute("ClimbIndex")
			check(type(index) == "number" and not seen[index], "each platform is numbered once")
			seen[index] = true
			check(object.CanCollide and object.CanQuery and object.Anchored, "platforms are solid and found by raycasts")
			check((object.CFrame.Position + Vector3.new(0, ClimbPath.THICKNESS / 2, 0) - ClimbPath.top(index)).Magnitude < 1e-6, "platform " .. index .. " is where the path says")
		end
		if object:IsA("BasePart") and object.CanCollide then
			solid += 1
			check(object.Name == "Platform" or object.Name == "StartIsland" or object.Name == "ClimbWall", "only platforms (and the wall) are solid: " .. tostring(object.Name))
		end
		if object.ClassName == "TextLabel" or object.ClassName == "SurfaceGui" or object.ClassName == "BillboardGui" then lettered += 1 end
		if object.ClassName == "PointLight" then lights += 1 end
	end
end
check(platforms == ClimbPath.TOP, "1000 platforms built: " .. platforms)
check(solid == ClimbPath.TOP + 2, "1000 platforms, the start island and the wall are solid")
check(lettered == 0, "no lettered signs on the tower")
check(lights <= 2, "the tower adds at most a light or two")
check(built.diamond.Name == "ClimbDiamond" and typeof(built.diamond:GetAttribute("Centre")) == "Vector3", "the diamond waits at the top")
check(built.spawn.Name == "ClimbStart" and built.spawn.Enabled == false, "the climb's respawn point is never a random spawn")
-- The wall in a running climb: pushes past platform 0 wear it down, and a
-- broken wall takes a win and is built again.
local fired = {}
local realGetService = game.GetService
game.GetService = function(self, name)
	if name == "Players" then return { GetPlayers = function() return {} end } end
	return realGetService(self, name)
end
task.delay = function() end
local climbState = newInstance("Folder")
local settings = { climb = { wins = 3, wallMax = 100 } }
local climbGame = ClimbGame.start({
	settings = settings, save = function() end, state = climbState, parent = newInstance("Workspace"),
	notify = { FireAllClients = function(_, kind, data) table.insert(fired, { kind = kind, data = data }) end },
} :: any)
check(climbState:GetAttribute("ClimbWall") == 100 and climbState:GetAttribute("ClimbWallMax") == 100, "the wall's health is shown")
local from, to, damage, broke = climbGame.gift("Ann", 10, { coins = 1 })
check(to == 10 and damage == 0 and not broke, "going up never hits the wall")
from, to, damage, broke = climbGame.gift("Ben", -30, { coins = 1 })
check(to == 0 and damage == 20 and not broke and climbGame.progress.wall == 80, "the push past platform 0 hits the wall")
from, to, damage, broke = climbGame.gift("Cat", -50, { coins = 1 })
check(to == 0 and damage == 50 and climbGame.progress.wall == 30, "gifts keep pushing at platform 0, into the wall")
check(fired[#fired].kind == "climbWall" and fired[#fired].data.damage == 50 and fired[#fired].data.health == 30, "everyone sees the hit")
from, to, damage, broke = climbGame.gift("Dee", -40, { coins = 1 })
check(broke and climbGame.progress.wins == 2 and climbGame.progress.wall == 100, "a broken wall takes a win and is built again")
check(fired[#fired].data.broke == true and climbState:GetAttribute("ClimbWins") == 2, "the break is shown")
climbGame.progress.wins = 0
climbGame.progress.wall = 1
climbGame.gift("Eve", -5, { coins = 1 })
check(climbGame.progress.wins == -1, "a broken wall can take wins below 0")
check(climbGame.setWallMax(2500) and climbGame.progress.wall == 2500 and climbState:GetAttribute("ClimbWallMax") == 2500, "the streamer sets the wall's health")
check(not climbGame.setWallMax("x") and climbGame.setWallMax(1) and climbGame.progress.wallMax == ClimbPath.WALL.min, "the wall's health stays in range")
game.GetService = realGetService

print(string.format("PASS: %d climb checks (gap %.2f, step %.2f, head room %.1f, tower %.0f studs)", passed, widestGap, steepest, lowestHead, ClimbPath.height(ClimbPath.TOP)))
'''

mock_extras = r'''
typeof = function(value)
	if type(value) == "table" and getmetatable(value) == vector then return "Vector3" end
	return type(value)
end
'''

run("climb", mock + mock_extras + modules(
    "src/shared/GiftTier.luau", "src/shared/Format.luau", "src/shared/DiamondShape.luau",
    "src/shared/ClimbPath.luau", "src/shared/Config.luau", "src/shared/HoldTimer.luau", "src/server/Climb.luau", "src/server/ClimbGame.luau",
    "src/client/CameraShake.luau", "src/client/Sounds.luau", "src/client/HoldCountdown.luau", "src/client/ClimbEffects.luau",
    "src/client/ClimbView.luau") + "\n" + path_test)

# The gift rides, on the gift effects test's simulated clock.
effects_source = (root / "tests/gift-effects.py").read_text(encoding="utf-8")
harness = re.search(r"harness = r'''(.*?)'''", effects_source, re.S).group(1)

rides_test = r'''
local passed = 0
local function check(condition: boolean, message: string)
	if not condition then error("FAIL " .. message, 2) end
	passed += 1
end
local function inWorld(object: any): boolean
	local parent = object.Parent
	while parent ~= nil do
		if parent == workspace or parent == Lighting then return true end
		if type(parent) ~= "table" or parent.destroyed then return false end
		parent = rawget(parent, "Parent")
	end
	return false
end
local rider = newInstance("Part")
rider.Name = "HumanoidRootPart"
rider.Parent = workspace
local function live(className: string): number
	local count = 0
	for _, object in instances do
		if object.ClassName == className and object ~= rider and not object.destroyed and inWorld(object) then count += 1 end
	end
	return count
end
camera.CameraType = Enum.CameraType.Custom
camera.FieldOfView = 70
local gui = newInstance("PlayerGui")
ClimbEffects.start(gui)
local function run(seconds: number)
	local finish = clock + seconds
	while clock < finish do
		clock += 1 / 60
		table.sort(scheduled, function(a, b) return a.at < b.at end)
		while scheduled[1] and scheduled[1].at <= clock do
			table.remove(scheduled, 1).run()
		end
		runBound(1 / 60)
		local callbacks = {}
		for _, callback in renderConnections do table.insert(callbacks, callback) end
		for _, callback in callbacks do callback(1 / 60) end
	end
end

local TIERS = { 1, 10, 100, 500, 1000, 10000 }
for round = 1, 2 do
	local up = round == 1
	for tier, coins in TIERS do
		local from = if up then 100 else 600
		local moved = ClimbPath.giftPlatforms(coins)
		local to = if up then from + moved else from - moved
		rider.CFrame = ClimbPath.standFrame(from)
		rider.Anchored = false
		local before = #instances
		emitted = 0
		local done = 0
		local seconds = ClimbEffects.play({ up = up, from = from, to = to, coins = coins, name = "Tester", gift = "Gift" }, rider, 1, function() done += 1 end)
		local name = (if up then ClimbPath.UP_TITLES else ClimbPath.DOWN_TITLES)[tier]
		check(math.abs(seconds - ClimbPath.GIFT_SECONDS[tier]) < 1e-9, name .. ": its length")
		check(rider.Anchored == true, name .. ": the climber is held")
		local farthest, highest, lowest = 0, -math.huge, math.huge
		local filmed = false
		local midIndex = nil
		local start = clock
		while clock - start < seconds - 0.05 do
			run(1 / 30)
			local p = rider.CFrame.Position
			farthest = math.max(farthest, (p - ClimbPath.standFrame(from).Position).Magnitude)
			highest = math.max(highest, p.Y)
			lowest = math.min(lowest, p.Y)
			filmed = filmed or camera.CameraType == Enum.CameraType.Scriptable
			if clock - start > seconds * 0.6 and midIndex == nil then midIndex = ClimbEffects.shownIndex() end
		end
		check(done == 0 and ClimbEffects.playing(), name .. ": still riding just before the end")
		run(0.1)
		check(done == 1 and not ClimbEffects.playing(), name .. ": the ride ends on time")
		check(rider.Anchored == false and (rider.CFrame.Position - ClimbPath.standFrame(to).Position).Magnitude < 1e-6, name .. ": let go on platform " .. to)
		check(farthest > 1, name .. ": the climber really moves")
		check(midIndex ~= nil and (if up then midIndex > from else midIndex < from), name .. ": the display counts the platforms going by")
		check(ClimbEffects.shownIndex() == nil, name .. ": the display goes back to the checkpoint")
		check(filmed == (tier >= ClimbEffects.CINEMATIC_TIER), name .. ": the camera is filmed from 100 coins")
		check(camera.CameraType == Enum.CameraType.Custom and camera.FieldOfView == 70, name .. ": the camera is given back")
		local parts, lights = 0, 0
		for i = before + 1, #instances do
			local object = instances[i]
			if object.ClassName == "Part" then
				parts += 1
				check(object.Anchored and object.CanCollide == false and object.CanTouch == false and object.CanQuery == false and object.CastShadow == false,
					name .. ": effect parts are never physical")
			end
			if object.ClassName == "PointLight" then
				lights += 1
				check(object.Shadows == false, name .. ": lights cast no shadows")
			end
			if object.ClassName == "ParticleEmitter" then
				local known = false
				for _, texture in ClimbEffects.TEXTURES do known = known or object.Texture == texture end
				check(known, name .. ": only built-in particle textures")
			end
		end
		run(4)
		check(parts >= 2 and parts <= ClimbEffects.PART_LIMITS[tier], name .. ": part budget kept (" .. parts .. ")")
		check(lights >= 1 and lights <= ClimbEffects.LIGHT_LIMITS[tier], name .. ": light budget kept (" .. lights .. ")")
		check(emitted >= 10 and emitted <= ClimbEffects.PARTICLE_BUDGETS[tier], name .. ": particle budget kept (" .. emitted .. ")")
		check(live("Part") == 0 and live("ParticleEmitter") == 0 and live("Trail") == 0 and live("PointLight") == 0, name .. ": nothing is left behind")
		check(live("ColorCorrectionEffect") == 0, name .. ": the sky comes back")
		check(next(renderConnections) == nil and next(bound) == nil and not ClimbEffects.shaking(), name .. ": every motion and shake stops")
		check(rider.CFrame.Position == ClimbPath.standFrame(to).Position, name .. ": nothing moves the climber afterwards")
		print(string.format("%-4s %-19s %3d parts, %d lights, %4d particles, %.1f s, %d platforms", if up then "up" else "down", name, parts, lights, emitted, seconds, moved))
	end
end

-- Queued rides play faster; a new ride cuts the last one short cleanly.
rider.CFrame = ClimbPath.standFrame(10)
local quick = ClimbEffects.play({ up = true, from = 10, to = 73, coins = 1000, name = "A", gift = "Galaxy" }, rider, 3)
check(math.abs(quick - ClimbPath.GIFT_SECONDS[5] / 3) < 1e-9, "a ride at three times the pace")
run(0.5)
local firstDone = false
ClimbEffects.stop()
check(not ClimbEffects.playing() and rider.Anchored == false and camera.CameraType == Enum.CameraType.Custom, "stopping lets go at once")
local done = 0
ClimbEffects.play({ up = false, from = 73, to = 53, coins = 100, name = "B", gift = "Anvil" }, rider, 1, function() done += 1 end)
run(0.5)
ClimbEffects.play({ up = true, from = 53, to = 55, coins = 1, name = "C", gift = "Rose" }, rider, 1, function() firstDone = true end)
check(done == 1, "a new ride ends the one before")
run(5)
check(firstDone and rider.CFrame.Position == ClimbPath.standFrame(55).Position, "and plays its own")
check(live("Part") == 0 and next(renderConnections) == nil and next(bound) == nil, "cut-short rides clean up")
-- Someone else's ride (no climber to carry) still plays.
ClimbEffects.play({ up = true, from = 0, to = 20, coins = 100, name = "D", gift = "Gift" }, nil, 1)
run(1)
check(camera.CameraType == Enum.CameraType.Custom, "a ride without a climber leaves the camera alone")
run(7)
check(live("Part") == 0, "and cleans up")
print(string.format("PASS: %d climb ride checks", passed))
'''

run("climb-rides", mock + "\n" + harness + modules(
    "src/shared/GiftTier.luau", "src/shared/Format.luau", "src/shared/ClimbPath.luau",
    "src/client/CameraShake.luau", "src/client/Sounds.luau", "src/client/ClimbEffects.luau") + "\n" + rides_test)
