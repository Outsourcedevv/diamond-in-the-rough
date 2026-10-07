// DIAMOND RUSH TikTok bridge.
// Connects to a TikTok LIVE and hands gifts, likes, follows and shares to the
// Roblox game. The published game receives them through Roblox Open Cloud
// MessagingService, on the topic for this PC's game code (see cloud.mjs);
// Roblox Studio can also poll http://localhost:8787/events.
// Open http://localhost:8787 for the control page (connect + test gifts).
import http from 'node:http';
import { KEYS, STARTER, normalizeGifts, validateRule, fetchCatalogue, GAMES, defaultGameRules, validateGameRule, CONNECT_OPTIONS, learnGift, catalogueError, mergeGifts } from './catalogue.mjs';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createEventQueue, createGiftTracker, likeEvent, socialEvent, themeEvent, THEMES, skinEvent, SKINS } from './events.mjs';
import { codeFor, topicFor, parseCloudFile, takeMessage, ruleId, SEND_EVERY_MS, readSlot, sealBinary, placeVersionUrl, placeFileType } from './cloud.mjs';
import { SLOT } from './sealed-slot.mjs';
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
  giftRules: {},
  // Diamond Climb's and Chalkboard Count's own rules (see defaultGameRules).
  climbRules: defaultGameRules(),
  chalkRules: defaultGameRules(),
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
  } catch {
    config = structuredClone(defaults);
  }
  // Keybinds used to be set on this page; pressing them sent pretend gifts.
  // They are gone, so older saves lose theirs (the game's own keybinds stay).
  for (const rule of Object.values(config.giftRules ?? {})) if (rule && typeof rule === 'object') rule.keybind = '';
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
// What waits to go to the published game (see "Roblox Open Cloud" below).
const cloudQueue = [];

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
  const { seq, ...compact } = stamped;
  cloudQueue.push(compact);
  if (cloudQueue.length > 2000) cloudQueue.splice(0, cloudQueue.length - 2000);
  if (event.type === 'giftRule' || event.type === 'climbRule' || event.type === 'chalkRule') return;
  recent.unshift({ at: Date.now(), ...stamped });
  recent.length = Math.min(recent.length, 30);
  const what = event.type === 'gift' ? `${event.gift} x${event.count} (${event.coins} coins each)` : event.type === 'like' ? `${event.likes} likes` : event.type === 'theme' ? `map theme ${THEMES[event.theme]}` : event.type === 'skin' ? `mountain skin ${SKINS[event.skin]}` : event.type;
  log(`${event.name}: ${what}`);
}

const cataloguePath = path.join(here, 'gift-catalogue.json');
let catalogue = STARTER;
let catalogueStatus = 'Starter gifts. Gifts you receive on your LIVE are added automatically.';
try { const cached=JSON.parse(fs.readFileSync(cataloguePath,'utf8')); const rows=normalizeGifts(cached); if(rows.length){catalogue=mergeGifts(STARTER,rows);catalogueStatus='Saved gift list';} } catch {}
let catalogueLoading = null;
async function refreshCatalogue(username = config.tiktokUsername) {
 if(catalogueLoading) return catalogueLoading;
 catalogueLoading=(async()=>{
  username = String(username ?? '').trim().replace(/^@/, '');
  if(!username) throw new Error('Enter your TikTok username first.');
  const { TikTokLiveConnection }=await import('tiktok-live-connector');
  let gifts;
  try { gifts=await fetchCatalogue(TikTokLiveConnection, username); }
  catch(error) { throw new Error(catalogueError(error)); }
  if(!gifts.length) throw new Error('TikTok returned no gifts. Try refreshing while your account is LIVE.');
  catalogue=mergeGifts(catalogue,gifts); catalogueStatus=`${gifts.length} gifts loaded from TikTok`;
  fs.writeFileSync(cataloguePath,JSON.stringify(gifts,null,2));
  config.tiktokUsername=username; saveConfig();
 })().finally(()=>{catalogueLoading=null;});
 return catalogueLoading;
}
// Gifts seen on the LIVE join the catalogue, so they can be given rules.
function rememberGift(event) {
  if (event?.type !== 'gift') return;
  const updated = learnGift(catalogue, event.gift, event.coins);
  if (!updated) return;
  catalogue = updated;
  try { fs.writeFileSync(cataloguePath, JSON.stringify(catalogue, null, 2)); } catch {}
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
  const live = new TikTokLiveConnection(username, CONNECT_OPTIONS);
  connection = live;
  tiktokStatus = `connecting to @${username}…`;
  live.on(WebcastEvent.GIFT, (data) => {
    const event = handleGift(data);
    rememberGift(event);
    emit(event);
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
      refreshCatalogue(username).catch(error=>{catalogueStatus=error.message;});
    }
  } catch (error) {
    if (connection !== live) return;
    const reason = error?.name === 'UserOfflineError' ? 'is not live right now' : `could not connect (${error?.message ?? error})`;
    tiktokStatus = `@${username} ${reason} · retrying every 20 s`;
    log(tiktokStatus);
    reconnectTimer = setTimeout(() => connectTikTok(username), 20000);
  }
}

// Roblox Open Cloud (the published game) ------------------------------------------
// The game owner's key and universe. The owner keeps them in roblox-cloud.txt
// next to their own copy; opening that copy makes the streamers' copy, with
// the key hidden inside it (see sealBinary) and no text file. The key can only
// publish messages to this one game.
function gameCode() {
  return codeFor(config.secret);
}
// Writes "For streamers/DiamondRushBridge.exe" next to this program and
// returns its path. Only the .exe can copy itself.
function makeStreamersCopy(settings) {
  if (!packaged) throw new Error('Only DiamondRushBridge.exe can make the streamers\' copy.');
  const folder = path.join(here, 'For streamers');
  fs.mkdirSync(folder, { recursive: true });
  const target = path.join(folder, 'DiamondRushBridge.exe');
  fs.writeFileSync(target, sealBinary(fs.readFileSync(process.execPath), settings));
  log('Made the streamers\' copy, with the Roblox key hidden inside: share the "For streamers" folder.');
  return target;
}
// Where the key comes from: the owner's box on the control page (kept in this
// PC's config.json), roblox-cloud.txt, or hidden inside a streamers' copy.
function cloudSettings() {
  const owner = config.ownerCloud;
  if (owner?.apiKey && owner?.universeId) return { apiKey: String(owner.apiKey), universeId: String(owner.universeId), source: 'owner' };
  try {
    const found = parseCloudFile(fs.readFileSync(path.join(here, 'roblox-cloud.txt'), 'utf8'));
    if (found.apiKey && found.universeId) {
      if (packaged) { try { makeStreamersCopy(found); } catch (error) { log(`Couldn't make the streamers' copy: ${error.message}`); } }
      return { ...found, source: 'owner' };
    }
  } catch {}
  const sealed = readSlot(SLOT);
  return sealed ? { ...sealed, source: 'built in' } : { apiKey: '', universeId: '', source: 'none' };
}
let cloud = cloudSettings();
let cloudStatus = cloud.apiKey && cloud.universeId ? 'starting' : 'off';
let cloudSending = false;
let nextSendAt = 0;
let lastStatusSent = '';
let lastStatusAt = 0;
let lastRulesAt = 0;
// Every gift rule, as events. Their ids stay the same while the rules do, so a
// game that just started takes them and one that has them skips the repeat.
function allRules() {
  const rules = [];
  for (const rule of Object.values(config.giftRules ?? {})) rules.push({ type: 'giftRule', name: 'Gift catalogue', ...rule });
  for (const game of Object.keys(GAMES)) rules.push(...gameRuleEvents(game));
  return rules.map((rule) => ({ id: ruleId(rule), ...rule }));
}
async function flushCloud() {
  if (!cloud.apiKey || !cloud.universeId) { cloudQueue.length = 0; return; }
  if (cloudSending || Date.now() < nextSendAt) return;
  const now = Date.now();
  if (cloudQueue.length === 0) {
    // Nothing new: the TikTok status now and then, so the game can show it,
    // and the rules every two minutes, for a game that started since.
    if (tiktokStatus !== lastStatusSent || now - lastStatusAt > 60000) {
      lastStatusSent = tiktokStatus;
      lastStatusAt = now;
      cloudQueue.push({ id: `s${now.toString(36)}`, type: 'status', tiktok: tiktokStatus });
    } else if (now - lastRulesAt > 120000) {
      lastRulesAt = now;
      cloudQueue.push(...allRules());
    }
    if (cloudQueue.length === 0) return;
  }
  const message = takeMessage(cloudQueue);
  if (!message) return;
  cloudSending = true;
  nextSendAt = now + SEND_EVERY_MS;
  try {
    const response = await fetch(`https://apis.roblox.com/messaging-service/v1/universes/${encodeURIComponent(cloud.universeId)}/topics/${encodeURIComponent(topicFor(gameCode()))}`, {
      method: 'POST',
      headers: { 'x-api-key': cloud.apiKey, 'content-type': 'application/json' },
      body: JSON.stringify({ message }),
    });
    if (response.ok) {
      cloudStatus = 'sending';
    } else {
      const text = (await response.text()).slice(0, 200);
      log(`Roblox refused a message: ${response.status} ${text}`);
      cloudQueue.unshift(...JSON.parse(message));
      if (response.status === 429 || response.status >= 500) {
        cloudStatus = 'Roblox is busy, retrying';
        nextSendAt = Date.now() + 10000;
      } else {
        // A wrong or expired key fails every time: try again now and then.
        cloudStatus = `Roblox refused the connector's key (${response.status}). Ask the game's owner for a new download.`;
        nextSendAt = Date.now() + 30000;
      }
    }
  } catch (error) {
    cloudStatus = `can't reach Roblox (${error.message})`;
    cloudQueue.unshift(...JSON.parse(message));
    nextSendAt = Date.now() + 5000;
  } finally {
    if (cloudQueue.length > 2000) cloudQueue.splice(0, cloudQueue.length - 2000);
    cloudSending = false;
  }
}
setInterval(flushCloud, 250);
if (cloudStatus === 'off') log('No Roblox key in this connector. Game owner: open the control page and use "Game owner: Roblox key".');

// Local web server ------------------------------------------------------------------
function statusLine() {
  const robloxSeen = Date.now() - lastRobloxPoll < 5000;
  return {
    tiktok: tiktokStatus,
    roblox: robloxSeen ? 'connected (Roblox Studio)'
      : cloudStatus === 'sending' ? 'sending to the game'
      : cloudStatus === 'starting' ? 'ready: type your game code in the game'
      : cloudStatus === 'off' ? 'not set up (this connector has no Roblox key: get the newest download)'
      : cloudStatus,
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
  if (request.method === 'GET' && url.pathname === '/catalogue') {
    return sendJson(response,200,{gifts:catalogue,status:catalogueStatus,rules:config.giftRules ?? {},keys:KEYS,climbRules:config.climbRules ?? {},chalkRules:config.chalkRules ?? {}});
  }
  if (request.method === 'POST' && url.pathname === '/catalogue/refresh') {
    try { const body=await readBody(request); await refreshCatalogue(body.username || config.tiktokUsername); return sendJson(response,200,{ok:true}); }
    catch(error) { catalogueStatus=error.message; return sendJson(response,400,{error:error.message}); }
  }
  if (request.method === 'POST' && url.pathname === '/catalogue/rule') {
    try {
      const rule={...validateRule(await readBody(request)),keybind:''};
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
    return sendJson(response, 200, { ...statusLine(), username: config.tiktokUsername, recent, keySource: cloud.source, packaged, publisher: { placeId: config.publisher?.placeId ?? '', ready: Boolean(config.publisher?.apiKey) } });
  }
  if (request.method === 'POST' && url.pathname === '/publisher') {
    // The owner's second key, which may publish the place. Kept on this PC only.
    const body = await readBody(request);
    const placeId = String(body.placeId ?? '').replace(/\D/g, '');
    const apiKey = String(body.apiKey ?? '').trim();
    if (placeId.length < 5) return sendJson(response, 400, { error: 'Paste the Place ID: the number in your game\'s Roblox link (roblox.com/games/NUMBER/...).' });
    if (apiKey && (apiKey.length < 20 || /\s/.test(apiKey))) return sendJson(response, 400, { error: 'Paste the whole publishing key.' });
    config.publisher = { placeId, apiKey: apiKey || config.publisher?.apiKey || '' };
    saveConfig();
    return sendJson(response, 200, { ok: true, ready: Boolean(config.publisher.apiKey) });
  }
  if (request.method === 'POST' && url.pathname === '/publish-place') {
    // Uploads a place file to Roblox as the game's new published version.
    const universeId = cloud.source === 'owner' ? cloud.universeId : '';
    const { placeId, apiKey } = config.publisher ?? {};
    if (!universeId) return sendJson(response, 400, { error: 'Save the Universe ID and Roblox key in the box above first.' });
    if (!placeId || !apiKey) return sendJson(response, 400, { error: 'Save the Place ID and publishing key first.' });
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
  if (request.method === 'POST' && url.pathname === '/owner-key') {
    // The game's owner pastes the Universe ID and Open Cloud key here once.
    const body = await readBody(request);
    const universeId = String(body.universeId ?? '').replace(/\D/g, '');
    const apiKey = String(body.apiKey ?? '').trim();
    if (universeId.length < 5) return sendJson(response, 400, { error: 'Paste the Universe ID: the long number from Copy Universe ID.' });
    if (apiKey.length < 20 || /\s/.test(apiKey)) return sendJson(response, 400, { error: 'Paste the whole API key (Copy Key to Clipboard on the Open Cloud page).' });
    config.ownerCloud = { universeId, apiKey };
    saveConfig();
    cloud = { universeId, apiKey, source: 'owner' };
    cloudStatus = 'starting';
    nextSendAt = 0;
    lastRulesAt = 0;
    log('Roblox key saved on this PC.');
    try {
      const made = makeStreamersCopy(cloud);
      return sendJson(response, 200, { ok: true, made });
    } catch (error) {
      return sendJson(response, 200, { ok: true, made: null, note: error.message });
    }
  }
  if (request.method === 'POST' && url.pathname === '/connect') {
    const body = await readBody(request);
    config.tiktokUsername = String(body.username ?? '').trim().replace(/^@/, '');
    saveConfig();
    connectTikTok(config.tiktokUsername);
    return sendJson(response, 200, { ok: true });
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
