--!strict
-- Diamond Climb's path: 1000 big gem platforms spiralling up round a crystal
-- pillar in the sky, far from the valley and the lobby (and hidden from them,
-- see ClimbView), with the diamond on the last one. Each platform is a little higher above the one before (from
-- 2 studs at the bottom to 3.5 at the top), always a short, easy hop away.
-- The spiral is wide (18 platforms a turn), so the turn above is over 30
-- studs overhead: clear of jumping heads and of the camera.
-- The server builds the tower from this and checks where players stand; each
-- player's game draws the climb's display and gift animations from it.
local GiftTier = require(script.Parent:WaitForChild("GiftTier"))

local ClimbPath = {}

ClimbPath.TOP = 1000 -- the platform with the diamond
ClimbPath.ORIGIN = Vector3.new(2600, 200, 0) -- the pillar's foot; platform 0 is the start island
ClimbPath.RADIUS = 48 -- studs from the pillar to the platforms' centres
ClimbPath.SPACING = 16.75 -- studs between neighbouring platforms' centres, along the spiral (18 a turn)
ClimbPath.RISE_LOW, ClimbPath.RISE_HIGH = 2, 3.5 -- studs each platform rises, at the bottom and the top
ClimbPath.THICKNESS = 1.2
ClimbPath.START_SIZE = 30 -- the start island's width
ClimbPath.MILESTONE = 100 -- every 100th platform is a bigger gold-rimmed one

-- Movement the climber can choose (the climb's sliders), and Roblox's defaults.
ClimbPath.SPEED = { min = 8, max = 40, default = 16 }
ClimbPath.JUMP = { min = 4, max = 15, default = 7.2 }

-- Gem colours, a new one every hundred platforms.
ClimbPath.GEMS = {
	Color3.fromRGB(96, 170, 255), -- sapphire
	Color3.fromRGB(70, 214, 140), -- emerald
	Color3.fromRGB(255, 92, 120), -- ruby
	Color3.fromRGB(176, 110, 255), -- amethyst
	Color3.fromRGB(255, 186, 72), -- topaz
	Color3.fromRGB(80, 226, 230), -- aquamarine
	Color3.fromRGB(255, 120, 200), -- pink sapphire
	Color3.fromRGB(150, 230, 90), -- peridot
	Color3.fromRGB(255, 140, 70), -- fire opal
	Color3.fromRGB(210, 236, 255), -- diamond
}

local function clampIndex(index: number): number
	return math.clamp(math.floor(index), 0, ClimbPath.TOP)
end

-- How far platform `index` rises above the one before it.
function ClimbPath.rise(index: number): number
	return ClimbPath.RISE_LOW + (ClimbPath.RISE_HIGH - ClimbPath.RISE_LOW) * index / ClimbPath.TOP
end

-- The height of platform `index`'s top above the start island's top.
function ClimbPath.height(index: number): number
	local n = clampIndex(index)
	-- The sum of rise(1) .. rise(n).
	return ClimbPath.RISE_LOW * n + (ClimbPath.RISE_HIGH - ClimbPath.RISE_LOW) * n * (n + 1) / (2 * ClimbPath.TOP)
end

-- The angle round the pillar of platform `index`.
function ClimbPath.angle(index: number): number
	return clampIndex(index) * ClimbPath.SPACING / ClimbPath.RADIUS
end

-- The middle of platform `index`'s top surface, in the world.
function ClimbPath.top(index: number): Vector3
	local n = clampIndex(index)
	local angle = ClimbPath.angle(n)
	local reach = if n == 0 then ClimbPath.RADIUS + 4 else ClimbPath.RADIUS
	return ClimbPath.ORIGIN + Vector3.new(math.cos(angle) * reach, ClimbPath.height(n), math.sin(angle) * reach)
end

-- How wide platform `index` is: 13.6 studs, 18.7 for every hundredth and
-- 23.8 for the top (1.7 times the first tower's 8, 11 and 14).
ClimbPath.SCALE = 1.7
function ClimbPath.size(index: number): number
	local n = clampIndex(index)
	if n == 0 then return ClimbPath.START_SIZE end
	if n == ClimbPath.TOP then return 14 * ClimbPath.SCALE end
	if n % ClimbPath.MILESTONE == 0 then return 11 * ClimbPath.SCALE end
	return 8 * ClimbPath.SCALE
end

-- Platform `index`'s gem colour.
function ClimbPath.colour(index: number): Color3
	local n = clampIndex(index)
	return ClimbPath.GEMS[math.min(#ClimbPath.GEMS, math.floor(math.max(n - 1, 0) / 100) + 1)]
end

-- Where a player stands on platform `index`, facing along the climb.
function ClimbPath.standFrame(index: number): CFrame
	local n = clampIndex(index)
	local at = ClimbPath.top(n) + Vector3.new(0, 3, 0)
	local ahead = ClimbPath.top(math.min(n + 1, ClimbPath.TOP))
	local look = Vector3.new(ahead.X - at.X, 0, ahead.Z - at.Z)
	if n == ClimbPath.TOP or look.Magnitude < 0.1 then
		look = Vector3.new(ClimbPath.ORIGIN.X - at.X, 0, ClimbPath.ORIGIN.Z - at.Z)
	end
	return CFrame.lookAt(at, at + look.Unit)
end

-- True if a point (a player's feet) is on platform `index`: over it and
-- standing on or just above its top. `slack` widens the check (the server
-- sees players a moment late).
function ClimbPath.isOn(index: number, feet: Vector3, slack: number?): boolean
	local extra = slack or 0
	local top = ClimbPath.top(index)
	local flat = Vector3.new(feet.X - top.X, 0, feet.Z - top.Z).Magnitude
	return flat <= ClimbPath.size(index) / 2 + 1.5 + extra and feet.Y >= top.Y - 1.5 - extra and feet.Y <= top.Y + 4 + extra * 2
end

-- How many platforms a gift of `coins` (each) moves the climber, up or down.
-- It grows with the square root of the coins: a Rose is 2, 100 coins is 20,
-- a Galaxy 63 and 10,000 coins 200. `strength` is the streamer's multiplier.
function ClimbPath.giftPlatforms(coins: number, strength: number?): number
	return math.max(1, math.floor(2 * math.sqrt(math.max(coins, 1)) * (strength or 1) + 0.5))
end

-- The animation tier (1 to 6) for a gift of `coins` (each).
ClimbPath.tier = GiftTier.forCoins

-- How long each tier's send-up or send-down animation runs, in seconds.
ClimbPath.GIFT_SECONDS = { 1.6, 2.2, 3.4, 4.6, 6, 8 }
function ClimbPath.giftSeconds(coins: number): number
	return ClimbPath.GIFT_SECONDS[GiftTier.forCoins(math.max(1, coins))]
end

ClimbPath.UP_TITLES = { "BOUNCE PAD", "SPRING LAUNCH", "ROCKET BOOST", "DIAMOND CANNON", "STARLIGHT ASCENT", "GALACTIC ASCENSION" }
ClimbPath.DOWN_TITLES = { "BANANA SLIP", "SPIKE BOUNCE", "ANVIL SMASH", "METEOR STRIKE", "THUNDER HAMMER", "BLACK HOLE PLUNGE" }

return ClimbPath
