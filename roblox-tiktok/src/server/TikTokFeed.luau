--!strict
-- Receives TikTok Live events from the streamer's connector (DiamondRushBridge.exe).
--  * The published game: the connector sends the events to the Diamond Rush
--    relay (relay/worker.js) under the streamer's game code. Once they type
--    the code in the Y panel, this server asks the relay for that code's
--    events, so only their gifts arrive. No Roblox key is involved.
--  * In Roblox Studio the game also polls the connector on this PC over HTTP.
-- Both paths can run at once; every event has a unique id and runs once.
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

export type Event = {
	id: string,
	type: string, -- "gift" | "like" | "follow" | "share" (and "status" from the relay)
	user: string?,
	name: string?,
	gift: string?,
	coins: number?, -- coins per gift
	count: number?, -- gifts in this event
	part: number?, -- set by the server when it plays a combo as separate gifts: which one this is
	parts: number?, -- and how many there are
	likes: number?,
	rocks: number?, -- set only by the game's own rebuild tests, never from outside
	tiktok: string?, -- "status" events: the connector's TikTok status line
}

local TikTokFeed = {}

local seen: { [string]: boolean } = {}
local seenOrder: { string } = {}

-- Only viewers' gifts, likes, follows and shares come from outside; gift rules
-- and the rest are set in the game itself (the gift settings and Y panel).
local ACCEPTED = { gift = true, like = true, follow = true, share = true }

local function deliver(raw: any, onEvent: (Event) -> ())
	if type(raw) ~= "table" or type(raw.id) ~= "string" or not ACCEPTED[raw.type] then
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
-- The game asks the relay for its code's events, and the relay holds each
-- request for a few seconds until something arrives, so gifts land within
-- about a second. The first request (start=1) only learns where the events
-- are up to, so gifts sent before the game started are not played; every
-- later one asks for the events after that (start=0, even from 0).
-- Goes up whenever the code changes, so an older loop stops.
local codeGeneration = 0
TikTokFeed.RELAY_WAIT = 8 -- seconds the relay may hold a request
TikTokFeed.IDLE_WAIT = 1 -- seconds between requests the relay answered at once with nothing

local function relayLoop(generation: number, url: string, code: string, onEvent: (Event) -> (), onStatus: (string) -> ())
	local since = 0
	local started = false
	local failures = 0
	while generation == codeGeneration do
		local address = string.format("%s/c/%s/events?since=%d&wait=%d&start=%d", url, code, since,
			if started then TikTokFeed.RELAY_WAIT else 0, if started then 0 else 1)
		local asked = os.clock()
		local ok, body = pcall(HttpService.GetAsync, HttpService, address, true)
		local decoded, data = false, nil
		if ok then
			decoded, data = pcall(HttpService.JSONDecode, HttpService, body)
		end
		if generation ~= codeGeneration then return end
		if decoded and type(data) == "table" and type(data.events) == "table" then
			failures = 0
			for _, raw in data.events do
				deliver(raw, onEvent)
			end
			if type(data.last) == "number" then since = math.max(since, data.last) end
			onStatus(if type(data.tiktok) == "string" and data.tiktok ~= "" then string.sub(data.tiktok, 1, 80) else "waiting for DiamondRushBridge.exe")
			-- An empty answer that came straight back (a relay that doesn't
			-- hold requests open) waits a second, so the game stays well under
			-- Roblox's HTTP limit and the relay's daily requests.
			local quick = started and #data.events == 0 and os.clock() - asked < 1
			started = true
			task.wait(if quick then TikTokFeed.IDLE_WAIT else 0.1)
		else
			failures += 1
			if not ok then warn("[DiamondRush] relay: " .. tostring(body)) end
			onStatus(if not HttpService.HttpEnabled then "Turn on HTTP: Game Settings > Security > Allow HTTP Requests"
				elseif failures > 2 then "can't reach the relay, retrying" else "connecting…")
			task.wait(math.min(2 * failures, 15))
		end
	end
end

-- Reads the connector's events under the streamer's game code, from the Y
-- panel, through the relay at `url` (Config.RelayUrl). An empty code stops.
function TikTokFeed.useCode(code: string, onEvent: (Event) -> (), onStatus: (string) -> (), url: string?)
	local clean = string.upper((string.gsub(code, "[^%w]", "")))
	local relay = (string.gsub(url or "", "/+$", ""))
	codeGeneration += 1
	if clean == "" then
		onStatus("no game code set (press Y)")
		return
	end
	if relay == "" then
		onStatus("no relay address (Config.RelayUrl)")
		return
	end
	onStatus("connecting…")
	task.spawn(relayLoop, codeGeneration, relay, clean, onEvent, onStatus)
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
				-- played (or sent before Play), so they are skipped.
				local fresh = session == ""
				if data.session ~= session then
					-- The bridge restarted: start again from its first event.
					session = tostring(data.session)
					since = 0
				end
				if type(data.events) == "table" then
					for _, raw in data.events do
						if not fresh then deliver(raw, onEvent) end
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
