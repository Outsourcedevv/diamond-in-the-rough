--!strict
-- The full-screen gift settings (streamer only): every TikTok gift with a
-- search bar; pick one to set what it does in each game and the key that
-- sends it. TikFinity can press that key whenever the gift arrives on the
-- LIVE, so the game reacts to real gifts.
-- GiftMenu.start(send, state, notice) builds it; open it with GiftMenu.setOpen.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Shared = ReplicatedStorage:WaitForChild("DiamondRush")
local GiftCatalogue = require(Shared:WaitForChild("GiftCatalogue"))
local Keybinds = require(Shared:WaitForChild("Keybinds"))

local GiftMenu = {}

type Gift = { name: string, coins: number, icon: string? }

local WHITE = Color3.fromRGB(255, 255, 255)
local GOLD = Color3.fromRGB(246, 200, 92)
local MUTED = Color3.fromRGB(168, 174, 190)
local BACK = Color3.fromRGB(12, 14, 20)
local CARD = Color3.fromRGB(24, 27, 38)
local ROW = Color3.fromRGB(32, 36, 50)
local BUTTON = Color3.fromRGB(46, 50, 68)
local SELECTED = Color3.fromRGB(64, 128, 236)
local DANGER = Color3.fromRGB(176, 64, 72)
local FONT = Enum.Font.GothamBold
local FONT_MEDIUM = Enum.Font.GothamMedium
local FONT_HEAVY = Enum.Font.GothamBlack

-- Each show (1 smallest to 6 biggest) by name in each game: breaking or
-- adding stone, climbing up or down, counting up or down. The same lists as
-- GiftEffects, ClimbPath and ChalkEffects (the tests check they match).
GiftMenu.ANIMATIONS = {
	{ rough = "SPARK BURST", add = "PEBBLE DROP", up = "BOUNCE PAD", down = "BANANA SLIP", chalkUp = "CHALK STAR", chalkDown = "SPITBALL" },
	{ rough = "SHOCKWAVE", add = "ROCKSLIDE", up = "SPRING LAUNCH", down = "SPIKE BOUNCE", chalkUp = "GOLD STARS", chalkDown = "ERASER TOSS" },
	{ rough = "DIAMOND FRACTURE", add = "STONE SURGE", up = "ROCKET BOOST", down = "ANVIL SMASH", chalkUp = "PAPER PLANES", chalkDown = "SPONGE SPLASH" },
	{ rough = "ORBITAL STRIKE", add = "BOULDER BARRAGE", up = "DIAMOND CANNON", down = "METEOR STRIKE", chalkUp = "CHALK STORM", chalkDown = "BOARD QUAKE" },
	{ rough = "GALAXY COLLAPSE", add = "STONE CYCLONE", up = "STARLIGHT ASCENT", down = "THUNDER HAMMER", chalkUp = "FIREWORKS", chalkDown = "DUSTER TORNADO" },
	{ rough = "COSMIC BURST", add = "MOUNTAIN RISING", up = "GALACTIC ASCENSION", down = "BLACK HOLE PLUNGE", chalkUp = "SUPERNOVA", chalkDown = "BLACK HOLE" },
}

-- What the animation button and its line under it say for a choice (nil: auto).
function GiftMenu.animationText(tier: number?): (string, string)
	if tier == nil then
		return "Animation: Auto (picked by the coins)", "Bigger gifts play bigger shows. Press to choose one."
	end
	local a = GiftMenu.ANIMATIONS[tier]
	return string.format("Animation: %d of 6", tier),
		string.format("Rough: %s / %s · Climb: %s / %s · Chalk: %s / %s", a.rough, a.add, a.up, a.down, a.chalkUp, a.chalkDown)
end

local open = false
local onOpenChanged: { (boolean) -> () } = {}

function GiftMenu.isOpen(): boolean
	return open
end

-- What a rule shows in the list: "+5", "-20", or "auto" (from the coins).
function GiftMenu.ruleText(value: number?): string
	if value == nil then return "auto" end
	return if value > 0 then "+" .. tostring(value) else tostring(value)
end

-- A typed amount: a whole number (negative allowed), or nil for "auto".
function GiftMenu.parseAmount(text: string): number?
	local clean = string.gsub(text, "[%s,]", "")
	if clean == "" then return nil end
	local number = tonumber(clean)
	if number == nil or number ~= number then return nil end
	return math.floor(number)
end

local function make(className: string, properties: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in properties do
		(instance :: any)[key] = value
	end
	if parent then instance.Parent = parent end
	return instance
end

local function rounded(parent: Instance, radius: number)
	make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function label(parent: Instance, text: string, size: number, colour: Color3, font: Enum.Font?, height: number?): TextLabel
	return make("TextLabel", {
		Size = UDim2.new(1, 0, 0, height or size + 6),
		BackgroundTransparency = 1,
		Font = font or FONT_MEDIUM,
		TextSize = size,
		TextColor3 = colour,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Text = text,
	}, parent)
end

local function box(parent: Instance, placeholder: string): TextBox
	local input = make("TextBox", {
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundColor3 = ROW,
		Font = FONT_MEDIUM,
		TextSize = 17,
		TextColor3 = WHITE,
		PlaceholderColor3 = Color3.fromRGB(120, 126, 142),
		PlaceholderText = placeholder,
		ClearTextOnFocus = false,
		Text = "",
	}, parent)
	rounded(input, 8)
	make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, input)
	return input
end

local function button(parent: Instance, text: string, colour: Color3?): TextButton
	local b = make("TextButton", {
		Size = UDim2.new(0, 150, 0, 38),
		BackgroundColor3 = colour or BUTTON,
		Font = FONT,
		TextSize = 15,
		TextColor3 = WHITE,
		Text = text,
		AutoButtonColor = true,
	}, parent)
	rounded(b, 8)
	return b
end

function GiftMenu.setOpen(value: boolean)
	if value == open then return end
	open = value
	for _, listener in onOpenChanged do task.spawn(listener, value) end
end

-- `send(action, value)` asks the server; `state` holds the published settings.
function GiftMenu.start(send: (string, any) -> (), state: Instance)
	local player = Players.LocalPlayer
	local function decode(name: string): { [string]: any }
		local ok, data = pcall(HttpService.JSONDecode, HttpService, (state:GetAttribute(name) :: any) or "{}")
		return if ok and type(data) == "table" then data else {}
	end

	local gui = make("ScreenGui", {
		Name = "GiftSettings",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 40, -- above every other card and menu
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))
	-- A full-screen button underneath, so clicks never fall through to the game.
	local screen = make("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = BACK,
		BackgroundTransparency = 0.04,
		AutoButtonColor = false,
		Text = "",
		Modal = true,
	}, gui)
	local page = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -48, 1, -48),
		BackgroundTransparency = 1,
	}, screen)
	make("UISizeConstraint", { MaxSize = Vector2.new(1400, 900) }, page)

	-- Header: title, how to use it with TikFinity, close.
	local header = make("Frame", { Size = UDim2.new(1, 0, 0, 86), BackgroundTransparency = 1 }, page)
	local title = label(header, "GIFT SETTINGS", 30, GOLD, FONT_HEAVY, 36)
	title.Size = UDim2.new(1, -170, 0, 36)
	local help = label(header, "Pick a gift to set what it does in each game. Give it a key, and in TikFinity add an action that presses that key when the gift arrives: keep the Roblox window focused while you stream.", 14, MUTED, FONT_MEDIUM, 44)
	help.Position = UDim2.fromOffset(0, 40)
	help.Size = UDim2.new(1, -170, 0, 44)
	local close = button(header, "Close", DANGER)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 0, 0, 0)
	close.Activated:Connect(function() GiftMenu.setOpen(false) end)

	-- Left: search and the gift list.
	local left = make("Frame", {
		Position = UDim2.fromOffset(0, 96),
		Size = UDim2.new(0.56, -10, 1, -96),
		BackgroundColor3 = CARD,
	}, page)
	rounded(left, 12)
	make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12) }, left)
	local search = box(left, "Search gifts, e.g. Rose, Galaxy, Lion…")
	search.Size = UDim2.new(1, 0, 0, 44)
	search.TextSize = 18
	local count = label(left, "", 13, MUTED, FONT_MEDIUM, 18)
	count.Position = UDim2.fromOffset(2, 50)
	local list = make("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 72),
		Size = UDim2.new(1, 0, 1, -72),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 10,
		ScrollBarImageColor3 = MUTED,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
	}, left)
	local listLayout = make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, list)
	listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		list.CanvasSize = UDim2.fromOffset(0, listLayout.AbsoluteContentSize.Y + 6)
	end)

	-- Right: the chosen gift's settings.
	local right = make("ScrollingFrame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 96),
		Size = UDim2.new(0.44, -10, 1, -96),
		BackgroundColor3 = CARD,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 10,
		ScrollBarImageColor3 = MUTED,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
	}, page)
	rounded(right, 12)
	make("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 16) }, right)
	local rightLayout = make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }, right)
	rightLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		right.CanvasSize = UDim2.fromOffset(0, rightLayout.AbsoluteContentSize.Y + 30)
	end)
	local order = 0
	local function add<T>(instance: T): T
		order += 1;
		(instance :: any).LayoutOrder = order
		return instance
	end
	local giftName = add(label(right, "Pick a gift", 26, WHITE, FONT_HEAVY, 32))
	local giftCoins = add(label(right, "", 15, MUTED, FONT_MEDIUM, 20))
	add(label(right, "COINS PER GIFT (change it if TikTok's price is different where you are)", 13, MUTED, FONT, 18))
	local coinsBox = add(box(right, "Coins per gift"))
	local function section(heading: string, hint: string, placeholder: string): TextBox
		add(label(right, heading, 15, GOLD, FONT, 20))
		add(label(right, hint, 13, MUTED, FONT_MEDIUM, 34))
		return add(box(right, placeholder))
	end
	local roughBox = section("DIAMOND IN THE ROUGH: rocks per gift", "Positive breaks that many rocks off the mountain; negative adds stone. Empty: worked out from the coins.", "auto (from the coins)")
	local climbBox = section("DIAMOND CLIMB: platforms per gift", "Positive sends the climber up; negative sends them down. Empty: worked out from the coins.", "auto (from the coins)")
	local chalkBox = section("CHALKBOARD COUNT: numbers per gift", "Positive counts up; negative counts down. Empty: worked out from the coins.", "auto (from the coins)")
	-- Chalkboard Count's own reset gift (Y panel) starts its countdown instead.
	local chalkNote = add(label(right, "", 13, GOLD, FONT_MEDIUM, 34))
	chalkNote.Visible = false
	local winsBox = section("WINS per gift", "Adds wins (e.g. 1) or takes them away (e.g. -1) on the win counter of whichever game you're playing. Empty: no change.", "no change")
	add(label(right, "ANIMATION", 15, GOLD, FONT, 20))
	local animButton = add(button(right, "Animation: Auto"))
	animButton.Size = UDim2.new(1, 0, 0, 38)
	local animNames = add(label(right, "", 13, MUTED, FONT_MEDIUM, 34))
	add(label(right, "RESET", 15, GOLD, FONT, 20))
	add(label(right, "On: this gift sends the game you're playing back to the start (a full mountain, platform 0, or a count of 0), and does nothing else.", 13, MUTED, FONT_MEDIUM, 34))
	local resetToggle = add(button(right, "Reset: off"))
	resetToggle.Size = UDim2.new(1, 0, 0, 38)
	add(label(right, "KEYBIND (for TikFinity)", 15, GOLD, FONT, 20))
	add(label(right, "Press the button, then the key. Shift or Ctrl with a key works too. Pressing it in the game sends this gift.", 13, MUTED, FONT_MEDIUM, 34))
	local keyRow = add(make("Frame", { Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1 }, right))
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }, keyRow)
	local keyButton = button(keyRow, "Set key")
	keyButton.Size = UDim2.new(0.6, -4, 1, 0)
	local clearKey = button(keyRow, "No key")
	clearKey.Size = UDim2.new(0.4, -4, 1, 0)
	local actions = add(make("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1 }, right))
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }, actions)
	local save = button(actions, "Save", SELECTED)
	save.Size = UDim2.new(0.4, -6, 1, 0)
	save.TextSize = 17
	local test = button(actions, "Test gift")
	test.Size = UDim2.new(0.3, -6, 1, 0)
	local reset = button(actions, "Reset")
	reset.Size = UDim2.new(0.3, -6, 1, 0)
	local removeCustom = add(button(right, "Remove this gift", DANGER))
	removeCustom.Size = UDim2.new(1, 0, 0, 34)
	local status = add(label(right, "", 14, GOLD, FONT_MEDIUM, 22))

	-- The chosen gift and its key (while editing).
	local chosen: Gift? = nil
	local chosenKey = ""
	local chosenReset = false
	local chosenAnim: number? = nil
	local function showAnim()
		local text, names = GiftMenu.animationText(chosenAnim)
		animButton.Text = text
		animButton.BackgroundColor3 = if chosenAnim then SELECTED else BUTTON
		animNames.Text = names
	end
	local function showReset()
		resetToggle.Text = if chosenReset then "Reset: ON (back to the start)" else "Reset: off"
		resetToggle.BackgroundColor3 = if chosenReset then DANGER else BUTTON
	end
	local capturing = false

	local function rules()
		return decode("GiftRules"), decode("ClimbRules"), decode("ChalkRules"), decode("GiftBindings"), decode("CustomGifts"), decode("WinRules"), decode("ResetGifts"), decode("AnimRules")
	end
	local function keyFor(bindings: { [string]: any }, name: string): string
		local lower = string.lower(name)
		for key, binding in bindings do
			if type(binding) == "table" and type(binding.gift) == "string" and string.lower(binding.gift) == lower then return key end
		end
		return ""
	end
	local function showKey()
		keyButton.Text = if capturing then "Press a key…" elseif chosenKey ~= "" then "Key: " .. Keybinds.label(chosenKey) else "Set key"
		keyButton.BackgroundColor3 = if capturing then SELECTED else BUTTON
	end

	local function choose(gift: Gift?, custom: boolean)
		chosen = gift
		capturing = false
		status.Text = ""
		local rough, climb, chalk, bindings, _, wins, resets, anims = rules()
		if gift == nil then
			chosenReset = false
			showReset()
			chosenAnim = nil
			showAnim()
			giftName.Text = "Pick a gift"
			giftCoins.Text = "Choose one from the list, or search for a gift that's missing to add it."
			coinsBox.Visible = false
			removeCustom.Visible = false
			chalkNote.Visible = false
			for _, input in { roughBox, climbBox, chalkBox, winsBox } do input.Text = "" end
			chosenKey = ""
			showKey()
			return
		end
		local lower = string.lower(gift.name)
		giftName.Text = (gift.icon or GiftCatalogue.ICON) .. "  " .. gift.name
		giftCoins.Text = string.format("%s coin%s", tostring(gift.coins), if gift.coins == 1 then "" else "s")
		coinsBox.Visible = true
		coinsBox.Text = tostring(gift.coins)
		removeCustom.Visible = custom and GiftCatalogue.find(gift.name) == nil
		roughBox.Text = if type(rough[lower]) == "number" then tostring(rough[lower]) else ""
		climbBox.Text = if type(climb[lower]) == "number" then tostring(climb[lower]) else ""
		chalkBox.Text = if type(chalk[lower]) == "number" then tostring(chalk[lower]) else ""
		winsBox.Text = if type(wins[lower]) == "number" then tostring(wins[lower]) else ""
		chosenReset = resets[lower] == true
		showReset()
		chosenAnim = if type(anims[lower]) == "number" then anims[lower] else nil
		showAnim()
		chosenKey = keyFor(bindings, gift.name)
		showKey()
		local countdownGift = state:GetAttribute("ChalkResetGift")
		chalkNote.Visible = type(countdownGift) == "string" and string.lower(countdownGift) == lower
		chalkNote.Text = "In Chalkboard Count this is the countdown reset gift (set in the Y panel), so there it starts the countdown and the number above isn't used."
	end

	-- The list, drawn again whenever the search or the settings change.
	local function draw()
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then child:Destroy() end
		end
		local rough, climb, chalk, bindings, custom, wins, resets, anims = rules()
		local all = GiftCatalogue.all(custom :: any)
		local shown = GiftCatalogue.search(all, search.Text)
		local query = (string.gsub(search.Text, "^%s*(.-)%s*$", "%1"))
		local exact = false
		for _, gift in shown do
			if string.lower(gift.name) == string.lower(query) then exact = true end
		end
		local rowOrder = 0
		if query ~= "" and not exact then
			-- A gift that isn't in the list yet: add it.
			rowOrder += 1
			local addRow = make("TextButton", {
				LayoutOrder = rowOrder,
				Size = UDim2.new(1, 0, 0, 46),
				BackgroundColor3 = SELECTED,
				Font = FONT,
				TextSize = 16,
				TextColor3 = WHITE,
				Text = string.format("+  Add \"%s\" as a gift", string.sub(query, 1, 40)),
			}, list)
			rounded(addRow, 8)
			addRow.Activated:Connect(function()
				choose({ name = string.sub(query, 1, 40), coins = 1 }, true)
				status.Text = "Type its coins, set what it does, then Save."
			end)
		end
		count.Text = string.format("%d gift%s", #shown, if #shown == 1 then "" else "s")
		for _, gift in shown do
			rowOrder += 1
			local lower = string.lower(gift.name)
			local key = keyFor(bindings, gift.name)
			local isChosen = chosen ~= nil and string.lower((chosen :: Gift).name) == lower
			local row = make("TextButton", {
				LayoutOrder = rowOrder,
				Size = UDim2.new(1, 0, 0, 46),
				BackgroundColor3 = if isChosen then SELECTED else ROW,
				AutoButtonColor = true,
				Text = "",
			}, list)
			rounded(row, 8)
			make("TextLabel", {
				Position = UDim2.fromOffset(8, 0),
				Size = UDim2.new(0, 34, 1, 0),
				BackgroundTransparency = 1,
				Font = FONT,
				TextSize = 24,
				TextColor3 = WHITE,
				Text = gift.icon or GiftCatalogue.ICON,
			}, row)
			make("TextLabel", {
				Position = UDim2.fromOffset(48, 0),
				Size = UDim2.new(0.42, -48, 1, 0),
				BackgroundTransparency = 1,
				Font = FONT,
				TextSize = 16,
				TextColor3 = WHITE,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = gift.name,
			}, row)
			make("TextLabel", {
				Position = UDim2.new(0.42, 0, 0, 0),
				Size = UDim2.new(0.14, 0, 1, 0),
				BackgroundTransparency = 1,
				Font = FONT_MEDIUM,
				TextSize = 14,
				TextColor3 = GOLD,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = tostring(gift.coins) .. " c",
			}, row)
			make("TextLabel", {
				Position = UDim2.new(0.56, 0, 0, 0),
				Size = UDim2.new(0.44, -12, 1, 0),
				BackgroundTransparency = 1,
				Font = FONT_MEDIUM,
				TextSize = 13,
				TextColor3 = MUTED,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = string.format("Rough %s · Climb %s · Chalk %s%s%s",
					GiftMenu.ruleText(rough[lower]), GiftMenu.ruleText(climb[lower]), GiftMenu.ruleText(chalk[lower]),
					(if type(wins[lower]) == "number" and wins[lower] ~= 0 then " · Wins " .. GiftMenu.ruleText(wins[lower]) else "")
						.. (if resets[lower] == true then " · RESET" else "")
						.. (if type(anims[lower]) == "number" then " · Anim " .. tostring(anims[lower]) else ""),
					if key ~= "" then " · [" .. Keybinds.label(key) .. "]" else ""),
			}, row)
			row.Activated:Connect(function()
				choose(gift, (custom :: any)[gift.name] ~= nil)
				draw()
			end)
		end
	end

	search:GetPropertyChangedSignal("Text"):Connect(draw)
	for _, name in { "GiftRules", "ClimbRules", "ChalkRules", "GiftBindings", "CustomGifts", "WinRules", "ResetGifts", "AnimRules" } do
		state:GetAttributeChangedSignal(name):Connect(function()
			if open then draw() end
		end)
	end

	keyButton.Activated:Connect(function()
		if chosen == nil then return end
		capturing = true
		showKey()
	end)
	animButton.Activated:Connect(function()
		if chosen == nil then return end
		-- Auto, then 1 to 6, then auto again.
		chosenAnim = if chosenAnim == nil then 1 elseif chosenAnim >= 6 then nil else chosenAnim + 1
		showAnim()
	end)
	resetToggle.Activated:Connect(function()
		if chosen == nil then return end
		chosenReset = not chosenReset
		showReset()
	end)
	clearKey.Activated:Connect(function()
		capturing = false
		chosenKey = ""
		showKey()
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if not open or not capturing or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		local key = input.KeyCode.Name
		-- Wait for the real key while Shift or Ctrl is being held down.
		if string.find(key, "Shift", 1, true) or string.find(key, "Control", 1, true) then return end
		capturing = false
		local combo = Keybinds.combo(key,
			UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl),
			UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift))
		if Keybinds.allowed(combo) then
			chosenKey = combo
			status.Text = ""
		else
			status.Text = Keybinds.label(combo) .. " is used by the game or Roblox. Try a letter like K, a number, F1–F8 on their own or the number pad."
		end
		showKey()
	end)

	local function current(): { [string]: any }?
		local gift = chosen
		if gift == nil then return nil end
		local coins = tonumber((string.gsub(coinsBox.Text, "[^%d]", ""))) or 0
		if coins < 1 then
			status.Text = "Type how many coins the gift costs."
			return nil
		end
		return {
			gift = gift.name,
			coins = coins,
			rough = GiftMenu.parseAmount(roughBox.Text),
			climb = GiftMenu.parseAmount(climbBox.Text),
			chalk = GiftMenu.parseAmount(chalkBox.Text),
			wins = GiftMenu.parseAmount(winsBox.Text),
			reset = chosenReset,
			anim = chosenAnim,
			key = chosenKey,
		}
	end
	save.Activated:Connect(function()
		local value = current()
		if value == nil then return end
		send("setGiftSettings", value)
		status.Text = "Saved."
		if chosen then (chosen :: Gift).coins = value.coins end
	end)
	test.Activated:Connect(function()
		local value = current()
		if value == nil then return end
		-- Saved first, so the test plays what the boxes say now (the server
		-- handles the two in order).
		send("setGiftSettings", value)
		if chosen then (chosen :: Gift).coins = value.coins end
		send("testGift", { coins = value.coins, count = 1, name = value.gift })
		status.Text = "Saved, and sent a test " .. value.gift .. " (test gifts never count on the leaderboards)."
	end)
	reset.Activated:Connect(function()
		if chosen == nil then return end
		roughBox.Text, climbBox.Text, chalkBox.Text, winsBox.Text = "", "", "", ""
		chosenReset = false
		showReset()
		chosenAnim = nil
		showAnim()
		chosenKey = ""
		capturing = false
		showKey()
		status.Text = "Back to auto with no key: press Save to keep it."
	end)
	removeCustom.Activated:Connect(function()
		local gift = chosen
		if gift == nil then return end
		send("removeCustomGift", gift.name)
		choose(nil, false)
	end)

	table.insert(onOpenChanged, function(value: boolean)
		gui.Enabled = value
		capturing = false
		if value then
			draw()
			if chosen == nil then choose(nil, false) end
		end
	end)
	choose(nil, false)
end

return GiftMenu
