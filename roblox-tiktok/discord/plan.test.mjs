import test from 'node:test';
import assert from 'node:assert/strict';
import { CHANNELS, ROLES, AUTOMOD, GUILD, EVERYONE, P, posts } from './plan.mjs';

const all = CHANNELS.flatMap((group) => group.channels.map((channel) => ({ ...channel, group })));
const byKey = Object.fromEntries(all.map((c) => [c.key, c]));

test('bug reports have a one hour cooldown', () => {
  assert.equal(byKey.bugs.name, 'bug-reports');
  assert.equal(byKey.bugs.slowmode, 3600);
});

test('rules, announcements and the download channel are read-only', () => {
  for (const key of ['rules', 'announcements', 'download']) assert.equal(byKey[key].access, 'readonly');
});

test('the staff log is hidden from everyone but moderators', () => {
  assert.equal(byKey.modlog.group.staff, true);
});

test('everyone cannot ping @everyone or make invites; moderators can moderate', () => {
  assert.equal(EVERYONE & P.MENTION_EVERYONE, 0n);
  assert.equal(EVERYONE & P.CREATE_INVITE, 0n);
  const mod = ROLES.find((r) => r.key === 'moderator').permissions;
  for (const bit of [P.KICK, P.BAN, P.MANAGE_MESSAGES, P.MODERATE_MEMBERS]) assert.notEqual(mod & bit, 0n);
});

test('safety: high verification, media scanning and AutoMod', () => {
  assert.equal(GUILD.verification_level, 3);
  assert.equal(GUILD.explicit_content_filter, 2);
  assert.deepEqual(AUTOMOD.map((r) => r.trigger_type).sort(), [1, 3, 4, 5]);
});

test('the download post carries the link, and fits in one Discord message', () => {
  const text = posts('https://example.com/DiamondRushBridge.exe');
  assert.match(text.download, /example\.com\/DiamondRushBridge\.exe/);
  for (const body of Object.values(text)) assert.ok(body.length <= 2000);
});
