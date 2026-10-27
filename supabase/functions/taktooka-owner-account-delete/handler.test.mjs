import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHandler} from './handler.ts';
const id='11111111-1111-4111-8111-111111111111';
const body={kind:'user',id,fingerprint:'a'.repeat(64),confirm:'DELETE_ACCOUNT'};
function fixture(options={}){
 const calls=[];const job={id,user_id:id,status:options.status||'pending',self:false,files:options.files||[]};
 const service={auth:{getUser:async token=>({data:{user:options.badAuth?null:{id:'owner'}},error:options.badAuth?{}:null}),admin:{getUserById:async()=>({data:{user:{email:options.email||'test@accounts.taktooka.invalid'}}}),deleteUser:async(uid,soft)=>{calls.push(['auth',uid,soft]);return {error:options.authFail?{}:null};}}},rpc:async(name,args)=>{calls.push(args.p_action);return {data:job,error:options.denied?{message:'OWNER_REQUIRED'}:null};},storage:{from:bucket=>({remove:async names=>{calls.push(['storage',bucket,names]);return {error:options.storageFail?{}:null};}})},from:table=>({select:()=>({eq:()=>({limit:async()=>({data:options.shared?[{user_id:id}]:[],error:null})})})})};
 return {calls,handler:createHandler(service)};
}
const request=(data=body,auth=true)=>new Request('https://example.test',{method:'POST',headers:{'content-type':'application/json',...(auth?{authorization:'Bearer token'}:{})},body:JSON.stringify(data)});
test('missing bearer rejected',async()=>{const f=fixture();assert.equal((await f.handler(request(body,false))).status,401);assert.equal(f.calls.length,0);});
test('invalid bearer rejected',async()=>{const f=fixture({badAuth:true});assert.equal((await f.handler(request())).status,401);});
test('explicit confirmation required',async()=>{const f=fixture();assert.equal((await f.handler(request({...body,confirm:''}))).status,400);assert.equal(f.calls.length,0);});
test('nonowner cannot delete',async()=>{const f=fixture({denied:true});assert.equal((await f.handler(request())).status,403);assert.deepEqual(f.calls,['prepare']);});
test('correct pipeline and soft Auth deletion',async()=>{const f=fixture();assert.equal((await f.handler(request())).status,200);assert.deepEqual(f.calls,['prepare','purge',['auth',id,true],'finish']);});
test('staff internal identity deleted',async()=>{const f=fixture({email:'staff.964@test.taktooka.internal'});await f.handler(request());assert.ok(!f.calls.some(c=>Array.isArray(c)&&c[0]==='auth'));const g=fixture({email:'staff.964@taktooka.internal'});await g.handler(request());assert.ok(g.calls.some(c=>Array.isArray(c)&&c[0]==='auth'));});
test('shared application identity retained',async()=>{const f=fixture({shared:true});await f.handler(request());assert.deepEqual(f.calls,['prepare','purge','finish']);});
test('unmanaged identity retained',async()=>{const f=fixture({email:'owner@example.com'});await f.handler(request());assert.deepEqual(f.calls,['prepare','purge','finish']);});
test('files removed before purge',async()=>{const f=fixture({files:[{bucket:'captain-documents',name:id+'/front.jpg'}]});await f.handler(request());assert.deepEqual(f.calls[1],['storage','captain-documents',[id+'/front.jpg']]);assert.equal(f.calls[2],'purge');});
test('other account files rejected',async()=>{const f=fixture({files:[{bucket:'captain-documents',name:'other/front.jpg'}]});assert.equal((await f.handler(request())).status,409);assert.deepEqual(f.calls,['prepare']);});
test('storage failure leaves retryable job',async()=>{const f=fixture({storageFail:true,files:[{bucket:'profile-photos',name:id+'/avatar.jpg'}]});assert.equal((await f.handler(request())).status,409);assert.ok(!f.calls.includes('purge'));});
test('auth failure does not finish job',async()=>{const f=fixture({authFail:true});assert.equal((await f.handler(request())).status,409);assert.ok(!f.calls.includes('finish'));});
test('completed retry is idempotent',async()=>{const f=fixture({status:'completed'});assert.equal((await f.handler(request())).status,200);assert.deepEqual(f.calls,['prepare']);});
