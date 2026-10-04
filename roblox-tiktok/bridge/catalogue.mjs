export const KEYS = ['', 'F6', 'F7', 'F8', 'J', 'K', 'L', 'U', 'I', 'O', 'P', 'B', 'N', 'M'];
export const STARTER = [['Rose',1],['Finger Heart',5],['Doughnut',30],['Hand Hearts',100],['Money Gun',500],['Galaxy',1000],['Lion',29999],['TikTok Universe',34999]].map(([name,coins])=>({id:name,name,coins}));
export function normalizeGifts(raw) {
 const list = Array.isArray(raw) ? raw : raw?.gifts ?? raw?.data?.gifts ?? [];
 const unique = new Map();
 for (const gift of list) {
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
