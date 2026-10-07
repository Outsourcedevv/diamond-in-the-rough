// Sending to the published game through Roblox Open Cloud MessagingService.
//
// Every streamer's bridge has a game code, worked out from a secret made once
// on their PC. The bridge publishes to the topic for that code, and the
// streamer's Roblox server, once they type the code in the Y panel, subscribes
// to that topic only, so each streamer gets their own gifts and nobody hosts a
// server. Roblox lets one topic receive about 30 messages a minute (with one
// server listening) and each message is at most 1 kB, so the bridge sends one
// message every few seconds and packs (and, when busy, merges) events into it.
import { createHash } from 'node:crypto';

// Letters and digits that can't be mixed up (no 0/O, 1/I).
export const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
export const CODE_LENGTH = 8;
// Must match Config.MessagingTopicPrefix in the game.
export const TOPIC_PREFIX = 'DiamondRush_';
export const SEND_EVERY_MS = 2500; // 24 messages a minute: under the topic's limit
export const MESSAGE_BYTES = 950; // Roblox allows 1 kB

// The game code for a bridge's secret: 8 characters (40 bits) of its SHA-256.
export function codeFor(secret) {
  const digest = createHash('sha256').update(String(secret)).digest();
  let bits = 0;
  let value = 0;
  let code = '';
  for (const byte of digest) {
    value = ((value << 8) | byte) & 0xffff;
    bits += 8;
    while (bits >= 5 && code.length < CODE_LENGTH) {
      bits -= 5;
      code += CODE_ALPHABET[(value >> bits) & 31];
    }
    if (code.length === CODE_LENGTH) break;
  }
  return code;
}

export function topicFor(code) {
  return `${TOPIC_PREFIX}${code}`;
}

// The game owner's Open Cloud key and universe, from roblox-cloud.txt next to
// the bridge. Written however is easiest, e.g.
//   universe: 1234567890
//   key: AbCd...
export function parseCloudFile(text) {
  const source = String(text ?? '');
  const universe = source.match(/universe[^:=\d]*[:=]?\s*(\d{5,})/i)?.[1] ?? source.match(/\b(\d{6,})\b/)?.[1] ?? '';
  let apiKey = source.match(/key[^:=]*[:=]\s*(\S+)/i)?.[1] ?? '';
  if (!apiKey) apiKey = source.split(/\s+/).filter((word) => word.length >= 40).sort((a, b) => b.length - a.length)[0] ?? '';
  return { universeId: universe, apiKey };
}

function same(a, b, keys) {
  return keys.every((key) => a[key] === b[key]);
}

// When events pile up (a gift storm), fold them together so fewer messages
// carry the same gifts: a viewer's repeated gift becomes one with a bigger
// count, likes add up into one, and only the newest of a rule, theme, skin or
// status matters. The order of what's left is kept.
export function mergeEvents(events) {
  const out = [];
  let likes = null;
  for (const event of events) {
    if (event.type === 'gift') {
      const match = out.find((other) => other.type === 'gift' && same(other, event, ['user', 'gift', 'coins', 'rocks']));
      if (match) { match.count = (match.count ?? 1) + (event.count ?? 1); continue; }
    } else if (event.type === 'like') {
      if (likes) { likes.likes += event.likes ?? 1; likes.user = event.user; likes.name = event.name; continue; }
      likes = { ...event, likes: event.likes ?? 1 };
      out.push(likes);
      continue;
    } else if (/Rule$/.test(event.type) || event.type === 'theme' || event.type === 'skin' || event.type === 'status') {
      const rule = /Rule$/.test(event.type);
      const index = out.findIndex((other) => other.type === event.type && (!rule || String(other.gift).toLowerCase() === String(event.gift).toLowerCase()));
      if (index !== -1) out.splice(index, 1);
    }
    out.push({ ...event });
  }
  return out;
}

// Takes as many events off the front of the queue as fit in one message.
// Returns the message (a JSON list) or null when the queue is empty.
export function takeMessage(queue, maxBytes = MESSAGE_BYTES) {
  if (queue.length === 0) return null;
  if (queue.length > 1) queue.splice(0, queue.length, ...mergeEvents(queue));
  const batch = [];
  let size = 2;
  while (queue.length > 0) {
    const text = JSON.stringify(queue[0]);
    const bytes = Buffer.byteLength(text) + (batch.length > 0 ? 1 : 0);
    if (size + bytes > maxBytes) {
      // One event too big for any message (it can't be: names are short) is dropped.
      if (batch.length === 0) { queue.shift(); continue; }
      break;
    }
    batch.push(queue.shift());
    size += bytes;
  }
  return batch.length > 0 ? JSON.stringify(batch) : null;
}

// An id for a rule that stays the same while the rule does, so a game that
// already has it skips the repeat and a game that just started takes it.
export function ruleId(rule) {
  return `r${createHash('sha256').update(JSON.stringify(rule)).digest('hex').slice(0, 12)}`;
}
