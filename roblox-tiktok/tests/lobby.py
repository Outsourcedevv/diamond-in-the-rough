"""Checks the royal lobby under the Luau CLI with a Roblox stand-in: where it
floats, the spawn, that the palace is closed all round (no sky shows, nobody
gets out), the game rooms and their portals, the emblems, the dais and
diamond, and the games menu's status line.

    python3 tests/lobby.py [path/to/luau]
"""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]


def module(path: str) -> str:
    source = (root / path).read_text(encoding="utf-8")
    source = re.sub(r'local Shared = [^\n]*\n', "", source)
    source = source.replace('require(Shared:WaitForChild("DiamondShape"))', "DiamondShape")
    source = re.sub(r'require\(Shared:WaitForChild\("(\w+)"\)\)', r'require("../src/shared/\1")', source)
    return "(function()\n" + source + "\nend)()"


test = r'''
local passed = 0
local function check(condition: boolean, message: string)
	if not condition then error("FAIL " .. message, 2) end
	passed += 1
end

workspace.BulkMoveTo = function(_, parts, frames)
	for i, p in parts do p.CFrame = frames[i] end
end
local before = #instances
local built = Lobby.build(workspace)
local O = Lobby.ORIGIN
local flat = Vector3.new(O.X, 0, O.Z)
-- Far from the valley (the terrain reaches 384 studs, the mountains about 680),
-- so the floating palace never shades the game, and high above the ground.
check(flat.Magnitude > 2000 and O.Y > 150, "the lobby floats far from the mountain valley")

-- The spawn stands at the entrance end of the hallway, facing the dais.
local spawn = built.spawn
check(spawn.ClassName == "SpawnLocation" and spawn.Neutral and spawn.Duration == 0 and spawn.Anchored, "a neutral spawn with no force field")
check(math.abs(spawn.CFrame.Position.Y - (O.Y + 0.5)) < 1e-6, "the spawn sits on the floor")
local toCentre = (Vector3.new(O.X, 0, O.Z) - Vector3.new(spawn.CFrame.Position.X, 0, spawn.CFrame.Position.Z)).Unit
check(spawn.CFrame.LookVector:Dot(toCentre) > 0.999, "players arrive facing the dais down the hallway")
check((spawn.CFrame.Position - O).Magnitude > 150, "the hallway is long: the spawn is far from the dais")

-- Every part, as plain numbers for fast ray tests.
local W = Lobby.HALL_WIDTH / 2
local counts = {}
local parts = {}
local lights, shadowed = 0, 0
for i = before + 1, #instances do
	local p = instances[i]
	if p.ClassName == "Part" or p.ClassName == "SpawnLocation" then
		counts[p.Name] = (counts[p.Name] or 0) + 1
		check(p.Anchored, p.Name .. " is anchored")
		local c = p.CFrame
		table.insert(parts, { part = p, px = c.p.X, py = c.p.Y, pz = c.p.Z, r = c.r, hx = p.Size.X / 2, hy = p.Size.Y / 2, hz = p.Size.Z / 2,
			cylinder = p.Shape == "PartType.Cylinder", opaque = (p.Transparency or 0) < 0.5, solid = p.CanCollide == true })
	elseif p.ClassName == "PointLight" then
		lights += 1
		if p.Shadows then shadowed += 1 end
	end
end
-- The distance along a ray to the first part `accept` lets through, or nil.
local function cast(origin, direction, accept, reach)
	local best = nil
	for _, q in parts do
		if not accept(q) then continue end
		local r = q.r
		local wx, wy, wz = origin.X - q.px, origin.Y - q.py, origin.Z - q.pz
		-- Into the part's own space (the rotation's transpose).
		local ox, oy, oz = r[1] * wx + r[4] * wy + r[7] * wz, r[2] * wx + r[5] * wy + r[8] * wz, r[3] * wx + r[6] * wy + r[9] * wz
		local dx = r[1] * direction.X + r[4] * direction.Y + r[7] * direction.Z
		local dy = r[2] * direction.X + r[5] * direction.Y + r[8] * direction.Z
		local dz = r[3] * direction.X + r[6] * direction.Y + r[9] * direction.Z
		local tmin, tmax = 0, best or reach
		local function slab(o, d, h)
			if math.abs(d) < 1e-9 then
				if o < -h or o > h then tmin = math.huge end
				return
			end
			local t1, t2 = (-h - o) / d, (h - o) / d
			if t1 > t2 then t1, t2 = t2, t1 end
			if t1 > tmin then tmin = t1 end
			if t2 < tmax then tmax = t2 end
		end
		slab(ox, dx, q.hx)
		if q.cylinder then
			-- Round across Y and Z.
			local radius = math.min(q.hy, q.hz)
			local a = dy * dy + dz * dz
			local b = 2 * (oy * dy + oz * dz)
			local cc = oy * oy + oz * oz - radius * radius
			if a < 1e-12 then
				if cc > 0 then tmin = math.huge end
			else
				local disc = b * b - 4 * a * cc
				if disc < 0 then
					tmin = math.huge
				else
					local root = math.sqrt(disc)
					local t1, t2 = (-b - root) / (2 * a), (-b + root) / (2 * a)
					if t1 > tmin then tmin = t1 end
					if t2 < tmax then tmax = t2 end
				end
			end
		else
			slab(oy, dy, q.hy)
			slab(oz, dz, q.hz)
		end
		if tmin <= tmax then best = tmin end
	end
	return best
end
local opaque = function(q) return q.opaque end
local solid = function(q) return q.solid end

-- Closed all round: from all over the inside, every look in every direction
-- ends on something you can't see through (so no sky shows), and every walk
-- or jump ends on a wall, floor or ceiling (so nobody gets out).
local directions = {}
for x = -1, 1 do for y = -1, 1 do for z = -1, 1 do
	if x ~= 0 or y ~= 0 or z ~= 0 then table.insert(directions, Vector3.new(x, y, z).Unit) end
end end end
for k = 0, 15 do
	local angle = (k + 0.5) / 16 * math.pi * 2
	table.insert(directions, Vector3.new(math.sin(angle), 0, math.cos(angle)))
end
local samples = {}
for _, x in { -18, 0, 18 } do
	for _, z in { 40, 70, 96, 130, 166, 205 } do
		for _, y in { 2, 18, 33 } do table.insert(samples, O + Vector3.new(x, y, z)) end
	end
end
for _, room in Lobby.ROOMS do
	for _, out in { 4, 25, 46 } do
		for _, along in { -22, 0, 22 } do
			for _, y in { 2, 15, 27 } do table.insert(samples, O + Vector3.new(room.side * (W + out), y, room.z + along)) end
		end
	end
end
for _, radius in { 18, 36 } do
	for k = 0, 7 do
		local angle = k / 8 * math.pi * 2 + 0.2
		for _, y in { 2, 20, 40 } do table.insert(samples, O + Vector3.new(math.sin(angle) * radius, y, math.cos(angle) * radius)) end
	end
end
local function show(v) return string.format("(%.1f, %.1f, %.1f)", v.X, v.Y, v.Z) end
local leaks, escapes = 0, 0
for _, point in samples do
	for _, direction in directions do
		if cast(point, direction, opaque, 500) == nil then
			leaks += 1
			if leaks <= 5 then print("sky seen from " .. show(point - O) .. " towards " .. show(direction)) end
		end
		if direction.Y >= 0 and cast(point, direction, solid, 500) == nil then
			escapes += 1
			if escapes <= 5 then print("way out from " .. show(point - O) .. " towards " .. show(direction)) end
		end
	end
end
check(leaks == 0, "no sky shows anywhere inside (" .. #samples * #directions .. " looks): " .. leaks)
check(escapes == 0, "nobody can walk or jump out: " .. escapes)
check(lights >= 30 and shadowed == 0, "lit by plenty of lights, none casting costly shadows: " .. lights)

-- Four rooms off the hallway, two each side; three portals join their games.
local rooms = 0
for _, object in instances do
	if object.Name == "Room" and object.Parent == built.model then rooms += 1 end
end
check(rooms == 4 and #Lobby.ROOMS == 4, "four rooms off the hallway")
local sides = { [-1] = 0, [1] = 0 }
for _, room in Lobby.ROOMS do sides[room.side] += 1 end
check(sides[-1] == 2 and sides[1] == 2, "two rooms on each side")
check(#built.portals == 3, "three portals, one per game")
local joined = {}
for _, portal in built.portals do
	local part, prompt = portal.part, portal.prompt
	joined[portal.place] = true
	check(part:GetAttribute("Game") == portal.place, "the portal knows its game")
	check(part.CanTouch and not part.CanCollide, "walk into the portal")
	check(prompt.ClassName == "ProximityPrompt" and prompt.Parent == part and prompt.HoldDuration == 0 and prompt.ActionText == "Join", "or press E at it")
	local room = nil
	for _, r in Lobby.ROOMS do if r.place == portal.place then room = r end end
	check(room ~= nil and prompt.ObjectText == room.name, "the prompt names the game")
	local offset = part.CFrame.Position - O
	check(math.abs(offset.X) > W + Lobby.ROOM_DEPTH - 6 and math.sign(offset.X) == room.side, "the portal is at the back of its room")
	check(part.CFrame.LookVector:Dot(Vector3.new(-room.side, 0, 0)) > 0.99, "the portal faces the hallway")
	-- A clear walk from the middle of the hallway to the portal.
	local from = O + Vector3.new(0, 3, room.z)
	local toward = Vector3.new(room.side, 0, 0)
	local reachPortal = cast(from, toward, function(q) return q.part == part end, 500)
	local blocked = cast(from, toward, solid, 500)
	check(reachPortal ~= nil and (blocked == nil or blocked > reachPortal), "a clear walk from the hallway into " .. room.name .. "'s portal")
end
check(joined.rough and joined.climb and joined.chalk, "Diamond in the Rough, Diamond Climb and Chalkboard Count each have a portal")
-- The Coming soon room is behind a closed gate.
for _, room in Lobby.ROOMS do
	if room.place == nil then
		local blocked = cast(O + Vector3.new(0, 3, room.z), Vector3.new(room.side, 0, 0), solid, 500)
		check(blocked ~= nil and blocked <= W + 2, "the Coming soon room is gated off")
	end
end
-- A drawn emblem over each door says which game it is.
local emblems = 0
for _, object in instances do
	if object.Name == "Emblem" and object:IsDescendantOf(built.model) then
		emblems += 1
		local gui = nil
		for _, child in instances do if child.Parent == object and child.ClassName == "SurfaceGui" then gui = child end end
		check(gui ~= nil, "the emblem is drawn")
		local offset = object.CFrame.Position - O
		check(object.CFrame.LookVector:Dot(Vector3.new(-math.sign(offset.X), 0, 0)) > 0.99, "the emblem faces the hallway")
	end
end
check(emblems == 4, "an emblem over every door")
check(counts.Chandelier == nil and (counts.ChandelierHeart or 0) >= 6, "chandeliers light the hallway and the throne room")
check(counts.Column == 16 and counts.Capital >= 16, "columns line the hallway")
check(counts.Dais == 3 and counts.Pedestal >= 1 and counts.Lamp == 4 and counts.Carpet == 1, "dais, pedestal, lamps and carpet")

-- The giant diamond floats over the pedestal, with its centre for the client spin.
local centre = built.diamond:GetAttribute("Centre")
check(built.diamond.Name == "LobbyDiamond" and built.diamond.Parent == built.model, "the giant diamond is the one the games menu spins")
check(centre ~= nil and (centre - (O + Vector3.new(0, Lobby.DIAMOND_HEIGHT, 0))).Magnitude < 1e-6, "the diamond's centre is recorded")
local facets = 0
for _, p in instances do
	if p.Name == "Facet" and p:IsDescendantOf(built.diamond) then
		facets += 1
		check(p.CanCollide == false and p.CanQuery == false, "the diamond does not block anyone")
		check((p.CFrame.Position - centre).Magnitude < Lobby.DIAMOND_SIZE, "facets are placed around the centre")
	end
end
check(facets == 64, "the diamond is a full brilliant cut")

local lobbyParts = #instances - before

-- The haystack skin's needle: a slim steel shaft, point, eye and red thread.
local needle = DiamondShape.facets(1, "needle")
local cylinders, thread, glint, farthest = 0, 0, 0, 0
for _, facet in needle do
	check(facet.shape ~= nil, "needle parts are blocks, cylinders and a ball, not facets")
	if facet.shape == "Cylinder" then cylinders += 1 end
	if facet.colour == Color3.fromRGB(214, 40, 52) then thread += 1 end
	if facet.material == "Material.Neon" then glint += 1 end
	farthest = math.max(farthest, facet.offset.Position.Magnitude)
	check(facet.size.Y <= 0.1 and facet.size.Z <= 0.1, "the needle is slim")
end
check(cylinders >= 6 and thread == 3 and glint == 1, "shaft, point, thread and glint")
check(farthest > 0.5 and farthest < 0.95, "the needle reaches across the gem's space: " .. farthest)
local heldNeedle = DiamondShape.build(2, "HeldDiamond", "needle")
check(#heldNeedle.parts == #needle and heldNeedle.parts[1].ClassName == "Part", "a held needle is built from the same parts")
check(heldNeedle.parts[1].Shape == "PartType.Cylinder", "the shaft is round")
-- A world gem switches between diamond and needle, keeping its visibility.
local root = Instance.new("Part")
root.Size = Vector3.new(0.68, 0.68, 0.68)
root.CFrame = CFrame.new(0, 10, 0)
root.Parent = workspace
DiamondShape.attach(root)
DiamondShape.visible(root, true)
local function shown()
	local list = root:FindFirstChild("Facets"):GetChildren()
	local visible = 0
	for _, face in list do if face:IsA("BasePart") and face.Transparency == 0 then visible += 1 end end
	return #list, visible
end
local count, visible = shown()
check(count == 64 and visible == 64, "the world diamond shows")
DiamondShape.setKind(root, "needle")
count, visible = shown()
check(root:GetAttribute("GemKind") == "needle" and count == #needle and visible == #needle, "it becomes a visible needle")
DiamondShape.resize(root, Vector3.new(2, 2, 2))
count = shown()
check(count == #needle, "a held needle stays a needle when it grows")
DiamondShape.setKind(root, "diamond")
count, visible = shown()
check(count == 64 and visible == 64, "and back to a diamond")

-- The How to Play board: beside the carpet, facing the spawn, opened by a
-- prompt (E) or a click, with a drawn face and no lettering.
local board = built.board
check(board ~= nil and board.Name == "HowToPlayBoard" and board.Parent == built.model, "a How to Play board stands in the lobby")
local boardFace, prompt, boardClick, drawn = nil, nil, nil, 0
for _, object in instances do
	if object.Name == "BoardFace" and object.Parent == board then boardFace = object end
end
check(boardFace ~= nil, "the board has a face")
for _, object in instances do
	if object.ClassName == "ProximityPrompt" and object.Parent == boardFace then prompt = object end
	if object.ClassName == "ClickDetector" and object.Parent == board then boardClick = object end
	if object.ClassName == "Frame" and object.Parent and object.Parent.Parent == boardFace then drawn += 1 end
end
check(prompt ~= nil and prompt.Name == "HowToPlay" and prompt.HoldDuration == 0 and prompt.ActionText == "How to play", "walking up to the board offers How to play")
check(boardClick ~= nil and boardClick.Name == "HowToPlayClick" and boardClick.MaxActivationDistance >= 20, "the board can be clicked from across the carpet")
check(drawn == 7, "the board's face is drawn: a gem and three list lines")
local facing = (Vector3.new(spawn.CFrame.Position.X, 0, spawn.CFrame.Position.Z) - Vector3.new(boardFace.CFrame.Position.X, 0, boardFace.CFrame.Position.Z)).Unit
check(boardFace.CFrame.LookVector:Dot(facing) > 0.99, "the board faces the spawn")
check(math.abs(boardFace.CFrame.Position.X - O.X) > 4.5, "the board stands clear of the carpet")

-- No lettered signs: their text renders badly, so the court carries none.
local lettered = 0
for _, object in instances do
	if object.ClassName == "TextLabel" and object:IsDescendantOf(built.model) then lettered += 1 end
end
check(lettered == 0 and counts.Crest == nil, "no lettered signs in the lobby")

-- The games menu's status line for Diamond in the Rough.
check(LobbyView.status("Digging", 123456) == "LIVE · 123,456 stone left", "live stone count")
check(LobbyView.status("Revealed", 9) == "LIVE · 9 stone left", "still live once the diamond shows")
check(LobbyView.status("Holding", 0) == "Someone is holding the diamond!", "holding")
check(LobbyView.status("Won", 0) == "Diamond found! A new round starts soon", "won")
check(LobbyView.status("Rebuilding", 0) == "The mountain is being rebuilt", "rebuilding")
-- The haystack skin says hay and needle instead.
check(LobbyView.status("Digging", 1200, "hay") == "LIVE · 1,200 hay left", "hay left")
check(LobbyView.status("Holding", 0, "hay") == "Someone is holding the needle!", "holding the needle")
check(LobbyView.status("Won", 0, "hay") == "Needle found! A new round starts soon", "needle found")
check(LobbyView.status("Rebuilding", 0, "hay") == "The haystack is being rebuilt", "haystack rebuilt")
check(LobbyView.status("Won", 0, "stone") == "Diamond found! A new round starts soon", "stone skin reads as before")

-- The Diamond Climb card's status line, and where a player is.
check(LobbyView.climbStatus(0, 0) == "Platform 0 of 1,000", "climb status at the start")
check(LobbyView.climbStatus(999, 1) == "Platform 999 of 1,000 · 1 climb", "climb status with a win")
check(LobbyView.climbStatus(57, 3) == "Platform 57 of 1,000 · 3 climbs", "climb status with wins")
local someone = newInstance("Player")
check(LobbyView.place(someone) == "lobby", "a new player is in the lobby")
someone:SetAttribute("InGame", true)
check(LobbyView.place(someone) == "rough", "InGame is Diamond in the Rough")
someone:SetAttribute("InClimb", true)
check(LobbyView.place(someone) == "climb", "InClimb is Diamond Climb, even mid-move")
someone:SetAttribute("InGame", false)
check(LobbyView.place(someone) == "climb", "climbing")
someone:SetAttribute("InChalk", true)
check(LobbyView.place(someone) == "chalk", "InChalk is Chalkboard Count, even mid-move")
someone:SetAttribute("InClimb", false)
check(LobbyView.place(someone) == "chalk", "writing on the board")
check(LobbyView.chalkStatus(0, 1000, 0) == "Count 0 of 1,000", "chalk status at the start")
check(LobbyView.chalkStatus(250, 1000, 1) == "Count 250 of 1,000 · 1 win", "chalk status with a win")
check(LobbyView.chalkStatus(12345, 100000, 4) == "Count 12,345 of 100,000 · 4 wins", "chalk status with wins")

-- The How to Play guide: connecting TikTok, testing without it, the controls
-- and how to win, in plain rich text with no emojis.
local titles = {}
for _, page in HowToPlay.PAGES do
	table.insert(titles, page.title)
	local plain = string.gsub(page.text, "</?b>", "")
	check(not string.find(plain, "[<>&]"), page.title .. ": rich text has no stray < > or &")
	check(not string.find(page.text, "[\240-\244]"), page.title .. ": no emojis")
end
check(table.concat(titles, "|") == "Connect TikTok|Testing|Controls|How to win|Diamond Climb|Chalkboard", "six guide pages")
local all = ""
for _, page in HowToPlay.PAGES do all ..= page.text .. "\n" end
for _, needed in { "1,000 platforms", "checkpoint", "Jump height", "DIAMOND CLIMB", "Shift+K", "focused", "A viewer sent", "portal", "sprint", "TEST GIFTS", "REBUILD TEST GIFTS", "Open gift settings", "Set key", "TikFinity", "<b>Y</b>", "<b>G</b>", "<b>P</b>", "<b>H</b>", "Diamond bird", "CHALKBOARD COUNT", "Hold to write", "60 second", "1,000 coins", "Test save" } do
	check(string.find(all, needed, 1, true) ~= nil, "the guide covers " .. needed)
end
check(HowToPlay.BOARD == "HowToPlay" and HowToPlay.KEY == Enum.KeyCode.H, "the board's prompt and H open the guide")
print(string.format("PASS: %d lobby checks (%d parts)", passed, lobbyParts))
'''

generated = root / "tests/lobby.generated.luau"
try:
    mock = (root / "tests/roblox-mock.luau").read_text(encoding="utf-8")
    body = (
        mock
        + "\nlocal DiamondShape = " + module("src/shared/DiamondShape.luau")
        + "\nlocal Lobby = " + module("src/server/Lobby.luau")
        + "\nlocal LobbyView = " + module("src/client/LobbyView.luau")
        + "\nlocal HowToPlay = " + module("src/client/HowToPlay.luau")
        + "\n" + test
    )
    generated.write_text(body, encoding="utf-8")
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(generated)], check=True)
finally:
    generated.unlink(missing_ok=True)
