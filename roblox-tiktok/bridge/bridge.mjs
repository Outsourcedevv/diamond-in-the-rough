// DIAMOND RUSH TikTok bridge.
// Connects to a TikTok LIVE and hands gifts, likes, follows and shares to the
// Roblox game. The published game reads them from the Diamond Rush relay,
// under this PC's game code (see cloud.mjs and relay/worker.js); Roblox Studio
// can also poll http://localhost:8787/events.
// Open http://localhost:8787 for the control page (connect + test gifts).
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createEventQueue, createGiftTracker, likeEvent, socialEvent, CONNECT_OPTIONS } from './events.mjs';
import { codeFor, RELAY_URL, placeVersionUrl, placeFileType } from './cloud.mjs';
import { randomBytes } from 'node:crypto';

// Packaged as DiamondRushBridge.exe (see tools/build-exe.mjs): settings sit next
// to the .exe and the control page comes from inside it.
const packaged = typeof globalThis.__DIAMOND_RUSH_SEA__ === 'object';
const here = packaged ? path.dirname(process.execPath) : path.dirname(fileURLToPath(import.meta.url));
function asset(name) {
  return packaged ? globalThis.__DIAMOND_RUSH_SEA__.asset(name) : fs.readFileSync(path.join(here, name));
}
const configPath = path.join(here, 'config.json');
const defaults = {
  tiktokUsername: '',
  port: 8787,
  // This PC's own secret: the game code comes from it (see cloud.mjs).
  secret: '',
};

function loadConfig() {
  let config;
  try {
    const saved = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    config = { ...defaults, ...saved };
    // Older saves kept the secret with the relay settings; the code stays the same.
    if (!config.secret && typeof saved.relay?.secret === 'string') config.secret = saved.relay.secret;
    delete config.relay;
    delete config.openCloud;
    delete config.ownerCloud; // the Roblox messaging key is no longer used
    // Gift rules used to be set on this page. The game's own gift settings
    // (the gift button in the game) replaced them, so older saves drop them.
    delete config.giftRules;
    delete config.climbRules;
    delete config.chalkRules;
  } catch {
    config = structuredClone(defaults);
  }
  // This PC's secret, made once. The game code is worked out from it.
  if (typeof config.secret !== 'string' || config.secret.length < 32) config.secret = randomBytes(24).toString('hex');
  return config;
}

function saveConfig() {
  fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`);
}

const config = loadConfig();
saveConfig(); // keeps this PC's secret (and its game code) for next time
const queue = createEventQueue();
const handleGift = createGiftTracker();
const recent = [];
let tiktokStatus = 'not connected';
let connection = null;
let reconnectTimer = null;
let lastRobloxPoll = 0;
// What waits to go to the relay (see "The relay" below).
const relayQueue = [];

function log(line) {
  const stamp = new Date().toLocaleTimeString();
  console.log(`[${stamp}] ${line}`);
}

function emit(event) {
  if (!event) return;
  const stamped = queue.push(event);
  const { seq, ...compact } = stamped;
  relayQueue.push(compact);
  if (relayQueue.length > 2000) relayQueue.splice(0, relayQueue.length - 2000);
  recent.unshift({ at: Date.now(), ...stamped });
  recent.length = Math.min(recent.length, 30);
  const what = event.type === 'gift' ? `${event.gift} x${event.count} (${event.coins} coins each)` : event.type === 'like' ? `${event.likes} likes` : event.type;
  log(`${event.name}: ${what}`);
}

// TikTok ----------------------------------------------------------------------
async function connectTikTok(username) {
  clearTimeout(reconnectTimer);
  if (connection) {
    const old = connection;
    connection = null;
    await old.disconnect().catch(() => {});
  }
  username = String(username ?? '').trim().replace(/^@/, '');
  if (!username) {
    tiktokStatus = 'not connected (enter your TikTok username)';
    return;
  }
  const { TikTokLiveConnection, WebcastEvent, ControlEvent } = await import('tiktok-live-connector');
  const live = new TikTokLiveConnection(username, CONNECT_OPTIONS);
  connection = live;
  tiktokStatus = `connecting to @${username}…`;
  live.on(WebcastEvent.GIFT, (data) => {
    emit(handleGift(data));
  });
  live.on(WebcastEvent.LIKE, (data) => emit(likeEvent(data)));
  live.on(WebcastEvent.FOLLOW, (data) => emit(socialEvent('follow', data)));
  live.on(WebcastEvent.SHARE, (data) => emit(socialEvent('share', data)));
  live.on(WebcastEvent.STREAM_END, () => {
    tiktokStatus = `@${username}'s live has ended`;
    log(tiktokStatus);
  });
  live.on(ControlEvent.DISCONNECTED, () => {
    if (connection !== live) return;
    tiktokStatus = `reconnecting to @${username}…`;
    log('TikTok disconnected; retrying in 10 seconds');
    reconnectTimer = setTimeout(() => connectTikTok(username), 10000);
  });
  try {
    await live.connect();
    if (connection === live) {
      tiktokStatus = `connected to @${username}`;
      log(`Connected to @${username}'s LIVE`);
    }
  } catch (error) {
    if (connection !== live) return;
    const reason = error?.name === 'UserOfflineError' ? 'is not live right now' : `could not connect (${error?.message ?? error})`;
    tiktokStatus = `@${username} ${reason} · retrying every 20 s`;
    log(tiktokStatus);
    reconnectTimer = setTimeout(() => connectTikTok(username), 20000);
  }
}

// The relay (the published game) --------------------------------------------------
// The events go to the relay under this PC's game code as they happen, with
// TikTok's status. No key: the relay checks this PC's secret. What each gift
// does is set in the game itself (its gift settings), not here.
function gameCode() {
  return codeFor(config.secret);
}
function relayUrl() {
  return String(config.relayUrl || RELAY_URL).trim().replace(/\/+$/, '');
}
let relayStatus = relayUrl() ? 'starting' : 'off';
let relaySending = false;
let relayRetryAt = 0;
let lastRelayPush = 0;
let lastPushedStatus = '';
async function flushRelay() {
  const url = relayUrl();
  if (!url) { relayQueue.length = 0; relayStatus = 'off'; return; }
  if (relaySending || Date.now() < relayRetryAt) return;
  // Nothing new: still check in now and then (and when TikTok's status
  // changes) so the relay keeps the status fresh.
  if (relayQueue.length === 0 && tiktokStatus === lastPushedStatus && Date.now() - lastRelayPush < 15000) return;
  const batch = relayQueue.splice(0, 300);
  relaySending = true;
  lastRelayPush = Date.now();
  lastPushedStatus = tiktokStatus;
  try {
    const response = await fetch(`${url}/c/${gameCode()}/push`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-relay-secret': config.secret },
      // No rules: an empty list clears any an older connector left there.
      body: JSON.stringify({ events: batch, rules: [], tiktok: tiktokStatus }),
    });
    if (response.ok) {
      relayStatus = 'sending';
    } else {
      const text = (await response.text()).slice(0, 200);
      relayQueue.unshift(...batch);
      if (response.status === 429 || response.status >= 500) {
        relayStatus = response.status === 429 ? relayStatus : `the relay had a problem (${response.status}), retrying`;
        relayRetryAt = Date.now() + (response.status === 429 ? 500 : 3000);
      } else {
        relayStatus = `the relay refused this connector (${response.status})`;
        log(`Relay refused a push: ${response.status} ${text}`);
        relayRetryAt = Date.now() + 30000;
      }
    }
  } catch (error) {
    relayStatus = `can't reach the relay (${error.message})`;
    relayQueue.unshift(...batch);
    relayRetryAt = Date.now() + 5000;
  } finally {
    if (relayQueue.length > 2000) relayQueue.splice(0, relayQueue.length - 2000);
    relaySending = false;
  }
}
setInterval(flushRelay, 300);
if (relayStatus === 'off') log('No relay address: gifts reach Roblox Studio only.');

// Local web server ------------------------------------------------------------------
function statusLine() {
  const robloxSeen = Date.now() - lastRobloxPoll < 5000;
  return {
    tiktok: tiktokStatus,
    roblox: robloxSeen ? 'connected (Roblox Studio)'
      : relayStatus === 'sending' ? 'ready: type your game code in the game (press Y)'
      : relayStatus === 'starting' ? 'connecting to the relay…'
      : relayStatus === 'off' ? 'Roblox Studio only (this connector has no relay address)'
      : relayStatus,
    gameCode: gameCode(),
  };
}

function sendJson(response, code, body) {
  response.writeHead(code, { 'content-type': 'application/json', 'cache-control': 'no-store' });
  response.end(JSON.stringify(body));
}

function readBody(request) {
  return new Promise((resolve) => {
    let body = '';
    request.on('data', (chunk) => {
      body += chunk;
      if (body.length > 10000) request.destroy();
    });
    request.on('end', () => {
      try {
        resolve(JSON.parse(body || '{}'));
      } catch {
        resolve({});
      }
    });
  });
}

// A place file sent by the control page (a few MB), as raw bytes.
function readRaw(request, limit = 200 * 1024 * 1024) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    request.on('data', (chunk) => {
      size += chunk.length;
      if (size > limit) { reject(new Error('That file is too big.')); request.destroy(); return; }
      chunks.push(chunk);
    });
    request.on('end', () => resolve(Buffer.concat(chunks)));
    request.on('error', reject);
  });
}

// Only the control page (on this PC) may change things: another website open
// in the browser could otherwise send fake gifts or change the settings.
function fromOtherSite(request) {
  const origin = request.headers.origin;
  if (!origin) return false;
  try {
    const { hostname } = new URL(origin);
    return !['localhost', '127.0.0.1', '[::1]', '::1'].includes(hostname);
  } catch {
    return true;
  }
}

const server = http.createServer(async (request, response) => {
  const url = new URL(request.url, 'http://localhost');
  if (request.method !== 'GET' && fromOtherSite(request)) {
    return sendJson(response, 403, { error: 'Only the control page on this PC can do that.' });
  }
  if (request.method === 'GET' && url.pathname === '/events') {
    lastRobloxPoll = Date.now();
    const session = url.searchParams.get('session');
    const since = session === queue.session ? Number(url.searchParams.get('since')) || 0 : 0;
    const events = queue.since(since).map(({ seq, ...event }) => event);
    return sendJson(response, 200, { session: queue.session, last: queue.last, tiktok: tiktokStatus, events });
  }
  if (request.method === 'GET' && url.pathname === '/status') {
    return sendJson(response, 200, { ...statusLine(), username: config.tiktokUsername, recent, publisher: { universeId: config.publisher?.universeId ?? '', placeId: config.publisher?.placeId ?? '', ready: Boolean(config.publisher?.apiKey) } });
  }
  if (request.method === 'POST' && url.pathname === '/publisher') {
    // The owner's second key, which may publish the place. Kept on this PC only.
    const body = await readBody(request);
    const universeId = String(body.universeId ?? '').replace(/\D/g, '');
    const placeId = String(body.placeId ?? '').replace(/\D/g, '');
    const apiKey = String(body.apiKey ?? '').trim();
    if (universeId.length < 5) return sendJson(response, 400, { error: 'Paste the Universe ID: Creator Dashboard, your game\'s ⋯ → Copy Universe ID.' });
    if (placeId.length < 5) return sendJson(response, 400, { error: 'Paste the Place ID: the number in your game\'s Roblox link (roblox.com/games/NUMBER/...).' });
    if (apiKey && (apiKey.length < 20 || /\s/.test(apiKey))) return sendJson(response, 400, { error: 'Paste the whole publishing key.' });
    config.publisher = { universeId, placeId, apiKey: apiKey || config.publisher?.apiKey || '' };
    saveConfig();
    return sendJson(response, 200, { ok: true, ready: Boolean(config.publisher.apiKey) });
  }
  if (request.method === 'POST' && url.pathname === '/publish-place') {
    // Uploads a place file to Roblox as the game's new published version.
    const { universeId, placeId, apiKey } = config.publisher ?? {};
    if (!universeId || !placeId || !apiKey) return sendJson(response, 400, { error: 'Fill in the Universe ID, Place ID and publishing key first.' });
    let file;
    try { file = await readRaw(request); } catch (error) { return sendJson(response, 400, { error: error.message }); }
    const type = placeFileType(file);
    if (!type) return sendJson(response, 400, { error: 'Choose the game file, DiamondRushTikTok.rbxlx.' });
    try {
      const reply = await fetch(placeVersionUrl(universeId, placeId), { method: 'POST', headers: { 'x-api-key': apiKey, 'content-type': type }, body: file });
      const text = await reply.text();
      if (!reply.ok) {
        log(`Roblox refused the game upload: ${reply.status} ${text.slice(0, 300)}`);
        const why = reply.status === 401 || reply.status === 403
          ? 'Roblox refused the publishing key. Check it has universe-places write for this game, and that the Place ID and Universe ID are this game\'s.'
          : reply.status === 404 ? 'Roblox couldn\'t find that place. Check the Place ID and Universe ID.'
          : `Roblox said ${reply.status}: ${text.slice(0, 200)}`;
        return sendJson(response, 400, { error: why });
      }
      let version = null;
      try { version = JSON.parse(text).versionNumber ?? null; } catch {}
      log(`Game updated on Roblox${version ? ` (version ${version})` : ''}.`);
      return sendJson(response, 200, { ok: true, version });
    } catch (error) {
      return sendJson(response, 502, { error: `Couldn't reach Roblox: ${error.message}` });
    }
  }
  if (request.method === 'POST' && url.pathname === '/connect') {
    const body = await readBody(request);
    config.tiktokUsername = String(body.username ?? '').trim().replace(/^@/, '');
    saveConfig();
    connectTikTok(config.tiktokUsername);
    return sendJson(response, 200, { ok: true });
  }
  // No pretend gifts: only real gifts from the LIVE reach the game (the
  // game's own Y panel still has test gifts for trying things out).
  // three.js (MIT, vendor/three.LICENSE) for the control page's 3D shrine.
  if (request.method === 'GET' && url.pathname === '/vendor/three.module.min.js') {
    response.writeHead(200, { 'content-type': 'text/javascript; charset=utf-8', 'cache-control': 'max-age=86400' });
    return response.end(asset('vendor/three.module.min.js'));
  }
  if (request.method === 'GET' && (url.pathname === '/' || url.pathname === '/index.html')) {
    response.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    return response.end(asset('control.html'));
  }
  sendJson(response, 404, { error: 'not found' });
});

server.on('error', (error) => {
  if (error.code === 'EADDRINUSE') {
    log(`Port ${config.port} is already in use. Is the bridge already running in another window?`);
  } else {
    log(`Server error: ${error.message}`);
  }
  process.exit(1);
});

// Only this PC can reach the bridge. Roblox may resolve "localhost" to the IPv6
// loopback, so answer there too when the PC has one.
const ipv6 = http.createServer((request, response) => server.emit('request', request, response));
ipv6.on('error', () => {});
ipv6.listen(config.port, '::1');
server.listen(config.port, '127.0.0.1', () => {
  log(`DIAMOND RUSH bridge running · control page: http://localhost:${config.port}`);
  // The .exe has no Start Bridge.bat to open the page, so it opens it itself.
  if (packaged && process.platform === 'win32') {
    import('node:child_process').then(({ spawn }) => spawn('cmd', ['/c', 'start', '""', `http://localhost:${config.port}`], { stdio: 'ignore', detached: true }).unref()).catch(() => {});
  }
  if (config.tiktokUsername) connectTikTok(config.tiktokUsername);
  else log('Open the control page and enter your TikTok username to connect.');
});
