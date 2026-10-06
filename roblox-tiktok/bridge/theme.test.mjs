import test from 'node:test';
import assert from 'node:assert/strict';
import { themeEvent, createEventQueue, packMessages } from './events.mjs';

test('theme events reach the game through polling and Open Cloud', () => {
  const queue = createEventQueue();
  for (const theme of ['sakura', 'default']) queue.push(themeEvent(theme));
  assert.deepEqual(queue.since(0).map(e => [e.type, e.theme]), [['theme', 'sakura'], ['theme', 'default']]);
  assert.deepEqual(packMessages(queue.since(0)).flatMap(s => JSON.parse(s)).map(e => e.theme), ['sakura', 'default']);
});

test('only the alpine and sakura themes are accepted', () => {
  for (const value of ['', 'Sakura', 'winter', 'constructor', '__proto__', null, undefined, 1]) {
    assert.throws(() => themeEvent(value));
  }
});
