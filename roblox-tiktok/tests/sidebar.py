"""Checks the sidebar and the theme shop under the Luau CLI with a Roblox
stand-in: the shop's rules (Alpine and unpriced themes free, the rest game
passes, what each button says), the sidebar's four buttons with their drawn
icons in order, GIFTS for the streamer only, the arrow sliding it away and
back, hiding it, and the Themes card: prices from Roblox, USE puts a theme on
the map, a price prompts Roblox's purchase of the right pass, and the card
follows the map's theme and what the player owns. The mountain skins (stone,
and the haystack with its needle) have a section of their own on the card,
after the map themes, and work the same way with setSkin; the list scrolls
on short screens.

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
local PRICES = { [111] = 99, [333] = 149, [555] = 79 }
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
local viewportChanged = signal()
local camera = { ViewportSize = Vector2.new(1280, 720), GetPropertyChangedSignal = function() return viewportChanged end }
local workspace = { CurrentCamera = camera }
'''

test = r'''
local passed = 0
local function check(condition, message)
	if not condition then error("FAIL " .. message, 2) end
	passed += 1
end
local R = ThemeShop.ROBUX

-- The shop's rules.
local passes = { sakura = 111, farm = 0, desert = 333, haunted = 444, hay = 555 }
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
-- The price line under each one: everyone sees the price, owner or not.
check(ThemeShop.tag("default", owned, passes) == "Free" and ThemeShop.tag("farm", owned, passes) == "Free", "free ones say Free")
check(ThemeShop.tag("sakura", owned, passes, 99) == R .. " 99", "the rest show their price")
check(ThemeShop.tag("haunted", owned, passes, 249) == R .. " 249  ·  yours", "and say when they're yours (the game's creator owns every pass)")
check(ThemeShop.tag("desert", owned, passes, nil, false) == "Pass not for sale yet" and ThemeShop.tag("haunted", owned, passes, nil, false) == "Yours  ·  pass not for sale", "a pass with no price isn't for sale yet")
check(ThemeShop.tag("desert", owned, passes) == "Game pass" and ThemeShop.tag("haunted", owned, passes) == "Yours", "before Roblox has said")
check(ThemeShop.encode({ haunted = true, sakura = true }) == "sakura,haunted", "owned themes as text")
local decoded = ThemeShop.decode("haunted,nonsense,,farm")
check(decoded.haunted and decoded.farm and decoded.nonsense == nil, "and back, ignoring anything unknown")
check(next(ThemeShop.decode(nil)) == nil, "nothing owned yet")
-- The mountain's skins.
check(#ThemeShop.SKINS == 2 and ThemeShop.SKINS[1].key == "stone" and ThemeShop.SKINS[2].key == "hay", "two skins, stone first")
check(ThemeShop.find("hay").kind == "skin" and ThemeShop.find("sakura").kind == "theme", "skins and themes know which they are")
check(#ThemeShop.ITEMS == #ThemeShop.THEMES + #ThemeShop.SKINS and ThemeShop.ITEMS[#ThemeShop.ITEMS].key == "hay", "the shop sells themes, then skins")
check(ThemeShop.pass("stone", { stone = 5 }) == nil and ThemeShop.free("stone", passes), "the stone skin can never be sold")
check(ThemeShop.pass("hay", passes) == 555 and ThemeShop.forPass(555, passes) == "hay", "the haystack skin's pass unlocks it")
check(ThemeShop.decode("hay,sakura").hay and ThemeShop.encode({ hay = true, sakura = true }) == "sakura,hay", "an owned skin is remembered with the themes")
check(Config.ThemePasses.hay ~= nil, "Config has a pass for the haystack skin")
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
local function tag(name)
	for _, child in childrenOf(row(name).Parent) do if child.Name == "Price" then return child.Text end end
	return nil
end
check(tag("Sakura") == R .. " 99" and tag("Desert") == R .. " 149", "each row shows its price on a line of its own")
check(tag("Farm") == "Free" and tag("Alpine") == "Free", "and free ones say so")
check(tag("Haunted") == "Yours  ·  pass not for sale", "a bought theme whose pass has no price says so: " .. tag("Haunted"))
row("Farm").Activated:Fire()
check(fired[#fired].action == "setTheme" and fired[#fired].value == "farm", "USE puts the theme on the map")
row("Sakura").Activated:Fire()
check(#prompted == 1 and prompted[1].pass == 111 and prompted[1].who == player, "a price opens Roblox's purchase of that theme's pass")
check(fired[#fired].value == "farm", "buying doesn't change the map by itself (the server does once it's bought)")
state:SetAttribute("Theme", "farm")
check(row("Farm").Text == "IN USE" and row("Alpine").Text == "USE", "the card follows the map's theme")
player:SetAttribute("OwnedThemes", "haunted,sakura")
check(row("Sakura").Text == "USE", "a theme just bought can be used")
check(tag("Sakura") == R .. " 99  ·  yours", "and its price line says it's yours, with its price still showing")
row("Alpine").Activated:Fire()
check(fired[#fired].value == "default", "Alpine is always free")

-- The mountain skins, in their own section after the map's themes.
local themesLabel, skinsLabel = nil, nil
for _, object in instances do
	if object.ClassName == "TextLabel" and object.Text == "MAP THEMES" then themesLabel = object end
	if object.ClassName == "TextLabel" and type(object.Text) == "string" and string.sub(object.Text, 1, 14) == "MOUNTAIN SKINS" then skinsLabel = object end
end
check(themesLabel ~= nil and skinsLabel ~= nil and themesLabel.Parent == skinsLabel.Parent, "the card has a MAP THEMES and a MOUNTAIN SKINS section")
local function rowFrame(name) return row(name).Parent end
check(themesLabel.LayoutOrder < rowFrame("Alpine").LayoutOrder and rowFrame("Haunted").LayoutOrder < skinsLabel.LayoutOrder, "the themes sit under MAP THEMES")
check(skinsLabel.LayoutOrder < rowFrame("Stone & diamond").LayoutOrder and rowFrame("Stone & diamond").LayoutOrder < rowFrame("Hay & needle").LayoutOrder, "the skins sit under MOUNTAIN SKINS, stone first")
check(rowFrame("Hay & needle").Parent == skinsLabel.Parent, "in the same list")
local needle = nil
for _, object in instances do if object.Name == "Highlight" and object.Parent and object.Parent.Parent and object.Parent.Parent.Parent == rowFrame("Hay & needle") then needle = object end end
check(needle ~= nil and needle.Size[2] <= 3, "the haystack's picture has a thin needle in it")
check(row("Stone & diamond").Text == "IN USE", "the stone skin is in use to start with")
check(row("Hay & needle").Text == R .. " 79", "the haystack skin shows its Robux price")
check(tag("Hay & needle") == R .. " 79" and tag("Stone & diamond") == "Free", "on its price line too")
local before = #prompted
row("Hay & needle").Activated:Fire()
check(#prompted == before + 1 and prompted[#prompted].pass == 555, "its price opens Roblox's purchase of the haystack pass")
player:SetAttribute("OwnedThemes", "haunted,sakura,hay")
check(row("Hay & needle").Text == "USE", "a bought haystack skin can be used")
row("Hay & needle").Activated:Fire()
check(fired[#fired].action == "setSkin" and fired[#fired].value == "hay", "USE puts the haystack skin on the mountain")
state:SetAttribute("Theme", "default")
state:SetAttribute("Skin", "hay")
check(row("Hay & needle").Text == "IN USE" and row("Stone & diamond").Text == "USE", "the card follows the mountain's skin")
check(row("Alpine").Text == "IN USE" and row("Farm").Text == "USE", "and a skin doesn't change which theme is in use")
row("Stone & diamond").Activated:Fire()
check(fired[#fired].action == "setSkin" and fired[#fired].value == "stone", "the stone skin is always free")
row("Farm").Activated:Fire()
check(fired[#fired].action == "setTheme", "and the themes still change the theme")

-- The list fits the screen, and scrolls on a short one (a phone).
local list = nil
for _, object in instances do if object.Name == "ThemeList" then list = object end end
check(list ~= nil and list.ClassName == "ScrollingFrame" and list.AutomaticCanvasSize == "AutomaticSize.Y", "the rows are in a scrolling list")
local full = #ThemeShop.ITEMS * 72 + 2 * 26
local function fits(height) return 2 * Sidebar.CENTRE * height - list.Size[4] >= 150 end
check(list.Size[4] < full and fits(720), "on a 720p screen it fits and scrolls: " .. tostring(list.Size[4]))
camera.ViewportSize = Vector2.new(1920, 1080)
viewportChanged:Fire()
check(list.Size[4] == full and fits(1080), "on a 1080p screen it shows every row: " .. tostring(list.Size[4]))
camera.ViewportSize = Vector2.new(800, 390)
viewportChanged:Fire()
check(list.Size[4] == 167 and fits(390), "on a short screen it shrinks and scrolls: " .. tostring(list.Size[4]))
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
