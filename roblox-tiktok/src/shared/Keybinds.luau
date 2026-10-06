--!strict
-- Gift keybinds: keys the streamer can give a gift to, so pressing the key in
-- the game sends that gift (no TikTok or bridge needed). Set from the Y
-- panel's GIFT KEYBINDS or from the bridge's catalogue; the server publishes
-- them as the State attribute "GiftBindings" (JSON {KeyName: {gift, coins}}).
local Keybinds = {}

Keybinds.MAX = 24 -- bindings kept at once

-- Keys that can carry a gift. Movement (W A S D, Space), the game's own keys
-- (E for prompts, G games, H how to play, P settings, Y the streamer panel)
-- and Roblox's zoom keys (I, O) are left out, so a binding never fights them.
Keybinds.KEYS = {
	"B", "C", "F", "J", "K", "L", "M", "N", "Q", "R", "T", "U", "V", "X", "Z",
	"One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Zero",
	"F6", "F7", "F8",
}
local allowed: { [string]: boolean } = {}
for _, key in Keybinds.KEYS do allowed[key] = true end

local DIGITS = {
	One = "1", Two = "2", Three = "3", Four = "4", Five = "5",
	Six = "6", Seven = "7", Eight = "8", Nine = "9", Zero = "0",
}

-- True for a KeyCode name (e.g. "K", "One", "F6") a gift can be bound to.
function Keybinds.allowed(key: any): boolean
	return type(key) == "string" and allowed[key] == true
end

-- How a key is written on screen: "1" for One, otherwise its name.
function Keybinds.label(key: string): string
	return DIGITS[key] or key
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
