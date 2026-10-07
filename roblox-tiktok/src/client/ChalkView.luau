--!strict
-- Chalkboard Count on this computer: the classroom camera, holding to write,
-- the chalk on the board (the count, written stroke by stroke as it goes up,
-- the goal in the corner, a progress line and the reset countdown, all drawn
-- with chalk strokes rather than text), the writer's arm and chalk, the
-- display (count, best and wins, the camera's REC light, the reset banner),
-- the writing speed and theme card, and the gift, reset, save and win shows.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local Shared = ReplicatedStorage:WaitForChild("DiamondRush")
local ChalkBoard = require(Shared:WaitForChild("ChalkBoard"))
local Format = require(Shared:WaitForChild("Format"))

local ChalkView = {}

local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(246, 200, 92)
local GREEN = Color3.fromRGB(118, 230, 160)
local RED = Color3.fromRGB(255, 84, 84)
local MUTED = Color3.fromRGB(168, 174, 190)
local PANEL = Color3.fromRGB(16, 18, 26)
local SELECTED = Color3.fromRGB(64, 128, 236)
local BUTTON = Color3.fromRGB(46, 50, 68)
local FONT = Enum.Font.GothamBold
local FONT_MEDIUM = Enum.Font.GothamMedium
local FONT_HEAVY = Enum.Font.GothamBlack
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
ChalkView.TEXTURES = { smoke = SMOKE, spark = SPARK }
ChalkView.STROKE = 0.34 -- the big number's chalk line width
ChalkView.SMALL_STROKE = 0.16

-- What the display says.
function ChalkView.countText(count: number, goal: number): string
	return string.format("%s / %s", Format.commas(count), Format.commas(goal))
end

function ChalkView.resetText(secondsLeft: number): string
	local s = math.max(0, math.ceil(secondsLeft))
	return string.format("RESET IN %d:%02d", s // 60, s % 60)
end

function ChalkView.saveText(saveCoins: number): string
	return string.format("Send a gift of %s+ coins to save the board", Format.commas(saveCoins))
end

-- Seconds to write one number's strokes at `speed` numbers a second.
function ChalkView.writeSeconds(speed: number): number
	return math.clamp(0.8 / math.max(speed, 0.1), 0.04, 0.35)
end

local function make(className: string, properties: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in properties do
		(instance :: any)[key] = value
	end
	if parent ~= nil then instance.Parent = parent end
	return instance
end

local function rounded(parent: Instance, radius: number)
	make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function glass(instance: GuiObject, radius: number)
	instance.BackgroundColor3 = PANEL
	instance.BackgroundTransparency = 0.28
	rounded(instance, radius)
	make("UIStroke", { Thickness = 1, Color = WHITE, Transparency = 0.88, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, instance)
end

-- A chalk line on the board from `a` to `b`.
local function stroke(parent: Instance, a: Vector3, b: Vector3, width: number, colour: Color3, glow: boolean): Part
	local length = math.max(0.05, (b - a).Magnitude)
	local p = Instance.new("Part")
	p.Name = "Chalk"
	p.Size = Vector3.new(width, width, length + width * 0.8)
	p.CFrame = CFrame.lookAt((a + b) / 2, b)
	p.Color = colour
	p.Material = if glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.Transparency = 0.04
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

function ChalkView.start(request: RemoteEvent, state: Instance)
	local player = Players.LocalPlayer
	local active = false
	local function attr(name: string, fallback: any): any
		local value = state:GetAttribute(name)
		return if value == nil then fallback else value
	end
	local function theme(): ChalkBoard.Theme
		return ChalkBoard.theme(attr("ChalkTheme", "classic"))
	end

	-- The display -------------------------------------------------------------------------
	local gui = make("ScreenGui", { Name = "ChalkboardHud", ResetOnSpawn = false, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling },
		player:WaitForChild("PlayerGui"))
	local card = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(320, 92) }, gui)
	glass(card, 14)
	local cardScale = make("UIScale", { Scale = 1 }, card)
	make("TextLabel", { Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1, Font = FONT, TextSize = 12,
		TextColor3 = MUTED, Text = "CHALKBOARD COUNT" }, card)
	local countLabel = make("TextLabel", { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Font = FONT_HEAVY,
		TextSize = 26, TextColor3 = WHITE, Text = "" }, card)
	local bar = make("Frame", { Position = UDim2.new(0, 16, 0, 58), Size = UDim2.new(1, -32, 0, 6), BackgroundColor3 = WHITE, BackgroundTransparency = 0.82, BorderSizePixel = 0 }, card)
	rounded(bar, 3)
	local barFill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = GREEN, BorderSizePixel = 0 }, bar)
	rounded(barFill, 3)
	local statsLabel = make("TextLabel", { Position = UDim2.fromOffset(0, 68), Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Font = FONT_MEDIUM,
		TextSize = 13, TextColor3 = MUTED, RichText = true, Text = "" }, card)

	-- The reset countdown banner.
	local resetBox = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 112), Size = UDim2.fromOffset(440, 70), Visible = false }, gui)
	glass(resetBox, 14)
	resetBox.BackgroundColor3 = Color3.fromRGB(90, 16, 24)
	local resetScale = make("UIScale", { Scale = 1 }, resetBox)
	local resetLabel = make("TextLabel", { Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, Font = FONT_HEAVY,
		TextSize = 32, TextColor3 = RED, Text = "" }, resetBox)
	local saveLabel = make("TextLabel", { Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Font = FONT,
		TextSize = 14, TextColor3 = WHITE, Text = "" }, resetBox)

	-- A big line for gifts, saves and wins.
	local shout = make("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 192), Size = UDim2.fromOffset(700, 46),
		BackgroundTransparency = 1, Font = FONT_HEAVY, TextSize = 38, TextColor3 = GOLD, TextStrokeTransparency = 0.3, TextTransparency = 1, Text = "" }, gui)
	local shoutScale = make("UIScale", { Scale = 1 }, shout)
	local shoutSerial = 0
	local function showShout(text: string, colour: Color3, seconds: number, size: number?)
		shoutSerial += 1
		local serial = shoutSerial
		shout.Text = text
		shout.TextColor3 = colour
		shout.TextTransparency = 0
		shoutScale.Scale = size or 1.8
		TweenService:Create(shoutScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		task.delay(seconds, function()
			if serial == shoutSerial then TweenService:Create(shout, TweenInfo.new(0.6), { TextTransparency = 1 }):Play() end
		end)
	end
	local function pop(scale: number)
		cardScale.Scale = scale
		TweenService:Create(cardScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end

	-- The classroom camera's viewfinder: corner marks and a blinking REC light.
	local viewfinder = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
	for _, corner in { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) } do
		local holder = make("Frame", { AnchorPoint = corner, Position = UDim2.new(corner.X, if corner.X == 0 then 24 else -24, corner.Y, if corner.Y == 0 then 60 else -24),
			Size = UDim2.fromOffset(46, 46), BackgroundTransparency = 1 }, viewfinder)
		make("Frame", { AnchorPoint = corner, Position = UDim2.fromScale(corner.X, corner.Y), Size = UDim2.fromOffset(46, 3), BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.25, BorderSizePixel = 0 }, holder)
		make("Frame", { AnchorPoint = corner, Position = UDim2.fromScale(corner.X, corner.Y), Size = UDim2.fromOffset(3, 46), BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.25, BorderSizePixel = 0 }, holder)
	end
	local rec = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -80, 0, 70), Size = UDim2.fromOffset(150, 26), BackgroundTransparency = 1 }, viewfinder)
	local recDot = make("Frame", { Position = UDim2.fromOffset(0, 6), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = RED, BorderSizePixel = 0 }, rec)
	rounded(recDot, 7)
	local recLabel = make("TextLabel", { Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -22, 1, 0), BackgroundTransparency = 1, Font = FONT, TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = WHITE, TextStrokeTransparency = 0.5, Text = "REC" }, rec)
	local hint = make("TextLabel", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40), Size = UDim2.fromOffset(520, 22), BackgroundTransparency = 1,
		Font = FONT, TextSize = 16, TextColor3 = WHITE, TextStrokeTransparency = 0.4, Text = "Hold the left mouse button, Space or the screen to write" }, gui)

	-- The writing card: speed and theme.
	local settingsCard = make("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -36), Size = UDim2.fromOffset(290, 178) }, gui)
	glass(settingsCard, 14)
	make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 10) }, settingsCard)
	make("TextLabel", { Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = MUTED, Text = "WRITING" }, settingsCard)
	make("TextLabel", { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, -80, 0, 18), BackgroundTransparency = 1, Font = FONT_MEDIUM, TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = WHITE, Text = "Writing speed" }, settingsCard)
	local speedValue = make("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 22), Size = UDim2.fromOffset(80, 18), BackgroundTransparency = 1,
		Font = FONT, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = WHITE, Text = "" }, settingsCard)
	local speedHit = make("TextButton", { Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Text = "", AutoButtonColor = false }, settingsCard)
	local track = make("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.82, BorderSizePixel = 0 }, speedHit)
	rounded(track, 3)
	local fill = make("Frame", { Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = SELECTED, BorderSizePixel = 0 }, track)
	rounded(fill, 3)
	local knob = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, track)
	rounded(knob, 9)
	make("TextLabel", { Position = UDim2.fromOffset(0, 74), Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Font = FONT, TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = MUTED, Text = "THEME" }, settingsCard)
	local themeButtons: { [string]: TextButton } = {}
	for i, key in ChalkBoard.THEME_ORDER do
		local row, col = (i - 1) // 3, (i - 1) % 3
		local button = make("TextButton", { Position = UDim2.new(col / 3, 2, 0, 94 + row * 36), Size = UDim2.new(1 / 3, -4, 0, 30), BackgroundColor3 = BUTTON,
			Font = FONT, TextSize = 12, TextColor3 = WHITE, TextWrapped = true, Text = ChalkBoard.THEMES[key].name }, settingsCard)
		rounded(button, 8)
		button.Activated:Connect(function() request:FireServer("setChalkTheme", key) end)
		themeButtons[key] = button
	end

	local speed = attr("ChalkSpeed", ChalkBoard.SPEED.default)
	local draggingSpeed = false
	local lastSent = 0
	local function showSpeed()
		local fraction = (speed - ChalkBoard.SPEED.min) / (ChalkBoard.SPEED.max - ChalkBoard.SPEED.min)
		fill.Size = UDim2.fromScale(fraction, 1)
		knob.Position = UDim2.fromScale(fraction, 0.5)
		speedValue.Text = (if speed % 1 == 0 then tostring(speed) else string.format("%.1f", speed)) .. " a second"
	end
	local function speedFromScreen(x: number, done: boolean)
		local fraction = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
		speed = math.floor((ChalkBoard.SPEED.min + fraction * (ChalkBoard.SPEED.max - ChalkBoard.SPEED.min)) * 2 + 0.5) / 2
		showSpeed()
		local now = os.clock()
		if done or now - lastSent > 0.25 then
			lastSent = now
			request:FireServer("setChalkSpeed", speed)
		end
	end
	speedHit.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingSpeed = true
			speedFromScreen(input.Position.X, false)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if draggingSpeed and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			speedFromScreen(input.Position.X, false)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if draggingSpeed and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			draggingSpeed = false
			speedFromScreen(input.Position.X, true)
		end
	end)
	local function refreshSettings()
		if not draggingSpeed then speed = attr("ChalkSpeed", ChalkBoard.SPEED.default) end
		showSpeed()
		local current = attr("ChalkTheme", "classic")
		for key, button in themeButtons do
			button.BackgroundColor3 = if key == current then SELECTED else BUTTON
		end
	end
	state:GetAttributeChangedSignal("ChalkSpeed"):Connect(refreshSettings)
	refreshSettings()

	-- The chalk on the board -----------------------------------------------------------------
	local drawing = make("Folder", { Name = "ChalkDrawing" }, workspace)
	local effects = make("Folder", { Name = "ChalkEffects" }, workspace)
	type Slot = { digit: number, parts: { Part } }
	local slots: { Slot } = {}
	local shownCount = -1
	local revealSerial = 0
	local function clearSlots()
		for _, slot in slots do
			for _, p in slot.parts do p:Destroy() end
		end
		table.clear(slots)
	end
	local function dust(at: Vector3, colour: Color3, count: number, speedRange: { number })
		local spot = make("Attachment", { Position = at }, workspace.Terrain)
		Debris:AddItem(spot, 2.5)
		local puff = make("ParticleEmitter", {
			Texture = SMOKE, Color = ColorSequence.new(colour), LightEmission = 0.3,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1.6) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.6, 1.4), Speed = NumberRange.new(speedRange[1], speedRange[2]), SpreadAngle = Vector2.new(70, 70),
			Acceleration = Vector3.new(0, -2, 0), Drag = 3, Enabled = false,
		}, spot)
		puff:Emit(count)
	end
	-- Writes digit `d` in slot `i` of `n`, its strokes appearing one by one over `seconds`.
	local function writeSlot(i: number, n: number, d: number, seconds: number)
		local look = theme()
		local lefts = ChalkBoard.digitLefts(n)
		local bottom = ChalkBoard.NUMBER_Y - ChalkBoard.NUMBER_HEIGHT / 2
		local segments = ChalkBoard.segments(d, lefts[i], bottom, ChalkBoard.NUMBER_HEIGHT)
		local parts: { Part } = {}
		for _, seg in segments do
			local p = stroke(drawing, seg[1], seg[2], ChalkView.STROKE, look.chalk, look.glow)
			if seconds > 0 then p.Transparency = 1 end
			table.insert(parts, p)
		end
		slots[i] = { digit = d, parts = parts }
		if seconds > 0 then
			revealSerial += 1
			local serial = revealSerial
			local step = seconds / math.max(1, #parts)
			for k, p in parts do
				task.delay(step * (k - 1), function()
					if p.Parent then p.Transparency = 0.04 end
					if k == #parts and serial == revealSerial then dust(segments[k][2], look.chalk, 3, { 0.5, 2 }) end
				end)
			end
		end
	end
	-- Draws the count: only the digits that changed are written again, unless
	-- the number of digits changed.
	local function drawCount(count: number, seconds: number)
		local digits = ChalkBoard.digits(math.min(count, 10 ^ ChalkBoard.MAX_DIGITS - 1))
		if #digits ~= #slots then
			clearSlots()
			for i, d in digits do writeSlot(i, #digits, d, if i == #digits then seconds else 0) end
		else
			for i, d in digits do
				if slots[i].digit ~= d then
					for _, p in slots[i].parts do p:Destroy() end
					writeSlot(i, #digits, d, seconds)
				end
			end
		end
		shownCount = count
	end

	-- The goal, top right, with a drawn target beside it; the progress line;
	-- the countdown, top left, with a drawn clock beside it.
	local cornerParts: { Part } = {}
	local progressPart: Part? = nil
	local countdownParts: { Part } = {}
	local shownGoal, shownCountdown = -1, -1
	local function ring(parts: { Part }, cx: number, cy: number, r: number, colour: Color3, glow: boolean, width: number)
		local steps = 14
		for k = 0, steps - 1 do
			local a0, a1 = k / steps * math.pi * 2, (k + 1) / steps * math.pi * 2
			table.insert(parts, stroke(drawing, ChalkBoard.onBoard(cx + math.cos(a0) * r, cy + math.sin(a0) * r),
				ChalkBoard.onBoard(cx + math.cos(a1) * r, cy + math.sin(a1) * r), width, colour, glow))
		end
	end
	local function smallNumber(parts: { Part }, value: number, right: number, middleY: number, height: number, colour: Color3, glow: boolean)
		local digits = ChalkBoard.digits(value)
		local width = height * ChalkBoard.DIGIT_WIDTH / ChalkBoard.NUMBER_HEIGHT
		local gap = height * ChalkBoard.DIGIT_GAP / ChalkBoard.NUMBER_HEIGHT
		local total = #digits * width + (#digits - 1) * gap
		local lefts = ChalkBoard.digitLefts(#digits, height, right - total / 2)
		for i, d in digits do
			for _, seg in ChalkBoard.segments(d, lefts[i], middleY - height / 2, height) do
				table.insert(parts, stroke(drawing, seg[1], seg[2], ChalkView.SMALL_STROKE, colour, glow))
			end
		end
	end
	local function drawGoal()
		for _, p in cornerParts do p:Destroy() end
		table.clear(cornerParts)
		local look = theme()
		local goal = attr("ChalkGoal", ChalkBoard.GOAL.default)
		local top = ChalkBoard.BOARD_BOTTOM + ChalkBoard.BOARD_HEIGHT - 1.6
		local right = ChalkBoard.BOARD_WIDTH / 2 - 1.2
		smallNumber(cornerParts, goal, right, top, 1.8, look.chalk, look.glow)
		local digits = #ChalkBoard.digits(goal)
		local width = digits * 1.8 * (ChalkBoard.DIGIT_WIDTH + ChalkBoard.DIGIT_GAP) / ChalkBoard.NUMBER_HEIGHT
		local cx = right - width - 1.3
		ring(cornerParts, cx, top, 0.9, look.chalk, look.glow, ChalkView.SMALL_STROKE)
		ring(cornerParts, cx, top, 0.4, look.chalk, look.glow, ChalkView.SMALL_STROKE)
		shownGoal = goal
	end
	local function drawProgress(count: number)
		local goal = math.max(1, attr("ChalkGoal", ChalkBoard.GOAL.default))
		local look = theme()
		local half = ChalkBoard.BOARD_WIDTH / 2 - 1.5
		local y = ChalkBoard.BOARD_BOTTOM + 1.1
		local fraction = math.clamp(count / goal, 0, 1)
		if progressPart then progressPart:Destroy() end
		progressPart = if fraction > 0 then stroke(drawing, ChalkBoard.onBoard(-half, y), ChalkBoard.onBoard(-half + 2 * half * fraction, y), 0.22, look.chalk, look.glow) else nil
	end
	local function drawCountdown(seconds: number)
		if seconds == shownCountdown then return end
		shownCountdown = seconds
		for _, p in countdownParts do p:Destroy() end
		table.clear(countdownParts)
		if seconds < 0 then return end
		local top = ChalkBoard.BOARD_BOTTOM + ChalkBoard.BOARD_HEIGHT - 1.7
		local left = -ChalkBoard.BOARD_WIDTH / 2 + 2.2
		local colour = Color3.fromRGB(255, 110, 110)
		ring(countdownParts, left, top, 1, colour, true, ChalkView.SMALL_STROKE)
		table.insert(countdownParts, stroke(drawing, ChalkBoard.onBoard(left, top), ChalkBoard.onBoard(left, top + 0.7), ChalkView.SMALL_STROKE, colour, true))
		table.insert(countdownParts, stroke(drawing, ChalkBoard.onBoard(left, top), ChalkBoard.onBoard(left + 0.5, top), ChalkView.SMALL_STROKE, colour, true))
		smallNumber(countdownParts, seconds, left + 3.4, top, 2, colour, true)
	end
	local function redrawAll()
		clearSlots()
		shownCount = -1
		drawCount(attr("ChalkCount", 0), 0)
		drawGoal()
		drawProgress(attr("ChalkCount", 0))
		shownCountdown = -2
	end

	-- The eraser sweeps across the board (a wipe), or over the number (a gift down).
	local function sweep(full: boolean, seconds: number)
		local look = theme()
		local eraser = make("Part", { Name = "SweepEraser", Size = Vector3.new(2.6, 1.2, 0.8), Color = Color3.fromRGB(96, 66, 42), Material = Enum.Material.Wood,
			Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }, effects)
		local passes = if full then 4 else 2
		local half = if full then ChalkBoard.BOARD_WIDTH / 2 - 2 else 9
		local lowY = if full then ChalkBoard.BOARD_BOTTOM + 1.5 else ChalkBoard.NUMBER_Y - 2.4
		local highY = if full then ChalkBoard.BOARD_BOTTOM + ChalkBoard.BOARD_HEIGHT - 1.5 else ChalkBoard.NUMBER_Y + 2.4
		local start = os.clock()
		local connection: RBXScriptConnection? = nil
		connection = RunService.RenderStepped:Connect(function()
			local t = math.clamp((os.clock() - start) / seconds, 0, 1)
			local pass = math.min(passes - 1, math.floor(t * passes))
			local u = t * passes - pass
			local x = if pass % 2 == 0 then -half + 2 * half * u else half - 2 * half * u
			local y = highY + (lowY - highY) * ((pass + u) / passes)
			local at = ChalkBoard.onBoard(x, y) + Vector3.new(0, 0, 0.4)
			eraser.CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.sin(t * 40) * 0.15)
			if math.random() < 0.35 then dust(at, look.chalk, 2, { 1, 3 }) end
			if t >= 1 and connection then
				connection:Disconnect()
				connection = nil
				eraser:Destroy()
			end
		end)
	end

	-- A gift: chalk bursts at the number (more for bigger gifts), or the eraser for gifts down.
	local function camShake(degrees: number, seconds: number)
		local start = os.clock()
		local name = "ChalkShake" .. tostring(start)
		RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 2, function()
			local t = os.clock() - start
			local camera = workspace.CurrentCamera
			if t > seconds or camera == nil then
				RunService:UnbindFromRenderStep(name)
				return
			end
			local a = math.rad(degrees) * (1 - t / seconds)
			camera.CFrame *= CFrame.Angles(math.noise(t * 18, 1) * a, math.noise(t * 18, 5) * a, 0)
		end)
	end
	local function burst(at: Vector3, colour: Color3, count: number)
		local spot = make("Attachment", { Position = at }, workspace.Terrain)
		Debris:AddItem(spot, 2.5)
		local sparks = make("ParticleEmitter", {
			Texture = SPARK, Color = ColorSequence.new(WHITE, colour), LightEmission = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(0.6, 1.3), Speed = NumberRange.new(10, 24), SpreadAngle = Vector2.new(80, 80), Drag = 2.5,
			Acceleration = Vector3.new(0, -8, 0), Enabled = false,
		}, spot)
		sparks:Emit(count)
	end
	local function onGift(data: any)
		if not active or type(data) ~= "table" then return end
		local coins = tonumber(data.coins) or 1
		local tier = ChalkBoard.tier(coins)
		local amount = tonumber(data.amount) or 0
		local look = theme()
		local middle = ChalkBoard.onBoard(0, ChalkBoard.NUMBER_Y) + Vector3.new(0, 0, 0.5)
		if data.up then
			for k = 1, tier do
				task.delay((k - 1) * 0.12, function()
					local offset = Vector3.new((math.random() - 0.5) * 16, (math.random() - 0.5) * 5, 0)
					burst(middle + offset, if k % 2 == 0 then GOLD else look.chalk, 14 + tier * 6)
					dust(middle + offset, look.chalk, 4 + tier, { 2, 6 })
				end)
			end
			showShout(string.format("%s  +%s", tostring(data.name or "Someone"), Format.commas(amount)), GREEN, 2.2, 1 + tier * 0.25)
		else
			sweep(false, 0.5 + tier * 0.1)
			dust(middle, look.chalk, 8 + tier * 4, { 2, 7 })
			showShout(string.format("%s  %s", tostring(data.name or "Someone"), Format.commas(amount)), RED, 2.2, 1 + tier * 0.25)
		end
		if tier >= 3 then camShake(0.4 + tier * 0.25, 0.4 + tier * 0.15) end
		pop(1.1 + tier * 0.05)
	end
	local function onReset(data: any)
		if not active or type(data) ~= "table" then return end
		if data.state == "started" then
			showShout(string.format("%s sent the RESET!", tostring(data.name or "Someone")), RED, 3, 2.2)
			camShake(1.4, 0.8)
			resetScale.Scale = 1.6
			TweenService:Create(resetScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		elseif data.state == "saved" then
			showShout(string.format("SAVED BY %s!", string.upper(tostring(data.name or "someone"))), GREEN, 3, 2.2)
			local middle = ChalkBoard.onBoard(0, ChalkBoard.NUMBER_Y) + Vector3.new(0, 0, 0.5)
			for k = 1, 5 do
				task.delay(k * 0.1, function() burst(middle + Vector3.new((k - 3) * 4, 0, 0), GREEN, 30) end)
			end
		elseif data.state == "wiped" then
			showShout("THE BOARD WAS WIPED!", RED, 3, 2)
			camShake(1.2, 0.6)
		end
	end
	local function onWipe(_data: any)
		if not active then return end
		sweep(true, 1.4)
	end
	local function onWin(data: any)
		if not active or type(data) ~= "table" then return end
		showShout(string.format("YOU REACHED %s!", Format.commas(tonumber(data.goal) or 0)), GOLD, 5, 2.4)
		pop(1.4)
		for k = 1, 8 do
			task.delay(k * 0.25, function()
				local at = ChalkBoard.onBoard((math.random() - 0.5) * 30, ChalkBoard.BOARD_BOTTOM + 2 + math.random() * 10) + Vector3.new(0, 0, 1)
				burst(at, ({ GOLD, GREEN, Color3.fromRGB(255, 120, 200), Color3.fromRGB(110, 200, 255) })[k % 4 + 1], 50)
			end)
		end
	end

	-- Holding to write -----------------------------------------------------------------------
	local held = false
	local function setHeld(on: boolean)
		if on == held then return end
		held = on
		request:FireServer("chalkHold", on)
	end
	local function isWriteInput(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.Space
	end
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if active and not processed and isWriteInput(input) and UserInputService:GetFocusedTextBox() == nil then setHeld(true) end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if isWriteInput(input) then setHeld(false) end
	end)
	UserInputService.WindowFocusReleased:Connect(function() setHeld(false) end)

	-- The writer's arm and chalk: the arm reaches up to the board and scribbles.
	local arm: { motor: Motor6D, base: CFrame, r15: boolean }? = nil
	local chalkStick: Part? = nil
	local function releaseArm()
		if arm then
			if arm.motor.Parent then arm.motor.C0 = arm.base end
			arm = nil
		end
		if chalkStick then
			chalkStick:Destroy()
			chalkStick = nil
		end
	end
	local function grabArm(): boolean
		local character = player.Character
		if character == nil then return false end
		local upper = character:FindFirstChild("RightUpperArm")
		local torso = character:FindFirstChild("Torso")
		local motor = if upper then upper:FindFirstChild("RightShoulder") elseif torso then torso:FindFirstChild("Right Shoulder") else nil
		if motor == nil or not motor:IsA("Motor6D") then return false end
		arm = { motor = motor, base = motor.C0, r15 = upper ~= nil }
		local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
		if hand and hand:IsA("BasePart") then
			local stick = make("Part", { Name = "HeldChalk", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 0.22, 0.22), Color = theme().chalk,
				Material = Enum.Material.SmoothPlastic, CanCollide = false, CanQuery = false, CanTouch = false, Massless = true, CastShadow = false }, character)
			local weld = make("Weld", { Part0 = hand, Part1 = stick, C0 = CFrame.new(0, -hand.Size.Y / 2 - 0.1, -0.2) * CFrame.Angles(0, math.pi / 2, 0.6) }, stick)
			local _ = weld
			chalkStick = stick
		end
		return true
	end
	local recBlink = 0
	RunService.RenderStepped:Connect(function(dt: number)
		if not active then return end
		-- The classroom camera, with a gentle hand-held drift.
		local camera = workspace.CurrentCamera
		if camera then
			if camera.CameraType ~= Enum.CameraType.Scriptable then camera.CameraType = Enum.CameraType.Scriptable end
			local t = os.clock()
			camera.CFrame = ChalkBoard.cameraFrame() * CFrame.Angles(math.sin(t * 0.7) * 0.004, math.sin(t * 0.5) * 0.006, 0)
		end
		-- The REC light blinks and the camera's clock runs.
		recBlink += dt
		recDot.BackgroundTransparency = if recBlink % 1.2 < 0.7 then 0 else 1
		local now = os.date("*t")
		recLabel.Text = string.format("REC  %02d:%02d:%02d", now.hour, now.min, now.sec)
		-- The arm writes while the server is writing.
		local writingNow = state:GetAttribute("ChalkWriting") == true
		if writingNow then
			if arm == nil then grabArm() end
			local a = arm
			if a then
				local t = os.clock() * math.min(30, 6 + speed * 2)
				local wiggle = CFrame.Angles(math.sin(t) * 0.12, math.cos(t * 1.3) * 0.1, 0)
				a.motor.C0 = a.base * (if a.r15 then CFrame.Angles(2.3, 0, 0) else CFrame.Angles(0, 0, 2.3)) * wiggle
			end
		elseif arm then
			releaseArm()
		end
		hint.Visible = not writingNow and attr("ChalkCount", 0) < 3
		-- The count, goal, progress and countdown on the board.
		local count = attr("ChalkCount", 0)
		if count ~= shownCount then
			local stepUp = count == shownCount + 1
			drawCount(count, if stepUp then ChalkView.writeSeconds(speed) else 0)
			drawProgress(count)
			if not stepUp and shownCount >= 0 then dust(ChalkBoard.onBoard(0, ChalkBoard.NUMBER_Y), theme().chalk, 6, { 1, 4 }) end
		end
		if attr("ChalkGoal", 0) ~= shownGoal then
			drawGoal()
			drawProgress(count)
		end
		local ends = attr("ChalkResetEnds", 0)
		local left = if ends > 0 then ends - workspace:GetServerTimeNow() else -1
		drawCountdown(if left >= 0 then math.ceil(left) else -1)
		resetBox.Visible = left >= 0
		if left >= 0 then
			resetLabel.Text = ChalkView.resetText(left)
			saveLabel.Text = ChalkView.saveText(attr("ChalkSaveCoins", ChalkBoard.SAVE_COINS))
			resetLabel.TextTransparency = if left < 10 and (left % 0.5) < 0.25 then 0.4 else 0
		end
		-- The display.
		local goal = attr("ChalkGoal", ChalkBoard.GOAL.default)
		countLabel.Text = ChalkView.countText(count, goal)
		barFill.Size = UDim2.fromScale(math.clamp(count / math.max(1, goal), 0, 1), 1)
		statsLabel.Text = string.format('BEST <font color="#FFFFFF">%s</font>    WINS <font color="#F6C85C">%s</font>',
			Format.commas(attr("ChalkBest", 0)), Format.commas(attr("ChalkWins", 0)))
	end)
	state:GetAttributeChangedSignal("ChalkTheme"):Connect(function()
		refreshSettings()
		if active then redrawAll() end
		if chalkStick then chalkStick.Color = theme().chalk end
	end)

	local function setActive(on: boolean)
		if on == active then return end
		active = on
		gui.Enabled = on
		if on then
			redrawAll()
		else
			setHeld(false)
			releaseArm()
			clearSlots()
			for _, p in cornerParts do p:Destroy() end
			table.clear(cornerParts)
			if progressPart then progressPart:Destroy() end
			progressPart = nil
			drawCountdown(-1)
			local camera = workspace.CurrentCamera
			if camera then camera.CameraType = Enum.CameraType.Custom end
		end
	end
	player.CharacterAdded:Connect(function()
		arm = nil
		chalkStick = nil
		setHeld(false)
	end)

	return { setActive = setActive, onGift = onGift, onReset = onReset, onWipe = onWipe, onWin = onWin }
end

return ChalkView
