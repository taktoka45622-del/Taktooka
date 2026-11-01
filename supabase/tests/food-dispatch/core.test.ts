import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {gridRing} from 'h3-js';
const original=fs.readFileSync(new URL('../../functions/taktooka-dispatch/core.ts',import.meta.url),'utf8');
const food=fs.readFileSync(new URL('../../functions/taktooka-food-dispatch/core.ts',import.meta.url),'utf8');
assert.equal(food,original,'food uses identical taxi search engine');
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'food-dispatch-core-'));
try {
 const target=path.join(dir,'core.ts');
 fs.writeFileSync(target,food.replace('npm:h3-js@4.4.0',import.meta.resolve('h3-js')));
 const {dispatchCycle,cellAt}=await import(pathToFileURL(target).href);
 const pickup=[33.3,44.4],cell=gridRing(cellAt(...pickup),3)[0];
 const zones=[{id:'baghdad',geometry:{coordinates:[[[44,33],[45,33],[45,34],[44,34],[44,33]]]}}];
 const edges:any[]=[];let calls=0;
 const snapshot={lease_id:'fixture',settings:{zones,mapbox_token:'fixture-token',max_eta_s:600},jobs:[{id:'food',pickup,zone:'baghdad',tried:[],created_at:'2026-11-01T00:00:00Z'}],available_cells:[{zone:'baghdad',cell}],tracking:[]};
 const rpc=async(op:string,data:any)=>{
  if(op==='candidates'){assert(data.cells.includes(cell));return [{user_id:'slower',lat:33.32,lng:44.42},{user_id:'faster',lat:33.31,lng:44.41}];}
  if(op==='apply')edges.push(...data.edges);
  return {};
 };
 const fetcher=async(url:URL)=>{
  calls++;assert(url.pathname.includes('44.4,33.3'),'matrix destination is restaurant');
  return Response.json({code:'Ok',durations:[[120],[60]]});
 };
 const result=await dispatchCycle(snapshot,rpc,fetcher);
 assert.equal(result.error,null);assert.equal(calls,1);assert.equal(edges[0].captain_id,'faster');
 assert.equal(edges.length,2);console.log('PASS same taxi engine expands H3 rings and orders by road ETA');
 edges.length=0;
 await dispatchCycle(snapshot,rpc,async()=>Response.json({code:'NoRoute'}));
 assert.equal(edges.length,0);console.log('PASS no road route produces no offer');
 edges.length=0;
 await dispatchCycle({...snapshot,jobs:[{...snapshot.jobs[0],tried:['slower','faster']}]},rpc,fetcher);
 assert.equal(edges.length,0);console.log('PASS declined captains excluded for current round');
}finally{fs.rmSync(dir,{recursive:true,force:true});}
