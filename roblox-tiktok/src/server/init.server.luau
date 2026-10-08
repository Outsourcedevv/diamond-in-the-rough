--!strict
-- DIAMOND RUSH: a TikTok Live mountain. Gifts, likes, follows and shares blast
-- stone out of the mountain; whoever grabs the hidden diamond and holds it for
-- 15 seconds wins the round.
local Players = game:GetService("Players")
-- Characters wait until the lobby is built (onPlayer loads them), so nobody
-- spawns into an empty sky and falls while the save loads.
Players.CharacterAutoLoads = false
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPack = game:GetService("StarterPack")
local TextService = game:GetService("TextService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("DiamondRush")
local Config = require(Shared:WaitForChild("Config"))
local ClimbPath = require(Shared:WaitForChild("ClimbPath"))
local ChalkBoard = require(Shared:WaitForChild("ChalkBoard"))
local Format = require(Shared:WaitForChild("Format"))
local Skin = require(Shared:WaitForChild("Skin"))
local GiftTier = require(Shared:WaitForChild("GiftTier"))
local Mountain = require(script.Mountain)
local GiftSettings = require(script.GiftSettings)
local Store = require(script.Store)
local ClimbGame = require(script.ClimbGame)
local ChalkGame = require(script.ChalkGame)

-- Shared state lives in attributes, so every client sees it without extra code.
local State = Instance.new("Configuration")
State.Name = "DiamondRushState"
State.Parent = ReplicatedStorage

local Remotes = Instance.new("Folder")
Remotes.Name = "DiamondRushRemotes"
local Notify = Instance.new("RemoteEvent")
Notify.Name = "Notify"
Notify.Parent = Remotes
local Request = Instance.new("RemoteEvent")
Request.Name = "Request"
Request.Parent = Remotes
-- Mountain snapshots and change lists travel in order on one remote; every
-- client draws its own rock from them (see Mountain and MountainView).
local MountainSync = Instance.new("RemoteEvent")
MountainSync.Name = "MountainSync"
MountainSync.Parent = Remotes
Remotes.Parent = ReplicatedStorage

-- A gift (or a like, follow or share) to play: from a key TikFinity presses,
-- the Y panel's test gifts or the gift settings' Test button.
type GiftEvent = {
	id: string,
	type: string, -- "gift" | "like" | "follow" | "share"
	user: string?,
	name: string?,
	gift: string?,
	coins: number?, -- coins per gift
	count: number?, -- gifts in this event
	part: number?, -- set when a combo plays as separate gifts: which one this is
	parts: number?, -- and how many there are
	likes: number?,
	rocks: number?, -- set only by the rebuild tests
}

-- Saved settings --------------------------------------------------------------
local settings = {
	wins = 0,
	title = Config.WinTitle,
	goal = Config.WinGoal,
	textColor = Config.WinTextColor,
	backgroundColor = Config.WinBackgroundColor,
	showWins = true,
	best = 0,
	startingStone = Config.StartingStone,
	perCoin = Config.StonePerCoin,
	perLike = Config.StonePerLike,
	perFollow = Config.StonePerFollow,
	perShare = Config.StonePerShare,
	giftRules = table.clone(Config.GiftRules) :: { [string]: number },
	-- Diamond Climb's and Chalkboard Count's own gift rules: platforms (or
	-- numbers) per gift, negative to send them down (set in the gift settings).
	climbRules = table.clone(Config.ClimbGiftRules) :: { [string]: number },
	chalkRules = table.clone(Config.ChalkGiftRules) :: { [string]: number },
	-- Wins per gift (from the gift settings): added to, or taken from, the win
	-- counter of whichever game is being played.
	winRules = {} :: { [string]: number },
	-- Reset gifts (gift settings): send the game being played back to the start.
	resetGifts = {} :: { [string]: boolean },
	-- The show each gift plays (1 smallest to 6 biggest), chosen in the gift settings.
	animRules = {} :: { [string]: number },
	giftBindings = {} :: { [string]: any },
	-- Gifts the streamer added in the gift settings (name -> coins), for gifts
	-- missing from the built-in list (see GiftCatalogue).
	customGifts = {} :: { [string]: number },
	-- Players who hid the GAMES tab and SETTINGS button (by user id).
	hiddenButtons = {} :: { [string]: boolean },
	-- Players who hid Diamond Climb's movement card or Chalkboard Count's
	-- writing card (in Settings), by user id.
	hiddenClimbCard = {} :: { [string]: boolean },
	hiddenChalkCard = {} :: { [string]: boolean },
	-- Leaderboard totals per TikTok viewer, and gold statues placed by the streamer.
	-- Helpers gave coins to break the mountain, griefers to add stone to it.
	leaderboards = { helpers = {}, griefers = {} } :: { helpers: { any }, griefers: { any } },
	statues = {} :: { any },
	theme = "default", -- the map's look: "default" (alpine), "sakura", "farm", "desert" or "haunted"
	skin = "stone", -- the mountain: "stone" with a diamond, or "hay" with a needle
	-- Diamond Climb's progress, chosen speed and jump, and gift strength (see ClimbGame).
	climb = ClimbGame.defaults() :: any,
	-- Chalkboard Count's count, goal, wins, writing speed, theme and reset gift (see ChalkGame).
	chalk = ChalkGame.defaults() :: any,
}
-- Single player: every player has their own save (statues, wins, theme,
-- keybinds and the rest), so the server waits for its player and loads theirs.
-- A first visit starts from the game's old shared save.
if Config.SinglePlayer then
	local waitUntil = os.clock() + 30
	while #Players:GetPlayers() == 0 and os.clock() < waitUntil do
		task.wait(0.1)
	end
	local owner = Players:GetPlayers()[1]
	if owner then Store.useKey("player_" .. tostring(owner.UserId)) end
end
local saved, readable = Store.load()
if saved == nil and readable and Config.SinglePlayer then
	saved = Store.load(Store.SHARED_KEY)
end
if saved then
	for key, value in saved do
		if settings[key] ~= nil and type(value) == type(settings[key]) then
			settings[key] = value
		end
	end
	local function cleanRules(saved: { [any]: any }, limit: number): { [string]: number }
		local rules: { [string]: number } = {}
		for name, value in saved do
			if type(name) == "string" and type(value) == "number" and value == value then
				rules[string.lower(name)] = math.clamp(math.floor(value), -limit, limit)
			end
		end
		return rules
	end
	settings.giftRules = cleanRules(settings.giftRules, 1500000)
	settings.climbRules = cleanRules(settings.climbRules, ClimbPath.TOP)
	settings.chalkRules = cleanRules(settings.chalkRules, ChalkBoard.GOAL.max)
	settings.winRules = cleanRules(settings.winRules, 1000)
	local resets: { [string]: boolean } = {}
	for name, on in settings.resetGifts do
		if type(name) == "string" and on == true then resets[string.lower(name)] = true end
	end
	settings.resetGifts = resets
	local anims: { [string]: number } = {}
	for name, tier in settings.animRules do
		if type(name) == "string" and type(tier) == "number" and tier == math.floor(tier) and tier >= 1 and tier <= 6 then anims[string.lower(name)] = tier end
	end
	settings.animRules = anims
	settings.customGifts = GiftSettings.cleanCustom(settings.customGifts)
	settings.giftBindings = GiftSettings.cleanBindings(settings.giftBindings)
	-- Older saves kept gifters and likers; those totals cannot be split by side.
	if type(settings.leaderboards.helpers) ~= "table" or type(settings.leaderboards.griefers) ~= "table" then
		settings.leaderboards = { helpers = {}, griefers = {} }
	end
	local statues = {}
	for _, statue in settings.statues do
		if type(statue) == "table" and type(statue.n) == "string" and type(statue.c) == "number"
			and type(statue.x) == "number" and type(statue.y) == "number" and type(statue.z) == "number" and type(statue.r) == "number" then
			table.insert(statues, statue)
		end
	end
	settings.statues = statues
end

local function publishSettings()
	State:SetAttribute("Wins", settings.wins)
	State:SetAttribute("WinTitle", settings.title)
	State:SetAttribute("WinGoal", settings.goal)
	State:SetAttribute("WinTextColor", settings.textColor)
	State:SetAttribute("WinBackgroundColor", settings.backgroundColor)
	State:SetAttribute("ShowWins", settings.showWins)
	State:SetAttribute("BestTime", settings.best)
	State:SetAttribute("NextStartingStone", settings.startingStone)
	State:SetAttribute("PerCoin", settings.perCoin)
	State:SetAttribute("PerLike", settings.perLike)
	State:SetAttribute("PerFollow", settings.perFollow)
	State:SetAttribute("PerShare", settings.perShare)
	State:SetAttribute("GiftRules", game:GetService("HttpService"):JSONEncode(settings.giftRules))
	State:SetAttribute("ClimbRules", game:GetService("HttpService"):JSONEncode(settings.climbRules))
	State:SetAttribute("ChalkRules", game:GetService("HttpService"):JSONEncode(settings.chalkRules))
	State:SetAttribute("WinRules", game:GetService("HttpService"):JSONEncode(settings.winRules))
	State:SetAttribute("ResetGifts", game:GetService("HttpService"):JSONEncode(settings.resetGifts))
	State:SetAttribute("AnimRules", game:GetService("HttpService"):JSONEncode(settings.animRules))
	State:SetAttribute("GiftBindings", game:GetService("HttpService"):JSONEncode(settings.giftBindings))
	State:SetAttribute("CustomGifts", game:GetService("HttpService"):JSONEncode(settings.customGifts))
	local statueList = {}
	for _, statue in settings.statues do table.insert(statueList, { name = statue.n, coins = statue.c }) end
	State:SetAttribute("Statues", game:GetService("HttpService"):JSONEncode(statueList))
	State:SetAttribute("Theme", settings.theme)
	State:SetAttribute("Skin", settings.skin)
end

local function saveSettings()
	publishSettings()
	Store.save(settings)
end

game:BindToClose(function()
	Store.flush(settings)
end)

-- The world ---------------------------------------------------------------------
local blockSize = Config.BlockSize
-- A cone of about this many rocks reaches out roughly this far.
local spawnDistance = math.ceil((math.min(Config.StartingStone, 1500000) * 1.06 / 0.94) ^ (1 / 3)) * blockSize + 30


local spawn = Instance.new("SpawnLocation")
spawn.Name = "Camp"
spawn.Anchored = true
spawn.Neutral = true
spawn.Duration = 0
spawn.Size = Vector3.new(14, 1, 14)
spawn.CFrame = CFrame.lookAt(Vector3.new(0, 0.5, spawnDistance), Vector3.new(0, 0.5, 0))
spawn.Material = Enum.Material.WoodPlanks
spawn.Color = Color3.fromRGB(129, 105, 79)
-- Everyone arrives in the royal lobby; joining the game brings them here.
spawn.Enabled = false
spawn.Parent = workspace
local lobby = require(script.Lobby).build(workspace)
-- Diamond Climb: the tower of 1000 platforms, far off in the sky.
local climbGame = ClimbGame.start({
	settings = settings,
	save = function() Store.save(settings) end,
	state = State,
	notify = Notify,
	parent = workspace,
})
-- Chalkboard Count: the classroom and its chalkboard, also far off in the sky.
local filterText: (Player, string) -> string? = function() return nil end
local chalkGame = ChalkGame.start({
	settings = settings,
	save = function() Store.save(settings) end,
	state = State,
	notify = Notify,
	parent = workspace,
	filter = function(player: Player, text: string): string? return filterText(player, text) end,
})

-- Leaderboards stand behind the mountain; the scenery keeps their ground clear.
local Leaderboards = require(script.Leaderboards)
local mountainRadius = spawnDistance - 30
local arenaRadius = math.max(mountainRadius + 14, 55)
local boardSpots = Leaderboards.spots(arenaRadius, mountainRadius, spawn.Position)
local reserved = {}
for _, spot in boardSpots do table.insert(reserved, { at = spot.at, radius = 30 }) end

-- Hills, distant peaks, a lake, a pine forest, boulders and a campfire, in the
-- saved theme (alpine, sakura, farm, desert or haunted).
local Scenery = require(script.Scenery)
if Scenery.LOOKS[settings.theme] == nil then settings.theme = "default" end
Scenery.build(mountainRadius, spawn.Position, reserved, settings.theme)

-- Switches the map's theme live for everyone and remembers it.
local function setTheme(name: string): boolean
	if name == settings.theme or not Scenery.setTheme(name) then return false end
	settings.theme = name
	saveSettings()
	return true
end

-- Every player carries a pickaxe to chip at the rock themselves.
local function makePickaxe(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Pickaxe"
	tool.CanBeDropped = false
	tool.ToolTip = "Click rock to dig it"
	tool.GripPos = Vector3.new(0, -1.3, 0)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.35, 4, 0.35)
	handle.Material = Enum.Material.Wood
	handle.Color = Color3.fromRGB(122, 84, 52)
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(3, 0.45, 0.45)
	head.Material = Enum.Material.Metal
	head.Color = Color3.fromRGB(150, 155, 160)
	head.CanCollide = false
	head.Massless = true
	head.CFrame = handle.CFrame * CFrame.new(0, 1.8, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = head
	weld.Parent = head
	head.Parent = tool
	return tool
end
-- Digging is done with bare hands, so nobody carries a tool.
local _ = makePickaxe
local _ = StarterPack

-- The one diamond -----------------------------------------------------------------
local DiamondShape = require(Shared:WaitForChild("DiamondShape"))
local diamond = Instance.new("Part")
diamond.Name = "Diamond"
-- Sizes are relative to the original gem. Held high, it must read clearly as a
-- diamond to everyone watching, so it is well over twice the found size.
local DIAMOND_BASE_SIZE = Vector3.new(blockSize, blockSize, blockSize) * 0.85
local DIAMOND_WORLD_SIZE = DIAMOND_BASE_SIZE * 2
local DIAMOND_HELD_SIZE = DIAMOND_BASE_SIZE * 6.5
diamond.Size = DIAMOND_WORLD_SIZE
diamond.Material = Enum.Material.Glass
diamond.Color = Color3.fromRGB(175, 240, 255)
diamond.Reflectance = 0.35
diamond.Anchored = true
diamond.CanCollide = false
diamond.CanTouch = false
diamond.CanQuery = false
diamond.Parent = workspace
if Skin.WORDS[settings.skin] == nil then settings.skin = "stone" end
-- In the haystack skin the gem is a needle (see Skin).
diamond:SetAttribute("GemKind", Skin.gem(settings.skin))
DiamondShape.attach(diamond)
local glow = Instance.new("PointLight")
glow.Color = Color3.fromRGB(140, 230, 255)
glow.Range = 8
glow.Brightness = 1.2
glow.Shadows = false
glow.Parent = diamond
-- Sparkles around the raised gem while it is held (default sparkle texture).
local sparkleAttachment = Instance.new("Attachment")
sparkleAttachment.Name = "Sparkle"
sparkleAttachment.Parent = diamond
local sparkles = Instance.new("ParticleEmitter")
sparkles.Name = "HeldSparkles"
sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 235, 255))
sparkles.LightEmission = 1
sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
sparkles.Transparency = NumberSequence.new(0.1, 1)
sparkles.Lifetime = NumberRange.new(0.4, 0.9)
sparkles.Rate = 14
sparkles.Speed = NumberRange.new(0.6, 1.8)
sparkles.SpreadAngle = Vector2.new(180, 180)
sparkles.Enabled = false
sparkles.Parent = sparkleAttachment
local holdOutline = Instance.new("Highlight")
holdOutline.Name = "CountdownDiamond"
holdOutline.Adornee = diamond
holdOutline.FillColor = Color3.fromRGB(135, 235, 255)
holdOutline.FillTransparency = 0.8
holdOutline.OutlineColor = Color3.new(1, 1, 1)
holdOutline.OutlineTransparency = 0.15
holdOutline.Enabled = false
holdOutline.Parent = diamond
local PICKUP_DISTANCE = 12
local click = Instance.new("ClickDetector")
click.Name = "ClickToPickUp"
click.MaxActivationDistance = 0
click.Parent = diamond

local DIAMOND_TILT = CFrame.Angles(0, math.rad(22.5), 0)

-- Reskins the mountain live for everyone (stone and a diamond, or hay and a
-- needle) and remembers it. Each player's game repaints its own rock.
local function setSkin(name: string): boolean
	if name == settings.skin or Skin.WORDS[name] == nil then return false end
	settings.skin = name
	DiamondShape.setKind(diamond, Skin.gem(name))
	saveSettings()
	return true
end

-- Round state -------------------------------------------------------------------
local mountain: Mountain.Mountain? = nil
local phase = "Digging"
local startingStone = settings.startingStone
local pendingChanges: { number } = {}
local roundStart = 0
local holder: Player? = nil
local holdStarted = 0
local holdWeld: WeldConstraint? = nil
local mineCooldown: { [Player]: number } = {}
local admins: { [Player]: boolean } = {}
local settling: Tween? = nil
-- Gift and rebuild work runs one job at a time (stoneBusy). Players keep
-- digging and can grab an uncovered diamond while a gift blasts; only a
-- rebuild refilling rock (stoneWork == "restore") holds the grab back.
local stoneBusy = false
local stoneWork: string? = nil
local requestedRound: boolean? = nil

local function stopSettling()
	if settling then
		settling:Cancel()
		settling = nil
	end
end

local function setPhase(value: string)
	phase = value
	State:SetAttribute("Phase", value)
end

local function refreshStone()
	State:SetAttribute("Stone", if mountain then mountain:remaining() else 0)
	State:SetAttribute("StartingStone", startingStone)
	State:SetAttribute("MountainTotal", if mountain then mountain:total() else startingStone)
end

local function showDiamond(visible: boolean)
	DiamondShape.resize(diamond, if phase == "Holding" then DIAMOND_HELD_SIZE else DIAMOND_WORLD_SIZE)
	DiamondShape.visible(diamond, visible)
	diamond.CanQuery = visible and phase == "Revealed"
	-- No through-rock outline, beacon or floating location label while searching.
	glow.Enabled = visible and phase == "Holding"
	holdOutline.Enabled = visible and phase == "Holding"
	sparkles.Enabled = visible and phase == "Holding"
	click.MaxActivationDistance = if visible and phase == "Revealed" then PICKUP_DISTANCE else 0
end

-- Mountain sync --------------------------------------------------------------------
-- Players whose client asked for the mountain; only they receive changes.
local synced: { [Player]: boolean } = {}
local readyAt: { [Player]: number } = {}
local catchAt: { [Player]: number } = {}
local hideAt: { [Player]: number } = {}
local function sendMessages(messages: { { any } }, player: Player?)
	for _, message in messages do
		if player then
			MountainSync:FireClient(player, message[1], message[2])
		else
			for listener in synced do MountainSync:FireClient(listener, message[1], message[2]) end
		end
	end
end
local lastFlush = 0
local function flushMountain(effect: string?, at: Vector3?)
	local current = mountain
	if current == nil then return end
	lastFlush = os.clock()
	for _, diff in current:flush(effect, at) do
		for listener in synced do MountainSync:FireClient(listener, "diff", diff) end
	end
end

-- The find stays at its reserved lower, central cell even when support is dug
-- away. Only carrying it unanchors it; releasing it returns it to that cell.
local function settleDiamond()
	if phase ~= "Revealed" or mountain == nil or not diamond.Anchored then return end
	stopSettling()
	diamond.CFrame = CFrame.new(mountain:keyPosition(mountain.diamondKey)) * DIAMOND_TILT
end

local function reveal(open: boolean)
	if not open then
		if phase == "Revealed" then
			setPhase("Digging")
			showDiamond(false)
		end
		return
	end
	if phase ~= "Digging" then
		return
	end
	setPhase("Revealed")
	showDiamond(true)
	Notify:FireAllClients("revealed")
end

-- One rock is one stone: blast exactly that many rocks.
local interruptRebuildHold: (number, Player?) -> () = function(_restored: number, _player: Player?) end
local cancelHoldForRebuild: () -> Player? = function() return nil end
local function growthCapacity(): number
	return math.max(Config.GrowthMaxStone, startingStone * 2)
end
-- Long rock work yields every few milliseconds so the server keeps its frame
-- rate. Changes stream to clients while the work continues. The server draws
-- no rock, so it can spend about half of each 60 Hz frame on a gift.
local GIFT_WORK_SECONDS = 0.008
local function workCheckpoint(onYield: (() -> ())?, effect: string?, budget: number?): () -> ()
	local frameStart = os.clock()
	local lastCountUpdate = frameStart
	local slice = budget or GIFT_WORK_SECONDS
	return function()
		if os.clock() - frameStart >= slice then
			if os.clock() - lastCountUpdate >= 0.1 then
				-- Publish the final count after geometry is reconciled, not ahead of it.
				if onYield then onYield() end
				lastCountUpdate = os.clock()
			end
			if mountain and mountain:hasChanges() and os.clock() - lastFlush >= 0.05 then
				flushMountain(effect)
			end
			task.wait()
			frameStart = os.clock()
		end
	end
end
local function applyStone(amount: number, centreKey: number?): (Vector3?, number?)
	amount = math.floor(amount)
	if amount == 0 then return nil, 0 end
	local current = mountain
	if phase == "Won" or phase == "Rebuilding" or current == nil then
		-- Gifts during the win screen count towards the next mountain.
		table.insert(pendingChanges, amount)
		return
	end
	if amount < 0 then
		local capacity = growthCapacity()
		local interrupted = if current:remaining() < capacity then cancelHoldForRebuild() else nil
		local checkpoint = workCheckpoint(function() interruptRebuildHold(0, interrupted) end, "restore")
		stoneWork = "restore"
		local restored, at = current:restore(-amount, capacity, checkpoint)
		stoneWork = nil
		flushMountain("restore", at)
		if restored > 0 then interruptRebuildHold(restored, interrupted) end
		refreshStone()
		if phase == "Revealed" then
			stopSettling()
			settleDiamond()
		end
		return at, -restored
	end
	local count = math.min(amount, current:remaining())
	stoneWork = "blast"
	local centre = current:blast(count, workCheckpoint(nil, "blast"), centreKey)
	stoneWork = nil
	flushMountain("blast", centre)
	-- Gift spectacle is rendered by GiftEffects on each client. Never create a
	-- physics Explosion: blasts may remove grid stones, never the diamond or rigs.
	refreshStone()
	settleDiamond()
	return centre, count
end

local function teleportHome(player: Player)
	-- Players in the lobby stay there.
	if player:GetAttribute("InGame") ~= true then return end
	local character = player.Character
	if character ~= nil then
		character:PivotTo(spawn.CFrame + Vector3.new(0, 4, 0))
	end
end

-- Raises the right arm straight up to the sky (R15 and R6 rigs) while holding.
local raisedArms: { [Motor6D]: CFrame } = {}
local function raiseArms(character: Model)
	local motors: { { motor: Motor6D, up: CFrame } } = {}
	-- One arm up: only the right shoulder lifts.
	for _, spec in { { "RightUpperArm", "RightShoulder" }, { "Torso", "Right Shoulder" } } do
		local parent = character:FindFirstChild(spec[1])
		local motor = parent and parent:FindFirstChild(spec[2])
		if motor ~= nil and motor:IsA("Motor6D") then
			local up = if spec[1] == "Torso"
				then CFrame.Angles(0, 0, math.rad(if spec[2] == "Right Shoulder" then 170 else -170))
				else CFrame.Angles(math.rad(170), 0, 0)
			table.insert(motors, { motor = motor, up = up })
		end
	end
	for _, entry in motors do
		local motor, up = entry.motor, entry.up
		local original: CFrame? = raisedArms[motor]
		if original == nil then
			original = motor.C0
			raisedArms[motor] = motor.C0
		end
		TweenService:Create(motor, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { C0 = (original :: CFrame) * up }):Play()
	end
end

local function lowerArms()
	for motor, original in raisedArms do
		if motor.Parent ~= nil then
			TweenService:Create(motor, TweenInfo.new(0.25), { C0 = original }):Play()
		end
	end
	table.clear(raisedArms)
end

-- The diamond holder cannot move until a rebuild cancels the hold or they win.
local frozen: { player: Player, humanoid: Humanoid, root: BasePart, walk: number, jump: number, jumpHeight: number, autoRotate: boolean }? = nil
local function freeze(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or not root:IsA("BasePart") then return end
	frozen = {
		player = player,
		humanoid = humanoid,
		root = root,
		walk = humanoid.WalkSpeed,
		jump = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
		autoRotate = humanoid.AutoRotate,
	}
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.Anchored = true
end
local function unfreeze()
	local state = frozen
	frozen = nil
	if state == nil then return end
	if state.humanoid.Parent then
		state.humanoid.WalkSpeed = state.walk
		state.humanoid.JumpPower = state.jump
		state.humanoid.JumpHeight = state.jumpHeight
		state.humanoid.AutoRotate = state.autoRotate
	end
	if state.root.Parent then
		state.root.Anchored = false
		-- Hand physics back to the player's own client.
		pcall(function() state.root:SetNetworkOwner(state.player) end)
	end
end

local rebuilding = false
local REBUILD_SECONDS = 0.5 + 16 * 0.15 -- matches the client's base-to-summit waves
local function newRound(animated: boolean?)
	if stoneBusy then requestedRound = animated == true; return end
	if rebuilding then return end
	rebuilding = true
	setPhase("Rebuilding")
	showDiamond(false)
	stopSettling()
	mountain = nil
	holder = nil
	unfreeze()
	lowerArms()
	if holdWeld ~= nil then
		holdWeld:Destroy()
		holdWeld = nil
	end
	-- Held, the diamond is unanchored: without this it falls out of the world
	-- (and is destroyed) while the new mountain is built.
	diamond.Anchored = true
	diamond.AssemblyLinearVelocity = Vector3.zero
	for _, player in Players:GetPlayers() do
		teleportHome(player)
	end
	startingStone = math.clamp(settings.startingStone, 100, 1500000)
	-- Larger slices while nothing else runs; the win screen covers the build.
	local created = Mountain.new(startingStone, blockSize, reveal, workCheckpoint(nil, nil, 0.008))
	mountain = created
	startingStone = created:total()
	diamond.Anchored = true
	diamond.CFrame = CFrame.new(created:keyPosition(created.diamondKey)) * DIAMOND_TILT
	showDiamond(false)
	roundStart = workspace:GetServerTimeNow()
	State:SetAttribute("RoundStart", roundStart)
	State:SetAttribute("Holder", "")
	State:SetAttribute("HolderUserId", 0)
	State:SetAttribute("HoldStart", 0)
	refreshStone()
	sendMessages(created:snapshot(animated == true, workspace:GetServerTimeNow() + 0.5))
	if animated then
		task.wait(REBUILD_SECONDS)
	end
	rebuilding = false
	setPhase("Digging")
	roundStart = workspace:GetServerTimeNow()
	State:SetAttribute("RoundStart", roundStart)
	-- Gifts sent during the win screen apply now, one job at a time: a gift
	-- that started meanwhile finishes first, so the two never overlap.
	while stoneBusy do task.wait() end
	local carried = pendingChanges
	pendingChanges = {}
	stoneBusy = true
	for _, change in carried do
		local ok, problem = pcall(function() applyStone(change) end)
		if not ok then warn("[DiamondRush] queued gift failed: " .. tostring(problem)) end
	end
	stoneWork = nil
	stoneBusy = false
	-- A new round asked for while the carried gifts ran starts now.
	if requestedRound ~= nil then
		local again = requestedRound
		requestedRound = nil
		task.spawn(newRound, again)
	end
end

-- Holding the diamond -----------------------------------------------------------
local function grab(player: Player)
	-- A blasting gift may still be running: the diamond can be taken as soon
	-- as it shows. Not while a rebuild is refilling the rock around it.
	if stoneWork == "restore" or phase ~= "Revealed" then
		return
	end
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if head == nil or not head:IsA("BasePart") or humanoid == nil or humanoid.Health <= 0 then
		return
	end
	-- ClickDetector events can be forged: range and an unobstructed sightline
	-- are checked again on the server before claiming the single diamond.
	-- Rock only exists on clients, so the sightline is checked on the grid.
	local current = mountain
	local direction = diamond.Position - head.Position
	if current == nil or direction.Magnitude > PICKUP_DISTANCE or current:lineBlocked(head.Position, diamond.Position) then
		return
	end
	stopSettling()
	holder = player
	holdStarted = os.clock()
	State:SetAttribute("Holder", player.DisplayName)
	State:SetAttribute("HolderUserId", player.UserId)
	State:SetAttribute("HoldStart", workspace:GetServerTimeNow())
	setPhase("Holding")
	showDiamond(true)
	-- The world diamond belongs to the real hand, including when that arm moves.
	diamond.Anchored = false
	diamond.Massless = true
	diamond.CanCollide = false
	local hand = (character :: Model):FindFirstChild("RightHand") or (character :: Model):FindFirstChild("Right Arm")
	local grip: BasePart = if hand and hand:IsA("BasePart") then hand else head
	local offset = if grip == head then CFrame.new(0.8, 1.4 + diamond.Size.Y / 2, -0.6) else CFrame.new(0, -grip.Size.Y / 2 - diamond.Size.Y * 0.45, -0.08)
	diamond.CFrame = grip.CFrame * offset * DIAMOND_TILT
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = grip
	weld.Part1 = diamond
	weld.Parent = diamond
	holdWeld = weld
	raiseArms(character :: Model)
	freeze(player, character :: Model)
	Notify:FireAllClients("grabbed", player.DisplayName)
end

local function drop(reason: string)
	if phase ~= "Holding" then
		return
	end
	stopSettling()
	local lost = holder
	holder = nil
	holdStarted = 0
	unfreeze()
	lowerArms()
	if holdWeld ~= nil then
		holdWeld:Destroy()
		holdWeld = nil
	end
	diamond.Anchored = true
	diamond.AssemblyLinearVelocity = Vector3.zero
	if mountain then diamond.CFrame = CFrame.new(mountain:keyPosition(mountain.diamondKey)) * DIAMOND_TILT end
	setPhase("Revealed")
	showDiamond(true)
	State:SetAttribute("Holder", "")
	State:SetAttribute("HolderUserId", 0)
	State:SetAttribute("HoldStart", 0)
	Notify:FireAllClients("dropped", { name = if lost then lost.DisplayName else "", reason = reason })
end

cancelHoldForRebuild = function()
	local interrupted = if phase == "Holding" then holder else nil
	if interrupted then drop("rebuild") end
	return interrupted
end
-- Puts a player on top of the rock: at `destination` if given, else out of
-- any restored rock their body is inside (`centreOnly`: only rock right where
-- they stand, not rock beside them).
local function liftOut(current: Mountain.Mountain, player: Player, destination: Vector3?, centreOnly: boolean?)
	if player:GetAttribute("InGame") ~= true or player == holder then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character == nil or root == nil or not root:IsA("BasePart") or humanoid == nil or humanoid.Health <= 0 then return end
	local clearance = humanoid.HipHeight + root.Size.Y / 2
	-- R6 rigs use zero HipHeight; account for their legs.
	if humanoid.RigType == Enum.HumanoidRigType.R6 then clearance += 2 end
	if destination == nil then
		-- Lift players whose body is now inside restored rock onto its surface.
		local feet = root.Position.Y - clearance
		local top = current:coveredTop(root.Position, feet + 0.15, root.Position.Y + 1.5, centreOnly)
		if top then destination = Vector3.new(root.Position.X, top, root.Position.Z) end
	end
	if destination then
		local target = destination + Vector3.new(0, clearance + 1, 0)
		character:PivotTo(character:GetPivot() + (target - root.Position))
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
end
-- Each client draws the rock itself, a moment after the server restores it.
-- A player lifted onto rock their client has not drawn yet falls back into
-- the old hole, and the rock then appears round them (the holder, moved to
-- the summit after a big rebuild, was trapped like this). So for a few
-- seconds after rock comes back, anyone standing inside it is lifted again.
local UNBURY_SECONDS, UNBURY_EVERY = 6, 0.4
local unburySerial = 0
local function keepUnburying()
	unburySerial += 1
	local serial = unburySerial
	task.spawn(function()
		for _ = 1, math.ceil(UNBURY_SECONDS / UNBURY_EVERY) do
			task.wait(UNBURY_EVERY)
			local current = mountain
			if serial ~= unburySerial or current == nil then return end
			for _, player in Players:GetPlayers() do
				liftOut(current, player, nil, true)
			end
		end
	end)
end
interruptRebuildHold = function(restored: number, interrupted: Player?)
	local current = mountain
	if current == nil then return end
	-- The former holder goes to the highest restored surface after a big rebuild.
	local summit = if interrupted and restored >= 10000 then current:summit() else nil
	for _, player in Players:GetPlayers() do
		liftOut(current, player, if player == interrupted then summit else nil)
	end
	if restored > 0 then keepUnburying() end
end

local function win(player: Player)
	setPhase("Won")
	-- The winner may move again; the arm stays raised until the next round.
	unfreeze()
	click.MaxActivationDistance = 0
	local roundTime = workspace:GetServerTimeNow() - roundStart
	local newBest = settings.best <= 0 or roundTime < settings.best
	if newBest then
		settings.best = roundTime
	end
	settings.wins += 1
	State:SetAttribute("LastTime", roundTime)
	saveSettings()
	Notify:FireAllClients("win", {
		winner = player.DisplayName,
		time = roundTime,
		best = settings.best,
		newBest = newBest,
	})
	task.delay(Config.WinScreenSeconds, function() newRound(true) end)
end

click.MouseClick:Connect(grab)

RunService.Heartbeat:Connect(function()
	if phase ~= "Holding" then
		return
	end
	local player = holder
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if player == nil or player.Parent == nil or character == nil or humanoid == nil or humanoid.Health <= 0 then
		drop("left")
		return
	end
	if holdWeld == nil or holdWeld.Parent == nil or diamond.Position.Y < -50 then
		drop("fell")
		return
	end
	if os.clock() - holdStarted >= Config.HoldSeconds then
		win(player)
	end
end)

-- Leaderboards --------------------------------------------------------------------
local showcase = Instance.new("Folder")
showcase.Name = "Leaderboards"
showcase.Parent = workspace
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.FilterDescendantsInstances = { workspace.Terrain }
local function groundAt(position: Vector3): number
	local hit = workspace:Raycast(Vector3.new(position.X, 400, position.Z), Vector3.new(0, -520, 0), groundParams)
	return if hit then hit.Position.Y else 0
end
-- Raised so both boards show over the summit as seen from the camp.
local boardLift = math.max(14, mountainRadius * 0.55)
local helperBoard = Leaderboards.build(showcase, boardSpots[1].at, boardSpots[1].facing, boardLift, {
	title = "TOP HELPERS",
	unit = "coins",
	trim = Color3.fromRGB(36, 92, 204),
	valueColour = Color3.fromRGB(160, 214, 255),
	emblem = "pickaxe",
	empty = "Send a gift to help break the mountain!",
}, groundAt)
local grieferBoard = Leaderboards.build(showcase, boardSpots[2].at, boardSpots[2].facing, boardLift, {
	title = "TOP GRIEFERS",
	unit = "coins",
	trim = Color3.fromRGB(196, 36, 44),
	valueColour = Color3.fromRGB(255, 178, 188),
	emblem = "boulders",
	empty = "Nobody has added stone... yet!",
}, groundAt)
local helperTally = Leaderboards.tally(settings.leaderboards.helpers)
local grieferTally = Leaderboards.tally(settings.leaderboards.griefers)
local SAMPLE_HELPERS: { { any } } = { { "DiamondDave", 34999 }, { "LunaStreams", 12500 }, { "rocky_road", 5000 }, { "GemHunter99", 2999 }, { "Pixel Pam", 1000 },
	{ "tiktok_tom", 520 }, { "MinerMia", 300 }, { "Sir Digs-a-Lot", 150 }, { "glitterbug", 99 }, { "rose_rain", 30 } }
local SAMPLE_GRIEFERS: { { any } } = { { "StoneLord", 29999 }, { "BrickByBrick", 10000 }, { "Pebble", 4500 }, { "mason.mo", 2999 }, { "RockSolid", 1500 },
	{ "boulder_bro", 699 }, { "Ava", 299 }, { "quarry_kid", 100 }, { "cement_sam", 55 }, { "newviewer22", 5 } }

-- Viewer names come from TikTok, so they are filtered like any other text
-- shown to players. Results are cached; a name that cannot be checked shows as "Viewer".
local shownNames: { [string]: string } = {}
local shownNameCount = 0
local function boardName(raw: string): string?
	local cached = shownNames[raw]
	if cached then return cached end
	local author: Player? = nil
	for player, isAdmin in admins do
		if isAdmin then author = player; break end
	end
	author = author or Players:GetPlayers()[1]
	if author == nil then return nil end
	local authorId = (author :: Player).UserId
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(raw, authorId, Enum.TextFilterContext.PublicChat):GetNonChatStringForBroadcastAsync()
	end)
	local clean = if ok and type(result) == "string" and result ~= "" then result else "Viewer"
	if shownNameCount > 3000 then
		table.clear(shownNames)
		shownNameCount = 0
	end
	shownNames[raw] = clean
	shownNameCount += 1
	return clean
end

local boardsScheduled = false
local boardsDirty = false
local lastBoardSave = 0
local previewUntil = 0
local function refreshBoards()
	boardsScheduled = false
	local previewing = os.clock() < previewUntil
	local function draw(board: Leaderboards.Board, tally: Leaderboards.Tally, samples: { { any } })
		local entries: { Leaderboards.Entry } = {}
		if previewing then
			for _, sample in samples do table.insert(entries, { key = sample[1], name = sample[1], value = sample[2] }) end
		else
			for _, entry in tally.top(Leaderboards.ROWS) do
				local name = boardName(entry.name)
				table.insert(entries, { key = entry.key, name = name or "…", value = entry.value })
			end
		end
		board.show(entries)
	end
	draw(helperBoard, helperTally, SAMPLE_HELPERS)
	draw(grieferBoard, grieferTally, SAMPLE_GRIEFERS)
	settings.leaderboards = { helpers = helperTally.serialize(100), griefers = grieferTally.serialize(100) }
	if boardsDirty and os.clock() - lastBoardSave >= 20 then
		boardsDirty = false
		lastBoardSave = os.clock()
		saveSettings()
	end
end
-- Coalesces bursts of gifts into one refresh a second.
local function scheduleBoards()
	if boardsScheduled then return end
	boardsScheduled = true
	task.delay(1, refreshBoards)
end
-- `rocks` is the gift's effect: positive breaks the mountain, negative adds stone.
local function recordGifter(event: GiftEvent, rocks: number, coins: number)
	-- Test gifts and keyed gifts (the sender isn't known) never count.
	if event.user == "tester" or string.sub(event.id, 1, 5) == "test-" then return end
	if rocks == 0 then return end
	local key = string.lower(event.user or event.name or "")
	local name = event.name or event.user or "Viewer"
	if rocks > 0 then helperTally.add(key, name, coins) else grieferTally.add(key, name, coins) end
	boardsDirty = true
	scheduleBoards()
end
Players.PlayerAdded:Connect(scheduleBoards)
-- Unsaved totals are written every 20 seconds while they change.
task.spawn(function()
	while true do
		task.wait(20)
		if boardsDirty then scheduleBoards() end
	end
end)
-- Name filtering can yield, so the first draw runs on its own.
task.spawn(refreshBoards)

-- The diamond bird ----------------------------------------------------------------
-- It circles the mountain every 5 to 7½ minutes; whoever clicks it doubles
-- every gift for 30 seconds.
local diamondBird = require(script.DiamondBird).start({
	state = State,
	notify = Notify,
	radius = mountainRadius + 12,
	-- Low enough to see and click from the trail: about halfway up the
	-- mountain, never lower than head height above the camp.
	height = function(): number
		local top = if mountain then mountain:summit() else nil
		return math.max(12, (if top then top.Y else mountainRadius) * 0.5 + 4)
	end,
})
-- Gifts that arrived during the bonus, so the feed can say so.
local doubledGifts: { [GiftEvent]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- Gifts ------------------------------------------------------------------------
local function processTikTok(event: GiftEvent)
	-- Names and gift names come from TikTok (or a typed keybind), so they go
	-- through Roblox's text filter before anyone sees them.
	local who = boardName(event.name or event.user or "Someone") or "Viewer"
	local giftLabel = if event.gift then (boardName(event.gift) or "a gift") else nil;
	(event :: any).giftLabel = giftLabel
	-- The show chosen for this gift in the gift settings (nil: its coins pick).
	local effectTier = if event.type == "gift" then settings.animRules[string.lower(event.gift or "")] else nil;
	(event :: any).effectTier = effectTier
	local amount = 0
	local text = ""
	if event.type == "gift" then
		local count = math.max(1, math.floor(event.count or 1))
		local coins = math.max(1, event.coins or 1)
		local rule = if event.rocks ~= nil then event.rocks else settings.giftRules[string.lower(event.gift or "")]
		amount = if rule ~= nil then rule * count else coins * count * settings.perCoin
		text = if event.parts == nil
			then string.format("%s sent %s x%d", who, giftLabel or "a gift", count)
			elseif count == 1 then string.format("%s sent %s (%d of %d)", who, giftLabel or "a gift", event.part or 1, event.parts)
			else string.format("%s sent %s x%d (%d of %d)", who, giftLabel or "a gift", count, event.part or 1, event.parts)
		recordGifter(event, amount, coins * count)
		-- Wins per gift (gift settings): the win counter of the game being played.
		local winRule = settings.winRules[string.lower(event.gift or "")]
		if winRule ~= nil and winRule ~= 0 then
			local change = winRule * count
			if chalkGame.writer() ~= nil then
				chalkGame.addWins(change)
			elseif climbGame.climber() ~= nil then
				climbGame.addWins(change)
			else
				settings.wins = math.clamp(settings.wins + change, -999999, 999999)
				saveSettings()
			end
			text ..= string.format("  %s%d WIN%s", if change > 0 then "+" else "", change, if math.abs(change) == 1 then "" else "S")
		end
		-- A reset gift sends the game being played back to the start, and does
		-- nothing else (no blast or climb on top of the fresh start).
		if settings.resetGifts[string.lower(event.gift or "")] then
			if chalkGame.writer() ~= nil then
				chalkGame.resetNow()
				text ..= "  RESET: back to 0"
			elseif climbGame.climber() ~= nil then
				climbGame.restart()
				text ..= "  RESET: back to platform 0"
			elseif phase ~= "Won" and phase ~= "Rebuilding" then
				newRound()
				text ..= "  RESET: a full mountain again"
			end
			Notify:FireAllClients("feed", { text = text, stone = 0, kind = event.type })
			return
		end
	elseif event.type == "like" then
		local likes = math.max(1, math.floor(event.likes or 1))
		amount = likes * settings.perLike
		text = string.format("%s liked x%d", who, likes)
	elseif event.type == "follow" then
		amount = settings.perFollow
		text = who .. " followed"
	elseif event.type == "share" then
		amount = settings.perShare
		text = who .. " shared the live"
	end
	if chalkGame.writer() ~= nil then
		-- In Chalkboard Count gifts move the count up or down, the reset gift
		-- starts the countdown and a big enough gift saves it.
		if event.type == "like" then return end
		local rule = if event.type == "gift" then settings.chalkRules[string.lower(event.gift or "")] else nil
		local ending = chalkGame.gift(who, event, amount, doubledGifts[event] == true, rule)
		if doubledGifts[event] then text = "2X " .. text end
		Notify:FireAllClients("feed", { text = text .. ending, stone = 0, kind = event.type })
		return
	end
	if climbGame.climber() ~= nil then
		-- In Diamond Climb gifts send the climber up the tower (gifts that would
		-- break the mountain) or down it (gifts that add stone); follows and
		-- shares lift them one platform. Likes leave the climb alone.
		if event.type == "like" then return end
		local coins = math.max(1, event.coins or 1)
		-- The streamer's own rule for this gift wins; otherwise its coins.
		local rule = if event.type == "gift" then settings.climbRules[string.lower(event.gift or "")] else nil
		local move = if rule ~= nil then math.floor(rule) * math.max(1, math.floor(event.count or 1))
			elseif event.type == "gift" then ClimbGame.giftMove(amount, coins, event.count or 1, climbGame.progress.strength)
			elseif amount > 0 then 1 else 0
		local from, to, wallDamage, wallBroke = climbGame.gift(who, move, {
			coins = if event.type == "gift" then coins else 1,
			tier = effectTier,
			gift = (giftLabel or (if event.type == "follow" then "Follow" elseif event.type == "share" then "Share" else "Gift"))
				.. (if event.parts then string.format("  (%d of %d)", event.part or 1, event.parts) else ""),
		})
		local moved = to - from
		if doubledGifts[event] then text = "2X " .. text end
		text ..= if moved > 0 then string.format("  UP %d", moved) elseif moved < 0 then string.format("  DOWN %d", -moved) else ""
		-- Pushed back past platform 0: the wall takes the rest.
		if wallBroke then
			text ..= "  WALL BROKEN! -1 WIN"
		elseif wallDamage > 0 then
			text ..= string.format("  WALL -%s", Format.commas(wallDamage))
		end
		Notify:FireAllClients("feed", { text = text, stone = 0, kind = event.type })
		return
	end
	if amount <= 0 and event.type ~= "gift" then return end
	local current = mountain
	local centreKey = if current then current.grid:randomExposed() else nil
	local preview = if current and centreKey then current:keyPosition(centreKey) else Vector3.new(0, 8, 0)
	-- Gifts that add stone play their effect on the summit: the mountain is fed.
	if amount < 0 and current then preview = current:summit() or preview end
	local available = if current then current:remaining() else 0
	local blocks = if phase == "Won" or phase == "Rebuilding" then nil elseif amount < 0 then -math.min(-amount, math.max(0, growthCapacity() - available)) else math.min(amount, available)
	-- Start the animation promptly while the queued rock work spans frames.
	if event.type == "gift" then
		Notify:FireAllClients("giftEffect", {
			-- One gift's coins, never the combo total: Galaxy x10 arrives here
			-- as ten Galaxies, each with the Galaxy's own effect.
			coins = math.max(1, event.coins or 1),
			tier = effectTier,
			position = preview,
			name = who,
			gift = (giftLabel or "Gift") .. (if event.parts then string.format("  (%d of %d)", event.part or 1, event.parts) else ""),
			adding = amount < 0,
			blocks = if amount < 0 then nil else blocks,
		})
	end
	local _centre, applied = applyStone(amount, centreKey)
	if doubledGifts[event] then text = "2X " .. text end
	Notify:FireAllClients("feed", { text = text .. (if applied == nil then " (queued)" elseif amount < 0 and applied == 0 then " (mountain full)" else ""), stone = applied or amount, kind = event.type })
end

-- One yielding worker owns all gift mutations; polling stays responsive and
-- overlapping live/test events cannot corrupt the grid or overtake each other.
local giftQueue: { GiftEvent } = {}
local giftHead = 1
local giftWorkerRunning = false
local enqueue: (GiftEvent) -> ()

-- A gift sent several times at once (Galaxy x10) plays as that many separate
-- gifts: each one blasts or adds its own stone with its own effect and feed
-- line, spaced so every effect gets its moment instead of one bigger effect
-- for the combined coins. Very long combos (Rose x500) are shared out over
-- at most MAX_SPLIT gifts so the show stays short.
local MAX_SPLIT = 20
-- Seconds between the gifts of a combo, by the gift's effect tier: about half
-- an effect, so at most two overlap (the client plays two at once).
local SPLIT_SPACING = { 0.6, 0.8, 1.2, 2.2, 2.8, 3.7 }
local function splitCombo(event: GiftEvent, doubled: boolean)
	local count = math.max(1, math.floor(event.count or 1))
	local parts = math.min(count, MAX_SPLIT)
	local spacing = SPLIT_SPACING[GiftTier.forCoins(math.max(1, event.coins or 1))]
	for part = 1, parts do
		local copy = table.clone(event)
		copy.count = count // parts + (if part <= count % parts then 1 else 0)
		copy.part = part
		copy.parts = parts
		if doubled then doubledGifts[copy] = true end
		if part == 1 then enqueue(copy) else task.delay((part - 1) * spacing, enqueue, copy) end
	end
end

local function onTikTok(event: GiftEvent)
	-- While the diamond bird's bonus runs, a gift counts as if it were sent
	-- twice: double the stone blasted or added, the effect and the leaderboard
	-- coins. It is decided on arrival, so gifts still queued keep their bonus.
	local multiplier = diamondBird.multiplier()
	if event.type == "gift" and multiplier > 1 then
		event = table.clone(event)
		event.count = math.max(1, math.floor(event.count or 1)) * multiplier
		doubledGifts[event] = true
	end
	if event.type == "gift" and math.floor(event.count or 1) > 1 then
		splitCombo(event, doubledGifts[event] == true)
		return
	end
	enqueue(event)
end

function enqueue(event: GiftEvent)
	table.insert(giftQueue, event)
	State:SetAttribute("GiftQueueLength", #giftQueue - giftHead + 1)
	if giftWorkerRunning then return end
	giftWorkerRunning = true
	task.spawn(function()
		local workerFrameStart = os.clock()
		while giftHead <= #giftQueue do
			while stoneBusy do task.wait() end
			local nextEvent = giftQueue[giftHead]
			giftHead += 1
			State:SetAttribute("GiftQueueLength", #giftQueue - giftHead + 1)
			stoneBusy = true
			State:SetAttribute("GiftProcessing", true)
			local ok, problem = pcall(processTikTok, nextEvent)
			stoneWork = nil
			stoneBusy = false
			if not ok then warn("[DiamondRush] gift failed: " .. tostring(problem)) end
			-- Digs made during the gift reach the players now if no gift change carried them.
			if mountain and mountain:hasChanges() then flushMountain() end
			if requestedRound ~= nil then
				local animated = requestedRound
				requestedRound = nil
				local roundOk, roundProblem = pcall(newRound, animated)
				if not roundOk then warn("[DiamondRush] new round failed: " .. tostring(roundProblem)) end
			end
			State:SetAttribute("GiftQueueLength", #giftQueue - giftHead + 1)
			if os.clock() - workerFrameStart >= 0.003 then
				task.wait()
				workerFrameStart = os.clock()
			end
		end
		table.clear(giftQueue)
		giftHead = 1
		giftWorkerRunning = false
		State:SetAttribute("GiftProcessing", false)
	end)
end

-- Pickaxe mining and settings ---------------------------------------------------------
local function isAdmin(player: Player): boolean
	if Config.SinglePlayer or RunService:IsStudio() then
		return true
	end
	if table.find(Config.Admins, player.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	local ok, rank = pcall(player.GetRankInGroupAsync, player, game.CreatorId)
	return ok and rank >= 255
end

local function filtered(player: Player, text: string): string?
	local ok, result = pcall(function()
		local filter = TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
		return filter:GetNonChatStringForBroadcastAsync()
	end)
	return if ok then result else nil
end
filterText = filtered

-- Rebuild test presets: blocks added -> the coins that pick its effect tier.
local REBUILD_TEST_COINS: { [number]: number } = { [100] = 1, [1000] = 10, [10000] = 100, [50000] = 500, [100000] = 1000, [1500000] = 10000 }
local function testGift(coins: number, count: number, name: string, rocks: number?, from: string?)
	onTikTok({
		id = "test-" .. tostring(os.clock()),
		type = "gift",
		name = from or "Test",
		gift = name,
		rocks = rocks,
		coins = coins,
		count = count,
	})
end

-- Gold statues ---------------------------------------------------------------------
local Statue = require(script.Statue)
local MAX_STATUES = 12
local statueFolder = Instance.new("Folder")
statueFolder.Name = "Statues"
statueFolder.Parent = workspace
local function notice(player: Player, text: string)
	Notify:FireClient(player, "notice", text)
end
local function buildStatues()
	statueFolder:ClearAllChildren()
	for _, statue in settings.statues do
		Statue.build(statueFolder, { name = statue.n, coins = statue.c, position = Vector3.new(statue.x, statue.y, statue.z), yaw = statue.r })
	end
end
buildStatues()

-- Places a statue 9 studs in front of the streamer, facing them.
local function placeStatue(player: Player, value: any)
	local name = if type(value.name) == "string" then string.gsub(string.sub(value.name, 1, 30), "^%s*(.-)%s*$", "%1") else ""
	if name == "" then
		notice(player, "Type the gifter's name for the plaque first.")
		return
	end
	if #settings.statues >= MAX_STATUES then
		notice(player, "You already have " .. MAX_STATUES .. " statues. Remove one first.")
		return
	end
	local coins = if type(value.coins) == "number" and value.coins == value.coins then math.clamp(math.floor(value.coins), 0, 999999999) else 0
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if character == nil or root == nil or not root:IsA("BasePart") then return end
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	local forward = if look.Magnitude > 0.1 then look.Unit else Vector3.new(0, 0, -1)
	local spot = root.Position + forward * 9
	if Vector3.new(spot.X, 0, spot.Z).Magnitude < arenaRadius then
		notice(player, "Too close to the mountain: walk back towards the camp and try again.")
		return
	end
	local clean = filtered(player, name)
	if clean == nil then
		notice(player, "Could not check that name. Try again in a moment.")
		return
	end
	local exclude = { statueFolder, diamond } :: { Instance }
	for _, other in Players:GetPlayers() do
		if other.Character then table.insert(exclude, other.Character) end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(spot + Vector3.new(0, 40, 0), Vector3.new(0, -140, 0), params)
	local y = if hit then hit.Position.Y else 0
	table.insert(settings.statues, { n = clean, c = coins, x = spot.X, y = y, z = spot.Z, r = math.atan2(forward.X, forward.Z) })
	buildStatues()
	saveSettings()
	notice(player, "Gold statue placed for " .. clean .. "!")
end

local function removeStatue(player: Player, index: number)
	local statue = settings.statues[index]
	if statue == nil then return end
	table.remove(settings.statues, index)
	buildStatues()
	saveSettings()
	notice(player, "Removed the statue for " .. statue.n .. ".")
end

-- Removes the statue the streamer is standing next to.
local STATUE_REACH = 30
local function removeNearestStatue(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then return end
	local index = Statue.nearest(settings.statues, root.Position, STATUE_REACH)
	if index == nil then
		notice(player, if #settings.statues == 0 then "There are no statues to remove."
			else "Walk up to the statue you want to remove, then press the button again.")
		return
	end
	removeStatue(player, index)
end

-- The lobby and the games ------------------------------------------------------------
-- Players arrive in the lobby and join Diamond in the Rough (the InGame
-- attribute) or Diamond Climb (InClimb) from the games menu; "Back to lobby"
-- returns them. Respawns follow where they are: the climb puts them back on
-- their checkpoint.
local lastMove: { [Player]: number } = {}
local function placeOf(player: Player): string
	if player:GetAttribute("InChalk") == true then return "chalk" end
	if player:GetAttribute("InClimb") == true then return "climb" end
	return if player:GetAttribute("InGame") == true then "rough" else "lobby"
end
local function placeFor(player: Player): (CFrame, SpawnLocation)
	local place = placeOf(player)
	if place == "climb" then return climbGame.standFrame(), climbGame.built.spawn end
	if place == "chalk" then return chalkGame.standFrame(), chalkGame.built.spawn end
	local target = if place == "rough" then spawn else lobby.spawn
	return target.CFrame + Vector3.new(0, 4, 0), target
end
local function setPlace(player: Player, place: string)
	local from = placeOf(player)
	if from == place then return end
	if from == "rough" and holder == player and phase == "Holding" then
		notice(player, "You're holding the " .. Skin.words(settings.skin).gem .. "! Win or lose it first, then leave the game.")
		return
	end
	local now = os.clock()
	if now - (lastMove[player] or -math.huge) < 1 then return end
	lastMove[player] = now
	if from == "rough" and holder == player then
		-- The winner leaves during the win screen: the diamond stays behind
		-- (anchored and hidden until the next round) and their arm comes down.
		diamond.Anchored = true
		if holdWeld ~= nil then
			holdWeld:Destroy()
			holdWeld = nil
		end
		showDiamond(false)
		lowerArms()
		holder = nil
	end
	-- The attribute turning on goes first, so the player is never seen in neither game on the way.
	if place == "chalk" then player:SetAttribute("InChalk", true) end
	if place == "climb" then player:SetAttribute("InClimb", true) end
	if place == "rough" then player:SetAttribute("InGame", true) end
	if place ~= "chalk" then player:SetAttribute("InChalk", false) end
	if place ~= "climb" then player:SetAttribute("InClimb", false) end
	if place ~= "rough" then player:SetAttribute("InGame", false) end
	-- The game being left gives back the usual movement first, then the game
	-- being joined sets its own (going straight from one to the other).
	if from == "climb" and place ~= "climb" then climbGame.entered(player, false) end
	if from == "chalk" and place ~= "chalk" then chalkGame.entered(player, false) end
	if place == "climb" then climbGame.entered(player, true) end
	if place == "chalk" then chalkGame.entered(player, true) end
	local frame, target = placeFor(player)
	player.RespawnLocation = target
	local character = player.Character
	if character then
		character:PivotTo(frame)
	end
end
-- A new character starts at the lobby, the camp or the climb's checkpoint,
-- wherever the player is.
local function placeCharacter(player: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root == nil or not root:IsA("BasePart") then return end
	task.wait()
	if character.Parent == nil then return end
	local frame = placeFor(player)
	if (root.Position - frame.Position).Magnitude > 30 then
		character:PivotTo(frame)
	end
	climbGame.characterAdded(player, character)
	chalkGame.characterAdded(player, character)
end

local function applySetting(player: Player, action: string, value: any)
	-- The wins box and its +1 / -1 change the win counter on screen: Diamond
	-- Climb's or Chalkboard Count's own while the streamer is in that game.
	local place = placeOf(player)
	if (action == "setWins" or action == "addWins") and type(value) == "number" and value == value
		and (place == "climb" or place == "chalk") then
		local wins = if place == "climb" then climbGame.progress.wins else chalkGame.progress.wins
		local change = if action == "addWins" then math.floor(value) else math.clamp(math.floor(value), -999999, 999999) - wins
		if place == "climb" then climbGame.addWins(change) else chalkGame.addWins(change) end
		return
	end
	if action == "setWins" and type(value) == "number" then
		settings.wins = math.clamp(math.floor(value), -999999, 999999)
	elseif action == "addWins" and type(value) == "number" then
		settings.wins = math.clamp(settings.wins + math.floor(value), -999999, 999999)
	elseif action == "setTitle" and type(value) == "string" then
		local clean = filtered(player, string.sub(value, 1, 24))
		if clean == nil then
			return
		end
		settings.title = clean
	elseif action == "setGoal" and type(value) == "number" then
		settings.goal = math.clamp(math.floor(value), 0, 999999)
	elseif (action == "setTextColor" or action == "setBackgroundColor") and type(value) == "string" then
		if Format.parseHex(value) == nil then
			return
		end
		local hex = "#" .. string.upper((string.gsub(value, "[^%x]", "")))
		if action == "setTextColor" then
			settings.textColor = hex
		else
			settings.backgroundColor = hex
		end
	elseif action == "setShowWins" and type(value) == "boolean" then
		settings.showWins = value
	elseif action == "setStartingStone" and type(value) == "number" then
		settings.startingStone = math.clamp(math.floor(value), 100, 1500000)
	elseif (action == "setPerCoin" or action == "setPerLike" or action == "setPerFollow" or action == "setPerShare") and type(value) == "number" then
		local field = ({ setPerCoin = "perCoin", setPerLike = "perLike", setPerFollow = "perFollow", setPerShare = "perShare" })[action]
		settings[field] = math.clamp(math.floor(value), 0, 1500000)
	elseif action == "resetBest" then
		settings.best = 0
	elseif action == "placeStatue" and type(value) == "table" then
		placeStatue(player, value)
		return
	elseif action == "removeStatue" and type(value) == "number" then
		removeStatue(player, math.floor(value))
		return
	elseif action == "removeNearestStatue" then
		removeNearestStatue(player)
		return
	elseif action == "removeAllStatues" then
		if #settings.statues == 0 then
			notice(player, "There are no statues to remove.")
			return
		end
		table.clear(settings.statues)
		buildStatues()
		saveSettings()
		notice(player, "All statues removed.")
		return
	elseif action == "resetBoard" and (value == "helpers" or value == "griefers") then
		if value == "helpers" then helperTally.reset() else grieferTally.reset() end
		boardsDirty = true
		lastBoardSave = 0
		scheduleBoards()
		return
	elseif action == "previewBoards" then
		-- Sample names for 20 seconds, so the boards can be checked before going live.
		previewUntil = os.clock() + 20
		scheduleBoards()
		task.delay(20.5, scheduleBoards)
		return
	elseif action == "newRound" then
		if phase ~= "Won" then
			newRound()
		end
		return
	elseif action == "testRebuildGift" and type(value) == "number" then
		-- Admin-only presets bypass saved destructive rules without changing them.
		-- Each carries the coins of one adding-effect tier, smallest to biggest.
		local coins = REBUILD_TEST_COINS[value]
		if coins == nil then return end
		testGift(coins, 1, "Rebuild test", -value)
		return
	elseif action == "climbRestart" then
		climbGame.restart()
		return
	elseif action == "setClimbStrength" and type(value) == "number" then
		climbGame.setStrength(value)
		return
	elseif action == "setClimbWall" and type(value) == "number" then
		-- The wall's health (Y panel): a whole new wall that strong.
		climbGame.setWallMax(value)
		return
	elseif action == "spawnBird" then
		diamondBird.spawn()
		return
	elseif action == "setTheme" and type(value) == "string" then
		setTheme(value)
		return
	elseif action == "setSkin" and type(value) == "string" then
		setSkin(value)
		return
	elseif action == "setGiftSettings" and type(value) == "table" then
		-- The full-screen gift settings: one gift's rules for each game and its key.
		local problem = GiftSettings.apply(settings, value, { rough = 1500000, climb = ClimbPath.TOP, chalk = ChalkBoard.GOAL.max, wins = 1000 })
		if problem then
			notice(player, problem)
			return
		end
		notice(player, "Saved " .. string.sub(tostring(value.gift), 1, 40) .. ".")
	elseif action == "removeCustomGift" and type(value) == "string" then
		GiftSettings.remove(settings, value)
	elseif action == "testGift" and type(value) == "table" then
		local coins = if type(value.coins) == "number" then math.clamp(value.coins, 1, 100000) else 1
		local count = if type(value.count) == "number" then math.clamp(math.floor(value.count), 1, 100) else 1
		-- A gift keybind (pressed by TikFinity when the gift arrives) is a real
		-- gift from the LIVE, so the feed says so rather than "Test".
		testGift(coins, count, if type(value.name) == "string" then string.sub(value.name, 1, 40) else "Test gift", nil, if value.keybind == true then "A viewer" else nil)
		return
	else
		return
	end
	saveSettings()
end

Request.OnServerEvent:Connect(function(player: Player, action: any, value: any)
	if type(action) ~= "string" then
		return
	end
	if action == "mine" then
		-- Sent each time a digging hand lands (four times a second while the
		-- dig button is held): dig as many rocks as DigPerSecond allows for the
		-- time since the last dig, rounded so strikes on time get their full share.
		-- The client names the rock cell it is aiming at (rock parts are local).
		-- Digging carries on while a gift blasts or rebuilds the mountain.
		local current = mountain
		if current == nil or phase == "Won" or phase == "Rebuilding" or holder == player
			or type(value) ~= "number" or value ~= math.floor(value) or value < 0 or value >= 2 ^ 32 then
			return
		end
		local now = os.clock()
		local since = now - (mineCooldown[player] or 0)
		-- Up to two strikes' worth, so a strike that arrives late (network
		-- jitter) makes up for the one before it that came early.
		local allowed = math.min(math.floor(since * Config.DigPerSecond + 0.5), math.ceil(Config.DigPerSecond / 4) * 2)
		if allowed < 1 then
			return
		end
		local key: number = value
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root == nil or not root:IsA("BasePart") or not current:isExposed(key) then
			return
		end
		local at = current:keyPosition(key)
		-- The client allows 16 studs; the server sees the player a moment late.
		if (root.Position - at).Magnitude > 20 then
			return
		end
		mineCooldown[player] = now
		if current:dig(key, allowed) > 0 then
			-- During a gift its own updates (every 0.05 s) carry the dig too.
			if not stoneBusy then flushMountain("dig", at) end
			refreshStone()
			settleDiamond()
		end
		return
	end
	if action == "mountainReady" then
		-- Sent by each client when its renderer is listening (and repeated until
		-- a snapshot arrives): it gets the whole mountain now and every change
		-- after it. During a rebuild the new round's snapshot follows shortly.
		local now = os.clock()
		if now - (readyAt[player] or -math.huge) < 2 then return end
		readyAt[player] = now
		synced[player] = true
		local current = mountain
		if current then
			sendMessages(current:snapshot(false), player)
		end
		return
	end
	if action == "joinGame" then
		setPlace(player, if value == "DiamondClimb" then "climb" elseif value == "Chalkboard" then "chalk" else "rough")
		return
	elseif action == "leaveGame" then
		setPlace(player, "lobby")
		return
	end
	if action == "climbLand" then
		-- Sent by a climber's game each time they land on a new platform.
		climbGame.land(player, value)
		return
	elseif action == "setClimbMove" then
		-- The climb's speed and jump sliders.
		climbGame.setMove(player, value)
		return
	elseif action == "chalkHold" then
		-- The writer pressed or let go of the write button.
		chalkGame.hold(player, value)
		return
	end
	if action == "setHideCard" and type(value) == "table" and type(value.hidden) == "boolean" then
		-- Settings: hide Diamond Climb's speed and jump card, or Chalkboard
		-- Count's writing speed card. Remembered for next time.
		local cards = { climb = { "hiddenClimbCard", "HideClimbCard" }, chalk = { "hiddenChalkCard", "HideChalkCard" } }
		local card = cards[value.card]
		if card == nil then return end
		local now = os.clock()
		if now - (hideAt[player] or -math.huge) < 0.2 then return end
		hideAt[player] = now
		player:SetAttribute(card[2], value.hidden)
		local list = settings[card[1]]
		local id = tostring(player.UserId)
		if (list[id] == true) ~= value.hidden then
			local count = 0
			for _ in list do count += 1 end
			if value.hidden and count >= 500 then return end
			list[id] = if value.hidden then true else nil
			Store.save(settings)
		end
		return
	end
	if action == "setHideButtons" then
		-- Any player can tuck away the GAMES tab and SETTINGS button (their
		-- keys still work); it is remembered for next time.
		if type(value) ~= "boolean" then return end
		local now = os.clock()
		if now - (hideAt[player] or -math.huge) < 0.2 then return end
		hideAt[player] = now
		player:SetAttribute("HideButtons", value)
		local id = tostring(player.UserId)
		if (settings.hiddenButtons[id] == true) ~= value then
			local count = 0
			for _ in settings.hiddenButtons do count += 1 end
			if value and count >= 500 then return end
			settings.hiddenButtons[id] = if value then true else nil
			Store.save(settings)
		end
		return
	end
	if action == "catchBird" then
		-- A click aimed at the bird this player sees (see the client's aim).
		local now = os.clock()
		if now - (catchAt[player] or -math.huge) < 0.25 then return end
		catchAt[player] = now
		diamondBird.catch(player)
		return
	end
	if admins[player] then
		if chalkGame.setting(player, action, value) then return end
		applySetting(player, action, value)
	end
end)

-- Chat commands for admins, e.g. "/wins 5", "/wins +1", "/title MY WINS".
local function onChat(player: Player, message: string)
	if not admins[player] then
		return
	end
	local command, args = string.match(message, "^/(%a+)%s*(.*)$")
	if command == nil then
		return
	end
	local rest: string = args or ""
	command = string.lower(command)
	local number = tonumber(rest)
	if command == "wins" and number ~= nil then
		if string.sub(rest, 1, 1) == "+" or string.sub(rest, 1, 1) == "-" then
			applySetting(player, "addWins", number)
		else
			applySetting(player, "setWins", number)
		end
	elseif command == "title" then
		applySetting(player, "setTitle", rest)
	elseif command == "goal" and number ~= nil then
		applySetting(player, "setGoal", number)
	elseif command == "stone" and number ~= nil then
		applySetting(player, "setStartingStone", number)
	elseif command == "newround" then
		applySetting(player, "newRound", nil)
	elseif command == "gift" then
		local coins, count = string.match(rest, "^(%d+)%s*(%d*)$")
		if coins ~= nil then
			applySetting(player, "testGift", { coins = tonumber(coins), count = tonumber(count) or 1, name = "Test gift" })
		end
	end
end

-- The modern chat swallows unknown "/" commands, so register them there; the
-- legacy chat delivers them through Player.Chatted instead.
local modernChat = TextChatService.ChatVersion == Enum.ChatVersion.TextChatService
if modernChat then
	local commands = Instance.new("Folder")
	commands.Name = "DiamondRushCommands"
	for _, name in { "wins", "title", "goal", "stone", "newround", "gift" } do
		local command = Instance.new("TextChatCommand")
		command.Name = "DiamondRush_" .. name
		command.PrimaryAlias = "/" .. name
		command.Triggered:Connect(function(source: TextSource, text: string)
			local player = Players:GetPlayerByUserId(source.UserId)
			if player ~= nil then
				onChat(player, text)
			end
		end)
		command.Parent = commands
	end
	commands.Parent = TextChatService
end

local function onPlayer(player: Player)
	player:SetAttribute("InGame", false)
	player:SetAttribute("InClimb", false)
	player:SetAttribute("InChalk", false)
	player.RespawnLocation = lobby.spawn
	player.CharacterAdded:Connect(function(character)
		placeCharacter(player, character)
	end)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character and not (humanoid and humanoid.Health <= 0) then
		task.spawn(placeCharacter, player, character)
	elseif not Players.CharacterAutoLoads then
		-- Joined while the world was being built (or died in the empty sky
		-- then): Roblox won't spawn them, so they spawn now, in the lobby.
		-- Later joiners are spawned by Roblox itself.
		task.spawn(function() if player.Parent then player:LoadCharacter() end end)
	end
	admins[player] = isAdmin(player)
	player:SetAttribute("DiamondRushAdmin", admins[player])
	player:SetAttribute("HideButtons", settings.hiddenButtons[tostring(player.UserId)] == true)
	player:SetAttribute("HideClimbCard", settings.hiddenClimbCard[tostring(player.UserId)] == true)
	player:SetAttribute("HideChalkCard", settings.hiddenChalkCard[tostring(player.UserId)] == true)
	if not modernChat then
		player.Chatted:Connect(function(message)
			onChat(player, message)
		end)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayer, player)
end
-- From now on Roblox respawns characters as usual.
Players.CharacterAutoLoads = true
Players.PlayerRemoving:Connect(function(player)
	admins[player] = nil
	lastMove[player] = nil
	mineCooldown[player] = nil
	synced[player] = nil
	readyAt[player] = nil
	catchAt[player] = nil
	hideAt[player] = nil
	climbGame.removing(player)
	chalkGame.removing(player)
end)

publishSettings()
newRound()
