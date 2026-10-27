begin;
create table if not exists tkt_private.admin_audit(id uuid primary key default gen_random_uuid(),actor_id uuid not null,action text not null,entity_id text,details jsonb not null default '{}',created_at timestamptz not null default now());
create index if not exists admin_audit_time on tkt_private.admin_audit(created_at desc);
create table if not exists tkt_private.admin_archives(kind text not null,entity_id text not null,actor_id uuid not null,created_at timestamptz not null default now(),primary key(kind,entity_id));
alter table tkt_private.admin_audit enable row level security;
alter table tkt_private.admin_archives enable row level security;
revoke all on tkt_private.admin_audit,tkt_private.admin_archives from public,anon,authenticated;
create or replace function tkt_private.manage(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); target uuid; ident uuid; result jsonb; rec public.tkt_profiles; ride public.tkt_rides; ph text; v_kind text; entity text; n integer; lim integer:=least(500,greatest(1,coalesce((p_data->>'limit')::integer,200))); offn integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 if not tkt_private.is_admin() then raise exception 'ADMIN_REQUIRED';end if;
 if not exists(select 1 from public.tkt_profiles where user_id=u and not blocked) then raise exception 'ACCOUNT_BLOCKED';end if;
 target:=nullif(p_data->>'user_id','')::uuid;
 ident:=nullif(p_data->>'id','')::uuid;
 if p_action='overview' then
  return jsonb_build_object('server_now',clock_timestamp(),'users',(select count(*) from public.tkt_profiles),'captains',(select count(*) from public.tkt_profiles where captain),'online',(select count(*) from public.tkt_profiles where captain and online and not blocked and location_at>clock_timestamp()-interval '90 seconds'),'active_rides',(select count(*) from public.tkt_rides where status in('pending','accepted','arrived','in_progress')),'today_rides',(select count(*) from public.tkt_rides where (created_at at time zone 'Asia/Baghdad')::date=(now() at time zone 'Asia/Baghdad')::date),'today_completed',(select coalesce(sum(fare),0) from public.tkt_rides where status='completed' and (updated_at at time zone 'Asia/Baghdad')::date=(now() at time zone 'Asia/Baghdad')::date),'applications',(select count(*) from tkt_private.preferences where captain_requested_at is not null),'worker',(select jsonb_build_object('heartbeat',last_worker_at,'last_error',last_error) from tkt_private.dispatch_settings where id));
 elsif p_action='users' then
  return coalesce((select jsonb_agg(to_jsonb(x)) from(select p.*,exists(select 1 from public.tkt_admins where user_id=p.user_id) as admin from public.tkt_profiles p where not exists(select 1 from tkt_private.admin_archives where kind='user' and entity_id=p.user_id::text) and (coalesce(p_data->>'search','')='' or p.name ilike '%'||(p_data->>'search')||'%' or p.phone ilike '%'||(p_data->>'search')||'%') order by p.created_at desc limit lim offset offn)x),'[]');
 elsif p_action='rides' then
  return coalesce((select jsonb_agg(to_jsonb(x)) from(select r.*,p.name as rider_name,p.phone as rider_phone,c.name as captain_name,c.phone as captain_phone from public.tkt_rides r left join public.tkt_profiles p on p.user_id=r.rider_id left join public.tkt_profiles c on c.user_id=r.captain_id where not exists(select 1 from tkt_private.admin_archives where kind='ride' and entity_id=r.id::text) and (coalesce(p_data->>'status','')='' or r.status=p_data->>'status') and (coalesce(p_data->>'search','')='' or r.id::text ilike '%'||(p_data->>'search')||'%' or r.pickup_name ilike '%'||(p_data->>'search')||'%' or r.destination_name ilike '%'||(p_data->>'search')||'%' or p.phone ilike '%'||(p_data->>'search')||'%' or c.phone ilike '%'||(p_data->>'search')||'%') order by r.created_at desc limit lim offset offn)x),'[]');
 elsif p_action='track' then
  select * into ride from public.tkt_rides where id=ident;
  if not found then raise exception 'RIDE_UNAVAILABLE';end if;
  return jsonb_build_object('ride',to_jsonb(ride),'captain',(select jsonb_build_object('user_id',user_id,'name',name,'phone',phone,'lat',lat,'lng',lng,'location_at',location_at,'online',online)from public.tkt_profiles where user_id=ride.captain_id),'offers',coalesce((select jsonb_agg(to_jsonb(x))from(select id,captain_id,status,created_at,expires_at from public.tkt_offers where ride_id=ride.id order by created_at desc limit 50)x),'[]'),'server_now',clock_timestamp());
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
  return coalesce((select jsonb_agg(to_jsonb(x))from(select phone,failures,window_at,requests from tkt_private.phone_attempts where failures>0 order by window_at desc limit lim offset offn)x),'[]');
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
end $$;
revoke all on function tkt_private.manage(text,jsonb)from public,anon;
grant execute on function tkt_private.manage(text,jsonb)to authenticated;
create or replace function public.tkt_manage(p_action text,p_data jsonb default '{}')returns jsonb language sql security invoker set search_path='' as $$select tkt_private.manage(p_action,p_data)$$;
revoke all on function public.tkt_manage(text,jsonb)from public,anon;
grant execute on function public.tkt_manage(text,jsonb)to authenticated;
create or replace function tkt_private.audit_admin_changes()returns trigger language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); rowdata jsonb;
begin
 if actor is not null and tkt_private.is_admin() then
  rowdata:=case when TG_OP='DELETE' then to_jsonb(old)else to_jsonb(new)end;
  insert into tkt_private.admin_audit(actor_id,action,entity_id,details)values(actor,lower(TG_OP)||':'||TG_TABLE_NAME,coalesce(rowdata->>'id',rowdata->>'user_id',rowdata->>'code'),jsonb_build_object('table',TG_TABLE_NAME,'operation',TG_OP));
 end if;
 if TG_OP='DELETE' then return old;else return new;end if;
end $$;
revoke all on function tkt_private.audit_admin_changes()from public,anon,authenticated;
create or replace function tkt_private.reopen_support()returns trigger language plpgsql security definer set search_path='' as $$
begin
 if not new.is_admin then
  if TG_TABLE_NAME='tkt_messages' then delete from tkt_private.admin_archives where kind='support' and entity_id=new.user_id::text;
  else delete from tkt_private.admin_archives where kind='recovery' and entity_id=new.thread_id::text;end if;
 end if;
 return new;
end $$;
revoke all on function tkt_private.reopen_support()from public,anon,authenticated;
create trigger tkt_reopen_support after insert on public.tkt_messages for each row execute function tkt_private.reopen_support();
create trigger tkt_reopen_recovery after insert on public.tkt_recovery_messages for each row execute function tkt_private.reopen_support();
do $$declare item text;begin
 foreach item in array array['public.tkt_profiles','public.tkt_rides','public.tkt_payments','public.tkt_saved_places','public.tkt_messages','public.tkt_recovery_messages','tkt_private.wallets','tkt_private.coupons','tkt_private.dispatch_settings','tkt_private.pricing_settings']loop
  execute format('create trigger tkt_admin_audit_changes after insert or update or delete on %s for each row execute function tkt_private.audit_admin_changes()',item);
 end loop;
end $$;
commit;
