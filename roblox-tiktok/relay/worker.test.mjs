// Runs the relay against an in-memory SQLite database shaped like Cloudflare D1.
import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { handle, codeFor, cleanCode, LIMITS } from './worker.js';
import { codeFor as bridgeCodeFor } from '../bridge/cloud.mjs';

function fakeD1() {
  const sqlite = new DatabaseSync(':memory:');
  const statement = (sql, args = []) => ({
    bind: (...values) => statement(sql, values),
    first: async () => sqlite.prepare(sql).get(...args) ?? null,
    all: async () => ({ results: sqlite.prepare(sql).all(...args) }),
    run: async () => sqlite.prepare(sql).run(...args),
  });
  return {
    prepare: (sql) => statement(sql),
    batch: async (list) => { for (const s of list) await s.run(); return []; },
  };
}

const SECRET = 'a'.repeat(48);
function setUp() {
  let now = 1_000_000;
  const env = { DB: fakeD1() };
  const clock = () => now;
  const call = async (path, init) => {
    const response = await handle(new Request(`https://relay.test${path}`, init), env, clock);
    return { status: response.status, body: await response.json().catch(() => null) };
  };
  const push = (code, body, secret = SECRET) =>
    call(`/c/${code}/push`, { method: 'POST', headers: { 'x-relay-secret': secret }, body: JSON.stringify(body) });
  return { env, call, push, tick: (ms) => { now += ms; } };
}

test('game codes match the connector exactly', async () => {
  for (let i = 0; i < 200; i += 1) {
    const secret = `secret-${i * 7919}-${'z'.repeat(40)}`;
    assert.equal(await codeFor(secret), bridgeCodeFor(secret));
  }
  assert.equal(cleanCode('abcd efgh'), 'ABCDEFGH');
  assert.equal(cleanCode('ABCD-EFG0'), null); // 0 is not in the alphabet
});

test('a connector pushes, its game reads only its own events', async () => {
  const relay = setUp();
  const code = await codeFor(SECRET);
  const otherSecret = 'b'.repeat(48);
  const other = await codeFor(otherSecret);

  // A game that starts first gets the rules and where the events are up to.
  let reply = await relay.call(`/c/${code}/events?since=0`);
  assert.equal(reply.status, 200);
  assert.deepEqual(reply.body.events, []);
  assert.match(reply.body.tiktok, /waiting/);

  const rules = [{ id: 'r1', type: 'giftRule', gift: 'Rose', rocks: 10 }];
  reply = await relay.push(code, { events: [{ id: 's:1', type: 'gift', gift: 'Rose', count: 2 }], rules, tiktok: 'connected to @me' });
  assert.deepEqual(reply.body, { ok: true, received: 1 });
  relay.tick(300);
  await relay.push(other, { events: [{ id: 'o:1', type: 'gift', gift: 'Lion' }], tiktok: 'x' }, otherSecret);

  reply = await relay.call(`/c/${code}/events?since=0`);
  assert.deepEqual(reply.body.events, rules, 'a new game gets the rules, not old gifts');
  assert.equal(reply.body.tiktok, 'connected to @me');
  const start = reply.body.last;

  relay.tick(300);
  await relay.push(code, { events: [{ id: 's:2', type: 'gift', gift: 'Galaxy' }, { id: 's:3', type: 'like', likes: 5 }], tiktok: 'connected to @me' });
  reply = await relay.call(`/c/${code}/events?since=${start}`);
  assert.deepEqual(reply.body.events.map((e) => e.id), ['s:2', 's:3']);
  reply = await relay.call(`/c/${code}/events?since=${reply.body.last}`);
  assert.deepEqual(reply.body.events, [], 'nothing twice');
  reply = await relay.call(`/c/${other}/events?since=1`);
  assert.ok(reply.body.events.every((e) => e.id.startsWith('o:')), "another streamer's gifts stay theirs");
});

test('nobody else can push under a code', async () => {
  const relay = setUp();
  const code = await codeFor(SECRET);
  assert.equal((await relay.push(code, { events: [] }, 'c'.repeat(48))).status, 403);
  assert.equal((await relay.push(code, { events: [] }, '')).status, 403);
  assert.equal((await relay.call('/c/NOTACODE!/events')).status, 400);
});

test('pushing too fast is refused, and old events go', async () => {
  const relay = setUp();
  const code = await codeFor(SECRET);
  assert.equal((await relay.push(code, { events: [{ id: '1', type: 'gift' }] })).status, 200);
  assert.equal((await relay.push(code, { events: [{ id: '2', type: 'gift' }] })).status, 429);
  relay.tick(LIMITS.keepSeconds * 1000 + 1000);
  assert.equal((await relay.push(code, { events: [{ id: '3', type: 'gift' }] })).status, 200);
  const reply = await relay.call(`/c/${code}/events?since=1`);
  assert.deepEqual(reply.body.events.map((e) => e.id), ['3'], 'events older than ten minutes are gone');
});

test('a game waiting for gifts gets an answer when the wait runs out', async () => {
  const relay = setUp();
  const code = await codeFor(SECRET);
  await relay.push(code, { events: [{ id: '1', type: 'gift' }], tiktok: 'ok' });
  const started = Date.now();
  const reply = await relay.call(`/c/${code}/events?since=1&wait=0.5`);
  assert.deepEqual(reply.body.events, []);
  assert.ok(Date.now() - started < 3000);
});

test('the front page says it is running', async () => {
  const response = await handle(new Request('https://relay.test/'), {});
  assert.match(await response.text(), /running/);
});
