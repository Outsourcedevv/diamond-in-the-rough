"""Plays every gift tier's effect in a simulated client under the Luau CLI, on
a simulated clock: every sequence runs to the end without errors, stays within
its part, light and particle budgets, uses only Roblox's built-in particle
textures, shakes the camera only briefly and leaves nothing behind.

    python3 tests/gift-effects.py [path/to/luau]
"""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]


def module(path: str) -> str:
    source = (root / path).read_text(encoding="utf-8")
    source = re.sub(r'local Shared = [^\n]*\n', "", source)
    source = re.sub(r'require\(Shared:WaitForChild\("(\w+)"\)\)', r'require("../src/shared/\1")', source)
    return "(function()\n" + source + "\nend)()"


harness = r'''
-- A simulated clock: delayed calls, render steps and tweens run in order.
local clock = 0
local scheduled: { { at: number, run: () -> () } } = {}
local function schedule(delay: number, run: () -> ())
	table.insert(scheduled, { at = clock + math.max(0, delay), run = run })
end
task = {
	wait = function() end,
	defer = function(f, ...) f(...) end,
	spawn = function(f, ...) f(...) end,
	delay = function(delay, f, ...)
		local args = { ... }
		schedule(delay, function() f(table.unpack(args)) end)
	end,
}
local renderConnections: { [any]: (number) -> () } = {}
local bound: { [string]: (number) -> () } = {}
RunService = {
	RenderStepped = { Connect = function(_, callback)
		local handle = {}
		handle.Disconnect = function() renderConnections[handle] = nil end
		renderConnections[handle] = callback
		return handle
	end },
	BindToRenderStep = function(_, name, _priority, callback) bound[name] = callback end,
	UnbindFromRenderStep = function(_, name) bound[name] = nil end,
}
local TweenService = { Create = function(_, object, info, goal)
	return {
		Play = function() schedule(info.Time, function() for key, value in goal do object[key] = value end end) end,
		Cancel = function() end,
	}
end }
TweenInfo = { new = function(time) return { Time = time or 1 } end }
local Debris = { AddItem = function(_, object, seconds) schedule(seconds, function() object:Destroy() end) end }
local Lighting = newInstance("Lighting")
local camera = { CFrame = CFrame.new(0, 20, 60) }
workspace.CurrentCamera = camera
workspace.FindFirstChild = function() return nil end
game = { GetService = function(_, name)
	if name == "RunService" then return RunService end
	if name == "TweenService" then return TweenService end
	if name == "Debris" then return Debris end
	if name == "Lighting" then return Lighting end
	return { WaitForChild = function() return Shared end }
end }
Enum = setmetatable({ RenderPriority = { Camera = { Value = 200 } } }, { __index = function(_, group)
	return setmetatable({}, { __index = function(_, item) return group .. "." .. item end })
end })
ColorSequenceKeypoint = { new = function(...) return { ... } end }
-- Vector3 needs Lerp here.
local oldIndex = vector.__index
vector.__index = function(v, k)
	if k == "Lerp" then return function(a, b, t) return a + (b - a) * t end end
	return oldIndex(v, k)
end
-- Particle emitters record what they emit.
local emitted = 0
local textures: { [string]: boolean } = {}
local makeInstance = newInstance
newInstance = function(className: string): any
	local object = makeInstance(className)
	if className == "ParticleEmitter" then
		object.Emit = function(self, count)
			emitted += count
			textures[self.Texture] = true
		end
	end
	return object
end
Instance = { new = newInstance }
typeof = function(value)
	if type(value) == "table" and getmetatable(value) == vector then return "Vector3" end
	return type(value)
end
'''

test = r'''
local passed = 0
local function check(condition: boolean, message: string)
	if not condition then error("FAIL " .. message, 2) end
	passed += 1
end

-- Roblox would tear down a destroyed folder's contents with it.
local function inWorld(object: any): boolean
	local parent = object.Parent
	while parent ~= nil do
		if parent == workspace or parent == Lighting then return true end
		if type(parent) ~= "table" or parent.destroyed then return false end
		parent = rawget(parent, "Parent")
	end
	return false
end
local function live(className: string): number
	local count = 0
	for _, object in instances do
		if object.ClassName == className and not object.destroyed and inWorld(object) then count += 1 end
	end
	return count
end
local function liveParts(): number
	return live("Part")
end

local state = newInstance("Configuration")
state:SetAttribute("Skin", "stone")
local gui = newInstance("PlayerGui")
GiftEffects.start(gui, state)

-- Runs the clock: delayed calls, then the camera (reset each frame, as Roblox's
-- camera does), then render steps.
local maxShake = 0
local function run(seconds: number)
	local finish = clock + seconds
	while clock < finish do
		clock += 1 / 60
		table.sort(scheduled, function(a, b) return a.at < b.at end)
		while scheduled[1] and scheduled[1].at <= clock do
			table.remove(scheduled, 1).run()
		end
		camera.CFrame = CFrame.new(0, 20, 60)
		for _, callback in bound do callback(1 / 60) end
		local look = camera.CFrame.LookVector
		maxShake = math.max(maxShake, math.deg(math.acos(math.clamp(-look.Z, -1, 1))))
		local callbacks = {}
		for _, callback in renderConnections do table.insert(callbacks, callback) end
		for _, callback in callbacks do callback(1 / 60) end
	end
end

local TIERS = { 1, 10, 100, 500, 1000, 10000 }
local expectedShake = { false, true, true, true, true, true }
for round = 1, 2 do
local adding = round == 2
for tier, coins in TIERS do
	local before = #instances
	emitted = 0
	maxShake = 0
	GiftEffects.play({ position = Vector3.new(3, 12, -2), coins = coins, name = "Tester", gift = "Gift", adding = adding, blocks = if adding then -coins * 100 else coins * 100 })
	local parts, lights, peakParts = 0, 0, 0
	for step = 1, 12 * 30 do
		run(1 / 30)
		peakParts = math.max(peakParts, liveParts())
	end
	for i = before + 1, #instances do
		local object = instances[i]
		if object.ClassName == "Part" then
			parts += 1
			check(object.Anchored and object.CanCollide == false and object.CanTouch == false and object.CanQuery == false and object.CastShadow == false,
				"tier " .. tier .. ": effect parts are never physical and cast no shadow")
		end
		if object.ClassName == "PointLight" then
			lights += 1
			check(object.Shadows == false, "tier " .. tier .. ": effect lights cast no shadows")
		end
		if object.ClassName == "ParticleEmitter" then
			local known = false
			for _, texture in GiftEffects.TEXTURES do known = known or object.Texture == texture end
			check(known, "tier " .. tier .. ": only built-in particle textures: " .. tostring(object.Texture))
		end
	end
	check(parts >= 2 and parts <= GiftEffects.PART_LIMIT, "tier " .. tier .. ": part budget kept (" .. parts .. ")")
	check(lights >= 1 and lights <= GiftEffects.LIGHT_LIMIT, "tier " .. tier .. ": light budget kept (" .. lights .. ")")
	check(emitted >= 20 and emitted <= 400, "tier " .. tier .. ": particle budget kept (" .. emitted .. ")")
	check(liveParts() == 0 and live("ParticleEmitter") == 0 and live("Trail") == 0 and live("PointLight") == 0, "tier " .. tier .. ": nothing is left behind")
	check(live("ColorCorrectionEffect") == 0, "tier " .. tier .. ": the colour grade is removed")
	check(next(renderConnections) == nil, "tier " .. tier .. ": every motion stops")
	check(not GiftEffects.shaking() and next(bound) == nil, "tier " .. tier .. ": the camera shake ends")
	check((maxShake > 0.05) == expectedShake[tier] and maxShake < 2.5, "tier " .. tier .. ": shake is gentle (" .. string.format("%.2f", maxShake) .. " degrees)")
	print(string.format("%s tier %d %-17s %2d parts (peak %2d), %d lights, %3d particles, shake %.2f deg", if adding then "adding" else "breaking", tier,
		(if adding then GiftEffects.ADD_TITLES else GiftEffects.TITLES)[tier], parts, peakParts, lights, emitted, maxShake))
end
end

-- Adding gifts are green and named for the adding tier; the haystack skin throws hay, not stone.
state:SetAttribute("Skin", "hay")
local before = #instances
GiftEffects.play({ position = Vector3.new(0, 10, 0), coins = 30, adding = true, blocks = -300, name = "Tester", gift = "Doughnut" })
run(0.2)
local banner = nil
for _, object in instances do
	if object.ClassName == "TextLabel" and object.Parent and object.Parent.Name == "GiftEffects" then banner = object end
end
check(banner ~= nil and banner.TextColor3 == Color3.fromRGB(90, 235, 170) and string.find(banner.Text, GiftEffects.ADD_TITLES[2], 1, true) ~= nil, "adding gifts glow green")
run(10)
before = #instances
GiftEffects.play({ position = Vector3.new(0, 10, 0), coins = 10, name = "Tester", gift = "Rose" })
run(0.2)
local hay = 0
for i = before + 1, #instances do
	local object = instances[i]
	if object.ClassName == "Part" and object.Material == "Material.Fabric" then hay += 1 end
end
check(hay > 0, "the haystack skin throws hay")
run(10)
state:SetAttribute("Skin", "stone")

-- Three big gifts at once: only two sequences play, the strongest kept.
GiftEffects.play({ position = Vector3.new(0, 10, 0), coins = 1000, name = "A", gift = "Galaxy" })
GiftEffects.play({ position = Vector3.new(5, 10, 0), coins = 500, name = "B", gift = "Money Gun" })
GiftEffects.play({ position = Vector3.new(-5, 10, 0), coins = 10000, name = "C", gift = "Universe" })
run(0.1)
local folders = 0
for _, object in instances do
	if object.ClassName == "Folder" and object.Name == "GiftBurst" and not object.destroyed and object.Parent == workspace then folders += 1 end
end
check(folders == 2, "at most two sequences at once: " .. folders)
run(12)
check(liveParts() == 0 and next(renderConnections) == nil and next(bound) == nil, "overlapping sequences clean up")

-- A tiny gift never interrupts a bigger show.
GiftEffects.play({ position = Vector3.new(0, 10, 0), coins = 1000, name = "A", gift = "Galaxy" })
GiftEffects.play({ position = Vector3.new(0, 10, 0), coins = 1000, name = "A", gift = "Galaxy" })
GiftEffects.play({ position = Vector3.new(0, 10, 0), coins = 1, name = "B", gift = "Rose" })
run(0.1)
folders = 0
for _, object in instances do
	if object.ClassName == "Folder" and object.Name == "GiftBurst" and not object.destroyed and object.Parent == workspace then folders += 1 end
end
check(folders == 2, "a rose does not cut short two galaxies")
run(12)

print(string.format("PASS: %d gift effect checks", passed))
'''

generated = root / "tests/gift-effects.generated.luau"
try:
    mock = (root / "tests/roblox-mock.luau").read_text(encoding="utf-8")
    body = mock + "\n" + harness + "\nlocal GiftEffects = " + module("src/client/GiftEffects.luau") + "\n" + test
    generated.write_text(body, encoding="utf-8")
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(generated)], check=True)
finally:
    generated.unlink(missing_ok=True)
