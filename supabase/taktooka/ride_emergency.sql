begin;
create table if not exists tkt_private.ride_emergencies(
 id uuid primary key default gen_random_uuid(), ride_id uuid not null references public.tkt_rides(id),
 reporter_id uuid not null references public.tkt_profiles(user_id), rider_id uuid not null,
 captain_id uuid, status text not null default 'open' check(status in ('open','resolved')),
 lat float8, lng float8, location_at timestamptz, location_source text not null,
 created_at timestamptz not null default clock_timestamp(), resolved_at timestamptz, resolved_by uuid,
 unique(ride_id,reporter_id), check(lat between -90 and 90),check(lng between -180 and 180)
);
alter table tkt_private.ride_emergencies enable row level security;
revoke all on tkt_private.ride_emergencies from public,anon,authenticated;
create or replace function tkt_private.emergency(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();r public.tkt_rides;e tkt_private.ride_emergencies;staff_id uuid;
 la float8;lo float8;at_time timestamptz;source text:='unavailable';body_text text;
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 if not exists(select 1 from public.tkt_profiles where user_id=u and not blocked) then raise exception 'ACCOUNT_BLOCKED';end if;
 if p_action in ('list','resolve') then
  perform tkt_private.require_dashboard('support',p_action='resolve');
  if p_action='resolve' then
   update tkt_private.ride_emergencies set status='resolved',resolved_at=clock_timestamp(),resolved_by=u where id=(p_data->>'id')::uuid and status='open';
   return '{"ok":true}';
  end if;
  return coalesce((select jsonb_agg(to_jsonb(x)) from (
   select alert.*,rp.name as rider_name,cp.name as captain_name,rp.phone as rider_phone,cp.phone as captain_phone
   from tkt_private.ride_emergencies alert join public.tkt_profiles rp on rp.user_id=alert.rider_id
   left join public.tkt_profiles cp on cp.user_id=alert.captain_id
   order by (alert.status='open') desc,alert.created_at desc limit 200)x),'[]');
 end if;
 select * into r from public.tkt_rides where id=(p_data->>'ride_id')::uuid for update;
 if r.id is null or (r.rider_id<>u and r.captain_id is distinct from u) then raise exception 'FORBIDDEN';end if;
 if r.status<>'in_progress' then raise exception 'RIDE_NOT_IN_PROGRESS';end if;
 if p_action='location' and r.rider_id<>u then raise exception 'FORBIDDEN';end if;
 if p_data->>'lat' is not null and p_data->>'lng' is not null then
  la:=(p_data->>'lat')::float8;lo:=(p_data->>'lng')::float8;at_time:=(p_data->>'location_at')::timestamptz;
  if not (la between -90 and 90 and lo between -180 and 180) or at_time is null or at_time>clock_timestamp()+interval '30 seconds' or at_time<clock_timestamp()-interval '5 minutes' then raise exception 'INVALID_LOCATION';end if;
  if u=r.rider_id then
   source:='rider';
   update public.tkt_profiles set lat=la,lng=lo,location_at=at_time where user_id=u and (location_at is null or location_at<=at_time);
  else source:='vehicle';end if;
 end if;
 if p_action='location' then
  if source='rider' then update tkt_private.ride_emergencies set lat=la,lng=lo,location_at=at_time,location_source='rider' where ride_id=r.id and status='open' and (location_at is null or location_at<=at_time);end if;
  return '{"ok":true}';
 end if;
 if p_action<>'send' then raise exception 'UNKNOWN_ACTION';end if;
 select * into e from tkt_private.ride_emergencies where ride_id=r.id and reporter_id=u;
 if e.id is not null then return to_jsonb(e);end if;
 if source<>'rider' then
  if exists(select 1 from public.tkt_profiles where user_id=r.rider_id and lat is not null and lng is not null and location_at>clock_timestamp()-interval '60 seconds') then
   select lat,lng,location_at into la,lo,at_time from public.tkt_profiles where user_id=r.rider_id;source:='rider';
  elsif source='unavailable' then
   select lat,lng,location_at into la,lo,at_time from public.tkt_profiles where user_id=r.rider_id;
   if la is not null and lo is not null then source:='rider_last_known';
   else select lat,lng,location_at into la,lo,at_time from public.tkt_profiles where user_id=r.captain_id;
    if la is not null and lo is not null then source:='vehicle_last_known';else source:='unavailable';end if;
   end if;
  end if;
 end if;
 insert into tkt_private.ride_emergencies(ride_id,reporter_id,rider_id,captain_id,lat,lng,location_at,location_source)
 values(r.id,u,r.rider_id,r.captain_id,la,lo,at_time,source) returning * into e;
 body_text:='SOS حالة طارئة 911'||E'\nرقم الرحلة: '||r.id::text||E'\nوقت البلاغ: '||e.created_at::text||
 E'\nمصدر الموقع: '||source||E'\nوقت الموقع: '||coalesce(at_time::text,'غير متاح')||
 case when la is not null and lo is not null then E'\nhttps://maps.google.com/?q='||la::text||','||lo::text else E'\nالموقع غير متاح؛ تواصل مع الزبون والكابتن فورًا' end;
 insert into public.tkt_messages(user_id,sender_id,is_admin,body) values(u,u,false,body_text);
 insert into tkt_private.preferences(user_id) values(u) on conflict do nothing;
 perform tkt_private.notify_admins('emergency:'||e.id::text,'emergency','SOS حالة طارئة 911','بلاغ طوارئ من رحلة جارية؛ افتح الدعم فورًا',jsonb_build_object('screen','emergency','emergency_id',e.id,'ride_id',r.id,'user_id',u));
 for staff_id in select s.user_id from tkt_private.staff_accounts s join public.tkt_profiles p on p.user_id=s.user_id where s.active and not p.blocked and s.permissions->'support'->>'view'='true' and not exists(select 1 from public.tkt_admins a where a.user_id=s.user_id) loop
  perform tkt_private.notification_add(staff_id,'emergency:'||e.id::text,'emergency','SOS حالة طارئة 911','بلاغ طوارئ من رحلة جارية؛ افتح الدعم فورًا',jsonb_build_object('screen','emergency','emergency_id',e.id,'ride_id',r.id,'user_id',u));
 end loop;
 return to_jsonb(e);
end $$;
revoke all on function tkt_private.emergency(text,jsonb) from public,anon;
grant execute on function tkt_private.emergency(text,jsonb) to authenticated;
create or replace function public.tkt_emergency(p_action text,p_data jsonb default '{}') returns jsonb language sql set search_path='' as $$select tkt_private.emergency(p_action,p_data)$$;
revoke all on function public.tkt_emergency(text,jsonb) from public,anon;
grant execute on function public.tkt_emergency(text,jsonb) to authenticated;
create or replace function public.tkt_action(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql set search_path='' as $$
declare result jsonb;
begin
 result:=tkt_private.action(p_action,p_data);
 if p_action='contact' and exists(select 1 from public.tkt_rides where id=(p_data->>'ride_id')::uuid and status='in_progress') then result:=result-'phone';end if;
 return result;
end $$;
commit;
