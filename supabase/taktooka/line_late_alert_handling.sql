
alter table tkt_private.line_runs add column if not exists departure_handled_at timestamptz;
alter table tkt_private.line_runs add column if not exists departure_handled_by uuid;
alter table tkt_private.line_runs add column if not exists arrival_handled_at timestamptz;
alter table tkt_private.line_runs add column if not exists arrival_handled_by uuid;

create or replace function tkt_private.line_progress(p_line uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
 'completed_days',count(*)filter(where state='completed'),
 'missed_days',count(*)filter(where state='missed'),
 'remaining_days',count(*)filter(where state not in('completed','missed')),
 'late_days',count(*)filter(where late_at is not null or completed_at>arrival_at+interval '5 minutes'),
 'unresolved_late',count(*)filter(where
 (state in('scheduled','heading','arrived') and departure_at+interval '5 minutes'<=now() and departure_handled_at is null)
 or (state='picked_up' and arrival_at+interval '5 minutes'<=now() and arrival_handled_at is null)))
 from tkt_private.line_runs where line_id=p_line;
$$;

create or replace function tkt_private.line_alert_action(p_action text,p_data jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare r tkt_private.line_runs%rowtype; stage text:=p_data->>'stage';
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 perform tkt_private.require_dashboard('lines',p_action='resolve');
 if p_action='resolve' then
  if stage is null or stage not in('departure','arrival') then raise exception 'INVALID_STAGE';end if;
  select x.* into r from tkt_private.line_runs x join tkt_private.lines l on l.id=x.line_id
   where x.id=(p_data->>'run_id')::uuid and l.status='accepted' for update of x;
  if not found then raise exception 'LINE_UNAVAILABLE';end if;
  if stage='departure' and r.departure_handled_at is null then
   if r.state not in('scheduled','heading','arrived') or r.departure_at+interval '5 minutes'>now() then raise exception 'ALERT_NO_LONGER_OPEN';end if;
   update tkt_private.line_runs set departure_handled_at=now(),departure_handled_by=auth.uid() where id=r.id;
  elsif stage='arrival' and r.arrival_handled_at is null then
   if r.state<>'picked_up' or r.arrival_at+interval '5 minutes'>now() then raise exception 'ALERT_NO_LONGER_OPEN';end if;
   update tkt_private.line_runs set arrival_handled_at=now(),arrival_handled_by=auth.uid() where id=r.id;
  end if;
  return jsonb_build_object('resolved',true,'run_id',r.id,'stage',stage);
 elsif p_action='list' then
  return coalesce((select jsonb_agg(j order by due_at) from (
   select jsonb_build_object('id',x.id::text||':'||case when x.state='picked_up' then 'arrival' else 'departure' end,
    'run_id',x.id,'line_id',l.id,'stage',case when x.state='picked_up' then 'arrival' else 'departure' end,
    'service_date',x.service_date,'due_at',case when x.state='picked_up' then x.arrival_at else x.departure_at end,
    'state',x.state,'passenger_name',l.passenger_name,'pickup_name',l.pickup_name,'destination_name',l.destination_name,
    'captain_name',c.name,'captain_phone',c.phone,'customer_name',p.name,'customer_phone',p.phone) j,
    case when x.state='picked_up' then x.arrival_at else x.departure_at end due_at
   from tkt_private.line_runs x join tkt_private.lines l on l.id=x.line_id
   join public.tkt_profiles p on p.user_id=l.customer_id left join public.tkt_profiles c on c.user_id=l.captain_id
   where l.status='accepted' and (
    (x.state in('scheduled','heading','arrived') and x.departure_at+interval '5 minutes'<=now() and x.departure_handled_at is null)
    or (x.state='picked_up' and x.arrival_at+interval '5 minutes'<=now() and x.arrival_handled_at is null))
  ) alerts),'[]'::jsonb);
 end if;
 raise exception 'UNKNOWN_ACTION';
end;
$$;
revoke all on function tkt_private.line_alert_action(text,jsonb) from public,anon;
grant execute on function tkt_private.line_alert_action(text,jsonb) to authenticated;
create or replace function public.tkt_line_alerts(p_action text,p_data jsonb default '{}')
returns jsonb language sql security invoker set search_path='' as $$
 select tkt_private.line_alert_action(p_action,p_data);
$$;
revoke all on function public.tkt_line_alerts(text,jsonb) from public,anon;
grant execute on function public.tkt_line_alerts(text,jsonb) to authenticated;
