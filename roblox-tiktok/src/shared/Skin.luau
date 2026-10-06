--!strict
-- The mountain's skin: stone with a diamond hidden inside (the default), or a
-- haystack with a needle hidden in it. It is the same game, reskinned: only
-- the rock's look (RockStyle), the gem's shape (DiamondShape) and the words on
-- the display change. The server publishes the chosen skin as the State
-- attribute "Skin".
local Skin = {}

export type Words = {
	material: string, -- "stone" / "hay": what gifts blast away
	gem: string, -- "diamond" / "needle": what you find and hold
	heap: string, -- "mountain" / "haystack"
	icon: string,
}

Skin.NAMES = { "stone", "hay" }
Skin.WORDS = {
	stone = { material = "stone", gem = "diamond", heap = "mountain", icon = "💎" },
	hay = { material = "hay", gem = "needle", heap = "haystack", icon = "🌾" },
} :: { [string]: Words }

-- The words for a skin name; anything unknown reads as stone.
function Skin.words(name: any): Words
	return Skin.WORDS[name] or Skin.WORDS.stone
end

-- The gem shape for a skin (see DiamondShape.facets).
function Skin.gem(name: any): string
	return if name == "hay" then "needle" else "diamond"
end

return Skin
