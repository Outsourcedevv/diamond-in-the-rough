// DIAMOND RUSH TikTok bridge.
// Connects to a TikTok LIVE and hands gifts, likes, follows and shares to the
// Roblox game: Roblox Studio polls http://localhost:8787/events, and published
// games can receive them through Roblox Open Cloud MessagingService.
// Open http://localhost:8787 for the control page (connect + test gifts).
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createEventQueue, createGiftTracker, likeEvent, socialEvent, packMessages } from './events.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const configPath = path.join(here, 'config.json');
const defaults = {
  tiktokUsername: '',
  port: 8787,
  openCloud: { apiKey: '', universeId: '', topic: 'DiamondRushTikTok' },
};

function loadConfig() {
  try {
    const saved = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    return { ...defaults, ...saved, openCloud: { ...defaults.openCloud, ...(saved.openCloud ?? {}) } };
  } catch {
    return structuredClone(defaults);
  }
}

function saveConfig() {
  fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`);
}

const config = loadConfig();
const queue = createEventQueue();
const handleGift = createGiftTracker();
const outbox = [];
const recent = [];
let tiktokStatus = 'not connected';
let connection = null;
let reconnectTimer = null;
let lastRobloxPoll = 0;

function log(line) {
  const stamp = new Date().toLocaleTimeString();
  console.log(`[${stamp}] ${line}`);
}

function emit(event) {
  if (!event) return;
  const stamped = queue.push(event);
  outbox.push(stamped);
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
  const live = new TikTokLiveConnection(username, { processInitialData: false, enableExtendedGiftInfo: false });
  connection = live;
  tiktokStatus = `connecting to @${username}…`;
  live.on(WebcastEvent.GIFT, (data) => emit(handleGift(data)));
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

// Roblox Open Cloud (published games) --------------------------------------------
async function flushOpenCloud() {
  const { apiKey, universeId, topic } = config.openCloud;
  if (!apiKey || !universeId || outbox.length === 0) {
    outbox.length = 0;
    return;
  }
  const batch = outbox.splice(0, outbox.length);
  for (const message of packMessages(batch)) {
    try {
      const response = await fetch(`https://apis.roblox.com/messaging-service/v1/universes/${encodeURIComponent(universeId)}/topics/${encodeURIComponent(topic)}`, {
        method: 'POST',
        headers: { 'x-api-key': apiKey, 'content-type': 'application/json' },
        body: JSON.stringify({ message }),
      });
      if (!response.ok) log(`Open Cloud refused a message: ${response.status} ${await response.text()}`);
    } catch (error) {
      log(`Open Cloud unreachable: ${error.message}`);
    }
  }
}
setInterval(flushOpenCloud, 1000);

// Local web server ------------------------------------------------------------------
function statusLine() {
  const robloxSeen = Date.now() - lastRobloxPoll < 5000;
  return { tiktok: tiktokStatus, roblox: robloxSeen ? 'connected (Roblox Studio)' : 'waiting for Roblox Studio (press Play)' };
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

const server = http.createServer(async (request, response) => {
  const url = new URL(request.url, 'http://localhost');
  if (request.method === 'GET' && url.pathname === '/events') {
    lastRobloxPoll = Date.now();
    const session = url.searchParams.get('session');
    const since = session === queue.session ? Number(url.searchParams.get('since')) || 0 : 0;
    const events = queue.since(since).map(({ seq, ...event }) => event);
    return sendJson(response, 200, { session: queue.session, last: queue.last, tiktok: tiktokStatus, events });
  }
  if (request.method === 'GET' && url.pathname === '/status') {
    return sendJson(response, 200, { ...statusLine(), username: config.tiktokUsername, openCloud: Boolean(config.openCloud.apiKey && config.openCloud.universeId), recent });
  }
  if (request.method === 'POST' && url.pathname === '/connect') {
    const body = await readBody(request);
    config.tiktokUsername = String(body.username ?? '').trim().replace(/^@/, '');
    saveConfig();
    connectTikTok(config.tiktokUsername);
    return sendJson(response, 200, { ok: true });
  }
  if (request.method === 'POST' && url.pathname === '/opencloud') {
    const body = await readBody(request);
    config.openCloud.apiKey = String(body.apiKey ?? '').trim();
    config.openCloud.universeId = String(body.universeId ?? '').trim();
    saveConfig();
    return sendJson(response, 200, { ok: true });
  }
  if (request.method === 'POST' && url.pathname === '/test') {
    const body = await readBody(request);
    const name = 'Test viewer';
    if (body.type === 'like') emit({ type: 'like', user: 'tester', name, likes: Math.max(1, Number(body.likes) || 10) });
    else if (body.type === 'follow' || body.type === 'share') emit({ type: body.type, user: 'tester', name });
    else emit({ type: 'gift', user: 'tester', name, gift: String(body.gift ?? 'Rose').slice(0, 40), coins: Math.max(1, Number(body.coins) || 1), count: Math.max(1, Math.min(100, Number(body.count) || 1)) });
    return sendJson(response, 200, { ok: true });
  }
  if (request.method === 'GET' && (url.pathname === '/' || url.pathname === '/index.html')) {
    response.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    return response.end(fs.readFileSync(path.join(here, 'control.html')));
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
  if (config.tiktokUsername) connectTikTok(config.tiktokUsername);
  else log('Open the control page and enter your TikTok username to connect.');
});
