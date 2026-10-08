"""Checks how the published game hears its streamer's connector through the
relay (TikTokFeed.useCode) under the Luau CLI with a Roblox stand-in: the
address it asks for its game code, starting from the rules (not old gifts),
events delivered once each and in order, the TikTok status line, changing and
clearing the code, a missing relay address, and retrying when the relay can't
be reached.

    python3 tests/code-feed.py [path/to/luau]
"""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
luau = sys.argv[1] if len(sys.argv) > 1 else "luau"

source = (root / "src/server/TikTokFeed.luau").read_text(encoding="utf-8")
for name in ("HttpService", "RunService"):
    source = re.sub(rf'local {name} = [^\n]*\n', "", source)

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
local warn = function() end
-- A pretend relay: events per code, numbered across all codes like D1.
local relay = { events = {}, rules = {}, tiktok = {}, down = 0, asked = {} }
local nextId = 0
local function send(code, event)
	nextId += 1
	table.insert(relay.events, { id = nextId, code = code, event = event })
end
local HttpService = {
	HttpEnabled = true,
	-- Replies come back as tables already; JSONDecode passes them on.
	JSONDecode = function(_, data) return data end,
	GetAsync = function(_, url)
		table.insert(relay.asked, url)
		if relay.down > 0 then
			relay.down -= 1
			error("HttpError: ConnectFail", 0)
		end
		local code, since = string.match(url, "/c/(%w+)/events%?since=(%d+)")
		since = tonumber(since)
		if since == 0 then
			return { session = "d1", last = nextId, tiktok = relay.tiktok[code] or "", events = relay.rules[code] or {} }
		end
		local out, last = {}, since
		for _, row in relay.events do
			if row.code == code and row.id > since then table.insert(out, row.event) last = row.id end
		end
		-- Nothing new: the relay holds the request for a while.
		if #out == 0 then task.wait(8) end
		return { session = "d1", last = last, tiktok = relay.tiktok[code] or "", events = out }
	end,
}
local RunService = { IsStudio = function() return false end }
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
local URL = "https://relay.example.workers.dev/"

TikTokFeed.start({ "http://localhost:8787" }, onEvent, onStatus)
check(#sleeping == 0, "a published server never polls a PC")

TikTokFeed.useCode("ABCDEFGH", onEvent, onStatus, "")
check(string.find(status, "no relay address", 1, true) ~= nil, "no relay address is reported")
TikTokFeed.useCode("", onEvent, onStatus, URL)
check(string.find(status, "no game code", 1, true) ~= nil and #relay.asked == 0, "no code: nothing is asked")

-- Gifts sent before the game started are not replayed; the rules are.
send("ABCDEFGH", { id = "old:1", type = "gift", gift = "Old" })
relay.rules.ABCDEFGH = { { id = "r1", type = "giftRule", gift = "Rose" } }
relay.tiktok.ABCDEFGH = "connected to @streamer"
TikTokFeed.useCode("abcd efgh", onEvent, onStatus, URL)
step(0.5)
check(string.find(relay.asked[1], "https://relay.example.workers.dev/c/ABCDEFGH/events?since=0", 1, true) == 1, "asks the relay for its cleaned-up code")
check(#got == 0, "starts after the old gifts, and ignores rules from outside (the game's own gift settings rule)")
check(status == "connected to @streamer", "shows the TikTok status")

send("ABCDEFGH", { id = "s:1", type = "gift", gift = "Galaxy" })
send("OTHERCOD", { id = "x:1", type = "gift", gift = "Lion" })
send("ABCDEFGH", { id = "s:2", type = "like", likes = 9 })
step(10)
check(#got == 2 and got[1] == "gift:Galaxy" and got[2] == "like:9", "new gifts arrive in order, only this code's")
step(30)
check(#got == 2, "nothing twice")

-- The relay goes down for a moment: it keeps trying.
relay.down = 4
send("ABCDEFGH", { id = "s:3", type = "gift", gift = "Rose" })
step(9)
step(60)
check(got[3] == "gift:Rose", "gets going again once the relay is back")

-- A new code: the old one stops.
TikTokFeed.useCode("WXYZ2345", onEvent, onStatus, URL)
send("ABCDEFGH", { id = "s:9", type = "gift", gift = "Late" })
step(30)
for _, line in got do check(line ~= "gift:Late", "the old code's gifts stop") end
TikTokFeed.useCode("", onEvent, onStatus, URL)
local asked = #relay.asked
step(60)
check(#relay.asked <= asked + 1, "clearing the code stops asking")
print("code feed: " .. passed .. " checks passed")
'''

body = source.replace("return TikTokFeed", "")
work = root / "tests" / ".code-feed.luau"
work.write_text(harness + body + test, encoding="utf-8")
try:
    result = subprocess.run([luau, str(work)], capture_output=True, text=True)
finally:
    work.unlink(missing_ok=True)
print(result.stdout.strip())
if result.returncode != 0 or "FAIL" in result.stdout or result.stderr.strip():
    print(result.stderr.strip())
    sys.exit(1)
