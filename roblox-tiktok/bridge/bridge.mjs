// DIAMOND RUSH TikTok bridge.
// Connects to a TikTok LIVE and hands gifts, likes, follows and shares to the
// Roblox game: Roblox Studio polls http://localhost:8787/events, and published
// games can receive them through Roblox Open Cloud MessagingService.
// Open http://localhost:8787 for the control page (connect + test gifts).
import http from 'node:http';
import { KEYS, STARTER, normalizeGifts, validateRule, fetchCatalogue, GAMES, defaultGameRules, validateGameRule } from './catalogue.mjs';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createEventQueue, createGiftTracker, likeEvent, socialEvent, packMessages, rebuildTestEvent, themeEvent, THEMES, skinEvent, SKINS } from './events.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const configPath = path.join(here, 'config.json');
const defaults = {
  tiktokUsername: '',
  port: 8787,
  giftRules: {},
  // Diamond Climb's and Chalkboard Count's own rules (see defaultGameRules).
  climbRules: defaultGameRules(),
  chalkRules: defaultGameRules(),
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
  if(event.type === 'gift') {
    const rule=config.giftRules?.[String(event.gift).toLowerCase()];
    if(rule && event.rocks === undefined) event={...event,rocks:rule.rocks};
  }
  const stamped = queue.push(event);
  outbox.push(stamped);
  if (event.type === 'giftRule' || event.type === 'climbRule' || event.type === 'chalkRule') return;
  recent.unshift({ at: Date.now(), ...stamped });
  recent.length = Math.min(recent.length, 30);
  const what = event.type === 'gift' ? `${event.gift} x${event.count} (${event.coins} coins each)` : event.type === 'like' ? `${event.likes} likes` : event.type === 'theme' ? `map theme ${THEMES[event.theme]}` : event.type === 'skin' ? `mountain skin ${SKINS[event.skin]}` : event.type;
  log(`${event.name}: ${what}`);
}

const cataloguePath = path.join(here, 'gift-catalogue.json');
let catalogue = STARTER;
let catalogueStatus = 'Starter gifts. Refresh to load all gifts available for your TikTok LIVE.';
try { const cached=JSON.parse(fs.readFileSync(cataloguePath,'utf8')); const rows=normalizeGifts(cached); if(rows.length){catalogue=rows;catalogueStatus='Saved TikTok catalogue';} } catch {}
let catalogueLoading = null;
async function refreshCatalogue(username = config.tiktokUsername) {
 if(catalogueLoading) return catalogueLoading;
 catalogueLoading=(async()=>{
  username = String(username ?? '').trim().replace(/^@/, '');
  if(!username) throw new Error('Enter your TikTok username first.');
  const { TikTokLiveConnection }=await import('tiktok-live-connector');
  const gifts=await fetchCatalogue(TikTokLiveConnection, username);
  if(!gifts.length) throw new Error('TikTok returned no gifts. Try refreshing while your account is LIVE.');
  catalogue=gifts; catalogueStatus=`${gifts.length} gifts loaded from TikTok`;
  fs.writeFileSync(cataloguePath,JSON.stringify(gifts,null,2));
  config.tiktokUsername=username; saveConfig();
 })().finally(()=>{catalogueLoading=null;});
 return catalogueLoading;
}
function publishRule(rule) { emit({type:'giftRule',name:'Gift catalogue',...rule}); }
for(const rule of Object.values(config.giftRules ?? {})) publishRule(rule);
// The climb's and chalkboard's rules, as events for the game: one per rule,
// and a "clear" for each of the game's own defaults the streamer removed (a
// new save starts with them).
function gameRuleEvents(game) {
  const rules = config[`${game}Rules`] ?? {};
  const events = Object.values(rules).map((rule) => ({ type: `${game}Rule`, name: 'Gift catalogue', gift: rule.gift, coins: rule.coins, amount: rule.amount }));
  for (const [key, rule] of Object.entries(defaultGameRules())) {
    if (!rules[key]) events.push({ type: `${game}Rule`, name: 'Gift catalogue', gift: rule.gift, clear: true });
  }
  return events;
}
for (const game of Object.keys(GAMES)) for (const event of gameRuleEvents(game)) emit(event);

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
  const live = new TikTokLiveConnection(username, { processInitialData: false, enableExtendedGiftInfo: true });
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
      refreshCatalogue().catch(error=>{catalogueStatus=error.message;});
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
let flushing = false;
let retryAt = 0;
async function flushOpenCloud() {
  const { apiKey, universeId, topic } = config.openCloud;
  if (!apiKey || !universeId || outbox.length === 0) {
    outbox.length = 0;
    return;
  }
  if (flushing || Date.now() < retryAt) return;
  flushing = true;
  const batch = outbox.splice(0, outbox.length);
  const messages = packMessages(batch);
  try {
    for (let i = 0; i < messages.length; i += 1) {
      let retry = false;
      try {
        const response = await fetch(`https://apis.roblox.com/messaging-service/v1/universes/${encodeURIComponent(universeId)}/topics/${encodeURIComponent(topic)}`, {
          method: 'POST',
          headers: { 'x-api-key': apiKey, 'content-type': 'application/json' },
          body: JSON.stringify({ message: messages[i] }),
        });
        if (!response.ok) {
          log(`Open Cloud refused a message: ${response.status} ${await response.text()}`);
          // Too many messages or Roblox busy: try again shortly. Anything else
          // (a wrong key or universe) would fail every time, so it is dropped.
          retry = response.status === 429 || response.status >= 500;
        }
      } catch (error) {
        log(`Open Cloud unreachable: ${error.message}`);
        retry = true;
      }
      if (retry) {
        // Put this message and the rest back, in order, ahead of newer events.
        const unsent = messages.slice(i).flatMap((message) => JSON.parse(message));
        outbox.unshift(...unsent);
        // A long Roblox outage keeps only the newest events.
        if (outbox.length > 2000) outbox.splice(0, outbox.length - 2000);
        retryAt = Date.now() + 3000;
        return;
      }
    }
  } finally {
    flushing = false;
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
  if (request.method === 'GET' && url.pathname === '/catalogue') {
    return sendJson(response,200,{gifts:catalogue,status:catalogueStatus,rules:config.giftRules ?? {},keys:KEYS,climbRules:config.climbRules ?? {},chalkRules:config.chalkRules ?? {}});
  }
  if (request.method === 'POST' && url.pathname === '/catalogue/refresh') {
    try { const body=await readBody(request); await refreshCatalogue(body.username || config.tiktokUsername); return sendJson(response,200,{ok:true}); }
    catch(error) { catalogueStatus=error.message; return sendJson(response,400,{error:error.message}); }
  }
  if (request.method === 'POST' && url.pathname === '/catalogue/rule') {
    try {
      const rule=validateRule(await readBody(request));
      const conflict=Object.values(config.giftRules ?? {}).find(other=>other.keybind && other.keybind===rule.keybind && other.gift.toLowerCase()!==rule.gift.toLowerCase());
      if(conflict) throw new Error(`${rule.keybind} is already assigned to ${conflict.gift}. Clear that binding first.`);
      config.giftRules ??= {};
      config.giftRules[rule.gift.toLowerCase()]=rule;
      saveConfig();publishRule(rule);
      return sendJson(response,200,{ok:true});
    } catch(error) {return sendJson(response,400,{error:error.message});}
  }
  if (request.method === 'POST' && url.pathname === '/game-rule') {
    try {
      const rule = validateGameRule(await readBody(request));
      const rules = (config[`${rule.game}Rules`] ??= {});
      const key = rule.gift.toLowerCase();
      if (rule.remove) {
        delete rules[key];
        emit({ type: `${rule.game}Rule`, name: 'Gift catalogue', gift: rule.gift, clear: true });
      } else {
        rules[key] = { gift: rule.gift, coins: rule.coins, amount: rule.amount };
        emit({ type: `${rule.game}Rule`, name: 'Gift catalogue', gift: rule.gift, coins: rule.coins, amount: rule.amount });
      }
      saveConfig();
      return sendJson(response, 200, { ok: true });
    } catch (error) { return sendJson(response, 400, { error: error.message }); }
  }
  if (request.method === 'GET' && url.pathname === '/events') {
    lastRobloxPoll = Date.now();
    const session = url.searchParams.get('session');
    const since = session === queue.session ? Number(url.searchParams.get('since')) || 0 : 0;
    const events = queue.since(since).map(({ seq, ...event }) => event);
    if(!since) for(const [key,rule] of Object.entries(config.giftRules ?? {})) events.unshift({id:`rules:${queue.session}:${key}:${JSON.stringify(rule)}`,type:'giftRule',...rule});
    if(!since) for(const game of Object.keys(GAMES)) for(const rule of gameRuleEvents(game)) events.unshift({id:`${game}Rules:${queue.session}:${JSON.stringify(rule)}`,...rule});
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
  if (request.method === 'POST' && url.pathname === '/test/rebuild') {
    try {
      emit(rebuildTestEvent((await readBody(request)).blocks));
      return sendJson(response, 200, { ok: true });
    } catch (error) { return sendJson(response, 400, { error: error.message }); }
  }
  if (request.method === 'POST' && url.pathname === '/theme') {
    try {
      emit(themeEvent((await readBody(request)).theme));
      return sendJson(response, 200, { ok: true });
    } catch (error) { return sendJson(response, 400, { error: error.message }); }
  }
  if (request.method === 'POST' && url.pathname === '/skin') {
    try {
      emit(skinEvent((await readBody(request)).skin));
      return sendJson(response, 200, { ok: true });
    } catch (error) { return sendJson(response, 400, { error: error.message }); }
  }
  if (request.method === 'POST' && url.pathname === '/test') {
    const body = await readBody(request);
    const name = 'Test viewer';
    if (body.type === 'like') emit({ type: 'like', user: 'tester', name, likes: Math.max(1, Number(body.likes) || 10) });
    else if (body.type === 'follow' || body.type === 'share') emit({ type: body.type, user: 'tester', name });
    else emit({ type: 'gift', user: 'tester', name, gift: String(body.gift ?? 'Rose').slice(0, 40), coins: Math.max(1, Number(body.coins) || 1), count: Math.max(1, Math.min(100, Number(body.count) || 1)) });
    return sendJson(response, 200, { ok: true });
  }
  // three.js (MIT, vendor/three.LICENSE) for the control page's 3D shrine.
  if (request.method === 'GET' && url.pathname === '/vendor/three.module.min.js') {
    response.writeHead(200, { 'content-type': 'text/javascript; charset=utf-8', 'cache-control': 'max-age=86400' });
    return response.end(fs.readFileSync(path.join(here, 'vendor', 'three.module.min.js')));
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
