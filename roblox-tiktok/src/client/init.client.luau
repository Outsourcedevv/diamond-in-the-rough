--!strict
-- The on-screen display: stone left, round time, the win counter, the hold
-- countdown, the gift feed, the win screen and the streamer's settings panel.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
-- Nobody carries a tool (digging is bare-handed), so Roblox's backpack bar is
-- off: it would otherwise take the number keys, which gifts can be bound to.
pcall(function()
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)
local Shared = ReplicatedStorage:WaitForChild("DiamondRush")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local HoldTimer = require(Shared:WaitForChild("HoldTimer"))
local Skin = require(Shared:WaitForChild("Skin"))
local Keybinds = require(Shared:WaitForChild("Keybinds"))
local FirstPerson = require(script:WaitForChild("FirstPerson"))
local Sounds = require(script:WaitForChild("Sounds"))
-- Everyone arrives in the royal lobby, with a normal camera (see LobbyView).
FirstPerson.setEnabled(player:GetAttribute("InGame") == true)
FirstPerson.start()
require(script:WaitForChild("Sprint")).start()
require(script:WaitForChild("SceneryView")).start()
local State = ReplicatedStorage:WaitForChild("DiamondRushState") :: Configuration
local Remotes = ReplicatedStorage:WaitForChild("DiamondRushRemotes")
local Notify = Remotes:WaitForChild("Notify") :: RemoteEvent
local Request = Remotes:WaitForChild("Request") :: RemoteEvent
local RebuildEffects = require(script:WaitForChild("RebuildEffects"))
local GiftEffects = require(script:WaitForChild("GiftEffects"))
GiftEffects.start(player:WaitForChild("PlayerGui"), State)

-- The rock is drawn here, not replicated from the server: the server sends a
-- snapshot and compact change lists, and MountainView keeps local parts in step.
local MountainView = require(script:WaitForChild("MountainView"))
local MountainSync = Remotes:WaitForChild("MountainSync") :: RemoteEvent
local view = MountainView.new()
view.onRebuild = RebuildEffects.play
view.onRestore = RebuildEffects.restore
MountainSync.OnClientEvent:Connect(function(kind: string, payload: any)
	view:push(kind, payload)
end)
view:start()
-- Ask for the mountain until a snapshot arrives; the first request can reach
-- the server before its handlers are ready.
task.spawn(function()
	repeat
		Request:FireServer("mountainReady")
		task.wait(4)
	until view.round > 0
end)

-- One clean look throughout: Gotham type, dark glass panels with a hairline
-- edge, white text, a pale blue accent and gold for wins.
local FONT = Enum.Font.GothamBold
local FONT_MEDIUM = Enum.Font.GothamMedium
local FONT_HEAVY = Enum.Font.GothamBlack
local WHITE = Color3.fromRGB(255, 255, 255)
local GOLD = Color3.fromRGB(246, 200, 92)
local ACCENT = Color3.fromRGB(132, 212, 255)
local GREEN = Color3.fromRGB(118, 230, 160)
local MUTED = Color3.fromRGB(168, 174, 190)
local PANEL = Color3.fromRGB(16, 18, 26)
local GLASS = 0.28 -- how see-through the HUD's panels are
local BUTTON = Color3.fromRGB(46, 50, 68)
local SELECTED = Color3.fromRGB(64, 128, 236)
local DANGER = Color3.fromRGB(176, 64, 72)

local function attr(name: string, fallback: any): any
	local value = State:GetAttribute(name)
	if value == nil then
		return fallback
	end
	return value
end

local function hexColor(text: string, fallback: Color3): Color3
	local r, g, b = Format.parseHex(text)
	if r == nil or g == nil or b == nil then
		return fallback
	end
	return Color3.fromRGB(r, g, b)
end

local function make(className: string, properties: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in properties do
		(instance :: any)[key] = value
	end
	if parent ~= nil then
		instance.Parent = parent
	end
	return instance
end

local function rounded(parent: Instance, radius: number)
	make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

-- Text changes force a relayout; per-frame labels only update when they differ.
local shownText: { [TextLabel]: string } = {}
local function setText(label: TextLabel, text: string)
	if shownText[label] ~= text then
		shownText[label] = text
		label.Text = text
	end
end

local function outline(parent: Instance, thickness: number)
	make("UIStroke", { Thickness = thickness, Color = Color3.fromRGB(0, 0, 0), Transparency = 0.55 }, parent)
end

-- A dark glass panel with rounded corners and a faint edge.
local function glass(instance: GuiObject, radius: number, transparency: number?)
	instance.BackgroundColor3 = PANEL
	instance.BackgroundTransparency = transparency or GLASS
	instance.BorderSizePixel = 0
	rounded(instance, radius)
	make("UIStroke", { Thickness = 1, Color = WHITE, Transparency = 0.88, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, instance)
end

local gui = make("ScreenGui", {
	Name = "DiamondRushHud",
	ResetOnSpawn = false,
	-- Above the climb's and chalkboard's own cards, so the Y panel and the
	-- settings are never covered (the games menu, 5, stays above).
	DisplayOrder = 2,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, player:WaitForChild("PlayerGui"))

-- Diamond in the Rough's own display (stone, wins, time, the hold countdown
-- and the win card); the feed, settings and streamer panel serve both games.
local roughHud = make("Frame", {
	Name = "RoughHud",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
}, gui)

-- Diamond Climb: its display, sliders, landings and gift rides.
local ClimbView = require(script:WaitForChild("ClimbView"))
local climb = ClimbView.start(Request, State)
-- Chalkboard Count: the view of the board, chalk numbers and its display.
local ChalkView = require(script:WaitForChild("ChalkView"))
local chalk = ChalkView.start(Request, State)

-- The games menu: the game's display, first-person view and hands only show
-- while playing Diamond in the Rough, not in the lobby; Diamond Climb has a
-- third-person camera and its own display, and Chalkboard Count shows the
-- writer and the board from a fixed view.
local LobbyView = require(script:WaitForChild("LobbyView"))
-- The sidebar on the left: gifts, themes, settings and games (started once
-- the settings card below exists).
local Sidebar = require(script:WaitForChild("Sidebar"))
LobbyView.LEFT = Sidebar.PANEL_LEFT
-- How to play: from the lobby board, the games menu or H.
local HowToPlay = require(script:WaitForChild("HowToPlay"))
HowToPlay.start()
LobbyView.start(Request, State, function(place: string)
	gui.Enabled = place ~= "lobby"
	roughHud.Visible = place == "rough"
	FirstPerson.setEnabled(place == "rough")
	climb.setActive(place == "climb")
	chalk.setActive(place == "chalk")
end, function()
	HowToPlay.setOpen(true)
end)
-- The diamond bird flies round the mountain; catching it doubles gifts.
-- Its "click it" label shows only at the mountain, where it can be caught.
require(script:WaitForChild("BirdView")).start(roughHud, State)
-- Cherry petals fall round the camera when the map shows the sakura theme.
require(script:WaitForChild("PetalView")).start(State)

-- Stone left (top centre) -------------------------------------------------------
local stoneBox = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 10),
	Size = UDim2.fromOffset(300, 84),
}, roughHud)
glass(stoneBox, 14)
local stoneTitle = make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 16),
	Position = UDim2.fromOffset(0, 10),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 13,
	TextColor3 = MUTED,
	Text = "STONE LEFT", -- or HAY LEFT (see refreshSkin)
}, stoneBox)
local stoneValue = make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 38),
	Position = UDim2.fromOffset(0, 26),
	BackgroundTransparency = 1,
	Font = FONT_HEAVY,
	TextSize = 36,
	TextColor3 = WHITE,
	Text = "250,000",
}, stoneBox)
local bar = make("Frame", {
	Position = UDim2.new(0, 20, 1, -15),
	Size = UDim2.new(1, -40, 0, 4),
	BackgroundColor3 = WHITE,
	BackgroundTransparency = 0.85,
	BorderSizePixel = 0,
}, stoneBox)
rounded(bar, 2)
local barFill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, bar)
rounded(barFill, 2)

-- Diamond bird bonus: a gold 2X card beside the stone count while it runs.
local boostTag = make("Frame", {
	Position = UDim2.new(0.5, 158, 0, 10),
	Size = UDim2.fromOffset(84, 84),
	Visible = false,
}, roughHud)
glass(boostTag, 14)
local boostStroke = boostTag:FindFirstChildOfClass("UIStroke")
if boostStroke then
	boostStroke.Color = GOLD
	boostStroke.Thickness = 2
	boostStroke.Transparency = 0
end
local boostScale = make("UIScale", { Scale = 1 }, boostTag)
make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 40),
	Position = UDim2.fromOffset(0, 12),
	BackgroundTransparency = 1,
	Font = FONT_HEAVY,
	TextSize = 38,
	TextColor3 = GOLD,
	Text = "2X",
}, boostTag)
local boostTime = make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 18),
	Position = UDim2.fromOffset(0, 54),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 14,
	TextColor3 = WHITE,
	Text = "",
}, boostTag)

-- Win counter: under the stone count, or under the climb's or chalkboard's own
-- display, showing the wins of whichever game is being played -----------------------
local WINS_Y, WINS_Y_HOLDING = 102, 158 -- moves below the hold countdown while it shows
local winsBox = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, WINS_Y),
	Size = UDim2.fromOffset(0, 44),
	AutomaticSize = Enum.AutomaticSize.X,
	Font = FONT_HEAVY,
	TextSize = 26,
	Text = "WINS: 0",
}, gui)
rounded(winsBox, 14)
make("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18) }, winsBox)
local winsStroke = make("UIStroke", { Thickness = 2, Color = GOLD, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, winsBox)

-- Round time, in a small pill under the wins.
local timerLabel = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 154),
	Size = UDim2.fromOffset(0, 26),
	AutomaticSize = Enum.AutomaticSize.X,
	Font = FONT,
	TextSize = 14,
	TextColor3 = WHITE,
	RichText = true,
	Text = "",
}, roughHud)
glass(timerLabel, 13)
make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, timerLabel)

-- Banner, hold countdown and status ----------------------------------------------------
local banner = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 192),
	Size = UDim2.fromOffset(0, 44),
	AutomaticSize = Enum.AutomaticSize.X,
	Font = FONT,
	TextSize = 22,
	TextColor3 = ACCENT,
	Text = "",
	Visible = false,
}, roughHud)
glass(banner, 22, 0.2)
make("UIPadding", { PaddingLeft = UDim.new(0, 22), PaddingRight = UDim.new(0, 22) }, banner)

local countdown = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 10),
	Size = UDim2.fromOffset(320, 140),
	BackgroundTransparency = 1,
	Visible = false,
}, roughHud)
local countHolder = make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 36),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 20,
	TextScaled = true,
	TextColor3 = WHITE,
	Text = "",
}, countdown)
make("UITextSizeConstraint", { MinTextSize = 13, MaxTextSize = 20 }, countHolder)
outline(countHolder, 1.5)
local countNumber = make("TextLabel", {
	Position = UDim2.fromOffset(0, 36),
	Size = UDim2.new(1, 0, 0, 100),
	BackgroundTransparency = 1,
	Font = FONT_HEAVY,
	TextSize = 88,
	TextColor3 = WHITE,
	Text = "10",
}, countdown)
outline(countNumber, 3)
local countScale = make("UIScale", { Scale = 1 }, countNumber)

local status = make("TextLabel", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -14, 1, -10),
	Size = UDim2.fromOffset(520, 20),
	BackgroundTransparency = 1,
	Font = FONT_MEDIUM,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Right,
	TextColor3 = MUTED,
	Text = "",
}, gui)
outline(status, 1)

-- Gift feed (bottom left) -------------------------------------------------------------
local feed = make("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 12, 1, -12),
	Size = UDim2.fromOffset(440, 280),
	BackgroundTransparency = 1,
}, gui)
make("UIListLayout", {
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 5),
}, feed)
local feedOrder = 0

local function addFeed(text: string, stone: number, kind: string)
	feedOrder += 1
	local colour = if kind == "gift" then GOLD elseif kind == "follow" then Color3.fromRGB(255, 140, 180) else ACCENT
	local clean = (text:gsub("[<>&]", ""))
	local row = make("TextLabel", {
		LayoutOrder = feedOrder,
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = FONT_MEDIUM,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = WHITE,
		RichText = true,
		Text = if stone ~= 0
			then string.format('%s   <b><font color="#%s">%s%s</font></b>', clean, (if stone < 0 then GREEN else colour):ToHex(), if stone < 0 then "+" else "-", Format.commas(math.abs(stone)))
			else clean,
	}, feed)
	glass(row, 8)
	make("UISizeConstraint", { MaxSize = Vector2.new(440, 30) }, row)
	make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 12) }, row)
	-- A thin bar in the row's colour along its left edge.
	local edge = make("Frame", {
		Position = UDim2.new(0, -14, 0, 7),
		Size = UDim2.new(0, 3, 1, -14),
		BackgroundColor3 = if stone < 0 then GREEN else colour,
		BorderSizePixel = 0,
	}, row)
	rounded(edge, 2)
	local rows = {}
	for _, child in feed:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(rows, child)
		end
	end
	table.sort(rows, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for index = 1, #rows - 6 do
		rows[index]:Destroy()
	end
	task.delay(7, function()
		if row.Parent then
			local info = TweenInfo.new(0.6)
			local fade = TweenService:Create(row, info, { BackgroundTransparency = 1, TextTransparency = 1 })
			TweenService:Create(edge, info, { BackgroundTransparency = 1 }):Play()
			local edgeStroke = row:FindFirstChildOfClass("UIStroke")
			if edgeStroke then TweenService:Create(edgeStroke, info, { Transparency = 1 }):Play() end
			fade:Play()
			fade.Completed:Wait()
			row:Destroy()
		end
	end)
end

-- Win screen --------------------------------------------------------------------------
local winScreen = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(8, 10, 16),
	BackgroundTransparency = 0.35,
	Visible = false,
	ZIndex = 20,
}, roughHud)
local winCard = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(540, 300),
	ZIndex = 21,
}, winScreen)
glass(winCard, 20, 0.05)
local winScale = make("UIScale", { Scale = 1 }, winCard)
local function winLine(y: number, height: number, font: Enum.Font, size: number, colour: Color3): TextLabel
	return make("TextLabel", {
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		Font = font,
		TextSize = size,
		TextColor3 = colour,
		Text = "",
		ZIndex = 22,
	}, winCard)
end
local winTitle = winLine(30, 48, FONT_HEAVY, 40, ACCENT)
local winWho = winLine(84, 32, FONT, 24, WHITE)
local winTime = winLine(140, 30, FONT_MEDIUM, 20, WHITE)
local winBest = winLine(174, 30, FONT_MEDIUM, 20, GOLD)
local winNewBest = winLine(230, 32, FONT, 18, GREEN)

local function showWin(data: { [string]: any })
	if player:GetAttribute("InGame") == true then Sounds.play("cheer") end
	local words = Skin.words(attr("Skin", "stone"))
	winTitle.Text = string.upper(words.gem) .. " SECURED"
	winWho.Text = tostring(data.winner or "") .. " wins!"
	winTime.Text = "This round: " .. Format.duration(tonumber(data.time) or 0)
	winBest.Text = "Best round: " .. Format.duration(tonumber(data.best) or 0)
	winNewBest.Text = if data.newBest then "NEW BEST TIME" else ""
	winScreen.Visible = true
	winScale.Scale = 0.85
	TweenService:Create(winScale, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(Config.WinScreenSeconds, function()
		winScreen.Visible = false
	end)
end

-- Settings panel (owner / admins only) ------------------------------------------------------
local panel = make("ScrollingFrame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 92),
	-- As tall as the screen allows (Studio's play area can be short), up to 520.
	Size = UDim2.new(0, 340, 1, -104),
	-- The canvas is sized from the list below: Roblox's automatic canvas
	-- leaves out the padding and can miss rows that grow, so the bottom of
	-- the panel (the tests and resets) couldn't be scrolled to.
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ScrollBarThickness = 10,
	ScrollBarImageColor3 = MUTED,
	ScrollBarImageTransparency = 0.2,
	VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
	Visible = false,
	ZIndex = 10,
}, gui)
glass(panel, 14, 0.06)
make("UISizeConstraint", { MaxSize = Vector2.new(340, 520) }, panel)
local PANEL_PAD_TOP, PANEL_PAD_BOTTOM = 10, 12
make("UIPadding", {
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 8),
	PaddingTop = UDim.new(0, PANEL_PAD_TOP),
	PaddingBottom = UDim.new(0, PANEL_PAD_BOTTOM),
}, panel)
local panelList = make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, panel)
local function fitPanelCanvas()
	panel.CanvasSize = UDim2.fromOffset(0, panelList.AbsoluteContentSize.Y + PANEL_PAD_TOP + PANEL_PAD_BOTTOM)
end
panelList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitPanelCanvas)
fitPanelCanvas()
-- The mouse wheel scrolls the panel whenever the pointer is over it, even if
-- something else on screen took the wheel first.
UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
	if processed or input.UserInputType ~= Enum.UserInputType.MouseWheel or not panel.Visible then return end
	local mouse = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
	local corner, size = panel.AbsolutePosition, panel.AbsoluteSize
	if mouse.X < corner.X or mouse.X > corner.X + size.X or mouse.Y < corner.Y or mouse.Y > corner.Y + size.Y then return end
	local most = math.max(0, panel.AbsoluteCanvasSize.Y - panel.AbsoluteWindowSize.Y)
	panel.CanvasPosition = Vector2.new(0, math.clamp(panel.CanvasPosition.Y - input.Position.Z * 60, 0, most))
end)
local panelOrder = 0

local function panelLabel(text: string)
	panelOrder += 1
	make("TextLabel", {
		LayoutOrder = panelOrder,
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		TextColor3 = MUTED,
		Text = text,
		ZIndex = 11,
	}, panel)
end

local function panelBox(text: string, onSubmit: (string) -> ()): TextBox
	panelOrder += 1
	local box = make("TextBox", {
		LayoutOrder = panelOrder,
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = Color3.fromRGB(32, 35, 48),
		Font = FONT_MEDIUM,
		TextSize = 15,
		TextColor3 = WHITE,
		PlaceholderColor3 = Color3.fromRGB(120, 126, 142),
		ClearTextOnFocus = false,
		Text = text,
		ZIndex = 11,
	}, panel)
	rounded(box, 8)
	make("UIStroke", { Thickness = 1, Color = WHITE, Transparency = 0.9, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, box)
	box.FocusLost:Connect(function()
		onSubmit(box.Text)
	end)
	return box
end

local function panelButtons(buttons: { { any } }): { TextButton }
	panelOrder += 1
	local row = make("Frame", {
		LayoutOrder = panelOrder,
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		ZIndex = 11,
	}, panel)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, row)
	local made: { TextButton } = {}
	for _, spec in buttons do
		local button = make("TextButton", {
			Size = UDim2.new(1 / #buttons, -6, 1, 0),
			BackgroundColor3 = BUTTON,
			Font = FONT,
			TextSize = 14,
			TextColor3 = WHITE,
			Text = spec[1],
			ZIndex = 12,
		}, row)
		rounded(button, 8)
		button.Activated:Connect(spec[2])
		table.insert(made, button)
	end
	return made
end

local function send(action: string, value: any)
	Request:FireServer(action, value)
end

-- The full-screen gift settings: every gift, what it does in each game and
-- its key (for TikFinity).
local GiftMenu = require(script:WaitForChild("GiftMenu"))
GiftMenu.start(send, State)
panelLabel("GIFTS")
local openGifts = panelButtons({
	{ "Open gift settings (full screen)", function()
		panel.Visible = false
		GiftMenu.setOpen(true)
	end },
})
openGifts[1].BackgroundColor3 = SELECTED
openGifts[1].TextSize = 16

panelLabel("WIN COUNTER TITLE")
local titleBox = panelBox("", function(text)
	send("setTitle", text)
end)
panelLabel("WINS (of the game you are playing)")
local winsInput = panelBox("", function(text)
	local number = tonumber(text)
	if number then
		send("setWins", number)
	end
end)
panelButtons({
	{ "-1", function() send("addWins", -1) end },
	{ "+1", function() send("addWins", 1) end },
	{ "Reset to 0", function() send("setWins", 0) end },
})
panelLabel("GOAL (0 = no goal)")
local goalBox = panelBox("", function(text)
	local number = tonumber(text)
	if number then
		send("setGoal", number)
	end
end)
panelLabel("TEXT COLOUR (#RRGGBB)")
local textColourBox = panelBox("", function(text)
	send("setTextColor", text)
end)
panelLabel("BACKGROUND COLOUR (#RRGGBB)")
local backgroundBox = panelBox("", function(text)
	send("setBackgroundColor", text)
end)
panelButtons({
	{ "Show / hide counter", function() send("setShowWins", not attr("ShowWins", true)) end },
})
panelLabel("STARTING STONE (next round)")
local stoneBoxInput = panelBox("", function(text)
	local number = tonumber((string.gsub(text, "[,%s]", "")))
	if number then
		send("setStartingStone", number)
	end
end)
panelButtons({
	{ "New round", function() send("newRound") end },
	{ "Reset best time", function() send("resetBest") end },
})
panelLabel("ROCKS PER COIN (gifts without a rule)")
local perCoinBox = panelBox("", function(text)
	local number = tonumber((string.gsub(text, "[,%s]", "")))
	if number then
		send("setPerCoin", number)
	end
end)
panelLabel("ROCKS PER LIKE / FOLLOW / SHARE")
local function amountBox(action: string): TextBox
	return panelBox("", function(text)
		local number = tonumber((string.gsub(text, "[^%d]", "")))
		if number then
			send(action, number)
		end
	end)
end
local perLikeBox = amountBox("setPerLike")
local perFollowBox = amountBox("setPerFollow")
local perShareBox = amountBox("setPerShare")

panelLabel("TEST GIFTS (no TikTok needed)")
local testGifts = {
	{ "Rose · 1", "Rose", 1, 1 },
	{ "Finger Heart · 5", "Finger Heart", 5, 1 },
	{ "Rose x10", "Rose", 1, 10 },
	{ "Doughnut · 30", "Doughnut", 30, 1 },
	{ "Perfume · 20", "Perfume", 20, 1 },
	{ "Hand Hearts · 100", "Hand Hearts", 100, 1 },
	{ "Confetti · 100", "Confetti", 100, 1 },
	{ "Money Gun · 500", "Money Gun", 500, 1 },
	{ "Galaxy · 1,000", "Galaxy", 1000, 1 },
	{ "Doughnut x40", "Doughnut", 30, 40 },
	{ "Galaxy x5", "Galaxy", 1000, 5 },
	{ "Galaxy x10", "Galaxy", 1000, 10 },
	{ "Lion · 29,999", "Lion", 29999, 1 },
	{ "Universe · 34,999", "TikTok Universe", 34999, 1 },
}
panelLabel("Numbers show coins. x10 sends ten separate gifts")
for index = 1, #testGifts, 2 do
	local buttons = {}
	for offset = 0, 1 do
		local gift = testGifts[index + offset]
		if gift then
			table.insert(buttons, { gift[1], function()
				send("testGift", { coins = gift[3], count = gift[4], name = gift[2] })
			end })
		end
	end
	panelButtons(buttons)
end

panelLabel("DIAMOND CLIMB")
panelLabel("While climbing, gifts send you up and adding gifts send you down.")
panelButtons({
	{ "Restart at platform 0", function() send("climbRestart") end },
})
panelLabel("Climb gift strength (platforms per gift)")
local CLIMB_STRENGTHS = { { "Half", 0.5 }, { "Normal", 1 }, { "Double", 2 } }
local strengthButtons = panelButtons({
	{ "Half", function() send("setClimbStrength", 0.5) end },
	{ "Normal", function() send("setClimbStrength", 1) end },
	{ "Double", function() send("setClimbStrength", 2) end },
})
local function refreshStrength()
	local strength = attr("ClimbStrength", 1)
	for i, entry in CLIMB_STRENGTHS do
		strengthButtons[i].BackgroundColor3 = if strength == entry[2] then SELECTED else BUTTON
	end
end
State:GetAttributeChangedSignal("ClimbStrength"):Connect(refreshStrength)
refreshStrength()
panelLabel("Wall health (gifts that push you back past platform 0 hit the wall; when it breaks you lose a win)")
local climbWallBox = panelBox("", function(text)
	local number = tonumber((string.gsub(text, "[,%s]", "")))
	if number then send("setClimbWall", number) end
end)
climbWallBox.PlaceholderText = "e.g. 5,000"
local function refreshWallBox()
	climbWallBox.Text = Format.commas(attr("ClimbWallMax", 5000))
end
State:GetAttributeChangedSignal("ClimbWallMax"):Connect(refreshWallBox)
refreshWallBox()

panelLabel("CHALKBOARD COUNT")
panelLabel("While writing, gifts add numbers and adding gifts rub them out.")
panelLabel("Goal number")
local chalkGoalBox = panelBox("", function(text)
	local number = tonumber((string.gsub(text, "[,%s]", "")))
	if number then send("setChalkGoal", number) end
end)
panelLabel("Reset gift (starts the countdown)")
local chalkResetGiftBox = panelBox("", function(text)
	if text ~= "" then send("setChalkResetGift", text) end
end)
panelLabel("Reset countdown (seconds)")
local chalkResetSecondsBox = panelBox("", function(text)
	local number = tonumber((string.gsub(text, "[^%d]", "")))
	if number then send("setChalkResetSeconds", number) end
end)
panelLabel("Coins that save the board (any other gift)")
local chalkSaveCoinsBox = panelBox("", function(text)
	local number = tonumber((string.gsub(text, "[^%d]", "")))
	if number then send("setChalkSaveCoins", number) end
end)
panelLabel("Chalk gift strength (numbers per gift)")
local chalkStrengthButtons = panelButtons({
	{ "Half", function() send("setChalkStrength", 0.5) end },
	{ "Normal", function() send("setChalkStrength", 1) end },
	{ "Double", function() send("setChalkStrength", 2) end },
})
panelButtons({
	{ "Restart at 0", function() send("chalkRestart") end },
	{ "Test reset", function() send("chalkTestReset") end },
	{ "Test save", function() send("chalkTestSave") end },
})
local function refreshChalkFields()
	chalkGoalBox.Text = Format.commas(attr("ChalkGoal", 1000))
	chalkResetGiftBox.Text = attr("ChalkResetGift", "Galaxy")
	chalkResetSecondsBox.Text = tostring(attr("ChalkResetSeconds", 60))
	chalkSaveCoinsBox.Text = Format.commas(attr("ChalkSaveCoins", 1000))
	local strength = attr("ChalkStrength", 1)
	for i, entry in CLIMB_STRENGTHS do
		chalkStrengthButtons[i].BackgroundColor3 = if strength == entry[2] then SELECTED else BUTTON
	end
end
for _, name in { "ChalkGoal", "ChalkResetGift", "ChalkResetSeconds", "ChalkSaveCoins", "ChalkStrength" } do
	State:GetAttributeChangedSignal(name):Connect(refreshChalkFields)
end
refreshChalkFields()

panelLabel("DIAMOND BIRD (every 5 to 7.5 minutes)")
panelButtons({
	{ "Send a diamond bird now", function() send("spawnBird") end },
})

panelLabel("MOUNTAIN SKIN (same game, reskinned)")
local skinButtons = panelButtons({
	{ "Stone & diamond", function() send("setSkin", "stone") end },
	{ "Hay & needle", function() send("setSkin", "hay") end },
})
-- The mountain repaints itself and the display's words follow the skin.
local function refreshSkin()
	local skin = attr("Skin", "stone")
	for i, name in Skin.NAMES do
		skinButtons[i].BackgroundColor3 = if skin == name then SELECTED else BUTTON
	end
	stoneTitle.Text = string.upper(Skin.words(skin).material) .. " LEFT"
	view:setSkin(skin)
end
State:GetAttributeChangedSignal("Skin"):Connect(refreshSkin)
refreshSkin()

panelLabel("REBUILD TEST GIFTS (adds blocks)")
panelLabel("Tests refill dug spaces, then grow new mountain rock.")
panelLabel("Each plays the next adding effect, smallest to biggest.")
panelButtons({
	{ "+100 blocks", function() send("testRebuildGift", 100) end },
	{ "+1,000 blocks", function() send("testRebuildGift", 1000) end },
})
panelButtons({
	{ "+10,000 blocks", function() send("testRebuildGift", 10000) end },
	{ "+50,000 blocks", function() send("testRebuildGift", 50000) end },
})
panelButtons({
	{ "+100,000 blocks", function() send("testRebuildGift", 100000) end },
	{ "Grow to limit", function() send("testRebuildGift", 1500000) end },
})

-- A destructive button only acts on a second click within three seconds.
local function confirmed(button: TextButton, label: string, action: () -> (), prompt: string?)
	local armed = false
	button.Activated:Connect(function()
		if armed then
			armed = false
			button.Text = label
			action()
			return
		end
		armed = true
		button.Text = prompt or "Click again to confirm"
		task.delay(3, function()
			if armed then
				armed = false
				button.Text = label
			end
		end)
	end)
end
local function panelButton(text: string): TextButton
	panelOrder += 1
	local button = make("TextButton", {
		LayoutOrder = panelOrder,
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = BUTTON,
		Font = FONT,
		TextSize = 14,
		TextColor3 = WHITE,
		Text = text,
		ZIndex = 12,
	}, panel)
	rounded(button, 8)
	return button
end

panelLabel("LEADERBOARDS (behind the mountain)")
panelLabel("Blue: helpers. Red: griefers who add stone.")
panelLabel("Test gifts never count.")
panelButtons({
	{ "Preview with sample names", function() send("previewBoards") end },
})
confirmed(panelButton("Reset top helpers"), "Reset top helpers", function() send("resetBoard", "helpers") end)
confirmed(panelButton("Reset top griefers"), "Reset top griefers", function() send("resetBoard", "griefers") end)

panelLabel("GOLD STATUES (saved in your game)")
local statueName = panelBox("", function() end)
statueName.PlaceholderText = "Gifter's name for the plaque"
local statueCoins = panelBox("", function() end)
statueCoins.PlaceholderText = "Coins they sent, e.g. 5000"
panelButtons({
	{ "Place statue in front of me", function()
		send("placeStatue", { name = statueName.Text, coins = tonumber((string.gsub(statueCoins.Text, "[^%d]", ""))) or 0 })
	end },
})
confirmed(panelButton("Remove the statue nearest me"), "Remove the statue nearest me", function() send("removeNearestStatue") end)
confirmed(panelButton("Remove all statues"), "Remove all statues", function() send("removeAllStatues") end)
panelLabel("Your statues (press Remove twice):")
panelOrder += 1
local statueList = make("Frame", {
	LayoutOrder = panelOrder,
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	ZIndex = 11,
}, panel)
make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, statueList)
local function refreshStatues()
	for _, child in statueList:GetChildren() do
		if child:IsA("Frame") then child:Destroy() end
	end
	local ok, statues = pcall(function()
		return game:GetService("HttpService"):JSONDecode(attr("Statues", "[]"))
	end)
	if not ok or type(statues) ~= "table" then return end
	if #statues == 0 then
		local row = make("Frame", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, ZIndex = 11 }, statueList)
		make("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = FONT_MEDIUM,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = MUTED,
			Text = "No statues yet.",
			ZIndex = 12,
		}, row)
		return
	end
	for index, statue in statues do
		local row = make("Frame", { LayoutOrder = index, Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, ZIndex = 11 }, statueList)
		make("TextLabel", {
			Size = UDim2.new(1, -96, 1, 0),
			BackgroundTransparency = 1,
			Font = FONT_MEDIUM,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = GOLD,
			Text = string.format("%s · %s coins", tostring(statue.name), Format.commas(tonumber(statue.coins) or 0)),
			ZIndex = 12,
		}, row)
		local remove = make("TextButton", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(88, 30),
			BackgroundColor3 = DANGER,
			Font = FONT,
			TextSize = 14,
			TextColor3 = WHITE,
			Text = "Remove",
			ZIndex = 12,
		}, row)
		rounded(remove, 8)
		confirmed(remove, "Remove", function() send("removeStatue", index) end, "Sure?")
	end
end
State:GetAttributeChangedSignal("Statues"):Connect(refreshStatues)
refreshStatues()

-- The wins of the game being played (Diamond Climb and Chalkboard Count keep their own).
local function currentWins(): number
	if player:GetAttribute("InClimb") == true then return attr("ClimbWins", 0) end
	if player:GetAttribute("InChalk") == true then return attr("ChalkWins", 0) end
	return attr("Wins", 0)
end
local function refreshPanelFields()
	titleBox.Text = attr("WinTitle", "WINS")
	winsInput.Text = tostring(currentWins())
	goalBox.Text = tostring(attr("WinGoal", 0))
	textColourBox.Text = attr("WinTextColor", "#FFFFFF")
	backgroundBox.Text = attr("WinBackgroundColor", "#2B2140")
	stoneBoxInput.Text = Format.commas(attr("NextStartingStone", Config.StartingStone))
	perCoinBox.Text = tostring(attr("PerCoin", Config.StonePerCoin))
	perLikeBox.Text = "Like: " .. tostring(attr("PerLike", Config.StonePerLike))
	perFollowBox.Text = "Follow: " .. tostring(attr("PerFollow", Config.StonePerFollow))
	perShareBox.Text = "Share: " .. tostring(attr("PerShare", Config.StonePerShare))
end

-- Settings (every player): the field of view and switches that hide things,
-- from SETTINGS on the sidebar or P (O is Roblox's zoom-out key, which
-- swallows it). The hands are refitted to the FOV, so digging looks the same
-- at any FOV.
local SETTINGS_KEY = Enum.KeyCode.P
-- The settings card opens from SETTINGS on the sidebar (or P), anywhere: the
-- lobby too, so it has its own screen layer.
local settingsGui = make("ScreenGui", {
	Name = "DiamondRushSettings",
	ResetOnSpawn = false,
	DisplayOrder = 6,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, player:WaitForChild("PlayerGui"))
local settingsCard = make("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, Sidebar.PANEL_LEFT, Sidebar.CENTRE, 0),
	Size = UDim2.fromOffset(300, 394),
	Visible = false,
	ZIndex = 15,
}, settingsGui)
glass(settingsCard, 14, 0.08)
make("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), PaddingTop = UDim.new(0, 14) }, settingsCard)
local function settingsText(properties: { [string]: any }): TextLabel
	local label = make("TextLabel", { BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 16 }, settingsCard)
	for key, value in properties do (label :: any)[key] = value end
	return label
end
settingsText({ Size = UDim2.new(1, 0, 0, 14), Font = FONT, TextSize = 12, TextColor3 = MUTED, Text = "SETTINGS" })
settingsText({ Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, -50, 0, 20), Font = FONT_MEDIUM, TextSize = 15, TextColor3 = WHITE, Text = "Field of view" })
local fovValue = settingsText({ Position = UDim2.new(1, -50, 0, 26), Size = UDim2.fromOffset(50, 20), Font = FONT, TextSize = 15, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Right, Text = "" })
-- The slider: a track, its filled part and a knob, with a taller hit area.
local fovSlider = make("TextButton", {
	Position = UDim2.fromOffset(0, 54),
	Size = UDim2.new(1, 0, 0, 28),
	BackgroundTransparency = 1,
	Text = "",
	AutoButtonColor = false,
	ZIndex = 16,
}, settingsCard)
local fovTrack = make("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.fromScale(0, 0.5),
	Size = UDim2.new(1, 0, 0, 6),
	BackgroundColor3 = WHITE,
	BackgroundTransparency = 0.82,
	BorderSizePixel = 0,
	ZIndex = 16,
}, fovSlider)
rounded(fovTrack, 3)
local fovFill = make("Frame", { Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = SELECTED, BorderSizePixel = 0, ZIndex = 17 }, fovTrack)
rounded(fovFill, 3)
local fovKnob = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(18, 18),
	BackgroundColor3 = WHITE,
	BorderSizePixel = 0,
	ZIndex = 18,
}, fovTrack)
rounded(fovKnob, 9)
local function settingsAction(text: string, x: number, colour: Color3): TextButton
	local button = make("TextButton", {
		Position = UDim2.new(x, if x > 0 then 4 else 0, 0, 348),
		Size = UDim2.new(0.5, -4, 0, 30),
		BackgroundColor3 = colour,
		Font = FONT,
		TextSize = 13,
		TextColor3 = WHITE,
		Text = text,
		ZIndex = 16,
	}, settingsCard)
	rounded(button, 8)
	return button
end
-- Hide the sidebar: tucks it away (arrow and all) so it stays off the stream;
-- G, P and Y still open the games, the settings and the streamer panel.
-- Remembered by the server.
settingsText({ Position = UDim2.fromOffset(0, 96), Size = UDim2.new(1, -60, 0, 20), Font = FONT_MEDIUM, TextSize = 15, TextColor3 = WHITE, Text = "Hide the sidebar" })
settingsText({ Position = UDim2.fromOffset(0, 118), Size = UDim2.new(1, -60, 0, 30), Font = FONT_MEDIUM, TextSize = 12, TextColor3 = MUTED, TextWrapped = true,
	TextYAlignment = Enum.TextYAlignment.Top, Text = "G, P and Y still open games, settings and the streamer panel." })
local hideSwitch = make("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 98),
	Size = UDim2.fromOffset(46, 26),
	BackgroundColor3 = BUTTON,
	AutoButtonColor = false,
	Text = "",
	ZIndex = 16,
}, settingsCard)
rounded(hideSwitch, 13)
local hideKnob = make("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 3, 0.5, 0),
	Size = UDim2.fromOffset(20, 20),
	BackgroundColor3 = WHITE,
	BorderSizePixel = 0,
	ZIndex = 17,
}, hideSwitch)
rounded(hideKnob, 10)
local function refreshHidden()
	-- Phones and tablets have no G or P key to bring the buttons back, so
	-- they always show there.
	local hidden = player:GetAttribute("HideButtons") == true and UserInputService.KeyboardEnabled
	hideSwitch.BackgroundColor3 = if hidden then SELECTED else BUTTON
	hideKnob.Position = if hidden then UDim2.new(1, -23, 0.5, 0) else UDim2.new(0, 3, 0.5, 0)
	Sidebar.setHidden(hidden)
end
player:GetAttributeChangedSignal("HideButtons"):Connect(refreshHidden)
refreshHidden()
hideSwitch.Activated:Connect(function()
	local hidden = player:GetAttribute("HideButtons") ~= true
	-- Shown at once; the server keeps it for next time.
	player:SetAttribute("HideButtons", hidden)
	Request:FireServer("setHideButtons", hidden)
end)
-- Switches that hide a game's own card: Diamond Climb's speed and jump
-- sliders, Chalkboard Count's writing speed and themes. Remembered by the server.
local function cardSwitch(y: number, title: string, card: string, attribute: string)
	settingsText({ Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, -60, 0, 20), Font = FONT_MEDIUM, TextSize = 15, TextColor3 = WHITE, Text = title })
	local switch = make("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, y + 2),
		Size = UDim2.fromOffset(46, 26),
		BackgroundColor3 = BUTTON,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 16,
	}, settingsCard)
	rounded(switch, 13)
	local knob = make("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 17,
	}, switch)
	rounded(knob, 10)
	local function refresh()
		local hidden = player:GetAttribute(attribute) == true
		switch.BackgroundColor3 = if hidden then SELECTED else BUTTON
		knob.Position = if hidden then UDim2.new(1, -23, 0.5, 0) else UDim2.new(0, 3, 0.5, 0)
	end
	player:GetAttributeChangedSignal(attribute):Connect(refresh)
	refresh()
	switch.Activated:Connect(function()
		local hidden = player:GetAttribute(attribute) ~= true
		player:SetAttribute(attribute, hidden)
		Request:FireServer("setHideCard", { card = card, hidden = hidden })
	end)
end
cardSwitch(156, "Hide speed and jump", "climb", "HideClimbCard")
settingsText({ Position = UDim2.fromOffset(0, 178), Size = UDim2.new(1, -60, 0, 16), Font = FONT_MEDIUM, TextSize = 12, TextColor3 = MUTED, Text = "Diamond Climb's sliders" })
cardSwitch(206, "Hide writing speed", "chalk", "HideChalkCard")
settingsText({ Position = UDim2.fromOffset(0, 228), Size = UDim2.new(1, -60, 0, 16), Font = FONT_MEDIUM, TextSize = 12, TextColor3 = MUTED, Text = "Chalkboard Count's card" })
-- The win counter (the streamer's: it's the same for everyone watching).
local winsRowTitle = settingsText({ Position = UDim2.fromOffset(0, 258), Size = UDim2.new(1, -60, 0, 20), Font = FONT_MEDIUM, TextSize = 15, TextColor3 = WHITE, Text = "Hide the win counter" })
local winsRowHint = settingsText({ Position = UDim2.fromOffset(0, 280), Size = UDim2.new(1, -60, 0, 16), Font = FONT_MEDIUM, TextSize = 12, TextColor3 = MUTED, Text = "In every game" })
local winsSwitch = make("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 260),
	Size = UDim2.fromOffset(46, 26),
	BackgroundColor3 = BUTTON,
	AutoButtonColor = false,
	Text = "",
	ZIndex = 16,
}, settingsCard)
rounded(winsSwitch, 13)
local winsKnob = make("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 3, 0.5, 0),
	Size = UDim2.fromOffset(20, 20),
	BackgroundColor3 = WHITE,
	BorderSizePixel = 0,
	ZIndex = 17,
}, winsSwitch)
rounded(winsKnob, 10)
local function refreshWinsSwitch()
	local hidden = State:GetAttribute("ShowWins") == false
	winsSwitch.BackgroundColor3 = if hidden then SELECTED else BUTTON
	winsKnob.Position = if hidden then UDim2.new(1, -23, 0.5, 0) else UDim2.new(0, 3, 0.5, 0)
end
State:GetAttributeChangedSignal("ShowWins"):Connect(refreshWinsSwitch)
refreshWinsSwitch()
winsSwitch.Activated:Connect(function()
	Request:FireServer("setShowWins", State:GetAttribute("ShowWins") == false)
end)
local function showWinsRow(isAdmin: boolean)
	winsRowTitle.Visible, winsRowHint.Visible, winsSwitch.Visible = isAdmin, isAdmin, isAdmin
end
local fovReset = settingsAction("Reset", 0, BUTTON)
local settingsDone = settingsAction("Done", 0.5, SELECTED)

local function refreshFov()
	local fov = FirstPerson.fieldOfView()
	local fraction = (fov - FirstPerson.FOV_MIN) / (FirstPerson.FOV_MAX - FirstPerson.FOV_MIN)
	fovFill.Size = UDim2.fromScale(fraction, 1)
	fovKnob.Position = UDim2.fromScale(fraction, 0.5)
	fovValue.Text = tostring(fov)
end
refreshFov()
local function fovFromScreen(x: number)
	local left, width = fovTrack.AbsolutePosition.X, math.max(1, fovTrack.AbsoluteSize.X)
	local fraction = math.clamp((x - left) / width, 0, 1)
	FirstPerson.setFieldOfView(FirstPerson.FOV_MIN + fraction * (FirstPerson.FOV_MAX - FirstPerson.FOV_MIN))
	refreshFov()
end
local draggingFov = false
fovSlider.InputBegan:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		draggingFov = true
		fovFromScreen(input.Position.X)
	end
end)
UserInputService.InputChanged:Connect(function(input: InputObject)
	if draggingFov and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		fovFromScreen(input.Position.X)
	end
end)
UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		draggingFov = false
	end
end)
fovReset.Activated:Connect(function()
	FirstPerson.setFieldOfView(FirstPerson.FOV_DEFAULT)
	refreshFov()
end)

local function settingsOpen(): boolean
	return settingsCard.Visible
end
local function setSettingsOpen(show: boolean)
	settingsCard.Visible = show
	-- One card at a time beside the sidebar.
	if show then
		LobbyView.close()
		Sidebar.setThemesOpen(false)
	end
	draggingFov = false
	if show then UserInputService.MouseBehavior = Enum.MouseBehavior.Default end
end
settingsDone.Activated:Connect(function() setSettingsOpen(false) end)
-- P toggles the settings, anywhere (no gift can be given P, see Keybinds).
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or input.KeyCode ~= SETTINGS_KEY or UserInputService:GetFocusedTextBox() then return end
	setSettingsOpen(not settingsCard.Visible)
end)
-- The games menu opening (GAMES, G, or arriving in the lobby) closes the others.
LobbyView.opened = function()
	settingsCard.Visible = false
	Sidebar.setThemesOpen(false)
end

-- The sidebar: GIFTS opens the gift settings (the streamer's), THEMES the
-- themes card, SETTINGS this settings card and GAMES the games menu; pressing
-- one that's open closes it.
Sidebar.start({
	request = Request,
	state = State,
	onPick = function(name: string)
		if name == "gifts" then
			LobbyView.close()
			setSettingsOpen(false)
			Sidebar.setThemesOpen(false)
			panel.Visible = false
			GiftMenu.setOpen(true)
		elseif name == "themes" then
			local show = not Sidebar.themesOpen()
			LobbyView.close()
			setSettingsOpen(false)
			Sidebar.setThemesOpen(show)
		elseif name == "settings" then
			setSettingsOpen(not settingsCard.Visible)
		else
			LobbyView.setOpen(not LobbyView.isOpen())
		end
	end,
	active = function(): string?
		if GiftMenu.isOpen() then return "gifts" end
		if Sidebar.themesOpen() then return "themes" end
		if settingsCard.Visible then return "settings" end
		if LobbyView.isOpen() then return "games" end
		return nil
	end,
})
-- The saved "hide the sidebar" was looked at before the sidebar existed.
refreshHidden()

-- The settings panel is hidden: the owner presses Y to open or close it.
local isAdmin = false
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	-- The panel lives in the game's display, which is off in the lobby.
	if processed or input.KeyCode ~= Enum.KeyCode.Y or not isAdmin or not gui.Enabled then
		return
	end
	-- Y also closes the gift settings.
	if GiftMenu.isOpen() then
		GiftMenu.setOpen(false)
		return
	end
	panel.Visible = not panel.Visible
	if panel.Visible then
		refreshPanelFields()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end)
RunService.RenderStepped:Connect(function()
	-- Back in the lobby the game's display is off, and the streamer panel with
	-- it (the sidebar's cards still work there); the lobby keeps the mouse free.
	if not gui.Enabled then
		panel.Visible = false
		return
	end
	-- First person locks the mouse; free it while a panel or card is open.
	if panel.Visible or settingsOpen() or GiftMenu.isOpen() or Sidebar.themesOpen() then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
end)

local function refreshAdmin()
	isAdmin = player:GetAttribute("DiamondRushAdmin") == true
	if not isAdmin then
		panel.Visible = false
	end
	Sidebar.setAdmin(isAdmin)
	showWinsRow(isAdmin)
end
player:GetAttributeChangedSignal("DiamondRushAdmin"):Connect(refreshAdmin)
refreshAdmin()

-- Live updates ---------------------------------------------------------------------------
local function refreshWins()
	winsBox.Visible = attr("ShowWins", true)
	winsBox.Text = Format.wins(attr("WinTitle", "WINS"), currentWins(), attr("WinGoal", 0))
	winsBox.TextColor3 = hexColor(attr("WinTextColor", "#FFFFFF"), WHITE)
	winsBox.BackgroundColor3 = hexColor(attr("WinBackgroundColor", "#2B2140"), PANEL)
	winsStroke.Color = winsBox.TextColor3:Lerp(GOLD, 0.6)
	if panel.Visible then
		refreshPanelFields()
	end
end
for _, name in { "Wins", "ClimbWins", "ChalkWins", "WinTitle", "WinGoal", "WinTextColor", "WinBackgroundColor", "ShowWins", "NextStartingStone" } do
	State:GetAttributeChangedSignal(name):Connect(refreshWins)
end
for _, name in { "InGame", "InClimb", "InChalk" } do
	player:GetAttributeChangedSignal(name):Connect(refreshWins)
end
refreshWins()

local shownStone = attr("Stone", Config.StartingStone)
local lastCount = -1

RunService.RenderStepped:Connect(function(dt: number)
	-- The stone number rolls towards its new value instead of jumping.
	local stone = attr("Stone", 0)
	local starting = math.max(1, attr("MountainTotal", attr("StartingStone", Config.StartingStone)))
	shownStone += (stone - shownStone) * math.min(1, dt * 10)
	if math.abs(stone - shownStone) < 1 then
		shownStone = stone
	end
	setText(stoneValue, Format.commas(shownStone))
	barFill.Size = UDim2.fromScale(math.clamp(shownStone / starting, 0, 1), 1)

	local phase = attr("Phase", "Digging")
	-- The hold counter takes the top-centre slot; the hand and gem stay unobscured.
	stoneBox.Visible = phase ~= "Holding"
	timerLabel.Visible = phase ~= "Holding"
	-- In Diamond in the Rough it moves below the hold countdown; the climb and
	-- chalkboard have their own displays above it, the same height.
	winsBox.Position = UDim2.new(0.5, 0, 0, if phase == "Holding" and roughHud.Visible then WINS_Y_HOLDING else WINS_Y)
	-- The time takes the wins' place when the counter is hidden.
	timerLabel.Position = UDim2.new(0.5, 0, 0, if winsBox.Visible then 154 else WINS_Y)
	local now = workspace:GetServerTimeNow()
	-- The 2X card shows while a caught diamond bird's bonus runs, and pops in.
	local boostLeft = attr("BirdBoostUntil", 0) - now
	local boosted = boostLeft > 0 and phase ~= "Holding"
	if boosted and not boostTag.Visible then
		boostScale.Scale = 1.4
		TweenService:Create(boostScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	boostTag.Visible = boosted
	if boosted then setText(boostTime, Format.duration(boostLeft)) end
	local roundStart = attr("RoundStart", now)
	setText(timerLabel, '<font color="#A8AEBE">TIME</font>   ' .. Format.duration(if phase == "Won" then attr("LastTime", 0) else now - roundStart))
	-- Shown only while gifts are being played on the mountain.
	setText(status, if attr("GiftProcessing", false) then "Updating mountain (" .. tostring(attr("GiftQueueLength", 0)) .. " queued)" else "")

	if phase == "Holding" then
		local elapsed = now - attr("HoldStart", now)
		local shown = HoldTimer.display(elapsed, Config.HoldSeconds, Config.HoldCountFrom, Config.HoldSlowdown)
		countdown.Visible = true
		setText(countHolder, string.upper(tostring(attr("Holder", ""))) .. " IS HOLDING IT")
		setText(countNumber, tostring(shown))
		if shown ~= lastCount then
			if lastCount ~= -1 and roughHud.Visible then Sounds.play("tick") end
			lastCount = shown
			countNumber.TextColor3 = WHITE:Lerp(GOLD, 1 - shown / Config.HoldCountFrom)
			countScale.Scale = 1.35
			TweenService:Create(countScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		banner.Visible = false
	else
		countdown.Visible = false
		lastCount = -1
		banner.Visible = phase == "Revealed" or phase == "Rebuilding"
		if phase == "Rebuilding" then
			banner.Text = "REBUILDING THE " .. string.upper(Skin.words(attr("Skin", "stone")).heap)
			banner.TextTransparency = 0
		end
		if phase == "Revealed" then
			banner.Text = string.upper(Skin.words(attr("Skin", "stone")).gem) .. " UNCOVERED  ·  FIND IT AND CLICK IT"
			banner.TextTransparency = 0.15 + 0.15 * math.sin(now * 5)
		end
	end
end)

-- A chime when the diamond (or needle) is uncovered.
State:GetAttributeChangedSignal("Phase"):Connect(function()
	if attr("Phase", "Digging") == "Revealed" and player:GetAttribute("InGame") == true then Sounds.play("chime") end
end)

Notify.OnClientEvent:Connect(function(kind: string, data: any)
	if kind == "giftEffect" and type(data) == "table" then
		-- The mountain's gift shows play at the mountain only.
		if player:GetAttribute("InGame") == true then GiftEffects.play(data) end
	elseif kind == "feed" and type(data) == "table" then
		addFeed(tostring(data.text), tonumber(data.stone) or 0, tostring(data.kind))
	elseif kind == "win" and type(data) == "table" then
		showWin(data)
	elseif kind == "climbGift" then
		climb.onGift(data)
	elseif kind == "climbWin" then
		climb.onWin(data)
	elseif kind == "climbRestart" then
		climb.onRestart()
	elseif kind == "climbWall" then
		climb.onWall(data)
	elseif kind == "chalkGift" then
		chalk.onGift(data)
	elseif kind == "chalkReset" then
		chalk.onReset(data)
	elseif kind == "chalkWipe" then
		chalk.onWipe(data)
	elseif kind == "chalkWin" then
		chalk.onWin(data)
	elseif kind == "notice" and type(data) == "string" then
		addFeed(data, 0, "notice")
	elseif kind == "dropped" and type(data) == "table" and data.name ~= "" then
		local gem = Skin.words(attr("Skin", "stone")).gem
		addFeed(tostring(data.name) .. (if data.reason == "rebuild" then " — rebuild cancelled the countdown! Pick up the " .. gem .. " again." else " dropped the " .. gem .. "!"), 0, "drop")
	end
end)

-- Digging: hold the dig button (left mouse / touch) and your hands tear
-- through the rock you aim at, about DigPerSecond rocks a second: a hand lands
-- four times a second and breaks a quarter of that each time (see FirstPerson).
-- A separate full-viewport layer keeps the dot aligned with the camera ray,
-- regardless of the HUD inset or the screen's aspect ratio.
local aimGui = make("ScreenGui", {
	Name = "DiamondRushAim",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 5,
}, player:WaitForChild("PlayerGui"))
local aimDot = make("Frame", {
	Name = "Dot",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(5, 5),
	BackgroundColor3 = WHITE,
	BorderSizePixel = 0,
	Active = false,
}, aimGui)
rounded(aimDot, 5)
outline(aimDot, 1)
local rockOutline = make("Highlight", {
	Name = "AimedRock",
	FillTransparency = 1,
	OutlineColor = WHITE,
	OutlineTransparency = 0.15,
	DepthMode = Enum.HighlightDepthMode.Occluded,
	Enabled = false,
}, workspace)
local aimTarget: BasePart? = nil
-- True while the aim is on (or close to) a diamond bird that is still circling.
-- The bird is small and moving, so a click within a few degrees counts.
local aimBird = false
local function birdNear(ray: Ray): boolean
	for _, child in workspace:GetChildren() do
		local root = if child.Name == "DiamondBird" and child:IsA("Model") then child.PrimaryPart else nil
		if root and child:GetAttribute("LeaveAt") == 0 then
			local offset = root.Position - ray.Origin
			local distance = offset.Magnitude
			if distance > 1e-3 and distance < 400 then
				local tolerance = math.max(math.rad(4), math.atan(7 / distance))
				if math.acos(math.clamp(offset.Unit:Dot(ray.Direction.Unit), -1, 1)) <= tolerance then
					return true
				end
			end
		end
	end
	return false
end
local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude
RunService:BindToRenderStep("DiamondRushAim", Enum.RenderPriority.Camera.Value + 3, function()
	local camera = workspace.CurrentCamera
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local phase = attr("Phase", "Digging")
	local active = camera ~= nil and humanoid ~= nil and humanoid.Health > 0
		and player:GetAttribute("InGame") == true and not LobbyView.isOpen() and not HowToPlay.isOpen()
		and not panel.Visible and not settingsOpen() and not GiftMenu.isOpen() and phase ~= "Won" and phase ~= "Rebuilding"
		and not (phase == "Holding" and attr("HolderUserId", 0) == player.UserId)
	aimDot.Visible = active
	UserInputService.MouseIconEnabled = not active
	aimTarget = nil
	aimBird = false
	if active and camera then
		aimParams.FilterDescendantsInstances = if character then { character } else {}
		local viewport = camera.ViewportSize
		local ray = camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)
		local result = workspace:Raycast(ray.Origin, ray.Direction * 500, aimParams)
		if result then aimTarget = result.Instance end
		aimBird = birdNear(ray)
	end
	-- The dot turns gold over the bird, so players know a click will catch it.
	local dotColour = if aimBird then GOLD else WHITE
	if aimDot.BackgroundColor3 ~= dotColour then
		aimDot.BackgroundColor3 = dotColour
		aimDot.Size = if aimBird then UDim2.fromOffset(9, 9) else UDim2.fromOffset(5, 5)
	end
	local target = aimTarget
	local stone = target ~= nil and view:keyForPart(target) ~= nil
	local adornee = if stone then target else nil
	if rockOutline.Adornee ~= adornee then rockOutline.Adornee = adornee end
	rockOutline.Enabled = stone
end)
local digging = false
local function isDigInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if not processed and isDigInput(input) then
		-- A click on (or close to) the diamond bird catches it. A tap aims
		-- where the finger is; a click aims at the screen centre.
		local camera = workspace.CurrentCamera
		local catching = aimBird
		if not catching and input.UserInputType == Enum.UserInputType.Touch and camera
			and player:GetAttribute("InGame") == true then
			catching = birdNear(camera:ScreenPointToRay(input.Position.X, input.Position.Y))
		end
		local target = aimTarget
		if catching or (target and target.Parent and target.Parent.Name == "DiamondBird") then
			Request:FireServer("catchBird")
			digging = false
			return
		end
		-- A fresh click on the diamond goes to its ClickDetector, never to digging.
		if target == workspace:FindFirstChild("Diamond") then
			digging = false
			return
		end
		digging = true
	end
end)
UserInputService.InputEnded:Connect(function(input: InputObject)
	if isDigInput(input) then
		digging = false
	end
end)
UserInputService.WindowFocusReleased:Connect(function()
	digging = false
end)
-- The rock this player is digging now, while the dig button is held: its key,
-- or nil when there is nothing to dig.
local function digTarget(): number?
	local phase = attr("Phase", "Digging")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local target = aimTarget
	local allowed = digging and not panel.Visible and not settingsOpen() and not GiftMenu.isOpen() and not Sidebar.themesOpen() and not HowToPlay.isOpen() and phase ~= "Won" and phase ~= "Rebuilding"
		and not (phase == "Holding" and attr("HolderUserId", 0) == player.UserId)
	local key = if allowed and target then view:keyForPart(target) else nil
	if key == nil or root == nil or not root:IsA("BasePart") or (root.Position - (target :: BasePart).Position).Magnitude > 16 then
		return nil
	end
	return key
end
-- The hands swing while this is set; the rock breaks as each one lands.
RunService.Heartbeat:Connect(function()
	player:SetAttribute("DiggingRock", digTarget() ~= nil)
end)
-- Each landed strike cracks the rock with a crunch; every fourth a bigger
-- chunk breaks away. Hits in a row climb a little in pitch (eight steps, then
-- round again), and a pause starts the climb over.
Sounds.useDigSound(Config.DigSoundId, Config.DigSoundVolume)
local strikes = 0
local lastStrikeAt = -math.huge
FirstPerson.onStrike(function()
	local key = digTarget()
	local character = player.Character
	if key ~= nil and (character == nil or character:FindFirstChildOfClass("Tool") == nil) then
		Request:FireServer("mine", key)
		local rock = aimTarget
		local at = if rock then rock.Position else nil
		local now = os.clock()
		if now - lastStrikeAt > 0.6 then strikes = 0 end
		lastStrikeAt = now
		strikes += 1
		Sounds.play("dig", at, 1, Sounds.digPitch(strikes))
		if strikes % 4 == 0 then Sounds.play("crumble", at) end
	end
end)

-- The key held with Shift and/or Ctrl, as a binding name ("Shift+K").
local function pressedCombo(input: InputObject): string
	return Keybinds.combo(input.KeyCode.Name,
		UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl),
		UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift))
end

-- Gift keybinds work in-game for the streamer, outside text entry and the
-- gift settings (where keys are being chosen): TikFinity presses the key when
-- the gift arrives on the LIVE. They work with the Y panel open too, so no
-- gift is lost while the streamer changes something there.
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not isAdmin or GiftMenu.isOpen() or UserInputService:GetFocusedTextBox() then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	local ok, bindings = pcall(game:GetService("HttpService").JSONDecode, game:GetService("HttpService"), attr("GiftBindings", "{}"))
	if not ok or type(bindings) ~= "table" then return end
	local binding = bindings[pressedCombo(input)]
	if binding then send("testGift", { coins = binding.coins, count = 1, name = binding.gift, keybind = true }) end
end)
