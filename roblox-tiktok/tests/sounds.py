"""Checks the sound player (src/client/Sounds.luau) under the Luau CLI with a
Roblox stand-in: holding dig for ten seconds plays every strike's sound
without running out of places, a place frees up as soon as its sound ends,
a sound that never ends (it failed to load) is still let go, and gifts still
sound while digging.

    python3 tests/sounds.py [path/to/luau]
"""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
luau = sys.argv[1] if len(sys.argv) > 1 else "luau"
source = (root / "src/client/Sounds.luau").read_text(encoding="utf-8")
source = re.sub(r'local SoundService = [^\n]*\n', "", source).replace("return Sounds", "")

harness = r'''
local clock = 0
local timers = {}
local function after(seconds, f) table.insert(timers, { at = clock + seconds, f = f }) end
local task = { delay = function(seconds, f) after(seconds, f) end }
local os = { clock = function() return clock end }
local function run(seconds)
	local finish = clock + seconds
	while true do
		local soonest, index = nil, nil
		for i, timer in timers do
			if timer.at <= finish and (soonest == nil or timer.at < soonest) then soonest, index = timer.at, i end
		end
		if index == nil then clock = finish return end
		local timer = table.remove(timers, index)
		clock = math.max(clock, timer.at)
		timer.f()
	end
end
-- Files and how long each lasts at normal speed; "broken.wav" never ends.
local LENGTHS = { ["rbxasset://sounds/collide.wav"] = 0.35, ["rbxasset://sounds/snap.wav"] = 0.2, ["rbxasset://sounds/clickfast.wav"] = 0.1,
	["rbxasset://sounds/impact_explosion_03.mp3"] = 2.5, ["rbxasset://sounds/action_jump_land.mp3"] = 0.5 }
local started, live, destroyed = 0, 0, 0
local speeds = {}
local SoundService = { Name = "SoundService" }
local workspace = { Terrain = {} }
local Enum = { RollOffMode = { InverseTapered = "InverseTapered" } }
local Instance = { new = function(className)
	local object = { ClassName = className }
	function object:Destroy() destroyed += 1 end
	if className == "Sound" then
		local listeners = {}
		object.Ended = { Connect = function(_, f) table.insert(listeners, f) end }
		function object:Play()
			started += 1
			table.insert(speeds, self.PlaybackSpeed)
			live += 1
			local length = LENGTHS[self.SoundId]
			if length then
				after(length / self.PlaybackSpeed, function()
					live -= 1
					for _, f in listeners do f() end
				end)
			end
		end
	end
	return object
end }
'''

test = r'''
local passed = 0
local function check(condition, message)
	if not condition then error("FAIL " .. message, 2) end
	passed += 1
end
local function layers(cue) return #Sounds.CUES[cue] end

-- Digging never uses the explosion, and stays quiet.
for _, cue in { "dig", "crumble" } do
	for _, layer in Sounds.CUES[cue] do
		check(layer.file ~= "boom" and layer.file ~= "glass" and layer.file ~= "rocket", cue .. " has no blast in it")
		check(layer.volume <= 0.25, cue .. " stays quiet")
	end
end

-- Hits in a row climb in pitch, eight steps, then round again.
check(Sounds.digPitch(1) == 1 and Sounds.digPitch(8) > Sounds.digPitch(7) and Sounds.digPitch(9) == 1, "the dig pitch climbs and comes round")
check(Sounds.digPitch(8) < 1.25, "the climb stays gentle")
-- The pitch raises every layer.
local low = Sounds.CUES.dig[1].pitch[1]
speeds = {}
Sounds.play("dig", Vector3, 1, 1.2)
check(speeds[1] >= low * 1.2 - 1e-9, "a higher pitch plays faster")
run(1)
started = 0

-- Hold dig for ten seconds: four strikes a second, a crumble every fourth.
local strikes, expected, highest = 0, 0, 0
for _ = 1, 40 do
	strikes += 1
	Sounds.play("dig", Vector3, 1, Sounds.digPitch(strikes))
	expected += layers("dig")
	if strikes % 4 == 0 then
		Sounds.play("crumble", Vector3)
		expected += layers("crumble")
	end
	run(0.25)
	highest = math.max(highest, Sounds.playingCount())
end
check(started == expected, string.format("every strike sounds while dig is held (%d of %d)", started, expected))
check(highest < Sounds.MAX_PLAYING / 2, string.format("digging uses few places at once (%d)", highest))

-- A gift in the middle of digging still sounds.
local before = started
Sounds.play("bigBoom", Vector3)
run(0.2)
check(started - before == layers("bigBoom"), "a gift sounds while digging")

run(10)
check(Sounds.playingCount() == 0, "every place is free once the sounds end")

-- A file that never finishes is let go after the longest a file could take.
Sounds.FILES.broken = "broken.wav"
Sounds.CUES.brokenCue = { { file = "broken", volume = 1, pitch = { 1, 1 } } }
Sounds.play("brokenCue")
check(Sounds.playingCount() == 1, "the broken sound holds a place")
run(Sounds.LONGEST_SECONDS + 1)
check(Sounds.playingCount() == 0, "and lets it go in the end")
print("sounds: " .. passed .. " checks passed")
'''

work = root / "tests" / ".sounds.luau"
work.write_text(harness + source + test, encoding="utf-8")
try:
    result = subprocess.run([luau, str(work)], capture_output=True, text=True)
finally:
    work.unlink(missing_ok=True)
print(result.stdout.strip())
if result.returncode != 0 or "FAIL" in result.stdout or result.stderr.strip():
    print(result.stderr.strip())
    sys.exit(1)
