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

// How the bridge connects to a LIVE. enableExtendedGiftInfo fetches the gift
// list through Euler Stream's signing, a paid feature, so it stays off: gift
// messages already carry each gift's name and coins.
export const CONNECT_OPTIONS = { processInitialData: false, enableExtendedGiftInfo: false };

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
