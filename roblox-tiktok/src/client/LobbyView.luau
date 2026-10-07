--!strict
-- The games menu on the left of the screen, in the lobby's royal white and
-- gold: Diamond in the Rough with its live status and a Join button, Diamond
-- Climb with the climber's platform and a Join button, Chalkboard Count with
-- the count on the board and a Join button, a slot marked Coming soon, How to play, and Back to lobby while playing. The
-- Hide button hides it to a small tab; the tab (or G) shows it again. The tab
-- itself can be hidden from the settings (G still works). Also turns the
-- lobby's giant diamond on this computer.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Shared = ReplicatedStorage:WaitForChild("DiamondRush")
local Format = require(Shared:WaitForChild("Format"))
local Skin = require(Shared:WaitForChild("Skin"))

local LobbyView = {}

local IVORY = Color3.fromRGB(250, 248, 243)
local GOLD = Color3.fromRGB(224, 178, 72)
local ROYAL = Color3.fromRGB(34, 52, 140)
local ROYAL_DEEP = Color3.fromRGB(18, 28, 92)
local MUTED = Color3.fromRGB(140, 132, 118)
local TITLE_FONT = Enum.Font.Merriweather
local WIDTH = 360
local TOGGLE_KEY = Enum.KeyCode.G

local open = false
local tabHidden = false
local refreshTab: () -> () = function() end

function LobbyView.isOpen(): boolean
	return open
end

-- Closes the menu (the settings card opens where it would cover it).
local closeHandler: () -> () = function() end
function LobbyView.close()
	closeHandler()
end

-- Hides the GAMES tab (the settings' "Hide buttons"); G still opens the menu.
function LobbyView.setTabHidden(hidden: boolean)
	tabHidden = hidden
	refreshTab()
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

local function stroke(parent: Instance, colour: Color3, thickness: number, transparency: number?)
	make("UIStroke", { Color = colour, Thickness = thickness, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end

local function text(parent: Instance, properties: { [string]: any }): TextLabel
	local label = make("TextLabel", {
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 2,
	}, parent)
	for key, value in properties do
		(label :: any)[key] = value
	end
	return label
end

-- A small cut-gem mark (a square turned on its corner) at the left of a game
-- card: filled for a game you can play, an outline for one still to come.
local function gemMark(card: Instance, colour: Color3, hollow: number)
	local mark = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(37, 40),
		Size = UDim2.fromOffset(28, 28),
		Rotation = 45,
		BackgroundColor3 = colour,
		BackgroundTransparency = hollow,
		ZIndex = 2,
	}, card)
	rounded(mark, 5)
	stroke(mark, if hollow > 0 then colour else Color3.new(1, 1, 1), 2, if hollow > 0 then 0.35 else 0.2)
	if hollow == 0 then
		make("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1), colour), Rotation = -45 }, mark)
	end
end

-- What the Diamond in the Rough card says about the round going on now, in
-- the mountain's skin ("stone" by default, or "hay": see Skin).
function LobbyView.status(phase: string, stone: number, skin: string?): string
	local words = Skin.words(skin)
	local gem = words.gem
	if phase == "Won" then return string.upper(string.sub(gem, 1, 1)) .. string.sub(gem, 2) .. " found! A new round starts soon" end
	if phase == "Rebuilding" then return "The " .. words.heap .. " is being rebuilt" end
	if phase == "Holding" then return "Someone is holding the " .. gem .. "!" end
	return "LIVE · " .. Format.commas(stone) .. " " .. words.material .. " left"
end

-- What the Diamond Climb card says about the climb.
function LobbyView.climbStatus(checkpoint: number, wins: number): string
	local text = "Platform " .. Format.commas(checkpoint) .. " of 1,000"
	if wins > 0 then text ..= " · " .. Format.commas(wins) .. (if wins == 1 then " climb" else " climbs") end
	return text
end

-- What the Chalkboard Count card says about the board.
function LobbyView.chalkStatus(count: number, goal: number, wins: number): string
	local text = "Count " .. Format.commas(count) .. " of " .. Format.commas(goal)
	if wins > 0 then text ..= " · " .. Format.commas(wins) .. (if wins == 1 then " win" else " wins") end
	return text
end

-- Where the player is: "chalk" (Chalkboard Count), "climb" (Diamond Climb),
-- "rough" (Diamond in the Rough) or "lobby", from their InChalk, InClimb and
-- InGame attributes.
function LobbyView.place(player: Player): string
	if player:GetAttribute("InChalk") == true then return "chalk" end
	if player:GetAttribute("InClimb") == true then return "climb" end
	return if player:GetAttribute("InGame") == true then "rough" else "lobby"
end

-- `request` sends joinGame (with the game's name) / leaveGame;
-- `onChange(place)` runs whenever the player moves between the lobby and the
-- games ("lobby", "rough", "climb" or "chalk"; once at the start too); `onHelp`
-- opens the How to Play guide.
function LobbyView.start(request: RemoteEvent, state: Instance, onChange: (string) -> (), onHelp: (() -> ())?)
	local player = Players.LocalPlayer
	local gui = make("ScreenGui", {
		Name = "GamesMenu",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))

	-- The tab that brings the menu back.
	local tab = make("TextButton", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(150, 48),
		BackgroundColor3 = IVORY,
		Font = Enum.Font.GothamBold,
		TextSize = 19,
		TextColor3 = ROYAL,
		Text = "GAMES",
		AutoButtonColor = true,
	}, gui)
	rounded(tab, 14)
	stroke(tab, GOLD, 2.5)

	local panel = make("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -WIDTH - 40, 0.5, 0),
		Size = UDim2.fromOffset(WIDTH, 620),
		BackgroundColor3 = IVORY,
		Visible = false,
	}, gui)
	rounded(panel, 18)
	stroke(panel, GOLD, 3)
	-- Shrinks to fit short screens (Studio's play area, phones).
	local fit = make("UIScale", { Scale = 1 }, panel)
	local function refit()
		local camera = workspace.CurrentCamera
		local height = if camera then camera.ViewportSize.Y else 768
		fit.Scale = math.clamp((height - 60) / 620, 0.5, 1)
	end
	refit()
	if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refit) end
	make("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(240, 235, 222)),
		Rotation = 90,
	}, panel)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
		PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 14),
	}, panel)

	text(panel, {
		Size = UDim2.new(1, -72, 0, 40),
		Font = TITLE_FONT,
		TextSize = 30,
		TextColor3 = ROYAL,
		Text = "Games",
	})
	text(panel, {
		Position = UDim2.fromOffset(2, 40),
		Size = UDim2.new(1, -72, 0, 20),
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextColor3 = MUTED,
		Text = "Pick a game to play · G hides this",
	})
	local hide = make("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 2),
		Size = UDim2.fromOffset(64, 30),
		BackgroundColor3 = ROYAL,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "Hide",
	}, panel)
	rounded(hide, 15)
	make("Frame", {
		Position = UDim2.fromOffset(0, 68),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = GOLD,
		BorderSizePixel = 0,
	}, panel)

	local list = make("Frame", {
		Position = UDim2.fromOffset(0, 80),
		Size = UDim2.new(1, 0, 1, -80),
		BackgroundTransparency = 1,
	}, panel)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }, list)

	-- Diamond in the Rough.
	local card = make("Frame", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 96),
		BackgroundTransparency = 1,
	}, list)
	rounded(card, 14)
	stroke(card, GOLD, 2)
	-- The royal blue fill is its own layer, so its gradient leaves the gold border alone.
	local fill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 1 }, card)
	rounded(fill, 14)
	make("UIGradient", { Color = ColorSequence.new(ROYAL, ROYAL_DEEP), Rotation = 35 }, fill)
	gemMark(card, Color3.fromRGB(176, 230, 255), 0)
	text(card, {
		Position = UDim2.fromOffset(72, 10),
		Size = UDim2.new(1, -80, 0, 26),
		Font = TITLE_FONT,
		TextSize = 20,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "Diamond in the Rough",
	})
	local live = text(card, {
		Position = UDim2.fromOffset(72, 38),
		Size = UDim2.new(1, -80, 0, 18),
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = Color3.fromRGB(205, 218, 255),
		Text = "",
	})
	local join = make("TextButton", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, -10),
		Size = UDim2.fromOffset(120, 30),
		BackgroundColor3 = GOLD,
		Font = Enum.Font.GothamBlack,
		TextSize = 16,
		TextColor3 = ROYAL_DEEP,
		Text = "JOIN",
		ZIndex = 2,
	}, card)
	rounded(join, 10)

	-- Diamond Climb.
	local climbCard = make("Frame", {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 96),
		BackgroundTransparency = 1,
	}, list)
	rounded(climbCard, 14)
	stroke(climbCard, GOLD, 2)
	local climbFill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 1 }, climbCard)
	rounded(climbFill, 14)
	make("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(92, 52, 160), Color3.fromRGB(40, 22, 96)), Rotation = 35 }, climbFill)
	gemMark(climbCard, Color3.fromRGB(255, 150, 220), 0)
	text(climbCard, {
		Position = UDim2.fromOffset(72, 10),
		Size = UDim2.new(1, -80, 0, 26),
		Font = TITLE_FONT,
		TextSize = 20,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "Diamond Climb",
	})
	local climbLive = text(climbCard, {
		Position = UDim2.fromOffset(72, 38),
		Size = UDim2.new(1, -80, 0, 18),
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = Color3.fromRGB(230, 210, 255),
		Text = "",
	})
	local climbJoin = make("TextButton", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, -10),
		Size = UDim2.fromOffset(120, 30),
		BackgroundColor3 = GOLD,
		Font = Enum.Font.GothamBlack,
		TextSize = 16,
		TextColor3 = ROYAL_DEEP,
		Text = "JOIN",
		ZIndex = 2,
	}, climbCard)
	rounded(climbJoin, 10)

	-- Chalkboard Count.
	local chalkCard = make("Frame", {
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 96),
		BackgroundTransparency = 1,
	}, list)
	rounded(chalkCard, 14)
	stroke(chalkCard, GOLD, 2)
	local chalkFill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 1 }, chalkCard)
	rounded(chalkFill, 14)
	make("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(46, 112, 74), Color3.fromRGB(20, 58, 38)), Rotation = 35 }, chalkFill)
	gemMark(chalkCard, Color3.fromRGB(240, 244, 230), 0)
	text(chalkCard, {
		Position = UDim2.fromOffset(72, 10),
		Size = UDim2.new(1, -80, 0, 26),
		Font = TITLE_FONT,
		TextSize = 20,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "Chalkboard Count",
	})
	local chalkLive = text(chalkCard, {
		Position = UDim2.fromOffset(72, 38),
		Size = UDim2.new(1, -80, 0, 18),
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = Color3.fromRGB(214, 240, 220),
		Text = "",
	})
	local chalkJoin = make("TextButton", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, -10),
		Size = UDim2.fromOffset(120, 30),
		BackgroundColor3 = GOLD,
		Font = Enum.Font.GothamBlack,
		TextSize = 16,
		TextColor3 = ROYAL_DEEP,
		Text = "JOIN",
		ZIndex = 2,
	}, chalkCard)
	rounded(chalkJoin, 10)

	-- More games to come.
	for index = 4, 4 do
		local soon = make("Frame", {
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 84),
			BackgroundColor3 = Color3.fromRGB(238, 235, 228),
		}, list)
		rounded(soon, 14)
		stroke(soon, GOLD, 1.5, 0.45)
		gemMark(soon, GOLD, 1)
		text(soon, {
			Position = UDim2.fromOffset(72, 18),
			Size = UDim2.new(1, -150, 0, 24),
			Font = TITLE_FONT,
			TextSize = 19,
			TextColor3 = MUTED,
			Text = "Coming soon",
		})
		text(soon, {
			Position = UDim2.fromOffset(72, 44),
			Size = UDim2.new(1, -150, 0, 18),
			Font = Enum.Font.GothamMedium,
			TextSize = 13,
			TextColor3 = Color3.fromRGB(165, 156, 140),
			Text = "A new game is on its way",
		})
		local badge = text(soon, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(64, 24),
			TextXAlignment = Enum.TextXAlignment.Center,
			BackgroundTransparency = 0,
			BackgroundColor3 = IVORY,
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextColor3 = GOLD,
			Text = "SOON",
		})
		rounded(badge, 12)
		stroke(badge, GOLD, 1.5)
	end

	local help = make("TextButton", {
		LayoutOrder = 9,
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = ROYAL,
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "How to play  H",
	}, list)
	rounded(help, 12)
	stroke(help, GOLD, 2)
	help.Activated:Connect(function()
		if onHelp then onHelp() end
	end)

	local back = make("TextButton", {
		LayoutOrder = 10,
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		TextColor3 = ROYAL,
		Text = "Back to lobby",
		Visible = false,
	}, list)
	rounded(back, 12)
	stroke(back, ROYAL, 2)

	-- Showing and hiding: the panel slides in from the left edge.
	local slide: Tween? = nil
	local function setOpen(show: boolean)
		if show == open then return end
		open = show
		if slide then slide:Cancel() end
		refreshTab()
		panel.Visible = true
		local target = if show then UDim2.new(0, 12, 0.5, 0) else UDim2.new(0, -WIDTH - 40, 0.5, 0)
		local tween = TweenService:Create(panel, TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = target })
		slide = tween
		tween.Completed:Connect(function(playback)
			if playback == Enum.PlaybackState.Completed and not open then panel.Visible = false end
		end)
		tween:Play()
	end
	closeHandler = function() setOpen(false) end
	refreshTab = function()
		tab.Visible = not open and not tabHidden
	end
	tab.Activated:Connect(function() setOpen(true) end)
	hide.Activated:Connect(function() setOpen(false) end)

	-- G toggles the menu, unless the streamer bound G to a test gift.
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or input.KeyCode ~= TOGGLE_KEY then return end
		local ok, bindings = pcall(function()
			return HttpService:JSONDecode(state:GetAttribute("GiftBindings") or "{}")
		end)
		if ok and type(bindings) == "table" and bindings[TOGGLE_KEY.Name] ~= nil then return end
		setOpen(not open)
	end)
	-- First person locks the mouse; free it while the menu is open.
	RunService.RenderStepped:Connect(function()
		if open then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end
	end)

	local function refreshLive()
		live.Text = LobbyView.status(tostring(state:GetAttribute("Phase") or "Digging"), tonumber(state:GetAttribute("Stone")) or 0, state:GetAttribute("Skin"))
	end
	state:GetAttributeChangedSignal("Phase"):Connect(refreshLive)
	state:GetAttributeChangedSignal("Stone"):Connect(refreshLive)
	state:GetAttributeChangedSignal("Skin"):Connect(refreshLive)
	refreshLive()
	local function refreshClimb()
		climbLive.Text = LobbyView.climbStatus(tonumber(state:GetAttribute("ClimbCheckpoint")) or 0, tonumber(state:GetAttribute("ClimbWins")) or 0)
	end
	state:GetAttributeChangedSignal("ClimbCheckpoint"):Connect(refreshClimb)
	state:GetAttributeChangedSignal("ClimbWins"):Connect(refreshClimb)
	refreshClimb()
	local function refreshChalk()
		chalkLive.Text = LobbyView.chalkStatus(tonumber(state:GetAttribute("ChalkCount")) or 0,
			tonumber(state:GetAttribute("ChalkGoal")) or 1000, tonumber(state:GetAttribute("ChalkWins")) or 0)
	end
	state:GetAttributeChangedSignal("ChalkCount"):Connect(refreshChalk)
	state:GetAttributeChangedSignal("ChalkGoal"):Connect(refreshChalk)
	state:GetAttributeChangedSignal("ChalkWins"):Connect(refreshChalk)
	refreshChalk()

	local place: string? = nil
	local function playing(button: TextButton, on: boolean)
		button.Text = if on then "PLAYING" else "JOIN"
		button.BackgroundColor3 = if on then Color3.new(1, 1, 1) else GOLD
		button.AutoButtonColor = not on
	end
	local refreshQueued = false
	local function refreshPlace()
		refreshQueued = false
		local now = LobbyView.place(player)
		if now == place then return end
		place = now
		playing(join, now == "rough")
		playing(climbJoin, now == "climb")
		playing(chalkJoin, now == "chalk")
		back.Visible = now ~= "lobby"
		-- Arriving in the lobby opens the menu; joining a game tucks it away.
		setOpen(now == "lobby")
		onChange(now)
	end
	-- Moving between games changes two attributes; look once both have arrived.
	local function queueRefresh()
		if refreshQueued then return end
		refreshQueued = true
		task.defer(refreshPlace)
	end
	player:GetAttributeChangedSignal("InGame"):Connect(queueRefresh)
	player:GetAttributeChangedSignal("InClimb"):Connect(queueRefresh)
	player:GetAttributeChangedSignal("InChalk"):Connect(queueRefresh)
	refreshPlace()

	join.Activated:Connect(function()
		if place == "rough" then
			setOpen(false)
		else
			request:FireServer("joinGame", "DiamondInTheRough")
		end
	end)
	climbJoin.Activated:Connect(function()
		if place == "climb" then
			setOpen(false)
		else
			request:FireServer("joinGame", "DiamondClimb")
		end
	end)
	chalkJoin.Activated:Connect(function()
		if place == "chalk" then
			setOpen(false)
		else
			request:FireServer("joinGame", "Chalkboard")
		end
	end)
	back.Activated:Connect(function()
		request:FireServer("leaveGame")
	end)

	-- The lobby's giant diamond turns slowly and bobs (only when near).
	task.spawn(function()
		local lobby = workspace:WaitForChild("Lobby", math.huge)
		local gem = lobby:WaitForChild("LobbyDiamond", math.huge)
		local centre = gem:GetAttribute("Centre")
		if typeof(centre) ~= "Vector3" then return end
		local origin = CFrame.new(centre)
		local parts: { BasePart } = {}
		local offsets: { CFrame } = {}
		for _, item in gem:GetDescendants() do
			if item:IsA("BasePart") then
				table.insert(parts, item)
				table.insert(offsets, origin:ToObjectSpace(item.CFrame))
			end
		end
		local frames: { CFrame } = table.create(#parts, CFrame.identity)
		RunService.RenderStepped:Connect(function()
			local camera = workspace.CurrentCamera
			if camera == nil or (camera.CFrame.Position - centre).Magnitude > 400 then return end
			local t = os.clock()
			local turn = CFrame.new(centre + Vector3.new(0, math.sin(t * 1.3) * 0.5, 0)) * CFrame.Angles(0, t * 0.6, 0)
			for i, offset in offsets do
				frames[i] = turn * offset
			end
			workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		end)
	end)
end

return LobbyView
