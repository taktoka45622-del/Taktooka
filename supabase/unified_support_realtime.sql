
create table if not exists tkt_private.exchange_support_reads(
 actor_id uuid not null references auth.users(id) on delete cascade,
 agent_id uuid not null references tkt_private.exchange_agents(id) on delete cascade,
 read_at timestamptz not null,
 primary key(actor_id,agent_id)
);
alter table tkt_private.exchange_support_reads enable row level security;
revoke all on tkt_private.exchange_support_reads from public,anon,authenticated;

create or replace function exchange_gateway.support_portal(p_action text,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare aid uuid;ident uuid;result jsonb;seen timestamptz;
begin
 perform tkt_private.require_dashboard('support',p_action='send');
 if p_action='rooms' then
 return coalesce((select jsonb_agg(to_jsonb(x) order by x.last_at desc,x.id) from(
 select a.id,a.name,a.personal_name,a.phone,a.user_id,max(m.created_at) last_at,
 count(*)filter(where not m.is_admin and m.created_at>coalesce(r.read_at,'-infinity'::timestamptz)) unread
 from tkt_private.exchange_agents a join tkt_private.exchange_messages m on m.agent_id=a.id
 left join tkt_private.exchange_support_reads r on r.agent_id=a.id and r.actor_id=auth.uid()
 group by a.id,r.read_at)x),'[]'::jsonb);
 end if;
 aid:=nullif(p_data->>'agent_id','')::uuid;
 if not exists(select 1 from tkt_private.exchange_agents where id=aid) then raise exception 'AGENT_REQUIRED';end if;
 if p_action='send' then
 ident:=nullif(p_data->>'id','')::uuid;
 if ident is null or coalesce(length(trim(p_data->>'body')),0) not between 1 and 2000 then raise exception 'INVALID_MESSAGE';end if;
 if exists(select 1 from tkt_private.exchange_messages where id=ident and (agent_id<>aid or not is_admin or body<>trim(p_data->>'body'))) then raise exception 'REQUEST_CONFLICT';end if;
 insert into tkt_private.exchange_messages(id,agent_id,body,is_admin)values(ident,aid,trim(p_data->>'body'),true)on conflict(id)do nothing;
 elsif p_action<>'read' then raise exception 'UNKNOWN_ACTION';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at,x.id),'[]'::jsonb),max(x.created_at) into result,seen from(select id,body,is_admin,created_at from tkt_private.exchange_messages where agent_id=aid order by created_at desc,id desc limit 300)x;
 if seen is not null then insert into tkt_private.exchange_support_reads values(auth.uid(),aid,seen)on conflict(actor_id,agent_id)do update set read_at=greatest(exchange_support_reads.read_at,excluded.read_at);end if;
 return result;
end $fn$;
revoke all on function exchange_gateway.support_portal(text,jsonb) from public,anon;
grant execute on function exchange_gateway.support_portal(text,jsonb) to authenticated;
create or replace function public.tkt_support(p_action text,p_data jsonb default '{}'::jsonb)returns jsonb language sql security invoker set search_path='' as $fn$select exchange_gateway.support_portal(p_action,p_data)$fn$;
revoke all on function public.tkt_support(text,jsonb) from public,anon;
grant execute on function public.tkt_support(text,jsonb) to authenticated;

create or replace function exchange_gateway.realtime_allowed(topic text) returns boolean language sql stable security definer set search_path='' as $fn$
select auth.uid() is not null and exists(select 1 from public.tkt_profiles where user_id=auth.uid() and not blocked) and (
(topic='tkt:dashboard' and (exists(select 1 from public.tkt_admins where user_id=auth.uid()) or exists(select 1 from tkt_private.staff_accounts where user_id=auth.uid() and active)))
or exists(select 1 from tkt_private.exchange_agents where user_id=auth.uid() and active and topic='tkt:agent:'||id::text));
$fn$;
revoke all on function exchange_gateway.realtime_allowed(text) from public,anon;
grant execute on function exchange_gateway.realtime_allowed(text) to authenticated;
drop policy if exists tkt_live_receive on realtime.messages;
create policy tkt_live_receive on realtime.messages for select to authenticated using (extension='broadcast' and exchange_gateway.realtime_allowed(realtime.topic()));

create or replace function tkt_private.broadcast_dashboard_change()returns trigger language plpgsql security definer set search_path='' as $fn$
begin perform realtime.send(jsonb_build_object('resource',tg_table_name),'invalidate','tkt:dashboard',true);return null;end $fn$;
revoke all on function tkt_private.broadcast_dashboard_change() from public,anon,authenticated;
create or replace function tkt_private.broadcast_agent_change()returns trigger language plpgsql security definer set search_path='' as $fn$
declare aid uuid;old_aid uuid;
begin
 if tg_table_name='exchange_agents' then aid:=case when tg_op='DELETE' then old.id else new.id end;
 else aid:=case when tg_op='DELETE' then old.agent_id else new.agent_id end;end if;
 perform realtime.send(jsonb_build_object('resource',tg_table_name),'invalidate','tkt:agent:'||aid::text,true);return null;
end $fn$;
revoke all on function tkt_private.broadcast_agent_change() from public,anon,authenticated;
do $triggers$declare r record;begin
 for r in select schemaname,tablename from pg_tables where
 (schemaname='public' and tablename in('tkt_profiles','tkt_rides','tkt_payments','tkt_messages','tkt_recovery_messages','tkt_recovery_threads','tkt_captain_applications','tkt_home_banners','tkt_saved_places','tkt_admins'))
 or(schemaname='tkt_private' and tablename in('exchange_agents','exchange_messages','exchange_settlements','exchange_transactions','lines','line_runs','line_locations','wallets','ledger','coupons','coupon_uses','coupon_history','coupon_card_batches','coupon_captain_rewards','company_expenses','pricing_settings','booking_prices','dispatch_settings','preferences','ride_emergencies','admin_archives','admin_audit','staff_accounts','wheel_prizes','wheel_settings','wheel_spins','portal_settings','portal_members'))
 loop execute format('drop trigger if exists tkt_live_dashboard on %I.%I',r.schemaname,r.tablename);
 execute format('create trigger tkt_live_dashboard after insert or update or delete on %I.%I for each statement execute function tkt_private.broadcast_dashboard_change()',r.schemaname,r.tablename);end loop;
 for r in select tablename from pg_tables where schemaname='tkt_private' and tablename in('exchange_agents','exchange_messages','exchange_settlements','exchange_transactions')
 loop execute format('drop trigger if exists tkt_live_agent on tkt_private.%I',r.tablename);execute format('create trigger tkt_live_agent after insert or update or delete on tkt_private.%I for each row execute function tkt_private.broadcast_agent_change()',r.tablename);end loop;
end $triggers$;

create or replace function tkt_private.broadcast_dashboard_change()returns trigger language plpgsql security definer set search_path='' as $fn$
begin
 if tg_table_name='preferences' and tg_op='UPDATE' then
 if (to_jsonb(new)-'admin_read'-'user_read')=(to_jsonb(old)-'admin_read'-'user_read') then return null;end if;
 end if;
 perform realtime.send(jsonb_build_object('resource',tg_table_name),'invalidate','tkt:dashboard',true);return null;
end $fn$;
drop trigger if exists tkt_live_dashboard on tkt_private.preferences;
create trigger tkt_live_dashboard after insert or update or delete on tkt_private.preferences for each row execute function tkt_private.broadcast_dashboard_change();

create or replace function tkt_private.exchange_support_notice()returns trigger language plpgsql security definer set search_path='' as $fn$
declare target uuid;shop text;
begin
 if new.is_admin then return new;end if;
 select name into shop from tkt_private.exchange_agents where id=new.agent_id;
 for target in
 select a.user_id from public.tkt_admins a join public.tkt_profiles p on p.user_id=a.user_id where not p.blocked
 union select s.user_id from tkt_private.staff_accounts s join public.tkt_profiles p on p.user_id=s.user_id where s.active and not p.blocked and s.permissions->'support'->>'view'='true'
 loop
 perform tkt_private.notification_add(target,'exchange-support:'||new.id::text,'support','رسالة من صيرفة '||shop,left(new.body,160),jsonb_build_object('screen','exchange_support','agent_id',new.agent_id));
 end loop;
 return new;
end $fn$;
revoke all on function tkt_private.exchange_support_notice() from public,anon,authenticated;
drop trigger if exists tkt_exchange_support_notice on tkt_private.exchange_messages;
create trigger tkt_exchange_support_notice after insert on tkt_private.exchange_messages for each row execute function tkt_private.exchange_support_notice();

drop trigger if exists tkt_live_dashboard on tkt_private.wallets;
create trigger tkt_live_dashboard after insert or update or delete on tkt_private.wallets for each row execute function tkt_private.broadcast_dashboard_change();
