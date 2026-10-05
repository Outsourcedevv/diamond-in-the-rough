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
-- Mountain snapshots and change lists travel in order on one remote; every
-- client draws its own rock from them (see Mountain and MountainView).
local MountainSync = Instance.new("RemoteEvent")
MountainSync.Name = "MountainSync"
MountainSync.Parent = Remotes
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
	-- Leaderboard totals per TikTok viewer, and gold statues placed by the streamer.
	leaderboards = { gifts = {}, likes = {} } :: { gifts: { any }, likes: { any } },
	statues = {} :: { any },
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
	if type(settings.leaderboards.gifts) ~= "table" or type(settings.leaderboards.likes) ~= "table" then
		settings.leaderboards = { gifts = {}, likes = {} }
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
	State:SetAttribute("GiftBindings", game:GetService("HttpService"):JSONEncode(settings.giftBindings))
	local statueList = {}
	for _, statue in settings.statues do table.insert(statueList, { name = statue.n, coins = statue.c }) end
	State:SetAttribute("Statues", game:GetService("HttpService"):JSONEncode(statueList))
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
spawn.Parent = workspace

-- Leaderboards stand behind the mountain; the scenery keeps their ground clear.
local Leaderboards = require(script.Leaderboards)
local mountainRadius = spawnDistance - 30
local arenaRadius = math.max(mountainRadius + 14, 55)
local boardSpots = Leaderboards.spots(arenaRadius, mountainRadius, spawn.Position)
local reserved = {}
for _, spot in boardSpots do table.insert(reserved, { at = spot.at, radius = 30 }) end

-- Hills, distant peaks, a lake, a pine forest, boulders and a campfire.
require(script.Scenery).build(mountainRadius, spawn.Position, reserved)

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
local stoneBusy = false
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
-- rate. Changes stream to clients while the work continues.
local function workCheckpoint(onYield: (() -> ())?, effect: string?, budget: number?): () -> ()
	local frameStart = os.clock()
	local lastCountUpdate = frameStart
	local slice = budget or 0.003
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
		local restored, at = current:restore(-amount, capacity, checkpoint)
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
	local centre = current:blast(count, workCheckpoint(nil, "blast"), centreKey)
	flushMountain("blast", centre)
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
	local carried = pendingChanges
	pendingChanges = {}
	stoneBusy = true
	for _, change in carried do applyStone(change) end
	stoneBusy = false
end

-- Holding the diamond -----------------------------------------------------------
local function grab(player: Player)
	if stoneBusy or phase ~= "Revealed" then
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
interruptRebuildHold = function(restored: number, interrupted: Player?)
	local current = mountain
	if current == nil then return end
	-- The former holder goes to the highest restored surface after a big rebuild.
	local summit = if interrupted and restored >= 10000 then current:summit() else nil
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if character == nil or root == nil or not root:IsA("BasePart") or humanoid == nil or humanoid.Health <= 0 then continue end
		local clearance = humanoid.HipHeight + root.Size.Y / 2
		-- R6 rigs use zero HipHeight; account for their legs.
		if humanoid.RigType == Enum.HumanoidRigType.R6 then clearance += 2 end
		local destination = if player == interrupted then summit else nil
		if destination == nil then
			-- Lift players whose body is now inside restored rock onto its surface.
			local feet = root.Position.Y - clearance
			local top = current:coveredTop(root.Position, feet + 0.15, root.Position.Y + 1.5)
			if top then destination = Vector3.new(root.Position.X, top, root.Position.Z) end
		end
		if destination then
			local target = destination + Vector3.new(0, clearance + 1, 0)
			character:PivotTo(character:GetPivot() + (target - root.Position))
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end

	end
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
local giftBoard = Leaderboards.build(showcase, boardSpots[1].at, boardSpots[1].facing, boardLift, {
	title = "🎁 TOP GIFTERS",
	unit = "coins",
	trim = Color3.fromRGB(36, 92, 204),
	valueColour = Color3.fromRGB(255, 214, 120),
	emblem = "gift",
	empty = "Send a gift to get on the board!",
}, groundAt)
local likeBoard = Leaderboards.build(showcase, boardSpots[2].at, boardSpots[2].facing, boardLift, {
	title = "❤️ TOP LIKERS",
	unit = "likes",
	trim = Color3.fromRGB(196, 36, 44),
	valueColour = Color3.fromRGB(255, 178, 188),
	emblem = "heart",
	empty = "Tap the screen to like the live!",
}, groundAt)
local giftTally = Leaderboards.tally(settings.leaderboards.gifts)
local likeTally = Leaderboards.tally(settings.leaderboards.likes)
local SAMPLE_GIFTS: { { any } } = { { "DiamondDave", 34999 }, { "LunaStreams", 12500 }, { "rocky_road", 5000 }, { "GemHunter99", 2999 }, { "Pixel Pam", 1000 },
	{ "tiktok_tom", 520 }, { "MinerMia", 300 }, { "Sir Digs-a-Lot", 150 }, { "glitterbug", 99 }, { "rose_rain", 30 } }
local SAMPLE_LIKES: { { any } } = { { "TapQueen", 48210 }, { "likeitlikeit", 23005 }, { "Pebble", 15400 }, { "Mo", 9870 }, { "skyler.digs", 6120 },
	{ "heart_spammer", 4400 }, { "Ava", 2950 }, { "quarry_kid", 1200 }, { "bubbles", 640 }, { "newviewer22", 75 } }

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
	draw(giftBoard, giftTally, SAMPLE_GIFTS)
	draw(likeBoard, likeTally, SAMPLE_LIKES)
	settings.leaderboards = { gifts = giftTally.serialize(100), likes = likeTally.serialize(100) }
	if boardsDirty and os.clock() - lastBoardSave >= 20 then
		boardsDirty = false
		lastBoardSave = os.clock()
		saveSettings()
	end
end
-- Coalesces bursts of likes and gifts into one refresh a second.
local function scheduleBoards()
	if boardsScheduled then return end
	boardsScheduled = true
	task.delay(1, refreshBoards)
end
local function recordViewer(event: TikTokFeed.Event, kind: string, amount: number)
	-- Test gifts and likes (from the settings panel or the bridge page) never count.
	if event.user == "tester" or string.sub(event.id, 1, 5) == "test-" then return end
	local key = string.lower(event.user or event.name or "")
	local name = event.name or event.user or "Viewer"
	if kind == "gift" then giftTally.add(key, name, amount) else likeTally.add(key, name, amount) end
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

-- TikTok ------------------------------------------------------------------------
local function processTikTok(event: TikTokFeed.Event)
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
		recordViewer(event, "gift", coins * count)
	elseif event.type == "like" then
		local likes = math.max(1, math.floor(event.likes or 1))
		amount = likes * settings.perLike
		text = string.format("%s liked x%d", who, likes)
		recordViewer(event, "like", likes)
	elseif event.type == "follow" then
		amount = settings.perFollow
		text = who .. " followed"
	elseif event.type == "share" then
		amount = settings.perShare
		text = who .. " shared the live"
	end
	if amount <= 0 and event.type ~= "gift" then return end
	local current = mountain
	local centreKey = if current then current.grid:randomExposed() else nil
	local preview = if current and centreKey then current:keyPosition(centreKey) else Vector3.new(0, 8, 0)
	local available = if current then current:remaining() else 0
	local blocks = if phase == "Won" or phase == "Rebuilding" then nil elseif amount < 0 then -math.min(-amount, math.max(0, growthCapacity() - available)) else math.min(amount, available)
	-- Start the animation promptly while the queued rock work spans frames.
	if event.type == "gift" then
		Notify:FireAllClients("giftEffect", {
			coins = math.max(1, event.coins or 1) * math.max(1, math.floor(event.count or 1)),
			position = preview,
			name = who,
			gift = event.gift or "Gift",
			adding = amount < 0,
			blocks = if amount < 0 then nil else blocks,
		})
	end
	local _centre, applied = applyStone(amount, centreKey)
	Notify:FireAllClients("feed", { text = text .. (if applied == nil then " (queued)" elseif amount < 0 and applied == 0 then " (mountain full)" else ""), stone = applied or amount, kind = event.type })
end

-- One yielding worker owns all gift mutations; polling stays responsive and
-- overlapping live/test events cannot corrupt the grid or overtake each other.
local giftQueue: { TikTokFeed.Event } = {}
local giftHead = 1
local giftWorkerRunning = false
local function onTikTok(event: TikTokFeed.Event)
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
			stoneBusy = false
			if not ok then warn("[DiamondRush] gift failed: " .. tostring(problem)) end
			if requestedRound ~= nil then
				local animated = requestedRound
				requestedRound = nil
				newRound(animated)
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
	elseif action == "resetBoard" and (value == "gifts" or value == "likes") then
		if value == "gifts" then giftTally.reset() else likeTally.reset() end
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
		-- The client names the rock cell it is aiming at (rock parts are local).
		local current = mountain
		if stoneBusy or current == nil or phase == "Won" or phase == "Rebuilding" or holder == player
			or type(value) ~= "number" or value ~= math.floor(value) or value < 0 or value >= 2 ^ 32 then
			return
		end
		local now = os.clock()
		local since = now - (mineCooldown[player] or 0)
		local allowed = math.min(math.floor(since * Config.DigPerSecond), math.ceil(Config.DigPerSecond / 4))
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
		if (root.Position - at).Magnitude > 16 then
			return
		end
		mineCooldown[player] = now
		if current:dig(key, allowed) > 0 then
			flushMountain("dig", at)
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
	synced[player] = nil
	readyAt[player] = nil
end)

publishSettings()
State:SetAttribute("TikTok", "Startingâ€¦")
newRound()
