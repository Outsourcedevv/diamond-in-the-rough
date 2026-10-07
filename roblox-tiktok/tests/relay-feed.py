"""Checks the game's side of the relay (TikTokFeed.useRelay) under the Luau CLI
with a Roblox stand-in: the request it makes for its game code, the events it
delivers once each, how it starts over when the relay restarts, changing the
code, clearing it, and what the screen says when the relay can't be reached.

    python3 tests/relay-feed.py [path/to/luau]
"""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
luau = sys.argv[1] if len(sys.argv) > 1 else "luau"

source = (root / "src/server/TikTokFeed.luau").read_text(encoding="utf-8")
source = re.sub(r'local HttpService = [^\n]*\n', "", source)
source = re.sub(r'local MessagingService = [^\n]*\n', "", source)
source = re.sub(r'local RunService = [^\n]*\n', "", source)

harness = r'''
-- A Roblox stand-in: a clock that runs only when the test says so, and an
-- HttpService whose GetAsync answers from a list of replies.
local clock = 0
local sleeping = {}
local task = {
	spawn = function(f, ...)
		local co = coroutine.create(f)
		local ok, problem = coroutine.resume(co, ...)
		if not ok then error(problem, 0) end
		return co
	end,
	wait = function(seconds)
		table.insert(sleeping, { at = clock + (seconds or 0), co = coroutine.running() })
		coroutine.yield()
	end,
	delay = function() end,
	defer = function(f, ...) f(...) end,
}
-- Runs the clock forward, waking whatever is due, until nothing is left or the
-- limit is reached (a loop that keeps sleeping would otherwise never stop).
local function step(seconds)
	local finish = clock + seconds
	while true do
		local soonest, index = nil, nil
		for i, item in sleeping do
			if item.at <= finish and (soonest == nil or item.at < soonest) then soonest, index = item.at, i end
		end
		if index == nil then
			clock = finish
			return
		end
		local item = table.remove(sleeping, index)
		clock = math.max(clock, item.at)
		local ok, problem = coroutine.resume(item.co)
		if not ok then error(problem, 0) end
	end
end

local requests = {}
local replies = {}
-- When the test has no reply queued: the same session with nothing new, as the
-- relay answers a game that is up to date.
local quietSession, quietLast = "abc123", 2
local function quiet()
	return string.format('{"session":"%s","last":%d,"tiktok":"connected to @niamh","events":[]}', quietSession, quietLast)
end
local HttpService = {
	UrlEncode = function(_, text)
		return (string.gsub(tostring(text), "[^%w%-%._~]", function(c)
			return string.format("%%%02X", string.byte(c))
		end))
	end,
	GetAsync = function(_, url)
		table.insert(requests, url)
		local reply = table.remove(replies, 1) or quiet()
		if reply == "fail" then error("HttpError: Timedout", 0) end
		return reply
	end,
	JSONDecode = function(_, text)
		-- Only the shapes this test sends: { session, last, tiktok, events }.
		local data = { events = {} }
		data.session = string.match(text, '"session":"([^"]*)"')
		data.last = tonumber(string.match(text, '"last":(%-?%d+)'))
		data.tiktok = string.match(text, '"tiktok":"([^"]*)"')
		for chunk in string.gmatch(text, '{"id":"[^"]*"[^}]*}') do
			local event = {
				id = string.match(chunk, '"id":"([^"]*)"'),
				type = string.match(chunk, '"type":"([^"]*)"'),
				gift = string.match(chunk, '"gift":"([^"]*)"'),
				coins = tonumber(string.match(chunk, '"coins":(%d+)')),
				count = tonumber(string.match(chunk, '"count":(%d+)')),
			}
			table.insert(data.events, event)
		end
		return data
	end,
}
local MessagingService = { SubscribeAsync = function() error("no MessagingService in Studio", 0) end }
local RunService = { IsStudio = function() return false end }
local function page(session, last, tiktok, events)
	local parts = {}
	for _, event in events do
		table.insert(parts, string.format('{"id":"%s","type":"%s","gift":"%s","coins":%d,"count":1}', event[1], event[2] or "gift", event[3] or "Rose", event[4] or 1))
	end
	return string.format('{"session":"%s","last":%d,"tiktok":"%s","events":[%s]}', session, last, tiktok, table.concat(parts, ","))
end
'''

test = r'''
local passed = 0
local function check(condition, message)
	if not condition then error("FAIL " .. message, 2) end
	passed += 1
end

local got = {}
local status = ""
local function onEvent(event) table.insert(got, event.type .. ":" .. tostring(event.gift)) end
local function onStatus(line) status = line end

-- The game code the streamer typed, and the relay's address.
replies = {
	page("abc123", 2, "connected to @niamh", { { "abc123:0", "giftRule", "Rose" }, { "abc123:1", "gift", "Galaxy", 1000 }, { "abc123:2", "gift", "Rose" } }),
}
TikTokFeed.useRelay("https://relay.example.com/", "abcd efgh", onEvent, onStatus)
step(1)
check(#requests >= 1, "it asked the relay: " .. #requests)
check(string.find(requests[1], "https://relay.example.com/c/ABCDEFGH/events?since=0&session=&wait=", 1, true) == 1,
	"it asks the relay for its own code, from the start: " .. requests[1])
check(table.concat(got, ",") == "giftRule:Rose,gift:Galaxy,gift:Rose", "every event is delivered: " .. table.concat(got, ","))
check(status == "connected to @niamh", "the screen shows the bridge's TikTok status: " .. status)

-- The next request carries the session and what it has seen, and a repeated
-- event (the relay replaying) only runs once.
got = {}
replies = { page("abc123", 3, "connected to @niamh", { { "abc123:2", "gift", "Rose" }, { "abc123:3", "gift", "Perfume", 20 } }) }
local asked = #requests + 1
step(1)
check(string.find(requests[asked], "since=2&session=abc123", 1, true) ~= nil, "it asks for what comes next: " .. requests[asked])
check(table.concat(got, ",") == "gift:Perfume", "an event already seen is not played twice: " .. table.concat(got, ","))

-- The relay restarted: a new session starts again from the beginning.
got = {}
quietSession, quietLast = "new999", 1
replies = { page("new999", 1, "waiting for your bridge", { { "new999:1", "gift", "Confetti", 100 } }) }
step(1)
check(table.concat(got, ",") == "gift:Confetti", "a restarted relay is picked up: " .. table.concat(got, ","))
step(1)
check(string.find(requests[#requests], "since=1&session=new999", 1, true) ~= nil, "it follows the new session: " .. requests[#requests])

-- The relay can't be reached: the screen says so and it keeps trying.
local before = #requests
replies = {}
for _ = 1, 40 do table.insert(replies, "fail") end
step(30)
check(#requests > before + 2, "it keeps trying: " .. (#requests - before) .. " tries")
check(status == "can't reach the relay (check the game code)", "the screen explains: " .. status)

-- A different code is used from then on, and the old loop stops.
replies = {}
quietSession, quietLast = "other", 1
TikTokFeed.useRelay("https://relay.example.com", "ZZZZ2222", onEvent, onStatus)
step(2)
local codes = {}
for _, url in requests do
	local code = string.match(url, "/c/([^/]+)/")
	codes[code] = (codes[code] or 0) + 1
end
local oldCount = codes.ABCDEFGH
step(3)
local after = {}
for _, url in requests do
	local code = string.match(url, "/c/([^/]+)/")
	after[code] = (after[code] or 0) + 1
end
check(after.ZZZZ2222 ~= nil and after.ZZZZ2222 > 1, "the new code is polled: " .. tostring(after.ZZZZ2222))
check(after.ABCDEFGH == oldCount, "the old code is left alone: " .. tostring(after.ABCDEFGH) .. " vs " .. tostring(oldCount))

-- Clearing the code (or the address) stops reading from the relay.
TikTokFeed.useRelay("", "", onEvent, onStatus)
check(status == "no game code set", "clearing it says so: " .. status)
local stopped = #requests
step(10)
check(#requests == stopped, "nothing is asked for once it is cleared: " .. (#requests - stopped) .. " extra")

-- Setting the same code again does not start a second loop.
replies = {}
quietSession = "again"
TikTokFeed.useRelay("https://relay.example.com", "ABCDEFGH", onEvent, onStatus)
step(1)
local one = #requests
TikTokFeed.useRelay("https://relay.example.com", "ABCDEFGH", onEvent, onStatus)
step(1)
local two = #requests
TikTokFeed.useRelay("https://relay.example.com", "ABCDEFGH", onEvent, onStatus)
step(1)
check(two - one >= 1 and (#requests - two) <= (two - one), "the same code keeps one loop: " .. (two - one) .. " then " .. (#requests - two))

print(string.format("PASS: %d relay feed checks", passed))
'''

generated = root / "tests/relay-feed.generated.luau"
body = harness + "\nlocal TikTokFeed = (function()\n" + source + "\nend)()\n" + test
try:
    generated.write_text(body, encoding="utf-8")
    subprocess.run([luau, str(generated)], check=True)
finally:
    generated.unlink(missing_ok=True)
