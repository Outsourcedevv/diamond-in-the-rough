--!strict
-- Chalkboard Count's classroom and board: where everything stands, how each
-- number is written in chalk strokes (no text on the board, so nothing can
-- glitch), the board's themes, and how far a gift moves the count. The server
-- builds the classroom from this; each player's game draws the chalk.
local GiftTier = require(script.Parent:WaitForChild("GiftTier"))

local ChalkBoard = {}

ChalkBoard.ORIGIN = Vector3.new(-2600, 200, 0) -- the middle of the classroom floor's top
ChalkBoard.BOARD_WIDTH, ChalkBoard.BOARD_HEIGHT = 36, 13
ChalkBoard.BOARD_BOTTOM = 2.4 -- above the floor
ChalkBoard.BOARD_Z = -20 -- the board's middle, from the classroom's middle (it faces +Z)
ChalkBoard.BOARD_THICKNESS = 0.6

-- The settings: the number to reach, and how fast the hand writes.
ChalkBoard.GOAL = { min = 10, max = 100000, default = 1000 }
ChalkBoard.SPEED = { min = 1, max = 20, default = 3 } -- numbers a second
ChalkBoard.RESET_SECONDS = { min = 10, max = 300, default = 60 }
ChalkBoard.RESET_GIFT = "Galaxy" -- starts the reset countdown
ChalkBoard.SAVE_COINS = 1000 -- a gift worth this much (not the reset gift) saves the count
ChalkBoard.MAX_DIGITS = 6

-- The board's front, where chalk goes.
function ChalkBoard.face(): number
	return ChalkBoard.ORIGIN.Z + ChalkBoard.BOARD_Z + ChalkBoard.BOARD_THICKNESS / 2
end

-- The middle of the board's front.
function ChalkBoard.centre(): Vector3
	return Vector3.new(ChalkBoard.ORIGIN.X, ChalkBoard.ORIGIN.Y + ChalkBoard.BOARD_BOTTOM + ChalkBoard.BOARD_HEIGHT / 2, ChalkBoard.face())
end

-- Where the writer stands: at the board, a little right of the middle,
-- facing it (the big number is written above their head).
function ChalkBoard.standFrame(): CFrame
	local at = Vector3.new(ChalkBoard.ORIGIN.X + 3, ChalkBoard.ORIGIN.Y + 3, ChalkBoard.face() + 2.6)
	return CFrame.lookAt(at, at - Vector3.new(0, 0, 1))
end

-- The classroom camera: in front of the board and off to one side, looking
-- at the writer and the board.
function ChalkBoard.cameraFrame(): CFrame
	local O = ChalkBoard.ORIGIN
	local at = Vector3.new(O.X + 7, O.Y + 7.5, ChalkBoard.face() + 27)
	return CFrame.lookAt(at, ChalkBoard.centre() + Vector3.new(0, -0.8, 0))
end

-- Where the big number is written: its middle and height.
ChalkBoard.NUMBER_HEIGHT = 5.4
ChalkBoard.NUMBER_Y = 9.6 -- above the floor, the number's middle
ChalkBoard.DIGIT_WIDTH = 3.1
ChalkBoard.DIGIT_GAP = 0.9

-- Board positions: `x` across from the board's middle, `y` above the floor.
function ChalkBoard.onBoard(x: number, y: number): Vector3
	return Vector3.new(ChalkBoard.ORIGIN.X + x, ChalkBoard.ORIGIN.Y + y, ChalkBoard.face() + 0.06)
end

-- The left edge of each digit of an `n`-digit number `height` tall, centred on `middle`.
function ChalkBoard.digitLefts(n: number, height: number?, middle: number?): { number }
	local scale = (height or ChalkBoard.NUMBER_HEIGHT) / ChalkBoard.NUMBER_HEIGHT
	local width, gap = ChalkBoard.DIGIT_WIDTH * scale, ChalkBoard.DIGIT_GAP * scale
	local total = n * width + (n - 1) * gap
	local lefts = {}
	for i = 1, n do
		table.insert(lefts, (middle or 0) - total / 2 + (i - 1) * (width + gap))
	end
	return lefts
end

-- An ellipse as a polyline, from angle `a0` to `a1` (radians, 0 = right).
local function arc(cx: number, cy: number, rx: number, ry: number, a0: number, a1: number, steps: number): { Vector2 }
	local points = {}
	for i = 0, steps do
		local a = a0 + (a1 - a0) * i / steps
		table.insert(points, Vector2.new(cx + math.cos(a) * rx, cy + math.sin(a) * ry))
	end
	return points
end
local function line(...: number): { Vector2 }
	local values = { ... }
	local points = {}
	for i = 1, #values, 2 do
		table.insert(points, Vector2.new(values[i], values[i + 1]))
	end
	return points
end
local function join(a: { Vector2 }, b: { Vector2 }): { Vector2 }
	local out = table.clone(a)
	for _, p in b do table.insert(out, p) end
	return out
end

-- Each digit as hand-written chalk strokes: polylines in a box from (0, 0)
-- at the bottom left to (1, 1) at the top right, in writing order.
ChalkBoard.DIGITS = {
	[0] = { arc(0.5, 0.5, 0.42, 0.5, math.pi / 2, math.pi / 2 + 2 * math.pi, 14) },
	[1] = { line(0.22, 0.78, 0.55, 1, 0.55, 0), line(0.25, 0, 0.85, 0) },
	[2] = { join(arc(0.5, 0.7, 0.4, 0.3, math.pi * 0.95, -math.pi * 0.25, 7), line(0.1, 0, 0.92, 0)) },
	[3] = { join(arc(0.48, 0.76, 0.36, 0.24, math.pi * 0.85, -math.pi * 0.5, 7), arc(0.48, 0.27, 0.42, 0.27, math.pi * 0.5, -math.pi * 0.85, 8)) },
	[4] = { line(0.68, 0, 0.68, 1, 0.05, 0.32, 0.95, 0.32) },
	[5] = { join(line(0.86, 1, 0.22, 1, 0.16, 0.56), arc(0.5, 0.3, 0.4, 0.3, math.pi * 0.7, -math.pi * 0.85, 8)) },
	[6] = { join(arc(0.6, 0.45, 0.45, 0.55, math.pi * 0.35, math.pi, 6), arc(0.5, 0.29, 0.35, 0.29, math.pi, math.pi * 3, 12)) },
	[7] = { line(0.05, 1, 0.95, 1, 0.35, 0) },
	[8] = { arc(0.5, 0.76, 0.3, 0.24, -math.pi / 2, math.pi * 1.5, 12), arc(0.5, 0.27, 0.4, 0.27, math.pi / 2, math.pi * 2.5, 12) },
	[9] = { join(arc(0.5, 0.71, 0.38, 0.29, 0, math.pi * 2, 12), line(0.88, 0.71, 0.72, 0)) },
} :: { [number]: { { Vector2 } } }

-- The strokes of digit `d` written `height` tall with its bottom left at
-- board position (`left`, `bottom`): a list of segments { from, to }.
function ChalkBoard.segments(d: number, left: number, bottom: number, height: number): { { Vector3 } }
	local width = height * ChalkBoard.DIGIT_WIDTH / ChalkBoard.NUMBER_HEIGHT
	local out = {}
	for _, stroke in ChalkBoard.DIGITS[d] do
		for i = 1, #stroke - 1 do
			local a, b = stroke[i], stroke[i + 1]
			-- Where two strokes join at the same point there is nothing to draw.
			if math.abs(a.X - b.X) + math.abs(a.Y - b.Y) < 1e-3 then continue end
			table.insert(out, {
				ChalkBoard.onBoard(left + a.X * width, bottom + a.Y * height),
				ChalkBoard.onBoard(left + b.X * width, bottom + b.Y * height),
			})
		end
	end
	return out
end

-- The digits of a count, most significant first.
function ChalkBoard.digits(count: number): { number }
	local text = tostring(math.max(0, math.floor(count)))
	local out = {}
	for i = 1, #text do table.insert(out, tonumber(string.sub(text, i, i)) :: number) end
	return out
end

-- How far a gift moves the count: up for gifts that would break the
-- mountain, down for gifts that add stone. A Rose is 2, 100 coins 20, a
-- Galaxy 63, 10,000 coins 200 (times the strength and each gift of a combo).
function ChalkBoard.giftAmount(rocks: number, coins: number, count: number, strength: number?): number
	if rocks == 0 then return 0 end
	local amount = math.max(1, math.floor(2 * math.sqrt(math.max(coins, 1)) * (strength or 1) + 0.5)) * math.max(1, math.floor(count))
	return if rocks > 0 then amount else -amount
end

ChalkBoard.tier = GiftTier.forCoins

-- True if a gift called `gift` starts the reset countdown.
function ChalkBoard.isResetGift(gift: string?, resetGift: string): boolean
	return gift ~= nil and resetGift ~= "" and string.lower(gift) == string.lower(resetGift)
end

-- True if a gift saves the count while the countdown runs: worth at least
-- `saveCoins` and not the reset gift itself.
function ChalkBoard.isSaveGift(gift: string?, coins: number, resetGift: string, saveCoins: number): boolean
	return coins >= saveCoins and not ChalkBoard.isResetGift(gift, resetGift)
end

-- The themes: the board, its frame, the walls and floor, and the chalk.
export type Theme = {
	name: string,
	board: Color3, boardMaterial: Enum.Material,
	frame: Color3, frameMaterial: Enum.Material,
	wall: Color3, trim: Color3, floor: Color3, floorMaterial: Enum.Material,
	chalk: Color3, glow: boolean, -- glowing (neon) chalk
	light: Color3,
}
ChalkBoard.THEMES = {
	classic = {
		name = "Classic", board = Color3.fromRGB(38, 84, 58), boardMaterial = Enum.Material.Slate,
		frame = Color3.fromRGB(150, 104, 62), frameMaterial = Enum.Material.Wood,
		wall = Color3.fromRGB(236, 226, 200), trim = Color3.fromRGB(150, 104, 62), floor = Color3.fromRGB(176, 128, 82), floorMaterial = Enum.Material.WoodPlanks,
		chalk = Color3.fromRGB(246, 246, 238), glow = false, light = Color3.fromRGB(255, 244, 222),
	},
	blackboard = {
		name = "Blackboard", board = Color3.fromRGB(32, 34, 36), boardMaterial = Enum.Material.Slate,
		frame = Color3.fromRGB(92, 64, 44), frameMaterial = Enum.Material.Wood,
		wall = Color3.fromRGB(176, 190, 204), trim = Color3.fromRGB(70, 82, 96), floor = Color3.fromRGB(110, 112, 118), floorMaterial = Enum.Material.Concrete,
		chalk = Color3.fromRGB(250, 250, 250), glow = false, light = Color3.fromRGB(235, 242, 255),
	},
	neon = {
		name = "Neon night", board = Color3.fromRGB(14, 12, 24), boardMaterial = Enum.Material.SmoothPlastic,
		frame = Color3.fromRGB(255, 70, 200), frameMaterial = Enum.Material.Neon,
		wall = Color3.fromRGB(34, 24, 58), trim = Color3.fromRGB(70, 230, 255), floor = Color3.fromRGB(20, 18, 34), floorMaterial = Enum.Material.SmoothPlastic,
		chalk = Color3.fromRGB(110, 240, 255), glow = true, light = Color3.fromRGB(190, 120, 255),
	},
	sakura = {
		name = "Sakura", board = Color3.fromRGB(44, 88, 66), boardMaterial = Enum.Material.Slate,
		frame = Color3.fromRGB(120, 60, 52), frameMaterial = Enum.Material.Wood,
		wall = Color3.fromRGB(252, 226, 232), trim = Color3.fromRGB(196, 108, 128), floor = Color3.fromRGB(196, 150, 120), floorMaterial = Enum.Material.WoodPlanks,
		chalk = Color3.fromRGB(255, 196, 220), glow = false, light = Color3.fromRGB(255, 232, 240),
	},
	royal = {
		name = "Royal diamond", board = Color3.fromRGB(26, 40, 110), boardMaterial = Enum.Material.Slate,
		frame = Color3.fromRGB(224, 178, 72), frameMaterial = Enum.Material.Foil,
		wall = Color3.fromRGB(242, 240, 235), trim = Color3.fromRGB(224, 178, 72), floor = Color3.fromRGB(230, 226, 218), floorMaterial = Enum.Material.Marble,
		chalk = Color3.fromRGB(255, 220, 120), glow = false, light = Color3.fromRGB(255, 246, 228),
	},
} :: { [string]: Theme }
ChalkBoard.THEME_ORDER = { "classic", "blackboard", "neon", "sakura", "royal" }

function ChalkBoard.theme(name: string?): Theme
	return ChalkBoard.THEMES[name or "classic"] or ChalkBoard.THEMES.classic
end

return ChalkBoard
