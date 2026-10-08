--!strict
-- The How to Play guide: a card in the lobby's white and gold with six
-- pages (connecting TikTok, testing without TikTok, the controls, how to
-- win, Diamond Climb and Chalkboard Count). It opens from the board beside the lobby spawn, the games menu's
-- How to play button, or H anywhere, and frees the mouse while it is open.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local HowToPlay = {}

local IVORY = Color3.fromRGB(250, 248, 243)
local GOLD = Color3.fromRGB(224, 178, 72)
local ROYAL = Color3.fromRGB(34, 52, 140)
local INK = Color3.fromRGB(46, 44, 56)
local MUTED = Color3.fromRGB(140, 132, 118)
local TITLE_FONT = Enum.Font.Merriweather
HowToPlay.KEY = Enum.KeyCode.H
-- The lobby board's prompt and click detector carry this name.
HowToPlay.BOARD = "HowToPlay"

-- Each page: its tab name and its text (Roblox rich text, so no < > or &).
HowToPlay.PAGES = {
	{
		title = "Connect TikTok",
		text = table.concat({
			"Gifts on your TikTok LIVE reach the game through <b>TikFinity</b>: it presses a key when a gift arrives, and the game plays that gift.",
			"",
			"<b>1.</b>  Here, press <b>Y</b>, then <b>Open gift settings</b>. Pick a gift, choose what it does, press <b>Set key</b> and press a key (like <b>K</b>, or <b>Shift+K</b>). Press <b>Save</b>.",
			"<b>2.</b>  In TikFinity, add an action that presses that same key, and an event that runs it when that gift is received. Do the same for each gift you want.",
			"<b>3.</b>  Go LIVE, and keep the Roblox window clicked on (focused) while you stream: the keys only reach the window in front.",
			"",
			"Likes, follows and shares can do something too: have TikFinity press a gift's key for them.",
			"Gifts sent by a key show as <b>A viewer sent</b> in the feed, and don't count on the leaderboards (the key doesn't say who sent them).",
			"To try a gift without going LIVE, press its key yourself, or use <b>Test gift</b>: see <b>Testing</b>.",
		}, "\n"),
	},
	{
		title = "Testing",
		text = table.concat({
			"<b>Y</b> opens the streamer panel in the game and frees the mouse. Press Y again to close it.",
			"",
			"<b>TEST GIFTS</b> send pretend gifts with no TikTok needed, from Rose (1 coin) up to Universe. Bigger gifts make bigger blasts.",
			"<b>REBUILD TEST GIFTS</b> add stone back, from +100 up to Grow to limit.",
			"<b>Send a diamond bird now</b> calls the diamond bird straight away.",
			"",
			"<b>Open gift settings</b> (at the top of the panel): search any TikTok gift, choose what it does in each game, its wins, its animation and whether it resets the game, and press <b>Set key</b> to give it a key. Pressing that key in the game sends that gift; TikFinity presses it for you. <b>Test gift</b> tries it out.",
		}, "\n"),
	},
	{
		title = "Controls",
		text = table.concat({
			"<b>W A S D</b> to walk, <b>Space</b> to jump, move the mouse to look.",
			"<b>Hold left mouse</b> on the mountain to dig. Stand close to the rock you aim at.",
			"<b>Click</b> the diamond to pick it up, and the diamond bird to catch it.",
			"",
			"<b>G</b>  games menu: join, or go back to the lobby",
			"<b>P</b>  settings: field of view, and hiding the GAMES and SETTINGS buttons",
			"<b>H</b>  this guide",
			"<b>Y</b>  streamer panel: gift settings, test gifts, map and settings",
			"",
			"On a phone or tablet, tap to dig and use the on-screen buttons.",
		}, "\n"),
	},
	{
		title = "How to win",
		text = table.concat({
			"Dig into the mountain to find the <b>diamond</b> hidden inside. TikTok gifts blast big holes in it, and likes, follows and shares break rocks too. Some gifts add stone back instead: the streamer chooses which.",
			"",
			"When the diamond shows, aim at it and click it from close by to pick it up.",
			"",
			"Hold it until the countdown ends (it takes 15 seconds) to win the round. You can't move while you hold it, and a gift that rebuilds rock makes you drop it.",
			"",
			"<b>Diamond bird</b>: every 5 to 7 and a half minutes a diamond bird circles the mountain. Aim at it until the dot turns gold and click: every gift counts double for 30 seconds.",
			"",
			"The leaderboards behind the mountain show the top helpers (gifts that break the mountain) and the top griefers (gifts that add stone).",
		}, "\n"),
	},
	{
		title = "Diamond Climb",
		text = table.concat({
			"Press <b>G</b> and <b>JOIN</b> Diamond Climb. Jump up <b>1,000 platforms</b> round the crystal tower to the diamond at the top.",
			"",
			"Every platform you land on is a <b>checkpoint</b>. Fall off and you are put straight back on it. Each platform is a little higher than the last, but every jump is a short hop.",
			"",
			"<b>MOVEMENT</b> (bottom right): drag <b>Speed</b> and <b>Jump height</b> to suit you. Reset puts them back. Settings (<b>P</b>) can hide this card.",
			"",
			"<b>Gifts</b> send you up the tower, more platforms for bigger gifts: a Rose is 2, 100 coins is 20, a Galaxy is 63. Some send you <b>down</b>: to start with an Ice Cream Cone, Finger Heart, Perfume, Confetti, Money Gun and TikTok Universe. The gift settings (<b>Y</b>, then <b>Open gift settings</b>) set how far each gift sends you, up or down. From 100 coins the rides take over the camera, and every tier is crazier than the last. Follows and shares lift you one platform.",
			"",
			"Reach the top, then <b>hold it</b>: stay there while the countdown runs from 10 (it slows down near the end). A gift that sends you down ends the hold. Make it to 0 to win the climb. The next one starts from the bottom.",
			"",
			"In the streamer panel (<b>Y</b>), <b>DIAMOND CLIMB</b> restarts the climb and sets the gift strength. TEST GIFTS send you up and REBUILD TEST GIFTS send you down.",
		}, "\n"),
	},
	{
		title = "Chalkboard",
		text = table.concat({
			"Press <b>G</b> and <b>JOIN</b> Chalkboard Count. You stand at a big green chalkboard in a classroom.",
			"",
			"<b>Hold to write</b>: hold the left mouse button, Space or the screen and you chalk up the next number, one after another. Reach the <b>goal</b> (1,000 to start) and <b>hold it</b> while the countdown runs from 10 (it slows down near the end). A gift that takes the count down ends the hold. Make it to 0 to win, then the board is wiped for the next one.",
			"",
			"<b>WRITING</b> (bottom right): drag <b>Speed</b> to write faster or slower, and pick a <b>theme</b> for the classroom: Classic green, Blackboard, Neon night, Sakura or Royal diamond. Settings (<b>P</b>) can hide this card.",
			"",
			"<b>Gifts</b> write numbers for you, more for bigger gifts: a Rose is 2, 100 coins is 20, a Galaxy is 63. Some take numbers <b>off</b>: to start with an Ice Cream Cone, Finger Heart, Perfume, Confetti, Money Gun and TikTok Universe. The gift settings (<b>Y</b>, then <b>Open gift settings</b>) set how far each gift moves the count, up or down. Every gift has its own animation, bigger for bigger gifts. Follows and shares add one.",
			"",
			"<b>The reset</b>: a <b>Galaxy</b> starts a 60 second countdown. When it runs out the board is wiped back to 0. Anyone who sends a different gift worth <b>1,000 coins or more</b> saves the board and stops the countdown.",
			"",
			"In the streamer panel (<b>Y</b>), <b>CHALKBOARD COUNT</b> sets the goal, which gift starts the reset, how long it lasts, how many coins save it and the gift strength. Test reset and Test save try it out without TikTok.",
		}, "\n"),
	},
}

local open = false
local setOpenHandler: ((boolean, number?) -> ())? = nil

function HowToPlay.isOpen(): boolean
	return open
end

-- Opens the guide (on `page`, or where it was left) or closes it.
function HowToPlay.setOpen(show: boolean, page: number?)
	if setOpenHandler then setOpenHandler(show, page) end
end

function HowToPlay.toggle()
	HowToPlay.setOpen(not open)
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

local function stroke(parent: Instance, colour: Color3, thickness: number)
	make("UIStroke", { Color = colour, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end

function HowToPlay.start()
	local player = Players.LocalPlayer
	local gui = make("ScreenGui", {
		Name = "HowToPlay",
		ResetOnSpawn = false,
		DisplayOrder = 20,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))
	local card = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.92, 0, 0.86, 0),
		BackgroundColor3 = IVORY,
	}, gui)
	make("UISizeConstraint", { MaxSize = Vector2.new(620, 520) }, card)
	rounded(card, 18)
	stroke(card, GOLD, 3)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 18),
		PaddingRight = UDim.new(0, 18),
		PaddingTop = UDim.new(0, 14),
		PaddingBottom = UDim.new(0, 16),
	}, card)
	make("TextLabel", {
		Size = UDim2.new(1, -110, 0, 38),
		BackgroundTransparency = 1,
		Font = TITLE_FONT,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = ROYAL,
		Text = "How to play",
	}, card)
	local close = make("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 4),
		Size = UDim2.fromOffset(96, 30),
		BackgroundColor3 = ROYAL,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "Close  H",
	}, card)
	rounded(close, 15)

	-- The page tabs.
	local tabs = make("Frame", {
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
	}, card)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, tabs)
	make("Frame", {
		Position = UDim2.fromOffset(0, 88),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = GOLD,
		BorderSizePixel = 0,
	}, card)
	local body = make("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 100),
		Size = UDim2.new(1, 0, 1, -122),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = GOLD,
	}, card)
	local text = make("TextLabel", {
		Size = UDim2.new(1, -10, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 16,
		LineHeight = 1.15,
		TextWrapped = true,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = INK,
		Text = "",
	}, body)

	local buttons: { TextButton } = {}
	local current = 1
	local function show(page: number)
		current = math.clamp(page, 1, #HowToPlay.PAGES)
		for index, button in buttons do
			local on = index == current
			button.BackgroundColor3 = if on then ROYAL else Color3.new(1, 1, 1)
			button.TextColor3 = if on then Color3.new(1, 1, 1) else ROYAL
		end
		text.Text = HowToPlay.PAGES[current].text
		body.CanvasPosition = Vector2.zero
	end
	for index, page in HowToPlay.PAGES do
		local button = make("TextButton", {
			Size = UDim2.new(1 / #HowToPlay.PAGES, -6, 1, 0),
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextScaled = false,
			TextWrapped = true,
			Text = page.title,
		}, tabs)
		rounded(button, 10)
		stroke(button, ROYAL, 1.5)
		button.Activated:Connect(function() show(index) end)
		table.insert(buttons, button)
	end
	make("TextLabel", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = MUTED,
		Text = "Open this again from the board by the lobby spawn, the games menu, or H.",
	}, card)
	show(1)

	setOpenHandler = function(visible: boolean, page: number?)
		if page then show(page) end
		open = visible
		gui.Enabled = visible
	end
	close.Activated:Connect(function() HowToPlay.setOpen(false) end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or input.KeyCode ~= HowToPlay.KEY or UserInputService:GetFocusedTextBox() then return end
		HowToPlay.toggle()
	end)
	-- The lobby board: walk up and press E, or click it.
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
		if prompt.Name == HowToPlay.BOARD and who == player then HowToPlay.setOpen(true, 1) end
	end)
	task.spawn(function()
		local lobby = workspace:WaitForChild("Lobby", math.huge)
		local board = lobby:WaitForChild("HowToPlayBoard", math.huge)
		local click = board:WaitForChild(HowToPlay.BOARD .. "Click", math.huge)
		if click:IsA("ClickDetector") then
			click.MouseClick:Connect(function() HowToPlay.setOpen(true, 1) end)
		end
	end)
	-- First person locks the mouse; free it while the guide is open.
	RunService.RenderStepped:Connect(function()
		if open then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end
	end)
end

return HowToPlay
