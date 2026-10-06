import test from 'node:test';
import assert from 'node:assert/strict';
import { themeEvent, skinEvent, createEventQueue, packMessages } from './events.mjs';

test('theme events reach the game through polling and Open Cloud', () => {
  const queue = createEventQueue();
  for (const theme of ['sakura', 'farm', 'default']) queue.push(themeEvent(theme));
  assert.deepEqual(queue.since(0).map(e => [e.type, e.theme]), [['theme', 'sakura'], ['theme', 'farm'], ['theme', 'default']]);
  assert.deepEqual(packMessages(queue.since(0)).flatMap(s => JSON.parse(s)).map(e => e.theme), ['sakura', 'farm', 'default']);
});

test('only the alpine, sakura and farm themes are accepted', () => {
  for (const value of ['', 'Sakura', 'Farm', 'winter', 'constructor', '__proto__', null, undefined, 1]) {
    assert.throws(() => themeEvent(value));
  }
});

test('skin events carry stone or hay, and nothing else', () => {
  const queue = createEventQueue();
  for (const skin of ['hay', 'stone']) queue.push(skinEvent(skin));
  assert.deepEqual(packMessages(queue.since(0)).flatMap(s => JSON.parse(s)).map(e => [e.type, e.skin]), [['skin', 'hay'], ['skin', 'stone']]);
  for (const value of ['', 'Hay', 'gold', 'toString', null, 2]) assert.throws(() => skinEvent(value));
});
