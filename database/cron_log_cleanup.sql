begin;
create table if not exists tkt_private.log_cleanup_settings (
 id boolean primary key default true check(id),
 enabled boolean not null default false,
 retention_days integer not null default 7 check(retention_days between 1 and 90),
 last_run_at timestamptz,
 last_deleted integer not null default 0,
 total_deleted bigint not null default 0
);
alter table tkt_private.log_cleanup_settings enable row level security;
revoke all on tkt_private.log_cleanup_settings from public,anon,authenticated;
insert into tkt_private.log_cleanup_settings(id) values(true) on conflict do nothing;

create or replace function tkt_private.cleanup_cron_logs(p_manual boolean default false)
returns integer language plpgsql security definer set search_path='' set lock_timeout='1s' as $$
declare s tkt_private.log_cleanup_settings; removed integer;
begin
 if not pg_catalog.pg_try_advisory_xact_lock(740113,17) then raise exception 'CLEANUP_BUSY'; end if;
 select * into s from tkt_private.log_cleanup_settings where id for update;
 if not p_manual and not s.enabled then return 0; end if;
 with old_runs as (
  select runid from cron.job_run_details
  where end_time < now()-pg_catalog.make_interval(days=>s.retention_days)
  and status in ('succeeded','failed')
  order by runid limit 20000
  for update skip locked
 )
 delete from cron.job_run_details d using old_runs r where d.runid=r.runid;
 get diagnostics removed=row_count;
 update tkt_private.log_cleanup_settings set last_run_at=now(),last_deleted=removed,total_deleted=total_deleted+removed where id;
 return removed;
end;$$;
revoke all on function tkt_private.cleanup_cron_logs(boolean) from public,anon,authenticated;

create or replace function tkt_private.manage_log_cleanup(p_action text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' set statement_timeout='15s' as $$
declare result jsonb;
begin
 if auth.uid() is null or not exists(select 1 from public.tkt_admins a join public.tkt_profiles p on p.user_id=a.user_id where a.user_id=auth.uid() and not p.blocked and p.deleted_at is null) then raise exception 'OWNER_REQUIRED';end if;
 if p_action='configure' then
  if jsonb_typeof(p_data->'enabled') is distinct from 'boolean' then raise exception 'INVALID_SETTINGS';end if;
  update tkt_private.log_cleanup_settings set enabled=(p_data->>'enabled')::boolean where id;
 elsif p_action='clean' then
  perform tkt_private.cleanup_cron_logs(true);
 elsif p_action<>'read' then raise exception 'INVALID_ACTION';end if;
 select jsonb_build_object('enabled',enabled,'retention_days',retention_days,'last_run_at',last_run_at,'last_deleted',last_deleted,'total_deleted',total_deleted,'log_bytes',pg_catalog.pg_total_relation_size('cron.job_run_details'::regclass),'batch_limit',20000) into result from tkt_private.log_cleanup_settings where id;
 return result;
end;$$;
revoke all on function tkt_private.manage_log_cleanup(text,jsonb) from public,anon;
grant execute on function tkt_private.manage_log_cleanup(text,jsonb) to authenticated;

create or replace function public.tkt_log_cleanup(p_action text default 'read',p_data jsonb default '{}'::jsonb)
returns jsonb language sql security invoker set search_path='' as $$
 select tkt_private.manage_log_cleanup(p_action,p_data);
$$;
revoke all on function public.tkt_log_cleanup(text,jsonb) from public,anon;
grant execute on function public.tkt_log_cleanup(text,jsonb) to authenticated;
select cron.schedule('tkt-cleanup-cron-logs','17 * * * *','select tkt_private.cleanup_cron_logs()');
commit;
