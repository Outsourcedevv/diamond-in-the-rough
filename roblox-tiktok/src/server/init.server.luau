--!strict
-- DIAMOND RUSH: a TikTok Live mountain. Gifts, likes, follows and shares blast
-- stone out of the mountain; whoever grabs the hidden diamond and holds it for
-- 15 seconds wins the round.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPack = game:GetService("StarterPack")
local TextService = game:GetService("TextService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("DiamondRush")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Mountain = require(script.Mountain)
local TikTokFeed = require(script.TikTokFeed)
local Store = require(script.Store)

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
Remotes.Parent = ReplicatedStorage

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
}
local saved = Store.load()
if saved then
	for key, value in saved do
		if settings[key] ~= nil and type(value) == type(settings[key]) then
			settings[key] = value
		end
	end
	local rules: { [string]: number } = {}
	for name, rocks in settings.giftRules do
		if type(name) == "string" and type(rocks) == "number" then
			rules[string.lower(name)] = rocks
		end
	end
	settings.giftRules = rules
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
spawn.Color = Color3.fromRGB(150, 110, 70)
spawn.Parent = workspace

-- Hills, distant peaks, a lake, a pine forest, boulders and a campfire.
require(script.Scenery).build(spawnDistance - 30, spawn.Position)

Lighting.ClockTime = 14.5
Lighting.Brightness = 2.2
Lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 150)
if Lighting:FindFirstChildOfClass("Atmosphere") == nil then
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.25
	atmosphere.Haze = 1.2
	atmosphere.Color = Color3.fromRGB(200, 215, 230)
	atmosphere.Parent = Lighting
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
local diamond = Instance.new("Part")
diamond.Name = "Diamond"
-- The diamond is the same size as a rock.
diamond.Size = Vector3.new(blockSize, blockSize, blockSize) * 0.85
diamond.Material = Enum.Material.Glass
diamond.Color = Color3.fromRGB(175, 240, 255)
diamond.Reflectance = 0.35
diamond.Anchored = true
diamond.CanCollide = false
diamond.Parent = workspace
local glow = Instance.new("PointLight")
glow.Color = Color3.fromRGB(140, 230, 255)
glow.Range = 16
glow.Brightness = 3
glow.Parent = diamond
local sparkles = Instance.new("Sparkles")
sparkles.SparkleColor = Color3.fromRGB(200, 250, 255)
sparkles.Parent = diamond
local highlight = Instance.new("Highlight")
highlight.FillColor = Color3.fromRGB(150, 240, 255)
highlight.FillTransparency = 0.55
highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
highlight.Parent = diamond
local prompt = Instance.new("ProximityPrompt")
prompt.ActionText = "Grab the diamond"
prompt.ObjectText = "Diamond"
prompt.HoldDuration = 0
prompt.MaxActivationDistance = 14
prompt.RequiresLineOfSight = false
prompt.Parent = diamond
local tag = Instance.new("BillboardGui")
tag.Size = UDim2.fromOffset(220, 50)
tag.StudsOffset = Vector3.new(0, 3.2, 0)
tag.AlwaysOnTop = true
tag.Parent = diamond
local tagText = Instance.new("TextLabel")
tagText.Size = UDim2.fromScale(1, 1)
tagText.BackgroundTransparency = 1
tagText.Font = Enum.Font.FredokaOne
tagText.TextScaled = true
tagText.TextColor3 = Color3.fromRGB(255, 255, 255)
tagText.TextStrokeTransparency = 0.2
tagText.Text = "💎 GRAB IT!"
tagText.Parent = tag

local DIAMOND_TILT = CFrame.Angles(math.rad(45), 0, math.rad(35))

-- Round state -------------------------------------------------------------------
local mountain: Mountain.Mountain? = nil
local phase = "Digging"
local startingStone = settings.startingStone
local pendingStone = 0
local roundStart = 0
local holder: Player? = nil
local holdStarted = 0
local holdWeld: WeldConstraint? = nil
local mineCooldown: { [Player]: number } = {}
local admins: { [Player]: boolean } = {}

local function setPhase(value: string)
	phase = value
	State:SetAttribute("Phase", value)
end

local function refreshStone()
	State:SetAttribute("Stone", if mountain then mountain:remaining() else 0)
	State:SetAttribute("StartingStone", startingStone)
end

local function showDiamond(visible: boolean)
	diamond.Transparency = if visible then 0.12 else 1
	diamond.CanTouch = visible
	glow.Enabled = visible
	sparkles.Enabled = visible
	highlight.Enabled = visible
	tag.Enabled = visible and phase == "Revealed"
	prompt.Enabled = visible and phase == "Revealed"
end

-- A loose diamond drops onto whatever rock (or ground) is left under it.
local function settleDiamond()
	if phase ~= "Revealed" or mountain == nil or not diamond.Anchored then
		return
	end
	local rest = mountain:restingHeight(diamond.Position) + blockSize / 2
	if rest < diamond.Position.Y - 0.1 then
		local target = CFrame.new(diamond.Position.X, rest, diamond.Position.Z) * DIAMOND_TILT
		TweenService:Create(diamond, TweenInfo.new(0.4, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), { CFrame = target }):Play()
	end
end

local function reveal()
	if phase ~= "Digging" then
		return
	end
	setPhase("Revealed")
	showDiamond(true)
	Notify:FireAllClients("revealed")
end

-- One rock is one stone: blast exactly that many rocks.
local function applyStone(amount: number)
	amount = math.floor(amount)
	if amount <= 0 then
		return
	end
	local current = mountain
	if phase == "Won" or current == nil then
		-- Gifts during the win screen count towards the next mountain.
		pendingStone += amount
		return
	end
	local count = math.min(amount, current:remaining())
	local centre = current:blast(count)
	if centre ~= nil and count >= 200 then
		local blast = Instance.new("Explosion")
		blast.Position = centre
		blast.BlastRadius = math.min(40, 2 + count ^ (1 / 3) * 1.6)
		blast.BlastPressure = 0
		blast.DestroyJointRadiusPercent = 0
		blast.ExplosionType = Enum.ExplosionType.NoCraters
		blast.Parent = workspace
	end
	refreshStone()
	settleDiamond()
end

local function teleportHome(player: Player)
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

local function newRound()
	if mountain ~= nil then
		mountain:destroy()
	end
	holder = nil
	lowerArms()
	if holdWeld ~= nil then
		holdWeld:Destroy()
		holdWeld = nil
	end
	startingStone = math.clamp(settings.startingStone, 100, 1500000)
	setPhase("Digging")
	local created = Mountain.new(workspace, startingStone, blockSize, reveal)
	mountain = created
	startingStone = created:total()
	diamond.Anchored = true
	diamond.CFrame = CFrame.new(created:keyPosition(created.diamondKey)) * DIAMOND_TILT
	showDiamond(false)
	roundStart = workspace:GetServerTimeNow()
	State:SetAttribute("RoundStart", roundStart)
	State:SetAttribute("Holder", "")
	State:SetAttribute("HoldStart", 0)
	refreshStone()
	for _, player in Players:GetPlayers() do
		teleportHome(player)
	end
	local carried = pendingStone
	pendingStone = 0
	applyStone(carried)
end

-- Holding the diamond -----------------------------------------------------------
local function grab(player: Player)
	if phase ~= "Revealed" then
		return
	end
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if head == nil or not head:IsA("BasePart") or humanoid == nil or humanoid.Health <= 0 then
		return
	end
	holder = player
	holdStarted = os.clock()
	setPhase("Holding")
	showDiamond(true)
	-- Held high above the head, like a trophy, so the stream can see it.
	diamond.Anchored = false
	diamond.Massless = true
	diamond.CanCollide = false
	-- Above the raised right hand.
	diamond.CFrame = head.CFrame * CFrame.new(1.4, 3.6, 0) * DIAMOND_TILT
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = diamond
	weld.Parent = diamond
	holdWeld = weld
	raiseArms(character :: Model)
	State:SetAttribute("Holder", player.DisplayName)
	State:SetAttribute("HoldStart", workspace:GetServerTimeNow())
	Notify:FireAllClients("grabbed", player.DisplayName)
end

local function drop(reason: string)
	if phase ~= "Holding" then
		return
	end
	local where = diamond.Position
	local lost = holder
	holder = nil
	lowerArms()
	if holdWeld ~= nil then
		holdWeld:Destroy()
		holdWeld = nil
	end
	diamond.Anchored = true
	diamond.AssemblyLinearVelocity = Vector3.zero
	local params = RaycastParams.new()
	local ignore: { Instance } = { diamond }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit = workspace:Raycast(where, Vector3.new(0, -400, 0), params)
	local y = if hit then hit.Position.Y + blockSize / 2 else blockSize / 2
	diamond.CFrame = CFrame.new(where.X, math.max(y, blockSize / 2), where.Z) * DIAMOND_TILT
	setPhase("Revealed")
	showDiamond(true)
	State:SetAttribute("Holder", "")
	State:SetAttribute("HoldStart", 0)
	Notify:FireAllClients("dropped", { name = if lost then lost.DisplayName else "", reason = reason })
end

local function win(player: Player)
	setPhase("Won")
	tag.Enabled = false
	prompt.Enabled = false
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
	task.delay(Config.WinScreenSeconds, newRound)
end

prompt.Triggered:Connect(grab)
diamond.Touched:Connect(function(hit)
	if phase ~= "Revealed" then
		return
	end
	local player = Players:GetPlayerFromCharacter(hit.Parent)
	if player ~= nil then
		grab(player)
	end
end)

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

-- TikTok ------------------------------------------------------------------------
local function onTikTok(event: TikTokFeed.Event)
	local who = event.name or event.user or "Someone"
	local amount = 0
	local text = ""
	if event.type == "gift" then
		local count = math.max(1, math.floor(event.count or 1))
		local coins = math.max(1, event.coins or 1)
		local rule = settings.giftRules[string.lower(event.gift or "")]
		amount = if rule ~= nil then rule * count else coins * count * settings.perCoin
		text = string.format("%s sent %s x%d", who, event.gift or "a gift", count)
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
	if amount <= 0 then
		return
	end
	applyStone(amount)
	Notify:FireAllClients("feed", { text = text, stone = amount, kind = event.type })
end

TikTokFeed.start(Config.BridgeUrls, Config.MessagingTopic, onTikTok, function(status: string)
	State:SetAttribute("TikTok", status)
end)

-- Pickaxe mining and settings ---------------------------------------------------------
local function isAdmin(player: Player): boolean
	if RunService:IsStudio() then
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

local function testGift(coins: number, count: number, name: string)
	onTikTok({
		id = "test-" .. tostring(os.clock()),
		type = "gift",
		name = "Test",
		gift = name,
		coins = coins,
		count = count,
	})
end

local function applySetting(player: Player, action: string, value: any)
	if action == "setWins" and type(value) == "number" then
		settings.wins = math.clamp(math.floor(value), 0, 999999)
	elseif action == "addWins" and type(value) == "number" then
		settings.wins = math.clamp(settings.wins + math.floor(value), 0, 999999)
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
	elseif action == "setGiftRule" and type(value) == "table" and type(value.gift) == "string" then
		local name = string.lower((string.gsub(string.sub(value.gift, 1, 40), "^%s*(.-)%s*$", "%1")))
		if name == "" then
			return
		end
		if type(value.rocks) == "number" then
			settings.giftRules[name] = math.clamp(math.floor(value.rocks), 0, 1500000)
		else
			settings.giftRules[name] = nil
		end
	elseif action == "resetBest" then
		settings.best = 0
	elseif action == "newRound" then
		if phase ~= "Won" then
			newRound()
		end
		return
	elseif action == "testGift" and type(value) == "table" then
		local coins = if type(value.coins) == "number" then math.clamp(value.coins, 1, 50000) else 1
		local count = if type(value.count) == "number" then math.clamp(math.floor(value.count), 1, 100) else 1
		testGift(coins, count, if type(value.name) == "string" then string.sub(value.name, 1, 24) else "Test gift")
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
		-- Sent every ~0.1 s while the dig button is held: dig as many rocks as
		-- DigPerSecond allows for the time since the last dig.
		local current = mountain
		if current == nil or phase == "Won" or typeof(value) ~= "Instance" then
			return
		end
		local now = os.clock()
		local since = now - (mineCooldown[player] or 0)
		local allowed = math.min(math.floor(since * Config.DigPerSecond), math.ceil(Config.DigPerSecond / 4))
		if allowed < 1 then
			return
		end
		local key = current:keyForPart(value)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if key == nil or root == nil or not root:IsA("BasePart") then
			return
		end
		if (root.Position - current:keyPosition(key)).Magnitude > 16 then
			return
		end
		mineCooldown[player] = now
		if current:dig(key, allowed) > 0 then
			refreshStone()
			settleDiamond()
		end
		return
	end
	if admins[player] then
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
	admins[player] = isAdmin(player)
	player:SetAttribute("DiamondRushAdmin", admins[player])
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
Players.PlayerRemoving:Connect(function(player)
	admins[player] = nil
	mineCooldown[player] = nil
end)

publishSettings()
State:SetAttribute("TikTok", "Starting…")
newRound()
