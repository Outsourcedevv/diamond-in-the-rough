--!strict
-- Everything a streamer may want to tune. Values marked (live) can also be
-- changed in-game from the settings panel; the panel's values are saved.
local Config = {
	-- Stone -----------------------------------------------------------------
	StartingStone = 250000, -- (live) rocks in the mountain at the start of a round (one rock = one stone, max 1,500,000)
	GrowthMaxStone = 1500000, -- growth limit, or twice starting stone for larger starting mountains
	StonePerCoin = 100, -- (live) rocks removed per TikTok coin, for gifts without their own rule
	-- (live) Gift rules: gift name -> rocks removed per gift. Change them in the
	-- settings panel (press Y) while playing.
	GiftRules = {} :: { [string]: number },
	-- (live) Diamond Climb and Chalkboard Count's own gift rules: gift name ->
	-- platforms (or numbers) per gift, up if positive and down if negative.
	-- Gifts without a rule go up by their coins (a Rose 2, 100 coins 20, a
	-- Galaxy 63). Change them on the bridge's control page.
	ClimbGiftRules = {
		["ice cream cone"] = -2,
		["finger heart"] = -4,
		["perfume"] = -9,
		["confetti"] = -20,
		["money gun"] = -45,
		["tiktok universe"] = -374,
	} :: { [string]: number },
	ChalkGiftRules = {
		["ice cream cone"] = -2,
		["finger heart"] = -4,
		["perfume"] = -9,
		["confetti"] = -20,
		["money gun"] = -45,
		["tiktok universe"] = -374,
	} :: { [string]: number },
	StonePerLike = 2, -- (live)
	StonePerFollow = 500, -- (live)
	StonePerShare = 300, -- (live)

	-- The diamond -----------------------------------------------------------
	HoldSeconds = 15, -- real seconds the diamond must be held to win
	HoldCountFrom = 10, -- the number the on-screen countdown starts at
	HoldSlowdown = 0.6, -- 0 = steady countdown, 1 = slows down a lot near the end
	WinScreenSeconds = 4,

	-- The diamond bird -------------------------------------------------------
	-- It flies round the mountain every 5 to 7½ minutes. Clicking it doubles
	-- every gift (blasting or adding stone) for BirdBoostSeconds.
	BirdMinSeconds = 300,
	BirdMaxSeconds = 450,
	BirdBoostSeconds = 30,
	BirdMultiplier = 2,

	-- Win counter defaults (all live) ----------------------------------------
	WinTitle = "WINS",
	WinGoal = 0, -- 0 hides the goal ("WINS: 3" instead of "WINS: 3/10")
	WinTextColor = "#FFFFFF",
	WinBackgroundColor = "#2B2140",

	-- Rocks -----------------------------------------------------------------------
	BlockSize = 0.4, -- diggable cell size in studs; each visible rock fills one cell, sloped towards open air
	DigPerSecond = 100, -- rocks dug per second while the dig button is held
	-- The dig sound. Empty plays the built-in chip. To use any sound you like,
	-- find one in Studio's Toolbox (Audio, e.g. "rock hit" or "pickaxe") or
	-- your uploads, copy its asset id and put it here, e.g. "1234567890".
	DigSoundId = "",
	DigSoundVolume = 0.5,

	-- TikTok ------------------------------------------------------------------
	BridgeUrls = { "http://localhost:8787", "http://127.0.0.1:8787" }, -- the bridge app (Roblox Studio)
	-- The published game: each streamer's connector sends their gifts to the
	-- Diamond Rush relay (relay/worker.js on Cloudflare) under their game code,
	-- and they type the code in the Y panel. bridge/cloud.mjs has the same address.
	RelayUrl = "https://diamond-rush-relay.diamondbridgeconnector.workers.dev",
	GameCodeMaxLength = 12,
	-- Where streamers get the TikTok connector. Roblox does not allow links
	-- that lead off Roblox inside the game, so name the place and put the
	-- actual Discord invite under Social Links on the game's page.
	ConnectorMessage = "Streamers: join our Discord to download the TikTok connector (DiamondRushBridge.exe). The Discord link is on this game's page, under Social Links.",

	-- Single player: whoever plays is the streamer, so every player gets the Y
	-- panel, test gifts and gift keybinds. Set to false for a game where others
	-- join; then only the owner and Admins can.
	SinglePlayer = true,
	-- Extra Roblox user ids allowed to change settings (the owner always can).
	Admins = {} :: { number },
}

return Config

