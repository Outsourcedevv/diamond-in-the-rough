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
	giftBindings = {} :: { [string]: any },
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
	State:SetAttribute("GiftBindings", game:GetService("HttpService"):JSONEncode(settings.giftBindings))
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
local DiamondShape = require(Shared:WaitForChild("DiamondShape"))
local diamond = Instance.new("Part")
diamond.Name = "Diamond"
-- The diamond is the same size as a rock.
diamond.Size = Vector3.new(blockSize, blockSize, blockSize) * 0.85
diamond.Material = Enum.Material.Glass
diamond.Color = Color3.fromRGB(175, 240, 255)
diamond.Reflectance = 0.35
diamond.Anchored = true
diamond.CanCollide = false
diamond.CanTouch = false
diamond.CanQuery = false
diamond.Parent = workspace
DiamondShape.attach(diamond)
local glow = Instance.new("PointLight")
glow.Color = Color3.fromRGB(140, 230, 255)
glow.Range = 4
glow.Brightness = 0.6
glow.Parent = diamond
local PICKUP_DISTANCE = 12
local click = Instance.new("ClickDetector")
click.Name = "ClickToPickUp"
click.MaxActivationDistance = 0
click.Parent = diamond

local DIAMOND_TILT = CFrame.Angles(0, math.rad(22.5), 0)

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
end

local function showDiamond(visible: boolean)
	DiamondShape.visible(diamond, visible)
	diamond.CanQuery = visible and phase == "Revealed"
	-- No through-rock outline, beacon or floating location label while searching.
	glow.Enabled = visible and phase == "Holding"
	click.MaxActivationDistance = if visible and phase == "Revealed" then PICKUP_DISTANCE else 0
end

-- Use the actual stone/terrain surface, including the enlarged rock facets.
-- The grid's cell height can put a tilted diamond inside the visible stone.
local function diamondLanding(where: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { diamond }
	for _, player in Players:GetPlayers() do
		if player.Character then table.insert(ignore, player.Character) end
	end
	params.FilterDescendantsInstances = ignore
	local origin = Vector3.new(where.X, math.max(where.Y + blockSize * 2, 2), where.Z)
	local hit = workspace:Raycast(origin, Vector3.new(0, -2000, 0), params)
	-- Bounding sphere covers every corner of the rotated gem, plus a small gap.
	local clearance = diamond.Size.Magnitude / 2 + 0.04
	local surface = if hit then math.max(0, hit.Position.Y) else 0
	return Vector3.new(where.X, surface + clearance, where.Z)
end

local function settleDiamond()
	if phase ~= "Revealed" or mountain == nil or not diamond.Anchored then return end
	local landing = diamondLanding(diamond.Position)
	if math.abs(landing.Y - diamond.Position.Y) > 0.02 then
		stopSettling()
		settling = TweenService:Create(diamond, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(landing) * DIAMOND_TILT,
		})
		settling:Play()
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
local function applyStone(amount: number): (Vector3?, number?)
	amount = math.floor(amount)
	if amount == 0 then return nil, 0 end
	local current = mountain
	if phase == "Won" or phase == "Rebuilding" or current == nil then
		-- Gifts during the win screen count towards the next mountain.
		table.insert(pendingChanges, amount)
		return
	end
	if amount < 0 then
		local restored, samples = current:restore(-amount)
		refreshStone()
		if phase == "Revealed" then
			stopSettling()
			diamond.CFrame = CFrame.new(diamondLanding(Vector3.new(diamond.Position.X, current.grid.height * blockSize * 2 + 8, diamond.Position.Z))) * DIAMOND_TILT
		end
		Notify:FireAllClients("restore", { stones = samples, count = restored })
		return (if #samples > 0 then samples[1].frame.Position else nil), -restored
	end
	local count = math.min(amount, current:remaining())
	local centre = current:blast(count)
	-- Gift spectacle is rendered by GiftEffects on each client. Never create a
	-- physics Explosion: blasts may remove grid stones, never the diamond or rigs.
	refreshStone()
	settleDiamond()
	return centre, count
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

local rebuilding = false
local function newRound(animated: boolean?)
	if rebuilding then return end
	rebuilding = true
	setPhase("Rebuilding")
	showDiamond(false)
	stopSettling()
	if mountain ~= nil then
		mountain:destroy()
	end
	holder = nil
	lowerArms()
	if holdWeld ~= nil then
		holdWeld:Destroy()
		holdWeld = nil
	end
	for _, player in Players:GetPlayers() do
		teleportHome(player)
	end
	startingStone = math.clamp(settings.startingStone, 100, 1500000)
	local created = Mountain.new(workspace, startingStone, blockSize, reveal, animated == true)
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
	if animated then
		local layers = {}
		local samples = {}
		for _, part in created.parts do
			local layer = math.clamp(math.floor(part.Position.Y / (created.grid.height * blockSize) * 16) + 1, 1, 16)
			layers[layer] = layers[layer] or {}
			table.insert(layers[layer], part)
		end
		for layer = 1, 16 do
			local bucket = layers[layer] or {}
			local taken = 0
			for _, part in bucket do
				if not part:GetAttribute("BackingRock") then
					table.insert(samples, { frame = part.CFrame, size = part.Size, colour = part.Color, layer = layer })
					taken += 1
					if taken >= 5 then break end
				end
			end
		end
		local start = workspace:GetServerTimeNow() + 0.5
		Notify:FireAllClients("rebuild", { stones = samples, start = start })
		task.wait(0.5)
		for layer = 1, 16 do
			task.wait(0.15)
			for _, part in layers[layer] or {} do part.Transparency = 0 end
		end
		created.folder:SetAttribute("Building", false)
	end
	rebuilding = false
	setPhase("Digging")
	roundStart = workspace:GetServerTimeNow()
	State:SetAttribute("RoundStart", roundStart)
	local carried = pendingChanges
	pendingChanges = {}
	for _, change in carried do applyStone(change) end
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
	-- ClickDetector events can be forged: range and an unobstructed sightline
	-- are checked again on the server before claiming the single diamond.
	local direction = diamond.Position - head.Position
	if direction.Magnitude > PICKUP_DISTANCE then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character :: Model }
	local hit = workspace:Raycast(head.Position, direction, params)
	if hit == nil or hit.Instance ~= diamond then
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
	local offset = if grip == head then CFrame.new(0.8, 1.4, -0.6) else CFrame.new(0, -grip.Size.Y / 2 - blockSize * 0.25, -0.08)
	diamond.CFrame = grip.CFrame * offset * DIAMOND_TILT
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = grip
	weld.Part1 = diamond
	weld.Parent = diamond
	holdWeld = weld
	raiseArms(character :: Model)
	Notify:FireAllClients("grabbed", player.DisplayName)
end

local function drop(reason: string)
	if phase ~= "Holding" then
		return
	end
	stopSettling()
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
	diamond.CFrame = CFrame.new(diamondLanding(where)) * DIAMOND_TILT
	setPhase("Revealed")
	showDiamond(true)
	State:SetAttribute("Holder", "")
	State:SetAttribute("HolderUserId", 0)
	State:SetAttribute("HoldStart", 0)
	Notify:FireAllClients("dropped", { name = if lost then lost.DisplayName else "", reason = reason })
end

local function win(player: Player)
	setPhase("Won")
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

-- TikTok ------------------------------------------------------------------------
local function onTikTok(event: TikTokFeed.Event)
	if event.type == "giftRule" and event.gift and event.rocks ~= nil then
		local name = string.lower(event.gift)
		settings.giftRules[name] = math.clamp(math.floor(event.rocks), -1500000, 1500000)
		for key, binding in settings.giftBindings do
			if string.lower(binding.gift) == name then settings.giftBindings[key] = nil end
		end
		if event.keybind and event.keybind ~= "" then
			settings.giftBindings[event.keybind] = { gift = event.gift, coins = event.coins or 1 }
		end
		saveSettings()
		return
	end
	local who = event.name or event.user or "Someone"
	local amount = 0
	local text = ""
	if event.type == "gift" then
		local count = math.max(1, math.floor(event.count or 1))
		local coins = math.max(1, event.coins or 1)
		local rule = if event.rocks ~= nil then event.rocks else settings.giftRules[string.lower(event.gift or "")]
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
	if amount <= 0 and event.type ~= "gift" then return end
	local centre, applied = applyStone(amount)
	if event.type == "gift" then
		Notify:FireAllClients("giftEffect", {
			coins = math.max(1, event.coins or 1) * math.max(1, math.floor(event.count or 1)),
			position = centre or Vector3.new(0, 8, 0),
			name = who,
			gift = event.gift or "Gift",
			adding = amount < 0,
			blocks = applied,
		})
	end
	Notify:FireAllClients("feed", { text = text .. (if applied == nil then " (queued)" elseif amount < 0 and applied == 0 then " (mountain full)" else ""), stone = applied or amount, kind = event.type })
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

local function testGift(coins: number, count: number, name: string, rocks: number?)
	onTikTok({
		id = "test-" .. tostring(os.clock()),
		type = "gift",
		name = "Test",
		gift = name,
		rocks = rocks,
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
			settings.giftRules[name] = math.clamp(math.floor(value.rocks), -1500000, 1500000)
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
	elseif action == "testRebuildGift" and type(value) == "number" then
		-- Admin-only presets bypass saved destructive rules without changing them.
		if value ~= 1000 and value ~= 10000 and value ~= 100000 and value ~= 1500000 then return end
		testGift(1, 1, "Rebuild test", -value)
		return
	elseif action == "testGift" and type(value) == "table" then
		local coins = if type(value.coins) == "number" then math.clamp(value.coins, 1, 100000) else 1
		local count = if type(value.count) == "number" then math.clamp(math.floor(value.count), 1, 100) else 1
		testGift(coins, count, if type(value.name) == "string" then string.sub(value.name, 1, 40) else "Test gift")
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
		if current == nil or phase == "Won" or phase == "Rebuilding" or holder == player or typeof(value) ~= "Instance" or value == diamond then
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
