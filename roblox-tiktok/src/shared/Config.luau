--!strict
-- Everything a streamer may want to tune. Values marked (live) can also be
-- changed in-game from the settings panel; the panel's values are saved.
local Config = {
	-- Stone -----------------------------------------------------------------
	StartingStone = 250000, -- (live) rocks in the mountain at the start of a round (one rock = one stone, max 1,500,000)
	GrowthMaxStone = 1500000, -- growth limit, or twice starting stone for larger starting mountains
	StonePerCoin = 100, -- (live) rocks removed per TikTok coin, for gifts without their own rule
	-- (live) Gift rules: gift name -> rocks removed per gift. Change them in the
	-- gift settings (press Y, then Open gift settings) while playing.
	GiftRules = {} :: { [string]: number },
	-- (live) Diamond Climb and Chalkboard Count's own gift rules: gift name ->
	-- platforms (or numbers) per gift, up if positive and down if negative.
	-- Gifts without a rule go up by their coins (a Rose 2, 100 coins 20, a
	-- Galaxy 63). Change them in the gift settings (press Y, then Open gift
	-- settings). A fresh save starts with these.
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
	-- Holding Shift (or the left stick, or the Run button on a phone) moves
	-- this many times faster, everywhere (see the client's Sprint).
	SprintMultiplier = 1.5,

	-- Map themes and the haystack skin for Robux (the sidebar's Themes).
	-- Alpine and the stone skin are free; each of these is a game pass: make
	-- it in the Creator Dashboard (your game, then Monetization, then Passes),
	-- set its price there, and put its id here. One left at 0 is free.
	ThemePasses = {
		sakura = 0,
		farm = 0,
		desert = 0,
		haunted = 0,
		hay = 0, -- the Hay & needle skin
	} :: { [string]: number },

	-- Single player: whoever plays is the streamer, so every player gets the Y
	-- panel, test gifts and gift settings (with their keys). Set to false for a game where others
	-- join; then only the owner and Admins can.
	SinglePlayer = true,
	-- Extra Roblox user ids allowed to change settings (the owner always can).
	Admins = {} :: { number },
}

return Config

