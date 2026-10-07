--!strict
-- Receives TikTok Live events from the streamer's connector (DiamondRushBridge.exe).
--  * The published game: the connector publishes to MessagingService through
--    Roblox Open Cloud, on the topic for the streamer's game code (see
--    bridge/cloud.mjs). Once they type the code in the Y panel, this server
--    listens to that topic only, so only their gifts arrive.
--  * In Roblox Studio the game also polls the connector on this PC over HTTP.
-- Both paths can run at once; every event has a unique id and runs once.
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("DiamondRush"):WaitForChild("Config"))

export type Event = {
	id: string,
	type: string, -- "gift" | "like" | "follow" | "share" | "giftRule" | "climbRule" | "chalkRule" | "theme" | "skin" | "status"
	user: string?,
	name: string?,
	gift: string?,
	coins: number?, -- coins per gift
	count: number?, -- gifts in this event
	part: number?, -- set by the server when it plays a combo as separate gifts: which one this is
	parts: number?, -- and how many there are
	likes: number?,
	rocks: number?,
	keybind: string?,
	amount: number?, -- "climbRule" and "chalkRule" events: platforms or numbers per gift, negative for down
	clear: boolean?, -- and true when the rule is removed
	theme: string?, -- "theme" events: the map theme the control page chose
	skin: string?, -- "skin" events: stone and diamond, or hay and needle
	tiktok: string?, -- "status" events: the connector's TikTok status line
}

local TikTokFeed = {}

local seen: { [string]: boolean } = {}
local seenOrder: { string } = {}

local function deliver(raw: any, onEvent: (Event) -> ())
	if type(raw) ~= "table" or type(raw.id) ~= "string" or type(raw.type) ~= "string" then
		return
	end
	if seen[raw.id] then
		return
	end
	seen[raw.id] = true
	table.insert(seenOrder, raw.id)
	if #seenOrder > 4000 then
		seen[table.remove(seenOrder, 1) :: string] = nil
	end
	local event: Event = {
		rocks = if type(raw.rocks) == "number" and raw.rocks == raw.rocks then math.clamp(raw.rocks, -1500000, 1500000) else nil,
		keybind = if type(raw.keybind) == "string" then string.sub(raw.keybind, 1, 16) else nil,
		amount = if type(raw.amount) == "number" and raw.amount == raw.amount then math.clamp(raw.amount, -100000, 100000) else nil,
		clear = if raw.clear == true then true else nil,
		theme = if type(raw.theme) == "string" then string.sub(raw.theme, 1, 16) else nil,
		skin = if type(raw.skin) == "string" then string.sub(raw.skin, 1, 16) else nil,
		tiktok = if type(raw.tiktok) == "string" then string.sub(raw.tiktok, 1, 80) else nil,
		id = raw.id,
		type = raw.type,
		user = if type(raw.user) == "string" then string.sub(raw.user, 1, 40) else nil,
		name = if type(raw.name) == "string" then string.sub(raw.name, 1, 40) else nil,
		gift = if type(raw.gift) == "string" then string.sub(raw.gift, 1, 40) else nil,
		coins = if type(raw.coins) == "number" then math.clamp(raw.coins, 0, 100000) else nil,
		count = if type(raw.count) == "number" then math.clamp(raw.count, 0, 10000) else nil,
		likes = if type(raw.likes) == "number" then math.clamp(raw.likes, 0, 100000) else nil,
	}
	local ok, problem = pcall(function()
		onEvent(event)
	end)
	if not ok then
		warn("[DiamondRush] event failed: " .. tostring(problem))
	end
end

-- The published game ---------------------------------------------------------
-- The streamer's game code and the topic it is sent on. Goes up whenever the
-- code changes, so an older watcher stops.
local codeGeneration = 0
local subscription: RBXScriptConnection? = nil
TikTokFeed.QUIET_SECONDS = 150 -- the connector says how TikTok is doing every minute

function TikTokFeed.topicFor(code: string): string
	return Config.MessagingTopicPrefix .. code
end

-- Listens for the connector's events under the streamer's game code, from the
-- Y panel. An empty code stops listening.
function TikTokFeed.useCode(code: string, onEvent: (Event) -> (), onStatus: (string) -> ())
	local clean = string.upper((string.gsub(code, "[^%w]", "")))
	codeGeneration += 1
	local generation = codeGeneration
	if subscription then
		subscription:Disconnect()
		subscription = nil
	end
	if clean == "" then
		onStatus("no game code set (press Y)")
		return
	end
	onStatus("waiting for DiamondRushBridge.exe")
	local heard: number? = nil -- when the connector was last heard from
	task.spawn(function()
		local tries = 0
		while generation == codeGeneration do
			local ok, result = pcall(function()
				return MessagingService:SubscribeAsync(TikTokFeed.topicFor(clean), function(message)
					local decoded, data = pcall(HttpService.JSONDecode, HttpService, message.Data)
					if not decoded or type(data) ~= "table" then return end
					heard = os.clock()
					for _, raw in data do
						if type(raw) == "table" and raw.type == "status" then
							if type(raw.tiktok) == "string" then onStatus(string.sub(raw.tiktok, 1, 80)) end
						else
							deliver(raw, onEvent)
						end
					end
				end)
			end)
			if ok then
				if generation == codeGeneration then
					subscription = result
				else
					result:Disconnect()
				end
				break
			end
			tries += 1
			warn("[DiamondRush] couldn't listen for the connector: " .. tostring(result))
			onStatus("can't reach Roblox's messaging, retrying")
			task.wait(math.min(5 * tries, 30))
		end
		-- No word from the connector for a while: say so.
		while generation == codeGeneration do
			task.wait(10)
			local last = heard
			if generation == codeGeneration and last ~= nil and os.clock() - last > TikTokFeed.QUIET_SECONDS then
				onStatus("connector not heard from (is DiamondRushBridge.exe open, with this game code?)")
				heard = nil
			end
		end
	end)
end

-- onStatus receives a short line for the screen, such as
-- "TikTok: connected to @name" or "Bridge app not running".
function TikTokFeed.start(urls: { string }, onEvent: (Event) -> (), onStatus: (string) -> ())
	-- A published server can't reach anyone's PC: it uses useCode instead.
	if not RunService:IsStudio() then return end
	-- Roblox Studio: poll the bridge app on this PC.
	task.spawn(function()
		local session = ""
		local since = 0
		local urlIndex = 1
		local failures = 0
		while true do
			if not HttpService.HttpEnabled then
				if RunService:IsStudio() then
					onStatus("Turn on HTTP: Home > Game Settings > Security > Allow HTTP Requests")
				end
				task.wait(3)
				continue
			end
			local url = urls[urlIndex] .. "/events?since=" .. tostring(since) .. "&session=" .. HttpService:UrlEncode(session)
			local ok, body = pcall(HttpService.GetAsync, HttpService, url, true)
			local decoded, data = false, nil
			if ok then
				decoded, data = pcall(HttpService.JSONDecode, HttpService, body)
			end
			if decoded and type(data) == "table" then
				failures = 0
				-- The game just started: the bridge's older events were already
				-- played (or sent before Play), so only its gift rules apply
				-- (the mountain's, the climb's and the chalkboard's).
				local fresh = session == ""
				if data.session ~= session then
					-- The bridge restarted: start again from its first event.
					session = tostring(data.session)
					since = 0
				end
				if type(data.events) == "table" then
					for _, raw in data.events do
						if not fresh or (type(raw) == "table" and (raw.type == "giftRule" or raw.type == "climbRule" or raw.type == "chalkRule")) then
							deliver(raw, onEvent)
						end
					end
				end
				if type(data.last) == "number" then
					since = data.last
				end
				onStatus(if type(data.tiktok) == "string" then data.tiktok else "TikTok bridge connected")
				task.wait(0.3)
			else
				failures += 1
				urlIndex = urlIndex % #urls + 1
				onStatus("connector not running (open DiamondRushBridge.exe on this PC)")
				task.wait(2)
			end
		end
	end)
end

return TikTokFeed
