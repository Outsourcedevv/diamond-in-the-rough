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
GiftEffects.start(player:WaitForChild("PlayerGui"))

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

local FONT = Enum.Font.FredokaOne
local WHITE = Color3.fromRGB(255, 255, 255)
local GOLD = Color3.fromRGB(255, 205, 70)
local PANEL = Color3.fromRGB(28, 24, 40)

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
	make("UIStroke", { Thickness = thickness, Color = Color3.fromRGB(0, 0, 0), Transparency = 0.3 }, parent)
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
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(440, 108),
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.15,
}, gui)
rounded(stoneBox, 16)
make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 26),
	Position = UDim2.fromOffset(0, 6),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 22,
	TextColor3 = Color3.fromRGB(200, 195, 215),
	Text = "STONE LEFT",
}, stoneBox)
local stoneValue = make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 50),
	Position = UDim2.fromOffset(0, 28),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 50,
	TextColor3 = WHITE,
	Text = "250,000",
}, stoneBox)
outline(stoneValue, 2)
local bar = make("Frame", {
	Position = UDim2.new(0, 18, 1, -22),
	Size = UDim2.new(1, -36, 0, 12),
	BackgroundColor3 = Color3.fromRGB(60, 55, 75),
}, stoneBox)
rounded(bar, 6)
local barFill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(150, 145, 140) }, bar)
rounded(barFill, 6)

local timerLabel = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 122),
	Size = UDim2.fromOffset(300, 30),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 26,
	TextColor3 = WHITE,
	Text = "⏱ 0:00.0",
}, gui)
outline(timerLabel, 2)

-- Win counter (top right) -----------------------------------------------------------
local winsBox = make("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 8),
	Size = UDim2.fromOffset(0, 72),
	AutomaticSize = Enum.AutomaticSize.X,
	Font = FONT,
	TextSize = 46,
	Text = "WINS: 0",
}, gui)
rounded(winsBox, 16)
make("UIPadding", { PaddingLeft = UDim.new(0, 22), PaddingRight = UDim.new(0, 22) }, winsBox)
local winsStroke = make("UIStroke", { Thickness = 3, Color = GOLD, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, winsBox)


-- Banner, hold countdown and status ----------------------------------------------------
local banner = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 160),
	Size = UDim2.fromOffset(640, 54),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 40,
	TextColor3 = Color3.fromRGB(150, 240, 255),
	Text = "",
	Visible = false,
}, gui)
outline(banner, 3)

local countdown = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 10),
	Size = UDim2.fromOffset(320, 144),
	BackgroundTransparency = 1,
	Visible = false,
}, gui)
local countHolder = make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 44),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 24,
	TextScaled = true,
	TextColor3 = WHITE,
	Text = "",
}, countdown)
make("UITextSizeConstraint", { MinTextSize = 14, MaxTextSize = 24 }, countHolder)
outline(countHolder, 3)
local countNumber = make("TextLabel", {
	Position = UDim2.fromOffset(0, 40),
	Size = UDim2.new(1, 0, 0, 104),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 96,
	TextColor3 = WHITE,
	Text = "10",
}, countdown)
outline(countNumber, 5)
local countScale = make("UIScale", { Scale = 1 }, countNumber)

local status = make("TextLabel", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -12, 1, -10),
	Size = UDim2.fromOffset(520, 22),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Right,
	TextColor3 = Color3.fromRGB(230, 230, 240),
	Text = "",
}, gui)
outline(status, 1)

-- Gift feed (bottom left) -------------------------------------------------------------
local feed = make("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 12, 1, -12),
	Size = UDim2.fromOffset(440, 300),
	BackgroundTransparency = 1,
}, gui)
make("UIListLayout", {
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 6),
}, feed)
local feedOrder = 0

local function addFeed(text: string, stone: number, kind: string)
	feedOrder += 1
	local colour = if kind == "gift" then GOLD elseif kind == "follow" then Color3.fromRGB(255, 120, 170) else Color3.fromRGB(170, 220, 255)
	local row = make("TextLabel", {
		LayoutOrder = feedOrder,
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.25,
		Font = FONT,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = WHITE,
		RichText = true,
		Text = if stone ~= 0
			then string.format('%s  <font color="#%s">%s%s</font>', (text:gsub("[<>&]", "")), (if stone < 0 then Color3.fromRGB(100, 240, 170) else colour):ToHex(), if stone < 0 then "+" else "-", Format.commas(math.abs(stone)))
			else (text:gsub("[<>&]", "")),
	}, feed)
	rounded(row, 10)
	make("UIPadding", { PaddingLeft = UDim.new(0, 12) }, row)
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
			local fade = TweenService:Create(row, TweenInfo.new(0.6), { BackgroundTransparency = 1, TextTransparency = 1 })
			fade:Play()
			fade.Completed:Wait()
			row:Destroy()
		end
	end)
end

-- Win screen --------------------------------------------------------------------------
local winScreen = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(10, 8, 20),
	BackgroundTransparency = 0.25,
	Visible = false,
	ZIndex = 20,
}, gui)
local winCard = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(620, 360),
	BackgroundColor3 = PANEL,
	ZIndex = 21,
}, winScreen)
rounded(winCard, 24)
make("UIStroke", { Thickness = 4, Color = Color3.fromRGB(150, 240, 255) }, winCard)
local winScale = make("UIScale", { Scale = 1 }, winCard)
local function winLine(y: number, height: number, size: number, colour: Color3): TextLabel
	return make("TextLabel", {
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = size,
		TextColor3 = colour,
		Text = "",
		ZIndex = 22,
	}, winCard)
end
local winTitle = winLine(24, 64, 56, Color3.fromRGB(150, 240, 255))
local winWho = winLine(92, 40, 30, WHITE)
local winTime = winLine(160, 50, 40, WHITE)
local winBest = winLine(216, 50, 40, GOLD)
local winNewBest = winLine(282, 44, 34, Color3.fromRGB(120, 255, 150))

local function showWin(data: { [string]: any })
	winTitle.Text = "💎 DIAMOND SECURED!"
	winWho.Text = tostring(data.winner or "") .. " wins!"
	winTime.Text = "This round's time: " .. Format.duration(tonumber(data.time) or 0)
	winBest.Text = "Best round's time: " .. Format.duration(tonumber(data.best) or 0)
	winNewBest.Text = if data.newBest then "⭐ NEW BEST! ⭐" else ""
	winScreen.Visible = true
	winScale.Scale = 0.6
	TweenService:Create(winScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
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
	ScrollBarThickness = 6,
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.05,
	Visible = false,
	ZIndex = 10,
}, gui)
rounded(panel, 14)
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
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(200, 195, 215),
		Text = text,
		ZIndex = 11,
	}, panel)
end

local function panelBox(text: string, onSubmit: (string) -> ()): TextBox
	panelOrder += 1
	local box = make("TextBox", {
		LayoutOrder = panelOrder,
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = Color3.fromRGB(50, 44, 68),
		Font = Enum.Font.GothamMedium,
		TextSize = 17,
		TextColor3 = WHITE,
		ClearTextOnFocus = false,
		Text = text,
		ZIndex = 11,
	}, panel)
	rounded(box, 8)
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
			BackgroundColor3 = Color3.fromRGB(90, 70, 150),
			Font = FONT,
			TextSize = 16,
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
			Font = Enum.Font.GothamMedium,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = WHITE,
			Text = string.format("%s → %s rocks", tostring(name), (if (tonumber(rocks) or 0) < 0 then "ADD " else "REMOVE ") .. Format.commas(math.abs(tonumber(rocks) or 0))),
			ZIndex = 12,
		}, row)
		local remove = make("TextButton", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(34, 30),
			BackgroundColor3 = Color3.fromRGB(150, 60, 70),
			Font = FONT,
			TextSize = 16,
			TextColor3 = WHITE,
			Text = "✕",
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

panelLabel("DIAMOND BIRD (every 5 to 7½ minutes)")
panelButtons({
	{ "Send a diamond bird now", function() send("spawnBird") end },
})

panelLabel("MAP THEME (changes for everyone straight away)")
local themeButtons = panelButtons({
	{ "⛰ Alpine", function() send("setTheme", "default") end },
	{ "🌸 Sakura", function() send("setTheme", "sakura") end },
})
-- The theme showing now is lit up.
local function refreshTheme()
	local theme = attr("Theme", "default")
	for i, name in { "default", "sakura" } do
		themeButtons[i].BackgroundColor3 = if theme == name then Color3.fromRGB(214, 92, 138) else Color3.fromRGB(90, 70, 150)
	end
end
State:GetAttributeChangedSignal("Theme"):Connect(refreshTheme)
refreshTheme()

panelLabel("REBUILD TEST GIFTS (adds blocks)")
panelLabel("Tests refill dug spaces, then grow new mountain rock.")
panelButtons({
	{ "+1,000 blocks", function() send("testRebuildGift", 1000) end },
	{ "+10,000 blocks", function() send("testRebuildGift", 10000) end },
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
		BackgroundColor3 = Color3.fromRGB(90, 70, 150),
		Font = FONT,
		TextSize = 16,
		TextColor3 = WHITE,
		Text = text,
		ZIndex = 12,
	}, panel)
	rounded(button, 8)
	return button
end

panelLabel("LEADERBOARDS (behind the mountain)")
panelLabel("Test gifts and likes never count.")
panelButtons({
	{ "Preview with sample names", function() send("previewBoards") end },
})
confirmed(panelButton("Reset top gifters"), "Reset top gifters", function() send("resetBoard", "gifts") end)
confirmed(panelButton("Reset top likers"), "Reset top likers", function() send("resetBoard", "likes") end)

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
			Font = Enum.Font.GothamMedium,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Color3.fromRGB(190, 180, 210),
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
			Font = Enum.Font.GothamMedium,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = GOLD,
			Text = string.format("🏆 %s · %s coins", tostring(statue.name), Format.commas(tonumber(statue.coins) or 0)),
			ZIndex = 12,
		}, row)
		local remove = make("TextButton", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(88, 30),
			BackgroundColor3 = Color3.fromRGB(150, 60, 70),
			Font = FONT,
			TextSize = 15,
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
	-- First person locks the mouse; free it while the panel is open.
	if panel.Visible then
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
	local now = workspace:GetServerTimeNow()
	local roundStart = attr("RoundStart", now)
	setText(timerLabel, "⏱ " .. Format.duration(if phase == "Won" then attr("LastTime", 0) else now - roundStart))
	setText(status, "TikTok: " .. tostring(attr("TikTok", "")) .. (if attr("GiftProcessing", false) then " · Updating mountain (" .. tostring(attr("GiftQueueLength", 0)) .. " queued)" else ""))

	if phase == "Holding" then
		local elapsed = now - attr("HoldStart", now)
		local shown = HoldTimer.display(elapsed, Config.HoldSeconds, Config.HoldCountFrom, Config.HoldSlowdown)
		countdown.Visible = true
		setText(countHolder, "💎 " .. tostring(attr("Holder", "")) .. " — HOLD IT!")
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
			banner.Text = "REBUILDING THE MOUNTAIN"
			banner.TextTransparency = 0
		end
		if phase == "Revealed" then
			banner.Text = "DIAMOND UNCOVERED — FIND IT AND CLICK IT"
			banner.TextTransparency = 0.25 + 0.25 * math.sin(now * 6)
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
		addFeed(tostring(data.name) .. (if data.reason == "rebuild" then " — rebuild cancelled the countdown! Pick up the diamond again." else " dropped the diamond!"), 0, "drop")
	end
end)

-- Digging: hold the dig button (left mouse / touch) and your hands tear
-- through the rock you aim at, about DigPerSecond rocks a second.
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
		and not panel.Visible and phase ~= "Won" and phase ~= "Rebuilding"
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
local digClock = 0
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
		digClock = 1
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
RunService.Heartbeat:Connect(function(dt: number)
	local phase = attr("Phase", "Digging")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local target = aimTarget
	local allowed = digging and not panel.Visible and phase ~= "Won" and phase ~= "Rebuilding"
		and not (phase == "Holding" and attr("HolderUserId", 0) == player.UserId)
	local key = if target then view:keyForPart(target) else nil
	local onRock = allowed and root ~= nil and root:IsA("BasePart")
		and key ~= nil and (root.Position - (target :: BasePart).Position).Magnitude <= 16
	player:SetAttribute("DiggingRock", onRock == true)
	if not allowed then
		return
	end
	digClock += dt
	if digClock < 0.1 then
		return
	end
	digClock = 0
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if tool == nil and onRock then
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
