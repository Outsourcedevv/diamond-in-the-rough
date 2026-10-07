--!strict
-- Chalkboard Count, the third game in the games menu: the writer stands at a
-- big green chalkboard, filmed by the classroom camera, and holds down to
-- write the next number, and the next, at their chosen writing speed, until
-- they reach the goal. TikTok gifts move the count up (gifts that would break
-- the mountain) or down (gifts that add stone). The reset gift (a Galaxy) starts
-- a 60 second countdown that wipes the board back to 0, unless someone sends
-- a gift worth 1,000 coins or more to save it. Reaching the goal wins.
--
-- Everything is saved in settings.chalk and shown to every player through the
-- State attributes ChalkCount, ChalkGoal, ChalkWins, ChalkBest, ChalkSpeed,
-- ChalkTheme, ChalkResetGift, ChalkSaveCoins, ChalkResetSeconds,
-- ChalkStrength, ChalkResetEnds (server time the board is wiped, 0 when no
-- countdown) and ChalkWriting. The game is single player, so there is one count.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("DiamondRush")
local ChalkBoard = require(Shared:WaitForChild("ChalkBoard"))
local Classroom = require(script.Parent:WaitForChild("Classroom"))

local ChalkGame = {}

export type Progress = {
	count: number, goal: number, wins: number, best: number, speed: number, theme: string,
	resetGift: string, saveCoins: number, resetSeconds: number, strength: number,
}

ChalkGame.STRENGTHS = { 0.5, 1, 2 }
ChalkGame.WIN_SECONDS = 6 -- the celebration before the board is wiped for the next count

function ChalkGame.defaults(): Progress
	return {
		count = 0, goal = ChalkBoard.GOAL.default, wins = 0, best = 0, speed = ChalkBoard.SPEED.default, theme = "classic",
		resetGift = ChalkBoard.RESET_GIFT, saveCoins = ChalkBoard.SAVE_COINS, resetSeconds = ChalkBoard.RESET_SECONDS.default, strength = 1,
	}
end

-- A saved count with anything missing or out of range put right.
function ChalkGame.clean(saved: any): Progress
	local progress = ChalkGame.defaults()
	if type(saved) ~= "table" then return progress end
	local function number(key: string, low: number, high: number, whole: boolean)
		local value = saved[key]
		if type(value) == "number" and value == value then
			value = math.clamp(value, low, high)
			progress[key] = if whole then math.floor(value) else value
		end
	end
	number("goal", ChalkBoard.GOAL.min, ChalkBoard.GOAL.max, true)
	number("count", 0, progress.goal, true)
	number("wins", 0, 999999, true)
	number("best", 0, ChalkBoard.GOAL.max, true)
	number("speed", ChalkBoard.SPEED.min, ChalkBoard.SPEED.max, false)
	number("saveCoins", 1, 1000000, true)
	number("resetSeconds", ChalkBoard.RESET_SECONDS.min, ChalkBoard.RESET_SECONDS.max, true)
	if type(saved.theme) == "string" and ChalkBoard.THEMES[saved.theme] then progress.theme = saved.theme end
	if type(saved.resetGift) == "string" then progress.resetGift = string.sub(saved.resetGift, 1, 40) end
	if table.find(ChalkGame.STRENGTHS, saved.strength) then progress.strength = saved.strength end
	-- A count saved at the goal (the server stopped during the win) starts again.
	if progress.count >= progress.goal then progress.count = 0 end
	progress.best = math.max(progress.best, progress.count)
	return progress
end

export type Options = {
	settings: any, -- the saved settings; the count lives in settings.chalk
	save: () -> (),
	state: Instance,
	notify: RemoteEvent,
	parent: Instance,
	filter: ((Player, string) -> string?)?, -- the chat filter, for the reset gift's name
}

export type Game = {
	built: Classroom.Built,
	progress: Progress,
	writer: () -> Player?,
	standFrame: () -> CFrame,
	entered: (player: Player, writing: boolean) -> (),
	characterAdded: (player: Player, character: Model) -> (),
	hold: (player: Player, value: any) -> (),
	setting: (player: Player, action: string, value: any) -> boolean,
	gift: (who: string, event: { [string]: any }, rocks: number, doubled: boolean) -> string,
	removing: (player: Player) -> (),
}

function ChalkGame.start(options: Options): Game
	local settings = options.settings
	local progress = ChalkGame.clean(settings.chalk)
	settings.chalk = progress
	local state = options.state
	local notify = options.notify
	local built = Classroom.build(options.parent, ServerStorage, progress.theme)
	local holding: { [Player]: boolean } = {}
	local holdAt: { [Player]: number } = {}
	local resetEnds = 0
	local resetSerial = 0
	local winning = false
	local dirty = false

	local function publish()
		state:SetAttribute("ChalkCount", progress.count)
		state:SetAttribute("ChalkGoal", progress.goal)
		state:SetAttribute("ChalkWins", progress.wins)
		state:SetAttribute("ChalkBest", progress.best)
		state:SetAttribute("ChalkSpeed", progress.speed)
		state:SetAttribute("ChalkTheme", progress.theme)
		state:SetAttribute("ChalkResetGift", progress.resetGift)
		state:SetAttribute("ChalkSaveCoins", progress.saveCoins)
		state:SetAttribute("ChalkResetSeconds", progress.resetSeconds)
		state:SetAttribute("ChalkStrength", progress.strength)
		state:SetAttribute("ChalkResetEnds", resetEnds)
	end
	publish()
	state:SetAttribute("ChalkWriting", false)

	local function writing(player: Player): boolean
		return player:GetAttribute("InChalk") == true
	end
	local function writer(): Player?
		for _, player in game:GetService("Players"):GetPlayers() do
			if writing(player) then return player end
		end
		return nil
	end

	-- The writer stands still at the board; elsewhere Roblox's usual movement.
	local function applyMove(player: Player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid == nil then return end
		if writing(player) then
			humanoid.WalkSpeed = 0
			humanoid.UseJumpPower = false
			humanoid.JumpHeight = 0
		else
			humanoid.UseJumpPower = StarterPlayer.CharacterUseJumpPower
			humanoid.WalkSpeed = StarterPlayer.CharacterWalkSpeed
			humanoid.JumpHeight = StarterPlayer.CharacterJumpHeight
			humanoid.JumpPower = StarterPlayer.CharacterJumpPower
		end
	end

	-- The count changed: shown at once, saved a moment later (writing is fast).
	local function setCount(value: number)
		progress.count = math.clamp(math.floor(value), 0, progress.goal)
		progress.best = math.max(progress.best, progress.count)
		state:SetAttribute("ChalkCount", progress.count)
		state:SetAttribute("ChalkBest", progress.best)
		dirty = true
	end

	local function cancelReset()
		resetSerial += 1
		resetEnds = 0
		state:SetAttribute("ChalkResetEnds", 0)
	end

	-- The goal: a win, then the board is wiped for the next count.
	local function reachGoal()
		if winning then return end
		winning = true
		cancelReset()
		progress.wins += 1
		state:SetAttribute("ChalkWins", progress.wins)
		dirty = true
		local who = writer()
		notify:FireAllClients("chalkWin", { wins = progress.wins, goal = progress.goal, name = if who then who.DisplayName else "" })
		task.delay(ChalkGame.WIN_SECONDS, function()
			winning = false
			setCount(0)
			notify:FireAllClients("chalkWipe", { reason = "win" })
		end)
	end

	local function add(amount: number)
		if winning then return end
		setCount(progress.count + amount)
		if progress.count >= progress.goal then reachGoal() end
	end

	-- Writing: while the writer holds, one number every 1/speed seconds.
	local carry = 0
	RunService.Heartbeat:Connect(function(dt: number)
		local anyone = false
		for player, on in holding do
			if on and writing(player) and player.Parent ~= nil then anyone = true end
		end
		if state:GetAttribute("ChalkWriting") ~= anyone then state:SetAttribute("ChalkWriting", anyone) end
		if not anyone or winning then
			carry = 0
			return
		end
		carry += dt * progress.speed
		local whole = math.floor(carry)
		if whole > 0 then
			carry -= whole
			add(math.min(whole, 5))
		end
	end)
	-- Saves the count every few seconds while it changes.
	task.spawn(function()
		while true do
			task.wait(4)
			if dirty then
				dirty = false
				options.save()
			end
		end
	end)

	local self = {} :: Game
	self.built = built
	self.progress = progress
	self.writer = writer

	function self.standFrame(): CFrame
		return ChalkBoard.standFrame()
	end

	function self.entered(player: Player, isWriting: boolean)
		if not isWriting then holding[player] = nil end
		applyMove(player)
	end

	function self.characterAdded(player: Player, character: Model)
		holding[player] = nil
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and character.Parent ~= nil then applyMove(player) end
	end

	-- The writer's game says they pressed (true) or let go (false).
	function self.hold(player: Player, value: any)
		if type(value) ~= "boolean" then return end
		local now = os.clock()
		if value and now - (holdAt[player] or -math.huge) < 0.05 then return end
		holdAt[player] = now
		holding[player] = value and writing(player) or nil
	end

	-- Settings from the writer's card and the streamer panel. True if handled.
	function self.setting(player: Player, action: string, value: any): boolean
		if action == "setChalkSpeed" and type(value) == "number" and value == value then
			progress.speed = math.clamp(math.floor(value * 2 + 0.5) / 2, ChalkBoard.SPEED.min, ChalkBoard.SPEED.max)
		elseif action == "setChalkTheme" and type(value) == "string" and ChalkBoard.THEMES[value] then
			progress.theme = value
			Classroom.setTheme(built, value)
		elseif action == "setChalkGoal" and type(value) == "number" and value == value then
			progress.goal = math.clamp(math.floor(value), ChalkBoard.GOAL.min, ChalkBoard.GOAL.max)
			if progress.count >= progress.goal then setCount(progress.goal - 1) end
		elseif action == "setChalkResetGift" and type(value) == "string" then
			local name = string.gsub(string.sub(value, 1, 40), "^%s*(.-)%s*$", "%1")
			local clean = if name == "" then "" elseif options.filter then options.filter(player, name) else name
			if clean == nil then return true end
			progress.resetGift = clean
		elseif action == "setChalkSaveCoins" and type(value) == "number" and value == value then
			progress.saveCoins = math.clamp(math.floor(value), 1, 1000000)
		elseif action == "setChalkResetSeconds" and type(value) == "number" and value == value then
			progress.resetSeconds = math.clamp(math.floor(value), ChalkBoard.RESET_SECONDS.min, ChalkBoard.RESET_SECONDS.max)
		elseif action == "setChalkStrength" and table.find(ChalkGame.STRENGTHS, value) then
			progress.strength = value
		elseif action == "chalkRestart" then
			if winning then return true end
			cancelReset()
			setCount(0)
			notify:FireAllClients("chalkWipe", { reason = "restart" })
		elseif action == "chalkTestReset" then
			self.gift("Test", { type = "gift", gift = progress.resetGift ~= "" and progress.resetGift or ChalkBoard.RESET_GIFT, coins = 1000, id = "test-reset" }, 1, false)
			return true
		elseif action == "chalkTestSave" then
			self.gift("Test", { type = "gift", gift = "Save test", coins = progress.saveCoins, id = "test-save" }, 1, false)
			return true
		else
			return false
		end
		publish()
		options.save()
		return true
	end

	-- A gift (or a follow or share) for the count. `rocks` is what it would do
	-- to the mountain: its sign decides up or down. Returns the feed's ending.
	function self.gift(who: string, event: { [string]: any }, rocks: number, doubled: boolean): string
		if winning then return "" end
		local coins = math.max(1, event.coins or 1)
		local count = math.max(1, math.floor(event.count or 1))
		if event.type == "gift" and ChalkBoard.isResetGift(event.gift, progress.resetGift) then
			-- The reset gift: a countdown to wipe the board (it does not stack).
			if resetEnds == 0 then
				resetSerial += 1
				local serial = resetSerial
				resetEnds = workspace:GetServerTimeNow() + progress.resetSeconds
				state:SetAttribute("ChalkResetEnds", resetEnds)
				notify:FireAllClients("chalkReset", { state = "started", name = who, seconds = progress.resetSeconds, saveCoins = progress.saveCoins })
				task.delay(progress.resetSeconds, function()
					if serial ~= resetSerial or winning then return end
					resetEnds = 0
					state:SetAttribute("ChalkResetEnds", 0)
					local lost = progress.count
					setCount(0)
					notify:FireAllClients("chalkReset", { state = "wiped", lost = lost })
					notify:FireAllClients("chalkWipe", { reason = "reset" })
				end)
				return string.format("  RESET IN %d", progress.resetSeconds)
			end
			return "  (reset already counting down)"
		end
		local ending = ""
		if event.type == "gift" and resetEnds > 0 and ChalkBoard.isSaveGift(event.gift, coins * count, progress.resetGift, progress.saveCoins) then
			cancelReset()
			notify:FireAllClients("chalkReset", { state = "saved", name = who })
			ending = "  SAVED THE BOARD"
		end
		local amount = if event.type == "gift" then ChalkBoard.giftAmount(rocks, coins, count, progress.strength)
			elseif rocks > 0 then 1 else 0
		if amount ~= 0 then
			local from = progress.count
			add(amount)
			local moved = progress.count - from
			notify:FireAllClients("chalkGift", { up = amount > 0, from = from, to = progress.count, amount = moved, coins = coins, name = who,
				gift = event.gift or (if event.type == "follow" then "Follow" elseif event.type == "share" then "Share" else "Gift"), doubled = doubled })
			if moved ~= 0 then
				ending = (if moved > 0 then string.format("  +%d", moved) else string.format("  %d", moved)) .. ending
			end
		end
		return ending
	end

	function self.removing(player: Player)
		holding[player] = nil
		holdAt[player] = nil
	end

	return self
end

return ChalkGame
