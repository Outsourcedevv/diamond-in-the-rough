"""Checks how the published game hears its streamer's connector
(TikTokFeed.useCode) under the Luau CLI with a Roblox stand-in: the topic it
listens on for the game code, the events it delivers once each, the TikTok
status lines, changing and clearing the code, retrying when MessagingService
is down, and saying so when the connector goes quiet.

    python3 tests/code-feed.py [path/to/luau]
"""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
luau = sys.argv[1] if len(sys.argv) > 1 else "luau"

source = (root / "src/server/TikTokFeed.luau").read_text(encoding="utf-8")
for name in ("HttpService", "MessagingService", "RunService", "ReplicatedStorage", "Config"):
    source = re.sub(rf'local {name} = [^\n]*\n', "", source)
prefix = re.search(r'MessagingTopicPrefix = "([^"]+)"', (root / "src/shared/Config.luau").read_text(encoding="utf-8")).group(1)
bridge_prefix = re.search(r"TOPIC_PREFIX = '([^']+)'", (root / "bridge/cloud.mjs").read_text(encoding="utf-8")).group(1)
if prefix != bridge_prefix:
    sys.exit(f"FAIL the game listens on {prefix!r} but the connector sends on {bridge_prefix!r}")

harness = r'''
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
}
local function step(seconds)
	local finish = clock + seconds
	while true do
		local soonest, index = nil, nil
		for i, item in sleeping do
			if item.at <= finish and (soonest == nil or item.at < soonest) then soonest, index = item.at, i end
		end
		if index == nil then clock = finish return end
		local item = table.remove(sleeping, index)
		clock = math.max(clock, item.at)
		local ok, problem = coroutine.resume(item.co)
		if not ok then error(problem, 0) end
	end
end
local os = { clock = function() return clock end }
local warn = function() end
local Config = { MessagingTopicPrefix = "PREFIX" }
-- Message data is handed over as a table already; JSONDecode passes it on.
local HttpService = { JSONDecode = function(_, data) return data end }
local listeners = {}
local failSubscribes = 0
local MessagingService = {
	SubscribeAsync = function(_, topic, callback)
		if failSubscribes > 0 then
			failSubscribes -= 1
			error("MessagingService unavailable", 0)
		end
		local listener = { topic = topic, callback = callback, connected = true }
		table.insert(listeners, listener)
		return { Disconnect = function() listener.connected = false end }
	end,
}
local RunService = { IsStudio = function() return false end }
local function publish(topic, events)
	for _, listener in listeners do
		if listener.connected and listener.topic == topic then listener.callback({ Data = events }) end
	end
end
local function connectedTopics()
	local topics = {}
	for _, listener in listeners do if listener.connected then table.insert(topics, listener.topic) end end
	return topics
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
local function onEvent(event) table.insert(got, event.type .. ":" .. tostring(event.gift or event.likes)) end
local function onStatus(line) status = line end

-- A published server never polls a PC.
TikTokFeed.start({ "http://localhost:8787" }, onEvent, onStatus)
check(#sleeping == 0, "no polling outside Studio")

TikTokFeed.useCode("", onEvent, onStatus)
check(#connectedTopics() == 0 and string.find(status, "no game code", 1, true) ~= nil, "no code: nothing to listen to")

TikTokFeed.useCode("abcd efgh", onEvent, onStatus)
check(connectedTopics()[1] == "PREFIXABCDEFGH" and #connectedTopics() == 1, "listens on the topic for the cleaned-up code")
check(string.find(status, "waiting", 1, true) ~= nil, "waits for the connector")

publish("PREFIXABCDEFGH", {
	{ id = "s1:1", type = "gift", gift = "Rose", coins = 1, count = 3 },
	{ id = "s1:2", type = "like", likes = 9 },
	{ id = "st1", type = "status", tiktok = "connected to @streamer" },
})
check(#got == 2 and got[1] == "gift:Rose" and got[2] == "like:9", "events arrive in order")
check(status == "connected to @streamer", "the status line shows, not as an event")
publish("PREFIXABCDEFGH", { { id = "s1:1", type = "gift", gift = "Rose", coins = 1, count = 3 } })
check(#got == 2, "a repeated event runs once")
publish("PREFIXOTHERCODE", { { id = "x:1", type = "gift", gift = "Lion", coins = 1, count = 1 } })
check(#got == 2, "another streamer's gifts never arrive")

-- Quiet for too long: the screen says so.
step(TikTokFeed.QUIET_SECONDS + 15)
check(string.find(status, "not heard from", 1, true) ~= nil, "a quiet connector is reported")

-- A new code: the old topic is dropped.
TikTokFeed.useCode("WXYZ2345", onEvent, onStatus)
check(#connectedTopics() == 1 and connectedTopics()[1] == "PREFIXWXYZ2345", "changing the code moves to its topic")
publish("PREFIXABCDEFGH", { { id = "s1:9", type = "gift", gift = "Lion", coins = 1, count = 1 } })
check(#got == 2, "the old code's gifts stop")

-- MessagingService down for a moment: it keeps trying.
failSubscribes = 2
TikTokFeed.useCode("QRST6789", onEvent, onStatus)
check(#connectedTopics() == 0 and string.find(status, "retrying", 1, true) ~= nil, "a failed subscribe retries")
step(60)
check(#connectedTopics() == 1 and connectedTopics()[1] == "PREFIXQRST6789", "listens once MessagingService is back")

TikTokFeed.useCode("", onEvent, onStatus)
check(#connectedTopics() == 0, "clearing the code stops listening")
print("code feed: " .. passed .. " checks passed")
'''

body = source.replace("return TikTokFeed", "")
program = harness + body + test
work = root / "tests" / ".code-feed.luau"
work.write_text(program, encoding="utf-8")
try:
    result = subprocess.run([luau, str(work)], capture_output=True, text=True)
finally:
    work.unlink(missing_ok=True)
print(result.stdout.strip())
if result.returncode != 0 or "FAIL" in result.stdout or result.stderr.strip():
    print(result.stderr.strip())
    sys.exit(1)
