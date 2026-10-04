import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeGifts, validateRule, fetchCatalogue } from './catalogue.mjs';

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
 for(const bad of [{blocks:-1},{blocks:1.5},{blocks:Infinity},{keybind:'W'},{action:'unknown'}]) assert.throws(()=>validateRule({gift:'Rose',coins:1,action:'add',blocks:100,keybind:'K',...bad}));
});
