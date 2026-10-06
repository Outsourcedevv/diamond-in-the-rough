import test from 'node:test';
import assert from 'node:assert/strict';
import { themeEvent, skinEvent, createEventQueue, packMessages } from './events.mjs';

test('theme events reach the game through polling and Open Cloud', () => {
  const queue = createEventQueue();
  const themes = ['sakura', 'farm', 'desert', 'haunted', 'default'];
  for (const theme of themes) queue.push(themeEvent(theme));
  assert.deepEqual(queue.since(0).map(e => [e.type, e.theme]), themes.map(theme => ['theme', theme]));
  assert.deepEqual(packMessages(queue.since(0)).flatMap(s => JSON.parse(s)).map(e => e.theme), themes);
});

test('only the five map themes are accepted', () => {
  for (const value of ['', 'Sakura', 'Farm', 'Desert', 'winter', 'constructor', '__proto__', null, undefined, 1]) {
    assert.throws(() => themeEvent(value));
  }
});

test('skin events carry stone or hay, and nothing else', () => {
  const queue = createEventQueue();
  for (const skin of ['hay', 'stone']) queue.push(skinEvent(skin));
  assert.deepEqual(packMessages(queue.since(0)).flatMap(s => JSON.parse(s)).map(e => [e.type, e.skin]), [['skin', 'hay'], ['skin', 'stone']]);
  for (const value of ['', 'Hay', 'gold', 'toString', null, 2]) assert.throws(() => skinEvent(value));
});
