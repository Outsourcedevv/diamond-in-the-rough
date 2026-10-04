import test from 'node:test';
import assert from 'node:assert/strict';
import { createEventQueue, createGiftTracker, likeEvent, packMessages } from './events.mjs';

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

test('the queue numbers events and returns only newer ones', () => {
  const queue = createEventQueue(3);
  for (let i = 0; i < 5; i += 1) queue.push({ type: 'like', likes: i });
  assert.equal(queue.last, 5);
  assert.deepEqual(queue.since(3).map((e) => e.seq), [4, 5]);
  assert.equal(queue.since(0).length, 3, 'old events are dropped past the limit');
  assert.match(queue.since(4)[0].id, /^[0-9a-f]{8}:5$/);
});

test('open cloud messages stay under the size limit and keep every event', () => {
  const queue = createEventQueue();
  const events = [];
  for (let i = 0; i < 40; i += 1) events.push(queue.push({ type: 'gift', user: `user${i}`, name: `Viewer number ${i}`, gift: 'Rose', coins: 1, count: 1 }));
  const messages = packMessages(events);
  assert.ok(messages.length > 1);
  let total = 0;
  for (const message of messages) {
    assert.ok(Buffer.byteLength(message) <= 900);
    total += JSON.parse(message).length;
  }
  assert.equal(total, 40);
});
