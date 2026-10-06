"""Checks the first-person hands' maths under the Luau CLI with a Roblox
stand-in: the dig swing starts and ends at rest without a jump, lands at its
impact point at the right pace for the server's dig rate, and the hands are
refitted to the field of view so they look the same on screen at any FOV.

    python3 tests/first-person.py [path/to/luau]
"""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]


def module(path: str) -> str:
    source = (root / path).read_text(encoding="utf-8")
    source = re.sub(r'require\(Shared:WaitForChild\("(\w+)"\)\)', r'require("../src/shared/\1")', source)
    return "(function()\n" + source + "\nend)()"


test = r'''
local passed = 0
local function check(condition: boolean, message: string)
	if not condition then error("FAIL " .. message, 2) end
	passed += 1
end
local function near(a: number, b: number, tolerance: number?): boolean
	return math.abs(a - b) <= (tolerance or 1e-6)
end

-- The swing starts and ends at rest, so swings chain without a jump.
local rest, finish = FirstPerson.pose(0), FirstPerson.pose(1)
for _, key in { "inward", "up", "back", "pitch", "curl" } do
	check(near((rest :: any)[key], (finish :: any)[key]), "the swing ends where it began: " .. key)
end
check(near(rest.inward, 0) and near(rest.up, 0) and near(rest.back, 0) and near(rest.pitch, 0), "it begins at rest")
-- No frame jumps: small steps through the swing make small moves.
local previous = rest
local deepest, deepestAt, tightest, tightestAt = math.huge, 0, -1, 0
for i = 1, 1000 do
	local t = i / 1000
	local p = FirstPerson.pose(t)
	check(math.abs(p.back - previous.back) < 0.012 and math.abs(p.up - previous.up) < 0.012
		and math.abs(p.inward - previous.inward) < 0.012 and math.abs(p.pitch - previous.pitch) < 0.012
		and math.abs(p.curl - previous.curl) < 0.012, "the swing moves smoothly at " .. t)
	if p.back < deepest then deepest, deepestAt = p.back, t end
	if p.curl > tightest then tightest, tightestAt = p.curl, t end
	previous = p
end
-- The hand reaches furthest into the rock at the impact, fingers clawed, and
-- draws back before it: a wind-up, a strike, a rake.
check(near(deepestAt, FirstPerson.IMPACT, 0.002), "the hand reaches furthest at the impact: " .. deepestAt)
check(FirstPerson.pose(FirstPerson.IMPACT).curl > 0.85, "the fingers are clawed as it lands")
check(FirstPerson.pose(0.3).back > 0.1 and FirstPerson.pose(0.3).up > 0.1, "it winds up, back and up, before striking")
check(FirstPerson.pose(0.75).up < -0.15, "it rakes down after landing")
check(tightestAt > FirstPerson.IMPACT, "the claw is tightest while raking")
-- The drive into the rock speeds up: faster just before the impact than just after the wind-up.
local function speed(t: number): number
	return math.abs(FirstPerson.pose(t + 0.005).back - FirstPerson.pose(t).back) / 0.005
end
check(speed(0.49) > speed(0.36) * 2, "the strike speeds up into the rock")
-- A strike each SWING_SECONDS digs as fast as holding the button always did:
-- the server allows DigPerSecond / 4 rocks per request.
check(near(Config.DigPerSecond * FirstPerson.SWING_SECONDS, math.ceil(Config.DigPerSecond / 4), 0.5), "strikes keep the dig rate")

-- Field of view: the base FOV needs no change; wider ones draw the hands bigger.
check(near(FirstPerson.fovScale(FirstPerson.FOV_DEFAULT), 1), "the default FOV fits as framed")
check(FirstPerson.fovScale(FirstPerson.FOV_MAX) > 1 and FirstPerson.fovScale(FirstPerson.FOV_MIN) < 1, "wider FOVs draw the hands bigger")
-- On screen (x / depth), a point at the hands' resting depth moves out exactly
-- with the screen's edge, at every FOV.
local function screen(p: Vector3): (number, number)
	return p.X / -p.Z, p.Y / -p.Z
end
for _, fov in { 50, 70, 85, 100 } do
	local scale = FirstPerson.fovScale(fov)
	local edge = math.tan(math.rad(fov) / 2) / math.tan(math.rad(70) / 2)
	local framed = Vector3.new(0.58, -0.92, -1.6)
	local fitted = FirstPerson.fit(CFrame.new(framed), scale).Position
	local fx, fy = screen(fitted)
	local bx, by = screen(framed)
	check(near(fx, bx * edge, 1e-6) and near(fy, by * edge, 1e-6), "the hands keep their place on screen at FOV " .. fov)
	-- The hands stay one rigid shape: every distance scales alike.
	local a = FirstPerson.fit(CFrame.new(0.2, -0.7, -1.1), scale).Position
	local b = FirstPerson.fit(CFrame.new(-0.4, -1.1, -2.2), scale).Position
	local before = (Vector3.new(0.2, -0.7, -1.1) - Vector3.new(-0.4, -1.1, -2.2)).Magnitude
	check(near((a - b).Magnitude, before * scale * 0.5, 1e-6), "the hands keep their shape at FOV " .. fov)
	-- And close enough to the camera not to sink into rock you stand against.
	check(-fitted.Z < 1, "the hands are drawn close to the camera at FOV " .. fov)
end
-- Rotation is kept as framed.
local turned = FirstPerson.fit(CFrame.new(0, -1, -1.6) * CFrame.Angles(0.3, 0.2, 0.1), 1.3)
local expected = CFrame.Angles(0.3, 0.2, 0.1)
check(near(turned.LookVector.X, expected.LookVector.X) and near(turned.LookVector.Y, expected.LookVector.Y), "rotation is kept")
print(string.format("PASS: %d first-person checks", passed))
'''

generated = root / "tests/first-person.generated.luau"
try:
    mock = (root / "tests/roblox-mock.luau").read_text(encoding="utf-8")
    body = (
        mock
        + "\nlocal Config = " + module("src/shared/Config.luau")
        + "\nlocal FirstPerson = " + module("src/client/FirstPerson.luau")
        + "\n" + test
    )
    generated.write_text(body, encoding="utf-8")
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(generated)], check=True)
finally:
    generated.unlink(missing_ok=True)
