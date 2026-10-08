--!strict
-- One gift's settings from the full-screen gift settings (GiftMenu): what it
-- does in each game and the key that sends it (for TikFinity), in one go.
--   rough: rocks per gift in Diamond in the Rough (negative adds stone)
--   climb: platforms per gift in Diamond Climb (negative goes down)
--   chalk: numbers per gift in Chalkboard Count (negative counts down)
--   wins:  wins per gift, added to (or, negative, taken from) the win
--          counter of whichever game is being played
--   anim:  the show to play (1 smallest to 6 biggest), or nil for the one
--          the gift's coins pick
--   reset: true to send whichever game is being played back to the start
--          (a full mountain, platform 0, or a count of 0)
--   key:   a keybind name ("K", "Shift+K"), or "" for none
-- A missing or non-number amount means "the game's default" (worked out from
-- the gift's coins). A gift that isn't in the built-in list is kept as one of
-- the streamer's own gifts, with its coins.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("DiamondRush")
local Keybinds = require(Shared:WaitForChild("Keybinds"))
local GiftCatalogue = require(Shared:WaitForChild("GiftCatalogue"))

local GiftSettings = {}

export type Limits = { rough: number, climb: number, chalk: number, wins: number }
export type Store = {
	giftRules: { [string]: any },
	climbRules: { [string]: any },
	chalkRules: { [string]: any },
	winRules: { [string]: any },
	resetGifts: { [string]: any },
	animRules: { [string]: any },
	giftBindings: { [string]: any },
	customGifts: { [string]: number },
}

GiftSettings.MAX_CUSTOM = 200

local function amount(value: any, limit: number): number?
	if type(value) ~= "number" or value ~= value then return nil end
	return math.clamp(math.floor(value), -limit, limit)
end

-- Applies `value` ({ gift, coins, rough, climb, chalk, key }) to the store.
-- Returns nil when done, or a short reason it couldn't be.
function GiftSettings.apply(store: Store, value: any, limits: Limits): string?
	if type(value) ~= "table" or type(value.gift) ~= "string" then return "Pick a gift." end
	local name = (string.gsub(string.sub(value.gift, 1, 40), "^%s*(.-)%s*$", "%1"))
	if name == "" then return "Type the gift's name." end
	local lower = string.lower(name)
	local known = GiftCatalogue.find(name)
	local coins = if type(value.coins) == "number" and value.coins == value.coins then math.clamp(math.floor(value.coins), 1, 100000) else nil
	if known == nil then
		-- One of the streamer's own gifts: it needs its coins.
		local existing: string? = nil
		local oldCoins: number? = nil
		for other, otherCoins in store.customGifts do
			if string.lower(other) == lower then existing, oldCoins = other, otherCoins end
		end
		if coins == nil and oldCoins == nil then return "Type how many coins the gift costs." end
		if existing == nil then
			local count = 0
			for _ in store.customGifts do count += 1 end
			if count >= GiftSettings.MAX_CUSTOM then return string.format("You can add up to %d gifts of your own.", GiftSettings.MAX_CUSTOM) end
		elseif existing ~= name then
			store.customGifts[existing] = nil
		end
		store.customGifts[name] = coins or oldCoins :: number
	end
	if known and coins then
		-- A built-in gift: a different price (TikTok's differ by country) is
		-- kept as the streamer's own; the built-in price needs nothing kept.
		for other in store.customGifts do
			if string.lower(other) == lower then store.customGifts[other] = nil end
		end
		if coins ~= known.coins then
			local count = 0
			for _ in store.customGifts do count += 1 end
			if count >= GiftSettings.MAX_CUSTOM then return string.format("You can change up to %d gifts' coins.", GiftSettings.MAX_CUSTOM) end
			store.customGifts[known.name] = coins
		end
	end
	local key = value.key
	if type(key) == "string" and key ~= "" and not Keybinds.allowed(key) then
		return Keybinds.label(key) .. " is used by the game. Pick another key."
	end

	store.giftRules[lower] = amount(value.rough, limits.rough)
	store.climbRules[lower] = amount(value.climb, limits.climb)
	store.chalkRules[lower] = amount(value.chalk, limits.chalk)
	store.winRules[lower] = amount(value.wins, limits.wins)
	store.resetGifts[lower] = if value.reset == true then true else nil
	store.animRules[lower] = if type(value.anim) == "number" and value.anim == math.floor(value.anim) and value.anim >= 1 and value.anim <= 6 then value.anim else nil

	-- One key per gift: the gift's old key goes, and the new key leaves any
	-- other gift it was on.
	for other, binding in store.giftBindings do
		if type(binding) == "table" and type(binding.gift) == "string" and string.lower(binding.gift) == lower then
			store.giftBindings[other] = nil
		end
	end
	if type(key) == "string" and key ~= "" then
		local count = 0
		for _ in store.giftBindings do count += 1 end
		if store.giftBindings[key] == nil and count >= Keybinds.MAX then
			return string.format("You can keep up to %d keybinds. Remove one first.", Keybinds.MAX)
		end
		local giftCoins = coins or store.customGifts[if known then known.name else name] or (if known then known.coins else nil) or 1
		store.giftBindings[key] = { gift = if known then known.name else name, coins = giftCoins, game = true }
	end
	return nil
end

-- Removes one of the streamer's own gifts, with its rules and key.
function GiftSettings.remove(store: Store, gift: any)
	if type(gift) ~= "string" then return end
	local lower = string.lower(gift)
	for name in store.customGifts do
		if string.lower(name) == lower then store.customGifts[name] = nil end
	end
	store.giftRules[lower] = nil
	store.climbRules[lower] = nil
	store.chalkRules[lower] = nil
	store.winRules[lower] = nil
	store.resetGifts[lower] = nil
	store.animRules[lower] = nil
	for key, binding in store.giftBindings do
		if type(binding) == "table" and type(binding.gift) == "string" and string.lower(binding.gift) == lower then
			store.giftBindings[key] = nil
		end
	end
end

-- Saved keybinds, cleaned up: only keys the game still lets a gift have (an
-- older save could hold one the game now uses itself, like G or P), each with
-- a gift name and its coins, and at most Keybinds.MAX of them.
function GiftSettings.cleanBindings(raw: any): { [string]: any }
	local out: { [string]: any } = {}
	if type(raw) ~= "table" then return out end
	local count = 0
	for key, binding in raw do
		if count >= Keybinds.MAX then break end
		if Keybinds.allowed(key) and type(binding) == "table" and type(binding.gift) == "string"
			and type(binding.coins) == "number" and binding.coins == binding.coins then
			local gift = (string.gsub(string.sub(binding.gift, 1, 40), "^%s*(.-)%s*$", "%1"))
			if gift ~= "" then
				out[key] = { gift = gift, coins = math.clamp(math.floor(binding.coins), 1, 100000), game = true }
				count += 1
			end
		end
	end
	return out
end

-- A saved list of the streamer's own gifts, cleaned up.
function GiftSettings.cleanCustom(raw: any): { [string]: number }
	local out: { [string]: number } = {}
	if type(raw) ~= "table" then return out end
	local count = 0
	for name, coins in raw do
		if type(name) == "string" and type(coins) == "number" and coins == coins and count < GiftSettings.MAX_CUSTOM then
			local clean = (string.gsub(string.sub(name, 1, 40), "^%s*(.-)%s*$", "%1"))
			if clean ~= "" then
				out[clean] = math.clamp(math.floor(coins), 1, 100000)
				count += 1
			end
		end
	end
	return out
end

return GiftSettings
