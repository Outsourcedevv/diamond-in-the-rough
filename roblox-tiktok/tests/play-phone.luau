-- A play session on a phone (tests/play.py): touch, no keyboard.
local uis = World.services.UserInputService
uis.TouchEnabled = true
uis.KeyboardEnabled = false
uis.MouseEnabled = false
local failures = {}
local function check(c, m) if not c then table.insert(failures, m) end end
World.start(server)
World.run(1)
local player = World.addPlayer("Phone", 2002)
if player.Character == nil then World.spawnCharacter(player) end
World.start(loading)
World.run(0.5)
local loadingGui = player.PlayerGui:FindFirstChild("DiamondRushLoading")
World.start(hud)
World.run(40)
check(loadingGui ~= nil and player.PlayerGui:FindFirstChild("DiamondRushLoading") == nil, "the loading screen shows, then goes, on a phone")
local Request = World.services.ReplicatedStorage.DiamondRushRemotes.Request
local gui = player.PlayerGui
local sidebar = gui:FindFirstChild("Sidebar")
check(sidebar and sidebar.Enabled, "the sidebar shows on a phone")
check(World.actions.DiamondRushSprint and World.actions.DiamondRushSprint.touch == true, "a Run button for phones")
-- Hiding the sidebar can't strand a phone (no keys to bring things back).
player:SetAttribute("HideButtons", true)
World.run(0.5)
check(sidebar.Enabled, "on a phone the sidebar stays even when hidden in settings")
-- The Run button: begin and end.
local run = World.actions.DiamondRushSprint
local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
run.f("DiamondRushSprint", World.Enum.UserInputState.Begin, {})
World.run(0.2)
check(humanoid.WalkSpeed == 24, "holding Run sprints")
run.f("DiamondRushSprint", World.Enum.UserInputState.End, {})
World.run(0.2)
check(humanoid.WalkSpeed == 16, "letting go walks")
for _, game in { "DiamondInTheRough", "DiamondClimb", "Chalkboard" } do
	Request:FireServer("joinGame", game)
	World.run(3)
	Request:FireServer("testGift", { coins = 1000, count = 1, name = "Galaxy" })
	World.run(8)
	World.run(1.5)
end
print(string.format("== phone: %d errors", #World.errors))
for i, e in World.errors do print("  [" .. i .. "] " .. e) end
for _, f in failures do print("  FAIL " .. f) end
