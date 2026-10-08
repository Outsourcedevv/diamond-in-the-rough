--!strict
-- TikTok LIVE gifts, their coin prices and an emoji for each, for the
-- full-screen gift settings (GiftMenu). TikTok's own gift pictures are its
-- artwork and can't be put in a Roblox game, so each gift has an emoji
-- instead. TikTok changes its gifts and prices now and then, and some differ
-- by country, so the streamer can change any gift's coins or add a gift that
-- is missing from the menu; those are kept as the "CustomGifts" of their save.
-- GiftCatalogue.ICON is the emoji for a gift that has none.
local GiftCatalogue = {}

GiftCatalogue.ICON = "🎁"

export type Gift = { name: string, coins: number, icon: string? }

GiftCatalogue.GIFTS = {
	{ name = "Rose", coins = 1, icon = "🌹" },
	{ name = "TikTok", coins = 1, icon = "🎵" },
	{ name = "GG", coins = 1, icon = "🎮" },
	{ name = "Super GG", coins = 1, icon = "🏆" },
	{ name = "Heart Me", coins = 1, icon = "💗" },
	{ name = "Ice Cream Cone", coins = 1, icon = "🍦" },
	{ name = "Thumbs Up", coins = 1, icon = "👍" },
	{ name = "Heart", coins = 1, icon = "❤️" },
	{ name = "Cake Slice", coins = 1, icon = "🍰" },
	{ name = "Glow Stick", coins = 1, icon = "🪄" },
	{ name = "Love you", coins = 1, icon = "💌" },
	{ name = "Love you so much", coins = 1, icon = "💞" },
	{ name = "Coffee", coins = 1, icon = "☕" },
	{ name = "Wink Charm", coins = 1, icon = "😉" },
	{ name = "Football", coins = 1, icon = "⚽" },
	{ name = "Basketball", coins = 1, icon = "🏀" },
	{ name = "Shamrock", coins = 1, icon = "☘️" },
	{ name = "Pumpkin", coins = 1, icon = "🎃" },
	{ name = "Snowflake", coins = 1, icon = "❄️" },
	{ name = "Team Bracelet", coins = 2, icon = "📿" },
	{ name = "Finger Heart", coins = 5, icon = "🤞" },
	{ name = "Panda", coins = 5, icon = "🐼" },
	{ name = "Tiny Diny", coins = 5, icon = "🦖" },
	{ name = "Mic", coins = 5, icon = "🎤" },
	{ name = "Cheer You Up", coins = 9, icon = "📣" },
	{ name = "Hand Wave", coins = 9, icon = "👋" },
	{ name = "Rosa", coins = 10, icon = "🌺" },
	{ name = "Friendship Necklace", coins = 10, icon = "📿" },
	{ name = "Journey Pass", coins = 10, icon = "🎫" },
	{ name = "Gold Boxing Gloves", coins = 10, icon = "🥊" },
	{ name = "Sunflower", coins = 10, icon = "🌻" },
	{ name = "Perfume", coins = 20, icon = "🧴" },
	{ name = "Kiss", coins = 20, icon = "💋" },
	{ name = "Love Bang", coins = 25, icon = "💥" },
	{ name = "Doughnut", coins = 30, icon = "🍩" },
	{ name = "Lollipop", coins = 30, icon = "🍭" },
	{ name = "Bubble Gum", coins = 49, icon = "🍬" },
	{ name = "Lightning Bolt", coins = 49, icon = "⚡" },
	{ name = "Butterfly", coins = 88, icon = "🦋" },
	{ name = "Paper Crane", coins = 99, icon = "🕊️" },
	{ name = "Little Crown", coins = 99, icon = "👑" },
	{ name = "Cap", coins = 99, icon = "🧢" },
	{ name = "Hat and Mustache", coins = 99, icon = "🥸" },
	{ name = "Star", coins = 99, icon = "⭐" },
	{ name = "Hand Hearts", coins = 100, icon = "🤲" },
	{ name = "Confetti", coins = 100, icon = "🎊" },
	{ name = "Mishka Bear", coins = 100, icon = "🧸" },
	{ name = "Heart Eyes", coins = 100, icon = "😍" },
	{ name = "Marvelous Confetti", coins = 100, icon = "🎉" },
	{ name = "Bouquet", coins = 100, icon = "💐" },
	{ name = "Rainbow Puke", coins = 100, icon = "🌈" },
	{ name = "Teddy Bear", coins = 100, icon = "🧸" },
	{ name = "Cupid", coins = 100, icon = "💘" },
	{ name = "Heart Rain", coins = 149, icon = "🌧️" },
	{ name = "Sunglasses", coins = 199, icon = "🕶️" },
	{ name = "Party Popper", coins = 199, icon = "🎉" },
	{ name = "Hearts", coins = 199, icon = "💕" },
	{ name = "Rose Hand", coins = 199, icon = "🌹" },
	{ name = "Love Balloon", coins = 199, icon = "🎈" },
	{ name = "Swing", coins = 199, icon = "🎠" },
	{ name = "Corgi", coins = 299, icon = "🐶" },
	{ name = "Boxing Gloves", coins = 299, icon = "🥊" },
	{ name = "Fruit Friends", coins = 299, icon = "🍓" },
	{ name = "Duck", coins = 299, icon = "🦆" },
	{ name = "Cotton the Seal", coins = 299, icon = "🦭" },
	{ name = "Play for You", coins = 299, icon = "🎸" },
	{ name = "Rock Star", coins = 499, icon = "🎸" },
	{ name = "Hands Up", coins = 499, icon = "🙌" },
	{ name = "Coral", coins = 499, icon = "🐠" },
	{ name = "Gaming Chair", coins = 499, icon = "🪑" },
	{ name = "Money Rain", coins = 500, icon = "💸" },
	{ name = "Money Gun", coins = 500, icon = "💵" },
	{ name = "Gem Gun", coins = 500, icon = "💎" },
	{ name = "Wishing Bottle", coins = 500, icon = "🍾" },
	{ name = "Swan", coins = 699, icon = "🦢" },
	{ name = "Lucky Cat", coins = 699, icon = "🐱" },
	{ name = "Train", coins = 899, icon = "🚂" },
	{ name = "Travel with You", coins = 999, icon = "🧳" },
	{ name = "Lucky Airdrop Box", coins = 999, icon = "🎁" },
	{ name = "Galaxy", coins = 1000, icon = "🌌" },
	{ name = "Watermelon Love", coins = 1000, icon = "🍉" },
	{ name = "Gold Mine", coins = 1000, icon = "⛏️" },
	{ name = "Glowing Jellyfish", coins = 1000, icon = "🌊" },
	{ name = "Concert", coins = 1000, icon = "🎤" },
	{ name = "Disco Ball", coins = 1000, icon = "🕺" },
	{ name = "Fireworks", coins = 1088, icon = "🎆" },
	{ name = "Bumper Cars", coins = 1200, icon = "🚗" },
	{ name = "Wedding", coins = 1400, icon = "💒" },
	{ name = "Diamond Ring", coins = 1500, icon = "💍" },
	{ name = "Marry Me", coins = 1500, icon = "💍" },
	{ name = "Love Drop", coins = 1800, icon = "💧" },
	{ name = "Paris", coins = 2000, icon = "🗼" },
	{ name = "Whale Diving", coins = 2150, icon = "🐋" },
	{ name = "Animal Band", coins = 2500, icon = "🐒" },
	{ name = "Mermaid", coins = 2988, icon = "🧜" },
	{ name = "Motorcycle", coins = 2988, icon = "🏍️" },
	{ name = "Rhythmic Bear", coins = 2999, icon = "🐻" },
	{ name = "Meteor Shower", coins = 3000, icon = "☄️" },
	{ name = "Car Drifting", coins = 3333, icon = "🏎️" },
	{ name = "Private Jet", coins = 4888, icon = "🛩️" },
	{ name = "Leon the Kitten", coins = 4888, icon = "🐈" },
	{ name = "Unicorn Fantasy", coins = 5000, icon = "🦄" },
	{ name = "Flying Jets", coins = 5000, icon = "✈️" },
	{ name = "Cool Cat", coins = 5000, icon = "😼" },
	{ name = "Wolf", coins = 5500, icon = "🐺" },
	{ name = "Sports Car", coins = 7000, icon = "🏎️" },
	{ name = "Yacht", coins = 9888, icon = "🛥️" },
	{ name = "Rose Carriage", coins = 9999, icon = "🎠" },
	{ name = "Interstellar", coins = 10000, icon = "🪐" },
	{ name = "Sunset Speedway", coins = 10000, icon = "🌅" },
	{ name = "Falcon", coins = 10999, icon = "🦅" },
	{ name = "Planet", coins = 15000, icon = "🪐" },
	{ name = "Rosa Nebula", coins = 15000, icon = "🌸" },
	{ name = "Castle Fantasy", coins = 20000, icon = "🏰" },
	{ name = "TikTok Shuttle", coins = 20000, icon = "🚀" },
	{ name = "Rocket", coins = 20000, icon = "🚀" },
	{ name = "Phoenix", coins = 25999, icon = "🐦" },
	{ name = "Dragon Flame", coins = 26999, icon = "🐉" },
	{ name = "Lion", coins = 29999, icon = "🦁" },
	{ name = "Leon and Lion", coins = 34000, icon = "🦁" },
	{ name = "Thunder Falcon", coins = 39999, icon = "🦅" },
	{ name = "Fire Phoenix", coins = 41999, icon = "🔥" },
	{ name = "Pegasus", coins = 42999, icon = "🐎" },
	{ name = "TikTok Universe", coins = 44999, icon = "🌠" },
} :: { Gift }

-- The built-in gifts plus the streamer's own (name -> coins), cheapest first,
-- one per name (a custom gift with a built-in name sets its coins).
function GiftCatalogue.all(custom: { [string]: number }?): { Gift }
	local byName: { [string]: Gift } = {}
	local list: { Gift } = {}
	for _, gift in GiftCatalogue.GIFTS do
		local copy = { name = gift.name, coins = gift.coins, icon = gift.icon }
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
				local gift = { name = name, coins = coins, icon = GiftCatalogue.ICON }
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
