"""Checks Chalkboard Count under the Luau CLI with a Roblox stand-in: the
board's geometry (every chalk digit inside its box, the biggest count and the
writer inside the board, the camera in front of it), how far gifts move the
count, which gifts start and save the reset, the saved count's clean-up, the
classroom the server builds (no lettered signs, themes recolour it and swap
its decorations), the display helpers, and the game itself on a simulated
clock: holding to write at the chosen speed, gifts up and down, the reset
countdown wiping the board, a save gift stopping it, the goal's win and the
streamer panel's settings.

    python3 tests/chalk.py [path/to/luau]
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

board_test = r'''
local passed = 0
local function check(condition: boolean, message: string)
	if not condition then error("FAIL " .. message, 2) end
	passed += 1
end

-- Every digit's strokes stay inside its box.
for d = 0, 9 do
	local strokes = ChalkBoard.DIGITS[d]
	check(strokes ~= nil and #strokes >= 1, "digit " .. d .. " has strokes")
	for _, stroke in strokes do
		check(#stroke >= 2, "digit " .. d .. ": every stroke is a line")
		for _, p in stroke do
			check(p.X >= -0.06 and p.X <= 1.06 and p.Y >= -0.06 and p.Y <= 1.06,
				string.format("digit %d stays in its box (%.2f, %.2f)", d, p.X, p.Y))
		end
	end
end

-- No stroke has zero length (a chalk part needs a direction).
for d = 0, 9 do
	for _, segment in ChalkBoard.segments(d, 0, 0, ChalkBoard.NUMBER_HEIGHT) do
		check((segment[2] - segment[1]).Magnitude > 1e-3, "digit " .. d .. " has no zero-length stroke")
	end
end

-- The biggest count fits on the board, above the writer's head.
local halfWidth = ChalkBoard.BOARD_WIDTH / 2
local lefts = ChalkBoard.digitLefts(ChalkBoard.MAX_DIGITS)
check(#lefts == ChalkBoard.MAX_DIGITS, "a slot for each digit")
check(lefts[1] > -halfWidth + 1, "the first of seven digits is on the board")
check(lefts[#lefts] + ChalkBoard.DIGIT_WIDTH < halfWidth - 1, "the last of seven digits is on the board")
check(math.abs(lefts[1] + lefts[#lefts] + ChalkBoard.DIGIT_WIDTH) < 1e-6, "the number is centred")
local bottom = ChalkBoard.NUMBER_Y - ChalkBoard.NUMBER_HEIGHT / 2
check(bottom > ChalkBoard.BOARD_BOTTOM + 1 and bottom + ChalkBoard.NUMBER_HEIGHT < ChalkBoard.BOARD_BOTTOM + ChalkBoard.BOARD_HEIGHT - 0.5, "the number fits the board's height")
for _, segment in ChalkBoard.segments(8, lefts[1], bottom, ChalkBoard.NUMBER_HEIGHT) do
	for _, p in segment do
		check(math.abs(p.Z - (ChalkBoard.face() + 0.06)) < 1e-6, "chalk sits just in front of the board")
		check(p.X >= ChalkBoard.ORIGIN.X - halfWidth and p.Y <= ChalkBoard.ORIGIN.Y + ChalkBoard.BOARD_BOTTOM + ChalkBoard.BOARD_HEIGHT, "chalk is on the board")
	end
end
check(table.concat(ChalkBoard.digits(1234), "") == "1234" and table.concat(ChalkBoard.digits(0), "") == "0" and table.concat(ChalkBoard.digits(-5), "") == "0", "the digits of a count")
check(#tostring(ChalkBoard.GOAL.max) <= ChalkBoard.MAX_DIGITS, "the highest goal fits in seven digits")
check(ChalkBoard.GOAL.max == 5000000, "goals go up to 5 million")
check(ChalkBoard.SPEED.max == 20 * ChalkBoard.GOAL.max / 1000, "the top speed is the old 20 a second scaled to 5 million")
-- The speed slider: even steps from 1 to 100,000 a second.
check(ChalkBoard.speedAt(0) == ChalkBoard.SPEED.min and ChalkBoard.speedAt(1) == ChalkBoard.SPEED.max, "the slider's ends")
local lastSpeed = 0
for i = 0, 50 do
	local v = ChalkBoard.speedAt(i / 50)
	check(v >= lastSpeed, "the slider only goes up")
	lastSpeed = v
end
check(math.abs(ChalkBoard.speedFraction(ChalkBoard.speedAt(0.6)) - 0.6) < 0.02, "slider positions round-trip")
check(ChalkBoard.speedAt(0.5) > 100 and ChalkBoard.speedAt(0.5) < 1000, "halfway is a few hundred a second")
-- The bigger writer stands on the floor at the board and steps along it.
check(ChalkBoard.WRITER_SCALE > 1.5, "the writer is drawn bigger")
local stand = ChalkBoard.standFrame()
check(math.abs(stand.Position.Y - ChalkBoard.ORIGIN.Y - 3 * ChalkBoard.WRITER_SCALE) < 1e-6 and stand.Position.Z > ChalkBoard.face(), "standing on the floor in front of the board")
check(ChalkBoard.writerX(0) < 0 and ChalkBoard.writerX(-100) >= -halfWidth and ChalkBoard.writerX(100) <= halfWidth, "the writer steps along the board, never off it")

-- The writer stands at the board facing it; the camera is in front, looking at it.
local stand = ChalkBoard.standFrame()
check(stand.Position.Z > ChalkBoard.face() and stand.Position.Z - ChalkBoard.face() < 4, "the writer stands at the board")
check(stand.LookVector.Z < -0.99, "the writer faces the board")
local cam = ChalkBoard.cameraFrame()
check(cam.Position.Z - ChalkBoard.face() > 15, "the camera films from across the room")
check(cam.LookVector.Z < -0.8, "the camera looks at the board")

-- Gifts: up for breaking gifts, down for adding ones.
check(ChalkBoard.giftAmount(5, 1, 1) == 2 and ChalkBoard.giftAmount(5, 100, 1) == 20 and ChalkBoard.giftAmount(5, 1000, 1) == 63 and ChalkBoard.giftAmount(5, 10000, 1) == 200, "numbers per gift")
check(ChalkBoard.giftAmount(-5, 100, 1) == -20 and ChalkBoard.giftAmount(0, 100, 1) == 0, "adding gifts rub numbers off; gifts that do nothing do nothing")
check(ChalkBoard.giftAmount(5, 1, 3) == 6 and ChalkBoard.giftAmount(5, 100, 1, 2) == 40 and ChalkBoard.giftAmount(5, 1, 1, 0.5) == 1, "combos and strength")
check(ChalkBoard.isResetGift("galaxy", "Galaxy") and ChalkBoard.isResetGift("Galaxy", "Galaxy"), "the Galaxy starts the reset, any case")
check(not ChalkBoard.isResetGift("Rose", "Galaxy") and not ChalkBoard.isResetGift(nil, "Galaxy") and not ChalkBoard.isResetGift("Galaxy", ""), "other gifts do not")
check(ChalkBoard.isSaveGift("Lion", 29999, "Galaxy", 1000) and ChalkBoard.isSaveGift("Money Gun", 1000, "Galaxy", 1000), "a different gift of 1,000+ coins saves the board")
check(not ChalkBoard.isSaveGift("Galaxy", 1000, "Galaxy", 1000) and not ChalkBoard.isSaveGift("Rose", 1, "Galaxy", 1000) and not ChalkBoard.isSaveGift("Hat", 999, "Galaxy", 1000), "the Galaxy itself and small gifts do not")

-- Themes.
check(#ChalkBoard.THEME_ORDER == 5, "five themes")
for _, name in ChalkBoard.THEME_ORDER do
	local theme = ChalkBoard.THEMES[name]
	check(theme ~= nil and type(theme.name) == "string" and not string.find(theme.name, "[\240-\244]"), name .. " has a plain name")
	for _, key in { "board", "boardMaterial", "frame", "frameMaterial", "wall", "trim", "floor", "floorMaterial", "chalk", "glow", "light" } do
		check(theme[key] ~= nil, name .. " sets " .. key)
	end
end
check(ChalkBoard.THEMES.classic.board.G > ChalkBoard.THEMES.classic.board.R and ChalkBoard.THEMES.classic.board.G > ChalkBoard.THEMES.classic.board.B, "the classic board is green")
check(ChalkBoard.theme("nope") == ChalkBoard.THEMES.classic and ChalkBoard.theme(nil) == ChalkBoard.THEMES.classic, "an unknown theme is classic")

-- A saved count is cleaned up.
local clean = ChalkGame.clean({ count = 5000, goal = 4000, wins = -2, speed = 1e9, theme = "x", strength = 3, resetSeconds = 2, saveCoins = 0 })
check(clean.goal == 4000 and clean.count == 0 and clean.wins == 0 and clean.speed == ChalkBoard.SPEED.max and clean.theme == "classic"
	and clean.strength == 1 and clean.resetSeconds == ChalkBoard.RESET_SECONDS.min and clean.saveCoins == 1, "out of range saves are put right (a count saved at the goal starts again)")
local kept = ChalkGame.clean({ count = 321.7, goal = 500, wins = 2, best = 400, speed = 4.5, theme = "neon", strength = 2, resetGift = "Lion", resetSeconds = 90, saveCoins = 5000 })
check(kept.count == 321 and kept.goal == 500 and kept.wins == 2 and kept.best == 400 and kept.speed == 4.5 and kept.theme == "neon"
	and kept.strength == 2 and kept.resetGift == "Lion" and kept.resetSeconds == 90 and kept.saveCoins == 5000, "a good save is kept")
local fresh = ChalkGame.clean(nil)
check(fresh.count == 0 and fresh.goal == 1000 and fresh.speed == 3 and fresh.resetGift == "Galaxy" and fresh.saveCoins == 1000 and fresh.resetSeconds == 60, "no save starts fresh with the defaults")

-- The display.
check(ChalkView.countText(123, 1000) == "123 / 1,000", "count text")
check(ChalkView.resetText(60) == "RESET IN 1:00" and ChalkView.resetText(9.2) == "RESET IN 0:10" and ChalkView.resetText(-3) == "RESET IN 0:00", "countdown text")
check(ChalkView.saveText(1000) == "Send a gift of 1,000+ coins to save the board", "save text")
check(ChalkView.writeSeconds(1) > ChalkView.writeSeconds(10) and ChalkView.writeSeconds(20) >= 0.04, "faster writing draws each number faster")
check(ChalkView.speedText(3) == "3 a second" and ChalkView.speedText(1.5) == "1.5 a second" and ChalkView.speedText(12000) == "12,000 a second", "speed text")

-- The classroom.
local parent = newInstance("Workspace")
local store = newInstance("Folder")
local built = Classroom.build(parent, store, "classic")
local lettered, lights, boards = 0, 0, {}
for _, object in instances do
	if object:IsDescendantOf(built.model) or object:IsDescendantOf(store) then
		if object.ClassName == "TextLabel" or object.ClassName == "SurfaceGui" or object.ClassName == "BillboardGui" then lettered += 1 end
		if object.ClassName == "PointLight" or object.ClassName == "SpotLight" then lights += 1 end
		if object.ClassName == "Part" and object:GetAttribute("Role") == "Board" then table.insert(boards, object) end
	end
end
check(lettered == 0, "no lettered signs in the classroom")
check(lights <= 6, "the classroom keeps to a few lights: " .. lights)
check(#boards == 1 and boards[1].Name == "Board", "one chalkboard")
local board = boards[1]
check(board.Color == ChalkBoard.THEMES.classic.board, "the board starts green")
check(math.abs(board.CFrame.Position.Z + board.Size.Z / 2 - ChalkBoard.face()) < 1e-6, "the board's front is where the chalk goes")
check(built.spawn.Name == "ChalkStart" and built.spawn.Enabled == false, "the classroom's respawn point is never a random spawn")
for _, name in { "royal", "sakura", "neon" } do
	check(built.decor[name] ~= nil and built.decor[name].Parent == store, name .. " decorations wait in storage")
end
Classroom.setTheme(built, "royal")
check(built.theme == "royal" and built.decor.royal.Parent == built.model and built.decor.neon.Parent == store, "the royal theme brings out its decorations")
check(board.Color == ChalkBoard.THEMES.royal.board, "the royal theme recolours the board")
local lampColoured = false
for _, object in built.model:GetDescendants() do
	if object.ClassName == "PointLight" and object.Name == "LampLight" then lampColoured = object.Color == ChalkBoard.THEMES.royal.light end
end
check(lampColoured, "the lamps take the theme's light")
Classroom.setTheme(built, "nope")
check(built.theme == "classic" and built.decor.royal.Parent == store and board.Color == ChalkBoard.THEMES.classic.board, "an unknown theme goes back to classic")
print(string.format("PASS: %d chalkboard checks", passed))
'''

mock_extras = r'''
typeof = function(value)
	if type(value) == "table" and getmetatable(value) == vector then return "Vector3" end
	return type(value)
end
ColorSequenceKeypoint = { new = function(...) return { ... } end }
'''

run("chalk", mock + mock_extras + modules(
    "src/shared/GiftTier.luau", "src/shared/Format.luau", "src/shared/DiamondShape.luau",
    "src/shared/ChalkBoard.luau", "src/shared/Config.luau", "src/shared/HoldTimer.luau", "src/server/Classroom.luau",
    "src/server/ChalkGame.luau", "src/client/Sounds.luau", "src/client/HoldCountdown.luau", "src/client/ChalkEffects.luau",
    "src/client/ChalkView.luau") + "\n" + board_test)

# The game on a simulated clock: Heartbeat and task.delay run on it.
game_harness = r'''
local clock = 0
local timers = {}
local heartbeat: ((number) -> ())? = nil
local task = {
	wait = function() end,
	defer = function(f, ...) f(...) end,
	spawn = function() end, -- the save loop never runs here; saves are counted instead
	delay = function(seconds: number, f, ...)
		table.insert(timers, { at = clock + seconds, f = f, args = { ... } })
	end,
}
local RunService = { Heartbeat = { Connect = function(_, f) heartbeat = f; return connection end } }
local players = {}
local Players = { GetPlayers = function() return players end }
local StarterPlayer = { CharacterUseJumpPower = false, CharacterWalkSpeed = 16, CharacterJumpHeight = 7.2, CharacterJumpPower = 50 }
local ServerStorage = newInstance("Folder")
local game = { GetService = function(_, name)
	if name == "RunService" then return RunService end
	if name == "Players" then return Players end
	if name == "StarterPlayer" then return StarterPlayer end
	if name == "ServerStorage" then return ServerStorage end
	return { WaitForChild = function() return Shared end }
end }
local workspace = newInstance("Workspace")
workspace.GetServerTimeNow = function() return clock end
workspace.BulkMoveTo = function() end
workspace.Raycast = function() return nil end
local function advance(seconds: number)
	local steps = math.floor(seconds * 10 + 0.5)
	for _ = 1, steps do
		clock += 0.1
		if heartbeat then heartbeat(0.1) end
		local due = {}
		for i = #timers, 1, -1 do
			if timers[i].at <= clock + 1e-9 then table.insert(due, table.remove(timers, i)) end
		end
		table.sort(due, function(a, b) return a.at < b.at end)
		for _, timer in due do timer.f(table.unpack(timer.args)) end
	end
end
'''

game_test = r'''
local passed = 0
local function check(condition: boolean, message: string)
	if not condition then error("FAIL " .. message, 2) end
	passed += 1
end
local events = {}
local notify = { FireAllClients = function(_, kind, data) table.insert(events, { kind = kind, data = data }) end }
local function last(kind: string): any
	for i = #events, 1, -1 do
		if events[i].kind == kind then return events[i].data end
	end
	return nil
end
local function countOf(kind: string): number
	local n = 0
	for _, e in events do if e.kind == kind then n += 1 end end
	return n
end
local saves = 0
local settings = {}
local state = newInstance("Folder")
local chalk = ChalkGame.start({
	settings = settings,
	save = function() saves += 1 end,
	state = state,
	notify = notify,
	parent = workspace,
})
check(settings.chalk == chalk.progress, "the count lives in the saved settings")
check(state:GetAttribute("ChalkCount") == 0 and state:GetAttribute("ChalkGoal") == 1000 and state:GetAttribute("ChalkSpeed") == 3
	and state:GetAttribute("ChalkResetGift") == "Galaxy" and state:GetAttribute("ChalkSaveCoins") == 1000 and state:GetAttribute("ChalkResetEnds") == 0, "the board is shown to every player")
check(chalk.writer() == nil, "nobody writes at first")

-- The streamer joins the board and is held still in front of it.
local streamer = newInstance("Player")
streamer.Name, streamer.DisplayName, streamer.Parent = "Niamh", "Niamh", Players
table.insert(players, streamer)
local character = newInstance("Model")
-- Models scale (ScaleTo) and move (PivotTo) like Roblox's.
local characterScale = 1
character.GetScale = function() return characterScale end
character.ScaleTo = function(_, value) characterScale = value end
character.PivotTo = function(self, frame) self.pivot = frame end
streamer.Character = character
local humanoid = newInstance("Humanoid")
humanoid.Parent = character
humanoid.WalkSpeed = 16
streamer:SetAttribute("InChalk", true)
chalk.entered(streamer, true)
check(chalk.writer() == streamer, "the streamer is the writer")
check(humanoid.WalkSpeed == 0 and humanoid.JumpHeight == 0, "the writer stands still at the board")
check(characterScale == ChalkBoard.WRITER_SCALE, "the writer is drawn bigger at the board")
check(humanoid.AutoRotate == false, "the movement keys can't turn the writer away from the board")

-- Holding writes three numbers a second; letting go stops.
chalk.hold(streamer, true)
advance(2)
check(chalk.progress.count == 6, "two seconds of holding writes six numbers: " .. chalk.progress.count)
check(state:GetAttribute("ChalkWriting") == true and state:GetAttribute("ChalkCount") == 6, "everyone sees the writing")
chalk.hold(streamer, false)
advance(1)
check(chalk.progress.count == 6 and state:GetAttribute("ChalkWriting") == false, "letting go stops the writing")
chalk.hold(streamer, "yes")
advance(1)
check(chalk.progress.count == 6, "only true or false holds")
check(chalk.setting(streamer, "setChalkSpeed", 7.3) and chalk.progress.speed == 7.5 and state:GetAttribute("ChalkSpeed") == 7.5, "the writing speed in half steps")
local wait = os.clock()
while os.clock() - wait < 0.06 do end
chalk.hold(streamer, true)
advance(2)
check(chalk.progress.count == 21, "faster writing: " .. chalk.progress.count)
chalk.hold(streamer, false)
advance(0.1)
check(chalk.setting(streamer, "setChalkSpeed", 1e9) and chalk.progress.speed == ChalkBoard.SPEED.max, "the speed has a top")
chalk.setting(streamer, "setChalkSpeed", 3)

-- Gifts move the count up and down.
check(chalk.gift("Ann", { type = "gift", gift = "Rose", coins = 1 }, 100, false) == "  +2" and chalk.progress.count == 23, "a Rose writes two numbers")
local up = last("chalkGift")
check(up.up and up.from == 21 and up.to == 23 and up.amount == 2 and up.name == "Ann" and up.gift == "Rose", "the gift show knows what happened")
check(chalk.gift("Bo", { type = "gift", gift = "Perfume", coins = 100 }, -500, false) == "  -20" and chalk.progress.count == 3, "an adding gift rubs out twenty")
chalk.gift("Bo", { type = "gift", gift = "Perfume", coins = 100 }, -500, false)
check(chalk.progress.count == 0, "the count never goes below zero")
chalk.gift("Cy", { type = "follow" }, 10, false)
chalk.gift("Cy", { type = "share" }, 10, false)
check(chalk.progress.count == 2 and last("chalkGift").gift == "Share", "follows and shares write one each")
chalk.gift("Di", { type = "gift", gift = "Rose", coins = 1, count = 5 }, 100, true)
check(chalk.progress.count == 12 and last("chalkGift").doubled == true, "a combo counts each gift")

-- The Galaxy starts the reset countdown; it does not stack or count.
check(chalk.gift("Eve", { type = "gift", gift = "Galaxy", coins = 1000 }, 1000, false) == "  RESET IN 60", "a Galaxy starts the reset")
check(chalk.progress.count == 12 and math.abs(state:GetAttribute("ChalkResetEnds") - (clock + 60)) < 1e-6, "the countdown is shown and the Galaxy writes nothing")
local started = last("chalkReset")
check(started.state == "started" and started.name == "Eve" and started.seconds == 60 and started.saveCoins == 1000, "everyone hears the reset start")
advance(20)
check(chalk.gift("Fay", { type = "gift", gift = "galaxy", coins = 1000 }, 1000, false) == "  (reset already counting down)", "a second Galaxy does not stack")
-- A different 1,000 coin gift saves it (and still counts).
check(chalk.gift("Gus", { type = "gift", gift = "Lion", coins = 29999 }, 1, false) == "  +346  SAVED THE BOARD", "a big gift saves the board")
check(state:GetAttribute("ChalkResetEnds") == 0 and last("chalkReset").state == "saved" and last("chalkReset").name == "Gus", "the countdown stops")
advance(45)
check(chalk.progress.count == 358 and countOf("chalkWipe") == 0, "the saved board is not wiped")

-- Small gifts do not save it; when the countdown runs out the board is wiped.
chalk.gift("Eve", { type = "gift", gift = "Galaxy", coins = 1000 }, 1000, false)
chalk.gift("Hal", { type = "gift", gift = "Rose", coins = 1, count = 3 }, 100, false)
check(state:GetAttribute("ChalkResetEnds") > 0, "three Roses do not save it")
advance(59.5)
check(chalk.progress.count == 364, "not wiped before the countdown ends")
advance(0.6)
check(chalk.progress.count == 0 and state:GetAttribute("ChalkResetEnds") == 0, "the reset wipes the board")
check(last("chalkReset").state == "wiped" and last("chalkReset").lost == 364 and last("chalkWipe").reason == "reset", "everyone sees the wipe")
check(chalk.progress.best == 364, "the best count is kept")

-- Reaching the goal wins, then the board is wiped for the next count.
check(chalk.setting(streamer, "setChalkGoal", 5) and chalk.progress.goal == 10, "the goal has a floor")
check(chalk.setting(streamer, "setChalkGoal", 50) and state:GetAttribute("ChalkGoal") == 50, "the goal can be changed")
chalk.gift("Eve", { type = "gift", gift = "Galaxy", coins = 1000 }, 1000, false)
chalk.gift("Ivy", { type = "gift", gift = "Universe", coins = 34999 }, 1, false)
check(chalk.progress.count == 50 and chalk.progress.wins == 0 and state:GetAttribute("ChalkHoldStart") == clock, "reaching the goal starts the hold")
chalk.hold(streamer, true)
advance(0.5)
check(chalk.progress.count == 50 and state:GetAttribute("ChalkWriting") == false, "nothing more to write at the goal: the arm rests")
chalk.hold(streamer, false)
check(chalk.gift("Bo", { type = "gift", gift = "Perfume", coins = 100 }, -500, false) == "  -20" and chalk.progress.count == 30, "a gift down during the hold")
check(state:GetAttribute("ChalkHoldStart") == 0, "ends the hold")
advance(Config.HoldSeconds)
check(chalk.progress.wins == 0, "a lost hold does not win")
chalk.gift("Ivy", { type = "gift", gift = "Universe", coins = 34999 }, 1, false)
check(chalk.progress.count == 50 and state:GetAttribute("ChalkHoldStart") == clock, "back at the goal, the hold starts again")
advance(Config.HoldSeconds - 0.5)
check(chalk.progress.wins == 0, "not won before the hold is over")
advance(0.6)
check(chalk.progress.count == 50 and chalk.progress.wins == 1 and state:GetAttribute("ChalkWins") == 1 and state:GetAttribute("ChalkHoldStart") == 0, "holding the goal for the whole hold wins")
check(last("chalkWin").wins == 1 and last("chalkWin").goal == 50 and last("chalkWin").name == "Niamh", "the win is celebrated")
check(chalk.gift("Bo", { type = "gift", gift = "Perfume", coins = 100 }, -500, false) == "" and chalk.progress.count == 50, "gifts wait during the celebration")
chalk.hold(streamer, true)
advance(0.5)
check(chalk.progress.count == 50 and state:GetAttribute("ChalkWriting") == false, "the arm rests during the celebration")
chalk.hold(streamer, false)
advance(ChalkGame.WIN_SECONDS + 0.1)
check(chalk.progress.count == 0 and last("chalkWipe").reason == "win", "the board is wiped for the next count")
advance(70)
check(last("chalkWipe").reason == "win" and countOf("chalkReset") == 6, "the countdown stayed stopped (the winning gift saved it)")
chalk.setting(streamer, "setChalkGoal", 1000)

-- The streamer panel's settings.
check(chalk.setting(streamer, "setChalkTheme", "sakura") and chalk.built.theme == "sakura" and state:GetAttribute("ChalkTheme") == "sakura", "the theme changes the classroom")
check(not chalk.setting(streamer, "setChalkTheme", "nope") and chalk.progress.theme == "sakura", "an unknown theme is ignored")
check(chalk.setting(streamer, "setChalkResetGift", "  Lion  ") and chalk.progress.resetGift == "Lion", "the reset gift can be changed")
check(chalk.gift("Eve", { type = "gift", gift = "Galaxy", coins = 1000 }, 1000, false) == "  +63" and state:GetAttribute("ChalkResetEnds") == 0, "then a Galaxy just writes")
check(chalk.setting(streamer, "setChalkResetSeconds", 1000) and chalk.progress.resetSeconds == ChalkBoard.RESET_SECONDS.max, "the countdown has a top")
check(chalk.setting(streamer, "setChalkResetSeconds", 30) and chalk.setting(streamer, "setChalkSaveCoins", 5000) and chalk.progress.saveCoins == 5000, "countdown and save coins")
check(chalk.setting(streamer, "setChalkStrength", 2) and chalk.progress.strength == 2 and not chalk.setting(streamer, "setChalkStrength", 3), "strength is half, normal or double")
local before = chalk.progress.count
chalk.gift("Ann", { type = "gift", gift = "Rose", coins = 1 }, 100, false)
check(chalk.progress.count == before + 4, "double strength doubles the numbers")
chalk.gift("Cy", { type = "gift", gift = "Rose", coins = 1, count = 2 }, 100, false, -3)
check(chalk.progress.count == before - 2, "the streamer's own rule for a gift wins over its coins (and the strength), per gift")
check(chalk.setting(streamer, "chalkTestReset", nil) and state:GetAttribute("ChalkResetEnds") > 0 and last("chalkReset").seconds == 30, "Test reset starts the countdown")
chalk.gift("Bea", { type = "gift", gift = "Money Gun", coins = 1000 }, 1, false)
check(state:GetAttribute("ChalkResetEnds") > 0, "1,000 coins no longer saves it at 5,000")
check(chalk.setting(streamer, "chalkTestSave", nil) and state:GetAttribute("ChalkResetEnds") == 0, "Test save saves it")
check(chalk.setting(streamer, "chalkRestart", nil) and chalk.progress.count == 0 and last("chalkWipe").reason == "restart", "Restart wipes the board")
-- Gift settings: a reset gift wipes the board at once, and gifts can give or take wins.
chalk.gift("Viewer", { type = "gift", gift = "Rose", coins = 1, count = 3, id = "reset-1" }, 3, false)
local before = chalk.progress.count
check(before > 0, "a gift counts up before the reset")
check(chalk.resetNow() == before and chalk.progress.count == 0 and last("chalkWipe").reason == "reset", "a reset gift wipes the board straight away")
check(chalk.resetNow() == 0 and chalk.progress.count == 0, "resetting an empty board is fine")
local wins = chalk.progress.wins
check(chalk.addWins(2) == wins + 2 and state:GetAttribute("ChalkWins") == wins + 2, "a gift can add wins")
check(chalk.addWins(-9999) == 0, "wins never go below 0")
check(not chalk.setting(streamer, "setPerCoin", 5), "other settings are left to the game")
check(saves > 0, "settings are saved")

-- Very fast writing really is that fast (no cap per frame).
chalk.setting(streamer, "setChalkGoal", 5000000)
chalk.setting(streamer, "setChalkSpeed", 50000)
local from = chalk.progress.count
chalk.hold(streamer, true)
advance(1)
chalk.hold(streamer, false)
advance(0.1)
check(chalk.progress.count - from > 40000, "50,000 a second writes tens of thousands: " .. (chalk.progress.count - from))
chalk.setting(streamer, "setChalkSpeed", 3)
chalk.setting(streamer, "chalkRestart", nil)
chalk.setting(streamer, "setChalkGoal", 1000)

-- Leaving the board gives back Roblox's usual movement.
chalk.hold(streamer, true)
streamer:SetAttribute("InChalk", false)
chalk.entered(streamer, false)
advance(1)
check(humanoid.WalkSpeed == 16 and humanoid.JumpHeight == 7.2 and humanoid.AutoRotate == true, "walking again after leaving")
check(characterScale == 1, "and their usual size again")
check(chalk.progress.count == 0 and state:GetAttribute("ChalkWriting") == false and chalk.writer() == nil, "nobody writes after leaving")
chalk.removing(streamer)
print(string.format("PASS: %d chalkboard game checks", passed))
'''

run("chalk-game", mock + mock_extras + game_harness + modules(
    "src/shared/GiftTier.luau", "src/shared/Format.luau", "src/shared/DiamondShape.luau",
    "src/shared/ChalkBoard.luau", "src/shared/Config.luau", "src/server/Classroom.luau", "src/server/ChalkGame.luau") + "\n" + game_test)

# The client view on a simulated clock: it films the board, draws the count,
# plays every show and tidies up after leaving, without errors.
client_harness = r'''
local clock = 0
local scheduled = {}
local function schedule(delay: number, run: () -> ())
	table.insert(scheduled, { at = clock + math.max(0, delay), run = run })
end
local task = {
	wait = function() end,
	defer = function(f, ...) f(...) end,
	spawn = function(f, ...) f(...) end,
	delay = function(delay, f, ...)
		local args = { ... }
		schedule(delay, function() f(table.unpack(args)) end)
	end,
}
local os = setmetatable({ clock = function() return clock end }, { __index = os })
local function signal()
	local callbacks = {}
	return {
		Connect = function(_, f)
			local handle = {}
			handle.Disconnect = function() callbacks[handle] = nil end
			callbacks[handle] = f
			return handle
		end,
		Fire = function(_, ...)
			for _, f in callbacks do f(...) end
		end,
	}
end
local renderStepped = signal()
local bound = {}
local RunService = {
	RenderStepped = renderStepped,
	Heartbeat = signal(),
	BindToRenderStep = function(_, name, _priority, callback) bound[name] = callback end,
	UnbindFromRenderStep = function(_, name) bound[name] = nil end,
}
local TweenService = { Create = function(_, object, info, goal)
	return { Play = function() schedule(info.Time, function() for key, value in goal do object[key] = value end end) end, Cancel = function() end }
end }
local TweenInfo = { new = function(time) return { Time = time or 1 } end }
local Debris = { AddItem = function(_, object, seconds) schedule(seconds, function() object:Destroy() end) end }
local UserInputService = {
	InputBegan = signal(), InputEnded = signal(), InputChanged = signal(), WindowFocusReleased = signal(),
	GetFocusedTextBox = function() return nil end,
}
local actions = {}
local ContextActionService = {
	BindActionAtPriority = function(_, name, callback) actions[name] = callback end,
	UnbindAction = function(_, name) actions[name] = nil end,
}
local makeInstance = newInstance
local attributeSignals = {}
newInstance = function(className: string): any
	local object = makeInstance(className)
	for _, name in { "Activated", "InputBegan", "InputEnded", "CharacterAdded" } do object[name] = signal() end
	object.WaitForChild = function(self, name) return self:FindFirstChild(name) end
	local set = object.SetAttribute
	attributeSignals[object] = {}
	object.SetAttribute = function(self, key, value)
		set(self, key, value)
		local s = attributeSignals[object][key]
		if s then s:Fire() end
	end
	object.GetAttributeChangedSignal = function(_, key)
		attributeSignals[object][key] = attributeSignals[object][key] or signal()
		return attributeSignals[object][key]
	end
	if className == "ParticleEmitter" then object.Emit = function() end end
	if className == "Frame" or className == "TextButton" then
		object.AbsolutePosition = Vector2.new(100, 0)
		object.AbsoluteSize = Vector2.new(200, 6)
	end
	return object
end
local Instance = { new = newInstance }
local player = newInstance("Player")
local playerGui = newInstance("PlayerGui")
playerGui.Name = "PlayerGui"
playerGui.Parent = player
local Players = { LocalPlayer = player }
local camera = { CFrame = CFrame.new(0, 20, 60), CameraType = "CameraType.Custom" }
local workspace = newInstance("Workspace")
workspace.CurrentCamera = camera
workspace.Terrain = newInstance("Terrain")
workspace.GetServerTimeNow = function() return clock end
local Lighting = newInstance("Lighting")
local game = { GetService = function(_, name)
	if name == "Lighting" then return Lighting end
	if name == "RunService" then return RunService end
	if name == "TweenService" then return TweenService end
	if name == "Debris" then return Debris end
	if name == "UserInputService" then return UserInputService end
	if name == "ContextActionService" then return ContextActionService end
	if name == "Players" then return Players end
	return { WaitForChild = function() return Shared end }
end }
local Enum = setmetatable({ RenderPriority = { Camera = { Value = 200 } } }, { __index = function(_, group)
	return setmetatable({}, { __index = function(_, item) return group .. "." .. item end })
end })
local function step(seconds: number)
	for _ = 1, math.floor(seconds * 30 + 0.5) do
		clock += 1 / 30
		local due = {}
		for i = #scheduled, 1, -1 do
			if scheduled[i].at <= clock then table.insert(due, table.remove(scheduled, i)) end
		end
		table.sort(due, function(a, b) return a.at < b.at end)
		for _, item in due do item.run() end
		renderStepped:Fire(1 / 30)
		for _, callback in bound do callback(1 / 30) end
	end
end
'''

client_test = r'''
local passed = 0
local function check(condition: boolean, message: string)
	if not condition then error("FAIL " .. message, 2) end
	passed += 1
end
local sent = {}
local request = { FireServer = function(_, action, value) table.insert(sent, { action = action, value = value }) end }
local state = newInstance("Folder")
for key, value in { ChalkCount = 0, ChalkGoal = 1000, ChalkWins = 0, ChalkBest = 0, ChalkSpeed = 3, ChalkTheme = "classic",
	ChalkSaveCoins = 1000, ChalkResetEnds = 0, ChalkWriting = false } do
	state:SetAttribute(key, value)
end
-- An R15 writer with a shoulder and a hand.
local character = newInstance("Model")
player.Character = character
local upper = newInstance("Part")
upper.Name, upper.Parent = "RightUpperArm", character
local shoulder = newInstance("Motor6D")
shoulder.Name, shoulder.Parent, shoulder.C0 = "RightShoulder", upper, CFrame.new(1, 0.5, 0)
local hand = newInstance("Part")
hand.Name, hand.Parent, hand.Size = "RightHand", character, Vector3.new(1, 0.3, 1)

local function live(name: string): number
	local n = 0
	for _, object in instances do
		if object.Name == name and not object.destroyed and object.Parent ~= nil then n += 1 end
	end
	return n
end
local view = ChalkView.start(request, state)
local hud = playerGui:FindFirstChild("ChalkboardHud")
check(hud ~= nil and hud.Enabled == false, "the display waits until the board is joined")
step(0.5)
check(live("Chalk") == 0 and camera.CameraType == "CameraType.Custom", "nothing is drawn in the lobby")

view.setActive(true)
check(hud.Enabled, "the display shows at the board")
step(0.2)
check(camera.CameraType == "CameraType.Scriptable" and (camera.CFrame.Position - ChalkBoard.cameraFrame().Position).Magnitude < 0.1, "the classroom camera films the board")
local zero = live("Chalk")
check(zero > 10, "a 0, the goal and its target are chalked on the board: " .. zero)

-- Holding writes; the arm reaches up with a stick of chalk.
UserInputService.InputBegan:Fire({ UserInputType = "UserInputType.MouseButton1", KeyCode = "KeyCode.Unknown" }, false)
check(#sent == 1 and sent[1].action == "chalkHold" and sent[1].value == true, "pressing sends hold")
UserInputService.InputBegan:Fire({ UserInputType = "UserInputType.Keyboard", KeyCode = "KeyCode.Space" }, false)
check(#sent == 1, "a second press while holding sends nothing")
state:SetAttribute("ChalkWriting", true)
for n = 1, 12 do
	state:SetAttribute("ChalkCount", n)
	step(1 / 3)
end
check(live("HeldChalk") == 1 and shoulder.C0 ~= CFrame.new(1, 0.5, 0), "the writer's arm writes with chalk")
UserInputService.InputEnded:Fire({ UserInputType = "UserInputType.MouseButton1", KeyCode = "KeyCode.Unknown" })
check(sent[#sent].action == "chalkHold" and sent[#sent].value == false, "letting go sends release")
state:SetAttribute("ChalkWriting", false)
step(0.2)
check(live("HeldChalk") == 0, "the chalk is put down")
local twelve = live("Chalk")
-- Space is the jump key: the classroom takes it first while writing.
check(actions.ChalkboardWrite ~= nil, "Space is bound at the board")
check(actions.ChalkboardWrite("ChalkboardWrite", "UserInputState.Begin", {}) == "ContextActionResult.Sink", "Space is kept from the jump")
check(sent[#sent].action == "chalkHold" and sent[#sent].value == true, "Space writes")
actions.ChalkboardWrite("ChalkboardWrite", "UserInputState.End", {})
check(sent[#sent].value == false, "letting go of Space stops")
local clicks = #sent
UserInputService.InputBegan:Fire({ UserInputType = "UserInputType.MouseButton1", KeyCode = "KeyCode.Unknown" }, true)
check(#sent == clicks, "clicking a button doesn't write")
local function strokes(d: number): number return #ChalkBoard.segments(d, 0, 0, 1) end
check(twelve - zero == strokes(1) + strokes(2) + 1 - strokes(0), "12 is chalked in place of 0, with the progress line")

-- Gifts, the reset and its save, a wipe and a win.
state:SetAttribute("ChalkCount", 75)
view.onGift({ up = true, from = 12, to = 75, amount = 63, coins = 1000, name = "Ann", gift = "Galaxy" })
step(1)
view.onGift({ up = false, from = 75, to = 55, amount = -20, coins = 100, name = "Bo", gift = "Perfume" })
state:SetAttribute("ChalkCount", 55)
step(1.5)
check(live("SweepEraser") == 0, "the eraser leaves after rubbing out")
state:SetAttribute("ChalkResetEnds", clock + 60)
view.onReset({ state = "started", name = "Eve", seconds = 60, saveCoins = 1000 })
step(1)
local banner
for _, object in instances do
	if object.ClassName == "TextLabel" and type(object.Text) == "string" and string.find(object.Text, "^RESET IN") then banner = object end
end
check(banner ~= nil and banner.Text == "RESET IN 0:59", "the reset banner counts down: " .. tostring(banner and banner.Text))
local withClock = live("Chalk")
check(withClock > twelve, "the countdown is chalked on the board too")
state:SetAttribute("ChalkResetEnds", 0)
view.onReset({ state = "saved", name = "Gus" })
step(1)
check(live("Chalk") < withClock, "saving rubs out the countdown")
state:SetAttribute("ChalkCount", 0)
view.onReset({ state = "wiped", lost = 55 })
view.onWipe({ reason = "reset" })
step(2)
check(live("SweepEraser") == 0, "the wipe's eraser leaves")
state:SetAttribute("ChalkCount", 1000)
view.onWin({ wins = 1, goal = 1000, name = "Niamh" })
step(3)
state:SetAttribute("ChalkTheme", "neon")
step(0.2)
check(live("Chalk") > 0, "a new theme redraws the board")

-- The writing card.
local themeSent = false
for _, object in instances do
	if object.ClassName == "TextButton" and object.Text == ChalkBoard.THEMES.royal.name then object.Activated:Fire() end
end
for _, s in sent do if s.action == "setChalkTheme" and s.value == "royal" then themeSent = true end end
check(themeSent, "the theme buttons choose a theme")

-- No camera look: no REC light or viewfinder corners.
for _, object in instances do
	if object.ClassName == "TextLabel" and type(object.Text) == "string" then
		check(not string.find(object.Text, "REC"), "no REC label: " .. object.Text)
	end
end

-- The hold at the goal counts down from 10 over 15 seconds, slower at the end.
local countdown
for _, object in instances do
	if object.Name == "HoldCountdown" and not object.destroyed then countdown = object end
end
check(countdown ~= nil and countdown.Visible == false, "the hold countdown waits for the goal")
state:SetAttribute("ChalkHoldStart", clock)
step(0.1)
local number
for _, child in countdown:GetChildren() do
	if child.ClassName == "TextLabel" and child.TextSize == 88 then number = child end
end
check(countdown.Visible and number.Text == "10", "the countdown starts at 10: " .. tostring(number and number.Text))
local seen, firstHalf = {}, 0
for t = 1, 149 do
	step(0.1)
	local n = tonumber(number.Text)
	if not seen[n] then seen[n] = clock end
	if t == 75 then firstHalf = n end
end
check(seen[1] ~= nil and 10 - firstHalf > 5, "past halfway in time the count is past halfway: " .. firstHalf)
state:SetAttribute("ChalkHoldStart", 0)
step(0.1)
check(countdown.Visible == false, "losing the hold hides the countdown")

-- Every gift show plays, keeps to its part limit and tidies up.
local function digits(): { BasePart }
	local list = {}
	for _, object in instances do
		if object.Name == "Chalk" and not object.destroyed and object.Parent ~= nil then table.insert(list, object) end
	end
	return list
end
for _, up in { true, false } do
	for tier = 1, 6 do
		local most = 0
		local impact = ChalkEffects.play(tier, up, {
			chalk = Color3.new(1, 1, 1), glow = false, digits = digits,
			drawStroke = function(a, b, width)
				local stroke = newInstance("Part")
				stroke.Name, stroke.Size, stroke.Parent = "TestStroke", Vector3.new(width, width, 1), workspace
				return stroke
			end,
			shake = function() end,
		})
		check(impact == (if up then ChalkEffects.UP_IMPACT else ChalkEffects.DOWN_IMPACT)[tier], "the show says when the number changes")
		for _ = 1, ChalkEffects.LIFETIMES[tier] * 10 + 10 do
			step(0.1)
			local parts = 0
			for _, object in instances do
				if object.ClassName == "Part" and not object.destroyed and object.Parent ~= nil and object.Parent.Name == "ChalkGiftShow" then parts += 1 end
			end
			most = math.max(most, parts)
		end
		local title = (if up then ChalkEffects.UP_TITLES else ChalkEffects.DOWN_TITLES)[tier]
		check(most > 0 and most <= ChalkEffects.PART_LIMITS[tier], title .. " keeps to its part limit: " .. most)
		check(live("ChalkGiftShow") == 0, title .. " tidies up")
		check(Lighting:FindFirstChild("ChalkGrade") == nil, title .. " puts the colour back")
	end
end

-- Leaving: the camera is handed back and the board's chalk is cleared.
view.setActive(false)
step(0.5)
check(hud.Enabled == false and camera.CameraType == "CameraType.Custom", "the camera is handed back")
check(actions.ChalkboardWrite == nil, "Space is the jump key again")
check(live("Chalk") == 0, "no chalk is left behind")
print(string.format("PASS: %d chalkboard view checks", passed))
'''

run("chalk-view", mock + client_harness + mock_extras + modules(
    "src/shared/GiftTier.luau", "src/shared/Format.luau", "src/shared/ChalkBoard.luau", "src/shared/Config.luau",
    "src/shared/HoldTimer.luau", "src/client/Sounds.luau", "src/client/HoldCountdown.luau", "src/client/ChalkEffects.luau",
    "src/client/ChalkView.luau") + "\n" + client_test)
