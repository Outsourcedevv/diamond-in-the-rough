// Diamond Rush relay, for Cloudflare Workers (free plan) with a D1 database
// bound as DB. Paste this whole file into the Worker's editor (see
// relay/README.md).
//
// Each streamer's connector (DiamondRushBridge.exe) sends their TikTok events
// here under their game code, and their Roblox game asks for that code's
// events. No Roblox key is involved anywhere.
//
// A game code is worked out from a secret only that streamer's connector
// knows (the first 40 bits of its SHA-256), so only that connector can send
// under it: the relay checks the secret on every push and stores nothing about
// it. Events are kept for ten minutes.
//
//   POST /c/CODE/push   header x-relay-secret, body { events, rules, tiktok }
//   GET  /c/CODE/events?since=N&wait=S&start=0|1
//        -> { session, last, tiktok, events }
//   A game that has just started asks with start=1: it gets the newest event
//   number, not the events that came before it, and then asks for the ones
//   after it (start=0, even when that number is 0). Games from before the
//   start flag ask with since=0 instead.

export const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
export const CODE_LENGTH = 8;
export const LIMITS = {
  bodyBytes: 256 * 1024,
  eventsPerPush: 300,
  eventBytes: 2000,
  rules: 400,
  keepSeconds: 600,
  waitSeconds: 8, // longest a game's request is held open
  checkMs: 400, // how often a held request looks for new events (D1 allows 50 queries a request)
  pushEveryMs: 250, // a connector may push this often
};
const SESSION = 'd1';

export async function codeFor(secret) {
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(String(secret))));
  let bits = 0;
  let value = 0;
  let code = '';
  for (const byte of digest) {
    value = ((value << 8) | byte) & 0xffff;
    bits += 8;
    while (bits >= 5 && code.length < CODE_LENGTH) {
      bits -= 5;
      code += CODE_ALPHABET[(value >> bits) & 31];
    }
    if (code.length === CODE_LENGTH) break;
  }
  return code;
}

export function cleanCode(text) {
  const code = String(text ?? '').toUpperCase().replace(/[\s-]/g, '');
  return code.length === CODE_LENGTH && [...code].every((c) => CODE_ALPHABET.includes(c)) ? code : null;
}

// The tables, made once per database the first time it is used.
const ready = new WeakMap();
function setUp(db) {
  if (!ready.has(db)) ready.set(db, db.batch([
    db.prepare('CREATE TABLE IF NOT EXISTS events (id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT NOT NULL, body TEXT NOT NULL, at INTEGER NOT NULL)'),
    db.prepare('CREATE INDEX IF NOT EXISTS events_code ON events (code, id)'),
    db.prepare('CREATE TABLE IF NOT EXISTS codes (code TEXT PRIMARY KEY, tiktok TEXT, rules TEXT, pushed INTEGER)'),
  ]).catch((error) => { ready.delete(db); throw error; }));
  return ready.get(db);
}

function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json', 'cache-control': 'no-store', 'access-control-allow-origin': '*' },
  });
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function push(db, code, request, now) {
  const secret = request.headers.get('x-relay-secret') ?? '';
  if (secret.length < 32 || (await codeFor(secret)) !== code) return json(403, { error: 'This connector does not own that game code.' });
  const text = await request.text();
  if (text.length > LIMITS.bodyBytes) return json(413, { error: 'Too much at once.' });
  let body;
  try { body = JSON.parse(text); } catch { return json(400, { error: 'Not JSON.' }); }
  const state = await db.prepare('SELECT pushed FROM codes WHERE code = ?').bind(code).first();
  if (state && now - Number(state.pushed) < LIMITS.pushEveryMs) return json(429, { error: 'Slow down.' });

  const events = (Array.isArray(body?.events) ? body.events : [])
    .filter((event) => event && typeof event === 'object' && typeof event.type === 'string')
    .slice(0, LIMITS.eventsPerPush)
    .map((event) => JSON.stringify(event))
    .filter((line) => line.length <= LIMITS.eventBytes);
  const rules = Array.isArray(body?.rules)
    ? JSON.stringify(body.rules.filter((rule) => rule && typeof rule === 'object' && typeof rule.id === 'string' && typeof rule.type === 'string').slice(0, LIMITS.rules))
    : null;
  const tiktok = typeof body?.tiktok === 'string' ? body.tiktok.slice(0, 120) : '';

  const writes = [
    db.prepare('INSERT INTO codes (code, tiktok, rules, pushed) VALUES (?1, ?2, COALESCE(?3, \'[]\'), ?4) ON CONFLICT (code) DO UPDATE SET tiktok = ?2, rules = COALESCE(?3, rules), pushed = ?4')
      .bind(code, tiktok, rules, now),
    ...events.map((line) => db.prepare('INSERT INTO events (code, body, at) VALUES (?, ?, ?)').bind(code, line, now)),
    // The newest event is always kept, so the newest event number never goes
    // back to 0 when everything is old (a game starting then would miss the
    // next gifts).
    db.prepare('DELETE FROM events WHERE code = ? AND at < ? AND id < (SELECT MAX(id) FROM events)').bind(code, now - LIMITS.keepSeconds * 1000),
  ];
  await db.batch(writes);
  return json(200, { ok: true, received: events.length });
}

async function read(db, code, url, clock) {
  const since = Math.max(0, Math.floor(Number(url.searchParams.get('since')) || 0));
  const wait = Math.min(LIMITS.waitSeconds, Math.max(0, Number(url.searchParams.get('wait')) || 0));
  const start = url.searchParams.get('start');
  const starting = start === '1' || (start === null && since === 0);
  const state = await db.prepare('SELECT tiktok, rules FROM codes WHERE code = ?').bind(code).first();
  const tiktok = state?.tiktok || 'waiting for DiamondRushBridge.exe (check the game code)';
  if (starting) {
    // A game that just started: the rules, and where the events are up to.
    const top = await db.prepare('SELECT MAX(id) AS last FROM events').first();
    let rules = [];
    try { rules = JSON.parse(state?.rules || '[]'); } catch {}
    return json(200, { session: SESSION, last: Number(top?.last) || 0, tiktok, events: rules });
  }
  // Look again every checkMs until something arrives or the wait is up (a
  // count as well as the clock, so it always stops within D1's query limit).
  const until = clock() + wait * 1000;
  const checks = Math.ceil((wait * 1000) / LIMITS.checkMs);
  for (let check = 0; ; check += 1) {
    const { results } = await db.prepare('SELECT id, body FROM events WHERE code = ? AND id > ? ORDER BY id LIMIT 300').bind(code, since).all();
    if (results.length > 0 || check >= checks || clock() >= until) {
      const events = [];
      for (const row of results) { try { events.push(JSON.parse(row.body)); } catch {} }
      const last = results.length > 0 ? Number(results[results.length - 1].id) : since;
      const fresh = results.length > 0 ? (await db.prepare('SELECT tiktok FROM codes WHERE code = ?').bind(code).first())?.tiktok || tiktok : tiktok;
      return json(200, { session: SESSION, last, tiktok: fresh, events });
    }
    await sleep(LIMITS.checkMs);
  }
}

export async function handle(request, env, clock = () => Date.now()) {
  const url = new URL(request.url);
  if (url.pathname === '/' || url.pathname === '') {
    return new Response('Diamond Rush relay is running.', { headers: { 'content-type': 'text/plain' } });
  }
  const match = url.pathname.match(/^\/c\/([^/]+)\/(push|events)$/);
  if (!match) return json(404, { error: 'not found' });
  const code = cleanCode(decodeURIComponent(match[1]));
  if (!code) return json(400, { error: 'That is not a game code.' });
  if (!env.DB) return json(500, { error: 'The relay has no database: bind a D1 database as DB.' });
  await setUp(env.DB);
  if (match[2] === 'push' && request.method === 'POST') return push(env.DB, code, request, clock());
  if (match[2] === 'events' && request.method === 'GET') return read(env.DB, code, url, clock);
  return json(405, { error: 'method not allowed' });
}

export default {
  fetch: (request, env) => handle(request, env).catch((error) => json(500, { error: String(error?.message ?? error) })),
};
