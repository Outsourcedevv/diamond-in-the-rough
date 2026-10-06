"""Checks the diamond bird: when it comes, how it flies, the model the server
builds and the double-gifts bonus, under the Luau CLI with a Roblox stand-in.

    python3 tests/diamond-bird.py [path/to/luau]
"""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]


def module(path: str) -> str:
    source = (root / path).read_text(encoding="utf-8")
    source = re.sub(r'local Shared = [^\n]*\n', "", source)
    for inlined in ("PartShapes", "DiamondShape", "BirdBonus"):
        source = source.replace(f'require(Shared:WaitForChild("{inlined}"))', inlined)
    source = re.sub(r'require\(Shared:WaitForChild\("(\w+)"\)\)', r'require("../src/shared/\1")', source)
    return "(function()\n" + source + "\nend)()"


# The bird's own clock, timers and click detectors, on top of the shared stand-in.
setup = r'''
local clock = 1000
workspace.GetServerTimeNow = function() return clock end
local delayed: { { at: number, f: () -> () } } = {}
local looped = 0
task = {
	wait = function() end,
	defer = function(f, ...) f(...) end,
	spawn = function() looped += 1 end, -- the endless spawn loop is driven by hand below
	delay = function(seconds: number, f: () -> ()) table.insert(delayed, { at = clock + seconds, f = f }) end,
}
local function advance(seconds: number)
	clock += seconds
	for _, job in table.clone(delayed) do
		if job.at <= clock and table.find(delayed, job) then
			table.remove(delayed, table.find(delayed, job))
			job.f()
		end
	end
end
local baseNew = Instance.new
Instance.new = function(className: string): any
	local object = baseNew(className)
	if className == "Model" then
		object.PivotTo = function(self, frame)
			local pivot = self.PrimaryPart.CFrame
			for _, part in self:GetDescendants() do
				if part.CFrame then
					local p = part.CFrame
					local rel = { p = p.p - pivot.p, r = p.r }
					part.CFrame = CFrame.new(frame.Position.X + rel.p.X, frame.Position.Y + rel.p.Y, frame.Position.Z + rel.p.Z)
				end
			end
		end
	elseif className == "ClickDetector" then
		object.MouseClick = { Connect = function(_, f) object.clicked = f end }
	end
	return object
end
'''

test = r'''
local passed = 0
local function check(condition: boolean, message: string)
	if not condition then error("FAIL " .. message, 2) end
	passed += 1
end

-- Timing: every 5 to 7½ minutes.
check(BirdBonus.nextDelay(0, 300, 450) == 300 and BirdBonus.nextDelay(0.999999, 300, 450) < 450, "a bird every 5 to 7½ minutes")
check(BirdBonus.nextDelay(0.5, 300, 450) == 375, "halfway is 6¼ minutes")
check(BirdBonus.multiplier(10, 20, 2) == 2 and BirdBonus.multiplier(20, 20, 2) == 1 and BirdBonus.multiplier(30, 20, 2) == 1, "the bonus doubles only until it ends")

-- Flight: swoops down from the sky, circles the mountain, climbs away.
local path = { radius = 38, height = 34, angle = math.pi / 2, direction = 1 }
local _, arriveY = BirdBonus.position(path, 0)
local x4, y4, z4 = BirdBonus.position(path, BirdBonus.ARRIVE_SECONDS)
check(arriveY > y4 + 50, "it arrives from high in the sky")
check(z4 > 25, "it arrives on the camp's side of the mountain")
local nearest, farthest = math.huge, 0
for t = BirdBonus.ARRIVE_SECONDS, 200, 0.5 do
	local x, y, z = BirdBonus.position(path, t)
	local reach = math.sqrt(x * x + z * z)
	nearest, farthest = math.min(nearest, reach), math.max(farthest, reach)
	check(y > 30 and y < 38, "it cruises at about the mountain's height")
end
check(nearest > 26 and farthest < 46, string.format("it circles clear of the mountain (%.1f to %.1f studs out)", nearest, farthest))
local lx, ly, lz = BirdBonus.position(path, 60 + BirdBonus.LEAVE_SECONDS, 60)
local ox, oy, oz = BirdBonus.position(path, 60 + BirdBonus.LEAVE_SECONDS)
check(ly > oy + 60 and math.sqrt(lx * lx + lz * lz) > 3 * math.sqrt(ox * ox + oz * oz), "it climbs and flies away when it leaves")
check(math.abs(BirdBonus.flap(0.2, false)) <= 0.7 and BirdBonus.flap(0, false) ~= BirdBonus.flap(0.2, false), "its wings beat")

-- The server's bird.
local State = Instance.new("Configuration")
local feed = {}
local Notify = { FireAllClients = function(_, kind, data) if kind == "feed" then table.insert(feed, data.text) end end }
local bird = DiamondBird.start({ state = State, notify = Notify, radius = 38, height = function() return 34 end, random = Random.new(7) })
check(looped == 1, "the arrival timer starts with the server")
check(bird.multiplier() == 1, "no bonus before a bird is caught")
local function birds()
	local found = {}
	for _, object in instances do
		if object.ClassName == "Model" and object.Name == "DiamondBird" and object.Parent == workspace then table.insert(found, object) end
	end
	return found
end
bird.spawn()
local model = birds()[1]
check(#birds() == 1 and model ~= nil, "a bird appears")
check(string.find(feed[#feed], "diamond bird appeared") ~= nil, "the feed announces it")
check(model:GetAttribute("LeaveAt") == 0 and model:GetAttribute("Start") == clock, "the clients are told when it arrived")
check(model:GetAttribute("Height") == 34 and model:GetAttribute("Radius") == 38, "the clients are told its circuit")

-- Model: a diamond body, a head and beak in front, a tail behind, two wings.
local hitbox = model.PrimaryPart
local centre = hitbox.CFrame.Position
local facets, left, right, heads, tails, beak = 0, 0, 0, 0, 0, nil
local feathers = { [-1] = {}, [1] = {} }
for _, part in model:GetDescendants() do
	if part.CFrame == nil then continue end
	local at = part.CFrame.Position - centre
	if part ~= hitbox then
		check(part.CanQuery == false and part.CanCollide == false and part.Anchored == true, part.Name .. " cannot block rays or players")
		check(math.abs(at.X) <= hitbox.Size.X / 2 + 0.3 and math.abs(at.Y) <= hitbox.Size.Y / 2 + 0.3 and math.abs(at.Z) <= hitbox.Size.Z / 2 + 0.3, part.Name .. " sits inside the click box")
	end
	if part.Name == "Facet" then facets += 1 end
	if part.Name == "Head" then heads += 1; check(at.Z < -1.5, "the head is at the front") end
	if part.Name == "Beak" then beak = at end
	if part.Name == "Tail" then tails += 1; check(at.Z > 2, "the tail is at the back") end
	local wing = part:GetAttribute("Wing")
	if wing == -1 then left += 1; check(at.X < 0, "left wing on the left") end
	if wing == 1 then right += 1; check(at.X > 0, "right wing on the right") end
	if part.Name == "Feather" then table.insert(feathers[wing], at) end
end
check(facets == 128, "a big diamond body and a small diamond crest (" .. facets .. " facets)")
check(heads == 1 and tails == 3 and beak ~= nil and beak.Z < -2.8, "head, beak and three tail feathers")
check(left == 6 and right == 6, "two matching wings")
for _, side in { -1, 1 } do
	table.sort(feathers[side], function(a, b) return math.abs(a.X) < math.abs(b.X) end)
	check(feathers[side][3].Z > feathers[side][1].Z, "wing tips sweep back")
	check(math.abs(feathers[side][3].X) > 5, "a wide wingspan")
end
check(hitbox.CanQuery == true and hitbox.Transparency == 1, "an invisible box takes the clicks")
local click = model:FindFirstChildOfClass("ClickDetector")
check(click ~= nil and click.MaxActivationDistance >= 200, "it can be clicked from the camp")

-- Catching it: 30 seconds of double gifts.
local lobbyPlayer = { DisplayName = "Away", GetAttribute = function() return false end, Character = nil }
click.clicked(lobbyPlayer)
check(bird.multiplier() == 1 and model:GetAttribute("LeaveAt") == 0, "players in the lobby cannot catch it")
local humanoid = Instance.new("Humanoid")
humanoid.Health = 100
local character = Instance.new("Model")
humanoid.Parent = character
local streamer = { DisplayName = "Niamh", GetAttribute = function(_, key) return key == "InGame" end, Character = character }
click.clicked(streamer)
check(bird.multiplier() == 2, "catching it doubles gifts")
check(State:GetAttribute("BirdBoostUntil") == clock + 30 and State:GetAttribute("BirdCatcher") == "Niamh", "the display is told who caught it and for how long")
check(model:GetAttribute("LeaveAt") == clock and click.MaxActivationDistance == 0, "it flies away and cannot be caught twice")
check(string.find(feed[#feed], "Niamh caught the diamond bird") ~= nil, "the feed says who caught it")
advance(BirdBonus.LEAVE_SECONDS + 1)
check(model.destroyed and #birds() == 0, "it is gone once it has flown off")
advance(20)
check(bird.multiplier() == 2, "still doubled after 25 seconds")
advance(6)
check(bird.multiplier() == 1, "back to normal after 30 seconds")
check(feed[#feed] == "Double gifts are over", "the feed says the bonus ended")

-- Uncaught birds fly off when the next one arrives.
bird.spawn()
local first = birds()[1]
advance(300)
bird.spawn()
check(first:GetAttribute("LeaveAt") == clock and first:FindFirstChildOfClass("ClickDetector").MaxActivationDistance == 0, "an uncaught bird flies off when the next arrives")
local second = nil
for _, candidate in birds() do if candidate ~= first then second = candidate end end
check(second ~= nil and second:GetAttribute("LeaveAt") == 0, "the new bird can be caught")
first:FindFirstChildOfClass("ClickDetector").clicked(streamer)
check(bird.multiplier() == 1, "the bird that is leaving cannot be caught")
second:FindFirstChildOfClass("ClickDetector").clicked(streamer)
check(bird.multiplier() == 2, "the new one can")
print(string.format("PASS: %d diamond bird checks", passed))
'''

generated = root / "tests/diamond-bird.generated.luau"
try:
    mock = (root / "tests/roblox-mock.luau").read_text(encoding="utf-8")
    body = (
        mock
        + setup
        + "\nlocal PartShapes = " + module("src/shared/PartShapes.luau")
        + "\nlocal DiamondShape = " + module("src/shared/DiamondShape.luau")
        + "\nlocal BirdBonus = " + module("src/shared/BirdBonus.luau")
        + "\nlocal DiamondBird = " + module("src/server/DiamondBird.luau")
        + "\n" + test
    )
    generated.write_text(body, encoding="utf-8")
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(generated)], check=True)
finally:
    generated.unlink(missing_ok=True)
