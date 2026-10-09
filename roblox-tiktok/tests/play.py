"""Play-tests the whole game under the Luau CLI: the real server script and
client script run together in a stand-in Roblox world (tests/roblox-world.luau)
with a simulated clock, the player's inputs and Roblox's purchases. Three runs:

  1. tests/play-session.luau: the loading screen, the lobby, the sidebar and every card and
     switch, the keys, the portals, every game with gifts, the gift settings
     (wins, reset gifts, keys), buying a theme, finding and holding the
     diamond, statues, saving;
  2. a restart from that session's save: wins, theme, keys and rules return;
  3. tests/play-phone.luau: a touch screen with no keyboard.

Any error in any script, or a failed check, fails the test.

    python3 tests/play.py [path/to/luau]
"""
from pathlib import Path
import json
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
luau = sys.argv[1] if len(sys.argv) > 1 else "luau"


def long_string(text: str) -> str:
    level = 1
    while ("]" + "=" * level + "]") in text:
        level += 1
    return "[" + "=" * level + "[\n" + text + "]" + "=" * level + "]"


def game_program(scenario: str) -> str:
    """The world, every script and module as default.project.json lays them out, then the scenario."""
    parts = ["local World = (function()\n" + (root / "tests/roblox-world.luau").read_text(encoding="utf-8") + "\nend)()\n"]
    parts.append("""
local RS = World.services.ReplicatedStorage
local shared = World.newInstance("Folder"); shared.Name = "DiamondRush"; shared.Parent = RS
local SSS = World.services.ServerScriptService
local SPS = World.services.StarterPlayer.StarterPlayerScripts
""")
    parts.append(f'local loading = World.addScript(World.services.ReplicatedFirst, "DiamondRushLoading", "LocalScript", {long_string((root / "src/first/init.client.luau").read_text(encoding="utf-8"))})\n')
    for path in sorted((root / "src/shared").glob("*.luau")):
        parts.append(f'World.addScript(shared, "{path.stem}", "ModuleScript", {long_string(path.read_text(encoding="utf-8"))})\n')
    parts.append(f'local server = World.addScript(SSS, "DiamondRushServer", "Script", {long_string((root / "src/server/init.server.luau").read_text(encoding="utf-8"))})\n')
    for path in sorted((root / "src/server").glob("*.luau")):
        if path.name != "init.server.luau":
            parts.append(f'World.addScript(server, "{path.stem}", "ModuleScript", {long_string(path.read_text(encoding="utf-8"))})\n')
    parts.append(f'local hud = World.addScript(SPS, "DiamondRushHud", "LocalScript", {long_string((root / "src/client/init.client.luau").read_text(encoding="utf-8"))})\n')
    for path in sorted((root / "src/client").glob("*.luau")):
        if path.name != "init.client.luau":
            parts.append(f'World.addScript(hud, "{path.stem}", "ModuleScript", {long_string(path.read_text(encoding="utf-8"))})\n')
    parts.append(scenario)
    return "".join(parts)


def play(name: str, scenario: str) -> str:
    work = root / "tests" / f".play-{name}.luau"
    work.write_text(game_program(scenario), encoding="utf-8")
    try:
        result = subprocess.run([luau, str(work)], capture_output=True, text=True)
    finally:
        work.unlink(missing_ok=True)
    if result.returncode != 0 or result.stderr.strip():
        print(result.stdout)
        print(result.stderr.strip())
        sys.exit(1)
    return result.stdout


RESTART = '''
local failures = {}
local function check(c, m) if not c then table.insert(failures, m) end end
World.start(server)
World.run(1)
local player = World.addPlayer("Streamer", 1001)
if player.Character == nil then World.spawnCharacter(player) end
World.start(hud)
World.run(40)
local saved = World.saves["DiamondRushTikTok_v1"]["player_1001"]
local State = World.services.ReplicatedStorage.DiamondRushState
check(State:GetAttribute("Wins") == saved.wins, "wins come back: " .. tostring(State:GetAttribute("Wins")))
check(State:GetAttribute("ClimbWins") == saved.climb.wins, "Diamond Climb's wins come back")
check(State:GetAttribute("ChalkWins") == saved.chalk.wins, "Chalkboard Count's wins come back")
check(State:GetAttribute("Theme") == saved.theme, "the theme comes back")
check(State:GetAttribute("BestTime") == saved.best, "the best time comes back")
local bindings = World.json.decode(State:GetAttribute("GiftBindings"))
check(bindings.K and bindings.K.gift == "Rose", "the Rose key comes back")
check(World.json.decode(State:GetAttribute("WinRules")).rose == 2, "Rose's wins come back")
check(player:GetAttribute("OwnedThemes") == "", "bought themes are asked of Roblox again (none here)")
local wins = State:GetAttribute("Wins")
World.press("K")
World.run(5)
check(State:GetAttribute("Wins") == wins + 2, "the saved key still works")
print(string.format("== restart: %d errors, t=%.1f", #World.errors, World.now()))
for i, e in World.errors do print("  [" .. i .. "] " .. e) end
for _, f in failures do print("  FAIL " .. f) end
'''

session = play("session", (root / "tests/play-session.luau").read_text(encoding="utf-8"))
saves = []
for line in session.splitlines():
    if line.startswith("SAVE "):
        _, store, key, body = line.split(" ", 3)
        saves.append(f"World.saves[{json.dumps(store)}] = World.saves[{json.dumps(store)}] or {{}}\n"
                     f"World.saves[{json.dumps(store)}][{json.dumps(key)}] = World.json.decode({json.dumps(body)})\n")
restart = play("restart", "".join(saves) + RESTART)
phone = play("phone", (root / "tests/play-phone.luau").read_text(encoding="utf-8"))

report = [line for line in (session + restart + phone).splitlines() if not line.startswith("SAVE ")]
print("\n".join(line for line in report if line.startswith("==") or line.startswith("  ")))
broken = [line for line in report if line.startswith("  [") or line.startswith("  FAIL")]
if not saves:
    broken.append("the session saved nothing")
sections = sum(1 for line in report if line.startswith("=="))
if broken:
    print(f"play: {len(broken)} problems")
    sys.exit(1)
print(f"play: {sections} sections played with no errors")
