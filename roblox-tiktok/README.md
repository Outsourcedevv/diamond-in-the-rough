# Diamond Rush: TikTok Live Roblox game

A Roblox version of Diamond in the Rough made for TikTok LIVE. A big mountain made of **250,000 tiny rocks** (one rock is one stone) is shown counting down at the top of the screen. Every gift, like, follow and share from your viewers blasts stone out of it. Somewhere inside is **one diamond**. Once it is exposed, grab it and **hold it for 15 seconds** to win.

- **Stone counter.** The top of the screen shows how much stone is left (250,000 to start), with a progress bar.
- **Gifts blast the mountain.** Each TikTok coin removes 100 rocks, so a Rose (1 coin) removes 100 and a Galaxy (1,000 coins) removes 100,000. The counter always equals the rocks really left. Likes, follows and shares also chip away. Big gifts make big explosions. A feed in the corner shows who sent what.
- **Hold the diamond.** When it is uncovered, a banner says "THE DIAMOND IS EXPOSED — GRAB IT!". Walk into it (or press E) to lift it above your head.
  - A big countdown shows **10 → 0**, but it really takes **15 seconds**: the numbers tick fast at first and slow down near the end.
  - If you fall or leave, the diamond drops.
- **Win counter.** It sits at the top right and is fully customisable: title, number, an optional goal (e.g. `WINS: 3/10`), text colour and background colour. It is saved between streams.
- **Win screen.** It shows for 4 seconds with **This round's time** and **Best round's time** (and ⭐ NEW BEST! when you beat it). Then a fresh mountain appears.
- **Dig with your hands.** First-person view with two hands: click a rock to punch it out (one rock each).

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

While playing, click **⚙ Settings** under the win counter (only you, the owner, can see it). From there you can change:

- the title
- the number of wins (or press +1 / −1)
- a goal
- the text and background colours (like `#FFD700`)
- whether the counter is shown

The same panel can start a new round, reset the best time, change the starting stone, and send test gifts.

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
| `StonePerCoin` | 100 | Stone removed per TikTok coin |
| `StonePerLike` / `StonePerFollow` / `StonePerShare` | 2 / 500 / 300 | Stone for likes, follows and shares |
| `HoldSeconds` | 15 | Real seconds the diamond must be held |
| `HoldCountFrom` | 10 | Number the countdown starts at |
| `HoldSlowdown` | 0.6 | 0 = even countdown, 1 = slows down a lot at the end |
| `WinScreenSeconds` | 4 | How long the win screen shows |
| `BlockSize` | 1 | Size of one rock in studs; the diamond is the same size |

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

## For developers

The source is a [Rojo](https://rojo.space) project:

- `src/shared`: config, the hold countdown curve and formatting.
- `src/server`: rounds, the mountain, the diamond, the TikTok feed and saving.
- `src/client`: the on-screen display and the settings panel.

Rebuild the place with `rojo build -o DiamondRushTikTok.rbxlx`, or use `rojo serve` with the Studio plugin while editing.

- Logic tests: `luau tests/run.luau` (Luau CLI).
- Bridge tests: `npm test` inside `bridge/`.

TikTok events come from the community [tiktok-live-connector](https://github.com/zerodytrash/TikTok-Live-Connector) package, which is not an official TikTok API.

### How 250,000 rocks stay fast

Every stone is a real rock, but only the rocks on the outside of the mountain exist as Roblox parts (about 14,000). Rocks inside are kept as numbers and get a part the instant digging uncovers them, so the mountain always looks solid and the counter always matches.
