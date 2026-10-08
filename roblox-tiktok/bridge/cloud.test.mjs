import test from 'node:test';
import assert from 'node:assert/strict';
import { codeFor, placeFileType, placeVersionUrl, CODE_ALPHABET, CODE_LENGTH } from './cloud.mjs';

test('a game code is 8 easy-to-read characters, the same for the same secret', () => {
  const code = codeFor('a'.repeat(48));
  assert.equal(code.length, CODE_LENGTH);
  assert.ok([...code].every((c) => CODE_ALPHABET.includes(c)));
  assert.equal(codeFor('a'.repeat(48)), code);
  assert.notEqual(codeFor('b'.repeat(48)), code);
});

test('place files are recognised and sent to the right address', () => {
  assert.equal(placeFileType(Buffer.from('<roblox xmlns:xmime="x" version="4">')), 'application/xml');
  assert.equal(placeFileType(Buffer.from('﻿<roblox version="4">')), 'application/xml');
  assert.equal(placeFileType(Buffer.from('<roblox!\x89\xff\r\n')), 'application/octet-stream');
  assert.equal(placeFileType(Buffer.from('PK zip file')), null);
  assert.equal(placeVersionUrl('111', '222'), 'https://apis.roblox.com/universes/v1/111/places/222/versions?versionType=Published');
});
