--!strict
-- Receives TikTok Live events from the bridge app.
--  * In Roblox Studio the game polls the bridge on this PC over HTTP.
--  * In a published game the bridge publishes to MessagingService through
--    Roblox Open Cloud (see the README), and the game subscribes here.
--  * A published game that many streamers play reads the streamer's own
--    events from the relay, using the game code they typed in the Y panel
--    (see relay/relay.mjs). Only that code's gifts arrive.
-- Every path can run at once; every event has a unique id and runs once.
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local RunService = game:GetService("RunService")

export type Event = {
	id: string,
	type: string, -- "gift" | "like" | "follow" | "share" | "giftRule" | "climbRule" | "chalkRule" | "theme" | "skin"
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

-- The relay (a published game played by many streamers) ------------------------
-- The game asks the relay for its code's events and holds the request open
-- until something arrives, so gifts land about as fast as in Studio.
local RELAY_WAIT = 15
local relayCode = ""
local relayUrl = ""
-- Goes up whenever the code or address changes, so an older loop stops.
local relayGeneration = 0

local function relayLoop(generation: number, onEvent: (Event) -> (), onStatus: (string) -> ())
	local session = ""
	local since = 0
	local failures = 0
	local code = relayCode
	while relayGeneration == generation and code ~= "" do
		local url = string.format(
			"%s/c/%s/events?since=%d&session=%s&wait=%d",
			relayUrl,
			HttpService:UrlEncode(code),
			since,
			HttpService:UrlEncode(session),
			RELAY_WAIT
		)
		local ok, body = pcall(HttpService.GetAsync, HttpService, url, true)
		local decoded, data = false, nil
		if ok then
			decoded, data = pcall(HttpService.JSONDecode, HttpService, body)
		end
		if decoded and type(data) == "table" and type(data.events) == "table" then
			failures = 0
			if data.session ~= session then
				session = tostring(data.session)
				since = 0
			end
			for _, raw in data.events do
				deliver(raw, onEvent)
			end
			if type(data.last) == "number" then
				since = data.last
			end
			onStatus(if type(data.tiktok) == "string" and data.tiktok ~= "" then data.tiktok else "waiting for your bridge")
			task.wait(0.2)
		else
			failures += 1
			onStatus(if failures > 2 then "can't reach the relay (check the game code)" else "connecting to the relay…")
			task.wait(math.min(2 * failures, 15))
		end
	end
end

-- The streamer's game code and the relay's address, from the Y panel. An empty
-- code stops reading from the relay.
function TikTokFeed.useRelay(url: string, code: string, onEvent: (Event) -> (), onStatus: (string) -> ())
	local cleanUrl = (string.gsub(url, "/+$", ""))
	-- The streamer may type the code with a space or dash, as it is shown.
	local cleanCode = if cleanUrl == "" then "" else string.upper((string.gsub(code, "[^%w]", "")))
	if cleanUrl == relayUrl and cleanCode == relayCode then
		return
	end
	relayUrl = cleanUrl
	relayCode = cleanCode
	-- Any loop still running is for the old code, so it stops on its own.
	relayGeneration += 1
	if relayCode == "" then
		onStatus("no game code set")
		return
	end
	task.spawn(relayLoop, relayGeneration, onEvent, onStatus)
end

-- onStatus receives a short line for the screen, such as
-- "TikTok: connected to @name" or "Bridge app not running".
function TikTokFeed.start(urls: { string }, topic: string, onEvent: (Event) -> (), onStatus: (string) -> ())
	-- Published games: Open Cloud messages carry a JSON list of events.
	task.spawn(function()
		local ok, problem = pcall(function()
			MessagingService:SubscribeAsync(topic, function(message)
				local decoded, data = pcall(HttpService.JSONDecode, HttpService, message.Data)
				if decoded and type(data) == "table" then
					for _, raw in data do
						deliver(raw, onEvent)
					end
				end
			end)
		end)
		if not ok and not RunService:IsStudio() then
			warn("[DiamondRush] MessagingService unavailable: " .. tostring(problem))
		end
	end)

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
				if RunService:IsStudio() or failures <= #urls then
					onStatus("Bridge app not running (start \"Start Bridge\" on this PC)")
				end
				-- Published servers cannot reach a PC; stop polling and rely on
				-- MessagingService after the first round of failures.
				if not RunService:IsStudio() and failures > #urls * 2 then
					onStatus("Waiting for TikTok events (Open Cloud)")
					return
				end
				task.wait(2)
			end
		end
	end)
end

return TikTokFeed
