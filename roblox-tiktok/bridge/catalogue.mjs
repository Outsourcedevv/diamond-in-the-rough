// Keys a gift can be bound to; the same letters as the game's GIFT KEYBINDS (src/shared/Keybinds.luau).
// I and O are Roblox's zoom keys, and P opens the game's settings, so none of them is offered.
export const KEYS = ['', 'F6', 'F7', 'F8', 'B', 'C', 'F', 'J', 'K', 'L', 'M', 'N', 'Q', 'R', 'T', 'U', 'V', 'X', 'Z'];
export async function fetchCatalogue(Client, username) {
 const client = new Client(username, {});
 await client.fetchRoomId();
 return normalizeGifts(await client.fetchAvailableGifts());
}
export const STARTER = [['Rose',1],['Ice Cream Cone',1],['Finger Heart',5],['Perfume',20],['Doughnut',30],['Hand Hearts',100],['Confetti',100],['Money Gun',500],['Galaxy',1000],['Lion',29999],['TikTok Universe',34999]].map(([name,coins])=>({id:name,name,coins}));
export function normalizeGifts(raw) {
 const list = Array.isArray(raw) ? raw : raw?.gifts ?? raw?.data?.gifts ?? [];
 const unique = new Map();
 if (!Array.isArray(list)) return [];
 for (const gift of list) {
  if (!gift || typeof gift !== "object") continue;
  const name=String(gift.name ?? '').trim().slice(0,40), coins=Number(gift.diamond_count ?? gift.diamondCount ?? gift.coins);
  if (!name || !Number.isFinite(coins) || coins<1) continue;
  const id=String(gift.id ?? name); unique.set(id,{id,name,coins:Math.floor(coins)});
 }
 return [...unique.values()].sort((a,b)=>a.coins-b.coins || a.name.localeCompare(b.name));
}
export function validateRule(body) {
 const gift=String(body.gift ?? '').trim().slice(0,40), coins=Number(body.coins), blocks=Number(body.blocks), keybind=String(body.keybind ?? '');
 if(!gift || !Number.isFinite(coins) || coins<1 || !Number.isInteger(blocks) || blocks<0 || blocks>1500000 || !['add','remove'].includes(body.action) || !KEYS.includes(keybind)) throw new Error('Choose a gift, add/remove, 0–1,500,000 whole blocks, and a supported key.');
 return {gift,coins:Math.floor(coins),rocks:body.action==='add' ? -blocks : blocks,keybind};
}

// Diamond Climb's and Chalkboard Count's own gift rules: how many platforms
// (or numbers) each gift moves you, up or down. Gifts without a rule go up
// by their coins. These defaults match Config.ClimbGiftRules and
// Config.ChalkGiftRules in the game (a fresh save starts with them too).
export const GAMES = {
 climb: { name: 'Diamond Climb', unit: 'platforms', max: 1000 },
 chalk: { name: 'Chalkboard Count', unit: 'numbers', max: 100000 },
};
const DOWN_DEFAULTS = [['Ice Cream Cone',1,2],['Finger Heart',5,4],['Perfume',20,9],['Confetti',100,20],['Money Gun',500,45],['TikTok Universe',34999,374]];
export function defaultGameRules() {
 const rules = {};
 for (const [gift,coins,amount] of DOWN_DEFAULTS) rules[gift.toLowerCase()] = {gift,coins,amount:-amount};
 return rules;
}
// How far a gift without a rule moves you (the game's own sum: a Rose 2,
// 100 coins 20, a Galaxy 63), for showing next to the choices.
export function coinsMove(coins) {
 return Math.max(1, Math.round(2 * Math.sqrt(Math.max(1, Number(coins) || 1))));
}
export function validateGameRule(body) {
 const game = GAMES[body.game];
 const gift = String(body.gift ?? '').trim().slice(0,40), coins = Number(body.coins), amount = Number(body.amount);
 if (!game || !gift) throw new Error('Choose a game and a gift.');
 if (body.remove === true) return {game: body.game, gift, remove: true};
 if (!Number.isFinite(coins) || coins < 1 || !Number.isInteger(amount) || amount < 0 || amount > game.max || !['up','down'].includes(body.direction))
  throw new Error(`Choose up or down and 0–${game.max.toLocaleString('en-US')} whole ${game.unit}.`);
 return {game: body.game, gift, coins: Math.floor(coins), amount: body.direction === 'down' ? -amount : amount};
}
