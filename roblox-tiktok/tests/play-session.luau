-- A play session (tests/play.py): everything a streamer would do, with checks.
local failures = {}
local function check(condition, message)
	if not condition then table.insert(failures, message) end
end
local function section(label)
	print(string.format("== %s: %d errors, t=%.1f", label, #World.errors, World.now()))
	for i, e in World.errors do print("  [" .. i .. "] " .. e) end
	table.clear(World.errors)
	for _, f in failures do print("  FAIL " .. f) end
	table.clear(failures)
end
local function run(seconds) World.run(seconds) end

World.start(server)
run(1)
local player = World.addPlayer("Streamer", 1001)
if World.services.Players.CharacterAutoLoads ~= false and player.Character == nil then World.spawnCharacter(player) end
World.start(loading)
World.run(0.5)
local loadingGui = player.PlayerGui:FindFirstChild("DiamondRushLoading")
World.start(hud)
check(loadingGui ~= nil and loadingGui.Enabled, "the loading screen covers the screen as the player joins")
check(World.defaultLoadingRemoved == true, "in place of Roblox's own")
run(40)
check(player:GetAttribute("DiamondRushHudReady") == true, "the game's display says it's ready")
check(player.PlayerGui:FindFirstChild("DiamondRushLoading") == nil, "and the loading screen has gone")
-- A list layout places its children itself: a child given its own position
-- there is ignored by Roblox (the sidebar's arrow once sat in the list, so
-- hiding the sidebar hid the arrow too).
local function layoutMisplaced()
	local out = {}
	for _, layout in World.findAll(player.PlayerGui, function(o) return o.ClassName == "UIListLayout" or o.ClassName == "UIGridLayout" end) do
		for _, child in layout.Parent:GetChildren() do
			local p = child.Position
			if child:IsA("GuiObject") and p and (p.X.Scale ~= 0 or p.X.Offset ~= 0 or p.Y.Scale ~= 0 or p.Y.Offset ~= 0) then
				table.insert(out, child:GetFullName())
			end
		end
	end
	return out
end
local misplaced = layoutMisplaced()
check(#misplaced == 0, "nothing given its own position inside a list layout: " .. table.concat(misplaced, ", "))
section("boot")

local RS = World.services.ReplicatedStorage
local State = RS:WaitForChild("DiamondRushState")
local Remotes = RS:WaitForChild("DiamondRushRemotes")
local Request = Remotes.Request
local notices = {}
Remotes.Notify.OnClientEvent:Connect(function(kind, value)
	if kind == "notice" then table.insert(notices, value) end
end)
local gui = player.PlayerGui
local function findText(text, className)
	return World.find(gui, function(o) return (className == nil or o.ClassName == className) and o.Text == text end)
end
local function sidebarButton(label)
	local l = World.find(gui, function(o) return o.ClassName == "TextLabel" and o.Text == label and o.Parent and o.Parent.ClassName == "TextButton" end)
	return l and l.Parent
end
local function click(button, label)
	check(button ~= nil, "no button: " .. tostring(label))
	if button then button.Activated:Fire() end
	run(0.3)
end
local function place()
	if player:GetAttribute("InChalk") then return "chalk" end
	if player:GetAttribute("InClimb") then return "climb" end
	return if player:GetAttribute("InGame") then "rough" else "lobby"
end
local function root() return player.Character and player.Character:FindFirstChild("HumanoidRootPart") end
local function humanoid() return player.Character and player.Character:FindFirstChildOfClass("Humanoid") end

-- The lobby ------------------------------------------------------------------------------
local lobby = World.workspace:FindFirstChild("Lobby")
check(lobby ~= nil, "the lobby is built")
check(place() == "lobby", "the player starts in the lobby")
local spawnPart = lobby and lobby:FindFirstChild("LobbySpawn")
check(root() and spawnPart and (root().Position - spawnPart.Position).Magnitude < 12, "the character stands at the lobby spawn")
check(player:GetAttribute("DiamondRushAdmin") == true, "the single player is the streamer")
local sidebarGui = gui:FindFirstChild("Sidebar")
check(sidebarGui ~= nil and sidebarGui.Enabled, "the sidebar is on screen in the lobby")
for _, label in { "GIFTS", "THEMES", "SETTINGS", "GAMES" } do
	local b = sidebarButton(label)
	check(b ~= nil and b.Visible, label .. " shows on the sidebar")
end
local gamesMenu = gui:FindFirstChild("GamesMenu")
local LobbyView = World.require(hud.LobbyView)
local Sidebar = World.require(hud.Sidebar)
local GiftMenu = World.require(hud.GiftMenu)
local HowToPlay = World.require(hud.HowToPlay)
local Config = World.require(RS.DiamondRush.Config)
check(LobbyView.isOpen(), "arriving in the lobby opens the games menu")
check(player:GetAttribute("OwnedThemes") == "", "nothing owned yet")
section("lobby")

-- Sidebar: THEMES, SETTINGS, GAMES, GIFTS -------------------------------------------------
click(sidebarButton("THEMES"), "THEMES")
check(Sidebar.themesOpen(), "THEMES opens the themes card")
check(not LobbyView.isOpen(), "and closes the games menu")
local function themeButton(name)
	local l = World.find(sidebarGui, function(o) return o.ClassName == "TextLabel" and o.Text == name end)
	if l == nil then return nil end
	return l.Parent:FindFirstChildOfClass("TextButton")
end
check(themeButton("Alpine") and themeButton("Alpine").Text == "IN USE", "Alpine is in use")
check(themeButton("Farm") and themeButton("Farm").Text == "USE", "Farm is free while it has no pass")
click(themeButton("Farm"), "Farm")
run(3)
check(State:GetAttribute("Theme") == "farm", "USE puts Farm on the map")
check(themeButton("Farm").Text == "IN USE", "and the card says so")
click(themeButton("Haunted"), "Haunted")
run(3)
check(State:GetAttribute("Theme") == "haunted", "Haunted too")
click(themeButton("Alpine"), "Alpine")
run(3)
check(State:GetAttribute("Theme") == "default", "and back to Alpine")
section("themes (free)")

-- Selling a theme: give Sakura a pass, then buy it.
Config.ThemePasses.sakura = 111
Config.ThemePasses.desert = 333
-- (The card looks again when what's owned changes.)
player:SetAttribute("OwnedThemes", "nothing")
player:SetAttribute("OwnedThemes", "")
run(0.5)
click(themeButton("Desert"), "Desert")
run(1)
check(State:GetAttribute("Theme") == "default", "an unbought paid theme isn't used")
check(#World.purchases >= 1 and World.purchases[#World.purchases].pass == 333, "pressing a price opens Roblox's purchase of that pass")
-- The client asking to use it anyway is refused by the server.
table.clear(notices)
Request:FireServer("setTheme", "desert")
run(1)
check(State:GetAttribute("Theme") == "default", "the server refuses a theme that wasn't bought")
check(#notices > 0 and string.find(notices[#notices], "Buy the Desert theme", 1, true) ~= nil, "and says to buy it")
-- The purchase goes through.
World.ownedPasses[333] = true
World.services.MarketplaceService.PromptGamePassPurchaseFinished:Fire(player, 333, true)
run(3)
check(State:GetAttribute("Theme") == "desert", "a bought theme goes on the map")
check(string.find(player:GetAttribute("OwnedThemes") or "", "desert", 1, true) ~= nil, "and is owned")
check(themeButton("Desert").Text == "IN USE", "the card shows it in use")
check(themeButton("Sakura").Text ~= "USE", "Sakura still needs buying: " .. tostring(themeButton("Sakura").Text))
click(themeButton("Alpine"), "Alpine")
run(2)
click(themeButton("Desert"), "Desert again")
run(2)
check(State:GetAttribute("Theme") == "desert", "a bought theme can be used again")
Request:FireServer("setTheme", "default")
run(2)
section("themes (bought)")

click(sidebarButton("SETTINGS"), "SETTINGS")
local settingsGui = gui:FindFirstChild("DiamondRushSettings")
local settingsCard = settingsGui and settingsGui:FindFirstChildOfClass("Frame")
check(settingsCard and settingsCard.Visible, "SETTINGS opens the settings card in the lobby")
check(not Sidebar.themesOpen(), "and closes the themes card")
local function switchFor(title)
	local l = settingsCard and World.find(settingsCard, function(o) return o.ClassName == "TextLabel" and o.Text == title end)
	if not l then return nil end
	local best, distance = nil, math.huge
	for _, b in settingsCard:GetChildren() do
		if b.ClassName == "TextButton" and b.Position.Y.Offset and math.abs(b.Position.Y.Offset - l.Position.Y.Offset) < distance then
			best, distance = b, math.abs(b.Position.Y.Offset - l.Position.Y.Offset)
		end
	end
	return best
end
click(switchFor("Hide speed and jump"), "hide speed and jump")
run(1)
check(player:GetAttribute("HideClimbCard") == true, "hide speed and jump")
click(switchFor("Hide writing speed"), "hide writing speed")
run(1)
check(player:GetAttribute("HideChalkCard") == true, "hide writing speed")
click(switchFor("Hide the win counter"), "hide win counter")
run(1)
check(State:GetAttribute("ShowWins") == false, "hide the win counter")
click(switchFor("Hide the win counter"), "show win counter")
run(1)
check(State:GetAttribute("ShowWins") == true, "show the win counter again")
click(switchFor("Hide the sidebar"), "hide sidebar")
run(1)
check(sidebarGui.Enabled == false, "hide the sidebar")
click(switchFor("Hide the sidebar"), "show sidebar")
run(1)
check(sidebarGui.Enabled == true, "show the sidebar again")
click(switchFor("Hide speed and jump"), "unhide")
click(switchFor("Hide writing speed"), "unhide")
run(1)
click(findText("Done", "TextButton"), "Done")
check(not settingsCard.Visible, "Done closes the settings")
section("settings")

click(sidebarButton("GAMES"), "GAMES")
check(LobbyView.isOpen(), "GAMES opens the games menu")
click(sidebarButton("GAMES"), "GAMES again")
check(not LobbyView.isOpen(), "and again closes it")
click(sidebarButton("GIFTS"), "GIFTS")
check(GiftMenu.isOpen(), "GIFTS opens the gift settings, in the lobby too")
local giftGui = gui:FindFirstChild("GiftSettings")
check(giftGui and giftGui.Enabled, "the gift settings show")
click(giftGui and World.find(giftGui, function(o) return o.ClassName == "TextButton" and o.Text == "Close" end), "Close")
check(not GiftMenu.isOpen(), "Close closes them")
-- The arrow.
local arrow = World.find(sidebarGui, function(o) return o.ClassName == "TextButton" and o.Text == "‹" end)
click(arrow, "arrow")
run(1)
check(arrow and arrow.Text == "›", "the arrow tucks the sidebar away")
click(arrow, "arrow back")
run(1)
check(arrow and arrow.Text == "‹", "and brings it back")
section("sidebar")

-- Keys in the lobby.
World.press("P")
run(0.3)
check(settingsCard.Visible, "P opens the settings in the lobby")
World.press("P")
run(0.3)
check(not settingsCard.Visible, "P closes them")
World.press("G")
run(0.3)
check(LobbyView.isOpen(), "G opens the games menu")
World.press("G")
run(0.3)
World.press("H")
run(0.3)
check(HowToPlay.isOpen(), "H opens the guide")
World.press("H")
run(0.3)
-- The How to Play board's prompt.
local prompt = World.find(lobby, function(o) return o.ClassName == "ProximityPrompt" and o.Name == "HowToPlay" end)
World.services.ProximityPromptService.PromptTriggered:Fire(prompt, player)
run(0.3)
check(HowToPlay.isOpen(), "the board opens the guide")
HowToPlay.setOpen(false)
section("lobby keys")

-- Sprint in the lobby.
World.input("LeftShift", true)
run(0.2)
check(humanoid() and math.abs(humanoid().WalkSpeed - 24) < 1e-6, "Shift sprints in the lobby: " .. tostring(humanoid() and humanoid().WalkSpeed))
World.input("LeftShift", false)
run(0.2)
check(humanoid() and humanoid().WalkSpeed == 16, "letting go walks")
section("sprint")

-- Portals ---------------------------------------------------------------------------------
local portals = World.findAll(lobby, function(o) return o.Name == "Portal" end)
check(#portals == 3, "three portals")
for _, portal in portals do
	local game = portal:GetAttribute("Game")
	run(1.5) -- moving is limited to once a second
	portal.Touched:Fire(player.Character:FindFirstChild("LeftFoot"))
	run(1)
	check(place() == game, "walking into the " .. tostring(game) .. " portal joins it (now " .. place() .. ")")
	check(gui.DiamondRushHud.Enabled == true, "the game's display shows in " .. tostring(game))
	check(not LobbyView.isOpen(), "the games menu tucks away in " .. tostring(game))
	-- The sidebar works in every game.
	click(sidebarButton("SETTINGS"), "SETTINGS in " .. tostring(game))
	check(settingsCard.Visible, "settings open in " .. tostring(game))
	World.press("P")
	run(0.3)
	run(1.5)
	Request:FireServer("leaveGame")
	run(1)
	check(place() == "lobby", "back to the lobby from " .. tostring(game))
	check(gui.DiamondRushHud.Enabled == false, "the game's display hides in the lobby")
end
-- The prompt way.
run(1.5)
local chalkPortal = nil
for _, p in portals do if p:GetAttribute("Game") == "chalk" then chalkPortal = p end end
local joinPrompt = chalkPortal:FindFirstChildOfClass("ProximityPrompt")
joinPrompt.Triggered:Fire(player)
run(1)
check(place() == "chalk", "pressing E at a portal joins")
run(1.5)
Request:FireServer("leaveGame")
run(1)
section("portals")

-- Diamond in the Rough ----------------------------------------------------------------------
run(1.5)
Request:FireServer("joinGame", "DiamondInTheRough")
run(2)
check(place() == "rough", "JOIN Diamond in the Rough")
local stone0 = State:GetAttribute("Stone")
check(type(stone0) == "number" and stone0 > 0, "the mountain has stone: " .. tostring(stone0))
for _, gift in { { "Rose", 1, 1 }, { "Galaxy", 1000, 1 }, { "Doughnut", 30, 10 }, { "Lion", 29999, 1 } } do
	Request:FireServer("testGift", { coins = gift[2], count = gift[3], name = gift[1] })
end
run(40)
check(State:GetAttribute("Stone") < stone0, "gifts blast the mountain: " .. tostring(State:GetAttribute("Stone")))
Request:FireServer("testRebuildGift", 10000)
run(15)
World.press("Y")
run(0.3)
local panel = World.find(gui.DiamondRushHud, function(o) return o.ClassName == "ScrollingFrame" end)
check(panel and panel.Visible, "Y opens the streamer panel")
local wins0 = State:GetAttribute("Wins")
click(findText("+1", "TextButton"), "+1")
run(1)
check(State:GetAttribute("Wins") == wins0 + 1, "+1 adds a win in the mine")
click(findText("-1", "TextButton"), "-1")
click(findText("-1", "TextButton"), "-1")
run(1)
check(State:GetAttribute("Wins") == wins0 - 1, "wins can go below 0: " .. tostring(State:GetAttribute("Wins")))
click(findText("Reset to 0", "TextButton"), "Reset")
run(1)
World.press("Y")
run(0.3)
World.input("LeftShift", true)
run(0.2)
check(humanoid().WalkSpeed == 24, "sprint in the mine")
World.input("LeftShift", false)
run(0.2)
Request:FireServer("spawnBird")
run(5)
Request:FireServer("catchBird")
run(1)
Request:FireServer("newRound")
run(20)
check(State:GetAttribute("Phase") == "Digging", "a new round digs again: " .. tostring(State:GetAttribute("Phase")))
section("diamond in the rough")

-- Gift settings: wins, a reset gift, a key.
Request:FireServer("setGiftSettings", { gift = "Rose", coins = 1, wins = 2, key = "K" })
Request:FireServer("setGiftSettings", { gift = "Galaxy", coins = 1000, reset = true })
run(1)
run(35) -- past the diamond bird's double gifts
local wins1 = State:GetAttribute("Wins")
World.press("K")
run(5)
check(State:GetAttribute("Wins") == wins1 + 2, "a gift's key sends it, and its wins count: " .. tostring(State:GetAttribute("Wins")) .. " from " .. tostring(wins1))
Request:FireServer("testGift", { coins = 1000, count = 1, name = "Galaxy" })
run(25)
check(State:GetAttribute("Stone") == State:GetAttribute("StartingStone"), "a reset gift brings back a full mountain")
section("gift settings in the mine")

-- Diamond Climb -------------------------------------------------------------------------------
run(1.5)
Request:FireServer("joinGame", "DiamondClimb")
run(2)
check(place() == "climb", "JOIN Diamond Climb")
for _, gift in { { "Rose", 1 }, { "Galaxy", 1000 }, { "Lion", 29999 }, { "Perfume", 20 } } do
	Request:FireServer("testGift", { coins = gift[2], count = 1, name = gift[1] })
	run(6)
end
run(20)
check(State:GetAttribute("ClimbCheckpoint") ~= nil, "the climb moves")
local climbWins = State:GetAttribute("ClimbWins")
World.press("Y")
run(0.3)
click(findText("+1", "TextButton"), "+1 climb")
run(1)
check(State:GetAttribute("ClimbWins") == climbWins + 1, "+1 adds a climb win while climbing")
World.press("Y")
run(0.3)
World.input("LeftShift", true)
run(0.2)
local speed = humanoid().WalkSpeed
World.input("LeftShift", false)
run(0.2)
check(math.abs(speed - humanoid().WalkSpeed * 1.5) < 1e-6, "sprint in the climb is 1.5x its speed: " .. speed .. " vs " .. humanoid().WalkSpeed)
Request:FireServer("setClimbWall", 50)
run(1)
for _ = 1, 3 do Request:FireServer("testRebuildGift", 100000); run(8) end
Request:FireServer("testGift", { coins = 1000, count = 1, name = "Galaxy" }) -- the reset gift
run(5)
check(State:GetAttribute("ClimbCheckpoint") == 0, "the reset gift sends the climber to platform 0")
-- Respawning on the climb.
humanoid().Health = 0
player:LoadCharacter()
run(2)
check(place() == "climb", "still climbing after a respawn")
section("diamond climb")

-- Chalkboard Count ------------------------------------------------------------------------------
run(1.5)
Request:FireServer("joinGame", "Chalkboard")
run(2)
check(place() == "chalk", "JOIN Chalkboard Count")
Request:FireServer("chalkHold", true)
run(5)
check((State:GetAttribute("ChalkCount") or 0) > 0, "holding writes numbers: " .. tostring(State:GetAttribute("ChalkCount")))
Request:FireServer("chalkHold", false)
for _, gift in { { "Rose", 1 }, { "Lion", 29999 }, { "Ice Cream Cone", 1 } } do
	Request:FireServer("testGift", { coins = gift[2], count = 1, name = gift[1] })
	run(5)
end
Request:FireServer("chalkTestReset")
run(3)
Request:FireServer("chalkTestSave")
run(5)
Request:FireServer("testGift", { coins = 1000, count = 1, name = "Galaxy" }) -- the reset gift (gift settings) beats the countdown gift
run(5)
check(State:GetAttribute("ChalkCount") == 0, "the reset gift wipes the board: " .. tostring(State:GetAttribute("ChalkCount")))
World.input("LeftShift", true)
run(0.2)
check(humanoid().WalkSpeed == 0, "the writer stays still even sprinting: " .. tostring(humanoid().WalkSpeed))
World.input("LeftShift", false)
run(0.2)
run(1.5)
Request:FireServer("leaveGame")
run(2)
check(place() == "lobby", "back to the lobby")
check(humanoid().WalkSpeed == 16, "normal speed back in the lobby: " .. tostring(humanoid().WalkSpeed))
section("chalkboard")

-- The diamond: clear the mountain, find it, hold it, win --------------------------------------
Request:FireServer("setGiftSettings", { gift = "Galaxy", coins = 1000, reset = false })
run(1.5)
click(sidebarButton("GAMES"), "GAMES")
local joinButtons = World.findAll(gui.GamesMenu, function(o) return o.ClassName == "TextButton" and o.Text == "JOIN" end)
check(#joinButtons == 3, "three JOIN buttons in the games menu: " .. #joinButtons)
click(joinButtons[1], "JOIN Diamond in the Rough")
run(2)
check(place() == "rough", "the games menu's JOIN joins")
local winsBefore = State:GetAttribute("Wins")
for _ = 1, 4 do Request:FireServer("testGift", { coins = 34999, count = 1, name = "TikTok Universe" }); run(20) end
run(20)
check(State:GetAttribute("Phase") == "Revealed", "clearing the mountain reveals the diamond: " .. tostring(State:GetAttribute("Phase")))
local diamond = World.workspace:FindFirstChild("Diamond")
player.Character:PivotTo(World.CF(diamond.Position + World.V3(0, 1, 3)))
run(0.5)
local detector = diamond:FindFirstChildOfClass("ClickDetector")
detector.MouseClick:Fire(player)
run(1)
check(State:GetAttribute("Phase") == "Holding", "clicking the diamond picks it up: " .. tostring(State:GetAttribute("Phase")))
table.clear(notices)
Request:FireServer("leaveGame")
run(1)
check(place() == "rough" and #notices > 0, "you can't leave while holding it")
run(17)
check(State:GetAttribute("Phase") == "Won", "holding it 15 seconds wins: " .. tostring(State:GetAttribute("Phase")))
check(State:GetAttribute("Wins") == winsBefore + 1, "a win is counted")
run(20)
check(State:GetAttribute("Phase") == "Digging", "a new round starts after the win")
section("finding the diamond")

-- Skins, statues and leaderboards.
Request:FireServer("setSkin", "hay")
run(2)
check(State:GetAttribute("Skin") == "hay", "the haystack skin")
Request:FireServer("setSkin", "stone")
run(2)
-- At the camp, facing the mountain, is too close; turned round, it's fine.
local camp = World.workspace.Camp
player.Character:PivotTo(camp.CFrame + World.V3(0, 4, 0))
run(0.5)
table.clear(notices)
Request:FireServer("placeStatue", { name = "Big Gifter", coins = 5000 })
run(2)
check(#World.workspace.Statues:GetChildren() == 0 and #notices > 0 and string.find(notices[1], "turn away", 1, true) ~= nil, "facing the mountain from the camp says to turn away")
player.Character:PivotTo(World.lookAt(camp.Position + World.V3(0, 4, 0), camp.Position + World.V3(0, 4, 0) - camp.CFrame.LookVector))
run(0.5)
Request:FireServer("placeStatue", { name = "Big Gifter", coins = 5000 })
run(2)
check(#World.workspace.Statues:GetChildren() > 0, "turned away from the mountain, a gold statue is placed")
Request:FireServer("removeNearestStatue")
run(2)
check(#World.workspace.Statues:GetChildren() == 0, "and removed")
Request:FireServer("previewBoards")
run(3)
section("skins, statues, boards")

-- Saving --------------------------------------------------------------------------------------
run(20)
check((World.saveCount or 0) > 0, "settings were saved")
print("saves written: " .. tostring(World.saveCount))
World.onClose()
for name, store in World.saves do
	for key, value in store do print("SAVE " .. name .. " " .. key .. " " .. World.json.encode(value)) end
end
section("saving")

for _, line in World.log do if string.find(line, "WARN") then print(line) end end
print("notices: " .. table.concat(notices, " | "))
