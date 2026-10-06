import test from 'node:test';
import assert from 'node:assert/strict';
import { rebuildTestEvent, createEventQueue, packMessages, REBUILD_TESTS } from './events.mjs';

test('all rebuild presets deliver signed block counts through polling and Open Cloud', () => {
  const queue = createEventQueue();
  const presets = [100, 1000, 10000, 50000, 100000, 1500000];
  for (const blocks of presets) {
    const event = rebuildTestEvent(blocks);
    assert.equal(event.rocks, -blocks);
    assert.equal(event.count, 1);
    assert.equal(event.type, 'gift');
    queue.push(event);
  }
  const added = presets.map(blocks => -blocks);
  assert.deepEqual(queue.since(0).map(e => e.rocks), added);
  assert.deepEqual(packMessages(queue.since(0)).flatMap(s => JSON.parse(s)).map(e => e.rocks), added);
});

test('each rebuild preset plays a different adding effect, smallest to biggest', () => {
  // The game's gift tiers start at 1, 10, 100, 500, 1,000 and 10,000 coins.
  assert.deepEqual(Object.keys(REBUILD_TESTS).map(Number).sort((a, b) => a - b).map(blocks => rebuildTestEvent(blocks).coins), [1, 10, 100, 500, 1000, 10000]);
});

test('rebuild test rejects invalid, destructive, excessive and non-numeric amounts', () => {
  for (const value of [0, -1000, 2, 1500001, '1000', null, NaN, Infinity]) {
    assert.throws(() => rebuildTestEvent(value));
  }
});
