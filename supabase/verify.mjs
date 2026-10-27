import {PGlite} from '@electric-sql/pglite';
import fs from 'node:fs';
const db=new PGlite();
await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,phone text,email text);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to anon,authenticated;create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text);alter table storage.objects enable row level security;create function storage.foldername(text) returns text[] language sql as $$select (string_to_array($1,'/'))[1:array_length(string_to_array($1,'/'),1)-1]$$;create publication supabase_realtime;`);
for (const name of ['001_x_space.sql','003_dashboard.sql','003_dashboard.sql','005_realtime_performance.sql','005_realtime_performance.sql','order_edit_requests.sql']) await db.exec(fs.readFileSync(new URL(name,import.meta.url),'utf8'));
const owner='11111111-1111-4111-8111-111111111111',other='22222222-2222-4222-8222-222222222222';
await db.query('insert into auth.users(id,email) values($1,$2),($3,$4)',[owner,'owner@example.com',other,'07700000001@gmail.com']);
await db.query('insert into x_admins(user_id) values($1)',[owner]);
await db.query('insert into x_profiles(user_id,phone,data) values($1,$2,$3)',[other,'07700000001',{name:'Test'}]);
async function actor(id,role='authenticated'){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role '+role)}
const test=(ok,msg)=>{if(!ok)throw new Error(msg);console.log('PASS '+msg)};
await actor(other);test((await db.query('select x_admin_access() a')).rows[0].a===false,'merchant denied admin access');
try{await db.query('select x_admin_notify(null,$1)',['test']);throw new Error('not denied')}catch(e){test(e.message.includes('للإدارة'),'merchant cannot broadcast')}
await actor(owner);test((await db.query('select x_admin_access() a')).rows[0].a===true,'owner admin access');
await db.query('select x_admin_notify(null,$1)',['Test notification']);test((await db.query('select * from x_notifications')).rows.length===1,'admin notification saved');
await db.query('insert into x_products(id,data,stock) values($1,$2,$3)',['new',{name:'test',baseCost:5000},5]);test((await db.query("select * from x_audit where action='insert:x_products'")).rows.length===1,'catalogue audit written');
await db.query('update x_settings set data=$1 where id=true',[{deliveryCost:5000}]);test((await db.query("select * from x_audit where action='update:x_settings'")).rows.length===1,'settings audit written');
await actor('','anon');try{await db.query('select x_admin_access()');throw new Error('not denied')}catch(e){test(e.message.includes('permission denied'),'anonymous access RPC denied')}
await db.exec('reset role');
await db.query('insert into x_tickets(id,merchant_id,created_at,latest_at) values($1,$2,$3,$3)', ['activity-test',other,'2026-01-01T00:00:00Z']);
await db.query('insert into x_messages(id,ticket_id,sender_id,text,created_at) values($1,$2,$3,$4,$5)', ['activity-new','activity-test',owner,'latest','2026-10-02T00:00:00Z']);
await db.query('insert into x_messages(id,ticket_id,sender_id,text,created_at) values($1,$2,$3,$4,$5)', ['activity-old','activity-test',owner,'older','2026-09-01T00:00:00Z']);
test(new Date((await db.query("select latest_at from x_tickets where id='activity-test'")).rows[0].latest_at).toISOString()==='2026-10-02T00:00:00.000Z','older message cannot move conversation activity backwards');
await db.exec('reset role');
const payload={customer:{name:'Customer',phone:'07700000001',province:'بغداد',address:'Test'},items:[{productId:'removed-product',name:'Historical item',quantity:1,sale:170000,unitCost:10400,color:'',size:'',note:''}],freeDelivery:false,sales:170000,profit:159600,delivery:5000};
await db.query('insert into x_orders(id,merchant_id,status,payload) values($1,$2,$3,$4)',['edit-test',other,'قيد المراجعة',payload]);
await actor(other);
const customer={...payload.customer,phone:'07700000002'};
const request=(await db.query('select x_edit_order($1,$2,$3,$4) value',['edit-test',customer,payload.items,false])).rows[0].value;
test(request.customer.phone==='07700000001'&&request.pendingEdit.after.customer.phone==='07700000002','merchant edit remains pending without changing original');
try{await db.query('select x_admin_order_edit_decision($1,$2,true)',['edit-test',request.pendingEdit.id]);throw Error('not denied')}catch(e){test(e.message.includes('للإدارة'),'merchant cannot approve own change')}
await actor(owner);
const approved=(await db.query('select x_admin_order_edit_decision($1,$2,true) value',['edit-test',request.pendingEdit.id])).rows[0].value;
test(approved.customer.phone==='07700000002'&&approved.sales===170000&&approved.items[0].sale===170000,'phone edit preserves historical price without catalogue validation');
test(approved.history[0].byName==='الدعم'&&approved.pendingEdit.status==='approved','decision history names support');
try{await db.query('select x_admin_order_edit_decision($1,$2,true)',['edit-test',request.pendingEdit.id]);throw Error('not denied')}catch(e){test(e.message.includes('تمت مراجعته'),'duplicate decision blocked')}
await actor(other);
const second=(await db.query('select x_edit_order($1,$2,$3,$4) value',['edit-test',payload.customer,payload.items,false])).rows[0].value;
await actor(owner);
const rejected=(await db.query('select x_admin_order_edit_decision($1,$2,false) value',['edit-test',second.pendingEdit.id])).rows[0].value;
test(rejected.customer.phone==='07700000002'&&rejected.pendingEdit.status==='rejected','reject retains approved order');
await db.close();
