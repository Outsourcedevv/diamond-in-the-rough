import test from 'node:test';
import assert from 'node:assert/strict';
import { codeFor, cleanCode, createRelay, createServer, CODE_ALPHABET, LIMITS } from './relay.mjs';

const secret = 'a'.repeat(32);
const code = codeFor(secret);
const gift = (n) => ({ id: `s1:${n}`, type: 'gift', user: 'ann', name: 'Ann', gift: 'Rose', coins: 1, count: 1 });
const rule = { id: 'rules:s1:rose', type: 'giftRule', gift: 'Rose', coins: 1, rocks: 500 };

test('a game code is 8 easy-to-read characters worked out from the secret', () => {
  assert.equal(code.length, 8);
  assert.ok([...code].every((c) => CODE_ALPHABET.includes(c)));
  assert.equal(codeFor(secret), code);
  assert.notEqual(codeFor('b'.repeat(32)), code);
  assert.equal(cleanCode(` ${code.slice(0, 4).toLowerCase()}-${code.slice(4)} `), code);
  assert.equal(cleanCode('ABCD-EFG0'), null);
  assert.equal(cleanCode('ABC'), null);
});

test('only the bridge with the secret can send gifts under its code', () => {
  const relay = createRelay();
  assert.equal(relay.push(code, 'b'.repeat(32), { events: [gift(1)] }).status, 403);
  assert.equal(relay.push(code, 'short', { events: [gift(1)] }).status, 403);
  assert.equal(relay.push(code, secret, { events: [gift(1)] }).status, 200);
});

test('a game gets its own events, its rules on a fresh start, and nobody else\'s', async () => {
  const relay = createRelay();
  const other = 'c'.repeat(32);
  relay.push(code, secret, { events: [gift(1), gift(2)], rules: [rule], tiktok: 'connected to @ann' });
  relay.push(codeFor(other), other, { events: [{ ...gift(9), id: 'other:9' }] });
  const first = (await relay.events(code)).body;
  assert.equal(first.tiktok, 'connected to @ann');
  assert.deepEqual(first.events.map((e) => e.id), ['rules:s1:rose', 's1:1', 's1:2']);
  assert.equal(first.last, 2);
  relay.push(code, secret, { events: [gift(3)] });
  const next = (await relay.events(code, { since: first.last, session: first.session })).body;
  assert.deepEqual(next.events.map((e) => e.id), ['s1:3']);
  // A different session (the relay restarted) starts again with the rules.
  const restarted = (await relay.events(code, { since: 3, session: 'old' })).body;
  assert.equal(restarted.events[0].id, 'rules:s1:rose');
  assert.equal(restarted.events.length, 4);
  // The rules are not sent again to a game that already has them, even while
  // no gift has been sent yet (the rules carry no sequence number).
  const quiet = createRelay();
  quiet.push(code, secret, { rules: [rule] });
  const opening = (await quiet.events(code)).body;
  assert.deepEqual(opening.events.map((e) => e.id), ['rules:s1:rose']);
  assert.equal(opening.last, 0);
  const again = (await quiet.events(code, { since: opening.last, session: opening.session })).body;
  assert.deepEqual(again.events, []);
});

test('a waiting game is answered as soon as a gift arrives', async () => {
  const relay = createRelay();
  relay.push(code, secret, { events: [gift(1)] });
  const { session, last } = (await relay.events(code)).body;
  const started = Date.now();
  const waiting = relay.events(code, { since: last, session, wait: 10 });
  setTimeout(() => relay.push(code, secret, { events: [gift(2)] }), 50);
  const answer = (await waiting).body;
  assert.ok(Date.now() - started < 2000);
  assert.deepEqual(answer.events.map((e) => e.id), ['s1:2']);
});

test('a status-only push does not wake a waiting game, and waits end on time', async () => {
  const relay = createRelay({ limits: { ...LIMITS, waitSeconds: 0.2 } });
  relay.push(code, secret, { events: [gift(1)] });
  const { session, last } = (await relay.events(code)).body;
  const waiting = relay.events(code, { since: last, session, wait: 5 });
  relay.push(code, secret, { tiktok: 'connected' });
  const started = Date.now();
  const answer = (await waiting).body;
  assert.equal(answer.events.length, 0);
  assert.equal(answer.tiktok, 'connected');
  assert.ok(Date.now() - started < 1000);
});

test('an unknown code waits for its bridge, and bad codes are refused', async () => {
  const relay = createRelay();
  const answer = await relay.events('ABCDEFGH');
  assert.equal(answer.status, 200);
  assert.equal(answer.body.session, '');
  assert.match(answer.body.tiktok, /waiting for your bridge/);
  assert.equal((await relay.events('nope')).status, 400);
  assert.equal(relay.channels.size, 0);
});

test('channels keep a limited number of recent events, and idle ones are dropped', async () => {
  let time = 0;
  const relay = createRelay({ now: () => time, limits: { ...LIMITS, events: 5, eventSeconds: 60, idleSeconds: 120 } });
  relay.push(code, secret, { events: Array.from({ length: 8 }, (_, i) => gift(i + 1)) });
  assert.deepEqual((await relay.events(code)).body.events.map((e) => e.id), ['s1:4', 's1:5', 's1:6', 's1:7', 's1:8']);
  time = 61_000;
  assert.equal((await relay.events(code)).body.events.length, 0);
  assert.equal(relay.push(code, secret, { events: Array.from({ length: 301 }, (_, i) => gift(i)) }).status, 413);
  time = 400_000;
  relay.sweep();
  assert.equal(relay.channels.size, 0);
});

test('the HTTP server speaks the bridge\'s /events shape', async () => {
  const server = createServer();
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    const pushed = await fetch(`${base}/c/${code}/push`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-relay-secret': secret }, body: JSON.stringify({ events: [gift(1)], rules: [rule], tiktok: 'connected' }) });
    assert.equal(pushed.status, 200);
    const bad = await fetch(`${base}/c/${code}/push`, { method: 'POST', headers: { 'x-relay-secret': 'x'.repeat(32) }, body: '{}' });
    assert.equal(bad.status, 403);
    // A code typed with a dash or in lower case still works.
    const polled = await (await fetch(`${base}/c/${code.slice(0, 4).toLowerCase()}-${code.slice(4)}/events?since=0`)).json();
    assert.equal(polled.events.length, 2);
    assert.equal((await (await fetch(`${base}/c/nope/events`)).json()).error, 'Not a game code.');
    const data = await (await fetch(`${base}/c/${code}/events?since=0&session=`)).json();
    assert.deepEqual(Object.keys(data).sort(), ['events', 'last', 'session', 'tiktok']);
    assert.equal(data.events.length, 2);
    assert.equal((await fetch(`${base}/`)).status, 200);
    assert.equal((await fetch(`${base}/c/${code}/push`, { method: 'POST', headers: { 'x-relay-secret': secret }, body: 'not json' })).status, 400);
  } finally {
    server.close();
  }
});
