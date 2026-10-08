--!strict
-- TikTok LIVE gifts and their coin prices, for the full-screen gift settings
-- (GiftMenu). TikTok changes its gifts and prices now and then, and some differ
-- by country, so the streamer can add any gift that is missing (with its
-- coins) from the menu; those are kept as the "CustomGifts" of their save.
local GiftCatalogue = {}

export type Gift = { name: string, coins: number }

GiftCatalogue.GIFTS = {
	-- 1 coin
	{ name = "Rose", coins = 1 },
	{ name = "TikTok", coins = 1 },
	{ name = "GG", coins = 1 },
	{ name = "Heart Me", coins = 1 },
	{ name = "Ice Cream Cone", coins = 1 },
	{ name = "Thumbs Up", coins = 1 },
	{ name = "Heart", coins = 1 },
	{ name = "Cake Slice", coins = 1 },
	{ name = "Glow Stick", coins = 1 },
	{ name = "Love you", coins = 1 },
	{ name = "Love you so much", coins = 1 },
	{ name = "Super GG", coins = 1 },
	-- 5 to 49 coins
	{ name = "Finger Heart", coins = 5 },
	{ name = "Panda", coins = 5 },
	{ name = "Tiny Diny", coins = 5 },
	{ name = "Rosa", coins = 10 },
	{ name = "Friendship Necklace", coins = 10 },
	{ name = "Perfume", coins = 20 },
	{ name = "Love Bang", coins = 25 },
	{ name = "Doughnut", coins = 30 },
	{ name = "Butterfly", coins = 88 },
	-- around 100 coins
	{ name = "Paper Crane", coins = 99 },
	{ name = "Little Crown", coins = 99 },
	{ name = "Cap", coins = 99 },
	{ name = "Hat and Mustache", coins = 99 },
	{ name = "Hand Hearts", coins = 100 },
	{ name = "Confetti", coins = 100 },
	{ name = "Mishka Bear", coins = 100 },
	{ name = "Heart Eyes", coins = 100 },
	{ name = "Marvelous Confetti", coins = 100 },
	{ name = "Bouquet", coins = 100 },
	{ name = "Heart Rain", coins = 149 },
	{ name = "Sunglasses", coins = 199 },
	{ name = "Party Popper", coins = 199 },
	{ name = "Hearts", coins = 199 },
	{ name = "Rose Hand", coins = 199 },
	-- 299 to 999 coins
	{ name = "Corgi", coins = 299 },
	{ name = "Boxing Gloves", coins = 299 },
	{ name = "Fruit Friends", coins = 299 },
	{ name = "Rock Star", coins = 499 },
	{ name = "Hands Up", coins = 499 },
	{ name = "Money Rain", coins = 500 },
	{ name = "Money Gun", coins = 500 },
	{ name = "Gem Gun", coins = 500 },
	{ name = "Swan", coins = 699 },
	{ name = "Train", coins = 899 },
	{ name = "Travel with You", coins = 999 },
	{ name = "Lucky Airdrop Box", coins = 999 },
	-- 1,000 coins and up
	{ name = "Galaxy", coins = 1000 },
	{ name = "Gold Mine", coins = 1000 },
	{ name = "Glowing Jellyfish", coins = 1000 },
	{ name = "Fireworks", coins = 1088 },
	{ name = "Diamond Ring", coins = 1500 },
	{ name = "Whale Diving", coins = 2150 },
	{ name = "Animal Band", coins = 2500 },
	{ name = "Motorcycle", coins = 2988 },
	{ name = "Rhythmic Bear", coins = 2999 },
	{ name = "Meteor Shower", coins = 3000 },
	{ name = "Private Jet", coins = 4888 },
	{ name = "Leon the Kitten", coins = 4888 },
	{ name = "Unicorn Fantasy", coins = 5000 },
	{ name = "Flying Jets", coins = 5000 },
	{ name = "Sports Car", coins = 7000 },
	{ name = "Interstellar", coins = 10000 },
	{ name = "Sunset Speedway", coins = 10000 },
	{ name = "Falcon", coins = 10999 },
	{ name = "Rosa Nebula", coins = 15000 },
	{ name = "Castle Fantasy", coins = 20000 },
	{ name = "TikTok Shuttle", coins = 20000 },
	{ name = "Dragon Flame", coins = 26999 },
	{ name = "Lion", coins = 29999 },
	{ name = "Leon and Lion", coins = 34000 },
	{ name = "Thunder Falcon", coins = 39999 },
	{ name = "Fire Phoenix", coins = 41999 },
	{ name = "Pegasus", coins = 42999 },
	{ name = "TikTok Universe", coins = 44999 },
} :: { Gift }

-- The built-in gifts plus the streamer's own (name -> coins), cheapest first,
-- one per name (a custom gift with a built-in name sets its coins).
function GiftCatalogue.all(custom: { [string]: number }?): { Gift }
	local byName: { [string]: Gift } = {}
	local list: { Gift } = {}
	for _, gift in GiftCatalogue.GIFTS do
		local copy = { name = gift.name, coins = gift.coins }
		byName[string.lower(gift.name)] = copy
		table.insert(list, copy)
	end
	local extra: { [string]: number } = custom or {}
	for name, coins in extra do
		if type(name) == "string" and name ~= "" and type(coins) == "number" then
			local known = byName[string.lower(name)]
			if known then
				known.coins = coins
			else
				local gift = { name = name, coins = coins }
				byName[string.lower(name)] = gift
				table.insert(list, gift)
			end
		end
	end
	table.sort(list, function(a, b)
		if a.coins ~= b.coins then return a.coins < b.coins end
		return string.lower(a.name) < string.lower(b.name)
	end)
	return list
end

-- The gifts whose name contains `query` (any case; empty matches all).
function GiftCatalogue.search(list: { Gift }, query: string): { Gift }
	local needle = string.lower((string.gsub(query, "^%s*(.-)%s*$", "%1")))
	if needle == "" then return list end
	local found: { Gift } = {}
	for _, gift in list do
		if string.find(string.lower(gift.name), needle, 1, true) then table.insert(found, gift) end
	end
	return found
end

-- The built-in gift called `name` (any case), or nil.
function GiftCatalogue.find(name: string): Gift?
	local lower = string.lower(name)
	for _, gift in GiftCatalogue.GIFTS do
		if string.lower(gift.name) == lower then return gift end
	end
	return nil
end

return GiftCatalogue
