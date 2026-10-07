# The Diamond Rush relay

One published Roblox game, any number of streamers, each getting their own
TikTok gifts. The game's owner hosts this once; every streamer just runs the
bridge on their own PC as usual.

Without the relay, a published game can only be fed by its owner's Open Cloud
key, and every gift goes to every server. The relay fixes both: a streamer's
bridge sends their events under their own **game code**, and their Roblox
server reads only that code.

```
TikTok LIVE  ->  bridge (streamer's PC)  ->  relay (hosted once)  ->  the streamer's game server
```

## What a streamer does

1. Run the bridge (**Start Bridge**) and connect their TikTok username as usual.
2. On the control page at <http://localhost:8787>, under **Playing the
   published game**, paste the relay address the game's owner gave them and
   press Save. The page then shows their **game code**, eight characters such
   as `ABCD EFGH`.
3. In the game, press **Y**, scroll to **GAME CODE** and type it in.

The code comes from a secret kept in the bridge's `config.json` on that PC, so
nobody else can send gifts under it. It stays the same every time, unless that
file is deleted.

## Hosting the relay

It is one file with no dependencies and no database. Node 20 or newer.

```bash
cd roblox-tiktok/relay
node relay.mjs          # listens on PORT, or 8788
npm test                # the relay's own tests
```

It must be reachable over HTTPS from Roblox's servers, so it needs hosting with
a public address. Any small Node host works (Render, Railway, Fly.io, a cheap
VPS). The start command is `node relay.mjs`, and the host's `PORT` is used
automatically. Memory use is small: a few hundred recent events per streamer,
nothing on disk.

Then, in the game:

- Turn on **Game Settings > Security > Allow HTTP Requests**, so Roblox may
  reach the relay.
- Put the address in `src/shared/Config.luau` as `RelayUrl`, so every streamer
  only needs their code. A streamer can also type it in the Y panel under
  **RELAY ADDRESS**.

## What it does and doesn't do

- Events live in memory for a few minutes and are then dropped. Nothing is
  written to disk, and no account is created.
- A game code is 8 characters worked out from the bridge's secret. Sending
  gifts needs the secret; reading a code's events needs only the code, so a
  streamer should keep theirs to themselves.
- One bridge owns a code. A second bridge claiming it is refused.
- A game's request is held open until a gift arrives (up to 15 seconds), so
  gifts land about as quickly as they do in Studio.
- Limits are in `LIMITS` in `relay.mjs`: 500 recent events per streamer, 300
  per push, 5,000 streamers at once.

## The two routes it talks

```
POST /c/CODE/push      header: x-relay-secret
     { events: [...], rules: [...], tiktok: "connected to @name" }

GET  /c/CODE/events?since=N&session=S&wait=15
  -> { session, last, tiktok, events: [...] }
```

`events` are the same events the bridge serves on its own `/events`, so the
game reads both the same way.
