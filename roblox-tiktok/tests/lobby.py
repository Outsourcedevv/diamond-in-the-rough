"""Checks the royal lobby under the Luau CLI with a Roblox stand-in: where it
floats, the spawn, the court's columns, banners, dais and diamond, the
walls that stop players falling off, and the games menu's status line.

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
-- so the floating court never shades the game, and high above the ground.
check(flat.Magnitude > 2000 and O.Y > 150, "the lobby floats far from the mountain valley")

-- The spawn stands on the court, near side, facing the dais.
local spawn = built.spawn
check(spawn.ClassName == "SpawnLocation" and spawn.Neutral and spawn.Duration == 0 and spawn.Anchored, "a neutral spawn with no force field")
check(math.abs(spawn.CFrame.Position.Y - (O.Y + 0.5)) < 1e-6, "the spawn sits on the floor")
local toCentre = (Vector3.new(O.X, 0, O.Z) - Vector3.new(spawn.CFrame.Position.X, 0, spawn.CFrame.Position.Z)).Unit
check(spawn.CFrame.LookVector:Dot(toCentre) > 0.999, "players arrive facing the dais")

local counts, walls, floor = {}, 0, nil
local banners = 0
for i = before + 1, #instances do
	local p = instances[i]
	if p.ClassName == "Part" or p.ClassName == "SpawnLocation" then
		counts[p.Name] = (counts[p.Name] or 0) + 1
		check(p.Anchored, p.Name .. " is anchored")
		local offset = Vector3.new(p.CFrame.Position.X, 0, p.CFrame.Position.Z) - flat
		check(offset.Magnitude < 64, p.Name .. " stays on the court")
		if p.Name == "Floor" then floor = p end
		if p.Name == "EdgeWall" then
			walls += 1
			check(p.CanCollide and p.Transparency == 1 and p.Size.Y >= 12, "the invisible edge wall is solid and taller than a jump")
			check(offset.Magnitude > 60, "the edge wall stands outside the balustrade")
		end
		if p.Name == "Banner" then
			banners += 1
			local gui = nil
			for _, child in instances do if child.Parent == p and child.ClassName == "SurfaceGui" then gui = child end end
			check(gui ~= nil and gui.Face == "NormalId.Front", "banners carry the crown emblem")
			check(p.CFrame.LookVector:Dot(Vector3.new(-offset.X, 0, -offset.Z).Unit) > 0.99, "banners face into the court")
		end
	end
end
check(floor ~= nil and floor.CanCollide and floor.Shape == "PartType.Cylinder" and floor.Size.Y >= 120, "a solid round marble floor")
check(floor.Material == "Material.Marble", "the floor is white marble")
check(counts.Column == 16 and counts.Capital == 16 and counts.Entablature == 16, "a full ring of sixteen columns")
check(banners == 8 and walls == 32 and counts.Baluster == 64 and counts.Rail == 32, "banners, balustrade and edge walls all round")
check(counts.Dais == 3 and counts.Pedestal == 1 and counts.Lamp == 4 and counts.Carpet == 1, "dais, pedestal, lamps and carpet")

-- The giant diamond floats over the pedestal, with its centre for the client spin.
local centre = built.diamond:GetAttribute("Centre")
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
for _, needed in { "1,000 platforms", "checkpoint", "Jump height", "DIAMOND CLIMB", "Start Bridge.bat", "localhost:8787", "Allow HTTP Requests", "JOIN", "TEST GIFTS", "REBUILD TEST GIFTS", "GIFT KEYBINDS", "<b>Y</b>", "<b>G</b>", "<b>P</b>", "<b>H</b>", "Diamond bird", "CHALKBOARD COUNT", "Hold to write", "60 second", "1,000 coins", "Test save" } do
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
