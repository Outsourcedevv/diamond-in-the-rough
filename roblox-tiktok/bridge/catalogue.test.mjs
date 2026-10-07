import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeGifts, validateRule, fetchCatalogue, validateGameRule, defaultGameRules, coinsMove } from './catalogue.mjs';
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
