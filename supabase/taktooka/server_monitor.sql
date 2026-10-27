create table if not exists tkt_private.server_monitor_provider (
 id boolean primary key default true check(id),
 snapshot jsonb not null default '{}', updated_at timestamptz not null default now()
);
alter table tkt_private.server_monitor_provider enable row level security;
revoke all on tkt_private.server_monitor_provider from public,anon,authenticated;
insert into tkt_private.server_monitor_provider(id,snapshot) values(true,jsonb_build_object('plan','free','verified_at',now())) on conflict do nothing;
create or replace function public.tkt_server_monitor(p_action text default 'read',p_data jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare s jsonb; v jsonb; k text;
begin
 if auth.uid() is null or not exists(select 1 from public.tkt_admins a join public.tkt_profiles p on p.user_id=a.user_id where a.user_id=auth.uid() and not p.blocked and p.deleted_at is null) then raise exception 'OWNER_REQUIRED';end if;
 if p_action='save_provider' then
  if p_data->>'plan' not in ('free','pro','team','custom') or p_data->>'plan' is null then raise exception 'INVALID_PLAN';end if;
  foreach k in array array['egress','cached_egress','edge','realtime','peak','mau','map_users','amount_usd'] loop
   if p_data->>k is not null and ((p_data->>k)::numeric<0 or (p_data->>k)::numeric>1e15) then raise exception 'INVALID_VALUE';end if;
  end loop;
  if p_data->>'period_end' is not null and p_data->>'period_start' is not null and (p_data->>'period_end')::timestamptz <= (p_data->>'period_start')::timestamptz then raise exception 'INVALID_PERIOD';end if;
  s:=jsonb_build_object('plan',p_data->>'plan','period_start',p_data->>'period_start','period_end',p_data->>'period_end','egress',p_data->'egress','cached_egress',p_data->'cached_egress','edge',p_data->'edge','realtime',p_data->'realtime','peak',p_data->'peak','mau',p_data->'mau','map_users',p_data->'map_users','amount_usd',p_data->'amount_usd','verified_at',now());
  update tkt_private.server_monitor_provider set snapshot=s,updated_at=now() where id;
 elsif p_action<>'read' then raise exception 'INVALID_ACTION';end if;
 select snapshot into s from tkt_private.server_monitor_provider where id;
 select jsonb_build_object(
 'database_bytes',pg_catalog.pg_database_size(current_database()),
 'storage_bytes',(select coalesce(sum(case when metadata->>'size' ~ '^[0-9]+$' then (metadata->>'size')::numeric else 0 end),0) from storage.objects),
 'storage_objects',(select count(*) from storage.objects),
 'database_connections',(select count(*) from pg_catalog.pg_stat_activity where datname=current_database() and backend_type='client backend'),
 'database_connection_limit',current_setting('max_connections')::int,
 'tracking_fresh',(select count(*) from public.tkt_profiles where captain and online and not blocked and deleted_at is null and location_at>now()-interval '2 minutes'),
 'tracking_stale',(select count(*) from public.tkt_profiles where captain and online and not blocked and deleted_at is null and (location_at is null or location_at<=now()-interval '2 minutes')),
 'rides_active',(select count(*) from public.tkt_rides where status in ('accepted','arrived','in_progress')),
 'rides_searching',(select count(*) from public.tkt_rides where status='pending'),
 'offers_pending',(select count(*) from public.tkt_offers where status='pending' and expires_at>now()),
 'dispatch_worker_at',(select last_worker_at from tkt_private.dispatch_settings where id),
 'dispatch_has_error',(select coalesce(last_error<>'',false) from tkt_private.dispatch_settings where id),
 'push_pending',(select count(*) from tkt_private.push_outbox where status='pending'),
 'push_failed',(select count(*) from tkt_private.push_outbox where status='failed'),
 'push_sent_24h',(select count(*) from tkt_private.push_outbox where status='sent' and delivered_at>now()-interval '24 hours'),
 'notifications_24h',(select count(*) from public.tkt_notifications where created_at>now()-interval '24 hours')
 ) into v;
 return jsonb_build_object('at',now(),'provider',s,'live',v);
end;$$;
revoke all on function public.tkt_server_monitor(text,jsonb) from public,anon;
grant execute on function public.tkt_server_monitor(text,jsonb) to authenticated;
