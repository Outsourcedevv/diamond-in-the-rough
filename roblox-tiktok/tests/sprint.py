"""Checks sprinting (src/client/Sprint.luau) under the Luau CLI: holding the
sprint key multiplies the walking speed, letting go puts it back, and a speed
the server sets meanwhile (the diamond holder's freeze, Diamond Climb's
slider) becomes the new walking speed, with change signals delivered at once
or late (Roblox's deferred signals) and never stacking.

    python3 tests/sprint.py [path/to/luau]
"""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
luau = sys.argv[1] if len(sys.argv) > 1 else "luau"

config = (root / "src/shared/Config.luau").read_text(encoding="utf-8")
multiplier = re.search(r"SprintMultiplier = ([\d.]+)", config).group(1)
source = (root / "src/client/Sprint.luau").read_text(encoding="utf-8")
source = re.sub(r"local (Players|ReplicatedStorage|ContextActionService|UserInputService) = [^\n]*\n", "", source)
source = re.sub(r"local Shared = [^\n]*\n", "", source)
source = re.sub(r"local Config = [^\n]*\n", "local Config = { SprintMultiplier = " + multiplier + " }\n", source)
source = source.replace("return Sprint", "")

test = r'''
local passed = 0
local function check(condition, message)
	if not condition then error("FAIL " .. message, 2) end
	passed += 1
end
local function near(a, b) return math.abs(a - b) < 1e-6 end

-- A humanoid stand-in whose WalkSpeed change signal fires at once, or later
-- (`deferred`) when `flush` is called, like Roblox's deferred signals.
local function walker(speed, deferred)
	local queued = 0
	local fake = { speed = speed, onChange = nil :: any }
	local self = setmetatable({}, {
		__index = function(_, key) if key == "WalkSpeed" then return fake.speed end end,
		__newindex = function(_, key, value)
			if key ~= "WalkSpeed" or value == fake.speed then return end
			fake.speed = value
			if deferred then queued += 1 elseif fake.onChange then fake.onChange() end
		end,
	})
	local function flush()
		while queued > 0 do
			queued -= 1
			if fake.onChange then fake.onChange() end
		end
	end
	return self, fake, flush
end

check(near(Sprint.MULTIPLIER, 1.5) and near(Sprint.speed(16, true), 24) and near(Sprint.speed(16, false), 16), "sprinting is 1.5 times as fast")

for _, deferred in { false, true } do
	local mode = if deferred then " (late signals)" else " (signals at once)"
	local human, fake, flush = walker(16, deferred)
	local control = Sprint.controller()
	fake.onChange = control.changed
	control.attach(human)
	flush()
	check(near(human.WalkSpeed, 16), "walks at the usual speed" .. mode)
	control.setHeld(true)
	flush()
	check(near(human.WalkSpeed, 24) and near(control.walking(), 16), "holding Shift sprints" .. mode)
	-- Its own change, delivered late, never stacks.
	for _ = 1, 5 do control.changed() end
	check(near(human.WalkSpeed, 24), "sprinting never stacks" .. mode)
	control.setHeld(false)
	flush()
	check(near(human.WalkSpeed, 16), "letting go walks again" .. mode)

	-- The server freezes the diamond holder (0) while they sprint, then lets
	-- them go (16): they stay still, then sprint on.
	control.setHeld(true)
	flush()
	human.WalkSpeed = 0
	flush()
	check(near(human.WalkSpeed, 0) and near(control.walking(), 0), "frozen while sprinting stays frozen" .. mode)
	human.WalkSpeed = 16
	flush()
	check(near(human.WalkSpeed, 24), "unfrozen while still holding Shift: sprinting again" .. mode)
	control.setHeld(false)
	flush()
	check(near(human.WalkSpeed, 16), "and walking once Shift is let go" .. mode)

	-- Diamond Climb's speed slider sets 20: sprinting is 30, walking 20.
	human.WalkSpeed = 20
	flush()
	check(near(control.walking(), 20) and near(human.WalkSpeed, 20), "a new walking speed is kept" .. mode)
	control.setHeld(true)
	flush()
	check(near(human.WalkSpeed, 30), "sprinting goes from the new speed" .. mode)
	control.setHeld(false)
	flush()
	check(near(human.WalkSpeed, 20), "back to the climb's speed" .. mode)

	-- A new character starts from its own speed; no character, no trouble.
	control.attach(nil)
	control.setHeld(true)
	control.changed()
	check(control.held(), "holding with no character is fine" .. mode)
	local fresh, freshFake, freshFlush = walker(16, deferred)
	freshFake.onChange = control.changed
	control.attach(fresh)
	freshFlush()
	check(near(fresh.WalkSpeed, 24), "a new character still holding Shift sprints" .. mode)
	control.setHeld(false)
	freshFlush()
	check(near(fresh.WalkSpeed, 16), "and walks when it's let go" .. mode)
end
print("sprint: " .. passed .. " checks passed")
'''

work = root / "tests" / ".sprint.luau"
work.write_text(source + test, encoding="utf-8")
try:
    result = subprocess.run([luau, str(work)], capture_output=True, text=True)
finally:
    work.unlink(missing_ok=True)
print(result.stdout.strip())
if result.returncode != 0 or "FAIL" in result.stdout or result.stderr.strip():
    print(result.stderr.strip())
    sys.exit(1)
