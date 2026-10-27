begin;
create table if not exists tkt_private.pricing_settings (
 id boolean primary key default true check(id),
 tiers jsonb not null,
 night_amount integer not null default 500,
 night_min_m integer not null default 1200,
 night_start integer not null default 21,
 night_end integer not null default 6,
 overflow_step_m integer not null default 3000,
 overflow_amount integer not null default 500,
 max_fare integer not null default 0,
 revision integer not null default 1,
 updated_at timestamptz not null default now(),
 updated_by uuid
);
alter table tkt_private.pricing_settings enable row level security;
revoke all on tkt_private.pricing_settings from public,anon,authenticated;
insert into tkt_private.pricing_settings(id,tiers) values(true,'[{"up_to_m":500,"fare":500},{"up_to_m":800,"fare":1000},{"up_to_m":1200,"fare":1500},{"up_to_m":2500,"fare":2000},{"up_to_m":3800,"fare":3000},{"up_to_m":4250,"fare":3500},{"up_to_m":5250,"fare":4000},{"up_to_m":6000,"fare":4250},{"up_to_m":7000,"fare":5000},{"up_to_m":10000,"fare":2500}]') on conflict(id) do nothing;
create or replace function tkt_private.fare(p_m numeric,p_at timestamptz) returns jsonb language plpgsql stable set search_path='' as $$
declare c tkt_private.pricing_settings; t jsonb; base integer; night integer; h integer; last_m integer; last_f integer;
begin
 if p_m is null or p_m<=0 or p_m>2147483647 or p_m='NaN'::numeric or p_at is null then raise exception 'ROUTE_UNAVAILABLE';end if;
 select * into strict c from tkt_private.pricing_settings where id;
 for t in select value from jsonb_array_elements(c.tiers) loop
  last_m:=(t->>'up_to_m')::integer;last_f:=(t->>'fare')::integer;
  if p_m<=last_m then base:=last_f;exit;end if;
 end loop;
 if base is null then base:=least(1000000::numeric,last_f::numeric+c.overflow_amount*ceil((p_m-last_m)/c.overflow_step_m))::integer;end if;
 h:=extract(hour from p_at at time zone 'Asia/Baghdad');
 night:=case when p_m>=c.night_min_m and ((c.night_start<c.night_end and h>=c.night_start and h<c.night_end) or (c.night_start>c.night_end and (h>=c.night_start or h<c.night_end))) then c.night_amount else 0 end;
 if c.max_fare>0 then base:=least(base,c.max_fare);night:=least(night,greatest(0,c.max_fare-base));end if;
 return jsonb_build_object('base_fare',base,'night_surcharge',night,'fare',base+night,'priced_at',p_at,'pricing_version','iqd-distance-v2');
end $$;
create or replace function tkt_private.pricing_admin(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare c tkt_private.pricing_settings;t jsonb;prev integer:=0;u uuid:=auth.uid();
begin
 if u is null or not tkt_private.is_admin() or not exists(select 1 from public.tkt_profiles where user_id=u and not blocked) then raise exception 'ADMIN_REQUIRED';end if;
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
end $$;
revoke all on function tkt_private.pricing_admin(text,jsonb) from public,anon;
grant execute on function tkt_private.pricing_admin(text,jsonb) to authenticated;
create or replace function public.tkt_pricing(p_action text default 'get',p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select tkt_private.pricing_admin(p_action,p_data)$$;
revoke all on function public.tkt_pricing(text,jsonb) from public,anon;
grant execute on function public.tkt_pricing(text,jsonb) to authenticated;
commit;
