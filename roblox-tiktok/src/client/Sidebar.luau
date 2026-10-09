--!strict
-- The sidebar on the left of the screen, everywhere (the lobby and every
-- game): GIFTS (the streamer's gift settings), THEMES (the map's theme, the
-- paid ones bought with Robux), SETTINGS and GAMES, each with a drawn icon.
-- The arrow on its edge slides it away and back. Settings can hide it
-- altogether (on a keyboard: G, P and Y still work).
--
-- The Themes card lives here too: each theme with a little picture of it and
-- a button that says IN USE, USE (free or bought) or its price in Robux.
-- Buying prompts Roblox's own purchase; the server checks what each player
-- owns and puts a bought theme on the map (see ThemeShop).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("DiamondRush")
local Config = require(Shared:WaitForChild("Config"))
local ThemeShop = require(Shared:WaitForChild("ThemeShop"))

local Sidebar = {}

local WHITE = Color3.fromRGB(255, 255, 255)
local MUTED = Color3.fromRGB(168, 174, 190)
local GLASS = Color3.fromRGB(16, 18, 26)
local BUTTON = Color3.fromRGB(46, 50, 68)
local SELECTED = Color3.fromRGB(64, 128, 236)
local GOLD = Color3.fromRGB(246, 200, 92)
local GREEN = Color3.fromRGB(46, 164, 96)
local FONT = Enum.Font.GothamBold
local FONT_MEDIUM = Enum.Font.GothamMedium

Sidebar.BAR_WIDTH = 84
Sidebar.MARGIN = 10
-- Where the cards that open from the sidebar sit: just to its right.
Sidebar.PANEL_LEFT = Sidebar.MARGIN + Sidebar.BAR_WIDTH + 12
Sidebar.CENTRE = 0.42 -- of the screen's height: clear of the gift feed below
Sidebar.ITEMS = { "gifts", "themes", "settings", "games" }
Sidebar.LABELS = { gifts = "GIFTS", themes = "THEMES", settings = "SETTINGS", games = "GAMES" }

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

local function round(parent: Instance)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, parent)
end

local function glass(frame: GuiObject, radius: number)
	frame.BackgroundColor3 = GLASS
	frame.BackgroundTransparency = 0.12
	frame.BorderSizePixel = 0
	rounded(frame, radius)
	make("UIStroke", { Color = WHITE, Transparency = 0.86, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame)
end

-- A piece of an icon: a frame at (x, y) (its centre, in scale of the icon),
-- w by h (scale), turned `rotation` degrees.
local function bit(icon: Frame, x: number, y: number, w: number, h: number, colour: Color3, rotation: number?, corner: number?): Frame
	local frame = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(w, h),
		Rotation = rotation or 0,
		BackgroundColor3 = colour,
		BorderSizePixel = 0,
		ZIndex = icon.ZIndex + 1,
	}, icon)
	if corner == -1 then round(frame) elseif corner then make("UICorner", { CornerRadius = UDim.new(corner, 0) }, frame) end
	return frame
end

-- The drawn icons: a wrapped gift, a painter's palette, a gear and a game
-- controller. Drawn from frames, so they need no uploaded images.
function Sidebar.icon(kind: string, parent: Instance, size: number): Frame
	local icon = make("Frame", { Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, ZIndex = 3 }, parent)
	if kind == "gifts" then
		local red = Color3.fromRGB(232, 64, 84)
		bit(icon, 0.5, 0.66, 0.72, 0.5, GOLD, 0, 0.12) -- the box
		bit(icon, 0.5, 0.38, 0.84, 0.16, Color3.fromRGB(255, 220, 128), 0, 0.2) -- its lid
		bit(icon, 0.5, 0.6, 0.14, 0.62, red) -- the ribbon down
		bit(icon, 0.36, 0.2, 0.26, 0.18, red, 30, -1) -- the bow
		bit(icon, 0.64, 0.2, 0.26, 0.18, red, -30, -1)
		bit(icon, 0.5, 0.26, 0.12, 0.12, Color3.fromRGB(190, 40, 60), 0, -1)
	elseif kind == "themes" then
		bit(icon, 0.5, 0.52, 0.86, 0.74, Color3.fromRGB(240, 226, 196), -10, -1) -- the palette
		bit(icon, 0.66, 0.68, 0.18, 0.16, Color3.fromRGB(40, 44, 60), 0, -1) -- its thumb hole
		bit(icon, 0.3, 0.42, 0.16, 0.16, Color3.fromRGB(232, 64, 84), 0, -1) -- paint
		bit(icon, 0.47, 0.3, 0.16, 0.16, Color3.fromRGB(246, 200, 92), 0, -1)
		bit(icon, 0.66, 0.36, 0.16, 0.16, Color3.fromRGB(86, 170, 255), 0, -1)
		bit(icon, 0.32, 0.64, 0.16, 0.16, Color3.fromRGB(96, 200, 120), 0, -1)
	elseif kind == "settings" then
		local steel = Color3.fromRGB(200, 208, 224)
		for k = 0, 3 do
			bit(icon, 0.5, 0.5, 0.2, 0.9, steel, k * 45, 0.2) -- four bars crossing: eight teeth
		end
		bit(icon, 0.5, 0.5, 0.68, 0.68, steel, 0, -1)
		bit(icon, 0.5, 0.5, 0.28, 0.28, Color3.fromRGB(40, 44, 60), 0, -1)
	else -- games: a controller
		local body = Color3.fromRGB(150, 120, 255)
		bit(icon, 0.5, 0.55, 0.92, 0.5, body, 0, 0.45)
		bit(icon, 0.24, 0.72, 0.26, 0.32, body, 0, -1) -- grips
		bit(icon, 0.76, 0.72, 0.26, 0.32, body, 0, -1)
		local dark = Color3.fromRGB(40, 44, 60)
		bit(icon, 0.3, 0.54, 0.24, 0.08, dark) -- the cross
		bit(icon, 0.3, 0.54, 0.08, 0.24, dark)
		bit(icon, 0.68, 0.48, 0.1, 0.1, Color3.fromRGB(255, 220, 128), 0, -1) -- buttons
		bit(icon, 0.78, 0.6, 0.1, 0.1, Color3.fromRGB(232, 64, 84), 0, -1)
	end
	return icon
end

export type Options = {
	request: RemoteEvent,
	state: Instance,
	-- A sidebar button was pressed ("gifts", "themes", "settings", "games").
	onPick: (name: string) -> (),
	-- Which card is open now (nil: none), so its button lights up.
	active: () -> string?,
}

local themesOpen = false
local setThemesOpenHandler: (boolean) -> () = function() end
local adminHandler: (boolean) -> () = function() end
local hiddenHandler: (boolean) -> () = function() end

function Sidebar.themesOpen(): boolean
	return themesOpen
end

function Sidebar.setThemesOpen(show: boolean)
	setThemesOpenHandler(show)
end

-- GIFTS shows for the streamer only.
function Sidebar.setAdmin(isAdmin: boolean)
	adminHandler(isAdmin)
end

-- Hidden from the settings (the arrow too).
function Sidebar.setHidden(hidden: boolean)
	hiddenHandler(hidden)
end

function Sidebar.start(options: Options)
	local player = Players.LocalPlayer
	local gui = make("ScreenGui", {
		Name = "Sidebar",
		ResetOnSpawn = false,
		DisplayOrder = 6,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))

	-- The bar --------------------------------------------------------------------
	local ITEM = 70
	local bar = make("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, Sidebar.MARGIN, Sidebar.CENTRE, 0),
		Size = UDim2.fromOffset(Sidebar.BAR_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, gui)
	glass(bar, 16)
	make("UIPadding", { PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7), PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }, bar)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center }, bar)
	local buttons: { [string]: TextButton } = {}
	local hovered: { [string]: boolean } = {}
	-- The open card's button is lit; one under the mouse is shaded.
	local function light()
		local active = options.active()
		for name, button in buttons do
			button.BackgroundColor3 = if active == name then SELECTED else BUTTON
			button.BackgroundTransparency = if active == name then 0.1 elseif hovered[name] then 0.5 else 1
		end
	end
	for index, name in Sidebar.ITEMS do
		local button = make("TextButton", {
			LayoutOrder = index,
			Size = UDim2.fromOffset(Sidebar.BAR_WIDTH - 14, ITEM),
			BackgroundColor3 = BUTTON,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 2,
		}, bar)
		rounded(button, 12)
		local icon = Sidebar.icon(name, button, 38)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 8)
		make("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, 0, 0, 14),
			BackgroundTransparency = 1,
			Font = FONT,
			TextSize = 11,
			TextColor3 = WHITE,
			Text = Sidebar.LABELS[name],
			ZIndex = 3,
		}, button)
		button.MouseEnter:Connect(function() hovered[name] = true; light() end)
		button.MouseLeave:Connect(function() hovered[name] = nil; light() end)
		button.Activated:Connect(function()
			options.onPick(name)
			light()
		end)
		buttons[name] = button
	end
	-- Cards also open and close by key (G, P, Y): look again now and then.
	task.spawn(function()
		while gui.Parent do
			light()
			task.wait(0.2)
		end
	end)

	-- The arrow on the bar's edge slides it away, and back.
	local arrow = make("TextButton", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 4, 0.5, 0),
		Size = UDim2.fromOffset(22, 58),
		Font = FONT,
		TextSize = 22,
		TextColor3 = WHITE,
		Text = "‹",
		AutoButtonColor = true,
	}, bar)
	glass(arrow, 10)
	local collapsed = false
	local slide: Tween? = nil
	local function setCollapsed(value: boolean)
		collapsed = value
		arrow.Text = if value then "›" else "‹"
		if slide then slide:Cancel() end
		local x = if value then -(Sidebar.BAR_WIDTH + 2) else Sidebar.MARGIN
		local tween = TweenService:Create(bar, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = UDim2.new(0, x, Sidebar.CENTRE, 0) })
		slide = tween
		tween:Play()
	end
	arrow.Activated:Connect(function() setCollapsed(not collapsed) end)

	adminHandler = function(isAdmin: boolean)
		buttons.gifts.Visible = isAdmin
	end
	hiddenHandler = function(hidden: boolean)
		gui.Enabled = not hidden
	end

	-- The Themes card -------------------------------------------------------------
	local card = make("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, Sidebar.PANEL_LEFT, Sidebar.CENTRE, 0),
		Size = UDim2.fromOffset(360, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		ZIndex = 5,
	}, gui)
	glass(card, 14)
	make("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14), PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, card)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }, card)
	local header = make("Frame", { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, ZIndex = 6 }, card)
	make("TextLabel", { Size = UDim2.new(1, -40, 0, 22), BackgroundTransparency = 1, Font = FONT, TextSize = 18, TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left, Text = "THEMES", ZIndex = 6 }, header)
	make("TextLabel", { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, -40, 0, 18), BackgroundTransparency = 1, Font = FONT_MEDIUM, TextSize = 12,
		TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left, Text = "The map's look, for everyone. Buy one once, keep it.", ZIndex = 6 }, header)
	local closeCard = make("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(32, 32),
		BackgroundColor3 = BUTTON, Font = FONT, TextSize = 16, TextColor3 = WHITE, Text = "X", ZIndex = 6 }, header)
	rounded(closeCard, 8)
	local message = make("TextLabel", { LayoutOrder = 99, Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Font = FONT_MEDIUM, TextSize = 12,
		TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Text = "", ZIndex = 6 }, card)

	local prices: { [string]: number } = {}
	local rows: { [string]: { button: TextButton, kind: string } } = {}
	local function refreshRows()
		local current = tostring(options.state:GetAttribute("Theme") or "default")
		local owned = ThemeShop.decode(player:GetAttribute("OwnedThemes"))
		for key, row in rows do
			local label, kind = ThemeShop.status(key, current, owned, Config.ThemePasses, prices[key])
			row.kind = kind
			row.button.Text = label
			row.button.BackgroundColor3 = if kind == "using" then BUTTON elseif kind == "use" then SELECTED else GREEN
			row.button.AutoButtonColor = kind ~= "using"
		end
	end
	for index, theme in ThemeShop.THEMES do
		local row = make("Frame", { LayoutOrder = index, Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = BUTTON, BackgroundTransparency = 0.5, ZIndex = 6 }, card)
		rounded(row, 10)
		-- A little picture of the theme: its sky, its ground and a highlight.
		local picture = make("Frame", { Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(64, 44), BackgroundColor3 = theme.sky, ClipsDescendants = true, ZIndex = 7 }, row)
		rounded(picture, 8)
		make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.4), BackgroundColor3 = theme.ground, BorderSizePixel = 0, ZIndex = 8 }, picture)
		local peak = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.42, 0.62), Size = UDim2.fromOffset(26, 26), Rotation = 45,
			BackgroundColor3 = theme.ground:Lerp(Color3.new(0, 0, 0), 0.25), BorderSizePixel = 0, ZIndex = 8 }, picture)
		peak.ZIndex = 8
		make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.78, 0.3), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = theme.accent, BorderSizePixel = 0, ZIndex = 9 }, picture).Name = "Highlight"
		make("TextLabel", { Position = UDim2.fromOffset(80, 8), Size = UDim2.new(1, -180, 0, 20), BackgroundTransparency = 1, Font = FONT, TextSize = 16, TextColor3 = WHITE,
			TextXAlignment = Enum.TextXAlignment.Left, Text = theme.name, ZIndex = 7 }, row)
		make("TextLabel", { Position = UDim2.fromOffset(80, 28), Size = UDim2.new(1, -180, 0, 18), BackgroundTransparency = 1, Font = FONT_MEDIUM, TextSize = 11, TextColor3 = MUTED,
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = theme.blurb, ZIndex = 7 }, row)
		local button = make("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(88, 32),
			BackgroundColor3 = SELECTED, Font = FONT, TextSize = 14, TextColor3 = WHITE, Text = "", ZIndex = 7 }, row)
		rounded(button, 8)
		rows[theme.key] = { button = button, kind = "use" }
		button.Activated:Connect(function()
			local kind = rows[theme.key].kind
			if kind == "use" then
				options.request:FireServer("setTheme", theme.key)
				message.Text = theme.name .. " is going on the map."
			elseif kind == "buy" then
				local pass = ThemeShop.pass(theme.key, Config.ThemePasses)
				if pass then
					message.Text = ""
					local ok = pcall(MarketplaceService.PromptGamePassPurchase, MarketplaceService, player, pass)
					if not ok then message.Text = "Roblox couldn't open the purchase. Try again in a moment." end
				end
			end
		end)
		-- Its price, asked of Roblox once.
		local pass = ThemeShop.pass(theme.key, Config.ThemePasses)
		if pass then
			task.spawn(function()
				local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, pass, Enum.InfoType.GamePass)
				if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
					prices[theme.key] = info.PriceInRobux
					refreshRows()
				end
			end)
		end
	end
	options.state:GetAttributeChangedSignal("Theme"):Connect(function()
		refreshRows()
		message.Text = ""
	end)
	player:GetAttributeChangedSignal("OwnedThemes"):Connect(refreshRows)
	refreshRows()

	setThemesOpenHandler = function(show: boolean)
		themesOpen = show
		card.Visible = show
		if show then message.Text = "" end
	end
	closeCard.Activated:Connect(function() setThemesOpenHandler(false) end)
end

return Sidebar
