import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeGifts, validateRule, fetchCatalogue, validateGameRule, defaultGameRules, coinsMove, CONNECT_OPTIONS, learnGift, catalogueError, mergeGifts, STARTER } from './catalogue.mjs';
import fs from 'node:fs';

test('catalogue resolves the LIVE room before retrieving every gift', async () => {
 let resolved = false;
 class Client {
  constructor(username, options) { assert.equal(username, 'Swillplays'); assert.deepEqual(options, {}); }
  async fetchRoomId() { resolved = true; }
  async fetchAvailableGifts() {
   assert.equal(resolved, true);
   return {gifts: Array.from({length: 1000}, (_, id) => ({id, name: `Gift ${id}`, diamond_count: id + 1}))};
  }
 }
 assert.equal((await fetchCatalogue(Client, 'Swillplays')).length, 1000);
});
test('catalogue accepts TikTok and cached gift formats, deduplicates IDs, and sorts prices',()=>{
 const rows=normalizeGifts([{id:2,name:'Galaxy',diamond_count:1000},{id:1,name:'Rose',coins:1},{id:1,name:'Rose',diamondCount:1},{id:3,name:'Bad',coins:NaN}]);
 assert.deepEqual(rows.map(g=>g.name),['Rose','Galaxy']);assert.equal(rows[1].coins,1000);
 assert.equal(normalizeGifts({data:{gifts:[{id:4,name:'Other',diamond_count:500}]}})[0].coins,500);
});
test('add/remove rules retain exact signed block amounts and validate shortcuts',()=>{
 assert.deepEqual(validateRule({gift:'Rose',coins:1,action:'add',blocks:200,keybind:'K'}),{gift:'Rose',coins:1,rocks:-200,keybind:'K'});
 assert.equal(validateRule({gift:'Galaxy',coins:1000,action:'remove',blocks:1234,keybind:''}).rocks,1234);
 for(const bad of [{blocks:-1},{blocks:1.5},{blocks:Infinity},{keybind:'W'},{keybind:'O'},{keybind:'P'},{action:'unknown'}]) assert.throws(()=>validateRule({gift:'Rose',coins:1,action:'add',blocks:100,keybind:'K',...bad}));
});

test('climb and chalkboard rules keep a signed amount per gift and can be removed',()=>{
 assert.deepEqual(validateGameRule({game:'climb',gift:'Rose',coins:1,direction:'down',amount:5}),{game:'climb',gift:'Rose',coins:1,amount:-5});
 assert.deepEqual(validateGameRule({game:'chalk',gift:'Galaxy',coins:1000,direction:'up',amount:5000}),{game:'chalk',gift:'Galaxy',coins:1000,amount:5000});
 assert.deepEqual(validateGameRule({game:'climb',gift:'Rose',remove:true}),{game:'climb',gift:'Rose',remove:true});
 for(const bad of [{game:'rough'},{gift:''},{amount:-1},{amount:1.5},{amount:1001},{direction:'sideways'},{coins:0}]) assert.throws(()=>validateGameRule({game:'climb',gift:'Rose',coins:1,direction:'up',amount:3,...bad}));
 assert.equal(validateGameRule({game:'chalk',gift:'Rose',coins:1,direction:'up',amount:100000}).amount,100000);
});
test('the default down gifts match the game\'s Config and the coins sum matches the game',()=>{
 const config=fs.readFileSync(new URL('../src/shared/Config.luau', import.meta.url),'utf8');
 for(const table of ['ClimbGiftRules','ChalkGiftRules']){
  const block=config.slice(config.indexOf(`${table} = {`)).split('}')[0];
  const game=Object.fromEntries([...block.matchAll(/\["([^"]+)"\] = (-?\d+)/g)].map(m=>[m[1],Number(m[2])]));
  const bridge=Object.fromEntries(Object.entries(defaultGameRules()).map(([key,rule])=>[key,rule.amount]));
  assert.deepEqual(bridge,game);
 }
 assert.deepEqual([1,10,100,1000,10000].map(coinsMove),[2,6,20,63,200]);
});

test('connecting never asks for the paid gift list',()=>{
 assert.equal(CONNECT_OPTIONS.enableExtendedGiftInfo,false);
 const source=fs.readFileSync(new URL('./bridge.mjs',import.meta.url),'utf8');
 assert.match(source,/new TikTokLiveConnection\(username, CONNECT_OPTIONS\)/);
 assert.doesNotMatch(source,/enableExtendedGiftInfo:\s*true/);
});
test('gifts seen on the LIVE join the catalogue and fix its prices',()=>{
 const start=normalizeGifts(STARTER);
 const added=learnGift(start,'Hat and Mustache',99);
 assert.equal(added.length,start.length+1);
 assert.equal(added.find(g=>g.name==='Hat and Mustache').coins,99);
 assert.equal(learnGift(added,'hat and mustache',99),null);
 assert.equal(learnGift(added,'Rose',1),null);
 assert.equal(learnGift(added,'Galaxy',1200).find(g=>g.name==='Galaxy').coins,1200);
 assert.equal(learnGift(added,'Gift 123',5),null);
 assert.equal(learnGift(added,'',5),null);
});
test('a saved list keeps the starter gifts and a failed refresh explains itself',()=>{
 const merged=mergeGifts(STARTER,[{id:'5655',name:'Rose',coins:1},{id:'99',name:'Paper Crane',coins:99}]);
 assert.equal(merged.filter(g=>g.name==='Rose').length,1);
 assert.ok(merged.some(g=>g.name==='Paper Crane') && merged.some(g=>g.name==='Money Gun'));
 const premium=Object.assign(new Error('You do not have permission from the signature provider to sign this URL.'),{name:'PremiumFeatureError'});
 assert.match(catalogueError(premium),/paid sign-server plan/);
 assert.match(catalogueError(new Error('timeout')),/timeout/);
});

test('the full gift list is asked of TikTok directly, without paid signing',async()=>{
 const asked=[];
 class Client {
  constructor(username, options) { this.webClient = { clientParams: { aid: '1988' }, getJsonObjectFromWebcastApi: async (path, params, sign) => { asked.push({ path, params, sign }); return { data: { gifts: [{ id: 1, name: 'Rose', diamond_count: 1 }, { id: 2, name: 'Paper Crane', diamond_count: 99 }] } }; } }; }
  async fetchRoomId() { return '7123'; }
  async fetchAvailableGifts() { throw new Error('the paid route must not be used'); }
 }
 const gifts=await fetchCatalogue(Client,'Niamh');
 assert.deepEqual(gifts.map(g=>g.name),['Rose','Paper Crane']);
 assert.deepEqual(asked,[{ path: 'gift/list/', params: { aid: '1988', room_id: '7123' }, sign: false }]);
});
test('the signed route is only a fallback, and a paid-plan refusal is reported as such',async()=>{
 class Empty {
  constructor() { this.webClient = { getJsonObjectFromWebcastApi: async () => ({ data: { gifts: [] } }) }; }
  async fetchRoomId() { return '1'; }
  async fetchAvailableGifts() { return [{ id: 9, name: 'Galaxy', diamond_count: 1000 }]; }
 }
 assert.equal((await fetchCatalogue(Empty,'a'))[0].name,'Galaxy');
 class Blocked {
  constructor() { this.webClient = { getJsonObjectFromWebcastApi: async () => { throw new Error('socket hang up'); } }; }
  async fetchRoomId() { return '1'; }
  async fetchAvailableGifts() { throw Object.assign(new Error('You do not have permission from the signature provider to sign this URL.'), { name: 'PremiumFeatureError' }); }
 }
 await assert.rejects(fetchCatalogue(Blocked,'a'), /permission/);
});
