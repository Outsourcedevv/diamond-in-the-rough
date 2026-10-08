// How the connector reaches the published game: through the Diamond Rush relay
// (relay/worker.js, hosted on Cloudflare), under this PC's game code. No Roblox
// key is involved: the relay checks the connector's secret, and the game asks
// the relay for its code's events.
import { createHash } from 'node:crypto';

// The relay's address, built into every connector. The game has the same one
// (Config.RelayUrl). A connector's config.json may say otherwise (relayUrl).
export const RELAY_URL = 'https://diamond-rush-relay.diamondbridgeconnector.workers.dev';

// Letters and digits that can't be mixed up (no 0/O, 1/I).
export const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
export const CODE_LENGTH = 8;

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

// An id for a rule that stays the same while the rule does, so a game that
// already has it skips the repeat and a game that just started takes it.
export function ruleId(rule) {
  return `r${createHash('sha256').update(JSON.stringify(rule)).digest('hex').slice(0, 12)}`;
}

// Updating the published game -------------------------------------------------
// The owner's connector can upload a new place file straight to Roblox (Open
// Cloud place publishing), for when Studio's own publish gets stuck. This uses
// an Open Cloud key that may publish the place; it stays in the owner's
// config.json and never goes anywhere else.
export function placeVersionUrl(universeId, placeId) {
  return `https://apis.roblox.com/universes/v1/${encodeURIComponent(universeId)}/places/${encodeURIComponent(placeId)}/versions?versionType=Published`;
}

// The content type for a place file, or null if it isn't one: .rbxl files
// start "<roblox!" (binary), .rbxlx files "<roblox " (XML).
export function placeFileType(data) {
  const head = Buffer.from(data.subarray(0, 64)).toString('latin1').replace(/^\uFEFF|^\xEF\xBB\xBF/, '').trimStart();
  if (head.startsWith('<roblox!')) return 'application/octet-stream';
  if (/^<roblox[\s>]/.test(head)) return 'application/xml';
  return null;
}
