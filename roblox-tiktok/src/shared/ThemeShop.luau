--!strict
-- The map themes and the mountain's skins as a shop, for the sidebar's Themes
-- card and the server. Alpine and the stone skin are free. Each other theme,
-- and the haystack skin, is a Roblox game pass: bought once with Robux, it's
-- the buyer's to use for good. The passes are made in the Creator Dashboard
-- (the game, then Monetization, then Passes), where each one's price is set,
-- and their ids go in Config.ThemePasses. One whose pass id is still 0 is
-- free, so the game works before the passes are made.
local ThemeShop = {}

export type Theme = {
	key: string, -- as Scenery.LOOKS / Skin and the server's setTheme / setSkin know it
	kind: string, -- "theme" (the map's look) or "skin" (the mountain's)
	name: string,
	blurb: string,
	sky: Color3, -- the little picture on its card: sky, ground and a highlight
	ground: Color3,
	accent: Color3,
}

ThemeShop.THEMES = {
	{ key = "default", kind = "theme", name = "Alpine", blurb = "Snowy peaks, pine forests and a lake",
		sky = Color3.fromRGB(150, 196, 236), ground = Color3.fromRGB(102, 126, 64), accent = Color3.fromRGB(238, 242, 247) },
	{ key = "sakura", kind = "theme", name = "Sakura", blurb = "Cherry blossom spring and a shrine",
		sky = Color3.fromRGB(246, 196, 206), ground = Color3.fromRGB(120, 160, 80), accent = Color3.fromRGB(255, 176, 204) },
	{ key = "farm", kind = "theme", name = "Farm", blurb = "A ranch with a red barn and cows",
		sky = Color3.fromRGB(250, 214, 150), ground = Color3.fromRGB(150, 140, 70), accent = Color3.fromRGB(180, 40, 36) },
	{ key = "desert", kind = "theme", name = "Desert", blurb = "A red canyon and a turquoise oasis",
		sky = Color3.fromRGB(250, 220, 170), ground = Color3.fromRGB(196, 120, 72), accent = Color3.fromRGB(64, 196, 196) },
	{ key = "haunted", kind = "theme", name = "Haunted", blurb = "A moonlit night of fog and lanterns",
		sky = Color3.fromRGB(40, 46, 86), ground = Color3.fromRGB(46, 54, 52), accent = Color3.fromRGB(255, 176, 70) },
} :: { Theme }

-- The mountain's skins: the same game, reskinned (see Skin). On their cards
-- the sky is the backdrop, the ground the mountain and the highlight the find.
ThemeShop.SKINS = {
	{ key = "stone", kind = "skin", name = "Stone & diamond", blurb = "A stone mountain with a diamond inside",
		sky = Color3.fromRGB(40, 56, 120), ground = Color3.fromRGB(132, 128, 124), accent = Color3.fromRGB(170, 230, 255) },
	{ key = "hay", kind = "skin", name = "Hay & needle", blurb = "A haystack with a needle hidden in it",
		sky = Color3.fromRGB(120, 170, 220), ground = Color3.fromRGB(226, 186, 92), accent = Color3.fromRGB(214, 220, 228) },
} :: { Theme }

-- Everything for sale, themes then skins.
ThemeShop.ITEMS = table.clone(ThemeShop.THEMES)
for _, skin in ThemeShop.SKINS do table.insert(ThemeShop.ITEMS, skin) end

-- The free ones, which can never be sold.
local ALWAYS_FREE = { default = true, stone = true }

-- The Robux symbol, as Roblox's own fonts draw it.
ThemeShop.ROBUX = utf8.char(0xE002)

function ThemeShop.find(key: string?): Theme?
	for _, theme in ThemeShop.ITEMS do
		if theme.key == key then return theme end
	end
	return nil
end

-- The theme's (or skin's) game pass id, or nil when it has none (and so is free).
function ThemeShop.pass(key: string, passes: { [string]: number }): number?
	if ALWAYS_FREE[key] then return nil end
	local id = passes[key]
	return if type(id) == "number" and id > 0 then id else nil
end

function ThemeShop.free(key: string, passes: { [string]: number }): boolean
	return ThemeShop.pass(key, passes) == nil
end

-- The theme (or skin) a game pass unlocks, or nil.
function ThemeShop.forPass(id: number, passes: { [string]: number }): string?
	for _, theme in ThemeShop.ITEMS do
		if ThemeShop.pass(theme.key, passes) == id then return theme.key end
	end
	return nil
end

-- What a theme's button says and does: "using" (it's the map now), "use"
-- (free or owned) or "buy" (with its price in Robux, if known).
function ThemeShop.status(key: string, current: string, owned: { [string]: boolean }, passes: { [string]: number }, price: number?): (string, string)
	if key == current then return "IN USE", "using" end
	if ThemeShop.free(key, passes) or owned[key] then return "USE", "use" end
	if price then return ThemeShop.ROBUX .. " " .. tostring(price), "buy" end
	return "BUY", "buy"
end

-- The OwnedThemes attribute ("sakura,farm") as a set, and back.
function ThemeShop.decode(text: any): { [string]: boolean }
	local owned: { [string]: boolean } = {}
	if type(text) ~= "string" then return owned end
	for key in string.gmatch(text, "[^,]+") do
		if ThemeShop.find(key) then owned[key] = true end
	end
	return owned
end

function ThemeShop.encode(owned: { [string]: boolean }): string
	local keys = {}
	for _, theme in ThemeShop.ITEMS do
		if owned[theme.key] then table.insert(keys, theme.key) end
	end
	return table.concat(keys, ",")
end

return ThemeShop
