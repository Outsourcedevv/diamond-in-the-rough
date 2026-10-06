"""Checks the leaderboard tallies, the two wooden boards and the gold statue
under the Luau CLI with a Roblox stand-in.

    python3 tests/showcase.py [path/to/luau]
"""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]


def module(path: str) -> str:
    source = (root / path).read_text(encoding="utf-8")
    source = re.sub(r'local Shared = [^\n]*\n', "", source)
    for inlined in ("PartShapes", "DiamondShape"):
        source = source.replace(f'require(Shared:WaitForChild("{inlined}"))', inlined)
    source = re.sub(r'require\(Shared:WaitForChild\("(\w+)"\)\)', r'require("../src/shared/\1")', source)
    return "(function()\n" + source + "\nend)()"


test = r'''
local passed = 0
local function check(condition: boolean, message: string)
	if not condition then error("FAIL " .. message, 2) end
	passed += 1
end

-- Tallies: running totals per viewer, ranked, saved and restored.
local tally = Leaderboards.tally(nil)
tally.add("amy", "Amy", 100)
tally.add("bob", "Bob", 500)
tally.add("amy", "Amy ✨", 450)
tally.add("cat", "Cat", 0)
tally.add("", "Nobody", 50)
local top = tally.top(10)
check(#top == 2 and top[1].key == "amy" and top[1].value == 550 and top[2].key == "bob", "totals add up and rank highest first")
check(top[1].name == "Amy ✨", "the latest display name is shown")
local restored = Leaderboards.tally(tally.serialize(100))
check(restored.top(1)[1].value == 550 and restored.size() == 2, "totals survive saving")
local hostile = Leaderboards.tally({ { u = "x", n = "X", v = -5 }, "junk", { u = 3 }, { u = "ok", n = "OK", v = 7 } })
check(hostile.size() == 1 and hostile.top(1)[1].key == "ok", "bad saved rows are ignored")
for i = 1, 5200 do tally.add("viewer" .. i, "Viewer " .. i, i) end
check(tally.size() <= 5000 and tally.top(1)[1].value == 5200, "memory stays bounded and keeps the biggest totals")
local smallestKept = math.huge
for _, entry in tally.top(5000) do smallestKept = math.min(smallestKept, entry.value) end
check(smallestKept > 1000, "the smallest totals were dropped first")
tally.reset()
check(tally.size() == 0 and #tally.top(10) == 0, "reset clears the board")

-- The boards stand behind the mountain, either side, facing the camp.
local camp = Vector3.new(0, 0, 56.4)
local spots = Leaderboards.spots(55, 26.4, camp)
check(#spots == 2 and spots[1].at.Z < -55 and spots[2].at.Z < -55, "boards stand behind the mountain")
check(spots[1].at.X < 0 and spots[2].at.X > 0, "one board on each side of the summit")
local folder = Instance.new("Folder")
local function ground() return 4 end
local blue, red = Color3.fromRGB(36, 92, 204), Color3.fromRGB(196, 36, 44)
local boards = {}
for index, style in {
	{ title = "⛏️ TOP HELPERS", unit = "coins", trim = blue, valueColour = Color3.new(1, 1, 1), emblem = "pickaxe", empty = "Send a gift" },
	{ title = "🧱 TOP GRIEFERS", unit = "coins", trim = red, valueColour = Color3.new(1, 1, 1), emblem = "boulders", empty = "Add stone" },
} do
	local before = #instances
	local board = Leaderboards.build(folder, spots[index].at, spots[index].facing, 14.5, style, ground)
	table.insert(boards, board)
	local parts, trim, wood, minY, maxY = 0, 0, 0, math.huge, -math.huge
	local face, emblem, roofs = nil, 0, {}
	for i = before + 1, #instances do
		local p = instances[i]
		if (p.ClassName == "Part" or p.ClassName == "WedgePart") and not p.destroyed then
			parts += 1
			check(p.Anchored and p.CanTouch == false and p.CanQuery == false, "board parts are static scenery")
			if p.Name == "Trim" then
				trim += 1
				check(p.Color == style.trim, "the border is painted in the board's colour")
				check(p.Material == "Material.Wood", "the border is painted wood")
			end
			if p.Material == "Material.Wood" or p.Material == "Material.WoodPlanks" then wood += 1 end
			if p.Name == "Face" then face = p end
			if p.Name == "PickaxeHandle" or p.Name == "BoulderBase" then emblem += 1 end
			if p.Name == "Roof" then table.insert(roofs, p) end
			minY = math.min(minY, p.CFrame.Position.Y)
			maxY = math.max(maxY, p.CFrame.Position.Y)
		end
	end
	check(trim == 4 and emblem == 1 and #roofs == 2, style.title .. ": border, emblem and roof are built")
	check(wood > parts * 0.6, style.title .. ": the board is mostly wood")
	check(face ~= nil and face.Size.X > 30 and face.Size.Y > 24, style.title .. ": the list panel is really big")
	check(maxY - minY > 40, style.title .. ": the whole board stands over 40 studs tall")
	local toCamp = (camp - face.CFrame.Position)
	toCamp = Vector3.new(toCamp.X, 0, toCamp.Z).Unit
	check(face.CFrame.LookVector:Dot(toCamp) > 0.99, style.title .. ": the list faces the camp")
	-- Roof wedges are tall at the ridge and slope down to the front and back.
	for _, roof in roofs do
		local low = roof.CFrame.LookVector * -PartShapes.wedgeFront()
		local away = roof.CFrame.Position - face.CFrame.Position
		away = Vector3.new(away.X, 0, away.Z).Unit
		check(Vector3.new(low.X, 0, low.Z).Unit:Dot(away) > 0.99, style.title .. ": roof slopes down away from its ridge")
	end
end
-- Rows show names and values; an empty board shows its invitation.
local function texts(): { [string]: boolean }
	local seen = {}
	for _, object in instances do
		if object.ClassName == "TextLabel" and object.Parent ~= nil and object.Text then seen[object.Text] = true end
	end
	return seen
end
boards[1].show({ { key = "a", name = "Amy", value = 12345 }, { key = "b", name = "Bob", value = 99 } })
local shown = texts()
check(shown["Amy"] and shown["12,345 coins"] and shown["Bob"] and shown["99 coins"], "rows show names and coins")
check(shown["⛏️ TOP HELPERS"] and shown["🧱 TOP GRIEFERS"], "titles are on the boards")

-- The gold statue and its plaque.
local before = #instances
local statue = Statue.build(folder, { name = "DiamondDave", coins = 34999, position = Vector3.new(10, 2, 80), yaw = 0.5 })
local gold, facets, plaque = 0, 0, false
for i = before + 1, #instances do
	local p = instances[i]
	if p.ClassName == "Part" and (p.Name == "Torso" or p.Name == "Head" or p.Name == "RaisedArm" or p.Name == "Leg" or p.Name == "Arm") then
		gold += 1
		check(p.Material == "Material.Metal" and p.Color.R > p.Color.B * 2, "the figure is gold")
		check(p.CFrame.Position.Y > 2 + 6, "the figure stands on the pedestal")
	end
	if p.Name == "Facet" then facets += 1 end
	if p.Name == "Plaque" then
		plaque = true
		check(p.CFrame.LookVector:Dot(Vector3.new(-math.sin(0.5), 0, -math.cos(0.5))) > 0.99, "the plaque faces the same way as the statue")
	end
end
check(gold == 6 and facets == 64 and plaque, "gold figure, a full diamond and a plaque are built")
shown = texts()
check(shown["DiamondDave"] and shown["34,999 COINS"], "the plaque shows the name and coins")

-- "Remove the statue nearest me" picks the closest statue within reach.
local saved = { { x = 0, z = 80 }, { x = 20, z = 80 }, { x = 60, z = 80 } }
check(Statue.nearest(saved, Vector3.new(17, 9, 78), 30) == 2, "the closest statue is chosen")
check(Statue.nearest(saved, Vector3.new(4, 50, 80), 30) == 1, "height does not matter, only distance across the ground")
check(Statue.nearest(saved, Vector3.new(0, 0, 0), 30) == nil, "nothing is removed when no statue is in reach")
check(Statue.nearest({}, Vector3.new(0, 0, 80), 30) == nil, "nothing to remove when there are no statues")
print(string.format("PASS: %d leaderboard and statue checks", passed))
'''

generated = root / "tests/showcase.generated.luau"
try:
    mock = (root / "tests/roblox-mock.luau").read_text(encoding="utf-8")
    body = (
        mock
        + "\nlocal PartShapes = " + module("src/shared/PartShapes.luau")
        + "\nlocal DiamondShape = " + module("src/shared/DiamondShape.luau")
        + "\nlocal Leaderboards = " + module("src/server/Leaderboards.luau")
        + "\nlocal Statue = " + module("src/server/Statue.luau")
        + "\n" + test
    )
    generated.write_text(body, encoding="utf-8")
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(generated)], check=True)
finally:
    generated.unlink(missing_ok=True)
