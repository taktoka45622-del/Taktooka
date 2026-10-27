import fs from 'node:fs';import assert from 'node:assert/strict';import {PGlite} from '@electric-sql/pglite';
const db=new PGlite();await db.exec(fs.readFileSync('verification/staff-test-schema.sql','utf8'));
await db.exec(fs.readFileSync('supabase/taktooka/inventory_staff.sql','utf8'));
const owner='00000000-0000-4000-8000-000000000001',staff='00000000-0000-4000-8000-000000000002',customer='00000000-0000-4000-8000-000000000003',v1='00000000-0000-4000-8000-000000000004',v2='00000000-0000-4000-8000-000000000005',v3='00000000-0000-4000-8000-000000000006',pending='00000000-0000-4000-8000-000000000007',incomplete='00000000-0000-4000-8000-000000000008';
for(const [i,id]of [owner,staff,customer,v1,v2,v3,pending,incomplete].entries()){await db.query('insert into auth.users(id,email) values($1,$2)',[id,'test'+i+'@example.test']);await db.query('insert into public.tkt_profiles(user_id,name,phone)values($1,$2,$3)',[id,'Person '+i,'+964770000000'+i]);}
await db.query('insert into public.tkt_admins(user_id)values($1)',[owner]);
await db.query("insert into tkt_private.staff_accounts(user_id,name,phone,email,permissions,created_by)values($1,'Employee','+9647700000001','staff@example.test',$2,$3)",[staff,JSON.stringify({inventory:{view:true,edit:false},users:{view:true,edit:false}}),owner]);
await db.query("update public.tkt_profiles set captain=true,expires_at=case when user_id=$1 then now()+interval '1 day' when user_id=$2 then now()-interval '1 day' else null end where user_id in($1,$2,$3)",[v1,v2,v3]);
await db.query("insert into public.tkt_captain_applications(user_id,status)values($1,'pending'),($2,'changes_required')",[pending,incomplete]);
await db.query('insert into tkt_private.wallets(user_id,balance)values($1,5000),($2,10000),($3,3000)',[customer,v1,v2]);
for(const [i,status]of ['completed','cancelled','pending','in_progress','completed'].entries())await db.query('insert into public.tkt_rides(id,rider_id,captain_id,status,created_at)values($1,$2,$3,$4,now())',['10000000-0000-4000-8000-'+String(i).padStart(12,'0'),customer,v1,status]);
const as=async id=>db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);
const rpc=async(name,action,data={})=>(await db.query(`select public.${name}($1,$2) as result`,[action,JSON.stringify(data)])).rows[0].result;
await as(owner);const summary=await rpc('tkt_inventory','summary');assert.equal(summary.rides_completed,2);assert.equal(summary.rides_cancelled,1);assert.equal(summary.rides_running,2);assert.equal(summary.vehicles_registered,3);assert.equal(summary.vehicles_active,1);assert.equal(summary.vehicles_expired,1);assert.equal(summary.vehicles_never,1);assert.equal(summary.vehicles_pending,1);assert.equal(summary.vehicles_incomplete,1);assert.equal(summary.vehicle_funds,13000);assert.equal(summary.customer_funds,5000);assert.equal(summary.customers,3);
for(const category of Object.keys(summary).filter(k=>k!=='server_now')){const result=await rpc('tkt_inventory','rows',{category,limit:1});assert(result.rows.length<=1);assert.equal(result.has_more,result.total>1);if(!category.endsWith('_funds'))assert.equal(result.total,summary[category]);}
const first=await rpc('tkt_inventory','rows',{category:'rides_completed',limit:1});const second=await rpc('tkt_inventory','rows',{category:'rides_completed',limit:1,offset:1});assert.notEqual(first.rows[0].id,second.rows[0].id);
assert.equal((await rpc('tkt_inventory','rows',{category:'customers',search:'Person 2'})).total,1);
assert.equal((await rpc('tkt_inventory','profile',{user_id:v1})).profile.balance,10000);
await as(staff);assert.equal((await rpc('tkt_inventory','summary')).vehicle_funds,13000);assert.equal((await db.query('select public.tkt_dashboard_access() as result')).rows[0].result.owner,false);
await assert.rejects(rpc('tkt_staff','list'),/OWNER_REQUIRED/);await assert.rejects(rpc('tkt_manage','topup',{user_id:customer}),/PERMISSION_DENIED/);await assert.rejects(rpc('tkt_manage','user_edit',{user_id:customer,name:'Hacked'}),/PERMISSION_DENIED/);await assert.rejects(rpc('tkt_extra','admin_snapshot'),/PERMISSION_DENIED/);await assert.rejects(rpc('tkt_pricing','save'),/PERMISSION_DENIED/);await assert.rejects(rpc('tkt_captain_registration','review'),/PERMISSION_DENIED/);await assert.rejects(rpc('tkt_wheel','stock'),/PERMISSION_DENIED/);
await db.query("update tkt_private.staff_accounts set permissions='{\"users\":{\"view\":true,\"edit\":false}}' where user_id=$1",[staff]);assert.equal((await rpc('tkt_inventory','profile',{user_id:customer})).profile.balance,undefined);await assert.rejects(rpc('tkt_inventory','summary'),/PERMISSION_DENIED/);
await db.query('update tkt_private.staff_accounts set active=false where user_id=$1',[staff]);await assert.rejects(db.query('select public.tkt_dashboard_access()'),/ADMIN_REQUIRED/);await assert.rejects(rpc('tkt_inventory','profile',{user_id:customer}),/PERMISSION_DENIED/);
await as(customer);await assert.rejects(rpc('tkt_inventory','summary'),/PERMISSION_DENIED/);await assert.rejects(rpc('tkt_staff','list'),/OWNER_REQUIRED/);
await as(owner);await assert.rejects(rpc('tkt_staff','prepare',{name:'Bad',phone:'07700000009',permissions:{staff:{view:true,edit:true}}}),/INVALID_PERMISSIONS/);
await assert.rejects(rpc('tkt_staff','prepare',{name:'Bad',phone:'07700000009',permissions:{users:{view:false,edit:true}}}),/INVALID_PERMISSIONS/);
const prepared=await rpc('tkt_staff','prepare',{name:'New staff',phone:'07700000009',permissions:{support:{view:true,edit:true}}});assert.equal(prepared.email,'staff.9647700000009@taktooka.internal');

const newStaff='00000000-0000-4000-8000-000000000009';await db.query('insert into auth.users(id,email)values($1,$2)',[newStaff,prepared.email]);
await rpc('tkt_staff','attach',{user_id:newStaff,name:'New staff',phone:'07700000009',permissions:{support:{view:true,edit:true}},active:false});
assert.equal((await rpc('tkt_staff','list')).find(s=>s.user_id===newStaff).active,false);
await rpc('tkt_staff','update',{user_id:newStaff,name:'New staff',permissions:{support:{view:true,edit:false}},active:true});
await as(newStaff);assert.equal((await db.query('select public.tkt_dashboard_access() as result')).rows[0].result.permissions.support.edit,false);
await assert.rejects(rpc('tkt_manage','send',{user_id:customer,id:crypto.randomUUID(),body:'Not allowed'}),/PERMISSION_DENIED/);
await db.query("update tkt_private.staff_accounts set permissions='{\"users\":{\"view\":true,\"edit\":true}}' where user_id=$1",[newStaff]);
await assert.rejects(rpc('tkt_manage','block',{user_id:staff,blocked:true}),/PROTECTED_ADMIN/);
assert.equal((await db.query("select has_function_privilege('authenticated','public.tkt_staff_login_lookup(text)','EXECUTE') as allowed")).rows[0].allowed,false);
assert.equal((await db.query("select has_function_privilege('authenticated','public.tkt_staff_login_success(uuid)','EXECUTE') as allowed")).rows[0].allowed,false);
await db.close();console.log('Inventory totals, search, pagination, profile privacy, staff permissions and revoked-access checks passed');
