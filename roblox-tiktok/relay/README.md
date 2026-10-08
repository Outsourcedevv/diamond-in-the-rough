# Diamond Rush relay (Cloudflare)

The relay carries each streamer's TikTok gifts from their connector (DiamondRushBridge.exe) to their Roblox game:

```
TikTok LIVE  ->  DiamondRushBridge.exe (the streamer's PC)  ->  relay (Cloudflare)  <-  that streamer's Roblox game
```

There are no keys anywhere. Each connector has a secret made on its PC, and its **game code** comes from that secret, so only that connector can send gifts under the code. The game asks the relay for its code's gifts. Events are kept for ten minutes.

It is one file, [`worker.js`](worker.js), and runs on Cloudflare Workers' free plan with a small D1 database.

## Set it up (once, about 10 minutes, all in the browser)

Use a Cloudflare account just for the game (free limits are per account).

1. Sign up or log in at **https://dash.cloudflare.com**.
2. **Make the database.** In the left menu open **Storage & Databases → D1 SQL Database**, press **Create**, name it `diamond-rush` and press **Create**.
3. **Make the Worker.** In the left menu open **Compute (Workers) → Workers & Pages**, press **Create**, choose **Start with Hello World!**, name it `diamond-rush-relay` and press **Deploy**. (The first time, Cloudflare asks you to pick your `workers.dev` subdomain: pick something neutral, like the game's name.)
4. **Paste the relay.** Press **Edit code**, delete everything in the editor, paste the whole of `worker.js`, and press **Deploy**.
5. **Connect the database.** Go back to the Worker, open **Settings → Bindings**, press **Add**, choose **D1 database**, set **Variable name** to `DB` (capitals), pick `diamond-rush`, and save. Cloudflare deploys it again.
6. **Check it.** Open the Worker's address, `https://diamond-rush-relay.<your-subdomain>.workers.dev`. It should say **Diamond Rush relay is running.**

Then put that address in `RELAY_URL` in `bridge/cloud.mjs` and `RelayUrl` in `src/shared/Config.luau`, rebuild DiamondRushBridge.exe and the place, and publish the game.

## Update it

When `worker.js` changes: open the Worker in Cloudflare, press **Edit code**, delete everything in the editor, paste the whole of the new `worker.js`, and press **Deploy**. The database and its binding stay as they are.

## Limits on the free plan

- 100,000 Worker requests a day. A game asks about every 8 seconds while nothing happens and straight away after each gift, and a connector pushes after gifts and every 15 seconds, so one streamer uses roughly 1,000 to 2,000 requests an hour: about 50 to 100 streaming hours a day across everyone.
- D1: 5 million rows read and 100,000 rows written a day; each gift is one row written.
- If the game outgrows that, Cloudflare's Workers Paid plan ($5 a month) raises every limit a long way.

## Endpoints

- `POST /c/CODE/push` with header `x-relay-secret` and body `{ events, rules, tiktok }`.
- `GET /c/CODE/events?since=N&wait=S&start=0|1` returns `{ session, last, tiktok, events }`. `start=1` (a game that just started) returns the newest event number, not older gifts (plus any rules an older connector stored; the game ignores them, as gift settings are kept in the game). After that the game asks with `start=0` for the events after that number, even when it is 0. Without `start` (games from before it), `since=0` means start. With `wait`, the relay holds the request up to 8 seconds until something arrives. Old events are deleted after ten minutes, except the newest, so the newest event number never drops back to 0.

Run the tests with `node --test relay/worker.test.mjs` (Node 22, using SQLite in place of D1).
