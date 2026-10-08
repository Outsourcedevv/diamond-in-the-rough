import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createEventQueue, createGiftTracker, likeEvent, CONNECT_OPTIONS } from './events.mjs';

const rose = (repeatCount, repeatEnd) => ({
  giftId: 5655,
  repeatCount,
  repeatEnd,
  user: { uniqueId: 'fan1', nickname: 'Fan One' },
  giftDetails: { giftName: 'Rose', diamondCount: 1, giftType: 1 },
});

test('a streak counts each gift exactly once', () => {
  const handle = createGiftTracker();
  const counts = [rose(1, false), rose(2, false), rose(5, false), rose(5, true)].map((event) => handle(event)?.count ?? 0);
  assert.deepEqual(counts, [1, 1, 3, 0]);
});

test('a single streak gift also arrives with repeatEnd and is not doubled', () => {
  const handle = createGiftTracker();
  assert.equal(handle(rose(1, false)).count, 1);
  assert.equal(handle(rose(1, true)), null);
  // A new streak starts fresh after the old one ended.
  assert.equal(handle(rose(1, false)).count, 1);
});

test('non-streak gifts count their repeat count at once', () => {
  const handle = createGiftTracker();
  const universe = handle({ giftId: 7, repeatCount: 1, repeatEnd: true, user: { uniqueId: 'big' }, giftDetails: { giftName: 'TikTok Universe', diamondCount: 34999, giftType: 2 } });
  assert.deepEqual([universe.coins, universe.count, universe.gift, universe.name], [34999, 1, 'TikTok Universe', 'big']);
});

test('likes carry their batch size', () => {
  assert.equal(likeEvent({ likeCount: 15, user: { uniqueId: 'a' } }).likes, 15);
});

// tiktok-live-connector 2.x passes on TikTok's newer layout: the gift is under
// `gift`, ids are strings, the viewer's handle is displayId, likes are `count`.
const newRose = (repeatCount, repeatEnd, displayId = 'fan1') => ({
  giftId: '5655',
  repeatCount,
  repeatEnd: repeatEnd ? 1 : 0,
  groupId: '77',
  user: { id: '6800000000000000001', displayId, nickname: 'Fan One' },
  gift: { id: '5655', name: 'Rose', diamondCount: 1, type: 1 },
});

test('the newer event layout: a streak counts each gift once, with its name and coins', () => {
  const handle = createGiftTracker();
  const events = [newRose(1, false), newRose(2, false), newRose(5, false), newRose(5, true)].map((event) => handle(event));
  assert.deepEqual(events.map((event) => event?.count ?? 0), [1, 1, 3, 0]);
  assert.deepEqual([events[0].gift, events[0].coins, events[0].user, events[0].name], ['Rose', 1, 'fan1', 'Fan One']);
});

test('the newer event layout: big gifts, viewers and likes', () => {
  const handle = createGiftTracker();
  const galaxy = handle({ giftId: '11046', repeatCount: 1, repeatEnd: 1, user: { id: '1', displayId: 'big', nickname: 'Big Fan' },
    gift: { id: '11046', name: 'Galaxy', diamondCount: 1000, type: 2 } });
  assert.deepEqual([galaxy.gift, galaxy.coins, galaxy.count, galaxy.user], ['Galaxy', 1000, 1, 'big']);
  // Two viewers never share a leaderboard row.
  assert.notEqual(handle(newRose(1, false, 'a')).user, handle(newRose(1, false, 'b')).user);
  assert.equal(likeEvent({ count: 15, user: { displayId: 'a' } }).likes, 15);
});

test('the queue numbers events and returns only newer ones', () => {
  const queue = createEventQueue(3);
  for (let i = 0; i < 5; i += 1) queue.push({ type: 'like', likes: i });
  assert.equal(queue.last, 5);
  assert.deepEqual(queue.since(3).map((e) => e.seq), [4, 5]);
  assert.equal(queue.since(0).length, 3, 'old events are dropped past the limit');
  assert.match(queue.since(4)[0].id, /^[0-9a-f]{8}:5$/);
});

test('connecting never asks for the paid gift list', () => {
  assert.equal(CONNECT_OPTIONS.enableExtendedGiftInfo, false);
  const source = fs.readFileSync(new URL('./bridge.mjs', import.meta.url), 'utf8');
  assert.match(source, /new TikTokLiveConnection\(username, CONNECT_OPTIONS\)/);
  assert.doesNotMatch(source, /enableExtendedGiftInfo:\s*true/);
});

test('the connector only passes on real LIVE events; gift settings live in the game', () => {
  const bridge = fs.readFileSync(new URL('./bridge.mjs', import.meta.url), 'utf8');
  const page = fs.readFileSync(new URL('./control.html', import.meta.url), 'utf8');
  // No pretend gifts, and none of the old rule, theme or skin controls.
  for (const route of ['/test', '/catalogue', '/game-rule', '/theme', '/skin']) {
    assert.doesNotMatch(bridge, new RegExp(`pathname === '${route}`));
    assert.doesNotMatch(page, new RegExp(`['"\`]${route}['"\`/]`));
  }
  assert.doesNotMatch(bridge, /rocks/);
  assert.match(bridge, /rules: \[\]/);
});
