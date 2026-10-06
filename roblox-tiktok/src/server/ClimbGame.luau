--!strict
-- Diamond Climb, the second game in the games menu: jump up 1000 platforms
-- round a crystal tower to the diamond at the top. Every platform you land
-- on is a checkpoint (falling, or respawning, puts you back on it), and the
-- climber picks their own walk speed and jump height. TikTok gifts send the
-- climber up the tower (gifts that would break the mountain) or down it
-- (gifts that would add stone), more platforms for bigger gifts, each with
-- its own animation (see ClimbEffects). Reaching the top wins a climb and
-- starts the next one from the bottom.
--
-- The climb's progress is part of the saved settings (settings.climb) and is
-- shown to every player through the State attributes ClimbCheckpoint,
-- ClimbBest, ClimbWins, ClimbSpeed, ClimbJump and ClimbStrength. The game is
-- single player, so there is one climb: the streamer's.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Shared = ReplicatedStorage:WaitForChild("DiamondRush")
local ClimbPath = require(Shared:WaitForChild("ClimbPath"))
local Climb = require(script.Parent:WaitForChild("Climb"))

local ClimbGame = {}

export type Progress = { checkpoint: number, best: number, wins: number, speed: number, jump: number, strength: number }

-- Gift strength choices in the streamer panel: platforms per gift times this.
ClimbGame.STRENGTHS = { 0.5, 1, 2 }
-- Seconds after reaching the top before the next climb starts at the bottom.
ClimbGame.WIN_SECONDS = 8
-- How far ahead of the checkpoint a landing may be (a long jump down onto a
-- platform a turn below can skip a few; nothing honest skips more).
ClimbGame.MAX_SKIP = 20

function ClimbGame.defaults(): Progress
	return { checkpoint = 0, best = 0, wins = 0, speed = ClimbPath.SPEED.default, jump = ClimbPath.JUMP.default, strength = 1 }
end

-- A saved climb with anything missing or out of range put right.
function ClimbGame.clean(saved: any): Progress
	local progress = ClimbGame.defaults()
	if type(saved) ~= "table" then return progress end
	local function number(key: string, low: number, high: number, whole: boolean)
		local value = saved[key]
		if type(value) == "number" and value == value then
			value = math.clamp(value, low, high)
			progress[key] = if whole then math.floor(value) else value
		end
	end
	number("checkpoint", 0, ClimbPath.TOP, true)
	number("best", 0, ClimbPath.TOP, true)
	number("wins", 0, 999999, true)
	number("speed", ClimbPath.SPEED.min, ClimbPath.SPEED.max, false)
	number("jump", ClimbPath.JUMP.min, ClimbPath.JUMP.max, false)
	if table.find(ClimbGame.STRENGTHS, saved.strength) then progress.strength = saved.strength end
	progress.best = math.max(progress.best, progress.checkpoint)
	-- A climb saved at the top (the server stopped during the win) starts again.
	if progress.checkpoint >= ClimbPath.TOP then progress.checkpoint = 0 end
	return progress
end

-- Where a gift moves the climber: how many platforms, and up or down. `rocks`
-- is what the gift would do to the mountain (positive breaks it: up; negative
-- adds stone: down; nothing: stays). `coins` is one gift's coins.
function ClimbGame.giftMove(rocks: number, coins: number, count: number, strength: number): number
	if rocks == 0 then return 0 end
	local platforms = ClimbPath.giftPlatforms(coins, strength) * math.max(1, math.floor(count))
	return if rocks > 0 then platforms else -platforms
end

export type Options = {
	settings: any, -- the saved settings; the climb lives in settings.climb
	save: () -> (), -- remembers the settings (Store.save)
	state: Instance,
	notify: RemoteEvent,
	parent: Instance,
}

export type Game = {
	built: Climb.Built,
	progress: Progress,
	climbing: (player: Player) -> boolean,
	climber: () -> Player?,
	standFrame: () -> CFrame,
	entered: (player: Player, climbing: boolean) -> (),
	characterAdded: (player: Player, character: Model) -> (),
	land: (player: Player, index: any) -> (),
	setMove: (player: Player, value: any) -> (),
	setStrength: (value: any) -> boolean,
	restart: () -> (),
	gift: (who: string, move: number, info: { [string]: any }) -> (number, number),
	removing: (player: Player) -> (),
}

function ClimbGame.start(options: Options): Game
	local settings = options.settings
	local progress = ClimbGame.clean(settings.climb)
	settings.climb = progress
	local state = options.state
	local notify = options.notify
	local built = Climb.build(options.parent)
	local winning = false
	local landAt: { [Player]: number } = {}
	local moveAt: { [Player]: number } = {}

	local function publish()
		state:SetAttribute("ClimbCheckpoint", progress.checkpoint)
		state:SetAttribute("ClimbBest", progress.best)
		state:SetAttribute("ClimbWins", progress.wins)
		state:SetAttribute("ClimbSpeed", progress.speed)
		state:SetAttribute("ClimbJump", progress.jump)
		state:SetAttribute("ClimbStrength", progress.strength)
	end
	publish()

	local function climbing(player: Player): boolean
		return player:GetAttribute("InClimb") == true
	end

	local function climber(): Player?
		for _, player in game:GetService("Players"):GetPlayers() do
			if climbing(player) then return player end
		end
		return nil
	end

	local function humanoidOf(player: Player): Humanoid?
		local character = player.Character
		return if character then character:FindFirstChildOfClass("Humanoid") else nil
	end

	-- The climber's chosen speed and jump while climbing; Roblox's usual ones elsewhere.
	local function applyMove(player: Player)
		local humanoid = humanoidOf(player)
		if humanoid == nil then return end
		if climbing(player) then
			humanoid.UseJumpPower = false
			humanoid.WalkSpeed = progress.speed
			humanoid.JumpHeight = progress.jump
		else
			humanoid.UseJumpPower = StarterPlayer.CharacterUseJumpPower
			humanoid.WalkSpeed = StarterPlayer.CharacterWalkSpeed
			humanoid.JumpHeight = StarterPlayer.CharacterJumpHeight
			humanoid.JumpPower = StarterPlayer.CharacterJumpPower
		end
	end

	local function setCheckpoint(index: number)
		progress.checkpoint = math.clamp(math.floor(index), 0, ClimbPath.TOP)
		progress.best = math.max(progress.best, progress.checkpoint)
		publish()
		options.save()
	end

	local function teleport(player: Player, index: number)
		local character = player.Character
		if character then character:PivotTo(ClimbPath.standFrame(index)) end
	end

	-- The top: a win, then the next climb starts from the bottom.
	local function reachTop(player: Player?)
		if winning then return end
		winning = true
		progress.wins += 1
		setCheckpoint(ClimbPath.TOP)
		notify:FireAllClients("climbWin", { wins = progress.wins, name = if player then player.DisplayName else "" })
		task.delay(ClimbGame.WIN_SECONDS, function()
			winning = false
			setCheckpoint(0)
			notify:FireAllClients("climbRestart", {})
			for _, other in game:GetService("Players"):GetPlayers() do
				if climbing(other) then teleport(other, 0) end
			end
		end)
	end

	local self = {} :: Game
	self.built = built
	self.progress = progress
	self.climbing = climbing
	self.climber = climber

	function self.standFrame(): CFrame
		return ClimbPath.standFrame(progress.checkpoint)
	end

	-- Called when a player joins the climb (true) or leaves it (false).
	function self.entered(player: Player, isClimbing: boolean)
		applyMove(player)
	end

	function self.characterAdded(player: Player, character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and character.Parent ~= nil then applyMove(player) end
	end

	-- A climber's game says they landed on platform `index`: it becomes the
	-- checkpoint if it is higher, once the server sees them standing there.
	function self.land(player: Player, index: any)
		if not climbing(player) or winning or type(index) ~= "number" or index ~= math.floor(index) then return end
		if index <= progress.checkpoint or index > math.min(ClimbPath.TOP, progress.checkpoint + ClimbGame.MAX_SKIP) then return end
		local now = os.clock()
		if now - (landAt[player] or -math.huge) < 0.1 then return end
		landAt[player] = now
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = humanoidOf(player)
		if root == nil or not root:IsA("BasePart") or humanoid == nil or humanoid.Health <= 0 then return end
		-- The server sees the player a moment late, so it allows a little slack.
		local feet = root.Position - Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
		if not ClimbPath.isOn(index, feet, 4) then return end
		setCheckpoint(index)
		if index == ClimbPath.TOP then reachTop(player) end
	end

	-- The climb's sliders: { speed = studs a second, jump = studs high }.
	function self.setMove(player: Player, value: any)
		if type(value) ~= "table" then return end
		local now = os.clock()
		if now - (moveAt[player] or -math.huge) < 0.1 then return end
		moveAt[player] = now
		if type(value.speed) == "number" and value.speed == value.speed then
			progress.speed = math.clamp(math.floor(value.speed * 2 + 0.5) / 2, ClimbPath.SPEED.min, ClimbPath.SPEED.max)
		end
		if type(value.jump) == "number" and value.jump == value.jump then
			progress.jump = math.clamp(math.floor(value.jump * 10 + 0.5) / 10, ClimbPath.JUMP.min, ClimbPath.JUMP.max)
		end
		publish()
		options.save()
		for _, other in game:GetService("Players"):GetPlayers() do
			if climbing(other) then applyMove(other) end
		end
	end

	function self.setStrength(value: any): boolean
		if not table.find(ClimbGame.STRENGTHS, value) then return false end
		progress.strength = value
		publish()
		options.save()
		return true
	end

	-- From the streamer panel: back to the bottom (wins and best stay).
	function self.restart()
		if winning then return end
		setCheckpoint(0)
		notify:FireAllClients("climbRestart", {})
		for _, player in game:GetService("Players"):GetPlayers() do
			if climbing(player) then teleport(player, 0) end
		end
	end

	-- A gift (or a follow or share) moves the climber `move` platforms (up if
	-- positive). Every climbing player's game plays it with `info` (the
	-- gift's coins, name and sender). Returns where the climber was and is now.
	function self.gift(who: string, move: number, info: { [string]: any }): (number, number)
		local from = progress.checkpoint
		if winning or move == 0 then return from, from end
		local to = math.clamp(from + move, 0, ClimbPath.TOP)
		setCheckpoint(to)
		local data = table.clone(info)
		data.up = move > 0
		data.from = from
		data.to = to
		data.platforms = math.abs(move)
		data.name = who
		notify:FireAllClients("climbGift", data)
		if to == ClimbPath.TOP and from ~= to then
			-- The win waits for the ride up to finish.
			winning = true
			task.delay(ClimbPath.giftSeconds(info.coins or 1), function()
				winning = false
				reachTop(climber())
			end)
		end
		return from, to
	end

	function self.removing(player: Player)
		landAt[player] = nil
		moveAt[player] = nil
	end

	return self
end

return ClimbGame
