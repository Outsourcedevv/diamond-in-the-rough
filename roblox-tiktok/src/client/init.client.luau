--!strict
-- The on-screen display: stone left, round time, the win counter, the hold
-- countdown, the gift feed, the win screen and the streamer's settings panel.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("DiamondRush")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local HoldTimer = require(Shared:WaitForChild("HoldTimer"))
local Skin = require(Shared:WaitForChild("Skin"))
local FirstPerson = require(script:WaitForChild("FirstPerson"))
-- Everyone arrives in the royal lobby, with a normal camera (see LobbyView).
FirstPerson.setEnabled(player:GetAttribute("InGame") == true)
FirstPerson.start()
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
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, player:WaitForChild("PlayerGui"))

-- The games menu: the game's display, first-person view and hands only show
-- while playing, not in the lobby.
local LobbyView = require(script:WaitForChild("LobbyView"))
LobbyView.start(Request, State, function(inGame: boolean)
	gui.Enabled = inGame
	FirstPerson.setEnabled(inGame)
end)
-- The diamond bird flies round the mountain; catching it doubles gifts.
require(script:WaitForChild("BirdView")).start(gui, State)
-- Cherry petals fall round the camera when the map shows the sakura theme.
require(script:WaitForChild("PetalView")).start(State)

-- Stone left (top centre) -------------------------------------------------------
local stoneBox = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 10),
	Size = UDim2.fromOffset(300, 84),
}, gui)
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
}, gui)
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

-- Win counter, under the stone count ------------------------------------------------
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
}, gui)
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
}, gui)
glass(banner, 22, 0.2)
make("UIPadding", { PaddingLeft = UDim.new(0, 22), PaddingRight = UDim.new(0, 22) }, banner)

local countdown = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 10),
	Size = UDim2.fromOffset(320, 140),
	BackgroundTransparency = 1,
	Visible = false,
}, gui)
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
}, gui)
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
	Size = UDim2.fromOffset(340, 520),
	CanvasSize = UDim2.fromOffset(0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = MUTED,
	Visible = false,
	ZIndex = 10,
}, gui)
glass(panel, 14, 0.06)
make("UIPadding", {
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 14),
	PaddingTop = UDim.new(0, 10),
	PaddingBottom = UDim.new(0, 12),
}, panel)
make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, panel)
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

panelLabel("WIN COUNTER TITLE")
local titleBox = panelBox("", function(text)
	send("setTitle", text)
end)
panelLabel("WINS")
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

panelLabel("GIFT CATALOGUE: localhost:8787 in your browser")
panelLabel("GIFT RULES: positive removes, negative adds")
panelOrder += 1
local rulesList = make("Frame", {
	LayoutOrder = panelOrder,
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	ZIndex = 11,
}, panel)
make("UIListLayout", { SortOrder = Enum.SortOrder.Name, Padding = UDim.new(0, 4) }, rulesList)
local newGiftName = panelBox("", function() end)
newGiftName.PlaceholderText = "Gift name, e.g. Rose"
local newGiftRocks = panelBox("", function() end)
newGiftRocks.PlaceholderText = "500 removes; -500 adds blocks"
panelButtons({
	{ "Add / change gift rule", function()
		local rocks = tonumber((string.gsub(newGiftRocks.Text, "[,%s]", "")))
		if newGiftName.Text ~= "" and rocks then
			send("setGiftRule", { gift = newGiftName.Text, rocks = rocks })
			newGiftName.Text = ""
			newGiftRocks.Text = ""
		end
	end },
})

local function refreshRules()
	for _, child in rulesList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local ok, rules = pcall(function()
		return game:GetService("HttpService"):JSONDecode(attr("GiftRules", "{}"))
	end)
	if not ok or type(rules) ~= "table" then
		return
	end
	for name, rocks in rules do
		local row = make("Frame", { Name = tostring(name), Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, ZIndex = 11 }, rulesList)
		make("TextLabel", {
			Size = UDim2.new(1, -40, 1, 0),
			BackgroundTransparency = 1,
			Font = FONT_MEDIUM,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = WHITE,
			Text = string.format("%s: %s %s rocks", tostring(name), if (tonumber(rocks) or 0) < 0 then "adds" else "removes", Format.commas(math.abs(tonumber(rocks) or 0))),
			ZIndex = 12,
		}, row)
		local remove = make("TextButton", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(34, 30),
			BackgroundColor3 = DANGER,
			Font = FONT,
			TextSize = 14,
			TextColor3 = WHITE,
			Text = "X",
			ZIndex = 12,
		}, row)
		rounded(remove, 8)
		remove.Activated:Connect(function()
			send("setGiftRule", { gift = tostring(name) })
		end)
	end
end
State:GetAttributeChangedSignal("GiftRules"):Connect(refreshRules)
refreshRules()

panelLabel("TEST GIFTS (no TikTok needed)")
local testGifts = {
	{ "Rose · 1", "Rose", 1, 1 },
	{ "Finger Heart · 5", "Finger Heart", 5, 1 },
	{ "Rose x10 · 10", "Rose", 1, 10 },
	{ "Doughnut · 30", "Doughnut", 30, 1 },
	{ "Hand Hearts · 100", "Hand Hearts", 100, 1 },
	{ "Money Gun · 500", "Money Gun", 500, 1 },
	{ "Galaxy · 1,000", "Galaxy", 1000, 1 },
	{ "Doughnut x40 · 1,200", "Doughnut", 30, 40 },
	{ "Galaxy x5 · 5,000", "Galaxy", 1000, 5 },
	{ "Galaxy x10 · 10,000", "Galaxy", 1000, 10 },
	{ "Lion · 29,999", "Lion", 29999, 1 },
	{ "Universe · 34,999", "TikTok Universe", 34999, 1 },
}
panelLabel("Button numbers show total test coins")
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

panelLabel("DIAMOND BIRD (every 5 to 7.5 minutes)")
panelButtons({
	{ "Send a diamond bird now", function() send("spawnBird") end },
})

panelLabel("MAP THEME (changes for everyone straight away)")
local themeButtons = panelButtons({
	{ "Alpine", function() send("setTheme", "default") end },
	{ "Sakura", function() send("setTheme", "sakura") end },
	{ "Farm", function() send("setTheme", "farm") end },
})
-- The theme showing now is lit up.
local function refreshTheme()
	local theme = attr("Theme", "default")
	for i, name in { "default", "sakura", "farm" } do
		themeButtons[i].BackgroundColor3 = if theme == name then SELECTED else BUTTON
	end
end
State:GetAttributeChangedSignal("Theme"):Connect(refreshTheme)
refreshTheme()

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

local function refreshPanelFields()
	titleBox.Text = attr("WinTitle", "WINS")
	winsInput.Text = tostring(attr("Wins", 0))
	goalBox.Text = tostring(attr("WinGoal", 0))
	textColourBox.Text = attr("WinTextColor", "#FFFFFF")
	backgroundBox.Text = attr("WinBackgroundColor", "#2B2140")
	stoneBoxInput.Text = Format.commas(attr("NextStartingStone", Config.StartingStone))
	perCoinBox.Text = tostring(attr("PerCoin", Config.StonePerCoin))
	perLikeBox.Text = "Like: " .. tostring(attr("PerLike", Config.StonePerLike))
	perFollowBox.Text = "Follow: " .. tostring(attr("PerFollow", Config.StonePerFollow))
	perShareBox.Text = "Share: " .. tostring(attr("PerShare", Config.StonePerShare))
end

-- Settings (every player): the field of view, from the Settings button or O.
-- The hands are refitted to it, so digging looks the same at any FOV.
local SETTINGS_KEY = Enum.KeyCode.O
local settingsButton = make("TextButton", {
	Position = UDim2.fromOffset(12, 10),
	Size = UDim2.fromOffset(0, 32),
	AutomaticSize = Enum.AutomaticSize.X,
	Font = FONT,
	TextSize = 13,
	TextColor3 = WHITE,
	Text = "SETTINGS  <font color=\"#A8AEBE\">O</font>",
	RichText = true,
}, gui)
glass(settingsButton, 16)
make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, settingsButton)
local settingsCard = make("Frame", {
	Position = UDim2.fromOffset(12, 50),
	Size = UDim2.fromOffset(300, 150),
	Visible = false,
	ZIndex = 15,
}, gui)
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
		Position = UDim2.new(x, if x > 0 then 4 else 0, 0, 96),
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
	return settingsCard.Visible and gui.Enabled
end
local function setSettingsOpen(show: boolean)
	settingsCard.Visible = show
	draggingFov = false
	if show then UserInputService.MouseBehavior = Enum.MouseBehavior.Default end
end
settingsButton.Activated:Connect(function() setSettingsOpen(not settingsCard.Visible) end)
settingsDone.Activated:Connect(function() setSettingsOpen(false) end)
-- O toggles the settings in the game, unless the streamer bound O to a test gift.
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or input.KeyCode ~= SETTINGS_KEY or not gui.Enabled or UserInputService:GetFocusedTextBox() then return end
	local ok, bindings = pcall(game:GetService("HttpService").JSONDecode, game:GetService("HttpService"), attr("GiftBindings", "{}"))
	if ok and type(bindings) == "table" and bindings[SETTINGS_KEY.Name] ~= nil then return end
	setSettingsOpen(not settingsCard.Visible)
end)

-- The settings panel is hidden: the owner presses Y to open or close it.
local isAdmin = false
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or input.KeyCode ~= Enum.KeyCode.Y or not isAdmin then
		return
	end
	panel.Visible = not panel.Visible
	if panel.Visible then
		refreshPanelFields()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end)
RunService.RenderStepped:Connect(function()
	-- First person locks the mouse; free it while the panel or settings are open.
	if panel.Visible or settingsOpen() then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
end)

local function refreshAdmin()
	isAdmin = player:GetAttribute("DiamondRushAdmin") == true
	if not isAdmin then
		panel.Visible = false
	end
end
player:GetAttributeChangedSignal("DiamondRushAdmin"):Connect(refreshAdmin)
refreshAdmin()

-- Live updates ---------------------------------------------------------------------------
local function refreshWins()
	winsBox.Visible = attr("ShowWins", true)
	winsBox.Text = Format.wins(attr("WinTitle", "WINS"), attr("Wins", 0), attr("WinGoal", 0))
	winsBox.TextColor3 = hexColor(attr("WinTextColor", "#FFFFFF"), WHITE)
	winsBox.BackgroundColor3 = hexColor(attr("WinBackgroundColor", "#2B2140"), PANEL)
	winsStroke.Color = winsBox.TextColor3:Lerp(GOLD, 0.6)
	if panel.Visible then
		refreshPanelFields()
	end
end
for _, name in { "Wins", "WinTitle", "WinGoal", "WinTextColor", "WinBackgroundColor", "ShowWins", "NextStartingStone" } do
	State:GetAttributeChangedSignal(name):Connect(refreshWins)
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
	winsBox.Position = UDim2.new(0.5, 0, 0, if phase == "Holding" then WINS_Y_HOLDING else WINS_Y)
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
	setText(status, "TikTok: " .. tostring(attr("TikTok", "")) .. (if attr("GiftProcessing", false) then " · Updating mountain (" .. tostring(attr("GiftQueueLength", 0)) .. " queued)" else ""))

	if phase == "Holding" then
		local elapsed = now - attr("HoldStart", now)
		local shown = HoldTimer.display(elapsed, Config.HoldSeconds, Config.HoldCountFrom, Config.HoldSlowdown)
		countdown.Visible = true
		setText(countHolder, string.upper(tostring(attr("Holder", ""))) .. " IS HOLDING IT")
		setText(countNumber, tostring(shown))
		if shown ~= lastCount then
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

Notify.OnClientEvent:Connect(function(kind: string, data: any)
	if kind == "giftEffect" and type(data) == "table" then
		GiftEffects.play(data)
	elseif kind == "feed" and type(data) == "table" then
		addFeed(tostring(data.text), tonumber(data.stone) or 0, tostring(data.kind))
	elseif kind == "win" and type(data) == "table" then
		showWin(data)
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
local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude
RunService:BindToRenderStep("DiamondRushAim", Enum.RenderPriority.Camera.Value + 3, function()
	local camera = workspace.CurrentCamera
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local phase = attr("Phase", "Digging")
	local active = camera ~= nil and humanoid ~= nil and humanoid.Health > 0
		and player:GetAttribute("InGame") == true and not LobbyView.isOpen()
		and not panel.Visible and not settingsOpen() and phase ~= "Won" and phase ~= "Rebuilding"
		and not (phase == "Holding" and attr("HolderUserId", 0) == player.UserId)
	aimDot.Visible = active
	UserInputService.MouseIconEnabled = not active
	aimTarget = nil
	if active and camera then
		aimParams.FilterDescendantsInstances = if character then { character } else {}
		local viewport = camera.ViewportSize
		local ray = camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)
		local result = workspace:Raycast(ray.Origin, ray.Direction * 500, aimParams)
		if result then aimTarget = result.Instance end
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
		-- A fresh click on the diamond or the diamond bird goes to its
		-- ClickDetector, never to digging.
		local target = aimTarget
		if target == workspace:FindFirstChild("Diamond") or (target and target.Parent and target.Parent.Name == "DiamondBird") then
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
	local allowed = digging and not panel.Visible and not settingsOpen() and phase ~= "Won" and phase ~= "Rebuilding"
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
FirstPerson.onStrike(function()
	local key = digTarget()
	local character = player.Character
	if key ~= nil and (character == nil or character:FindFirstChildOfClass("Tool") == nil) then
		Request:FireServer("mine", key)
	end
end)

-- Catalogue keybinds work in-game for the streamer, outside text entry and menus.
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not isAdmin or panel.Visible or UserInputService:GetFocusedTextBox() then return end
	local ok, bindings = pcall(game:GetService("HttpService").JSONDecode, game:GetService("HttpService"), attr("GiftBindings", "{}"))
	if not ok or type(bindings) ~= "table" then return end
	local binding = bindings[input.KeyCode.Name]
	if binding then send("testGift", { coins = binding.coins, count = 1, name = binding.gift }) end
end)
