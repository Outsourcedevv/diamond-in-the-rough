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

	-- TikTok ------------------------------------------------------------------
	BridgeUrls = { "http://localhost:8787", "http://127.0.0.1:8787" }, -- the bridge app (Roblox Studio)
	MessagingTopic = "DiamondRushTikTok", -- Open Cloud topic (published games)

	-- Extra Roblox user ids allowed to change settings (the owner always can).
	Admins = {} :: { number },
}

return Config

