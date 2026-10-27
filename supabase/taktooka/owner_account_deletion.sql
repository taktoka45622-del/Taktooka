
alter table public.tkt_profiles add column if not exists deleted_at timestamptz;
alter table tkt_private.exchange_agents add column if not exists deleted_at timestamptz;
create table if not exists tkt_private.admin_account_deletions(
 id uuid primary key default gen_random_uuid(),target_kind text not null check(target_kind in('user','exchange')),target_id uuid not null,
 actor_id uuid not null,account_type text not null,status text not null default 'pending' check(status in('pending','purged','completed')),
 files jsonb not null default '[]',requested_at timestamptz not null default now(),completed_at timestamptz,
 unique(target_kind,target_id)
);
alter table tkt_private.admin_account_deletions enable row level security;
revoke all on tkt_private.admin_account_deletions from public,anon,authenticated;
grant all on tkt_private.admin_account_deletions to service_role;

create or replace function tkt_private.admin_delete_preview(p_kind text,p_id uuid,p_actor uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid;v_agent uuid;p public.tkt_profiles;a tkt_private.exchange_agents;j tkt_private.admin_account_deletions;v_type text;v_name text;v_phone text;v_balance bigint:=0;v_due bigint:=0;blockers jsonb:='[]';v_kind text:=p_kind;v_id uuid:=p_id;
begin
 if p_actor is null or not exists(select 1 from public.tkt_admins x join public.tkt_profiles q on q.user_id=x.user_id where x.user_id=p_actor and not q.blocked and q.deleted_at is null)then raise exception 'OWNER_REQUIRED';end if;
 if p_kind not in('user','exchange')or p_id is null then raise exception 'INVALID_TARGET';end if;
 if p_kind='exchange' then
  select *into a from tkt_private.exchange_agents where id=p_id;if not found then raise exception 'ACCOUNT_NOT_FOUND';end if;
  if a.user_id is not null then v_kind:='user';v_id:=a.user_id;else v_agent:=a.id;end if;
 end if;
 if v_kind='user'then
  v_user:=v_id;select *into p from public.tkt_profiles where user_id=v_user;if not found then raise exception 'ACCOUNT_NOT_FOUND';end if;
  select *into a from tkt_private.exchange_agents where user_id=v_user;v_agent:=a.id;
  v_type:=case when exists(select 1 from public.tkt_admins where user_id=v_user)then 'owner' when exists(select 1 from tkt_private.staff_accounts where user_id=v_user)then 'staff'when v_agent is not null then 'exchange'when p.captain then 'captain'else 'customer'end;
  v_name:=p.name;v_phone:=p.phone;
  select coalesce(balance,0)into v_balance from tkt_private.wallets where user_id=v_user;v_balance:=coalesce(v_balance,0);
  if exists(select 1 from public.tkt_rides where(rider_id=v_user or captain_id=v_user)and status in('pending','accepted','arrived','in_progress'))then blockers:=blockers||'"ACTIVE_RIDE"'::jsonb;end if;
  if exists(select 1 from tkt_private.lines where(customer_id=v_user or captain_id=v_user)and status in('pending','accepted'))then blockers:=blockers||'"ACTIVE_LINE"'::jsonb;end if;
  if v_balance<>0 then blockers:=blockers||'"SETTLE_BALANCE"'::jsonb;end if;
  if v_type='owner'and(select count(*)from public.tkt_admins x join public.tkt_profiles q on q.user_id=x.user_id where not q.blocked and q.deleted_at is null)<=1 then blockers:=blockers||'"LAST_OWNER"'::jsonb;end if;
 else v_type:='exchange';v_name:=a.name;v_phone:=a.phone;
 end if;
 select *into j from tkt_private.admin_account_deletions where target_kind=v_kind and target_id=v_id;
 if v_agent is not null then
  select *into a from tkt_private.exchange_agents where id=v_agent;
  select coalesce(sum(amount),0)into v_due from tkt_private.exchange_transactions where agent_id=v_agent and kind='subscription';
  v_due:=v_due-(select coalesce(sum(amount),0)from tkt_private.exchange_settlements where agent_id=v_agent);
  if a.balance<>0 or v_due<>0 then blockers:=blockers||'"SETTLE_EXCHANGE"'::jsonb;end if;
 end if;
 if p.deleted_at is not null or a.deleted_at is not null then
  if j.id is null then raise exception 'ACCOUNT_DELETED';end if;
 end if;
 return jsonb_build_object('kind',v_kind,'id',v_id,'user_id',v_user,'agent_id',v_agent,'name',v_name,'phone',v_phone,'account_type',coalesce(j.account_type,v_type),
 'balance',v_balance,'exchange_balance',coalesce(a.balance,0),'exchange_due',v_due,'blockers',blockers,'status',coalesce(j.status,'ready'),'self',v_user=p_actor,
 'fingerprint',encode(extensions.digest(v_kind||':'||v_id::text||':'||coalesce(v_name,'')||':'||coalesce(v_phone,'')||':'||v_type,'sha256'),'hex'));
end;$$;
revoke all on function tkt_private.admin_delete_preview(text,uuid,uuid) from public,anon,authenticated;
grant execute on function tkt_private.admin_delete_preview(text,uuid,uuid) to service_role;

create or replace function public.tkt_account_admin(p_action text,p_data jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();q text:=trim(coalesce(p_data->>'search',''));v_type text:=coalesce(p_data->>'type','all');
begin
 if u is null or not exists(select 1 from public.tkt_admins a join public.tkt_profiles p using(user_id)where a.user_id=u and not p.blocked and p.deleted_at is null)then raise exception 'OWNER_REQUIRED';end if;
 if p_action='preview'then return tkt_private.admin_delete_preview(p_data->>'kind',(p_data->>'id')::uuid,u);end if;
 if p_action='list'then
  return coalesce((select jsonb_agg(to_jsonb(x))from(
   select *from(
    select 'user'::text kind,p.user_id id,p.name,p.phone,p.blocked,coalesce(j.account_type,case when a.user_id is not null then 'owner'when s.user_id is not null then 'staff'when e.id is not null then 'exchange'when p.captain then 'captain'else 'customer'end)account_type,coalesce(j.status,'ready')deletion_status,p.created_at
    from public.tkt_profiles p left join public.tkt_admins a on a.user_id=p.user_id left join tkt_private.staff_accounts s on s.user_id=p.user_id left join tkt_private.exchange_agents e on e.user_id=p.user_id
    left join tkt_private.admin_account_deletions j on j.target_kind='user'and j.target_id=p.user_id
    where(p.deleted_at is null or j.status in('pending','purged'))and(j.status is distinct from 'completed')
    union all
    select 'exchange',e.id,e.name,e.phone,not e.active,'exchange',coalesce(j.status,'ready'),e.created_at
    from tkt_private.exchange_agents e left join tkt_private.admin_account_deletions j on j.target_kind='exchange'and j.target_id=e.id
    where e.user_id is null and(e.deleted_at is null or j.status in('pending','purged'))and j.status is distinct from 'completed'
   )z where(v_type='all'or z.account_type=v_type)and(q=''or z.name ilike '%'||q||'%'or z.phone ilike '%'||q||'%'or z.id::text=q)
   order by z.created_at desc limit 500
  )x),'[]'::jsonb);
 end if;
 raise exception 'UNKNOWN_ACTION';
end;$$;
revoke all on function public.tkt_account_admin(text,jsonb) from public,anon;
grant execute on function public.tkt_account_admin(text,jsonb) to authenticated;

create or replace function public.tkt_admin_account_delete(p_action text,p_data jsonb,p_actor uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare info jsonb;j tkt_private.admin_account_deletions;v_kind text:=p_data->>'kind';v_id uuid:=(p_data->>'id')::uuid;v_user uuid;v_agent uuid;files jsonb;old_job jsonb;
begin
 perform pg_advisory_xact_lock(74658291);
 if p_action='prepare'then
  info:=tkt_private.admin_delete_preview(v_kind,v_id,p_actor);v_kind:=info->>'kind';v_id:=(info->>'id')::uuid;v_user:=(info->>'user_id')::uuid;v_agent:=(info->>'agent_id')::uuid;
  select *into j from tkt_private.admin_account_deletions where target_kind=v_kind and target_id=v_id for update;
  if j.id is not null then return to_jsonb(j)||jsonb_build_object('user_id',v_user,'agent_id',v_agent,'self',v_user=p_actor);end if;
  if jsonb_array_length(info->'blockers')>0 then raise exception '%',info->'blockers'->>0;end if;
  if p_data->>'fingerprint' is distinct from info->>'fingerprint'then raise exception 'ACCOUNT_CHANGED';end if;
  if v_user is not null then
   perform 1 from public.tkt_profiles where user_id=v_user for update;
   delete from public.tkt_admins where user_id=v_user;
   delete from tkt_private.staff_accounts where user_id=v_user;
   delete from tkt_private.admin_login where user_id=v_user;
   old_job:=tkt_private.account_delete('prepare',v_user);
   select coalesce(jsonb_agg(jsonb_build_object('bucket',bucket_id,'name',name)),'[]')into files from storage.objects where bucket_id in('profile-photos','captain-documents','tkt-line-documents')and split_part(name,'/',1)=v_user::text;
   delete from tkt_private.password_links where user_id=v_user;
   update public.tkt_profiles set deleted_at=now() where user_id=v_user;
  else files:='[]';end if;
  if v_agent is not null then update tkt_private.exchange_agents set active=false where id=v_agent;delete from tkt_private.exchange_sessions where agent_id=v_agent;end if;
  insert into tkt_private.admin_account_deletions(target_kind,target_id,actor_id,account_type,files)values(v_kind,v_id,p_actor,info->>'account_type',files)returning *into j;
  insert into tkt_private.admin_audit(actor_id,action,entity_id,details)values(p_actor,'account_delete_prepare',v_id::text,jsonb_build_object('job_id',j.id,'kind',v_kind,'account_type',j.account_type));
  return to_jsonb(j)||jsonb_build_object('user_id',v_user,'agent_id',v_agent,'self',v_user=p_actor);
 end if;
 select *into j from tkt_private.admin_account_deletions where id=(p_data->>'job_id')::uuid for update;
 if not found then raise exception 'DELETE_NOT_PREPARED';end if;
 if p_actor is null or (p_actor<>j.actor_id and not exists(select 1 from public.tkt_admins a join public.tkt_profiles p using(user_id)where a.user_id=p_actor and not p.blocked and p.deleted_at is null))then raise exception 'OWNER_REQUIRED';end if;
 v_user:=case when j.target_kind='user'then j.target_id end;
 if j.target_kind='exchange'then v_agent:=j.target_id;else select id into v_agent from tkt_private.exchange_agents where user_id=v_user;end if;
 if p_action='purge'then
  if j.status<>'pending'then return to_jsonb(j);end if;
  if v_user is not null then
   perform tkt_private.account_delete('purge',v_user);
   update public.tkt_profiles set deleted_at=now()where user_id=v_user;
   delete from tkt_private.portal_members where user_id=v_user;
   delete from tkt_private.line_locations where user_id=v_user;
   update tkt_private.lines set passenger_name='حساب محذوف',front_path='',back_path='' where customer_id=v_user;
  end if;
  if v_agent is not null then
   delete from tkt_private.exchange_sessions where agent_id=v_agent;
   delete from tkt_private.exchange_messages where agent_id=v_agent;
   update tkt_private.exchange_agents set name='صيرفة محذوفة',phone='deleted-'||id::text,pin_hash='deleted',active=false,user_id=null,personal_name=null,personal_phone=null,province=null,area=null,street=null,lat=null,lng=null,accuracy_m=null,location_at=null,deleted_at=now()where id=v_agent;
  end if;
  update tkt_private.admin_account_deletions set status='purged',files='[]'where id=j.id returning *into j;
 elsif p_action='finish'then
  if j.status='pending'then raise exception 'DELETE_NOT_PURGED';end if;
  if v_user is not null then perform tkt_private.account_delete('finish',v_user);end if;
  update tkt_private.admin_account_deletions set status='completed',completed_at=coalesce(completed_at,now())where id=j.id returning *into j;
  insert into tkt_private.admin_audit(actor_id,action,entity_id,details)values(p_actor,'account_delete_completed',j.target_id::text,jsonb_build_object('job_id',j.id,'kind',j.target_kind,'account_type',j.account_type));
 else raise exception 'UNKNOWN_ACTION';end if;
 return to_jsonb(j);
end;$$;
revoke all on function public.tkt_admin_account_delete(text,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.tkt_admin_account_delete(text,jsonb,uuid) to service_role;

CREATE OR REPLACE FUNCTION tkt_private.authorize_manage(p_action text, p_data jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 if editing and target is not null and exists(select 1 from public.tkt_profiles where user_id=target and deleted_at is not null)then raise exception 'ACCOUNT_DELETED';end if;
 if p_action='restore'and kind='user'and exists(select 1 from public.tkt_profiles where user_id=(p_data->>'entity_id')::uuid and deleted_at is not null)then raise exception 'ACCOUNT_DELETED';end if;
 if editing and (exists(select 1 from tkt_private.staff_accounts where user_id=target)
 or (p_action in('archive','restore') and kind='user' and exists(select 1 from tkt_private.staff_accounts where user_id=(p_data->>'entity_id')::uuid))) then raise exception 'PROTECTED_ADMIN';end if;
end;$function$
;
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
   else disc:=case when c.reward_type='free_ride' then q.fare else least(q.fare,c.amount) end;end if;
  end if;
  due:=q.fare-disc;
  if p_data->>'payment_method'='wallet' then
   select balance into bal from tkt_private.wallets where user_id=u for update;
   if bal<due then raise exception 'INSUFFICIENT_BALANCE';end if;
  end if;
  res:=tkt_private.action('create',jsonb_build_object('quote_id',q.id));
  select * into r from public.tkt_rides where id=(res->>'id')::uuid;
  update public.tkt_rides set pickup_name=left(coalesce(p_data->>'pickup_name','موقع الانطلاق'),256),destination_name=left(coalesce(p_data->>'destination_name','الوجهة'),256),payment_method=coalesce(p_data->>'payment_method','cash'),discount=disc,customer_due=due,coupon_code=c.code,coupon_reward_type=coalesce(c.reward_type,'amount') where id=r.id returning * into r;
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
  return jsonb_build_object('wallets',coalesce((select jsonb_agg(to_jsonb(t)) from (select p.user_id,p.name,p.phone,p.captain,w.balance,pr.captain_requested_at from public.tkt_profiles p left join tkt_private.wallets w on w.user_id=p.user_id left join tkt_private.preferences pr on pr.user_id=p.user_id where p.deleted_at is null order by p.created_at desc limit 500)t),'[]'::jsonb),
   'coupons',coalesce((select jsonb_agg(to_jsonb(coupon_row)) from tkt_private.coupons coupon_row where coupon_row.batch_id is null),'[]'::jsonb),
   'rooms',coalesce((select jsonb_agg(to_jsonb(t)) from (select p.user_id,p.name,p.phone,max(m.created_at) as last_at,count(*) filter(where not m.is_admin and m.created_at>pr.admin_read) as unread from public.tkt_profiles p join public.tkt_messages m on m.user_id=p.user_id join tkt_private.preferences pr on pr.user_id=p.user_id group by p.user_id,pr.admin_read order by max(m.created_at) desc limit 500)t),'[]'::jsonb));
 elsif p_action in ('topup','settle') then
  if not adm then raise exception 'ADMIN_REQUIRED';end if;
  target:=(p_data->>'user_id')::uuid;ident:=(p_data->>'id')::uuid;value:=(p_data->>'amount')::integer;
  if ident is null or value is null or value not between 1 and 10000000 then raise exception 'INVALID_AMOUNT';end if;
  select captain into iscap from public.tkt_profiles where user_id=target and not blocked for update;
  if not found then raise exception 'PROFILE_REQUIRED';end if;
  if p_action='settle' and not iscap then raise exception 'CAPTAIN_REQUIRED';end if;
  if exists(select 1 from tkt_private.ledger where id=ident) then
   if not exists(select 1 from tkt_private.ledger where id=ident and user_id=target and actor_id=u and kind=p_action and amount=case when p_action='settle' then -value else value end) then raise exception 'REQUEST_CONFLICT';end if;
   return '{"ok":true}';
  end if;
  insert into tkt_private.wallets(user_id) values(target) on conflict do nothing;
  select balance into bal from tkt_private.wallets where user_id=target for update;
  if p_action='settle' and bal<value then raise exception 'INSUFFICIENT_BALANCE';end if;
  insert into tkt_private.ledger(id,user_id,amount,kind,actor_id) values(ident,target,case when p_action='settle' then -value else value end,p_action,u);
  update tkt_private.wallets set balance=balance+(case when p_action='settle' then -value else value end) where user_id=target;
 elsif p_action='coupon_admin' then
  if not adm then raise exception 'ADMIN_REQUIRED';end if;
  select * into c from tkt_private.coupons where code=upper(trim(p_data->>'code')) for update;
  if c.code is not null and exists(select 1 from tkt_private.coupon_history where code=c.code) and coalesce(p_data->>'reward_type',c.reward_type)<>c.reward_type then raise exception 'COUPON_TYPE_LOCKED';end if;
  if coalesce(p_data->>'reward_type',c.reward_type,'amount') not in ('amount','free_ride') then raise exception 'INVALID_COUPON_TYPE';end if;
  if (p_data->>'max_uses')::integer<(select count(*) from tkt_private.coupon_uses where code=c.code) then raise exception 'COUPON_USE_LIMIT';end if;
  insert into tkt_private.coupons(code,amount,expires_at,max_uses,active,reward_type) values(upper(trim(p_data->>'code')),case when coalesce(p_data->>'reward_type',c.reward_type,'amount')='free_ride' then 100000 else (p_data->>'amount')::integer end,(p_data->>'expires_at')::timestamptz,(p_data->>'max_uses')::integer,coalesce((p_data->>'active')::boolean,true),coalesce(p_data->>'reward_type',c.reward_type,'amount')) on conflict(code) do update set amount=excluded.amount,expires_at=excluded.expires_at,max_uses=excluded.max_uses,active=excluded.active,reward_type=excluded.reward_type;
 else raise exception 'UNKNOWN_ACTION';end if;
 return '{"ok":true}'::jsonb;
end $function$
;
CREATE OR REPLACE FUNCTION exchange_gateway.global_search(p_query text, p_kind text DEFAULT 'all'::text, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '8s'
AS $function$
declare q text:=trim(translate(coalesce(p_query,''),'٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹','01234567890123456789'));digits text;pattern text;result jsonb:='{}';offn integer:=greatest(0,least(coalesce(p_offset,0),10000));
begin
 if auth.uid()is null then raise exception 'AUTH_REQUIRED';end if;
 if not exists(select 1 from public.tkt_profiles p where p.user_id=auth.uid()and not p.blocked)or not(tkt_private.is_admin()or exists(select 1 from tkt_private.staff_accounts where user_id=auth.uid()and active))then raise exception 'PERMISSION_DENIED';end if;
 if length(q)<2 then return '{}'::jsonb;end if;
 if length(q)>100 or p_kind not in('all','users','rides','exchanges','lines')then raise exception 'INVALID_SEARCH';end if;
 digits:=regexp_replace(q,'[^0-9]','','g');if digits like '00964%'then digits:='0'||substr(digits,6);elsif digits like '964%'then digits:='0'||substr(digits,4);end if;
 pattern:='%'||replace(replace(replace(q,E'\\',E'\\\\'),'%',E'\\%'),'_',E'\\_')||'%';
 if p_kind in('all','users')and(tkt_private.dashboard_permission('users')or tkt_private.dashboard_permission('inventory'))then
 result:=result||jsonb_build_object('users',coalesce((select jsonb_agg(to_jsonb(x))from(select p.user_id,p.name,p.phone,p.captain,p.blocked,p.expires_at from public.tkt_profiles p where p.deleted_at is null and not exists(select 1 from tkt_private.staff_accounts where user_id=p.user_id)and not exists(select 1 from tkt_private.admin_archives where kind='user'and entity_id=p.user_id::text)and(p.name ilike pattern or p.user_id::text ilike pattern or(length(digits)>=3 and regexp_replace(regexp_replace(p.phone,'[^0-9]','','g'),'^964','0')like '%'||digits||'%'))order by case when p.phone=q then 0 when lower(p.name)=lower(q)then 1 else 2 end,p.created_at desc,p.user_id limit 21 offset offn)x),'[]'));
 end if;
 if p_kind in('all','rides')and(tkt_private.dashboard_permission('rides')or tkt_private.dashboard_permission('inventory'))then
 result:=result||jsonb_build_object('rides',coalesce((select jsonb_agg(to_jsonb(x))from(select r.id,r.status,r.pickup_name,r.destination_name,r.created_at,p.name rider_name,c.name captain_name from public.tkt_rides r left join public.tkt_profiles p on p.user_id=r.rider_id left join public.tkt_profiles c on c.user_id=r.captain_id where not exists(select 1 from tkt_private.admin_archives where kind='ride'and entity_id=r.id::text)and(r.id::text ilike pattern or r.pickup_name ilike pattern or r.destination_name ilike pattern or p.name ilike pattern or c.name ilike pattern or(length(digits)>=3 and(regexp_replace(regexp_replace(p.phone,'[^0-9]','','g'),'^964','0')like '%'||digits||'%'or regexp_replace(regexp_replace(c.phone,'[^0-9]','','g'),'^964','0')like '%'||digits||'%')))order by case when r.id::text=q then 0 else 1 end,r.created_at desc,r.id limit 21 offset offn)x),'[]'));
 end if;
 if p_kind in('all','exchanges')and tkt_private.is_admin()then
 result:=result||jsonb_build_object('exchanges',coalesce((select jsonb_agg(to_jsonb(x))from(select a.id,a.name,a.personal_name,a.phone,a.personal_phone,a.province,a.area,a.active from tkt_private.exchange_agents a where a.deleted_at is null and(a.name ilike pattern or a.personal_name ilike pattern or a.id::text ilike pattern or a.province ilike pattern or a.area ilike pattern or a.street ilike pattern or(length(digits)>=3 and(regexp_replace(regexp_replace(a.phone,'[^0-9]','','g'),'^964','0')like '%'||digits||'%'or regexp_replace(regexp_replace(a.personal_phone,'[^0-9]','','g'),'^964','0')like '%'||digits||'%')) )order by a.created_at desc,a.id limit 21 offset offn)x),'[]'));
 end if;
 if p_kind in('all','lines')and tkt_private.dashboard_permission('lines')then
 result:=result||jsonb_build_object('lines',coalesce((select jsonb_agg(to_jsonb(x))from(select l.id,l.passenger_name,l.pickup_name,l.destination_name,l.status,l.created_at from tkt_private.lines l left join public.tkt_profiles p on p.user_id=l.customer_id left join public.tkt_profiles c on c.user_id=l.captain_id where l.id::text ilike pattern or l.passenger_name ilike pattern or l.pickup_name ilike pattern or l.destination_name ilike pattern or p.name ilike pattern or c.name ilike pattern or(length(digits)>=3 and(regexp_replace(regexp_replace(p.phone,'[^0-9]','','g'),'^964','0')like '%'||digits||'%'or regexp_replace(regexp_replace(c.phone,'[^0-9]','','g'),'^964','0')like '%'||digits||'%'))order by l.created_at desc,l.id limit 21 offset offn)x),'[]'));
 end if;return result;
end $function$
;
CREATE OR REPLACE FUNCTION exchange_gateway.exchange_portal_before_settlements(p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a tkt_private.exchange_agents; c public.tkt_profiles; tx tkt_private.exchange_transactions; aid uuid; tid uuid; tok text; ph text; w integer; cost bigint; exp timestamptz; n integer; admin_mode boolean:=p_action like 'admin_%'; result jsonb;
begin

if p_action in ('account','register') then
 if auth.uid() is null then raise exception 'AUTH_REQUIRED';end if;
 select * into c from public.tkt_profiles where user_id=auth.uid() and not blocked;
 if not found then raise exception 'ACCOUNT_BLOCKED';end if;
 select * into a from tkt_private.exchange_agents where user_id=auth.uid();
 if p_action='account' then return jsonb_build_object('needs_registration',a.id is null,'personal_name',c.name,'personal_phone',c.phone);end if;
 if a.id is not null then return jsonb_build_object('ok',true,'agent_id',a.id);end if;
 ph:=tkt_private.normalize_phone(p_data->>'shop_phone');
 if ph is null then raise exception 'INVALID_SHOP_PHONE';end if;
 if tkt_private.normalize_phone(p_data->>'personal_phone') is null then raise exception 'INVALID_PERSONAL_PHONE';end if;
 if tkt_private.normalize_phone(p_data->>'personal_phone') is distinct from tkt_private.normalize_phone(c.phone) then raise exception 'PERSONAL_PHONE_MISMATCH';end if;
 if coalesce(length(trim(p_data->>'personal_name')),0) not between 5 and 100 or cardinality(regexp_split_to_array(trim(p_data->>'personal_name'),'[[:space:]]+'))<3 or coalesce(length(trim(p_data->>'shop_name')),0) not between 2 and 120 or coalesce(length(trim(p_data->>'area')),0) not between 2 and 120 or coalesce(length(trim(p_data->>'street')),0) not between 2 and 160 then raise exception 'INVALID_PROFILE';end if;
 if not coalesce(p_data->>'province'=any(array['بغداد','البصرة','نينوى','أربيل','السليمانية','دهوك','حلبجة','كركوك','ديالى','الأنبار','صلاح الدين','بابل','كربلاء','النجف','واسط','القادسية','ذي قار','ميسان','المثنى']),false) then raise exception 'INVALID_PROVINCE';end if;
 if p_data->>'lat' is null or p_data->>'lng' is null or (p_data->>'lat')::float8 not between 29 and 38 or (p_data->>'lng')::float8 not between 38 and 49 or coalesce((p_data->>'accuracy_m')::float8,0)<0 then raise exception 'LOCATION_REQUIRED';end if;
 insert into tkt_private.exchange_agents(name,phone,pin_hash,user_id,personal_name,personal_phone,province,area,street,lat,lng,accuracy_m,location_at)
 values(trim(p_data->>'shop_name'),ph,extensions.crypt(gen_random_uuid()::text,extensions.gen_salt('bf',12)),auth.uid(),trim(p_data->>'personal_name'),tkt_private.normalize_phone(c.phone),p_data->>'province',trim(p_data->>'area'),trim(p_data->>'street'),(p_data->>'lat')::float8,(p_data->>'lng')::float8,(p_data->>'accuracy_m')::float8,clock_timestamp()) returning id into aid;
 return jsonb_build_object('ok',true,'agent_id',aid);
end if;

if admin_mode then
 if auth.uid() is null or not tkt_private.is_admin() or not exists(select 1 from public.tkt_profiles where user_id=auth.uid() and not blocked) then raise exception 'ADMIN_REQUIRED';end if;
 aid:=nullif(p_data->>'agent_id','')::uuid;
 if aid is not null and exists(select 1 from tkt_private.exchange_agents where id=aid and deleted_at is not null)then raise exception 'ACCOUNT_DELETED';end if;

 if p_action='admin_overview' then
 return jsonb_build_object('total',(select count(*) from tkt_private.exchange_agents where deleted_at is null),'active',(select count(*) from tkt_private.exchange_agents where active and deleted_at is null),'total_balance',(select coalesce(sum(balance),0) from tkt_private.exchange_agents where deleted_at is null),'provinces',coalesce((select jsonb_agg(to_jsonb(x)) from(select coalesce(province,'غير محددة') as province,count(*) as count from tkt_private.exchange_agents where deleted_at is null group by province order by count(*) desc,province)x),'[]'));
 end if;
 if p_action='admin_profile' then
 select * into a from tkt_private.exchange_agents where id=aid;
 if not found then raise exception 'AGENT_REQUIRED';end if;
 return jsonb_build_object('profile',to_jsonb(a)-'pin_hash'-'failures'-'locked_until','summary',(select jsonb_build_object('transactions',count(*),'credits',coalesce(sum(amount)filter(where kind='credit'),0),'spent',coalesce(sum(amount)filter(where kind='subscription'),0),'activations',count(*)filter(where kind='subscription'),'accounts',count(distinct captain_id)filter(where kind='subscription'),'weeks',coalesce(sum(weeks)filter(where kind='subscription'),0)) from tkt_private.exchange_transactions where agent_id=aid));
 end if;
 if p_action='admin_accounts' then
 return coalesce((select jsonb_agg(to_jsonb(x)) from(select p.user_id,p.name,p.phone,p.expires_at,p.blocked,count(*) as activation_count,sum(t.weeks) as total_weeks,sum(t.amount) as total_amount,max(t.created_at) as last_activation from tkt_private.exchange_transactions t join public.tkt_profiles p on p.user_id=t.captain_id where t.agent_id=aid and t.kind='subscription' group by p.user_id order by max(t.created_at) desc,p.user_id limit 100 offset greatest(0,coalesce((p_data->>'offset')::integer,0)))x),'[]');
 end if;

 if p_action='admin_create' then
 ph:=tkt_private.normalize_phone(p_data->>'phone');
 if ph is null or coalesce(length(trim(p_data->>'name')),0) not between 2 and 100 or coalesce(length(p_data->>'pin'),0) not between 8 and 72 then raise exception 'INVALID_DETAILS';end if;
 insert into tkt_private.exchange_agents(name,phone,pin_hash) values(trim(p_data->>'name'),ph,extensions.crypt(p_data->>'pin',extensions.gen_salt('bf',12))) returning id into aid;
 elsif p_action='admin_credit' then
 tid:=(p_data->>'id')::uuid;cost:=(p_data->>'amount')::bigint;
 if tid is null or cost is null or cost not between 1 and 100000000 then raise exception 'INVALID_AMOUNT';end if;
 select * into a from tkt_private.exchange_agents where id=aid for update;if not found then raise exception 'AGENT_REQUIRED';end if;
 select * into tx from tkt_private.exchange_transactions where id=tid;
 if found then if tx.agent_id<>aid or tx.kind<>'credit' or tx.amount<>cost then raise exception 'REQUEST_CONFLICT';end if;return to_jsonb(tx);end if;
 update tkt_private.exchange_agents set balance=balance+cost where id=aid returning * into a;
 insert into tkt_private.exchange_transactions(id,agent_id,kind,amount,balance_after,actor_id)values(tid,aid,'credit',cost,a.balance,auth.uid());
 elsif p_action='admin_toggle' then
 update tkt_private.exchange_agents set active=(p_data->>'active')::boolean where id=aid;
 delete from tkt_private.exchange_sessions where agent_id=aid;
 elsif p_action='admin_reset' then
 if exists(select 1 from tkt_private.exchange_agents where id=aid and user_id is not null) then raise exception 'NATIVE_PASSWORD_RESET';end if;
 if coalesce(length(p_data->>'pin'),0) not between 8 and 72 then raise exception 'INVALID_DETAILS';end if;
 update tkt_private.exchange_agents set pin_hash=extensions.crypt(p_data->>'pin',extensions.gen_salt('bf',12)),failures=0,locked_until=null where id=aid;
 delete from tkt_private.exchange_sessions where agent_id=aid;
 elsif p_action not in ('admin_list','admin_transactions','admin_messages','admin_send') then raise exception 'UNKNOWN_ACTION';end if;
 if p_action in ('admin_create','admin_credit','admin_toggle','admin_reset') then
 insert into tkt_private.admin_audit(actor_id,action,entity_id,details)values(auth.uid(),p_action,aid::text,p_data-'pin');
 return jsonb_build_object('ok',true,'agent_id',aid);
 end if;
 if p_action='admin_list' then return coalesce((select jsonb_agg(to_jsonb(x))from(select id,name,phone,balance,active,created_at,personal_name,personal_phone,province,area,street,user_id from tkt_private.exchange_agents where deleted_at is null order by created_at desc)x),'[]');end if;
else
 if p_action='login' then
 ph:=tkt_private.normalize_phone(p_data->>'phone');
 select * into a from tkt_private.exchange_agents where phone=ph for update;
 if not found or not a.active then return '{"error":"LOGIN_FAILED"}';end if;
 if a.locked_until>now() then return '{"error":"LOGIN_LOCKED"}';end if;
 if a.locked_until is not null then a.failures:=0;end if;
 if coalesce(length(p_data->>'pin'),0) not between 8 and 72 or extensions.crypt(p_data->>'pin',a.pin_hash) is distinct from a.pin_hash then
 update tkt_private.exchange_agents set failures=a.failures+1,locked_until=case when a.failures+1>=5 then now()+interval '15 minutes' else null end where id=a.id;
 return '{"error":"LOGIN_FAILED"}';end if;
 update tkt_private.exchange_agents set failures=0,locked_until=null where id=a.id;
 tok:=encode(extensions.gen_random_bytes(32),'hex');
 delete from tkt_private.exchange_sessions where expires_at<now();
 insert into tkt_private.exchange_sessions values(encode(extensions.digest(tok,'sha256'),'hex'),a.id,now()+interval '12 hours');
 return jsonb_build_object('token',tok);
 end if;
 select id into aid from tkt_private.exchange_agents where user_id=auth.uid();
 if aid is null then select agent_id into aid from tkt_private.exchange_sessions where token_hash=encode(extensions.digest(coalesce(p_data->>'token',''),'sha256'),'hex') and expires_at>now();end if;
 select * into a from tkt_private.exchange_agents where id=aid and active for update;
 if not found then raise exception 'SESSION_EXPIRED';end if;
 if a.user_id is not null and not exists(select 1 from public.tkt_profiles where user_id=a.user_id and not blocked) then raise exception 'ACCOUNT_BLOCKED';end if;
 if p_action='logout' then delete from tkt_private.exchange_sessions where token_hash=encode(extensions.digest(p_data->>'token','sha256'),'hex');return '{"ok":true}';end if;
 if p_action='me' then return jsonb_build_object('id',a.id,'name',a.name,'phone',a.phone,'balance',a.balance,'weekly_price',5000);end if;
 if p_action in ('lookup','activate') then
 ph:=tkt_private.normalize_phone(p_data->>'phone');if ph is null then raise exception 'INVALID_PHONE';end if;
 select count(*) into n from public.tkt_profiles where tkt_private.normalize_phone(phone)=ph and captain and not blocked;
 if n<>1 then raise exception 'CAPTAIN_NOT_FOUND';end if;
 select * into c from public.tkt_profiles where tkt_private.normalize_phone(phone)=ph and captain and not blocked for update;
 if p_action='lookup' then return jsonb_build_object('id',c.user_id,'name',c.name,'phone',c.phone,'expires_at',c.expires_at);end if;
 w:=(p_data->>'weeks')::integer;tid:=(p_data->>'id')::uuid;
 if w is null or w not between 1 and 52 or tid is null then raise exception 'INVALID_WEEKS';end if;
 if (p_data->>'captain_id')::uuid is distinct from c.user_id then raise exception 'REQUEST_CONFLICT';end if;
 select * into tx from tkt_private.exchange_transactions where id=tid;
 if found then if tx.agent_id<>aid or tx.captain_id<>c.user_id or tx.weeks<>w or tx.kind<>'subscription' then raise exception 'REQUEST_CONFLICT';end if;return to_jsonb(tx);end if;
 cost:=5000*w;
 if a.balance<cost then raise exception 'INSUFFICIENT_BALANCE';end if;
 exp:=greatest(coalesce(c.expires_at,now()),now())+make_interval(days=>7*w);
 update tkt_private.exchange_agents set balance=balance-cost where id=aid returning balance into a.balance;
 update public.tkt_profiles set expires_at=exp where user_id=c.user_id;
 insert into tkt_private.exchange_transactions(id,agent_id,kind,amount,balance_after,captain_id,weeks,expires_at)values(tid,aid,'subscription',cost,a.balance,c.user_id,w,exp) returning * into tx;
 perform tkt_private.notification_add(c.user_id,'exchange:'||tid,'subscription','تم تفعيل اشتراكك','تمت إضافة '||w||' أسبوع إلى اشتراكك في تكتوكة.',jsonb_build_object('expires_at',exp));
 return to_jsonb(tx);
 end if;
 if p_action not in ('transactions','messages','send') then raise exception 'UNKNOWN_ACTION';end if;
end if;
if p_action in ('transactions','admin_transactions') then
 return coalesce((select jsonb_agg(to_jsonb(x))from(select t.*,p.name as captain_name,p.phone as captain_phone from tkt_private.exchange_transactions t left join public.tkt_profiles p on p.user_id=t.captain_id where t.agent_id=aid and (nullif(p_data->>'captain_id','') is null or t.captain_id=(p_data->>'captain_id')::uuid) order by t.created_at desc,t.id desc limit 100 offset greatest(0,coalesce((p_data->>'offset')::integer,0)))x),'[]');
end if;
if p_action in ('send','admin_send') then
 if coalesce(length(trim(p_data->>'body')),0) not between 1 and 2000 then raise exception 'INVALID_MESSAGE';end if;
 tid:=(p_data->>'id')::uuid;if tid is null then raise exception 'INVALID_DETAILS';end if;
 insert into tkt_private.exchange_messages(id,agent_id,body,is_admin)values(tid,aid,trim(p_data->>'body'),admin_mode)on conflict(id)do nothing;
end if;
return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at)from(select id,body,is_admin,created_at from tkt_private.exchange_messages where agent_id=aid order by created_at desc limit 300)x),'[]');
end$function$
;
CREATE OR REPLACE VIEW tkt_private.inventory_people AS  SELECT p.user_id,
    p.name,
    p.phone,
    p.captain,
    p.blocked,
    p.expires_at,
    p.online,
    p.lat,
    p.lng,
    p.location_at,
    p.created_at,
    p.avatar_path,
    p.privacy_version,
    p.privacy_accepted_at,
    p.gender,
    COALESCE(w.balance, 0) AS balance,
    a.status AS application_status,
    a.full_name,
    a.chassis,
    a.color,
    a.model,
    a.province,
    a.area,
    a.reason,
    a.submitted_at,
    p.captain OR COALESCE(a.status = 'approved'::text, false) AS vehicle,
        CASE
            WHEN p.expires_at IS NULL THEN 'never'::text
            WHEN p.expires_at > now() THEN 'active'::text
            ELSE 'expired'::text
        END AS subscription_state,
    (EXISTS ( SELECT 1
           FROM tkt_private.admin_archives ar
          WHERE ar.kind = 'user'::text AND ar.entity_id = p.user_id::text)) AS archived
   FROM tkt_profiles p
     LEFT JOIN tkt_private.wallets w ON w.user_id = p.user_id
     LEFT JOIN tkt_captain_applications a ON a.user_id = p.user_id
  WHERE p.deleted_at IS NULL AND NOT (EXISTS ( SELECT 1
           FROM tkt_admins
          WHERE tkt_admins.user_id = p.user_id)) AND NOT (EXISTS ( SELECT 1
           FROM tkt_private.staff_accounts
          WHERE staff_accounts.user_id = p.user_id));;
