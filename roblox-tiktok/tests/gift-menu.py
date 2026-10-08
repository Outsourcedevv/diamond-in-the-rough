"""Checks the full-screen gift settings under the Luau CLI with a Roblox
stand-in: the gift list (every gift once, with its coins), keybinds with Shift
and Ctrl, saving a gift's settings for each game and its key (GiftSettings),
adding a gift that's missing, and the menu itself: search, picking a gift,
typing amounts, pressing a key, Save, Test and the list showing what was saved.

    python3 tests/gift-menu.py [path/to/luau]
"""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
luau = sys.argv[1] if len(sys.argv) > 1 else "luau"


def module(path: str) -> str:
    source = (root / path).read_text(encoding="utf-8")
    source = re.sub(r'local Shared = [^\n]*\n', "", source)
    source = re.sub(r'require\(Shared:WaitForChild\("(\w+)"\)\)', r'require("../src/shared/\1")', source)
    for name in ("Players", "ReplicatedStorage", "UserInputService", "HttpService"):
        source = re.sub(rf'local {name} = game:GetService[^\n]*\n', "", source)
    return "(function()\n" + source + "\nend)()"


harness = r'''
-- A small Roblox stand-in for building GUIs.
local function signal()
	local listeners = {}
	return {
		Connect = function(_, f) table.insert(listeners, f); return { Disconnect = function() end } end,
		Fire = function(self, ...) for _, f in listeners do f(...) end end,
	}
end
local instances = {}
local guiClasses = { Frame = true, TextButton = true, TextLabel = true, TextBox = true, ScrollingFrame = true }
local Instance = { new = function(className)
	local object = { ClassName = className, destroyed = false, Activated = signal(), props = {} }
	local changed = {}
	object.IsA = function(_, name) return name == className or (name == "GuiObject" and guiClasses[className] == true) end
	object.Destroy = function(self) self.destroyed = true; rawset(self, "Parent", nil) end
	object.GetChildren = function(self)
		local out = {}
		for _, other in instances do if rawget(other, "Parent") == self and not other.destroyed then table.insert(out, other) end end
		return out
	end
	object.GetPropertyChangedSignal = function(_, name)
		changed[name] = changed[name] or signal()
		return changed[name]
	end
	object.setText = function(self, text) self.Text = text; if changed.Text then changed.Text:Fire() end end
	table.insert(instances, object)
	return object
end }
local UDim = { new = function(s, o) return { Scale = s, Offset = o } end }
local UDim2 = {
	new = function(a, b, c, d) return { a, b, c, d } end,
	fromScale = function(a, b) return { a, 0, b, 0 } end,
	fromOffset = function(a, b) return { 0, a, 0, b } end,
}
local Vector2 = { new = function(x, y) return { X = x, Y = y } end }
local Color3 = { fromRGB = function(r, g, b) return { r, g, b } end }
local Enum = setmetatable({}, { __index = function(_, group)
	return setmetatable({}, { __index = function(_, item) return group .. "." .. item end })
end })
local task = { spawn = function(f, ...) f(...) end }
-- JSON in attributes: tables are handed over by a token.
local jsonValues = {}
local HttpService = { JSONDecode = function(_, text)
	local value = jsonValues[text]
	if value == nil then error("bad json", 0) end
	return value
end }
local held = {}
local UserInputService = {
	InputBegan = signal(),
	IsKeyDown = function(_, key) return held[key] == true end,
}
local playerGui = { Name = "PlayerGui" }
local Players = { LocalPlayer = { WaitForChild = function() return playerGui end } }
local attributes = {}
local attributeSignals = {}
local state = {
	GetAttribute = function(_, name) return attributes[name] end,
	GetAttributeChangedSignal = function(_, name)
		attributeSignals[name] = attributeSignals[name] or signal()
		return attributeSignals[name]
	end,
}
local tokens = 0
local function publish(name, value)
	tokens += 1
	local token = "json#" .. tokens
	jsonValues[token] = value
	attributes[name] = token
	if attributeSignals[name] then attributeSignals[name]:Fire() end
end
local game = { GetService = function() return {} end }
'''

test = r'''
local passed = 0
local function check(condition, message)
	if not condition then error("FAIL " .. message, 2) end
	passed += 1
end

-- The gift list ------------------------------------------------------------
local seen = {}
for _, gift in GiftCatalogue.GIFTS do
	check(not seen[string.lower(gift.name)], "each gift once: " .. gift.name)
	seen[string.lower(gift.name)] = true
	check(gift.coins >= 1 and gift.coins == math.floor(gift.coins), "whole coins: " .. gift.name)
end
check(#GiftCatalogue.GIFTS >= 120, "a long list of gifts (" .. #GiftCatalogue.GIFTS .. ")")
for _, name in { "Rose", "Galaxy", "Lion", "TikTok Universe", "Interstellar", "Finger Heart", "Watermelon Love" } do
	check(GiftCatalogue.find(name) ~= nil, "has " .. name)
end
for _, gift in GiftCatalogue.GIFTS do
	check(type(gift.icon) == "string" and #gift.icon > 0, "an icon for " .. gift.name)
end
check(GiftCatalogue.find("Watermelon Love").icon == "🍉", "Watermelon Love has a watermelon")
local all = GiftCatalogue.all({ ["My Gift"] = 77, Rose = 3 })
check(#all == #GiftCatalogue.GIFTS + 1, "the streamer's own gift joins the list")
for i = 2, #all do check(all[i - 1].coins <= all[i].coins, "cheapest first") end
check(GiftCatalogue.search(all, "  GAL ")[1].name == "Galaxy", "search ignores case and spaces")
check(#GiftCatalogue.search(all, "") == #all, "empty search shows everything")
for _, gift in all do if gift.name == "Rose" then check(gift.coins == 3, "a custom price replaces the built-in one") end end

-- Keybinds -----------------------------------------------------------------
check(Keybinds.allowed("K") and Keybinds.allowed("Shift+K") and Keybinds.allowed("Ctrl+Shift+F5") and Keybinds.allowed("KeypadSeven"), "keys and combos")
check(not Keybinds.allowed("W") and not Keybinds.allowed("Shift+Y") and not Keybinds.allowed("F9") and not Keybinds.allowed("Alt+K") and not Keybinds.allowed(5), "the game's own keys are refused")
check(Keybinds.combo("K", true, true) == "Ctrl+Shift+K" and Keybinds.combo("K") == "K", "combo names")
check(Keybinds.label("Shift+One") == "Shift+1" and Keybinds.label("KeypadSeven") == "Num 7", "labels")
local keyCount = #Keybinds.KEYS * 4
check(keyCount >= 200, "hundreds of keys for TikFinity (" .. keyCount .. ")")

-- Saving a gift's settings ---------------------------------------------------
local store = { giftRules = {}, climbRules = {}, chalkRules = {}, giftBindings = { K = { gift = "Rose", coins = 1 } }, customGifts = {} }
local limits = { rough = 1500000, climb = 1000, chalk = 9999 }
check(GiftSettings.apply(store, { gift = "Galaxy", rough = 5000, climb = -20, chalk = 99999, key = "Shift+K" }, limits) == nil, "saves a gift")
check(store.giftRules.galaxy == 5000 and store.climbRules.galaxy == -20 and store.chalkRules.galaxy == 9999, "each game's amount, kept in range")
check(store.giftBindings["Shift+K"].gift == "Galaxy" and store.giftBindings["Shift+K"].coins == 1000, "the key sends the gift with its coins")
check(store.giftBindings.K.gift == "Rose", "other keys stay")
GiftSettings.apply(store, { gift = "Galaxy", rough = 5000, key = "J" }, limits)
check(store.giftBindings["Shift+K"] == nil and store.giftBindings.J.gift == "Galaxy", "one key per gift")
check(store.climbRules.galaxy == nil, "an empty amount goes back to auto")
GiftSettings.apply(store, { gift = "Rose", key = "J" }, limits)
check(store.giftBindings.J.gift == "Rose" and store.giftBindings.K == nil, "a key moves to the new gift")
check(GiftSettings.apply(store, { gift = "Galaxy", key = "W" }, limits) ~= nil, "a game key is refused")
check(GiftSettings.apply(store, { gift = "Mystery Box" }, limits) ~= nil, "a new gift needs its coins")
check(GiftSettings.apply(store, { gift = "Mystery Box", coins = 250, rough = -50 }, limits) == nil and store.customGifts["Mystery Box"] == 250, "adds a missing gift")
check(GiftSettings.apply(store, { gift = "mystery box", rough = 10 }, limits) == nil and store.customGifts["mystery box"] == 250, "renaming keeps its coins")
GiftSettings.remove(store, "Mystery Box")
check(next(store.customGifts) == nil and store.giftRules["mystery box"] == nil, "removing a gift clears it")
-- A built-in gift's price can be changed, and changed back.
check(GiftSettings.apply(store, { gift = "Galaxy", coins = 1100, key = "N" }, limits) == nil and store.customGifts.Galaxy == 1100, "a different price is kept")
check(store.giftBindings.N.coins == 1100, "the key sends the gift at that price")
GiftSettings.apply(store, { gift = "Galaxy", coins = 1000 }, limits)
check(store.customGifts.Galaxy == nil, "the built-in price needs nothing kept")
check(next(GiftSettings.cleanCustom({ [""] = 4, Good = 5.5, Bad = "x" })) == "Good", "saved custom gifts are cleaned")

-- The menu -------------------------------------------------------------------
publish("GiftRules", {}); publish("ClimbRules", {}); publish("ChalkRules", {}); publish("GiftBindings", {}); publish("CustomGifts", {})
local sent = {}
GiftMenu.start(function(action, value) table.insert(sent, { action = action, value = value }) end, state)
local function find(predicate)
	for _, object in instances do
		if not object.destroyed and predicate(object) then return object end
	end
	return nil
end
local function rows()
	local out = {}
	for _, object in instances do
		if not object.destroyed and object.ClassName == "TextButton" and object.Size and object.Size[4] == 46 then table.insert(out, object) end
	end
	return out
end
local function rowNamed(name)
	for _, row in rows() do
		for _, child in row:GetChildren() do
			if child.Text == name then return row end
		end
	end
	return nil
end
local function textOf(row)
	local texts = {}
	for _, child in row:GetChildren() do table.insert(texts, child.Text or "") end
	return table.concat(texts, " | ")
end
local gui = find(function(o) return o.ClassName == "ScreenGui" end)
check(gui and gui.Enabled == false, "starts closed")
GiftMenu.setOpen(true)
check(gui.Enabled == true and GiftMenu.isOpen(), "opens full screen")
check(#rows() == #GiftCatalogue.GIFTS, "every gift is listed (" .. #rows() .. ")")
local search = find(function(o) return o.ClassName == "TextBox" and o.PlaceholderText and string.find(o.PlaceholderText, "Search", 1, true) end)
search:setText("lion")
check(#rows() == 2 and rowNamed("Lion") and rowNamed("Leon and Lion"), "search narrows the list")
rowNamed("Lion").Activated:Fire()
local boxes = {}
for _, object in instances do
	if not object.destroyed and object.ClassName == "TextBox" and object.PlaceholderText == "auto (from the coins)" then table.insert(boxes, object) end
end
check(#boxes == 3, "an amount box for each game")
boxes[1].Text, boxes[2].Text, boxes[3].Text = "-1,000", "+25", ""
local keyButton = find(function(o) return o.ClassName == "TextButton" and o.Text == "Set key" end)
keyButton.Activated:Fire()
held["KeyCode.LeftShift"] = true
UserInputService.InputBegan:Fire({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = { Name = "LeftShift" } })
UserInputService.InputBegan:Fire({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = { Name = "M" } })
held["KeyCode.LeftShift"] = nil
check(keyButton.Text == "Key: Shift+M", "Shift and a key make the binding")
find(function(o) return o.ClassName == "TextButton" and o.Text == "Save" end).Activated:Fire()
local last = sent[#sent]
check(last.action == "setGiftSettings" and last.value.gift == "Lion" and last.value.coins == 29999, "Save sends the gift")
local title = find(function(o) return o.ClassName == "TextLabel" and o.Text == "🦁  Lion" end)
check(title ~= nil, "the editor shows the gift's icon and name")
local lionRow = rowNamed("Lion")
local hasIcon = false
for _, child in lionRow:GetChildren() do if child.Text == "🦁" then hasIcon = true end end
check(hasIcon, "each row shows the gift's icon")
check(last.value.rough == -1000 and last.value.climb == 25 and last.value.chalk == nil and last.value.key == "Shift+M", "with each game's amount and the key")
find(function(o) return o.ClassName == "TextButton" and o.Text == "Test gift" end).Activated:Fire()
check(sent[#sent].action == "testGift" and sent[#sent].value.name == "Lion", "Test sends a test gift")

-- The server saves it and publishes; the list shows it.
publish("GiftRules", { lion = -1000 }); publish("ClimbRules", { lion = 25 }); publish("GiftBindings", { ["Shift+M"] = { gift = "Lion", coins = 29999 } })
local summary = textOf(rowNamed("Lion"))
check(string.find(summary, "Rough -1000", 1, true) and string.find(summary, "Climb +25", 1, true) and string.find(summary, "Chalk auto", 1, true) and string.find(summary, "[Shift+M]", 1, true), "the list shows the saved settings: " .. summary)

-- A gift that's missing can be added.
search:setText("Space Whale")
local addRow = find(function(o) return o.ClassName == "TextButton" and o.Text and string.find(o.Text, "Add \"Space Whale\"", 1, true) end)
check(addRow ~= nil, "offers to add a missing gift")
addRow.Activated:Fire()
local coinsBox = find(function(o) return o.ClassName == "TextBox" and o.PlaceholderText == "Coins per gift" end)
check(coinsBox.Visible == true, "asks for its coins")
coinsBox.Text = "1,234"
find(function(o) return o.ClassName == "TextButton" and o.Text == "Save" end).Activated:Fire()
check(sent[#sent].value.gift == "Space Whale" and sent[#sent].value.coins == 1234, "saves the new gift with its coins")

-- Keys typed while the menu is open never reach the game's keybinds.
GiftMenu.setOpen(false)
check(gui.Enabled == false and not GiftMenu.isOpen(), "closes")
check(GiftMenu.parseAmount(" 1,500 ") == 1500 and GiftMenu.parseAmount("") == nil and GiftMenu.parseAmount("x") == nil, "amounts are read")
print("gift menu: " .. passed .. " checks passed")
'''

program = (harness
    + "local GiftCatalogue = require(\"../src/shared/GiftCatalogue\")\n"
    + "local Keybinds = require(\"../src/shared/Keybinds\")\n"
    + "local GiftSettings = " + module("src/server/GiftSettings.luau") + "\n"
    + "local GiftMenu = " + module("src/client/GiftMenu.luau") + "\n"
    + test)
work = root / "tests" / ".gift-menu.luau"
work.write_text(program, encoding="utf-8")
try:
    result = subprocess.run([luau, str(work)], capture_output=True, text=True)
finally:
    work.unlink(missing_ok=True)
print(result.stdout.strip())
if result.returncode != 0 or "FAIL" in result.stdout or result.stderr.strip():
    print(result.stderr.strip())
    sys.exit(1)
