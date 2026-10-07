import test from 'node:test';
import assert from 'node:assert/strict';
import { codeFor, topicFor, parseCloudFile, mergeEvents, takeMessage, ruleId, CODE_ALPHABET, CODE_LENGTH, MESSAGE_BYTES } from './cloud.mjs';

test('a game code is 8 easy-to-read characters, the same for the same secret', () => {
  const code = codeFor('a'.repeat(48));
  assert.equal(code.length, CODE_LENGTH);
  assert.ok([...code].every((c) => CODE_ALPHABET.includes(c)));
  assert.equal(codeFor('a'.repeat(48)), code);
  assert.notEqual(codeFor('b'.repeat(48)), code);
  assert.ok(topicFor(code).length <= 80); // Roblox's topic limit
});

test('roblox-cloud.txt can be written loosely', () => {
  const key = 'Xy'.repeat(40);
  assert.deepEqual(parseCloudFile(`universe: 1234567890\nkey: ${key}\n`), { universeId: '1234567890', apiKey: key });
  assert.deepEqual(parseCloudFile(`Universe ID = 987654321\r\nAPI key = ${key}`), { universeId: '987654321', apiKey: key });
  assert.deepEqual(parseCloudFile(`987654321\n${key}`), { universeId: '987654321', apiKey: key });
  assert.deepEqual(parseCloudFile(''), { universeId: '', apiKey: '' });
});

test('busy streams fold together without losing gifts or likes', () => {
  const events = [
    { id: '1', type: 'gift', user: 'a', name: 'A', gift: 'Rose', coins: 1, count: 3 },
    { id: '2', type: 'like', user: 'b', name: 'B', likes: 5 },
    { id: '3', type: 'gift', user: 'c', name: 'C', gift: 'Rose', coins: 1, count: 1 },
    { id: '4', type: 'gift', user: 'a', name: 'A', gift: 'Rose', coins: 1, count: 2 },
    { id: '5', type: 'like', user: 'c', name: 'C', likes: 7 },
    { id: '6', type: 'follow', user: 'd', name: 'D' },
    { id: '7', type: 'giftRule', gift: 'Rose', rocks: 10 },
    { id: '8', type: 'giftRule', gift: 'rose', rocks: 20 },
    { id: '9', type: 'status', tiktok: 'connecting' },
    { id: '10', type: 'status', tiktok: 'connected to @x' },
  ];
  const merged = mergeEvents(events);
  const gifts = merged.filter((e) => e.type === 'gift');
  assert.deepEqual(gifts.map((e) => [e.user, e.count]), [['a', 5], ['c', 1]]);
  assert.deepEqual(merged.filter((e) => e.type === 'like').map((e) => e.likes), [12]);
  assert.equal(merged.filter((e) => e.type === 'follow').length, 1);
  assert.deepEqual(merged.filter((e) => e.type === 'giftRule').map((e) => e.rocks), [20]);
  assert.deepEqual(merged.filter((e) => e.type === 'status').map((e) => e.tiktok), ['connected to @x']);
  assert.equal(events[0].count, 3); // the originals are untouched
});

test('each message fits in 1 kB and nothing is lost across messages', () => {
  const queue = [];
  for (let i = 0; i < 300; i += 1) queue.push({ id: `s:${i}`, type: 'gift', user: `viewer${i}`, name: `Viewer number ${i}`, gift: 'Galaxy', coins: 1000, count: 1 });
  let total = 0;
  let messages = 0;
  for (let message = takeMessage(queue); message; message = takeMessage(queue)) {
    assert.ok(Buffer.byteLength(message) <= MESSAGE_BYTES);
    total += JSON.parse(message).reduce((sum, e) => sum + e.count, 0);
    messages += 1;
  }
  assert.equal(total, 300);
  assert.ok(messages > 1);
  assert.equal(takeMessage([]), null);
});

test('a rule keeps its id while it stays the same', () => {
  assert.equal(ruleId({ gift: 'Rose', rocks: 5 }), ruleId({ gift: 'Rose', rocks: 5 }));
  assert.notEqual(ruleId({ gift: 'Rose', rocks: 5 }), ruleId({ gift: 'Rose', rocks: 6 }));
});

test('the key is hidden in the program and read back', async () => {
  const { SLOT } = await import('./sealed-slot.mjs');
  const { sealBinary, readSlot, SLOT_SIZE } = await import('./cloud.mjs');
  assert.equal(SLOT.length, SLOT_SIZE);
  assert.equal(readSlot(SLOT), null); // an unsealed program has no key
  const settings = { universeId: '1234567890', apiKey: 'Zk'.repeat(600) };
  const program = Buffer.concat([Buffer.from('MZ program start\0'), Buffer.from(`const SLOT = '${SLOT}';`), Buffer.from('\0the end')]);
  const sealed = sealBinary(program, settings);
  assert.equal(sealed.length, program.length);
  assert.ok(!sealed.includes(Buffer.from(settings.apiKey)), 'the key is not in plain sight');
  const start = sealed.indexOf(Buffer.from('DRSEAL1['));
  assert.deepEqual(readSlot(sealed.subarray(start, start + SLOT_SIZE).toString('latin1')), settings);
  // Sealing again (a new key) works on an already sealed copy.
  const again = sealBinary(sealed, { universeId: '42424242', apiKey: 'Q'.repeat(900) });
  assert.equal(readSlot(again.subarray(start, start + SLOT_SIZE).toString('latin1')).universeId, '42424242');
  assert.throws(() => sealBinary(Buffer.from('no slot here'), settings));
  assert.throws(() => sealBinary(program, { universeId: '1', apiKey: 'x'.repeat(5000) }));
});
