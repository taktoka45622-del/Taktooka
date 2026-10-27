-- Dashboard inventory and staff permissions. Owner accounts remain separate.
create table tkt_private.staff_accounts (
 user_id uuid primary key references auth.users(id) on delete cascade,
 name text not null check(length(name) between 1 and 80),
 phone text not null unique,
 email text not null unique,
 permissions jsonb not null default '{}'::jsonb,
 active boolean not null default true,
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 failures integer not null default 0,
 locked_until timestamptz
);
alter table tkt_private.staff_accounts enable row level security;
revoke all on tkt_private.staff_accounts from public,anon,authenticated;

create or replace function tkt_private.dashboard_permission(p_page text,p_edit boolean default false)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null
 and exists(select 1 from public.tkt_profiles where user_id=auth.uid() and not blocked)
 and (exists(select 1 from public.tkt_admins where user_id=auth.uid())
 or exists(select 1 from tkt_private.staff_accounts s where s.user_id=auth.uid() and s.active
 and s.permissions->p_page->>'view'='true' and (not p_edit or s.permissions->p_page->>'edit'='true')));
$$;
revoke all on function tkt_private.dashboard_permission(text,boolean) from public,anon;
grant execute on function tkt_private.dashboard_permission(text,boolean) to authenticated,service_role;

create or replace function tkt_private.require_dashboard(p_page text,p_edit boolean default false)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not tkt_private.dashboard_permission(p_page,p_edit) then raise exception 'PERMISSION_DENIED';end if;
end;$$;
revoke all on function tkt_private.require_dashboard(text,boolean) from public,anon;
grant execute on function tkt_private.require_dashboard(text,boolean) to authenticated,service_role;

create or replace function tkt_private.clean_staff_permissions(p_value jsonb)
returns jsonb language plpgsql immutable set search_path='' as $$
declare result jsonb:='{}';k text;v jsonb;
begin
 if jsonb_typeof(p_value) is distinct from 'object' then raise exception 'INVALID_PERMISSIONS';end if;
 for k,v in select key,value from jsonb_each(p_value) loop
  if k not in('inventory','overview','rides','applications','users','finance','support','pricing','coverage','wheel','banners','favorites','security','audit')
   or jsonb_typeof(v) is distinct from 'object' or jsonb_typeof(v->'view') is distinct from 'boolean'
   or jsonb_typeof(v->'edit') is distinct from 'boolean' then raise exception 'INVALID_PERMISSIONS';end if;
  if v->>'edit'='true' and v->>'view'<>'true' then raise exception 'INVALID_PERMISSIONS';end if;
  if v->>'view'='true' then result:=result||jsonb_build_object(k,v);end if;
 end loop;
 if result='{}' then raise exception 'SELECT_PERMISSION';end if;
 return result;
end;$$;
revoke all on function tkt_private.clean_staff_permissions(jsonb) from public,anon,authenticated;

create or replace function tkt_private.authorize_manage(p_action text,p_data jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare page text;editing boolean:=true;kind text:=p_data->>'kind';target uuid:=nullif(p_data->>'user_id','')::uuid;
begin
 case
 when p_action='overview' then page:='overview';editing:=false;
 when p_action in('users') then page:='users';editing:=false;
 when p_action in('rides','track') then page:='rides';editing:=false;
 when p_action in('finance','ledger') then page:='finance';editing:=false;
 when p_action='favorites' then page:='favorites';editing:=false;
 when p_action in('support_rooms','recovery','recovery_messages','read') then page:='support';editing:=false;
 when p_action='security' then page:='security';editing:=false;
 when p_action in('audit','archives') then page:='audit';editing:=false;
 when p_action in('user_edit','role','block','renew','subscription_edit') then page:='users';
 when p_action='application_reject' then page:='applications';
 when p_action in('topup','settle','coupon_admin','coupon_delete') then page:='finance';
 when p_action in('send','recovery_send') then page:='support';
 when p_action in('reset_target','password_reset_record','unlock_phone') then page:='security';
 when p_action in('favorite_edit','favorite_delete') then page:='favorites';
 when p_action='ride_cancel' then page:='rides';
 when p_action='pricing_save' then page:='pricing';
 when p_action='dispatch_configure' then page:='coverage';
 when p_action='archive' then page:=case kind when 'user' then 'users' when 'ride' then 'rides' when 'support' then 'support' when 'recovery' then 'support' end;
 when p_action='restore' then page:='audit';
 else raise exception 'UNKNOWN_ACTION';
 end case;
 if page is null then raise exception 'INVALID_ENTITY';end if;
 perform tkt_private.require_dashboard(page,editing);
 if editing and (exists(select 1 from tkt_private.staff_accounts where user_id=target)
 or (p_action in('archive','restore') and kind='user' and exists(select 1 from tkt_private.staff_accounts where user_id=(p_data->>'entity_id')::uuid))) then raise exception 'PROTECTED_ADMIN';end if;
end;$$;
revoke all on function tkt_private.authorize_manage(text,jsonb) from public,anon,authenticated;

create or replace function public.tkt_dashboard_access()
returns jsonb language plpgsql security definer set search_path='' as $$
declare s tkt_private.staff_accounts;owner boolean;
begin
 if auth.uid() is null or not exists(select 1 from public.tkt_profiles where user_id=auth.uid() and not blocked) then raise exception 'AUTH_REQUIRED';end if;
 owner:=tkt_private.is_admin();
 if owner then return jsonb_build_object('owner',true,'name',(select name from public.tkt_profiles where user_id=auth.uid()),'permissions','{}'::jsonb);end if;
 select * into s from tkt_private.staff_accounts where user_id=auth.uid() and active;
 if not found then raise exception 'ADMIN_REQUIRED';end if;
 return jsonb_build_object('owner',false,'name',s.name,'permissions',s.permissions);
end;$$;
revoke all on function public.tkt_dashboard_access() from public,anon;
grant execute on function public.tkt_dashboard_access() to authenticated;

create view tkt_private.inventory_people with(security_invoker=true) as
 select p.*,coalesce(w.balance,0) as balance,a.status as application_status,a.full_name,a.chassis,a.color,a.model,a.province,a.area,a.reason,a.submitted_at,
 (p.captain or coalesce(a.status='approved',false)) as vehicle,
 case when p.expires_at is null then 'never' when p.expires_at>now() then 'active' else 'expired' end as subscription_state,
 exists(select 1 from tkt_private.admin_archives ar where ar.kind='user' and ar.entity_id=p.user_id::text) as archived
 from public.tkt_profiles p left join tkt_private.wallets w on w.user_id=p.user_id left join public.tkt_captain_applications a on a.user_id=p.user_id
 where not exists(select 1 from public.tkt_admins where user_id=p.user_id) and not exists(select 1 from tkt_private.staff_accounts where user_id=p.user_id);
revoke all on tkt_private.inventory_people from public,anon,authenticated;

create or replace function tkt_private.inventory(p_action text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;total bigint;cat text:=p_data->>'category';q text:=trim(coalesce(p_data->>'search',''));lim integer:=least(100,greatest(1,coalesce((p_data->>'limit')::integer,30)));offn integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));target uuid:=nullif(p_data->>'user_id','')::uuid;person record;
begin
 if not tkt_private.dashboard_permission('inventory') and not(p_action='profile' and (tkt_private.dashboard_permission('users') or tkt_private.dashboard_permission('rides') or tkt_private.dashboard_permission('applications') or tkt_private.dashboard_permission('finance') or tkt_private.dashboard_permission('support'))) then raise exception 'PERMISSION_DENIED';end if;
 if p_action='summary' then
  select jsonb_build_object('vehicles_pending',count(*) filter(where application_status='pending'),'vehicles_registered',count(*) filter(where vehicle),'vehicles_incomplete',count(*) filter(where application_status='changes_required'),
   'vehicles_never',count(*) filter(where vehicle and subscription_state='never'),'vehicles_active',count(*) filter(where vehicle and subscription_state='active'),'vehicles_expired',count(*) filter(where vehicle and subscription_state='expired'),
   'vehicle_funds',coalesce(sum(greatest(balance,0)) filter(where vehicle),0),'customers',count(*) filter(where not vehicle),'customer_funds',coalesce(sum(greatest(balance,0)) filter(where not vehicle),0)) into result from tkt_private.inventory_people;
  return result||(select jsonb_build_object('rides_completed',count(*) filter(where status='completed'),'rides_cancelled',count(*) filter(where status='cancelled'),'rides_running',count(*) filter(where status in('pending','accepted','arrived','in_progress')),'server_now',clock_timestamp()) from public.tkt_rides);
 elsif p_action='rows' then
  if cat in('rides_completed','rides_cancelled','rides_running') then
   select count(*) into total from public.tkt_rides r left join public.tkt_profiles p on p.user_id=r.rider_id left join public.tkt_profiles c on c.user_id=r.captain_id
    where (case cat when 'rides_completed' then r.status='completed' when 'rides_cancelled' then r.status='cancelled' else r.status in('pending','accepted','arrived','in_progress') end)
    and (q='' or r.id::text ilike '%'||q||'%' or concat_ws(' ',r.pickup_name,r.destination_name,p.name,p.phone,c.name,c.phone) ilike '%'||q||'%');
   select coalesce(jsonb_agg(to_jsonb(x)),'[]') into result from(
    select r.*,p.name as rider_name,p.phone as rider_phone,c.name as captain_name,c.phone as captain_phone from public.tkt_rides r left join public.tkt_profiles p on p.user_id=r.rider_id left join public.tkt_profiles c on c.user_id=r.captain_id
    where (case cat when 'rides_completed' then r.status='completed' when 'rides_cancelled' then r.status='cancelled' else r.status in('pending','accepted','arrived','in_progress') end)
    and (q='' or r.id::text ilike '%'||q||'%' or concat_ws(' ',r.pickup_name,r.destination_name,p.name,p.phone,c.name,c.phone) ilike '%'||q||'%') order by r.created_at desc,r.id desc limit lim offset offn)x;
  elsif cat in('vehicles_pending','vehicles_registered','vehicles_incomplete','vehicles_never','vehicles_active','vehicles_expired','vehicle_funds','customers','customer_funds') then
   select count(*) into total from tkt_private.inventory_people p where
    case cat when 'vehicles_pending' then application_status='pending' when 'vehicles_registered' then vehicle when 'vehicles_incomplete' then application_status='changes_required' when 'vehicles_never' then vehicle and subscription_state='never' when 'vehicles_active' then vehicle and subscription_state='active' when 'vehicles_expired' then vehicle and subscription_state='expired' when 'vehicle_funds' then vehicle and balance>0 when 'customers' then not vehicle when 'customer_funds' then not vehicle and balance>0 end
    and (q='' or concat_ws(' ',name,phone,full_name,chassis,province,area) ilike '%'||q||'%');
   select coalesce(jsonb_agg(to_jsonb(x)),'[]') into result from(select * from tkt_private.inventory_people p where
    case cat when 'vehicles_pending' then application_status='pending' when 'vehicles_registered' then vehicle when 'vehicles_incomplete' then application_status='changes_required' when 'vehicles_never' then vehicle and subscription_state='never' when 'vehicles_active' then vehicle and subscription_state='active' when 'vehicles_expired' then vehicle and subscription_state='expired' when 'vehicle_funds' then vehicle and balance>0 when 'customers' then not vehicle when 'customer_funds' then not vehicle and balance>0 end
    and (q='' or concat_ws(' ',name,phone,full_name,chassis,province,area) ilike '%'||q||'%') order by created_at desc,user_id limit lim offset offn)x;
  else raise exception 'INVALID_CATEGORY';end if;
  return jsonb_build_object('rows',result,'total',total,'has_more',offn+jsonb_array_length(result)<total,'server_now',clock_timestamp());
 elsif p_action='profile' then
  select * into person from tkt_private.inventory_people where user_id=target;if not found then raise exception 'PROFILE_REQUIRED';end if;
  return jsonb_build_object('profile',case when tkt_private.dashboard_permission('finance') or tkt_private.dashboard_permission('inventory') then to_jsonb(person) else to_jsonb(person)-'balance' end,'rides',(select jsonb_build_object('completed',count(*) filter(where status='completed'),'cancelled',count(*) filter(where status='cancelled'),'running',count(*) filter(where status in('pending','accepted','arrived','in_progress'))) from public.tkt_rides where rider_id=target or captain_id=target),
   'payments',case when tkt_private.dashboard_permission('finance') or tkt_private.dashboard_permission('inventory') then coalesce((select jsonb_agg(to_jsonb(x)) from(select id,amount,created_at,expires_at from public.tkt_payments where captain_id=target order by created_at desc limit 30)x),'[]') else '[]'::jsonb end);
 else raise exception 'UNKNOWN_ACTION';end if;
end;$$;
revoke all on function tkt_private.inventory(text,jsonb) from public,anon;
grant execute on function tkt_private.inventory(text,jsonb) to authenticated;
create or replace function public.tkt_inventory(p_action text,p_data jsonb default '{}') returns jsonb language sql set search_path='' as $$select tkt_private.inventory(p_action,p_data)$$;
revoke all on function public.tkt_inventory(text,jsonb) from public,anon;
grant execute on function public.tkt_inventory(text,jsonb) to authenticated;

create or replace function public.tkt_staff(p_action text,p_data jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();target uuid:=nullif(p_data->>'user_id','')::uuid;ph text;nm text;v_permissions jsonb;s tkt_private.staff_accounts;
begin
 if not tkt_private.is_admin() or not exists(select 1 from public.tkt_profiles where user_id=u and not blocked) then raise exception 'OWNER_REQUIRED';end if;
 if p_action='list' then return coalesce((select jsonb_agg(to_jsonb(x)) from(select user_id,name,phone,permissions,active,created_at,updated_at from tkt_private.staff_accounts order by created_at desc)x),'[]');
 elsif p_action='prepare' then
  ph:=tkt_private.normalize_phone(p_data->>'phone');nm:=trim(p_data->>'name');v_permissions:=tkt_private.clean_staff_permissions(p_data->'permissions');
  if ph is null or coalesce(length(nm),0) not between 1 and 80 then raise exception 'INVALID_PROFILE';end if;
  if exists(select 1 from public.tkt_profiles where tkt_private.normalize_phone(phone)=ph) or exists(select 1 from tkt_private.staff_accounts where phone=ph) then raise exception 'PHONE_EXISTS';end if;
  return jsonb_build_object('email','staff.'||replace(ph,'+','')||'@taktooka.internal','phone',ph);
 elsif p_action='attach' then
  ph:=tkt_private.normalize_phone(p_data->>'phone');nm:=trim(p_data->>'name');v_permissions:=tkt_private.clean_staff_permissions(p_data->'permissions');
  if target is null or ph is null or coalesce(length(nm),0) not between 1 and 80 then raise exception 'INVALID_PROFILE';end if;
  perform pg_advisory_xact_lock(hashtextextended(ph,67209));
  if exists(select 1 from public.tkt_profiles where tkt_private.normalize_phone(phone)=ph and user_id<>target) then raise exception 'PHONE_EXISTS';end if;
  if not exists(select 1 from auth.users where id=target and email='staff.'||replace(ph,'+','')||'@taktooka.internal') then raise exception 'INVALID_STAFF_ACCOUNT';end if;
  if exists(select 1 from public.tkt_admins where user_id=target) then raise exception 'PROTECTED_ADMIN';end if;
  insert into tkt_private.staff_accounts(user_id,name,phone,email,permissions,created_by,active)values(target,nm,ph,'staff.'||replace(ph,'+','')||'@taktooka.internal',v_permissions,u,coalesce((p_data->>'active')::boolean,true));
  insert into public.tkt_profiles(user_id,name,phone)values(target,nm,ph) on conflict(user_id)do update set name=excluded.name,phone=excluded.phone,captain=false,online=false;
  insert into tkt_private.preferences(user_id)values(target)on conflict do nothing;
 elsif p_action in('update','reset_target','password_record') then
  select * into s from tkt_private.staff_accounts where user_id=target for update;if not found then raise exception 'STAFF_NOT_FOUND';end if;
  if p_action='reset_target' then return jsonb_build_object('user_id',s.user_id);end if;
  if p_action='update' then
   nm:=trim(p_data->>'name');v_permissions:=tkt_private.clean_staff_permissions(p_data->'permissions');
   if coalesce(length(nm),0) not between 1 and 80 or jsonb_typeof(p_data->'active') is distinct from 'boolean' then raise exception 'INVALID_PROFILE';end if;
   update tkt_private.staff_accounts set name=nm,permissions=v_permissions,active=(p_data->>'active')::boolean,updated_at=now() where user_id=target;
   update public.tkt_profiles set name=nm where user_id=target;
  else update tkt_private.staff_accounts set failures=0,locked_until=null,updated_at=now() where user_id=target;end if;
 else raise exception 'UNKNOWN_ACTION';end if;
 insert into tkt_private.admin_audit(actor_id,action,entity_id,details)values(u,'staff_'||p_action,target::text,p_data-'password'-'pin');
 return '{"ok":true}';
end;$$;
revoke all on function public.tkt_staff(text,jsonb) from public,anon;
grant execute on function public.tkt_staff(text,jsonb) to authenticated;

-- Login helpers are available only to the server, never to public clients.
create or replace function public.tkt_staff_login_lookup(p_phone text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s tkt_private.staff_accounts;
begin
 select * into s from tkt_private.staff_accounts where phone=tkt_private.normalize_phone(p_phone) for update;
 if not found then return '{"staff":false}';end if;
 if not s.active or exists(select 1 from public.tkt_profiles where user_id=s.user_id and blocked) then return '{"staff":true,"allowed":false}';end if;
 if s.locked_until>clock_timestamp() then return '{"staff":true,"allowed":false,"locked":true}';end if;
 if s.locked_until is not null then update tkt_private.staff_accounts set failures=0,locked_until=null where user_id=s.user_id;s.failures:=0;end if;
 update tkt_private.staff_accounts set failures=failures+1,locked_until=case when failures+1>=5 then clock_timestamp()+interval '15 minutes' end where user_id=s.user_id;
 return jsonb_build_object('staff',true,'allowed',true,'email',s.email,'user_id',s.user_id);
end;$$;
create or replace function public.tkt_staff_login_success(p_user uuid)
returns void language sql security definer set search_path='' as $$update tkt_private.staff_accounts set failures=0,locked_until=null where user_id=p_user$$;
revoke all on function public.tkt_staff_login_lookup(text),public.tkt_staff_login_success(uuid) from public,anon,authenticated;
grant execute on function public.tkt_staff_login_lookup(text),public.tkt_staff_login_success(uuid) to service_role;

-- Apply permission checks inside existing operations; ordinary app behavior is retained.
CREATE OR REPLACE FUNCTION tkt_private.manage(p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u uuid:=auth.uid(); target uuid; ident uuid; result jsonb; rec public.tkt_profiles; ride public.tkt_rides; ph text; v_kind text; entity text; n integer; lim integer:=least(500,greatest(1,coalesce((p_data->>'limit')::integer,200))); offn integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 perform tkt_private.authorize_manage(p_action,p_data);
 if not exists(select 1 from public.tkt_profiles where user_id=u and not blocked) then raise exception 'ACCOUNT_BLOCKED';end if;
 target:=nullif(p_data->>'user_id','')::uuid;
 ident:=nullif(p_data->>'id','')::uuid;
 if p_action='overview' then
  return jsonb_build_object('server_now',clock_timestamp(),'users',(select count(*) from public.tkt_profiles),'captains',(select count(*) from public.tkt_profiles where captain),'online',(select count(*) from public.tkt_profiles where captain and online and not blocked and location_at>clock_timestamp()-interval '90 seconds'),'active_rides',(select count(*) from public.tkt_rides where status in('pending','accepted','arrived','in_progress')),'today_rides',(select count(*) from public.tkt_rides where (created_at at time zone 'Asia/Baghdad')::date=(now() at time zone 'Asia/Baghdad')::date),'today_completed',(select coalesce(sum(fare),0) from public.tkt_rides where status='completed' and (updated_at at time zone 'Asia/Baghdad')::date=(now() at time zone 'Asia/Baghdad')::date),'applications',(select count(*) from tkt_private.preferences where captain_requested_at is not null),'worker',(select jsonb_build_object('heartbeat',last_worker_at,'last_error',last_error) from tkt_private.dispatch_settings where id));
 elsif p_action='users' then
  return coalesce((select jsonb_agg(to_jsonb(x)) from(select p.*,exists(select 1 from public.tkt_admins where user_id=p.user_id) as admin from public.tkt_profiles p where not exists(select 1 from tkt_private.staff_accounts where user_id=p.user_id) and not exists(select 1 from tkt_private.admin_archives where kind='user' and entity_id=p.user_id::text) and (coalesce(p_data->>'search','')='' or p.name ilike '%'||(p_data->>'search')||'%' or p.phone ilike '%'||(p_data->>'search')||'%') order by p.created_at desc limit lim offset offn)x),'[]');
 elsif p_action='rides' then
  return coalesce((select jsonb_agg(to_jsonb(x)) from(select r.*,p.name as rider_name,p.phone as rider_phone,c.name as captain_name,c.phone as captain_phone from public.tkt_rides r left join public.tkt_profiles p on p.user_id=r.rider_id left join public.tkt_profiles c on c.user_id=r.captain_id where not exists(select 1 from tkt_private.admin_archives where kind='ride' and entity_id=r.id::text) and (coalesce(p_data->>'status','')='' or r.status=p_data->>'status') and (coalesce(p_data->>'search','')='' or r.id::text ilike '%'||(p_data->>'search')||'%' or r.pickup_name ilike '%'||(p_data->>'search')||'%' or r.destination_name ilike '%'||(p_data->>'search')||'%' or p.phone ilike '%'||(p_data->>'search')||'%' or c.phone ilike '%'||(p_data->>'search')||'%') order by r.created_at desc limit lim offset offn)x),'[]');
 elsif p_action='track' then
  select * into ride from public.tkt_rides where id=ident;
  if not found then raise exception 'RIDE_UNAVAILABLE';end if;
  return jsonb_build_object('ride',to_jsonb(ride),'captain',(select jsonb_build_object('user_id',user_id,'name',name,'phone',phone,'lat',lat,'lng',lng,'location_at',location_at,'online',online)from public.tkt_profiles where user_id=ride.captain_id),'offers',coalesce((select jsonb_agg(to_jsonb(x))from(select o.id,o.captain_id,o.status,o.created_at,o.expires_at,o.eta_s,p.name as captain_name,p.phone as captain_phone from public.tkt_offers o left join public.tkt_profiles p on p.user_id=o.captain_id where o.ride_id=ride.id order by o.created_at desc limit 50)x),'[]'),'server_now',clock_timestamp());
 elsif p_action='finance' then return tkt_private.extra('admin_snapshot','{}');
 elsif p_action='ledger' then
  return jsonb_build_object('balance',(select coalesce(balance,0)from tkt_private.wallets where user_id=target),'entries',coalesce((select jsonb_agg(to_jsonb(x))from(select * from tkt_private.ledger where user_id=target order by created_at desc limit lim offset offn)x),'[]'),'payments',coalesce((select jsonb_agg(to_jsonb(x))from(select * from public.tkt_payments where captain_id=target order by created_at desc limit lim offset offn)x),'[]'));
 elsif p_action='favorites' then
  return coalesce((select jsonb_agg(to_jsonb(x))from(select s.*,p.name,p.phone from public.tkt_saved_places s join public.tkt_profiles p on p.user_id=s.user_id where (target is null or s.user_id=target) order by s.created_at desc limit lim offset offn)x),'[]');
 elsif p_action='recovery' then
  return coalesce((select jsonb_agg(to_jsonb(x))from(select t.id,t.phone,t.name,t.created_at,(select max(created_at)from public.tkt_recovery_messages where thread_id=t.id) as last_at,(select count(*)from public.tkt_recovery_messages where thread_id=t.id and not is_admin) as customer_messages from public.tkt_recovery_threads t where not exists(select 1 from tkt_private.admin_archives where kind='recovery' and entity_id=t.id::text) order by t.created_at desc limit lim offset offn)x),'[]');
 elsif p_action='recovery_messages' then
  return coalesce((select jsonb_agg(to_jsonb(x)order by x.created_at)from(select id,body,is_admin,created_at from public.tkt_recovery_messages where thread_id=ident order by created_at desc limit 200)x),'[]');
 elsif p_action='security' then
  return coalesce((select jsonb_agg(to_jsonb(x))from(select phone,failures,window_at,requests from tkt_private.phone_attempts where (requests>0 or failures>0) order by window_at desc limit lim offset offn)x),'[]');
 elsif p_action='audit' then
  return coalesce((select jsonb_agg(to_jsonb(x))from(select a.*,p.name as actor_name from tkt_private.admin_audit a left join public.tkt_profiles p on p.user_id=a.actor_id order by a.created_at desc limit lim offset offn)x),'[]');
 elsif p_action='reset_target' then
  if target is null then
   ph:=tkt_private.normalize_phone(p_data->>'phone');
   select count(*) into n from public.tkt_profiles where tkt_private.normalize_phone(phone)=ph;
   if n<>1 then raise exception 'CONTACT_SUPPORT';end if;
   select user_id into target from public.tkt_profiles where tkt_private.normalize_phone(phone)=ph;
  end if;
  if exists(select 1 from public.tkt_admins where user_id=target)then raise exception 'PROTECTED_ADMIN';end if;
  select * into rec from public.tkt_profiles where user_id=target and not blocked;
  if not found then raise exception 'PROFILE_REQUIRED';end if;
  return jsonb_build_object('user_id',target,'phone',rec.phone);
 elsif p_action='password_reset_record' then
  if exists(select 1 from public.tkt_admins where user_id=target)then raise exception 'PROTECTED_ADMIN';end if;
  ph:=tkt_private.normalize_phone(p_data->>'phone');
  update tkt_private.phone_attempts set failures=0,requests=0,window_at=clock_timestamp()where phone=ph;
 elsif p_action='support_rooms' then
  result:=tkt_private.extra('admin_snapshot','{}');
  return coalesce((select jsonb_agg(value)from jsonb_array_elements(result->'rooms')where not exists(select 1 from tkt_private.admin_archives where kind='support' and entity_id=value->>'user_id')),'[]');
 elsif p_action='archives' then
  return coalesce((select jsonb_agg(to_jsonb(x))from(select * from tkt_private.admin_archives order by created_at desc limit lim offset offn)x),'[]');
 elsif p_action='user_edit' then
  select * into rec from public.tkt_profiles where user_id=target for update;
  if not found then raise exception 'PROFILE_REQUIRED';end if;
  if exists(select 1 from public.tkt_admins where user_id=target)then raise exception 'PROTECTED_ADMIN';end if;
  ph:=tkt_private.normalize_phone(p_data->>'phone');
  if ph is null or coalesce(length(trim(p_data->>'name')),0)not between 1 and 80 then raise exception 'INVALID_PROFILE';end if;
  if exists(select 1 from public.tkt_profiles where user_id<>target and tkt_private.normalize_phone(phone)=ph) or exists(select 1 from auth.users where id<>target and tkt_private.normalize_phone(phone)=ph)then raise exception 'PHONE_EXISTS';end if;
  if ph is distinct from tkt_private.normalize_phone(rec.phone) and exists(select 1 from auth.users where id=target and phone is not null and phone<>'')then raise exception 'NATIVE_PHONE_REQUIRES_SUPPORT';end if;
  update public.tkt_profiles set name=trim(p_data->>'name'),phone=ph where user_id=target;
 elsif p_action in('role','renew','block') then
  if exists(select 1 from public.tkt_admins where user_id=target)then raise exception 'PROTECTED_ADMIN';end if;
  result:=tkt_private.action(p_action,p_data);
  if p_action='role' then update tkt_private.preferences set captain_requested_at=null where user_id=target;end if;
 elsif p_action='application_reject' then update tkt_private.preferences set captain_requested_at=null where user_id=target;
 elsif p_action='subscription_edit' then
  select * into rec from public.tkt_profiles where user_id=target for update;
  if not found or not rec.captain then raise exception 'CAPTAIN_REQUIRED';end if;
  if (p_data->>'expires_at')::timestamptz is null or (p_data->>'expires_at')::timestamptz>now()+interval '2 years' then raise exception 'INVALID_EXPIRY';end if;
  if exists(select 1 from public.tkt_rides where captain_id=target and status in('accepted','arrived','in_progress'))then raise exception 'ACTIVE_RIDE';end if;
  update public.tkt_profiles set expires_at=(p_data->>'expires_at')::timestamptz,online=false where user_id=target;
 elsif p_action='read' then return tkt_private.extra('read',p_data);
 elsif p_action in('topup','settle','coupon_admin','send')then
  result:=tkt_private.extra(p_action,p_data);
 elsif p_action='coupon_delete' then
  entity:=upper(trim(p_data->>'code'));
  perform 1 from tkt_private.coupons where code=entity for update;
  if not found then raise exception 'COUPON_EXPIRED';end if;
  if exists(select 1 from tkt_private.coupon_uses where code=entity) or exists(select 1 from public.tkt_rides where coupon_code=entity)then update tkt_private.coupons set active=false where code=entity;
  else update tkt_private.preferences set coupon=null where coupon=entity;delete from tkt_private.coupons where code=entity;end if;
 elsif p_action='favorite_edit' then
  if coalesce(length(trim(p_data->>'label')),0)not between 1 and 120 or (p_data->>'lat')is null or (p_data->>'lng')is null then raise exception 'INVALID_ADDRESS';end if;
  update public.tkt_saved_places set label=trim(p_data->>'label'),lat=(p_data->>'lat')::float8,lng=(p_data->>'lng')::float8 where id=ident;
  if not found then raise exception 'ADDRESS_NOT_FOUND';end if;
 elsif p_action='favorite_delete' then delete from public.tkt_saved_places where id=ident;
 elsif p_action='ride_cancel' then
  result:=tkt_private.action('ride_status',jsonb_build_object('ride_id',ident,'status','cancelled'));
 elsif p_action='recovery_send' then
  if coalesce(length(trim(p_data->>'body')),0)not between 1 and 2000 then raise exception 'INVALID_MESSAGE';end if;
  insert into public.tkt_recovery_messages(id,thread_id,body,is_admin)values((p_data->>'message_id')::uuid,ident,trim(p_data->>'body'),true)on conflict(id)do nothing;
 elsif p_action='unlock_phone' then
  ph:=tkt_private.normalize_phone(p_data->>'phone');if ph is null then raise exception 'INVALID_PHONE';end if;
  update tkt_private.phone_attempts set failures=0,requests=0,window_at=clock_timestamp()where phone=ph;
 elsif p_action in('archive','restore') then
  v_kind:=p_data->>'kind';entity:=p_data->>'entity_id';
  if v_kind not in('ride','user','support','recovery') or coalesce(entity,'')='' then raise exception 'INVALID_ENTITY';end if;
  if p_action='archive' then
   if v_kind='ride' and exists(select 1 from public.tkt_rides where id=entity::uuid and status not in('completed','cancelled'))then raise exception 'ACTIVE_RIDE';end if;
   if v_kind='user' then
    if exists(select 1 from public.tkt_admins where user_id=entity::uuid)then raise exception 'PROTECTED_ADMIN';end if;
    if exists(select 1 from public.tkt_rides where (rider_id=entity::uuid or captain_id=entity::uuid)and status in('pending','accepted','arrived','in_progress'))then raise exception 'ACTIVE_RIDE';end if;
    update public.tkt_profiles set blocked=true,online=false where user_id=entity::uuid;
   end if;
   insert into tkt_private.admin_archives(kind,entity_id,actor_id)values(v_kind,entity,u)on conflict do nothing;
  else delete from tkt_private.admin_archives where kind=v_kind and entity_id=entity;end if;
 elsif p_action='pricing_save' then result:=tkt_private.pricing_admin('save',p_data);
 elsif p_action='dispatch_configure' then result:=tkt_private.dispatch('configure',p_data);
 else raise exception 'UNKNOWN_ACTION';end if;
 -- Message bodies and credentials are intentionally absent from operational audit entries.
 insert into tkt_private.admin_audit(actor_id,action,entity_id,details)values(u,p_action,coalesce(entity,target::text,ident::text,p_data->>'code',ph),p_data-'body'-'password'-'pin'-'token');
 return coalesce(result,'{"ok":true}'::jsonb);
end $function$;


CREATE OR REPLACE FUNCTION tkt_private.admin_live()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform tkt_private.require_dashboard('overview');
 return jsonb_build_object('server_now',clock_timestamp(),'pending_applications',(select count(*) from public.tkt_captain_applications where status='pending'),'captains',coalesce((select jsonb_agg(to_jsonb(x)) from (
 select p.user_id,p.name,p.phone,p.lat,p.lng,p.location_at,p.online,tkt_private.service_zone(p.lat,p.lng) is not null as in_service,r.id as ride_id,r.status as ride_status
 from public.tkt_profiles p left join lateral(select id,status from public.tkt_rides where captain_id=p.user_id and status in ('accepted','arrived','in_progress') order by created_at desc limit 1)r on true
 where p.captain and p.online and not p.blocked order by p.location_at desc nulls last,p.user_id limit 1000)x),'[]'::jsonb));
end;$function$;


CREATE OR REPLACE FUNCTION tkt_private.captain_registration(p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u uuid:=auth.uid();a public.tkt_captain_applications;target uuid;slot text;path text;ph text;decision text;why text;lim integer:=least(200,greatest(1,coalesce((p_data->>'limit')::integer,100)));offn integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 if not exists(select 1 from public.tkt_profiles where user_id=u and not blocked)then raise exception 'ACCOUNT_BLOCKED';end if;
 if p_action='get' then return (select to_jsonb(x)from public.tkt_captain_applications x where user_id=u);end if;
 if p_action in('list','review')then
  perform tkt_private.require_dashboard('applications',p_action='review');
  if p_action='list'then return coalesce((select jsonb_agg(to_jsonb(x))from(select app.* from public.tkt_captain_applications app where app.status<>'draft' and (coalesce(p_data->>'status','')='' or app.status=p_data->>'status') and (coalesce(p_data->>'search','')='' or app.full_name ilike '%'||(p_data->>'search')||'%' or app.phone ilike '%'||(p_data->>'search')||'%' or app.chassis ilike '%'||(p_data->>'search')||'%') order by app.submitted_at desc limit lim offset offn)x),'[]'::jsonb);end if;
  target:=(p_data->>'user_id')::uuid;
  perform pg_advisory_xact_lock(74658291);
  select * into a from public.tkt_captain_applications where user_id=target for update;
  if not found or a.status<>'pending' or a.revision is distinct from (p_data->>'revision')::integer then raise exception 'APPLICATION_CHANGED';end if;
  if exists(select 1 from public.tkt_admins where user_id=target) or exists(select 1 from tkt_private.staff_accounts where user_id=target)then raise exception 'PROTECTED_ADMIN';end if;
  decision:=p_data->>'decision';why:=btrim(coalesce(p_data->>'reason',''));
  if decision not in('approved','changes_required') or decision is null then raise exception 'INVALID_DECISION';end if;
  if decision='changes_required' and length(why) not between 3 and 2000 then raise exception 'REASON_REQUIRED';end if;
  if decision='approved'then
   if not exists(select 1 from public.tkt_profiles where user_id=target and not blocked)then raise exception 'ACCOUNT_BLOCKED';end if;
   if exists(select 1 from public.tkt_rides where (rider_id=target or captain_id=target)and status in('pending','accepted','arrived','in_progress'))then raise exception 'ACTIVE_RIDE';end if;
   perform set_config('taktooka.reviewing_captain',target::text,true);
   update public.tkt_profiles set captain=true,online=false,name=a.full_name where user_id=target;
  end if;
  update public.tkt_captain_applications set status=decision,reason=case when decision='approved'then '' else why end,reviewed_by=u,reviewed_at=clock_timestamp(),updated_at=clock_timestamp()where user_id=target returning * into a;
  update tkt_private.preferences set captain_requested_at=null where user_id=target;
  insert into tkt_private.admin_audit(actor_id,action,entity_id,details)values(u,'captain_'||decision,target::text,jsonb_build_object('revision',a.revision,'status',decision));
  insert into public.tkt_messages(user_id,sender_id,is_admin,body)values(target,u,true,case when decision='approved'then 'تمت الموافقة على تسجيلك ككابتن؛ حساب الكابتن متاح الآن.'else 'طلب تسجيل الكابتن يحتاج تعديل: '||why end);
  return to_jsonb(a);
 end if;
 if p_action not in('save','submit')then raise exception 'UNKNOWN_ACTION';end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text,7341));
 if exists(select 1 from public.tkt_profiles where user_id=u and captain)then raise exception 'ALREADY_CAPTAIN';end if;
 insert into public.tkt_captain_applications(user_id)values(u)on conflict(user_id)do nothing;
 select * into a from public.tkt_captain_applications where user_id=u for update;
 if a.status in('pending','approved')then
  if p_action='submit' and a.status='pending'then return to_jsonb(a);end if;
  raise exception 'APPLICATION_LOCKED';
 end if;
 if p_action='save'then
  if p_data ? 'full_name'then a.full_name:=btrim(p_data->>'full_name');end if;
  if p_data ? 'phone'then
   ph:=tkt_private.normalize_phone(p_data->>'phone');
   if ph is null or ph is distinct from (select tkt_private.normalize_phone(phone)from public.tkt_profiles where user_id=u)then raise exception 'ACCOUNT_PHONE_REQUIRED';end if;
   a.phone:=ph;
  end if;
  if p_data ? 'province'then a.province:=btrim(p_data->>'province');end if;
  if p_data ? 'area'then a.area:=btrim(p_data->>'area');end if;
  if length(a.province)>80 or length(a.area)>160 then raise exception 'INVALID_FIELDS';end if;
  if p_data ? 'chassis'then a.chassis:=btrim(p_data->>'chassis');end if;
  if p_data ? 'color'then a.color:=btrim(p_data->>'color');end if;
  if p_data ? 'model'then a.model:=btrim(p_data->>'model');end if;
  if length(a.full_name)>160 or length(a.chassis)>80 or length(a.color)>50 or length(a.model)>80 then raise exception 'INVALID_FIELDS';end if;
  if p_data ? 'pending_slot'then
   slot:=p_data->>'pending_slot';if slot is not null and slot not in('id_front','id_back')then raise exception 'INVALID_DOCUMENT';end if;a.pending_slot:=slot;
  end if;
  if p_data ? 'document'then
   slot:=p_data->'document'->>'slot';path:=p_data->'document'->>'path';
   if slot is null or slot not in('id_front','id_back')or path is null or split_part(path,'/',1)<>u::text or not exists(select 1 from storage.objects where bucket_id='captain-documents'and name=path)then raise exception 'INVALID_DOCUMENT';end if;
   a.documents:=jsonb_set(a.documents,array[slot],to_jsonb(path),true);a.pending_slot:=null;
  end if;
 else
  if cardinality(regexp_split_to_array(btrim(a.full_name),'\s+'))<3 or length(a.full_name)<5 then raise exception 'FULL_NAME_REQUIRED';end if;
  if a.phone='' or a.phone is distinct from (select tkt_private.normalize_phone(phone)from public.tkt_profiles where user_id=u)then raise exception 'ACCOUNT_PHONE_REQUIRED';end if;
  if a.province='' or a.area='' then raise exception 'AREA_REQUIRED';end if;
  foreach slot in array array['id_front','id_back']loop
   path:=a.documents->>slot;
   if path is null or not exists(select 1 from storage.objects where bucket_id='captain-documents'and name=path and split_part(name,'/',1)=u::text)then raise exception 'DOCUMENTS_REQUIRED';end if;
  end loop;
  a.status:='pending';a.reason:='';a.revision:=a.revision+1;a.submitted_at:=clock_timestamp();a.reviewed_at:=null;a.reviewed_by:=null;a.pending_slot:=null;
  insert into tkt_private.preferences(user_id,captain_requested_at)values(u,clock_timestamp())on conflict(user_id)do update set captain_requested_at=excluded.captain_requested_at;
 end if;
 update public.tkt_captain_applications set province=a.province,area=a.area,verification=a.verification,full_name=a.full_name,phone=a.phone,chassis=a.chassis,color=a.color,model=a.model,documents=a.documents,pending_slot=a.pending_slot,status=a.status,reason=a.reason,revision=a.revision,submitted_at=a.submitted_at,reviewed_at=a.reviewed_at,reviewed_by=a.reviewed_by,updated_at=clock_timestamp()where user_id=u returning * into a;
 return to_jsonb(a);
end $function$;


CREATE OR REPLACE FUNCTION tkt_private.pricing_admin(p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c tkt_private.pricing_settings;t jsonb;prev integer:=0;u uuid:=auth.uid();
begin
 perform tkt_private.require_dashboard('pricing',p_action='save');
 if p_action='save' then
  perform pg_advisory_xact_lock(74658291);
  select * into strict c from tkt_private.pricing_settings where id for update;
  if (p_data->>'expected_revision')::integer is distinct from c.revision then raise exception 'PRICING_CONFLICT';end if;
  if jsonb_typeof(p_data->'tiers') is distinct from 'array' or jsonb_array_length(p_data->'tiers') not between 1 and 30 then raise exception 'INVALID_PRICING';end if;
  for t in select value from jsonb_array_elements(p_data->'tiers') loop
   if jsonb_typeof(t->'up_to_m') is distinct from 'number' or jsonb_typeof(t->'fare') is distinct from 'number' or (t->>'up_to_m') !~ '^[0-9]+$' or (t->>'fare') !~ '^[0-9]+$' then raise exception 'INVALID_PRICING';end if;
   if (t->>'up_to_m')::numeric<=prev or (t->>'up_to_m')::numeric>100000 or (t->>'fare')::numeric>1000000 then raise exception 'INVALID_PRICING';end if;
   prev:=(t->>'up_to_m')::integer;
  end loop;
  foreach t in array array[p_data->'night_amount',p_data->'night_min_m',p_data->'night_start',p_data->'night_end',p_data->'overflow_step_m',p_data->'overflow_amount',p_data->'max_fare'] loop
   if jsonb_typeof(t) is distinct from 'number' or t::text !~ '^[0-9]+$' then raise exception 'INVALID_PRICING';end if;
  end loop;
  if (p_data->>'night_amount')::numeric>100000 or (p_data->>'night_min_m')::numeric>100000 or (p_data->>'night_start')::numeric>23 or (p_data->>'night_end')::numeric>23 or (p_data->>'overflow_step_m')::numeric not between 1 and 100000 or (p_data->>'overflow_amount')::numeric>100000 or (p_data->>'max_fare')::numeric>1000000 then raise exception 'INVALID_PRICING';end if;
  update tkt_private.pricing_settings set tiers=p_data->'tiers',night_amount=(p_data->>'night_amount')::integer,night_min_m=(p_data->>'night_min_m')::integer,night_start=(p_data->>'night_start')::integer,night_end=(p_data->>'night_end')::integer,overflow_step_m=(p_data->>'overflow_step_m')::integer,overflow_amount=(p_data->>'overflow_amount')::integer,max_fare=(p_data->>'max_fare')::integer,revision=revision+1,updated_at=clock_timestamp(),updated_by=u where id;
 elsif p_action='preview' then
  return tkt_private.fare((p_data->>'distance_m')::numeric,coalesce((p_data->>'at')::timestamptz,clock_timestamp()));
 elsif p_action<>'get' then raise exception 'UNKNOWN_ACTION';end if;
 return (select to_jsonb(s)-'updated_by' from tkt_private.pricing_settings s where id);
end $function$;


CREATE OR REPLACE FUNCTION tkt_private.dispatch_v1(p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare u uuid:=auth.uid();res jsonb;r public.tkt_rides;z jsonb;pts jsonb;p jsonb;
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 if p_action not in ('snapshot','settings') then perform pg_advisory_xact_lock(74658291);perform tkt_private.dispatch_maintenance();end if;
 if not exists(select 1 from public.tkt_profiles where user_id=u and not blocked) then raise exception 'ACCOUNT_BLOCKED';end if;
 if p_action='snapshot' then
  return jsonb_build_object('server_now',clock_timestamp(),'max_eta_s',(select max_eta_s from tkt_private.dispatch_settings where id),'features_enabled',to_regprocedure('public.tkt_extra(text,jsonb)') is not null);
 elsif p_action='book' then
  if to_regprocedure('tkt_private.extra(text,jsonb)') is not null then execute 'select tkt_private.extra($1,$2)' into res using 'book',p_data;return res;end if;
  if coalesce(p_data->>'payment_method','cash')<>'cash' then raise exception 'FEATURE_NOT_ENABLED';end if;
  res:=tkt_private.action('create',p_data);
  update public.tkt_rides set pickup_name=left(p_data->>'pickup_name',256),destination_name=left(p_data->>'destination_name',256) where id=(res->>'id')::uuid returning * into r;return to_jsonb(r);
 elsif p_action='retry' then
  select * into r from public.tkt_rides where id=(p_data->>'ride_id')::uuid and rider_id=u for update;
  -- New quote/booking required: never restart an old financial reservation or reuse a stale price.
  if r.id is null or r.dispatch_state<>'no_captain' then raise exception 'RIDE_UNAVAILABLE';end if;
  return jsonb_build_object('pickup',r.pickup,'destination',r.destination,'pickup_name',r.pickup_name,'destination_name',r.destination_name);
 elsif p_action in ('settings','configure') then
  perform tkt_private.require_dashboard('coverage',p_action='configure');
  if p_action='configure' then
   if p_data ? 'zones' then
    if jsonb_typeof(p_data->'zones')<>'array' or jsonb_array_length(p_data->'zones') not between 1 and 20 then raise exception 'INVALID_ZONES';end if;
    for z in select value from jsonb_array_elements(p_data->'zones') loop
     if coalesce(z->>'id','') !~ '^[a-z0-9_-]{1,40}$' or z->'geometry'->>'type'<>'Polygon' or jsonb_array_length(z->'geometry'->'coordinates')<>1 then raise exception 'INVALID_ZONES';end if;
     pts:=z->'geometry'->'coordinates'->0;
     if jsonb_array_length(pts) not between 4 and 100 or pts->0<>pts->(jsonb_array_length(pts)-1) then raise exception 'INVALID_ZONES';end if;
     for p in select value from jsonb_array_elements(pts) loop if jsonb_array_length(p)<>2 or (p->>0)::float8 not between 38 and 49 or (p->>1)::float8 not between 29 and 38 then raise exception 'INVALID_ZONES';end if;end loop;
    end loop;
    if (select count(distinct value->>'id') from jsonb_array_elements(p_data->'zones'))<>jsonb_array_length(p_data->'zones') then raise exception 'INVALID_ZONES';end if;
    if exists(select 1 from tkt_private.dispatch_jobs where state='searching') then raise exception 'SEARCH_IN_PROGRESS';end if;
    update tkt_private.dispatch_settings set zones=p_data->'zones' where id;
    update tkt_private.dispatch_locations set received_at='epoch'::timestamptz where captain_id is not null; -- Revalidate at the next fresh GPS update.
   end if;
   update tkt_private.dispatch_settings set max_eta_s=coalesce((p_data->>'max_eta_s')::integer,max_eta_s),search_s=coalesce((p_data->>'search_s')::integer,search_s),stale_s=coalesce((p_data->>'stale_s')::integer,stale_s) where id;
  end if;
  return (select to_jsonb(s)-'mapbox_token'-'lease_id' from tkt_private.dispatch_settings s where id);
 else raise exception 'UNKNOWN_ACTION';end if;
end $function$;


CREATE OR REPLACE FUNCTION tkt_private.wheel(p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u uuid:=auth.uid();ident uuid;pr tkt_private.wheel_prizes;spin tkt_private.wheel_spins;res jsonb;qty integer;rev bigint;flag boolean;
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 -- Consistent user lock order with profile deletion and existing account operations.
 perform 1 from public.tkt_profiles where user_id=u and not blocked for update;
 if not found then raise exception 'ACCOUNT_BLOCKED';end if;
 if p_action in('snapshot','spin') and not exists(select 1 from public.tkt_profiles where user_id=u and captain) then raise exception 'WHEEL_CAPTAIN_ONLY';end if;
 if p_action='snapshot' then
  return jsonb_build_object('enabled',(select enabled from tkt_private.wheel_settings where id),
    'server_now',clock_timestamp(),'next_spin_at',(select max(created_at)+interval '3 days' from tkt_private.wheel_spins where user_id=u),
    'history',coalesce((select jsonb_agg(to_jsonb(x)order by x.created_at desc) from
      (select id,prize_key,prize_title,status,created_at,delivered_at from tkt_private.wheel_spins where user_id=u order by created_at desc,id limit 20)x),'[]'::jsonb));
 elsif p_action='spin' then
  ident:=(p_data->>'id')::uuid;
  if ident is null then raise exception 'SPIN_ID_REQUIRED';end if;
  -- All inventory changes share one lock, including admin edits.
  perform pg_advisory_xact_lock(748251760);
  select * into spin from tkt_private.wheel_spins where id=ident;
  if found then
   if spin.user_id<>u then raise exception 'SPIN_ID_CONFLICT';end if;
   return jsonb_build_object('id',spin.id,'prize_key',spin.prize_key,'prize_title',spin.prize_title,'status',spin.status,'created_at',spin.created_at,'next_spin_at',(select max(created_at)+interval '3 days' from tkt_private.wheel_spins where user_id=u),'server_now',clock_timestamp());
  end if;
  if exists(select 1 from tkt_private.wheel_spins where user_id=u and created_at>clock_timestamp()-interval '3 days') then raise exception 'WHEEL_COOLDOWN';end if;
  if not (select enabled from tkt_private.wheel_settings where id) then raise exception 'WHEEL_PAUSED';end if;
  select * into pr from tkt_private.wheel_prizes where enabled and remaining>0 order by random() limit 1 for update;
  if found then
   update tkt_private.wheel_prizes set remaining=remaining-1,revision=revision+1 where key=pr.key;
   insert into tkt_private.wheel_spins(id,user_id,prize_key,prize_title,status)values(ident,u,pr.key,pr.title,'pending')returning * into spin;
  else
   insert into tkt_private.wheel_spins(id,user_id,prize_title,status)values(ident,u,'حظ أوفر','no_prize')returning * into spin;
  end if;
  return jsonb_build_object('id',spin.id,'prize_key',spin.prize_key,'prize_title',spin.prize_title,'status',spin.status,'created_at',spin.created_at,'next_spin_at',(select max(created_at)+interval '3 days' from tkt_private.wheel_spins where user_id=u),'server_now',clock_timestamp());
 end if;
 perform tkt_private.require_dashboard('wheel',p_action<>'admin_snapshot');
 if p_action='admin_snapshot' then
  return jsonb_build_object('enabled',(select enabled from tkt_private.wheel_settings where id),
   'prizes',(select jsonb_agg(to_jsonb(p)order by key)from tkt_private.wheel_prizes p),
   'pending',(select count(*)from tkt_private.wheel_spins where status='pending'),
   'wins',(select count(*)from tkt_private.wheel_spins where prize_key is not null),
   'spins',(select count(*)from tkt_private.wheel_spins),
   'claims',coalesce((select jsonb_agg(to_jsonb(x)order by x.created_at desc)from
    (select s.*,p.name,p.phone from tkt_private.wheel_spins s join public.tkt_profiles p on p.user_id=s.user_id
     where s.prize_key is not null and (coalesce(p_data->>'status','')='' or s.status=p_data->>'status')
     order by s.created_at desc,s.id limit 100 offset least(100000,greatest(0,coalesce((p_data->>'offset')::integer,0))))x),'[]'::jsonb));
 elsif p_action='stock' then
  if coalesce(p_data->>'remaining','') !~ '^[0-9]{1,6}$' or jsonb_typeof(p_data->'enabled')<>'boolean' then raise exception 'INVALID_WHEEL_STOCK';end if;
  qty:=(p_data->>'remaining')::integer;rev:=(p_data->>'revision')::bigint;
  if qty>100000 or rev is null or p_data->'enabled' is null then raise exception 'INVALID_WHEEL_STOCK';end if;
  perform pg_advisory_xact_lock(748251760);
  update tkt_private.wheel_prizes set remaining=qty,enabled=(p_data->>'enabled')::boolean,revision=revision+1
   where key=p_data->>'key' and revision=rev returning * into pr;
  if not found then raise exception 'WHEEL_STOCK_CHANGED';end if;
  return to_jsonb(pr);
 elsif p_action='configure' then
  if p_data->'enabled' is null or jsonb_typeof(p_data->'enabled')<>'boolean' then raise exception 'INVALID_WHEEL_SETTING';end if;
  perform pg_advisory_xact_lock(748251760);
  update tkt_private.wheel_settings set enabled=(p_data->>'enabled')::boolean where id;
  return jsonb_build_object('ok',true);
 elsif p_action='deliver' then
  ident:=(p_data->>'id')::uuid;
  update tkt_private.wheel_spins set status='delivered',delivered_at=clock_timestamp(),delivered_by=u where id=ident and status='pending' returning * into spin;
  if not found then
   select * into spin from tkt_private.wheel_spins where id=ident and status='delivered';
   if not found then raise exception 'WHEEL_CLAIM_UNAVAILABLE';end if;
  end if;
  return jsonb_build_object('ok',true,'id',spin.id,'status',spin.status);
 else raise exception 'UNKNOWN_WHEEL_ACTION';end if;
end $function$;


CREATE OR REPLACE FUNCTION tkt_private.extra(p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u uuid:=auth.uid(); adm boolean; target uuid; res jsonb; q public.tkt_quotes; r public.tkt_rides; c tkt_private.coupons; bal integer; disc integer:=0; due integer; ident uuid; value integer; room uuid; iscap boolean;
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 select captain into iscap from public.tkt_profiles where user_id=u and not blocked for update;
 if not found then raise exception 'ACCOUNT_BLOCKED';end if;
 adm:=tkt_private.is_admin() or case when p_action in('messages','read') then tkt_private.dashboard_permission('support') when p_action='send' then tkt_private.dashboard_permission('support',true) when p_action='admin_snapshot' then tkt_private.dashboard_permission('finance') or tkt_private.dashboard_permission('support') when p_action in('topup','settle','coupon_admin') then tkt_private.dashboard_permission('finance',true) else false end;
 insert into tkt_private.wallets(user_id) values(u) on conflict do nothing;
 insert into tkt_private.preferences(user_id) values(u) on conflict do nothing;
 if p_action='snapshot' then
  select jsonb_build_object('balance',(select balance from tkt_private.wallets where user_id=u),'coupon',(select to_jsonb(cc) from tkt_private.coupons cc join tkt_private.preferences pp on pp.coupon=cc.code where pp.user_id=u and cc.active and cc.expires_at>now() and (select count(*) from tkt_private.coupon_uses where code=cc.code)<cc.max_uses and not exists(select 1 from tkt_private.coupon_uses x where x.code=cc.code and x.user_id=u)),
   'coupon_selected',(select coupon from tkt_private.preferences where user_id=u),
   'coupon_history',coalesce((select jsonb_agg(to_jsonb(h) order by h.selected_at desc) from (select cc.*, ch.selected_at, cu.ride_id, case when cu.ride_id is not null then 'used' when cc.expires_at<=now() then 'expired' when not cc.active or (select count(*) from tkt_private.coupon_uses x where x.code=cc.code)>=cc.max_uses then 'unavailable' when pp.coupon=cc.code then 'active' else 'saved' end as status from tkt_private.coupon_history ch join tkt_private.coupons cc on cc.code=ch.code left join tkt_private.coupon_uses cu on cu.code=ch.code and cu.user_id=u left join tkt_private.preferences pp on pp.user_id=u where ch.user_id=u) h),'[]'::jsonb),
   'addresses',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from tkt_private.addresses a where user_id=u),'[]'::jsonb),
   'ledger',coalesce((select jsonb_agg(to_jsonb(l)) from (select amount,kind,created_at from tkt_private.ledger where user_id=u order by created_at desc limit 100)l),'[]'::jsonb),
   'unread',(select count(*) from public.tkt_messages m join tkt_private.preferences p on p.user_id=m.user_id where m.user_id=u and m.is_admin and m.created_at>p.user_read),
   'captain_requested',(select captain_requested_at is not null from tkt_private.preferences where user_id=u)) into res;
  return res;
 elsif p_action='book' then
  if iscap then raise exception 'RIDER_PROFILE_REQUIRED';end if;
  select * into q from public.tkt_quotes where id=(p_data->>'quote_id')::uuid and user_id=u for update;
  if q.id is null then raise exception 'QUOTE_INVALID';end if;
  select * into r from public.tkt_rides where quote_id=q.id;
  if r.id is not null then return to_jsonb(r);end if;
  if q.expires_at<=now() then raise exception 'QUOTE_EXPIRED';end if;
  if coalesce(p_data->>'payment_method','cash') not in ('cash','wallet') then raise exception 'INVALID_PAYMENT';end if;
  select cc.* into c from tkt_private.coupons cc join tkt_private.preferences pp on pp.coupon=cc.code where pp.user_id=u for update of cc;
  if c.code is not null then
   if not c.active or c.expires_at<=now() or exists(select 1 from tkt_private.coupon_uses where code=c.code and user_id=u) or (select count(*) from tkt_private.coupon_uses where code=c.code)>=c.max_uses then
    c:=null;
    update tkt_private.preferences set coupon=null where user_id=u;
   else disc:=least(q.fare,c.amount);end if;
  end if;
  due:=q.fare-disc;
  if p_data->>'payment_method'='wallet' then
   select balance into bal from tkt_private.wallets where user_id=u for update;
   if bal<due then raise exception 'INSUFFICIENT_BALANCE';end if;
  end if;
  res:=tkt_private.action('create',jsonb_build_object('quote_id',q.id));
  select * into r from public.tkt_rides where id=(res->>'id')::uuid;
  update public.tkt_rides set pickup_name=left(coalesce(p_data->>'pickup_name','موقع الانطلاق'),256),destination_name=left(coalesce(p_data->>'destination_name','الوجهة'),256),payment_method=coalesce(p_data->>'payment_method','cash'),discount=disc,customer_due=due,coupon_code=c.code where id=r.id returning * into r;
  if r.payment_method='wallet' then
   update tkt_private.wallets set balance=balance-due where user_id=u;
   insert into tkt_private.ledger(user_id,amount,kind,ride_id) values(u,-due,'ride_payment',r.id);
  end if;
  if c.code is not null then insert into tkt_private.coupon_uses(ride_id,code,user_id) values(r.id,c.code,u);end if;
  return to_jsonb(r);
 elsif p_action='coupon' then
  if coalesce(p_data->>'code','')='' then update tkt_private.preferences set coupon=null where user_id=u;return '{"ok":true}';end if;
  select * into c from tkt_private.coupons where code=upper(trim(p_data->>'code')) for update;
  if c.code is null or not c.active or c.expires_at<=now() or exists(select 1 from tkt_private.coupon_uses where code=c.code and user_id=u) or (select count(*) from tkt_private.coupon_uses where code=c.code)>=c.max_uses then raise exception 'COUPON_EXPIRED';end if;
  insert into tkt_private.coupon_history(user_id,code) values(u,c.code) on conflict(user_id,code) do update set selected_at=now();
  update tkt_private.preferences set coupon=c.code where user_id=u;
 elsif p_action='address_save' then
  if (select count(*) from tkt_private.addresses where user_id=u)>=30 then raise exception 'ADDRESS_LIMIT';end if;
  insert into tkt_private.addresses(user_id,label,lat,lng) values(u,trim(p_data->>'label'),(p_data->>'lat')::float8,(p_data->>'lng')::float8);
 elsif p_action='address_delete' then delete from tkt_private.addresses where id=(p_data->>'id')::uuid and user_id=u;
 elsif p_action='captain_apply' then
  if exists(select 1 from public.tkt_profiles where user_id=u and (name='' or phone='')) then raise exception 'INVALID_PROFILE';end if;
  update tkt_private.preferences set captain_requested_at=coalesce(captain_requested_at,now()) where user_id=u;
 elsif p_action in ('messages','send','read') then
  room:=coalesce((p_data->>'user_id')::uuid,u);
  if room<>u and not adm then raise exception 'FORBIDDEN';end if;
  if not exists(select 1 from public.tkt_profiles where user_id=room) then raise exception 'PROFILE_REQUIRED';end if;
  insert into tkt_private.preferences(user_id) values(room) on conflict do nothing;
  if p_action='send' then
   if (select count(*) from public.tkt_messages where sender_id=u and created_at>now()-interval '1 minute')>=30 then raise exception 'RATE_LIMIT';end if;
   ident:=(p_data->>'id')::uuid;
   if ident is null then raise exception 'INVALID_MESSAGE';end if;
   insert into public.tkt_messages(id,user_id,sender_id,is_admin,body) values(ident,room,u,adm,trim(p_data->>'body')) on conflict(id) do nothing;
  elsif p_action='read' then
   if adm and room<>u then update tkt_private.preferences set admin_read=now() where user_id=room;
   else update tkt_private.preferences set user_read=now() where user_id=room;end if;
  end if;
  return coalesce((select jsonb_agg(to_jsonb(m) order by m.created_at) from (select * from public.tkt_messages where user_id=room order by created_at desc limit 200)m),'[]'::jsonb);
 elsif p_action='admin_snapshot' then
  if not adm then raise exception 'ADMIN_REQUIRED';end if;
  return jsonb_build_object('wallets',coalesce((select jsonb_agg(to_jsonb(t)) from (select p.user_id,p.name,p.phone,p.captain,w.balance,pr.captain_requested_at from public.tkt_profiles p left join tkt_private.wallets w on w.user_id=p.user_id left join tkt_private.preferences pr on pr.user_id=p.user_id order by p.created_at desc limit 500)t),'[]'::jsonb),
   'coupons',coalesce((select jsonb_agg(to_jsonb(coupon_row)) from tkt_private.coupons coupon_row),'[]'::jsonb),
   'rooms',coalesce((select jsonb_agg(to_jsonb(t)) from (select p.user_id,p.name,p.phone,max(m.created_at) as last_at,count(*) filter(where not m.is_admin and m.created_at>pr.admin_read) as unread from public.tkt_profiles p join public.tkt_messages m on m.user_id=p.user_id join tkt_private.preferences pr on pr.user_id=p.user_id group by p.user_id,pr.admin_read order by max(m.created_at) desc limit 500)t),'[]'::jsonb));
 elsif p_action in ('topup','settle') then
  if not adm then raise exception 'ADMIN_REQUIRED';end if;
  target:=(p_data->>'user_id')::uuid;ident:=(p_data->>'id')::uuid;value:=(p_data->>'amount')::integer;
  if ident is null or value is null or value not between 1 and 10000000 then raise exception 'INVALID_AMOUNT';end if;
  select captain into iscap from public.tkt_profiles where user_id=target and not blocked for update;
  if not found then raise exception 'PROFILE_REQUIRED';end if;
  if p_action='settle' and not iscap then raise exception 'CAPTAIN_REQUIRED';end if;
  if exists(select 1 from tkt_private.ledger where id=ident) then return '{"ok":true}';end if;
  insert into tkt_private.wallets(user_id) values(target) on conflict do nothing;
  select balance into bal from tkt_private.wallets where user_id=target for update;
  if p_action='settle' and bal<value then raise exception 'INSUFFICIENT_BALANCE';end if;
  insert into tkt_private.ledger(id,user_id,amount,kind,actor_id) values(ident,target,case when p_action='settle' then -value else value end,p_action,u);
  update tkt_private.wallets set balance=balance+(case when p_action='settle' then -value else value end) where user_id=target;
 elsif p_action='coupon_admin' then
  if not adm then raise exception 'ADMIN_REQUIRED';end if;
  insert into tkt_private.coupons(code,amount,expires_at,max_uses,active) values(upper(trim(p_data->>'code')),(p_data->>'amount')::integer,(p_data->>'expires_at')::timestamptz,(p_data->>'max_uses')::integer,coalesce((p_data->>'active')::boolean,true)) on conflict(code) do update set amount=excluded.amount,expires_at=excluded.expires_at,max_uses=excluded.max_uses,active=excluded.active;
 else raise exception 'UNKNOWN_ACTION';end if;
 return '{"ok":true}'::jsonb;
end $function$;


create or replace function public.tkt_extra(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql set search_path='' as $$
begin
 if p_action='admin_snapshot' then perform tkt_private.require_dashboard('finance');end if;
 return tkt_private.extra(p_action,p_data);
end;$$;
CREATE OR REPLACE FUNCTION tkt_private.legacy_action(p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid:=auth.uid(); me public.tkt_profiles; r public.tkt_rides; q public.tkt_quotes; target uuid; until_at timestamptz; result jsonb; dist double precision;
begin
 if uid is null then raise exception 'AUTH_REQUIRED';end if;
 if p_action='me' then
  if not exists(select 1 from public.tkt_profiles where user_id=uid) then insert into public.tkt_profiles(user_id) values(uid) on conflict do nothing;end if;
  select * into me from public.tkt_profiles where user_id=uid;
  return to_jsonb(me)||jsonb_build_object('admin',tkt_private.is_admin());
 end if;
 if p_action in ('snapshot','contact') then select * into me from public.tkt_profiles where user_id=uid;else select * into me from public.tkt_profiles where user_id=uid for update;end if;
 if me.user_id is null then raise exception 'PROFILE_REQUIRED';end if;
 if me.blocked then raise exception 'ACCOUNT_BLOCKED';end if;
 if p_action='profile' then
  if length(trim(p_data->>'name')) not between 1 and 80 or coalesce(p_data->>'phone','') !~ '^(07[0-9]{9}|\+9647[0-9]{9})$' then raise exception 'INVALID_PROFILE';end if;
  if p_data ? 'gender' and coalesce(p_data->>'gender','') not in ('male','female') then raise exception 'PROFILE_GENDER_INVALID';end if;
  update public.tkt_profiles set name=trim(p_data->>'name'),phone=p_data->>'phone',gender=coalesce(p_data->>'gender',gender) where user_id=uid;
 elsif p_action='presence' then
  if not me.captain then raise exception 'CAPTAIN_REQUIRED';end if;
  if coalesce((p_data->>'online')::boolean,false) and coalesce(me.expires_at,now())<=now() and not exists(select 1 from public.tkt_rides where captain_id=uid and status in ('accepted','arrived','in_progress')) then raise exception 'SUBSCRIPTION_EXPIRED';end if;
  if (p_data->>'lat')::double precision not between 29 and 38 or (p_data->>'lng')::double precision not between 38 and 49 then raise exception 'OUTSIDE_SERVICE';end if;
  if p_data->>'lat' is null or p_data->>'lng' is null then raise exception 'LOCATION_REQUIRED';end if;
  update public.tkt_profiles set online=coalesce((p_data->>'online')::boolean,false),lat=(p_data->>'lat')::double precision,lng=(p_data->>'lng')::double precision,location_at=now() where user_id=uid;
 elsif p_action='create' then
  if me.captain or me.name='' or me.phone='' then raise exception 'RIDER_PROFILE_REQUIRED';end if;
  select * into q from public.tkt_quotes where id=(p_data->>'quote_id')::uuid and user_id=uid;
  if q.id is null then raise exception 'QUOTE_INVALID';end if;
  select * into r from public.tkt_rides where quote_id=q.id;
  if r.id is not null then return to_jsonb(r);end if;
  if q.expires_at<=now() then raise exception 'QUOTE_EXPIRED';end if;
  update public.tkt_rides set status='cancelled',updated_at=now() where rider_id=uid and status='pending' and created_at<now()-interval '10 minutes';
  insert into public.tkt_rides(quote_id,rider_id,pickup,destination,geometry,fare,distance_m,duration_s) values(q.id,uid,q.pickup,q.destination,q.geometry,q.fare,q.distance_m,q.duration_s) returning * into r;

  return to_jsonb(r);
 elsif p_action='snapshot' then
  select coalesce(jsonb_agg(to_jsonb(t)),'[]') into result from (select rr.* from public.tkt_rides rr where rr.rider_id=uid or rr.captain_id=uid order by rr.created_at desc limit 100)t;
  return result;
 elsif p_action='requests' then
  if not me.captain or not me.online or coalesce(me.expires_at,now())<=now() or me.location_at<now()-interval '90 seconds' then return '[]'::jsonb;end if;
  if exists(select 1 from public.tkt_rides where captain_id=uid and status in ('accepted','arrived','in_progress')) then return '[]'::jsonb;end if;
  select coalesce(jsonb_agg(to_jsonb(t)),'[]') into result from (
   select id,pickup,destination,fare,distance_m,duration_s,created_at,tkt_private.km(me.lat,me.lng,(pickup->>0)::float8,(pickup->>1)::float8) as away_km from public.tkt_rides
   where status='pending' and rider_id<>uid and created_at>now()-interval '10 minutes' and tkt_private.km(me.lat,me.lng,(pickup->>0)::float8,(pickup->>1)::float8)<=5 order by away_km,created_at limit 10)t;
  return result;
 elsif p_action='claim' then
  if not me.captain or not me.online or me.name='' or me.phone='' or coalesce(me.expires_at,now())<=now() or coalesce(me.location_at,now()-interval '1 day')<now()-interval '90 seconds' then raise exception 'CAPTAIN_UNAVAILABLE';end if;
  select * into r from public.tkt_rides where id=(p_data->>'ride_id')::uuid for update;
  if r.id is null or r.status<>'pending' or r.rider_id=uid or r.created_at<now()-interval '10 minutes' then raise exception 'RIDE_UNAVAILABLE';end if;
  if tkt_private.km(me.lat,me.lng,(r.pickup->>0)::float8,(r.pickup->>1)::float8)>5 then raise exception 'TOO_FAR';end if;
  update public.tkt_rides set captain_id=uid,status='accepted',updated_at=now() where id=r.id returning * into r;
  return to_jsonb(r)-'start_code';
 elsif p_action='ride_status' then
  select * into r from public.tkt_rides where id=(p_data->>'ride_id')::uuid for update;
  if r.id is null or (r.rider_id<>uid and r.captain_id is distinct from uid and not tkt_private.dashboard_permission('rides',true)) then raise exception 'FORBIDDEN';end if;
  if p_data->>'status'='cancelled' and r.status='cancelled' then
   return jsonb_build_object('ok',true);
  end if;
  if p_data->>'status'='cancelled' and (r.rider_id=uid or r.captain_id=uid or tkt_private.dashboard_permission('rides',true)) and r.status in ('pending','accepted','arrived') then
   update public.tkt_rides set status='cancelled',updated_at=now() where id=r.id;
  elsif r.captain_id=uid and me.captain and ((r.status='accepted' and p_data->>'status'='arrived') or (r.status='arrived' and p_data->>'status'='in_progress') or (r.status='in_progress' and p_data->>'status'='completed')) then
   update public.tkt_rides set status=p_data->>'status',updated_at=now() where id=r.id;
  else raise exception 'INVALID_STATUS_OR_CODE';end if;
 elsif p_action='contact' then
  select * into r from public.tkt_rides where id=(p_data->>'ride_id')::uuid;
  if r.id is null or r.status not in ('accepted','arrived','in_progress') or (r.rider_id<>uid and r.captain_id is distinct from uid) then raise exception 'FORBIDDEN';end if;
  target:=case when uid=r.rider_id then r.captain_id else r.rider_id end;
  select jsonb_build_object('name',name,'phone',phone,'lat',lat,'lng',lng,'location_at',location_at,'avatar_path',avatar_path) into result from public.tkt_profiles where user_id=target;
  return result;
 elsif p_action='nearby' then
  select coalesce(jsonb_agg(to_jsonb(t)),'[]') into result from (select user_id,lat,lng,location_at from public.tkt_profiles p where captain and online and not blocked and expires_at>now() and location_at>now()-interval '90 seconds' and tkt_private.km((p_data->>'lat')::float8,(p_data->>'lng')::float8,lat,lng)<5 and not exists(select 1 from public.tkt_rides where captain_id=p.user_id and status in ('accepted','arrived','in_progress')) limit 30)t;
  return result;
 elsif p_action in ('role','renew','block') then
  perform tkt_private.require_dashboard('users',true);
  target:=(p_data->>'user_id')::uuid; if exists(select 1 from public.tkt_admins where user_id=target) or exists(select 1 from tkt_private.staff_accounts where user_id=target) then raise exception 'PROTECTED_ADMIN';end if;
  if exists(select 1 from public.tkt_rides where (captain_id=target or rider_id=target) and status in ('accepted','arrived','in_progress')) then raise exception 'ACTIVE_RIDE';end if;
  if p_action='role' then update public.tkt_profiles set captain=(p_data->>'captain')::boolean,online=false where user_id=target;
  elsif p_action='block' then update public.tkt_profiles set blocked=(p_data->>'blocked')::boolean,online=false where user_id=target;
  else
   select * into me from public.tkt_profiles where user_id=target for update;
   if me.user_id is null or not me.captain or me.blocked then raise exception 'INVALID_CAPTAIN';end if;
   if exists(select 1 from public.tkt_payments where id=(p_data->>'payment_id')::uuid) then return jsonb_build_object('ok',true);end if;
   until_at:=greatest(coalesce(me.expires_at,now()),now())+interval '7 days';
   insert into public.tkt_payments(id,captain_id,admin_id,expires_at) values((p_data->>'payment_id')::uuid,target,uid,until_at);
   update public.tkt_profiles set expires_at=until_at where user_id=target;
  end if;
 else raise exception 'UNKNOWN_ACTION';end if;
 return jsonb_build_object('ok',true);
end$function$;


CREATE OR REPLACE FUNCTION tkt_private.profile_photo_read(p_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select auth.uid() is not null
 and exists(select 1 from public.tkt_profiles where user_id=auth.uid() and not blocked)
 and (tkt_private.dashboard_permission('inventory') or tkt_private.dashboard_permission('users') or tkt_private.dashboard_permission('rides') or tkt_private.dashboard_permission('applications') or tkt_private.dashboard_permission('finance') or tkt_private.dashboard_permission('support') or split_part(p_name,'/',1)=auth.uid()::text
 or exists(select 1 from public.tkt_profiles owner join public.tkt_rides ride
   on (ride.rider_id=owner.user_id and ride.captain_id=auth.uid())
   or (ride.captain_id=owner.user_id and ride.rider_id=auth.uid())
   where owner.avatar_path=p_name and ride.status in('accepted','arrived','in_progress')));
$function$;


CREATE OR REPLACE FUNCTION tkt_private.banner_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select auth.uid() is not null and tkt_private.dashboard_permission('banners',true)
 and exists(select 1 from public.tkt_profiles where user_id=auth.uid() and not blocked)
$function$;



-- Staff can subscribe only to data covered by their assigned pages.
create policy tkt_staff_live_profiles on public.tkt_profiles for select to authenticated using((select tkt_private.dashboard_permission('overview')));
create policy tkt_staff_rides on public.tkt_rides for select to authenticated using((select tkt_private.dashboard_permission('rides')) or (select tkt_private.dashboard_permission('overview')));
create policy tkt_staff_offers on public.tkt_offers for select to authenticated using((select tkt_private.dashboard_permission('rides')) or (select tkt_private.dashboard_permission('overview')));
create policy tkt_staff_messages on public.tkt_messages for select to authenticated using((select tkt_private.dashboard_permission('support')));
create policy tkt_staff_applications on public.tkt_captain_applications for select to authenticated using((select tkt_private.dashboard_permission('applications')));
create policy tkt_staff_banner_rows on public.tkt_home_banners for select to authenticated using((select tkt_private.dashboard_permission('banners')));
create policy tkt_staff_banner_objects on storage.objects for select to authenticated using(bucket_id='taktooka-banners' and (select tkt_private.dashboard_permission('banners')));
create policy tkt_staff_document_read on storage.objects for select to authenticated using(bucket_id='captain-documents' and (select tkt_private.dashboard_permission('applications')));
