"""Runs the server Mountain and the client MountainView together under the Luau
CLI and checks that every client keeps an exact, watertight copy of the rock.

    python3 tests/mountain-sync.py [path/to/luau]
"""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]


def module(path: str) -> str:
    source = (root / path).read_text(encoding="utf-8")
    source = re.sub(r'local Shared = [^\n]*\n', "", source)
    source = source.replace('require(Shared:WaitForChild("PartShapes"))', "PartShapes")
    source = re.sub(r'require\(Shared:WaitForChild\("(\w+)"\)\)', r'require("../src/shared/\1")', source)
    source = re.sub(r'require\(ReplicatedStorage:WaitForChild\("DiamondRush"\):WaitForChild\("(\w+)"\)\)', r'require("../src/shared/\1")', source)
    return "(function()\n" + source + "\nend)()"


test = r'''
local Grid = require("../src/shared/Grid")
local RockStyle = require("../src/shared/RockStyle")
local LAYER, SPAN = Grid.LAYER, Grid.SPAN

local passed = 0
local function check(condition: boolean, message: string)
	if not condition then error("FAIL " .. message, 2) end
	passed += 1
end

-- Faces a shape leaves part-open or fully open, as key offsets. Every such face
-- must border open air or another drawn cell, or the hollow interior shows.
local function openFaces(shape: number): { number }
	if shape == RockStyle.BLOCK then return {} end
	local d = RockStyle.DIRECTIONS[shape]
	if shape <= 5 then
		local toward = d[1] + d[2] * SPAN
		local sides = if d[1] ~= 0 then { SPAN, -SPAN } else { 1, -1 }
		return { LAYER, toward, sides[1], sides[2] }
	end
	return { LAYER, d[1], d[2] * SPAN, -d[1], -d[2] * SPAN }
end

local function verify(view: any, server: any, label: string)
	local grid = view.grid
	local serverCount, clientCount = 0, 0
	for key in server.grid.solid do
		serverCount += 1
		check(grid:isSolid(key), label .. ": client has every server rock")
	end
	grid:eachSolid(function() clientCount += 1 end)
	check(serverCount == clientCount, label .. string.format(": same rock count (%d server, %d client)", serverCount, clientCount))
	check(grid.sealed[server.diamondKey] == true and not grid:isSolid(server.diamondKey), label .. ": diamond cavity stays empty")
	local exposed = 0
	grid:eachSolid(function(key)
		local part = view.parts[key]
		if grid:isExposed(key) then
			exposed += 1
			check(part ~= nil and not part.destroyed and part.Parent == view.folder, label .. ": every exposed rock is drawn")
			check(view.keys[part] == key, label .. ": part maps back to its cell")
			local shape = view.codes[key] % 16
			check(shape == RockStyle.shape(grid, key), label .. ": drawn shape matches its neighbours")
			for _, offset in openFaces(shape) do
				local neighbour = key + offset
				check(grid:isAir(neighbour) or (grid:isSolid(neighbour) and grid:isExposed(neighbour)),
					label .. ": open faces only border air or drawn rock (watertight)")
			end
		else
			check(part == nil, label .. ": buried rock has no part")
		end
	end)
	local drawn = 0
	for _, part in view.parts do
		drawn += 1
		check(not part.destroyed, label .. ": no destroyed part is still listed")
	end
	check(drawn == exposed, label .. string.format(": one part per exposed rock (%d parts, %d exposed)", drawn, exposed))
end

local function snapshot(view: any, server: any, animated: boolean?)
	for _, message in server:snapshot(animated) do
		view:_handle(message[1], message[2])
	end
end
local function deliver(views: { any }, server: any, effect: string?)
	for _, diff in server:flush(effect) do
		for _, view in views do view:_handle("diff", diff) end
	end
end

local events = {}
local server = Mountain.new(25000, 0.4, function(open) table.insert(events, open) end)
local view = MountainView.new()
snapshot(view, server)
verify(view, server, "initial snapshot")
check(view.ready, "snapshot completes")

-- Blasts, digs, refills and growth stay in step.
server:blast(3000, nil)
deliver({ view }, server, "blast")
verify(view, server, "blast")
local key = server.grid.exposedList[1]
check(server:dig(key, 25) > 0, "dig removes rock")
deliver({ view }, server, "dig")
verify(view, server, "dig")
local restored = server:restore(1800, 60000)
check(restored == 1800, "restore refills the requested rocks")
deliver({ view }, server, "restore")
verify(view, server, "restore")
local grown = server:restore(server:total() - server:remaining() + 4000, 60000)
deliver({ view }, server, "restore")
verify(view, server, "refill and growth")
check(server:remaining() == server:total(), "growth leaves no holes")

-- A long blast streams changes while it runs, like the live server.
local streamed = 0
server:blast(9000, function()
	streamed += 1
	if streamed % 20 == 0 then deliver({ view }, server, "blast") end
end)
deliver({ view }, server, "blast")
verify(view, server, "streamed blast")

-- A player joining mid-round gets the current rock, then follows changes.
local late = MountainView.new()
snapshot(late, server)
verify(late, server, "late join")
server:blast(2500, nil)
server:restore(900, 60000)
deliver({ view, late }, server, "blast")
verify(view, server, "after late join (first client)")
verify(late, server, "after late join (late client)")

-- Exposure events: reveal, rebury, reveal again.
local probe = Mountain.new(25000, 0.4, function(open) table.insert(events, open) end)
table.clear(events)
local dx, dy, dz = Grid.coords(probe.diamondKey)
local above = Grid.key(dx, dy + 1, dz)
check(probe.grid:remove(above), "fixture: cell above the diamond is rock")
probe:_syncDiamond()
check(probe.revealed and events[1] == true, "opening next to the diamond announces it")
check(probe:restore(1, 25000) == 1 and not probe.revealed and events[2] == false, "rebuilding buries it again")
probe.grid:remove(above)
probe:_syncDiamond()
check(probe.revealed and events[3] == true, "digging can announce it again")
probe:_syncDiamond()
check(#events == 3, "unchanged exposure does not repeat announcements")

-- Server-side checks that replace raycasts against server parts.
local gem = probe:keyPosition(probe.diamondKey)
local shaftTop = dy + 1
while probe.grid:isSolid(Grid.key(dx, shaftTop + 1, dz)) do
	shaftTop += 1
	probe.grid:remove(Grid.key(dx, shaftTop, dz))
end
local sky = gem + Vector3.new(0, (shaftTop - dy + 3) * 0.4, 0)
check(not probe:lineBlocked(sky, gem), "a dug shaft gives a clear sightline to the diamond")
check(probe:lineBlocked(gem + Vector3.new(8, 2, 0), gem), "rock between the player and the diamond blocks pickup")
local beside = probe:keyPosition(Grid.key(dx + 4, 2, dz))
local top = probe:coveredTop(beside, beside.Y - 1, beside.Y + 1)
check(top ~= nil and top > beside.Y + 1, "a buried character is lifted to the rock surface")
local high = gem + Vector3.new(0, 60, 0)
check(probe:coveredTop(high, high.Y - 1, high.Y + 1) == nil, "a character in open air is left alone")
local summit = probe:summit()
check(summit ~= nil and summit.Y >= gem.Y, "summit is the highest uncovered rock")

-- A new round replaces the rock; stale changes from the old round are ignored.
local before = view.folder
local nextRound = Mountain.new(20000, 0.4, function() end)
snapshot(view, nextRound, true)
check(before.destroyed and view.folder ~= before, "the old mountain is removed")
server:blast(500, nil)
deliver({ view }, server, "blast")
verify(view, nextRound, "stale diff ignored")

-- Client cost of a very large gift (CPU only; rendering is Roblox's).
local big = Mountain.new(250000, 0.4, function() end)
local client = MountainView.new()
local started = os.clock()
snapshot(client, big)
print(string.format("250k snapshot: %d bytes, client build %.2f s CPU, %d parts", (function()
	local bytes = 0
	for _, message in big:snapshot() do if type(message[2]) == "buffer" then bytes += buffer.len(message[2]) end end
	return bytes
end)(), os.clock() - started, (function() local n = 0 for _ in client.parts do n += 1 end return n end)()))
big:blast(100000, nil)
local diffs = big:flush("blast")
local bytes = 0
for _, diff in diffs do for _, chunk in diff.removed or {} do bytes += buffer.len(chunk) end end
started = os.clock()
for _, diff in diffs do client:_handle("diff", diff) end
print(string.format("100k blast: %d bytes over the network, client applied in %.2f s CPU", bytes, os.clock() - started))
verify(client, big, "100k blast")
print(string.format("PASS: %d mountain sync checks", passed))
'''

generated = root / "tests/mountain-sync.generated.luau"
try:
    mock = (root / "tests/roblox-mock.luau").read_text(encoding="utf-8")
    body = (
        mock
        + "\nlocal PartShapes = " + module("src/shared/PartShapes.luau")
        + "\nlocal Mountain = " + module("src/server/Mountain.luau")
        + "\nlocal MountainView = " + module("src/client/MountainView.luau")
        + "\n" + test
    )
    generated.write_text(body, encoding="utf-8")
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(generated)], check=True)
finally:
    generated.unlink(missing_ok=True)
