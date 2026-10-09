"""Checks the sidebar and the theme shop under the Luau CLI with a Roblox
stand-in: the shop's rules (Alpine and unpriced themes free, the rest game
passes, what each button says), the sidebar's four buttons with their drawn
icons in order, GIFTS for the streamer only, the arrow sliding it away and
back, hiding it, and the Themes card: prices from Roblox, USE puts a theme on
the map, a price prompts Roblox's purchase of the right pass, and the card
follows the map's theme and what the player owns.

    python3 tests/sidebar.py [path/to/luau]
"""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
luau = sys.argv[1] if len(sys.argv) > 1 else "luau"


def module(path: str) -> str:
    source = (root / path).read_text(encoding="utf-8")
    source = re.sub(r'local Shared = [^\n]*\n', "", source)
    source = re.sub(r'require\(Shared:WaitForChild\("(\w+)"\)\)', r'require("../src/shared/\1")', source)
    for name in ("Players", "ReplicatedStorage", "TweenService", "MarketplaceService"):
        source = re.sub(rf'local {name} = game:GetService[^\n]*\n', "", source)
    return "(function()\n" + source + "\nend)()"


harness = r'''
local function signal()
	local listeners = {}
	return {
		Connect = function(_, f) table.insert(listeners, f); return { Disconnect = function() end } end,
		Fire = function(_, ...) for _, f in listeners do f(...) end end,
	}
end
local instances = {}
local Instance = { new = function(className)
	local object = { ClassName = className, Activated = signal(), MouseEnter = signal(), MouseLeave = signal(), Visible = true }
	table.insert(instances, object)
	return object
end }
local function childrenOf(parent)
	local out = {}
	for _, object in instances do if object.Parent == parent then table.insert(out, object) end end
	return out
end
local UDim = { new = function(s, o) return { Scale = s, Offset = o } end }
local UDim2 = {
	new = function(a, b, c, d) return { a, b, c, d } end,
	fromScale = function(a, b) return { a, 0, b, 0 } end,
	fromOffset = function(a, b) return { 0, a, 0, b } end,
}
local Vector2 = { new = function(x, y) return { X = x, Y = y } end }
local colour = {}
colour.__index = { Lerp = function(a) return a end }
local Color3 = {
	fromRGB = function(r, g, b) return setmetatable({ r, g, b }, colour) end,
	new = function(r, g, b) return setmetatable({ r * 255, g * 255, b * 255 }, colour) end,
}
local Enum = setmetatable({}, { __index = function(_, group)
	return setmetatable({}, { __index = function(_, item) return group .. "." .. item end })
end })
-- task.wait parks the coroutine (the sidebar's refresh loop runs once).
local task = {
	spawn = function(f, ...) local co = coroutine.create(f); local ok, problem = coroutine.resume(co, ...); if not ok then error(problem, 0) end end,
	wait = function() coroutine.yield() end,
}
local TweenInfo = { new = function() return {} end }
local TweenService = { Create = function(_, object, _, goal)
	return { Play = function() for key, value in goal do object[key] = value end end, Cancel = function() end }
end }
local prompted = {}
local PRICES = { [111] = 99, [333] = 149 }
local MarketplaceService = {
	PromptGamePassPurchase = function(_, who, pass) table.insert(prompted, { who = who, pass = pass }) end,
	GetProductInfo = function(_, id) return { PriceInRobux = PRICES[id] } end,
}
local function attributed(object)
	local attributes, changed = {}, {}
	object.GetAttribute = function(_, name) return attributes[name] end
	object.SetAttribute = function(_, name, value)
		attributes[name] = value
		if changed[name] then changed[name]:Fire() end
	end
	object.GetAttributeChangedSignal = function(_, name)
		changed[name] = changed[name] or signal()
		return changed[name]
	end
	return object
end
local playerGui = { Name = "PlayerGui" }
local player = attributed({ Name = "Streamer", WaitForChild = function() return playerGui end })
local Players = { LocalPlayer = player }
local state = attributed({})
local fired = {}
local request = { FireServer = function(_, action, value) table.insert(fired, { action = action, value = value }) end }
'''

test = r'''
local passed = 0
local function check(condition, message)
	if not condition then error("FAIL " .. message, 2) end
	passed += 1
end
local R = ThemeShop.ROBUX

-- The shop's rules.
local passes = { sakura = 111, farm = 0, desert = 333, haunted = 444 }
check(#ThemeShop.THEMES == 5 and ThemeShop.THEMES[1].key == "default" and ThemeShop.THEMES[1].name == "Alpine", "five themes, Alpine first")
check(ThemeShop.free("default", passes) and ThemeShop.free("farm", passes) and not ThemeShop.free("sakura", passes), "Alpine and unpriced themes are free")
check(ThemeShop.pass("default", { default = 5 }) == nil, "Alpine can never be sold")
check(ThemeShop.pass("desert", passes) == 333 and ThemeShop.forPass(333, passes) == "desert" and ThemeShop.forPass(999, passes) == nil, "each pass unlocks its theme")
local owned = { haunted = true }
local function status(key, current, price) return ThemeShop.status(key, current, owned, passes, price) end
check(select(2, status("default", "default")) == "using" and status("default", "default") == "IN USE", "the theme in use says so")
check(status("farm", "default") == "USE" and status("haunted", "default") == "USE", "free and bought themes can be used")
check(status("sakura", "default", 99) == R .. " 99" and select(2, status("sakura", "default", 99)) == "buy", "the rest show their price in Robux")
check(status("desert", "default") == "BUY", "a price not known yet says BUY")
check(ThemeShop.encode({ haunted = true, sakura = true }) == "sakura,haunted", "owned themes as text")
local decoded = ThemeShop.decode("haunted,nonsense,,farm")
check(decoded.haunted and decoded.farm and decoded.nonsense == nil, "and back, ignoring anything unknown")
check(next(ThemeShop.decode(nil)) == nil, "nothing owned yet")
for key in pairs(Config.ThemePasses) do check(ThemeShop.find(key) ~= nil and key ~= "default", "Config sells a real theme: " .. key) end

-- The icons are drawn.
for _, kind in Sidebar.ITEMS do
	local holder = Instance.new("Frame")
	local icon = Sidebar.icon(kind, holder, 38)
	check(icon.Parent == holder and #childrenOf(icon) >= 5, kind .. " has a drawn icon")
end

-- The sidebar.
for key, id in pairs(passes) do Config.ThemePasses[key] = id end
state:SetAttribute("Theme", "default")
player:SetAttribute("OwnedThemes", "haunted")
local picked = {}
local active = nil
Sidebar.start({
	request = request,
	state = state,
	onPick = function(name) table.insert(picked, name) end,
	active = function() return active end,
})
local gui = nil
for _, object in instances do if object.ClassName == "ScreenGui" and object.Name == "Sidebar" then gui = object end end
check(gui ~= nil and gui.Parent == playerGui and gui.ResetOnSpawn == false, "the sidebar has its own screen layer")
local labels = {}
for _, object in instances do
	if object.ClassName == "TextLabel" and object.Parent and object.Parent.ClassName == "TextButton" and Sidebar.LABELS[string.lower(object.Text or "")] then
		labels[object.Parent.LayoutOrder] = object.Text
	end
end
check(table.concat(labels, ",") == "GIFTS,THEMES,SETTINGS,GAMES", "gifts at the top, themes, settings, then games: " .. table.concat(labels, ","))
local function button(label)
	for _, object in instances do
		if object.ClassName == "TextLabel" and object.Text == label and object.Parent and object.Parent.ClassName == "TextButton" then return object.Parent end
	end
	return nil
end
for _, label in { "GIFTS", "THEMES", "SETTINGS", "GAMES" } do
	local hasIcon = false
	for _, child in childrenOf(button(label)) do if child.ClassName == "Frame" and #childrenOf(child) >= 5 then hasIcon = true end end
	check(hasIcon, label .. " has its icon")
end
button("SETTINGS").Activated:Fire()
button("GAMES").Activated:Fire()
check(picked[1] == "settings" and picked[2] == "games", "the buttons say which was pressed")
active = "games"
button("GAMES").Activated:Fire()
check(button("GAMES").BackgroundTransparency < 0.5 and button("SETTINGS").BackgroundTransparency == 1, "the open card's button is lit")
Sidebar.setAdmin(false)
check(button("GIFTS").Visible == false, "GIFTS is the streamer's only")
Sidebar.setAdmin(true)
check(button("GIFTS").Visible == true, "and shows for the streamer")

-- The arrow slides it away and back.
local arrow = nil
for _, object in instances do if object.ClassName == "TextButton" and object.Text == "‹" then arrow = object end end
check(arrow ~= nil, "an arrow on the sidebar's edge")
local bar = button("GAMES").Parent
-- The bar's list layout would place anything inside it among the buttons, so
-- the arrow must sit beside the bar (it once sat in it, and hiding the bar
-- hid the arrow too).
local inList = false
for _, child in childrenOf(arrow.Parent) do if child.ClassName == "UIListLayout" then inList = true end end
check(not inList and arrow.Parent ~= bar, "the arrow sits beside the bar, not in its list")
check(bar.Position[2] == Sidebar.MARGIN and arrow.Position[2] >= Sidebar.MARGIN + Sidebar.BAR_WIDTH, "the sidebar shows to start with, the arrow on its edge")
arrow.Activated:Fire()
check(arrow.Text == "›" and bar.Position[2] + Sidebar.BAR_WIDTH <= 0, "the arrow tucks the bar away off screen")
check(arrow.Position[2] >= 0 and arrow.Position[2] < 20, "and stays at the screen's edge to bring it back")
arrow.Activated:Fire()
check(arrow.Text == "‹" and bar.Position[2] == Sidebar.MARGIN and arrow.Position[2] >= Sidebar.MARGIN + Sidebar.BAR_WIDTH, "and brings it back")
Sidebar.setHidden(true)
check(gui.Enabled == false, "settings can hide it")
Sidebar.setHidden(false)
check(gui.Enabled == true, "and show it again")

-- The Themes card.
check(not Sidebar.themesOpen(), "the themes card starts closed")
Sidebar.setThemesOpen(true)
check(Sidebar.themesOpen(), "it opens")
local function row(name)
	for _, object in instances do
		if object.ClassName == "TextLabel" and object.Text == name and object.Parent and object.Parent.ClassName == "Frame" then
			for _, child in childrenOf(object.Parent) do if child.ClassName == "TextButton" then return child end end
		end
	end
	return nil
end
check(row("Alpine").Text == "IN USE", "Alpine is in use")
check(row("Sakura").Text == R .. " 99" and row("Desert").Text == R .. " 149", "paid themes show their Robux price")
check(row("Farm").Text == "USE", "a theme with no pass is free")
check(row("Haunted").Text == "USE", "a bought theme can be used")
row("Farm").Activated:Fire()
check(fired[#fired].action == "setTheme" and fired[#fired].value == "farm", "USE puts the theme on the map")
row("Sakura").Activated:Fire()
check(#prompted == 1 and prompted[1].pass == 111 and prompted[1].who == player, "a price opens Roblox's purchase of that theme's pass")
check(fired[#fired].value == "farm", "buying doesn't change the map by itself (the server does once it's bought)")
state:SetAttribute("Theme", "farm")
check(row("Farm").Text == "IN USE" and row("Alpine").Text == "USE", "the card follows the map's theme")
player:SetAttribute("OwnedThemes", "haunted,sakura")
check(row("Sakura").Text == "USE", "a theme just bought can be used")
row("Alpine").Activated:Fire()
check(fired[#fired].value == "default", "Alpine is always free")
Sidebar.setThemesOpen(false)
check(not Sidebar.themesOpen(), "it closes")
print("sidebar: " .. passed .. " checks passed")
'''

program = (harness
    + "local Config = " + module("src/shared/Config.luau") + "\n"
    + "local ThemeShop = " + module("src/shared/ThemeShop.luau") + "\n"
    + "local Sidebar = " + module("src/client/Sidebar.luau").replace('require("../src/shared/Config")', "Config").replace('require("../src/shared/ThemeShop")', "ThemeShop") + "\n"
    + test)
work = root / "tests" / ".sidebar.luau"
work.write_text(program, encoding="utf-8")
try:
    result = subprocess.run([luau, str(work)], capture_output=True, text=True)
finally:
    work.unlink(missing_ok=True)
print(result.stdout.strip())
if result.returncode != 0 or "FAIL" in result.stdout or result.stderr.strip():
    print(result.stderr.strip())
    sys.exit(1)
