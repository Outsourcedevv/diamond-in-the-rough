// Turns raw TikTok Live events into the small events the Roblox game reads,
// and keeps a numbered buffer the game can poll.
import { randomUUID } from 'node:crypto';

export function createEventQueue(limit = 1000) {
  const session = randomUUID().slice(0, 8);
  let sequence = 0;
  const events = [];
  return {
    session,
    get last() {
      return sequence;
    },
    push(event) {
      sequence += 1;
      const stamped = { ...event, id: `${session}:${sequence}`, seq: sequence };
      events.push(stamped);
      if (events.length > limit) events.shift();
      return stamped;
    },
    // Events after `since` (the game sends the last sequence number it saw).
    since(since) {
      return events.filter((event) => event.seq > since);
    },
  };
}

// Rebuild test presets: blocks added -> the coins that pick the game's adding
// effect (Pebble Drop up to Mountain Rising), smallest to biggest.
export const REBUILD_TESTS = { 100: 1, 1000: 10, 10000: 100, 50000: 500, 100000: 1000, 1500000: 10000 };

export function rebuildTestEvent(blocks) {
  if (typeof blocks !== 'number' || !Object.hasOwn(REBUILD_TESTS, blocks)) {
    throw new Error('Choose a supported rebuild test amount.');
  }
  return { type: 'gift', user: 'tester', name: 'Test viewer', gift: 'Rebuild test', coins: REBUILD_TESTS[blocks], count: 1, rocks: -blocks };
}

// The map themes the game can show: the alpine valley, sakura in blossom, or a ranch.
export const THEMES = { default: 'Alpine', sakura: 'Sakura', farm: 'Farm', desert: 'Desert', haunted: 'Haunted' };

export function themeEvent(theme) {
  if (!Object.hasOwn(THEMES, theme)) {
    throw new Error('Choose the alpine, sakura or farm theme.');
  }
  return { type: 'theme', name: 'Control page', theme };
}

// The mountain's skins: stone with a diamond, or a haystack with a needle.
export const SKINS = { stone: 'Stone & diamond', hay: 'Hay & needle' };

export function skinEvent(skin) {
  if (!Object.hasOwn(SKINS, skin)) {
    throw new Error('Choose stone and diamond, or hay and needle.');
  }
  return { type: 'skin', name: 'Control page', skin };
}

// The viewer. tiktok-live-connector 2.x sends TikTok's newer event layout
// (the @handle is displayId, the number is id); older versions used uniqueId
// and userId. Both are read.
function who(user) {
  const handle = user?.uniqueId || user?.displayId;
  return {
    user: String(handle || user?.userId || user?.id || 'someone').slice(0, 40),
    name: String(user?.nickname || handle || 'Someone').slice(0, 40),
  };
}

// TikTok sends a "streak" gift (giftType 1) again and again with a growing
// repeatCount, then once more with repeatEnd. Count only the new gifts each
// time so the mountain reacts during the streak and nothing is counted twice.
export function createGiftTracker() {
  const streaks = new Map();
  return function handleGift(data) {
    // The gift: `gift` { name, diamondCount, type } in TikTok's newer layout
    // (tiktok-live-connector 2.x), `giftDetails` { giftName, giftType } in the old one.
    const details = data.gift ?? data.giftDetails ?? {};
    const extended = data.extendedGiftInfo ?? {};
    const coins = Number(details.diamondCount ?? extended.diamond_count ?? extended.diamondCount ?? 1) || 1;
    const gift = String(details.name || details.giftName || extended.name || `Gift ${data.giftId ?? ''}`).trim();
    const repeat = Math.max(1, Number(data.repeatCount) || 1);
    const streakable = Number(details.type ?? details.giftType ?? data.giftType) === 1;
    const person = who(data.user);
    if (!streakable) {
      return { type: 'gift', ...person, gift, coins, count: repeat };
    }
    const key = `${person.user}:${data.giftId}:${data.groupId ?? ''}`;
    const now = Date.now();
    // A streak whose end never arrived (a dropped connection) is forgotten.
    for (const [old, streak] of streaks) if (now - streak.at > 120000) streaks.delete(old);
    const counted = streaks.get(key)?.count ?? 0;
    const fresh = Math.max(0, repeat - counted);
    if (data.repeatEnd) {
      streaks.delete(key);
    } else {
      streaks.set(key, { count: Math.max(counted, repeat), at: now });
    }
    if (fresh === 0) return null;
    return { type: 'gift', ...person, gift, coins, count: fresh };
  };
}

export function likeEvent(data) {
  const likes = Math.max(1, Number(data.likeCount ?? data.count) || 1);
  return { type: 'like', ...who(data.user), likes };
}

export function socialEvent(type, data) {
  return { type, ...who(data.user) };
}

// Open Cloud messages are limited to 1 kB: pack events into JSON lists that fit.
export function packMessages(events, maxBytes = 900) {
  const messages = [];
  let batch = [];
  for (const event of events) {
    const { seq, ...compact } = event;
    const candidate = [...batch, compact];
    if (batch.length > 0 && Buffer.byteLength(JSON.stringify(candidate)) > maxBytes) {
      messages.push(JSON.stringify(batch));
      batch = [compact];
    } else {
      batch = candidate;
    }
  }
  if (batch.length > 0) messages.push(JSON.stringify(batch));
  return messages;
}
