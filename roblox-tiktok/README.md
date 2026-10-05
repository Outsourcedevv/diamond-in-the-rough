# Diamond Rush: TikTok Live Roblox game

A Roblox version of Diamond in the Rough made for TikTok LIVE. A big mountain made of **250,000 rocks** (one rock is one stone) is shown counting down at the top of the screen. The rock slopes smoothly towards open air, with snow on the summit, grassy foothills over a dirt layer and layered stone inside: finding the one small diamond should feel like finding a needle in a haystack. Every gift, like, follow and share from your viewers blasts stone out of it. Once the diamond is exposed, find it, click it and **hold it for 15 seconds** to win.

- **Stone counter.** The top of the screen shows how much stone is left (250,000 to start), with a progress bar.
- **Gifts blast the mountain.** Each TikTok coin removes 100 rocks, so a Rose (1 coin) removes 100 and a Galaxy (1,000 coins) removes 100,000. The counter always equals the rocks really left. Likes, follows and shares also chip away. Big gifts make big explosions. A feed in the corner shows who sent what.
- **Gift animations.** Total coins (gift price × combo count) scale the effects: 1–9 sparks, 10–99 shockwaves, 100–499 Diamond Fracture (cyan cracks spread over the remaining rock, flash into a pulse, and release sparkling fragments), 500–999 orbital strikes, 1,000–9,999 galaxy collapses, and 10,000+ a cosmic burst with a light column and rising rings. Shockwaves use smooth expanding light rings; meteors accelerate along curved paths with tapered trails, flashes and arcing debris. A brief banner shows the sender, gift and coin value. Gift blasts only remove mountain stones: they never target the diamond. The gem settles above the actual visible stone or ground after each blast. Effects are cosmetic, do not block digging, and are capped at two simultaneous sequences and 80 live effect parts; expensive gifts take priority. The Y-panel has 12 test presets, including Hand Hearts, Money Gun, Lion and gift combos, with total test coins shown on each button. The bridge control page includes the same presets. Test gifts use these same effects.
- **Find and click the diamond.** The uncovered message tells you when it can be found, but there is no floating location label, through-rock outline or light beacon. Aim directly at the gem and left-click (tap on mobile) within 12 studs. Walking into it and pressing E do not pick it up; rocks cannot be clicked through.
- **Hold the diamond.** The gem flies from where it lay into your right hand, your hand lifts it high and your view eases upward, framing a large, sparkling diamond against the sky. The eight-sided gem has a pale crown, a bright table and a deeper blue pointed base, so it reads clearly as a diamond on stream. A visible palm, thumb and curled fingers grip it. **You cannot move while holding it:** you stay frozen in place until you win or a rebuild gift cancels the hold. The countdown occupies the top-centre HUD while holding, leaving the hand and gem clear below it. Other players see a big sparkling diamond in your avatar's raised hand.
  - A big countdown shows **10 → 0**, but it really takes **15 seconds**: the numbers tick fast at first and slow down near the end.
  - If you fall or leave, the diamond drops.
- **Scenery.** An alpine valley in smooth terrain: grassy meadows with animated grass, forested hills, a lake with a dock, terrain boulders and a ring of rocky, snow-capped peaks. Low-poly pines (snow-dusted higher up) and birches, and a log-cabin mining camp with a porch, warm windows, a campfire, lanterns and a trail sign. The place uses Future lighting and Roblox's 2022 material pack, with atmosphere haze, sun rays, bloom and a gentle colour grade.
- **Win counter.** It sits at the top right and is fully customisable: title, number, an optional goal (e.g. `WINS: 3/10`), text colour and background colour. It is saved between streams.
- **Win screen.** It shows for 4 seconds with **This round's time** and **Best round's time** (and ⭐ NEW BEST! when you beat it). Then the mountain rebuilds from base to peak in 16 waves, with flying stones snapping into place and a final glint at the summit. Gifts arriving during the rebuild are saved and applied when digging resumes.
- **Aim at stone.** A small dot marks the centre of the screen. The surface rock directly under it gets a white outline; the outline follows the same target used for digging and disappears when aiming away or opening settings.
- **Dig with your hands.** First-person view with two hands: hold the left mouse button on the mountain and your hands alternate between reaching, scooping and pulling rubble back, removing about 100 rocks a second. Connected, hinged fingers curl during the scoop; sleeves meet the palms, and the real avatar arms are hidden locally to prevent duplicate floating limbs; the animation pauses when you aim away from reachable stone.

## Gift catalogue and keybinds

Open the updated bridge control page at **http://localhost:8787**. Enter your TikTok username, then use **Refresh from TikTok** in the catalogue to load every gift returned for that LIVE. This is the room's available list, which can vary; the offline starter list is explicitly labelled and is not the full catalogue. The last successful catalogue is cached for later use.

Search by gift name or coin price, click a gift, choose **Add blocks** or **Remove blocks**, enter the amount per gift, and pick an optional keybind. **Save & test** sends a simulated gift through the same path as live gifts. Settings are saved locally and synced to Roblox, including published games configured with Open Cloud. Keybinds work in the bridge window and in Roblox for admins once synced; they do not fire while typing or using the settings panel. Duplicate keybinds are rejected.

Add gifts refill previously dug spaces, with stones flying and snapping into place. After refilling dug spaces, surplus blocks grow new connected rock outside the existing surface. Growth stops at GrowthMaxStone (1,500,000 by default), or twice the starting stone if larger, and never fills the diamond cell; a revealed diamond is moved above the restored surface. Gifts queued during a win/rebuild are applied in arrival order. Existing gifts keep removing blocks until you assign an Add rule. In the Y-menu's manual rules, negative amounts add and positive amounts remove.

## Rebuild tests

Rebuilding any rocks during a diamond hold cancels that hold, clears the countdown and lets the holder move again. Dug spaces refill from the diamond outward. Players covered by restored rock are lifted onto the new surface. A rebuild that actually restores at least 10,000 rocks moves the former holder to the highest restored rock surface instead. The diamond is released beside the player, above the rock, ready to click again for a fresh countdown. An add gift at the growth limit that restores zero rocks does not interrupt the hold. During the countdown, the holder sees a larger bright outlined gem above their palm; other players see an outlined diamond in the raised hand.

In the game's **Y settings panel**, scroll to **REBUILD TEST GIFTS**. Choose **+1,000**, **+10,000**, **+100,000**, or **Grow to limit**. These tests work offline and always rebuild, regardless of existing gift rules. They refill previously dug spaces, then enlarge the mountain up to its growth limit, and preserve the round and wins. They also work on an undug mountain. The localhost bridge page has the same four buttons.

The gift catalogue refresh now accepts the username typed on the page directly, without first connecting live events. It loads every gift TikTok returns for that account, with no display limit, and caches the result. TikTok must be reachable and may require the account to be LIVE; the eight offline starter gifts are not a complete worldwide list.

## Gift performance and mountain growth

Gift mutations run through one ordered worker. Large blasts, restoration and growth yield between short chunks rather than doing all work in one frame. Animations start when a gift begins processing; the status shows queued work and the stone counter updates as work progresses. Digging and diamond pickup wait while rock changes are reconciled. Round resets wait for the current mutation to finish. Players are kept above newly built surfaces.

**The server has no rock parts.** It keeps only the rock grid and streams compact change lists (column runs, 6 bytes each) to every client, which draws the rock itself. Each client spends at most a few milliseconds a frame on rock work, so a huge gift opens its crater over a second or so instead of freezing the game. A 100,000-rock blast is about 23 KB of network traffic; it used to replicate thousands of parts. A 250,000-rock mountain needs about 13,400 parts (it used to need about 26,200): slope-shaped surface rock closes the shell by itself, so the hidden backing layer is gone. Cell occupancy, crater queues and growth frontiers use bit-packed buffers to avoid hash-table resize stalls.

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
3. Double-click **DiamondRushTikTok.rbxlx** to open the game in Roblox Studio.
4. Press **Play** (F5) in Studio.
   - The control page should now say **Roblox: connected**.
   - The bottom-right of the game says what the TikTok connection is doing.
5. Try the **test gift buttons** on the control page. The mountain should blow up in the game.

If Studio says HTTP requests are off, use **Home → Game Settings → Security → Allow HTTP Requests**. It is already turned on in this file.

## Every stream

1. Go **LIVE on TikTok** first.
2. Start the bridge (**Start Bridge.bat**).
3. Type your TikTok username on the control page and press **Connect**.
   - It remembers your username, so next time it connects by itself.
4. Open the game in Roblox Studio and press **Play**.
5. Capture the Studio window in TikTok LIVE Studio or OBS.

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
- **Gift rules** give a gift its own amount: type the gift's name exactly as TikTok shows it (for example `Rose`, `Galaxy`) and how many rocks it removes per gift, then press **Add / change gift rule**. Press ✕ to delete a rule. Names are not case-sensitive.

Everything is saved with your other settings.

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

## Troubleshooting

- **"Bridge app not running"** in the game: start **Start Bridge.bat** and keep its window open.
- **TikTok "is not live right now"**: go live first. The bridge retries every 20 seconds by itself.
- **TikTok "could not connect"**: check the username (no @ needed). TikTok sometimes rate-limits; wait a minute.
- **Nothing happens on gifts but test gifts work**: make sure the control page says *connected to @yourname*.
- **The page says "waiting for Roblox Studio"**: press Play in Studio. HTTP requests must be allowed (see above).
- **No mountain in Studio's Server view**: that is expected. Each player's client draws the rock; switch back to the Client view. Use **Play** (F5), not **Run** (F8), which has no client.
- **The world looks flat or old-fashioned**: open the place file from this folder. It sets Future lighting and the 2022 material pack, which scripts cannot change. In an older copy, set **Lighting → LightingStyle** to Realistic and **MaterialService → Use2022Materials** on.

## For developers

The source is a [Rojo](https://rojo.space) project:

- `src/shared`: config, the rock grid, rock shapes and looks, the network codec, the diamond shape, the hold countdown curve and formatting.
- `src/server`: rounds, the authoritative mountain grid, the diamond, scenery, the TikTok feed and saving.
- `src/client`: the mountain renderer (`MountainView`), first-person hands, effects, the on-screen display and the settings panel.

Rebuild the place with `python3 tools/build_place.py` (or `rojo build -o DiamondRushTikTok.rbxlx`), or use `rojo serve` with the Studio plugin while editing. `python3 tools/build_place.py --check` fails if the committed place is out of date; `--sourcemap` writes a `sourcemap.json` for luau-lsp.

- Logic tests: `luau tests/run.luau`, `luau tests/mountain-shape.luau`, `luau tests/diamond-rebuild.luau` (Luau CLI).
- Server/client sync and watertight rock: `python3 tests/mountain-sync.py [path/to/luau]`.
- Scenery: `python3 tests/scenery.py [path/to/luau]`.
- Bridge tests: `npm test` inside `bridge/`.

TikTok events come from the community [tiktok-live-connector](https://github.com/zerodytrash/TikTok-Live-Connector) package, which is not an official TikTok API.

### How 250,000 rocks stay fast

Every stone is a real rock, but only the rocks on the outside of the mountain exist as Roblox parts (about 13,400), and only on each player's own client. Rocks inside are kept as numbers and get a part the instant digging uncovers them, so the mountain always looks solid and the counter always matches. The server keeps the authoritative grid, checks digging and the diamond's sightline against it, and sends each client a snapshot when it joins plus a change list for every blast, dig and rebuild. Surface rocks slope towards open air only where every face they leave open borders air or another drawn rock, so the drawn shell stays watertight without a second layer behind it.

