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

function who(user) {
  return {
    user: String(user?.uniqueId ?? user?.userId ?? 'someone').slice(0, 40),
    name: String(user?.nickname || user?.uniqueId || 'Someone').slice(0, 40),
  };
}

// TikTok sends a "streak" gift (giftType 1) again and again with a growing
// repeatCount, then once more with repeatEnd. Count only the new gifts each
// time so the mountain reacts during the streak and nothing is counted twice.
export function createGiftTracker() {
  const streaks = new Map();
  return function handleGift(data) {
    const details = data.giftDetails ?? {};
    const extended = data.extendedGiftInfo ?? {};
    const coins = Number(details.diamondCount ?? extended.diamond_count ?? 1) || 1;
    const gift = String(details.giftName || extended.name || `Gift ${data.giftId ?? ''}`).trim();
    const repeat = Math.max(1, Number(data.repeatCount) || 1);
    const streakable = Number(details.giftType ?? data.giftType) === 1;
    const person = who(data.user);
    if (!streakable) {
      return { type: 'gift', ...person, gift, coins, count: repeat };
    }
    const key = `${person.user}:${data.giftId}:${data.groupId ?? ''}`;
    const counted = streaks.get(key) ?? 0;
    const fresh = Math.max(0, repeat - counted);
    if (data.repeatEnd) {
      streaks.delete(key);
    } else {
      streaks.set(key, Math.max(counted, repeat));
    }
    if (fresh === 0) return null;
    return { type: 'gift', ...person, gift, coins, count: fresh };
  };
}

export function likeEvent(data) {
  const likes = Math.max(1, Number(data.likeCount) || 1);
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
