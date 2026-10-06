# Diamond Rush: TikTok Live Roblox game

A Roblox version of Diamond in the Rough made for TikTok LIVE. A big mountain made of **250,000 rocks** (one rock is one stone) is shown counting down at the top of the screen. The rock slopes smoothly towards open air, with snow on the summit, grassy foothills over a dirt layer and layered stone inside: finding the one small diamond should feel like finding a needle in a haystack. Every gift, like, follow and share from your viewers blasts stone out of it. Once the diamond is exposed, find it, click it and **hold it for 15 seconds** to win.

- **Royal lobby.** Everyone arrives in a white marble court floating in the sky, with gold trim, royal blue banners, a ring of columns and a giant turning diamond. A games menu on the left joins **Diamond in the Rough**; more games are marked *Coming soon*. See [The lobby and the games menu](#the-lobby-and-the-games-menu).
- **Stone counter.** The top of the screen shows how much stone is left (250,000 to start), with a progress bar.
- **Gifts blast the mountain.** Each TikTok coin removes 100 rocks, so a Rose (1 coin) removes 100 and a Galaxy (1,000 coins) removes 100,000. The counter always equals the rocks really left. Likes, follows and shares also chip away. Big gifts make big explosions. A feed in the corner shows who sent what.
- **Diamond bird.** Every 5 to 7½ minutes (at random) a sparkling bird made of diamond swoops down from the sky and circles the mountain about halfway up, flapping its glass wings. Click it and **every gift counts double for 30 seconds**: gifts that blast stone remove twice as much, gifts with an add rule add twice as much, the gift animation is sized for the doubled gift and the coins count double on the leaderboard. The display shows **DIAMOND BIRD · CLICK IT FOR 2X GIFTS** while it is flying, and a gold **2X** card with the seconds left sits beside the stone count while the bonus runs; doubled gifts show 2X in the feed. Gifts are doubled if they arrive during the 30 seconds, even if the mountain is still busy with earlier gifts. Aim the dot at it in first person: the dot turns gold and grows when a click will catch it, so you don't have to hit the bird exactly (it counts within a few degrees), and on a phone you tap it. The click goes to the server, which checks the bird is still circling and that you are within 300 studs of where it is flying. If nobody catches it, it flies off when the next bird arrives. Catching another bird during the bonus restarts the 30 seconds (gifts are doubled, never quadrupled). The **Y** panel has **Send a diamond bird now** for testing, and the timings are in `src/shared/Config.luau` (`BirdMinSeconds`, `BirdMaxSeconds`, `BirdBoostSeconds`, `BirdMultiplier`).
- **Gift animations.** One gift's coins pick one of six hand-made effects, each bigger than the last. A combo plays as separate gifts: Galaxy x10 is ten Galaxy Collapses one after another (each with its own blast and feed line), not one 10,000-coin effect. Gifts in a combo are spaced about half an effect apart, and very long combos (Rose x500) are shared out over at most 20 gifts:
  - **Spark Burst** (1–9 coins): a golden pop with sparks, a puff of dust and a small ground ring.
  - **Shockwave** (10–99): a double shockwave ring races across the ground while sparks, embers and chunks of rock fly.
  - **Diamond Fracture** (100–499): glowing cracks spread over the remaining rock, ice-blue crystals burst up out of them, and then they shatter into glittering shards.
  - **Orbital Strike** (500–999): a target ring locks on while a charge gathers high in the sky, then a beam slams down, the screen flashes and fire, smoke and embers erupt. A barrage of four more strikes walks round the crater, and a wider beam with three rings finishes it (about 4½ seconds).
  - **Galaxy Collapse** (1,000–9,999): a black hole opens over the rock with a spinning ring of stars and pulls light in from all round, then goes nova. The stars fling out in spiral arms, the hole flickers back for a second pulse, and a beam of starlight pours into the mountain with sparks raining down (about 5 seconds).
  - **Cosmic Burst** (10,000+): the sky darkens for the whole show, a storm of twelve meteors rains down round the target, then a blazing comet strikes with a mushroom of fire and smoke, three shockwaves and a pillar of light. Fire geysers erupt in a ring, a second wave of meteors falls, and a final cosmic shock flashes the sky white and rolls rings out across the valley (about 7 seconds).

  The effects use Roblox's own particle textures (sparkles, fire, smoke, embers and shockwave rings), neon parts with trails, lights, a gentle camera shake and a brief colour grade. Flying rock and dust match the mountain skin, so the haystack throws hay.

  Gifts that add stone have their own six effects, in greens, played on the summit:
  - **Pebble Drop** (1–9 coins): pebbles fall onto the peak with puffs of dust.
  - **Rockslide** (10–99): a ring of rocks rises out of the slopes and tumbles in.
  - **Stone Surge** (100–499): green veins race in from all round, then stone pillars thrust up, lean in and sink into the peak.
  - **Boulder Barrage** (500–999): a dozen boulders are hurled in from far away, trailing dust, and crash home one after another, then the peak heaves with a ring and a pillar of light (about 4 seconds).
  - **Stone Cyclone** (1,000–9,999): 32 rocks from the valley spiral up into a towering cyclone round a pulsing green core, slam down into the peak, and a second ring and pillar blast out (about 4½ seconds).
  - **Mountain Rising** (10,000+): the sky turns, the ground rumbles and green light cracks outward, then a colossal boulder descends slowly, pulling 26 rocks up off the slopes, and lands with a blast of light. A ring of eight green pillars erupts round the mountain and the peak pulses once more (about 5½ seconds).

  The rocks that come back still fly into place one by one, in stone or hay to match the skin. The six **REBUILD TEST GIFTS** buttons in the Y panel play these effects in order, smallest to biggest. A banner shows the effect, the sender, the gift and the coins. The effects are cosmetic: they never collide, block digging or cast shadows. At most two play at once (expensive gifts take priority), each is capped (70 parts and 3 lights for the small tiers, up to 160 parts and 4 lights for the biggest), and everything is cleaned up within 12 seconds. Gift blasts only remove mountain stones: they never target the diamond, and the gem settles above the actual visible stone or ground after each blast. To see each effect, use the Y panel's test presets (Rose, Doughnut, Hand Hearts, Money Gun, Galaxy and Lion cover all six tiers, and Galaxy x10 shows a combo as ten Galaxies); each button shows the coins for one gift, and the bridge control page has the same presets. Test gifts use these same effects.
- **Find and click the diamond.** The uncovered message tells you when it can be found, but there is no floating location label, through-rock outline or light beacon. Aim directly at the gem and left-click (tap on mobile) within 12 studs. Walking into it and pressing E do not pick it up; rocks cannot be clicked through.
- **Hold the diamond.** The gem flies from where it lay into your right hand, your hand lifts it high and your view eases upward, framing a large, sparkling diamond against the sky. The eight-sided gem has a pale crown, a bright table and a deeper blue pointed base, so it reads clearly as a diamond on stream. A visible palm, thumb and curled fingers grip it. **You cannot move while holding it:** you stay frozen in place until you win or a rebuild gift cancels the hold. The countdown occupies the top-centre HUD while holding, leaving the hand and gem clear below it. Other players see a big sparkling diamond in your avatar's raised hand.
  - A big countdown shows **10 → 0**, but it really takes **15 seconds**: the numbers tick fast at first and slow down near the end.
  - If you fall or leave, the diamond drops.
- **Scenery.** An alpine valley in smooth terrain, with grassy meadows and animated grass, a lake with a dock, a log-cabin mining camp with a porch, warm windows, a campfire and lanterns, and a timber fire lookout on a hillside to the left of the mountain, with braced log legs, a ladder, a lamp-lit lookout under a shingle roof and a red flag (alpine only; it is put away in the sakura theme). The valley is ringed by huge snow-capped mountains made in Blender and filled with about 200 pines (snow-dusted higher up), birches, oaks, mossy boulders, rock outcrops, bushes, wildflower patches, fallen logs and stumps. The game builds these meshes itself when it starts, so there is nothing to import (see [Blender scenery](#blender-scenery)). Where Roblox does not allow that (a published game without Mesh / Image APIs turned on), built-in low-poly trees, terrain boulders and terrain peaks are used instead. The place uses Future lighting and Roblox's 2022 material pack, with atmosphere haze, sun rays, bloom and a gentle colour grade.
- **Sakura theme.** The map can switch between the alpine valley (the default), a sakura spring and a farm (below). Sakura adds about 50 cherry trees in blossom across the meadows and round the camp, each with fallen petals beneath it, a vermilion torii gate where the trail leaves the camp (framing the mountain from the spawn, in place of the festoon lights) stone lanterns at the camp and on the dock, and a Shinto shrine on a flat meadow to one side of the mountain, facing the camp. The shrine has a stone plinth with steps, vermilion pillars, paper screens, a curved copper roof with crossed finials, a sacred straw rope with paper streamers, a bell, an offering box, a golden mirror on its altar and its own small torii on the approach. The light turns to a lower golden sun through a soft pink haze, with fresh green meadows and blush-tinted clouds, and cherry petals drift down around everyone playing. Choose it in the **Y** panel under **MAP THEME** (**Alpine**, **Sakura** or **Farm**) or from **3 · Map theme** on the bridge control page. It changes for everyone straight away, without restarting, and the game remembers the choice. The looks are in `src/server/Scenery.luau` (`LOOKS`) and the sakura scenery in `src/server/Sakura.luau`.
- **Farm theme.** The third map theme turns the valley into a ranch. A timber board fence runs all the way round the mountain's arena, open only where the trail comes in from the camp, under a log gate arch. Beyond the fence, on open ground in view of the spawn, stands a red gambrel-roofed barn with white trim, big X-braced doors, a hayloft, a cupola and weathervane and a concrete silo, with a cornfield and a scarecrow beside it, a windpump, a little red tractor, stacked and round hay bales, and cows grazing round a water trough. The light is a warm harvest-time sun through a golden haze. The fence is solid but low enough to hop. Choose it in the **Y** panel under **MAP THEME** (**Farm**) or from **3 · Map theme** on the control page; it hides the alpine festoon lights and watchtower, and works with either mountain skin (hay and a needle suits it). The farm scenery is in `src/server/Farm.luau`. The barn (with its silo), the sakura shrine (with its torii) and the alpine lookout are built 1.5 times their drawn size so they stand out from the camp; change `Farm.BARN_SCALE`, `Sakura.SHRINE_SCALE` or `Watchtower.SCALE` to resize them, and the ground they need is found to match.
- **Haystack skin.** The mountain itself can be reskinned as a haystack with a **needle** hidden in it instead of a diamond: the same game, the same rules, only the look changes. The rock turns to straw (sun-bleached on top, greener fresh hay low down, packed hay and golden bales inside) and the gem becomes a steel needle with a red thread through its eye, found, clicked and held exactly like the diamond. The display follows: **HAY LEFT**, **NEEDLE UNCOVERED**, **NEEDLE SECURED!** and the lobby's status line. Choose it in the **Y** panel under **MOUNTAIN SKIN** (**Stone & diamond** or **Hay & needle**) or under **3 · Map theme** on the control page. It works with either map theme, changes for everyone straight away and is remembered. The palettes are in `src/shared/RockStyle.luau` (`HAY_LAYERS`), the needle in `src/shared/DiamondShape.luau` and the words in `src/shared/Skin.luau`.
- **Leaderboards.** Two giant 3D wooden boards stand behind the mountain, either side of the summit, angled towards the camp: **TOP HELPERS** (blue border, a pickaxe on the roof) ranks viewers by the coins they sent in gifts that break the mountain, and **TOP GRIEFERS** (red border, boulders on the roof) by the coins they sent in gifts that add stone (gifts with a negative rule). Each shows the top 10 on a shingle-roofed board with log posts. Totals are saved between streams, viewer names are text-filtered, and test gifts never count.
- **Gold statues.** Honour a big gifter with a gold statue holding a diamond aloft on a marble pedestal. An engraved brass plaque shows their name and coins. Statues are placed and removed from the settings panel and saved to the player who built them (see [single player](#playing-the-published-game-instead-of-studio-optional)).
- **Win counter.** It sits under the stone count and is fully customisable: title, number, an optional goal (e.g. `WINS: 3/10`), text colour and background colour. It is saved between streams.
- **Win screen.** It shows for 4 seconds with **This round's time** and **Best round's time** (and NEW BEST TIME when you beat it). Then the mountain rebuilds from base to peak in 16 waves, with flying stones snapping into place and a final glint at the summit. Gifts arriving during the rebuild are saved and applied when digging resumes.
- **Settings and field of view.** Every player has a **SETTINGS** button at the top left (or press **P**, which frees the mouse in first person; it used to be O, but O is Roblox's zoom-out key and Roblox swallowed it). Its **Field of view** slider runs from 50 to 100 (70 by default) with **Reset** and **Done**. **Hide buttons** tucks away the **GAMES** tab and the **SETTINGS** button so they stay off the stream; **G** and **P** still open them, and the game remembers the choice for that player. The hands are refitted to the field of view, so they keep the same size and place on screen and the dig swing looks the same at any setting. The field of view applies only in the game (the lobby keeps the normal view) and lasts for the session. If the streamer gave **P** to a gift keybind through an older bridge, use the button instead.
- **Clean display.** The on-screen display uses one style throughout: Gotham type, dark see-through panels with a fine edge, white text, a pale blue accent and gold for wins, and no emojis anywhere (in the game or on the control page). There are no lettered signs in the world (their text renders badly in Roblox); only the leaderboards and statue plaques carry text.
- **Aim at stone.** A small dot marks the centre of the screen. The surface rock directly under it gets a white outline; the outline follows the same target used for digging and disappears when aiming away or opening settings.
- **Dig with your hands.** First-person view with two hands: hold the left mouse button on the mountain and your hands take turns, four swings a second: each draws back, drives forward into the rock with the fingers clawed, and rakes the rubble down and back. The rock breaks as each hand lands (25 rocks a strike, about 100 a second), so what you see and what you dig stay in step. A swing always finishes once begun, so letting go never snaps a hand back. The hands are drawn small and close to the camera, so they never sink into the rock when you stand right against it. Connected, hinged fingers curl during the scoop; sleeves meet the palms, and the real avatar arms are hidden locally to prevent duplicate floating limbs; the animation pauses when you aim away from reachable stone.

## Gift catalogue and keybinds

Open the updated bridge control page at **http://localhost:8787**. Enter your TikTok username, then use **Refresh from TikTok** in the catalogue to load every gift returned for that LIVE. This is the room's available list, which can vary; the offline starter list is explicitly labelled and is not the full catalogue. The last successful catalogue is cached for later use.

Search by gift name or coin price, click a gift, choose **Add blocks** or **Remove blocks**, enter the amount per gift, and pick an optional keybind. **Save & test** sends a simulated gift through the same path as live gifts. Settings are saved locally and synced to Roblox, including published games configured with Open Cloud. Keybinds work in the bridge window and in Roblox once synced; they do not fire while typing or using the settings panel. Duplicate keybinds are rejected. The keys on offer leave out I and O (Roblox's zoom keys) and P (the game's settings).

**Keybinds without the bridge.** In the game's **Y** panel, **GIFT KEYBINDS** lists every keybind and lets the streamer add their own: type the gift name (a gift rule with that name applies, otherwise its coins times rocks per coin) and its coins, press **Key: choose** and then the key, and press **Save keybind**. **X** removes one. Pressing the key in the game then sends that gift, with or without the bridge, through the same path as the test gifts. The free keys are B, C, F, J, K, L, M, N, Q, R, T, U, V, X, Z, 1 to 0 and F6 to F8 (W A S D, E, G, H, I, O, P and Y are kept for the game and Roblox). Up to 24 keybinds are kept and saved with the game. A keybind set in the game stays when the bridge resends its catalogue; the bridge only replaces its own.

Add gifts refill previously dug spaces, with stones flying and snapping into place. After refilling dug spaces, surplus blocks grow new connected rock outside the existing surface. Growth stops at GrowthMaxStone (1,500,000 by default), or twice the starting stone if larger, and never fills the diamond cell; a revealed diamond is moved above the restored surface. Gifts queued during a win/rebuild are applied in arrival order. Existing gifts keep removing blocks until you assign an Add rule. In the Y-menu's manual rules, negative amounts add and positive amounts remove.

## Rebuild tests

Rebuilding any rocks during a diamond hold cancels that hold, clears the countdown and lets the holder move again. Dug spaces refill from the diamond outward. Players covered by restored rock are lifted onto the new surface. A rebuild that actually restores at least 10,000 rocks moves the former holder to the highest restored rock surface instead. Each player's computer draws the returning rock a moment after the server restores it, so a player could land back in the old hole and have the rock appear round them. To stop that, for 6 seconds after any rebuild the server checks every 0.4 seconds whether anyone is standing inside rock and lifts them onto it. A player standing in a shaft they dug themselves is left alone. The diamond is released beside the player, above the rock, ready to click again for a fresh countdown. An add gift at the growth limit that restores zero rocks does not interrupt the hold. During the countdown, the holder sees a larger bright outlined gem above their palm; other players see an outlined diamond in the raised hand.

In the game's **Y settings panel**, scroll to **REBUILD TEST GIFTS**. Choose **+100**, **+1,000**, **+10,000**, **+50,000**, **+100,000**, or **Grow to limit**; each plays the next adding effect, from Pebble Drop to Mountain Rising. These tests work offline and always rebuild, regardless of existing gift rules. They refill previously dug spaces, then enlarge the mountain up to its growth limit, and preserve the round and wins. They also work on an undug mountain. The localhost bridge page has the same six buttons.

The gift catalogue refresh now accepts the username typed on the page directly, without first connecting live events. It loads every gift TikTok returns for that account, with no display limit, and caches the result. TikTok must be reachable and may require the account to be LIVE; the eight offline starter gifts are not a complete worldwide list.

## Gift performance and mountain growth

Gift mutations run through one ordered worker. Large blasts, restoration and growth yield between short chunks rather than doing all work in one frame. Animations start when a gift begins processing; the status shows queued work and the stone counter updates as work progresses. You can keep digging while a gift blasts or rebuilds the mountain. The diamond shows the moment a gift uncovers it, and you can pick it up straight away while the rest of the gift keeps blasting (not while a rebuild gift is refilling rock). Every change is sent to the players as one net change per rock, so overlapping gifts and digging never leave a destroyed block on screen. Round resets wait for the current mutation to finish. Players are kept above newly built surfaces.

**The server has no rock parts.** It keeps only the rock grid and streams compact change lists (column runs, 6 bytes each) to every client, which draws the rock itself. The server spends up to 8 ms of each frame on a gift (it draws nothing, so players never feel it), and each client at most a few milliseconds a frame on rock work, so a 100,000-rock gift opens its crater in about half a second instead of freezing the game. Rock parts cast no shadows and small scenery props (under 3 studs across) don't either, which takes the biggest load off the renderer. A 100,000-rock blast is about 23 KB of network traffic; it used to replicate thousands of parts. A 250,000-rock mountain needs about 13,400 parts (it used to need about 26,200): slope-shaped surface rock closes the shell by itself, so the hidden backing layer is gone. Cell occupancy, crater queues and growth frontiers use bit-packed buffers to avoid hash-table resize stalls.

Run `luau tests/gift-performance.luau` for a CPU checkpoint timing report and `python3 tests/mountain-sync.py` for client build and network sizes. Rendering cost and frame rate still need checking on the streaming PC.

## What you need

- A Windows PC with **Roblox Studio** (free from [create.roblox.com](https://create.roblox.com)).
- **Node.js LTS** (free from [nodejs.org](https://nodejs.org/en/download)). You only install it once.
- This folder: on GitHub click **Code → Download ZIP**, then extract it.

## Set up (once)

1. Install Node.js LTS.
2. Open the `bridge` folder and double-click **Start Bridge.bat**.
   - On the first run it installs the TikTok connector, which takes about a minute.
   - A black window stays open (that is the bridge), and the **control page** opens in your browser at http://localhost:8787.
   - The control page opens on a 3D sakura shrine: scroll down to reach the controls. Without a graphics card that supports WebGL, it shows a drawn version instead.
3. Double-click **DiamondRushTikTok.rbxlx** to open the game in Roblox Studio.
4. Press **Play** (F5) in Studio. You arrive in the royal lobby: press **JOIN** on **Diamond in the Rough** in the games menu on the left.
   - The control page should now say **Roblox: connected**.
   - The bottom-right of the game says what the TikTok connection is doing.
5. Try the **test gift buttons** on the control page. The mountain should blow up in the game.

If Studio says HTTP requests are off, use **Home → Game Settings → Security → Allow HTTP Requests**. It is already turned on in this file.

## Every stream

1. Go **LIVE on TikTok** first.
2. Start the bridge (**Start Bridge.bat**).
3. Type your TikTok username on the control page and press **Connect**.
   - It remembers your username, so next time it connects by itself.
4. Open the game in Roblox Studio, press **Play**, then **JOIN** Diamond in the Rough from the games menu.
5. Capture the Studio window in TikTok LIVE Studio or OBS.

## The lobby and the games menu

Players start in the lobby, a white and gold royal court floating high in the sky away from the mountain. A royal blue carpet leads from the spawn to a marble dais with a giant turning diamond. Marble columns with gold capitals ring the court, hung with royal blue banners with gold diamonds. A balustrade runs round the edge, and nobody can fall off.

The **GAMES** menu on the left of the screen lists the games:

- **Diamond in the Rough** shows what is happening right now (stone left, or that the diamond was found). Press **JOIN** to go to the mining camp.
- The other cards say **Coming soon**, ready for future games.

Beside the carpet stands a **How to Play** board (drawn, with no lettering). Walk up and press **E**, or click it, and a guide opens on screen with four pages: **Connect TikTok** (the bridge, the control page, HTTP requests and joining), **Testing** (the Y panel's test gifts, rebuild tests, the bird button and gift keybinds), **Controls** and **How to win**. The games menu's **How to play** button and the **H** key open it too, anywhere.

Press **Hide** to hide the menu. The **GAMES** tab on the left, or the **G** key, brings it back. The key matters in the game, where the mouse is locked to first person. While you play, the menu has **Back to lobby**. You can't go back while you are holding the diamond.

The mountain keeps going while you are in the lobby: gifts still blast it, and the game's display shows again as soon as you join. If you gave **G** to a gift keybind (see [Gift catalogue and keybinds](#gift-catalogue-and-keybinds)), G keeps doing that. To reach the menu in the game then, press **Y** to free the mouse and click the **GAMES** tab.

## Customise the win counter

While playing, press **Y** to open the hidden settings panel (only you, the owner, can open it; press Y again to close it). From there you can change:

- the title
- the number of wins (or press +1 / −1)
- a goal
- the text and background colours (like `#FFD700`)
- whether the counter is shown

The same panel can start a new round, reset the best time, change the starting stone, and send test gifts.

## Change what each gift does

In the **Y** panel:

- **Rocks per coin** sets what any gift without its own rule does (default 100 rocks per coin).
- **Rocks per like / follow / share** set those amounts.
- **Gift rules** give a gift its own amount: type the gift's name exactly as TikTok shows it (for example `Rose`, `Galaxy`) and how many rocks it removes per gift, then press **Add / change gift rule**. Press **X** to delete a rule. Names are not case-sensitive.

Everything is saved with your other settings.

## Blender scenery

The mountains, trees, rocks and undergrowth around the arena are real 3D meshes made in Blender, not Roblox parts. They are already inside the place file, so **there is nothing to import**: press **Play** and the game builds them itself. It takes a few seconds, smallest meshes first, spread out so the game keeps running smoothly. The Output window says *Scenery: building the Blender pack in game*, then *built 25 of 25 Blender meshes*.

![The valley as the game lays it out, rendered in Blender from the camp](art/previews/game_view.png)

![The trees, bushes, rocks and logs in the pack](art/previews/assets.png)

The preview pictures are Blender renders. Roblox's own lighting, haze and terrain textures will look a little different.

This uses Roblox's EditableMesh, which always works in Studio. A [published game](#playing-the-published-game-instead-of-studio-optional) may only use it once you are 13+ age-verified and ID-verified, and have turned on **Enable Mesh / Image APIs** for the experience in the [Creator Dashboard](https://create.roblox.com/dashboard/creations). Until then the published game uses its built-in scenery, and the Output window says so.

If you can't turn that on, import the pack as normal meshes instead. This works in any published game:

1. Open **DiamondRushTikTok.rbxlx** in Roblox Studio (you need to be logged in).
2. Click **File → Import**, and choose **art/DiamondRushScenery.fbx** from this folder.
3. In the import window keep the default settings. Leave **Merge Meshes** off and the name as **DiamondRushScenery**. Ticking **Anchored** is a good idea. Click **Import**.
4. A row of mountains, trees and rocks appears in the Workspace. Leave it there: when the game runs, it moves the pack out of sight and builds the valley from it. You can also drag **DiamondRushScenery** into **ServerStorage**.
5. Save the place (**Ctrl+S**) and publish it. The Output window says *Scenery: using the imported Blender pack*.

An imported pack is used instead of building the meshes in game.

## Leaderboards and gold statues

The two leaderboards fill up by themselves as viewers send gifts. A gift counts for **Top Helpers** when it removes rock and for **Top Griefers** when its gift rule adds stone; either way the board adds the gift's coin value. In the **Y** panel:

- **Preview with sample names** fills both boards with made-up viewers for 20 seconds, so you can check them before going live.
- **Reset top helpers** / **Reset top griefers** clear a board (click twice to confirm), for example at the start of a new stream.

To place a **gold statue**, stand where you want it (outside the mountain area), face that spot and open the **Y** panel. Under **GOLD STATUES**, type the gifter's name and how many coins they sent, then press **Place statue in front of me**. The statue appears a few steps ahead, facing you. Up to 12 statues are kept.

To **remove a statue**, use any of these in the same section. Each button needs a second click to confirm, so a stray click never removes anything:

- **Remove the statue nearest me**: walk up to the statue, open the **Y** panel and press it.
- **Remove** next to a name in the **Your statues** list.
- **Remove all statues** clears every statue.

Like wins and best times, statues and leaderboard totals are remembered between sessions, in each player's own save, once the game is published to Roblox and **Enable Studio Access to API Services** is on (Game Settings → Security).

You can also type these in the Roblox chat:

| Command | What it does |
| --- | --- |
| `/wins 5` | Set wins to 5 |
| `/wins +1` / `/wins -1` | Add or take away a win |
| `/title MY WINS` | Change the counter's title |
| `/goal 10` | Show `WINS: 3/10` (use `/goal 0` to hide the goal) |
| `/stone 500000` | Starting stone for the next round |
| `/newround` | Start a fresh mountain now |
| `/gift 30 2` | Test: pretend someone sent 2 gifts worth 30 coins |

Wins, colours and the best time are saved once the game is published to Roblox and **Enable Studio Access to API Services** is on (Game Settings → Security). Without that they still work, but reset when you stop.

## Change the numbers

In Studio, open **ReplicatedStorage → DiamondRush → Config**:

| Setting | Default | Meaning |
| --- | --- | --- |
| `StartingStone` | 250000 | Rocks in each new mountain (one rock = one stone, up to 1,500,000) |
| `GrowthMaxStone` | 1500000 | Maximum growth, or twice starting stone if larger |
| `StonePerCoin` | 100 | Stone removed per TikTok coin |
| `StonePerLike` / `StonePerFollow` / `StonePerShare` | 2 / 500 / 300 | Stone for likes, follows and shares |
| `HoldSeconds` | 15 | Real seconds the diamond must be held |
| `HoldCountFrom` | 10 | Number the countdown starts at |
| `HoldSlowdown` | 0.6 | 0 = even countdown, 1 = slows down a lot at the end |
| `WinScreenSeconds` | 4 | How long the win screen shows |
| `BlockSize` | 0.4 | Size of one rock in studs; the diamond is about twice that when found |
| `DigPerSecond` | 100 | Rocks dug per second while holding the dig button |

With the defaults, clearing the whole mountain takes 2,500 coins of gifts. The diamond often shows up before that, depending on where the blasts land.

## Playing the published game instead of Studio (optional)

A published Roblox server cannot reach the bridge on your PC, so the bridge sends events through Roblox **Open Cloud** instead:

1. Publish the place (File → Publish to Roblox).
2. At [create.roblox.com](https://create.roblox.com) go to **Open Cloud → API Keys → Create API Key**:
   - Add **Messaging Service** with the **publish** permission for your experience.
   - Set **Accepted IP Addresses** to `0.0.0.0/0`.
   - Copy the key.
3. On your experience's page use **⋯ → Copy Universe ID**.
4. On the control page, open **Published game (optional)**, paste both and press **Save**.

The game listens on the topic `DiamondRushTikTok`. Studio keeps working at the same time.

The game is **single player** (`SinglePlayer = true` in `src/shared/Config.luau`). Whoever plays is treated as the streamer and gets the **Y** panel, test gifts and gift keybinds. **Each player has their own save**: statues, wins, the win counter's look, best time, leaderboards, map theme, skin, gift rules and keybinds. The server waits for its player, then loads that player's save (stored as `player_<user id>`). A player's first visit starts from the game's older shared save, so nothing built before this change is lost. Set the published game's maximum players to 1: a second player in the same server would be saving into the first player's save. Set `SinglePlayer = false` to go back to one shared save and owner-and-Admins only.

To show the Blender mountains and trees in the published game, also turn on **Enable Mesh / Image APIs** (see [Blender scenery](#blender-scenery)).

## Troubleshooting

- **"Bridge app not running"** in the game: start **Start Bridge.bat** and keep its window open.
- **TikTok "is not live right now"**: go live first. The bridge retries every 20 seconds by itself.
- **TikTok "could not connect"**: check the username (no @ needed). TikTok sometimes rate-limits; wait a minute.
- **Nothing happens on gifts but test gifts work**: make sure the control page says *connected to @yourname*.
- **The page says "waiting for Roblox Studio"**: press Play in Studio. HTTP requests must be allowed (see above).
- **No mountain in Studio's Server view**: that is expected. Each player's client draws the rock; switch back to the Client view. Use **Play** (F5), not **Run** (F8), which has no client.
- **No Blender mountains or trees in the published game**: Roblox only lets a published game build meshes once Mesh / Image APIs are turned on. See [Blender scenery](#blender-scenery) for that, or for importing the pack instead.
- **The world looks flat or old-fashioned**: open the place file from this folder. It sets Future lighting and the 2022 material pack, which scripts cannot change. In an older copy, set **Lighting → LightingStyle** to Realistic and **MaterialService → Use2022Materials** on.

## For developers

The source is a [Rojo](https://rojo.space) project:

- `src/shared`: config, the rock grid, rock shapes and looks, the network codec, the diamond shape, the hold countdown curve, formatting, and the Blender scenery meshes with their unpacker.
- `src/server`: rounds, the authoritative mountain grid, the diamond, scenery, the royal lobby (`Lobby`), the TikTok feed and saving.
- `src/client`: the mountain renderer (`MountainView`), the scenery mesh builder (`SceneryView`), the games menu (`LobbyView`), first-person hands, effects, the on-screen display and the settings panel.

Rebuild the place with `python3 tools/build_place.py` (or `rojo build -o DiamondRushTikTok.rbxlx`), or use `rojo serve` with the Studio plugin while editing. `python3 tools/build_place.py --check` fails if the committed place is out of date; `--sourcemap` writes a `sourcemap.json` for luau-lsp.

- Logic tests: `luau tests/run.luau`, `luau tests/mountain-shape.luau`, `luau tests/diamond-rebuild.luau` (Luau CLI).
- Server/client sync and watertight rock: `python3 tests/mountain-sync.py [path/to/luau]`.
- Scenery: `python3 tests/scenery.py [path/to/luau]`.
- Scenery meshes and their unpacker: `python3 tests/scene-pack.py [path/to/luau]`.
- Leaderboards and statues: `python3 tests/showcase.py [path/to/luau]`.
- The diamond bird and its double-gifts bonus: `python3 tests/diamond-bird.py [path/to/luau]`.
- Every gift tier's effect on a simulated clock (budgets, cleanup, camera shake): `python3 tests/gift-effects.py [path/to/luau]`.
- The lobby and the games menu's status line: `python3 tests/lobby.py [path/to/luau]`.

The Blender scenery pack is generated by `art/scenery_assets.py` (no hand-made files): every mesh is closed, vertex-coloured, under Roblox's 20,000-triangle limit, and modelled at real size. Rebuild it with `pip install bpy` (Python 3.11), then `python art/scenery_assets.py`, or with `blender --background --python art/scenery_assets.py`. This writes `src/shared/ScenePackData.luau`, the `.fbx`, `art/manifest.json` and the preview renders. `ScenePackData` holds each mesh as quantised, delta-coded geometry with a colour palette, compressed with DEFLATE and stored as base64: about 290 KB for 72,000 triangles. `python3 tests/scenery.py --dump` writes the game's layout so the build also renders `art/previews/game_view.png`.

In the game, the server's `ScenePack.luau` lays the pack out and sends the placements to each player. Each player's `SceneryView.luau` then unpacks the meshes (`Inflate.luau`, `MeshPack.luau`) and builds them with EditableMesh, one per mesh, shared by all its copies. An imported `.fbx` takes priority: `ScenePack` finds it and sizes each copy from a reference tree, so it works whatever units or up-axis the importer used. `tests/scene-pack.py` checks the unpacker against Python's zlib, and checks every mesh: closed, facing outward, and with the right sizes and colours. `tests/scenery.py` checks the valley when the meshes are built in game, when they are imported, and without them.
- Bridge tests: `npm test` inside `bridge/`.
- The control page (`bridge/control.html`) draws its 3D sakura shrine with three.js, which the bridge serves from `bridge/vendor/` (MIT licence in `vendor/three.LICENSE`) so it works offline. The stone, paint, tile, bark and blossom textures are painted from noise when the page opens, so there are no image files to ship.

TikTok events come from the community [tiktok-live-connector](https://github.com/zerodytrash/TikTok-Live-Connector) package, which is not an official TikTok API.

### How 250,000 rocks stay fast

Every stone is a real rock, but only the rocks on the outside of the mountain exist as Roblox parts (about 13,400), and only on each player's own client. Rocks inside are kept as numbers and get a part the instant digging uncovers them, so the mountain always looks solid and the counter always matches. The server keeps the authoritative grid, checks digging and the diamond's sightline against it, and sends each client a snapshot when it joins plus a change list for every blast, dig and rebuild. Surface rocks slope towards open air only where every face they leave open borders air or another drawn rock, so the drawn shell stays watertight without a second layer behind it.

