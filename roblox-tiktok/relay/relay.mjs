// The Diamond Rush relay: lets many streamers play the published game at once.
//
// Each streamer runs the bridge on their own PC. The bridge connects to their
// TikTok LIVE and sends the events here under the streamer's game code. Their
// Roblox server asks for that code's events only, so every streamer gets their
// own gifts and nobody needs the game's Open Cloud key.
//
// A game code is worked out from a secret only that streamer's bridge knows, so
// nobody else can send gifts under it. Reading a code's events needs only the
// code. Nothing is stored on disk: events live in memory for a few minutes.
//
//   POST /c/CODE/push    (header x-relay-secret) { events, rules, tiktok }
//   GET  /c/CODE/events?since=N&session=S&wait=15
//        -> { session, last, tiktok, events }   (the bridge's own /events shape)
import http from 'node:http';
import { createHash, randomUUID } from 'node:crypto';
import { pathToFileURL } from 'node:url';

// Letters and digits that can't be mixed up (no 0/O, 1/I).
export const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
export const CODE_LENGTH = 8;

// The game code for a bridge's secret: 8 characters (40 bits) of its SHA-256.
export function codeFor(secret) {
  const digest = createHash('sha256').update(String(secret)).digest();
  let bits = 0;
  let value = 0;
  let code = '';
  for (const byte of digest) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5 && code.length < CODE_LENGTH) {
      bits -= 5;
      code += CODE_ALPHABET[(value >> bits) & 31];
    }
    if (code.length === CODE_LENGTH) break;
  }
  return code;
}

// "abcd-efgh" or "ABCD EFGH" -> "ABCDEFGH", or null if it can't be a code.
export function cleanCode(text) {
  const code = String(text ?? '').toUpperCase().replace(/[\s-]/g, '');
  return code.length === CODE_LENGTH && [...code].every((c) => CODE_ALPHABET.includes(c)) ? code : null;
}

export const LIMITS = {
  events: 500, // kept per channel
  eventSeconds: 600, // and for at most ten minutes
  perPush: 300, // events in one push
  rules: 400, // rule events in the snapshot
  bodyBytes: 256 * 1024,
  channels: 5000,
  idleSeconds: 2 * 60 * 60, // a channel nobody used for two hours is dropped
  waitSeconds: 20, // longest a game's request is held open
  waitersPerChannel: 8,
};

export function createRelay({ now = () => Date.now(), limits = LIMITS } = {}) {
  const channels = new Map();

  function channel(code, create) {
    let found = channels.get(code);
    if (!found && create) {
      if (channels.size >= limits.channels) sweep(true);
      if (channels.size >= limits.channels) return null;
      found = { code, session: randomUUID().slice(0, 8), seq: 0, events: [], rules: [], tiktok: '', secretHash: null, used: now(), waiters: new Set() };
      channels.set(code, found);
    }
    if (found) found.used = now();
    return found;
  }

  // Old events and idle channels go; `hard` also drops channels no bridge claimed.
  function sweep(hard = false) {
    const time = now();
    for (const [code, found] of channels) {
      const idle = (time - found.used) / 1000 > limits.idleSeconds;
      if ((idle || (hard && !found.secretHash)) && found.waiters.size === 0) channels.delete(code);
    }
  }

  function trim(found) {
    const oldest = now() - limits.eventSeconds * 1000;
    while (found.events.length > limits.events || (found.events.length && found.events[0].at < oldest)) found.events.shift();
  }

  function wake(found) {
    for (const waiter of found.waiters) waiter();
    found.waiters.clear();
  }

  // A bridge sends its events, its current gift rules and its TikTok status.
  function push(rawCode, secret, body) {
    const code = cleanCode(rawCode);
    if (!code || typeof secret !== 'string' || secret.length < 16 || codeFor(secret) !== code) {
      return { status: 403, body: { error: 'That secret does not match this game code.' } };
    }
    const found = channel(code, true);
    if (!found) return { status: 503, body: { error: 'The relay is full. Try again later.' } };
    const hash = createHash('sha256').update(secret).digest('hex');
    if (found.secretHash && found.secretHash !== hash) return { status: 403, body: { error: 'Another bridge owns this game code.' } };
    found.secretHash = hash;
    const events = Array.isArray(body?.events) ? body.events : [];
    if (events.length > limits.perPush) return { status: 413, body: { error: `At most ${limits.perPush} events at once.` } };
    for (const event of events) {
      if (!event || typeof event !== 'object' || typeof event.id !== 'string' || typeof event.type !== 'string') continue;
      found.seq += 1;
      found.events.push({ seq: found.seq, at: now(), event });
    }
    if (Array.isArray(body?.rules)) {
      found.rules = body.rules.filter((rule) => rule && typeof rule === 'object' && typeof rule.id === 'string' && typeof rule.type === 'string').slice(0, limits.rules);
    }
    if (typeof body?.tiktok === 'string') found.tiktok = body.tiktok.slice(0, 120);
    trim(found);
    if (events.length) wake(found);
    return { status: 200, body: { ok: true, last: found.seq } };
  }

  function reply(found, session, since) {
    if (!found) return { session: '', last: 0, tiktok: 'waiting for your bridge (check the game code)', events: [] };
    trim(found);
    // A game that doesn't know this channel's session is new (or the relay
    // restarted): it starts from the beginning and gets the gift rules first.
    const fresh = session !== found.session;
    const from = fresh ? 0 : since;
    const events = found.events.filter((item) => item.seq > from).map((item) => item.event);
    if (fresh) events.unshift(...found.rules);
    return { session: found.session, last: found.seq, tiktok: found.tiktok || 'waiting for your bridge', events };
  }

  // A game asks for its code's events after `since`; with `wait` the request
  // is held until something arrives (or `wait` seconds pass).
  async function events(rawCode, { since = 0, session = '', wait = 0 } = {}) {
    const code = cleanCode(rawCode);
    if (!code) return { status: 400, body: { error: 'Not a game code.' } };
    const found = channel(code, false);
    const seconds = Math.min(Math.max(Number(wait) || 0, 0), limits.waitSeconds);
    if (found && seconds > 0 && session === found.session && found.seq <= since && found.waiters.size < limits.waitersPerChannel) {
      await new Promise((resolve) => {
        const timer = setTimeout(done, seconds * 1000);
        function done() {
          clearTimeout(timer);
          found.waiters.delete(done);
          resolve();
        }
        found.waiters.add(done);
      });
    } else if (!found && seconds > 0) {
      // No bridge yet: answer a little later so idle games don't poll fast.
      await new Promise((resolve) => setTimeout(resolve, Math.min(seconds, 5) * 1000));
    }
    return { status: 200, body: reply(channels.get(code), session, Number(since) || 0) };
  }

  return { push, events, sweep, channels };
}

function readBody(request, limit) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    request.on('data', (chunk) => {
      size += chunk.length;
      if (size > limit) {
        reject(Object.assign(new Error('Too large.'), { status: 413 }));
        request.destroy();
      } else chunks.push(chunk);
    });
    request.on('end', () => {
      try { resolve(chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : {}); }
      catch { reject(Object.assign(new Error('Not JSON.'), { status: 400 })); }
    });
    request.on('error', reject);
  });
}

export function createServer(relay = createRelay()) {
  const server = http.createServer(async (request, response) => {
    const send = (status, body) => {
      response.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store' });
      response.end(JSON.stringify(body));
    };
    try {
      const url = new URL(request.url, 'http://relay');
      const match = url.pathname.match(/^\/c\/([^/]+)\/(push|events)$/);
      if (request.method === 'GET' && url.pathname === '/') {
        response.writeHead(200, { 'content-type': 'text/plain' });
        return response.end(`Diamond Rush relay · ${relay.channels.size} channels\n`);
      }
      if (match && request.method === 'POST' && match[2] === 'push') {
        const body = await readBody(request, LIMITS.bodyBytes);
        const result = relay.push(match[1], request.headers['x-relay-secret'], body);
        return send(result.status, result.body);
      }
      if (match && request.method === 'GET' && match[2] === 'events') {
        const result = await relay.events(match[1], {
          since: Number(url.searchParams.get('since')) || 0,
          session: url.searchParams.get('session') ?? '',
          wait: url.searchParams.get('wait'),
        });
        return send(result.status, result.body);
      }
      send(404, { error: 'Not found.' });
    } catch (error) {
      send(error.status ?? 500, { error: error.message });
    }
  });
  const sweeper = setInterval(() => relay.sweep(), 60_000);
  sweeper.unref();
  server.on('close', () => clearInterval(sweeper));
  // Keep held requests alive past the longest wait.
  server.requestTimeout = (LIMITS.waitSeconds + 10) * 1000;
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const port = Number(process.env.PORT) || 8788;
  createServer().listen(port, () => console.log(`Diamond Rush relay listening on port ${port}`));
}
