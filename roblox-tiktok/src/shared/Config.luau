--!strict
-- Everything a streamer may want to tune. Values marked (live) can also be
-- changed in-game from the settings panel; the panel's values are saved.
local Config = {
	-- Stone -----------------------------------------------------------------
	StartingStone = 250000, -- (live) rocks in the mountain at the start of a round (one rock = one stone, max 1,500,000)
	StonePerCoin = 100, -- stone removed per TikTok coin gifted (a Rose is 1 coin)
	StonePerLike = 2,
	StonePerFollow = 500,
	StonePerShare = 300,

	-- The diamond -----------------------------------------------------------
	HoldSeconds = 15, -- real seconds the diamond must be held to win
	HoldCountFrom = 10, -- the number the on-screen countdown starts at
	HoldSlowdown = 0.6, -- 0 = steady countdown, 1 = slows down a lot near the end
	WinScreenSeconds = 4,

	-- Win counter defaults (all live) ----------------------------------------
	WinTitle = "WINS",
	WinGoal = 0, -- 0 hides the goal ("WINS: 3" instead of "WINS: 3/10")
	WinTextColor = "#FFFFFF",
	WinBackgroundColor = "#2B2140",

	-- Rocks -----------------------------------------------------------------------
	BlockSize = 1, -- size of one rock in studs (the diamond is the same size)

	-- TikTok ------------------------------------------------------------------
	BridgeUrls = { "http://localhost:8787", "http://127.0.0.1:8787" }, -- the bridge app (Roblox Studio)
	MessagingTopic = "DiamondRushTikTok", -- Open Cloud topic (published games)

	-- Extra Roblox user ids allowed to change settings (the owner always can).
	Admins = {} :: { number },
}

return Config
