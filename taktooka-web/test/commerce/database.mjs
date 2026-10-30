import {PGlite} from '@electric-sql/pglite';
import fs from 'node:fs';
const db=new PGlite();
await db.exec(`create role anon;create role authenticated;create schema auth;create schema storage;create schema tkt_private;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.uid',true),'')::uuid$$;
create table public.tkt_profiles(user_id uuid primary key,name text default '',phone text default '',captain boolean default false,blocked boolean default false,deleted_at timestamptz,expires_at timestamptz,online boolean default false,location_at timestamptz,lat double precision,lng double precision);
create table public.tkt_quotes(id uuid primary key,user_id uuid,pickup jsonb,destination jsonb,fare int,expires_at timestamptz,round_trip boolean default false,change_ride_id uuid,geometry jsonb);
create table public.tkt_rides(id uuid primary key default gen_random_uuid(),quote_id uuid,captain_id uuid, status text default 'pending',fare int);
create table tkt_private.admin_audit(actor_id uuid,action text,entity_id text,details jsonb);
create function tkt_private.require_dashboard(text,boolean)returns void language plpgsql as $$begin if current_setting('request.admin',true) is distinct from 'yes' then raise exception 'PERMISSION_DENIED';end if;end$$;
create function tkt_private.notification_add(uuid,text,text,text,text,jsonb) returns void language sql as $$select$$;
create function tkt_private.km(float8,float8,float8,float8)returns float8 language sql immutable as $$select sqrt(($1-$3)^2+($2-$4)^2)*111$$;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(bucket_id text,name text);
`);
await db.exec(fs.readFileSync(new URL('../../sql/restaurant_accounts.sql',import.meta.url),'utf8'));
console.log('schema and PL/pgSQL compiled');
const [owner,captain,customer,admin]=['11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','33333333-3333-4333-8333-333333333333','44444444-4444-4444-8444-444444444444'];
async function as(uid,admin=false){await db.query(`select set_config('request.uid',$1,false),set_config('request.admin',$2,false)`,[uid,admin?'yes':'no']);}
async function api(action,data={}){return (await db.query('select public.tkt_commerce($1,$2::jsonb) v',[action,JSON.stringify(data)])).rows[0].v;}
async function fails(action,data,expected){try{await api(action,data);throw Error('should have failed '+action);}catch(e){if(!e.message.includes(expected))throw e;}}
function assert(x,label){if(!x)throw Error(label);console.log('PASS',label);}
await db.query(`insert into public.tkt_profiles(user_id,name,phone,captain,expires_at,online,location_at)values($1,'owner','07700000001',false,null,false,now()),($2,'captain','07700000002',true,now()+interval '7 days',true,now()),($3,'customer','07700000003',false,null,false,now()),($4,'admin','07700000004',false,null,false,now())`,[owner,captain,customer,admin]);
await db.query('update public.tkt_profiles set lat=33.5,lng=44.4 where user_id=$1',[captain]);
await as(owner);await db.query(`insert into storage.objects values('restaurant-images',$1)`,[owner+'/image.jpg']);
const shop=await api('restaurant_save',{name:'مطعم اختبار',phone:'07700000001',address:'الحسينية شارع السوق',image_path:owner+'/image.jpg',location:[33.5,44.4]});
const item=await api('item_save',{name:'برغر',price:10000});
await as(customer);await fails('settings_save',{service_fee:1,commission_percent:0},'PERMISSION_DENIED');
await db.query(`insert into public.tkt_quotes(id,user_id,pickup,destination,fare,expires_at) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',$1,'[33.5,44.4]','[33.6,44.5]',2000,now()+interval '1 hour')`,[customer]);
const input={request_id:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',restaurant_id:shop.id,quote_id:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',items:[{id:item.id,quantity:1}],customer_address:'البيت مقابل السوق',expected_service_fee:500};
const order=await api('order_create',input);assert(order.service_fee===500,'fee snapshots at checkout');assert((await api('order_create',input)).id===order.id,'retry does not duplicate order');
await as(captain);await fails('order_update',{id:order.id,status:'delivered'},'PERMISSION_DENIED');
await as(owner);await api('order_update',{id:order.id,status:'preparing'});await api('order_update',{id:order.id,status:'searching',vehicle:'tuktuk'});
await as(captain);await api('order_update',{id:order.id,status:'accepted'});await api('order_update',{id:order.id,status:'heading'});await api('order_update',{id:order.id,status:'picked_up'});await api('order_update',{id:order.id,status:'delivered'});
let a=await api('accounts');assert(a.debts.find(d=>d.kind==='captain_company').amount===0,'weekly captain pays no food commission');assert(a.debts.find(d=>d.kind==='captain_restaurant').amount===10500,'captain returns food and service fee to restaurant');
await fails('order_update',{id:order.id,status:'delivered'},'INVALID_TRANSITION');
await as(owner);let acc=await api('accounts');assert(acc.debts.find(d=>d.kind==='restaurant_fee').amount===500,'restaurant owes app fee only after delivered');
let settle=await api('settlement_request',{kind:'captain_restaurant',captain_id:captain});assert(settle.amount===10500&&/^\d{6}$/.test(settle.code),'restaurant issues amount-bound settlement code');
await as(customer);await fails('settlement_confirm',{id:settle.id,code:settle.code},'PERMISSION_DENIED');
await as(captain);assert((await api('settlement_confirm',{id:settle.id,code:'wrong'})).ok===false,'invalid code does not clear debts');assert((await api('settlement_confirm',{id:settle.id,code:settle.code})).ok,'correct code settles both sides');assert((await api('settlement_confirm',{id:settle.id,code:settle.code})).ok,'settlement confirmation is idempotent');
await as(owner);settle=await api('settlement_request',{kind:'restaurant_fee'});await fails('settlement_confirm',{id:settle.id,confirmed_amount:500},'PERMISSION_DENIED');
await as(admin,true);await api('settings_save',{service_fee:750,commission_percent:25,captain_debt_limit:10000,restaurant_debt_limit:10000});await api('settlement_confirm',{id:settle.id,confirmed_amount:500});
assert((await db.query(`select service_fee from tkt_private.food_orders where id=$1`,[order.id])).rows[0].service_fee===500,'settings changes preserve existing order fees');
await db.query(`insert into tkt_private.captain_plans(user_id,plan)values($1,'commission')`,[captain]);
await db.query(`insert into public.tkt_rides(id,captain_id,fare)values('cccccccc-cccc-4ccc-8ccc-cccccccccccc',$1,4000)`,[captain]);await api('settings_save',{service_fee:500,commission_percent:20});await db.query(`update public.tkt_rides set status='completed' where id='cccccccc-cccc-4ccc-8ccc-cccccccccccc'`);
assert((await db.query(`select amount from tkt_private.commerce_debts where source_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc'`)).rows[0].amount===1000,'taxi commission uses rate at booking');

await as(customer);assert((await api('track',{id:order.id})).order.id===order.id,'customer can access own tracking map');
await as(admin,true);await fails('track',{id:order.id},'PERMISSION_DENIED');
await db.query(`insert into tkt_private.commerce_debts(source_id,kind,debtor_id,amount)values(gen_random_uuid(),'captain_company',$1,9000)`,[captain]);
await as(captain);assert((await api('me')).company_debt===10000,'company debt sums all unpaid completed trips');assert((await api('me')).debt_blocked===true,'captain blocked at exact 10000 boundary');
assert((await db.query('select tkt_private.captain_eligible($1,true) ok',[captain])).rows[0].ok===false,'dispatch excludes blocked captain');
await as(owner);await db.query(`insert into tkt_private.commerce_debts(source_id,kind,debtor_id,restaurant_id,amount)values(gen_random_uuid(),'restaurant_fee',$1,$2,10000)`,[owner,shop.id]);assert((await api('me')).debt_blocked===true,'restaurant blocked at exact 10000 boundary');assert((await api('restaurants')).length===0,'blocked restaurant hidden from new orders');
const companySettlement=await api('settlement_request',{kind:'restaurant_fee'});
await db.query(`insert into tkt_private.commerce_debts(source_id,kind,debtor_id,restaurant_id,amount)values(gen_random_uuid(),'restaurant_fee',$1,$2,500)`,[owner,shop.id]);
await as(admin,true);await api('settlement_confirm',{id:companySettlement.id,confirmed_amount:10000});
await as(owner);assert((await api('me')).company_debt===500,'settlement preserves fees accrued after request');assert((await api('me')).debt_blocked===false,'restaurant resumes after confirmed payment');
await as(captain);const captainSettlement=await api('settlement_request',{kind:'captain_company'});await as(admin,true);await api('settlement_confirm',{id:captainSettlement.id,confirmed_amount:10000});
await as(customer);await db.query(`insert into public.tkt_quotes(id,user_id,pickup,destination,fare,expires_at) values('dddddddd-dddd-4ddd-8ddd-dddddddddddd',$1,'[33.5,44.4]','[33.6,44.5]',2000,now()+interval '1 hour')`,[customer]);
const percentOrder=await api('order_create',{...input,quote_id:'dddddddd-dddd-4ddd-8ddd-dddddddddddd',request_id:'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'});
await as(owner);await api('order_update',{id:percentOrder.id,status:'preparing'});await api('order_update',{id:percentOrder.id,status:'searching',vehicle:'tuktuk'});
await as(captain);await db.query(`insert into tkt_private.commerce_debts(source_id,kind,debtor_id,amount)values('77777777-7777-4777-8777-777777777777','captain_company',$1,10000)`,[captain]);
await fails('order_update',{id:percentOrder.id,status:'accepted'},'CAPTAIN_DEBT_LIMIT');
await db.query(`update tkt_private.commerce_debts set settled_at=now() where source_id='77777777-7777-4777-8777-777777777777'`);
await api('order_update',{id:percentOrder.id,status:'accepted'});await api('order_update',{id:percentOrder.id,status:'heading'});await api('order_update',{id:percentOrder.id,status:'picked_up'});await api('order_update',{id:percentOrder.id,status:'delivered'});
assert((await api('accounts')).debts.find(d=>d.source_id===percentOrder.id&&d.kind==='captain_company').amount===400,'commission uses delivery fee only, excludes food and service fee');
await as(customer);await db.query(`insert into public.tkt_quotes(id,user_id,pickup,destination,fare,expires_at) values('ffffffff-ffff-4fff-8fff-ffffffffffff',$1,'[33.5,44.4]','[33.6,44.5]',2000,now()+interval '1 hour')`,[customer]);
const rejected=await api('order_create',{...input,quote_id:'ffffffff-ffff-4fff-8fff-ffffffffffff',request_id:'99999999-9999-4999-8999-999999999999'});
await as(owner);await db.query(`insert into tkt_private.commerce_debts(source_id,kind,debtor_id,restaurant_id,amount)values(gen_random_uuid(),'restaurant_fee',$1,$2,10000)`,[owner,shop.id]);
await fails('order_update',{id:rejected.id,status:'preparing'},'RESTAURANT_DEBT_LIMIT');
await api('order_update',{id:rejected.id,status:'rejected',reason:'الصنف غير متوفر'});
assert((await db.query('select count(*)::int n from tkt_private.commerce_debts where source_id=$1',[rejected.id])).rows[0].n===0,'rejected orders produce no service fee or commission');

await db.exec(`create table public.tkt_captain_applications(user_id uuid primary key,full_name text default '',phone text default '',chassis text default '',color text default '',model text default '',documents jsonb default '{}',pending_slot text,status text default 'draft',revision int default 0,reason text default '',reviewed_by uuid,submitted_at timestamptz,reviewed_at timestamptz,updated_at timestamptz,province text default '',area text default '',verification jsonb default '{}');
create table public.tkt_admins(user_id uuid);
create table public.tkt_messages(user_id uuid,sender_id uuid,is_admin boolean,body text);
create table tkt_private.preferences(user_id uuid primary key,captain_requested_at timestamptz);
create function tkt_private.normalize_phone(text) returns text language sql as $$select $1$$;
create function tkt_private.is_admin() returns boolean language sql as $$select current_setting('request.admin',true)='yes'$$;
alter table public.tkt_rides add column rider_id uuid;`);
await db.exec(fs.readFileSync(new URL('../../sql/registration_work_plans.sql',import.meta.url),'utf8'));
async function registration(action,data={}){return (await db.query('select tkt_private.captain_registration($1,$2::jsonb) v',[action,JSON.stringify(data)])).rows[0].v;}
await as(customer);await registration('save',{full_name:'اسم كابتن اختبار',phone:'07700000003',province:'بغداد',area:'الحسينية',work_plan:'commission',vehicle_kind:'tuktuk'});
for(const slot of ['id_front','id_back']){const path=customer+'/'+slot+'.jpg';await db.query("insert into storage.objects values('captain-documents',$1)",[path]);await registration('save',{document:{slot,path}});}
const application=await registration('submit');assert(application.status==='pending','commission signup needs ID front and back only');
await as(admin,true);await registration('review',{user_id:customer,revision:application.revision,decision:'approved'});
assert((await db.query('select plan from tkt_private.captain_plans where user_id=$1',[customer])).rows[0].plan==='commission','approved plan saved for dispatch and commission');
const weekly='55555555-5555-4555-8555-555555555555';await db.query("insert into public.tkt_profiles(user_id,phone)values($1,'07700000005')",[weekly]);
await as(weekly);await registration('save',{full_name:'كابتن اشتراك اختبار',phone:'07700000005',province:'بغداد',area:'الحسينية',work_plan:'weekly',vehicle_kind:'bike'});
for(const slot of ['id_front','id_back']){const path=weekly+'/'+slot+'.jpg';await db.query("insert into storage.objects values('captain-documents',$1)",[path]);await registration('save',{document:{slot,path}});}
let missing=false;try{await registration('submit');}catch(e){missing=e.message.includes('DOCUMENTS_REQUIRED');}assert(missing,'weekly signup requires both housing-card photos');
for(const slot of ['residence_front','residence_back']){const path=weekly+'/'+slot+'.jpg';await db.query("insert into storage.objects values('captain-documents',$1)",[path]);await registration('save',{document:{slot,path}});}
assert((await registration('submit')).status==='pending','weekly signup accepts four required document photos');

await db.exec(`create table tkt_private.lines(id uuid primary key default gen_random_uuid(),captain_id uuid,status text);
create function tkt_private.dispatch_test_placeholder()returns void language sql as $$select$$;`);
await db.exec(fs.readFileSync(new URL('../../sql/commerce_dispatch.sql',import.meta.url),'utf8'));
let locked=false;try{await db.query("insert into tkt_private.lines(captain_id,status)values($1,'accepted')",[customer]);}catch(e){locked=e.message.includes('CAPTAIN_SUBSCRIPTION_REQUIRED');}assert(locked,'commission captains cannot accept school/work lines through API');
await db.close();


