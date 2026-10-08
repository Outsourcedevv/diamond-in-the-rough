--!strict
-- Gift keybinds: keys the streamer can give a gift to, so pressing the key in
-- the game sends that gift (no TikTok or connector needed). TikFinity can
-- press the key when the gift arrives on the LIVE. Set from the gift settings
-- (GiftMenu), the Y panel or the connector; the server publishes them as the
-- State attribute "GiftBindings" (JSON {"Shift+K": {gift, coins}}).
local Keybinds = {}

Keybinds.MAX = 300 -- bindings kept at once

-- Keys that can carry a gift. Movement (W A S D, Space), the game's own keys
-- (E for prompts, G games, H how to play, P settings, Y the streamer panel)
-- and Roblox's own keys (I and O zoom, F9 to F12) are left out, so a binding
-- never fights them. Any of them can also be held with Shift or Ctrl (or both),
-- which gives TikFinity hundreds of keys to press, one per gift.
Keybinds.KEYS = {
	"B", "C", "F", "J", "K", "L", "M", "N", "Q", "R", "T", "U", "V", "X", "Z",
	"One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Zero",
	"F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8",
	"KeypadZero", "KeypadOne", "KeypadTwo", "KeypadThree", "KeypadFour",
	"KeypadFive", "KeypadSix", "KeypadSeven", "KeypadEight", "KeypadNine",
	"KeypadPlus", "KeypadMinus", "KeypadMultiply", "KeypadDivide", "KeypadPeriod",
	"Insert", "Home", "End", "PageUp", "PageDown", "Delete",
}
Keybinds.MODIFIERS = { "Ctrl", "Shift" }
local allowed: { [string]: boolean } = {}
for _, key in Keybinds.KEYS do allowed[key] = true end

local DIGITS = {
	One = "1", Two = "2", Three = "3", Four = "4", Five = "5",
	Six = "6", Seven = "7", Eight = "8", Nine = "9", Zero = "0",
}
local KEYPAD = {
	KeypadZero = "Num 0", KeypadOne = "Num 1", KeypadTwo = "Num 2", KeypadThree = "Num 3", KeypadFour = "Num 4",
	KeypadFive = "Num 5", KeypadSix = "Num 6", KeypadSeven = "Num 7", KeypadEight = "Num 8", KeypadNine = "Num 9",
	KeypadPlus = "Num +", KeypadMinus = "Num -", KeypadMultiply = "Num *", KeypadDivide = "Num /", KeypadPeriod = "Num .",
	PageUp = "Page Up", PageDown = "Page Down",
}

-- A binding's name from a key and the modifiers held: "K", "Shift+K",
-- "Ctrl+Shift+K".
function Keybinds.combo(key: string, ctrl: boolean?, shift: boolean?): string
	return (if ctrl then "Ctrl+" else "") .. (if shift then "Shift+" else "") .. key
end

-- The key and modifiers of a binding name, or nil if it isn't one.
function Keybinds.split(name: string): (string?, boolean, boolean)
	local ctrl, shift = false, false
	local rest = name
	if string.sub(rest, 1, 5) == "Ctrl+" then ctrl = true; rest = string.sub(rest, 6) end
	if string.sub(rest, 1, 6) == "Shift+" then shift = true; rest = string.sub(rest, 7) end
	if not allowed[rest] then return nil, false, false end
	return rest, ctrl, shift
end

-- True for a binding name (e.g. "K", "One", "F6", "Shift+K") a gift can use.
function Keybinds.allowed(key: any): boolean
	if type(key) ~= "string" then return false end
	return (Keybinds.split(key)) ~= nil
end

-- How a binding is written on screen: "1" for One, "Num 1", "Shift+K".
function Keybinds.label(name: string): string
	local key, ctrl, shift = Keybinds.split(name)
	if key == nil then return name end
	return (if ctrl then "Ctrl+" else "") .. (if shift then "Shift+" else "") .. (DIGITS[key] or KEYPAD[key] or key)
end

-- A binding as the server keeps it, or nil if it is not a valid one.
function Keybinds.clean(gift: any, coins: any): { gift: string, coins: number }?
	if type(gift) ~= "string" or type(coins) ~= "number" or coins ~= coins then return nil end
	local name = string.sub(string.gsub(gift, "^%s+", ""), 1, 40)
	name = string.gsub(name, "%s+$", "")
	if name == "" then return nil end
	return { gift = name, coins = math.clamp(math.floor(coins), 1, 100000) }
end

return Keybinds
