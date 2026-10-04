import test from 'node:test';
import assert from 'node:assert/strict';
import { rebuildTestEvent, createEventQueue, packMessages } from './events.mjs';

test('all rebuild presets deliver signed block counts through polling and Open Cloud', () => {
  const queue = createEventQueue();
  for (const blocks of [1000, 10000, 100000, 1500000]) {
    const event = rebuildTestEvent(blocks);
    assert.equal(event.rocks, -blocks);
    assert.equal(event.count, 1);
    assert.equal(event.type, 'gift');
    queue.push(event);
  }
  assert.deepEqual(queue.since(0).map(e => e.rocks), [-1000, -10000, -100000, -1500000]);
  assert.deepEqual(packMessages(queue.since(0)).flatMap(s => JSON.parse(s)).map(e => e.rocks), [-1000, -10000, -100000, -1500000]);
});

test('rebuild test rejects invalid, destructive, excessive and non-numeric amounts', () => {
  for (const value of [0, -1000, 2, 1500001, '1000', null, NaN, Infinity]) {
    assert.throws(() => rebuildTestEvent(value));
  }
});
