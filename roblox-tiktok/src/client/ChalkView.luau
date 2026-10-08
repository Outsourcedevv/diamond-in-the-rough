--!strict
-- Chalkboard Count on this computer: the fixed view of the board, holding to
-- write, the chalk on the board (the count, drawn line by line as it goes up
-- with a stick of chalk at the tip, the goal in the corner, a progress line
-- and the reset countdown, all chalk strokes rather than text), the writer's
-- arm and chalk, the display (count, best and wins, the reset banner and the
-- hold countdown at the goal), the writing speed and theme card (Settings can
-- hide it), and the gift (see ChalkEffects), reset, save and win shows. The
-- classroom is kept out of sight from the other games.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Shared = ReplicatedStorage:WaitForChild("DiamondRush")
local ChalkBoard = require(Shared:WaitForChild("ChalkBoard"))
local Format = require(Shared:WaitForChild("Format"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))
local HoldCountdown = require(script.Parent:WaitForChild("HoldCountdown"))
local ChalkEffects = require(script.Parent:WaitForChild("ChalkEffects"))

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

-- The writing speed as the card shows it: "3 a second", "1.5 a second",
-- "12,000 a second".
function ChalkView.speedText(speed: number): string
	return (if speed % 1 == 0 then Format.commas(speed) else string.format("%.1f", speed)) .. " a second"
end

-- Above this speed the board shows the count about FAST_DRAWS times a second
-- (quick scribbles) instead of writing every number.
ChalkView.FAST_SPEED = 12
ChalkView.FAST_DRAWS = 12

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
	-- Under the win counter (102 to 146).
	local resetBox = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 156), Size = UDim2.fromOffset(440, 70), Visible = false }, gui)
	glass(resetBox, 14)
	resetBox.BackgroundColor3 = Color3.fromRGB(90, 16, 24)
	local resetScale = make("UIScale", { Scale = 1 }, resetBox)
	local resetLabel = make("TextLabel", { Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, Font = FONT_HEAVY,
		TextSize = 32, TextColor3 = RED, Text = "" }, resetBox)
	local saveLabel = make("TextLabel", { Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Font = FONT,
		TextSize = 14, TextColor3 = WHITE, Text = "" }, resetBox)

	-- A big line for gifts, saves and wins.
	local shout = make("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 236), Size = UDim2.fromOffset(700, 46),
		BackgroundTransparency = 1, Font = FONT_HEAVY, TextSize = 38, TextColor3 = GOLD, TextStrokeTransparency = 0.3, TextTransparency = 1, Text = "" }, gui)
	local shoutScale = make("UIScale", { Scale = 1 }, shout)
	-- Who sent what, under a gift show's name.
	local subLine = make("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 240), Size = UDim2.fromOffset(700, 24),
		BackgroundTransparency = 1, Font = FONT, TextSize = 18, TextColor3 = WHITE, TextStrokeTransparency = 0.3, TextTransparency = 1, Text = "" }, gui)
	local shoutSerial = 0
	local function showShout(text: string, colour: Color3, seconds: number, size: number?, sub: string?)
		shoutSerial += 1
		local serial = shoutSerial
		shout.Text = text
		shout.TextColor3 = colour
		shout.TextTransparency = 0
		subLine.Text = sub or ""
		subLine.TextTransparency = if sub then 0 else 1
		shoutScale.Scale = size or 1.8
		TweenService:Create(shoutScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		task.delay(seconds, function()
			if serial == shoutSerial then
				TweenService:Create(shout, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
				TweenService:Create(subLine, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
			end
		end)
	end
	local function pop(scale: number)
		cardScale.Scale = scale
		TweenService:Create(cardScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end

	-- The hold at the goal, under the reset banner's place.
	local hold = HoldCountdown.new(gui, 300, "HOLD THE GOAL")
	local hint = make("TextLabel", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40), Size = UDim2.fromOffset(520, 22), BackgroundTransparency = 1,
		Font = FONT, TextSize = 16, TextColor3 = WHITE, TextStrokeTransparency = 0.4, Text = "Hold the left mouse button, Space or the screen to write" }, gui)

	-- The writing card: speed and theme (Settings can hide it).
	-- Higher on touch screens, clear of Roblox's jump button.
	local settingsCard = make("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, if UserInputService.TouchEnabled then -190 else -36),
		Size = UDim2.fromOffset(290, 178) }, gui)
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
		local fraction = ChalkBoard.speedFraction(speed)
		fill.Size = UDim2.fromScale(fraction, 1)
		knob.Position = UDim2.fromScale(fraction, 0.5)
		speedValue.Text = ChalkView.speedText(speed)
	end
	local function speedFromScreen(x: number, done: boolean)
		local fraction = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
		speed = ChalkBoard.speedAt(fraction)
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
	local function refreshCard()
		settingsCard.Visible = player:GetAttribute("HideChalkCard") ~= true
	end
	player:GetAttributeChangedSignal("HideChalkCard"):Connect(refreshCard)
	refreshCard()

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
	-- Drawing: each chalk line grows from its start to its end, one after
	-- another, with a stick of chalk at the tip and a scratch as it goes.
	type Growing = { part: Part, a: Vector3, b: Vector3, width: number, start: number, finish: number, begun: boolean }
	local growing: { Growing } = {}
	local tip = make("Part", { Name = "ChalkTip", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.1, 0.26, 0.26), Material = Enum.Material.SmoothPlastic,
		Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Transparency = 1 }, effects)
	-- A line from `a` to `b` drawn between `start` and `finish` seconds from now.
	local function drawStroke(a: Vector3, b: Vector3, width: number, colour: Color3, glow: boolean, start: number, finish: number): Part
		local p = stroke(drawing, a, b, width, colour, glow)
		if finish > 0 then
			p.Transparency = 1
			local now = os.clock()
			table.insert(growing, { part = p, a = a, b = b, width = width, start = now + start, finish = now + math.max(finish, start + 0.01), begun = false })
		end
		return p
	end
	-- Where the chalk last touched the board, and when: the writer's hand follows it.
	local chalkPoint: Vector3? = nil
	local chalkPointAt = 0
	local function growStrokes()
		local now = os.clock()
		local at: Vector3? = nil
		for k = #growing, 1, -1 do
			local g = growing[k]
			if g.part.Parent == nil then
				table.remove(growing, k)
				continue
			end
			local u = math.clamp((now - g.start) / (g.finish - g.start), 0, 1)
			if u <= 0 then continue end
			if not g.begun then
				g.begun = true
				Sounds.play("chalk", g.a)
			end
			local reach = g.a + (g.b - g.a) * u
			local length = (reach - g.a).Magnitude
			g.part.Size = Vector3.new(g.width, g.width, math.max(0.05, length) + g.width * 0.8)
			g.part.CFrame = CFrame.lookAt((g.a + reach) / 2, g.b)
			g.part.Transparency = 0.04
			if u >= 1 then
				table.remove(growing, k)
			else
				at = reach
			end
		end
		if at then
			chalkPoint = at
			chalkPointAt = now
			tip.Color = theme().chalk
			tip.Transparency = 0
			-- Held at an angle, its end on the board.
			tip.CFrame = CFrame.new(at + Vector3.new(0.3, -0.25, 0.55)) * CFrame.Angles(0, math.rad(60), math.rad(35))
			if math.random() < 0.15 then dust(at, theme().chalk, 1, { 0.3, 1 }) end
		elseif tip.Transparency < 1 then
			tip.Transparency = 1
		end
	end
	-- Writes digit `d` in slot `i` of `n`: its lines drawn one after another
	-- over `seconds`, starting `delay` seconds from now (all at once if 0).
	local function writeSlot(i: number, n: number, d: number, seconds: number, delay: number?)
		local look = theme()
		local lefts = ChalkBoard.digitLefts(n)
		local bottom = ChalkBoard.NUMBER_Y - ChalkBoard.NUMBER_HEIGHT / 2
		local segments = ChalkBoard.segments(d, lefts[i], bottom, ChalkBoard.NUMBER_HEIGHT)
		local total = 0
		for _, seg in segments do total += (seg[2] - seg[1]).Magnitude end
		local parts: { Part } = {}
		local done = delay or 0
		for _, seg in segments do
			local share = if seconds > 0 then seconds * (seg[2] - seg[1]).Magnitude / math.max(total, 1e-3) else 0
			table.insert(parts, drawStroke(seg[1], seg[2], ChalkView.STROKE, look.chalk, look.glow, done, if seconds > 0 then done + share else 0))
			done += share
		end
		slots[i] = { digit = d, parts = parts }
		if seconds > 0 then
			revealSerial += 1
			local serial = revealSerial
			task.delay(done, function()
				if serial == revealSerial and #segments > 0 then dust(segments[#segments][2], look.chalk, 3, { 0.5, 2 }) end
			end)
		end
	end
	-- Draws the count: only the digits that changed are written again, unless
	-- the number of digits changed. Each takes `seconds`, one after another.
	local function drawCount(count: number, seconds: number)
		local digits = ChalkBoard.digits(math.min(count, 10 ^ ChalkBoard.MAX_DIGITS - 1))
		local delay = 0
		if #digits ~= #slots then
			clearSlots()
			for i, d in digits do
				writeSlot(i, #digits, d, seconds, delay)
				delay += seconds
			end
		else
			for i, d in digits do
				if slots[i].digit ~= d then
					for _, p in slots[i].parts do p:Destroy() end
					writeSlot(i, #digits, d, seconds, delay)
					delay += seconds
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
		-- The seconds start just right of the clock (smallNumber lines up their right edge).
		local count = #ChalkBoard.digits(seconds)
		local total = 2 * (count * ChalkBoard.DIGIT_WIDTH + (count - 1) * ChalkBoard.DIGIT_GAP) / ChalkBoard.NUMBER_HEIGHT
		smallNumber(countdownParts, seconds, left + 1.6 + total, top, 2, colour, true)
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
	local holdDrawUntil = 0
	local function sweep(full: boolean, seconds: number)
		local look = theme()
		local eraser = make("Part", { Name = "SweepEraser", Size = Vector3.new(2.6, 1.2, 0.8), Color = Color3.fromRGB(96, 66, 42), Material = Enum.Material.Wood,
			Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }, effects)
		-- The board shows the old count until the eraser has passed over it.
		holdDrawUntil = math.max(holdDrawUntil, os.clock() + seconds * 0.6)
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
	-- The shake is added by the classroom camera each frame (below), so it is never overwritten.
	local shakeDegrees, shakeStart, shakeSeconds = 0, 0, 1
	local function camShake(degrees: number, seconds: number)
		local now = os.clock()
		local left = shakeDegrees * math.max(0, 1 - (now - shakeStart) / shakeSeconds)
		if degrees < left then return end
		shakeDegrees, shakeStart, shakeSeconds = degrees, now, seconds
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
	-- A gift: its show (see ChalkEffects) plays on the board, and the number
	-- changes when the show hits it.
	local effectContext: ChalkEffects.Context = {
		chalk = theme().chalk,
		glow = theme().glow,
		digits = function(): { BasePart }
			local list = {}
			for _, slot in slots do
				for _, p in slot.parts do table.insert(list, p) end
			end
			return list
		end,
		drawStroke = drawStroke,
		shake = function(degrees: number, seconds: number) camShake(degrees, seconds) end,
	}
	local function onGift(data: any)
		if not active or type(data) ~= "table" then return end
		local coins = tonumber(data.coins) or 1
		local tier = ChalkBoard.tier(coins, data.tier)
		local amount = tonumber(data.amount) or 0
		local up = data.up == true
		local look = theme()
		effectContext.chalk = look.chalk
		effectContext.glow = look.glow
		local impact = ChalkEffects.play(tier, up, effectContext)
		-- The board keeps the old number until the show hits it.
		holdDrawUntil = math.max(holdDrawUntil, os.clock() + impact)
		local title = (if up then ChalkEffects.UP_TITLES else ChalkEffects.DOWN_TITLES)[tier]
		local sub = string.format("%s sent %s  ·  %s%s", tostring(data.name or "Someone"), tostring(data.gift or "a gift"),
			if amount > 0 then "+" else "", Format.commas(amount))
		showShout(title, if up then GREEN else RED, 2 + tier * 0.4, 1 + tier * 0.2, sub)
		task.delay(impact, function()
			if active then pop(1.1 + tier * 0.05) end
		end)
	end
	local function onReset(data: any)
		if not active or type(data) ~= "table" then return end
		if data.state == "started" then
			Sounds.play("rumble")
			showShout(string.format("%s sent the RESET!", tostring(data.name or "Someone")), RED, 3, 2.2)
			camShake(1.4, 0.8)
			resetScale.Scale = 1.6
			TweenService:Create(resetScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		elseif data.state == "saved" then
			Sounds.play("chime")
			showShout(string.format("SAVED BY %s!", string.upper(tostring(data.name or "someone"))), GREEN, 3, 2.2)
			local middle = ChalkBoard.onBoard(0, ChalkBoard.NUMBER_Y) + Vector3.new(0, 0, 0.5)
			for k = 1, 5 do
				task.delay(k * 0.1, function() burst(middle + Vector3.new((k - 3) * 4, 0, 0), GREEN, 30) end)
			end
		elseif data.state == "wiped" then
			Sounds.play("boom")
			showShout("THE BOARD WAS WIPED!", RED, 3, 2)
			camShake(1.2, 0.6)
		end
	end
	local function onWipe(_data: any)
		if not active then return end
		Sounds.play("erase")
		task.delay(0.6, function() if active then Sounds.play("erase") end end)
		sweep(true, 1.4)
	end
	local function onWin(data: any)
		if not active or type(data) ~= "table" then return end
		Sounds.play("cheer")
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
	-- The mouse and the screen (clicks on buttons don't write).
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if active and not processed and isWriteInput(input) and input.KeyCode ~= Enum.KeyCode.Space and UserInputService:GetFocusedTextBox() == nil then setHeld(true) end
	end)
	-- Space is the jump key, which Roblox's controls take, so in the classroom
	-- it is taken first (bound while writing); bound keys never fire while
	-- typing in chat.
	local WRITE_ACTION = "ChalkboardWrite"
	local function onWriteKey(_name: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
		if inputState == Enum.UserInputState.Begin then
			setHeld(true)
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			setHeld(false)
		end
		return Enum.ContextActionResult.Sink
	end
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
	local wasHolding = false
	local lastDraw = 0
	-- The writer's right hand follows the chalk (an IKControl moves the arm to
	-- an invisible point on the board), and they step along the board to the
	-- digit being written. Only this player's own game does this.
	local handTarget = make("Part", { Name = "ChalkHandTarget", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
		Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2) }, drawing)
	local ik: IKControl? = nil
	local function handIK(): IKControl?
		if ik and ik.Parent then return ik end
		ik = nil
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local upper = character and character:FindFirstChild("RightUpperArm")
		local hand = character and character:FindFirstChild("RightHand")
		if humanoid == nil or upper == nil or hand == nil then return nil end -- R6: the old wiggle instead
		ik = make("IKControl", { Name = "ChalkHand", Type = Enum.IKControlType.Position, ChainRoot = upper, EndEffector = hand,
			Target = handTarget, SmoothTime = 0.04, Weight = 1, Enabled = false }, humanoid)
		return ik
	end
	local function writeWithHand(dt: number): boolean
		local control = handIK()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if control == nil or root == nil or not root:IsA("BasePart") then return false end
		-- The hand on the chalk while it writes; between numbers it hovers by
		-- the last stroke, a little off the board.
		local point = chalkPoint or ChalkBoard.onBoard(ChalkBoard.writerX(0) + 2, ChalkBoard.NUMBER_Y)
		local resting = os.clock() - chalkPointAt > 0.15
		handTarget.Position = point + Vector3.new(0, 0, if resting then 0.9 else 0.35)
		control.Enabled = true
		-- Step along the board so the hand reaches the digit being written.
		local want = ChalkBoard.ORIGIN.X + ChalkBoard.writerX(point.X - ChalkBoard.ORIGIN.X)
		local here = root.Position
		local x = here.X + (want - here.X) * math.min(1, dt * 6)
		local at = Vector3.new(x, here.Y, here.Z)
		root.CFrame = CFrame.lookAt(at, at - Vector3.new(0, 0, 1))
		return true
	end
	local function restHand()
		if ik then ik.Enabled = false end
	end
	RunService.RenderStepped:Connect(function(dt: number)
		if not active then return end
		-- A steady view of the writer and the board (gifts may shake it).
		local camera = workspace.CurrentCamera
		if camera then
			if camera.CameraType ~= Enum.CameraType.Scriptable then camera.CameraType = Enum.CameraType.Scriptable end
			local t = os.clock()
			local frame = ChalkBoard.cameraFrame()
			local shook = t - shakeStart
			if shook < shakeSeconds then
				local a = math.rad(shakeDegrees) * (1 - shook / shakeSeconds)
				frame *= CFrame.Angles(math.noise(shook * 18, 1) * a, math.noise(shook * 18, 5) * a, 0)
			end
			camera.CFrame = frame
			-- Roblox draws the most detail round the camera's focus: the board.
			camera.Focus = CFrame.new(ChalkBoard.centre())
		end
		-- The mouse stays free in the classroom.
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then UserInputService.MouseBehavior = Enum.MouseBehavior.Default end
		growStrokes()
		-- The hold at the goal: a gift that takes the count down ends it.
		local holdStart = attr("ChalkHoldStart", 0)
		hold.update(holdStart, workspace:GetServerTimeNow())
		if wasHolding and holdStart == 0 and attr("ChalkCount", 0) < attr("ChalkGoal", ChalkBoard.GOAL.default) then
			showShout("KNOCKED DOWN! THE HOLD IS LOST", RED, 3, 1.8)
		end
		wasHolding = holdStart > 0
		-- The arm writes while the server is writing.
		local writingNow = state:GetAttribute("ChalkWriting") == true
		if writingNow then
			if arm == nil then grabArm() end
			local a = arm
			if writeWithHand(dt) then
				-- The IKControl moves the arm (R15); the shoulder stays as it is.
				if a and a.motor.Parent then a.motor.C0 = a.base end
			elseif a then
				local t = os.clock() * math.min(30, 6 + speed * 2)
				local wiggle = CFrame.Angles(math.sin(t) * 0.12, math.cos(t * 1.3) * 0.1, 0)
				a.motor.C0 = a.base * (if a.r15 then CFrame.Angles(2.3, 0, 0) else CFrame.Angles(0, 0, 2.3)) * wiggle
			end
		elseif arm then
			releaseArm()
			restHand()
		end
		hint.Visible = not writingNow and attr("ChalkCount", 0) < 3
		-- The count, goal, progress and countdown on the board.
		local count = attr("ChalkCount", 0)
		local fast = writingNow and speed > ChalkView.FAST_SPEED
		if count ~= shownCount and os.clock() >= holdDrawUntil and (not fast or os.clock() - lastDraw >= 1 / ChalkView.FAST_DRAWS) then
			lastDraw = os.clock()
			local stepUp = count == shownCount + 1
			-- Writing draws the next number at the writing speed; very fast
			-- writing scribbles the changed digits a dozen times a second; a
			-- jump (a gift) draws each changed digit quickly.
			drawCount(count, if fast then 0.012 elseif stepUp then ChalkView.writeSeconds(speed) elseif shownCount >= 0 then 0.22 else 0)
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
			ContextActionService:BindActionAtPriority(WRITE_ACTION, onWriteKey, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space)
			redrawAll()
		else
			ContextActionService:UnbindAction(WRITE_ACTION)
			setHeld(false)
			releaseArm()
			restHand()
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
		ik = nil
		setHeld(false)
	end)

	return { setActive = setActive, onGift = onGift, onReset = onReset, onWipe = onWipe, onWin = onWin }
end

return ChalkView
