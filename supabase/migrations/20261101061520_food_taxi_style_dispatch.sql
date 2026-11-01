create table tkt_private.food_dispatch_jobs (
 order_id uuid primary key references tkt_private.food_orders(id) on delete cascade,
 round_at timestamptz not null, zone text, started_at timestamptz not null default clock_timestamp(),
 deadline timestamptz not null, state text not null check(state in ('searching','matched','stopped','no_captain'))
);
create table tkt_private.food_dispatch_offers (
 id uuid primary key default gen_random_uuid(), order_id uuid not null references tkt_private.food_orders(id) on delete cascade,
 captain_id uuid not null references public.tkt_profiles(user_id), round_at timestamptz not null,
 status text not null default 'offered' check(status in ('offered','accepted','declined','expired','cancelled')),
 eta_s integer not null check(eta_s>=0), expires_at timestamptz not null,
 created_at timestamptz not null default clock_timestamp()
);
create unique index food_dispatch_one_order on tkt_private.food_dispatch_offers(order_id) where status='offered';
create unique index food_dispatch_one_captain on tkt_private.food_dispatch_offers(captain_id) where status='offered';
create index food_dispatch_tried on tkt_private.food_dispatch_offers(order_id,round_at,captain_id);
create table tkt_private.food_dispatch_eta (
 ride_id uuid not null references tkt_private.food_orders(id) on delete cascade,
 captain_id uuid not null references public.tkt_profiles(user_id),lat float8 not null,lng float8 not null,
 eta_s integer,computed_at timestamptz not null default clock_timestamp(),primary key(ride_id,captain_id)
);
create table tkt_private.food_dispatch_lease (
 id boolean primary key default true check(id), lease_id uuid,lease_until timestamptz,last_matrix_at timestamptz,last_error text
);
insert into tkt_private.food_dispatch_lease(id) values(true);
alter table tkt_private.food_dispatch_jobs enable row level security;
alter table tkt_private.food_dispatch_offers enable row level security;
alter table tkt_private.food_dispatch_eta enable row level security;
alter table tkt_private.food_dispatch_lease enable row level security;
revoke all on tkt_private.food_dispatch_jobs,tkt_private.food_dispatch_offers,tkt_private.food_dispatch_eta,tkt_private.food_dispatch_lease from public,anon,authenticated;

create function tkt_private.food_dispatch_eligible(p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.tkt_profiles p join tkt_private.dispatch_locations l on l.captain_id=p.user_id
 cross join tkt_private.dispatch_settings s where s.id and p.user_id=p_user and p.online and p.captain and not p.blocked and p.deleted_at is null
 and p.name<>'' and p.phone<>'' and tkt_private.captain_eligible(p.user_id,false)
 and coalesce((select vehicle from tkt_private.captain_plans where user_id=p.user_id),'tuktuk')='tuktuk'
 and l.gps_at>clock_timestamp()-make_interval(secs=>s.stale_s) and l.received_at>clock_timestamp()-make_interval(secs=>s.stale_s)
 and p.location_at>clock_timestamp()-make_interval(secs=>s.stale_s)
 and not exists(select 1 from public.tkt_rides where captain_id=p.user_id and status in('accepted','arrived','in_progress')))
$$;

create function tkt_private.food_dispatch_maintenance() returns void language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare f tkt_private.food_dispatch_offers;
begin
 for f in select x.* from tkt_private.food_dispatch_offers x join tkt_private.food_orders o on o.id=x.order_id
 where x.status='offered' and (x.expires_at<=clock_timestamp() or o.status<>'searching' or o.updated_at<>x.round_at
 or o.delivery_mode<>'public' or not tkt_private.food_dispatch_eligible(x.captain_id)
 or exists(select 1 from tkt_private.food_offer_declines d where d.order_id=x.order_id and d.user_id=x.captain_id and d.round_at=x.round_at)) for update of o skip locked loop
  update tkt_private.food_dispatch_offers set status='expired' where id=f.id and status='offered';
  perform tkt_private.food_requests_stop(f.order_id,'courier',f.captain_id);
 end loop;
 update tkt_private.food_dispatch_jobs j set state='no_captain' where state='searching' and deadline<=clock_timestamp()
 and not exists(select 1 from tkt_private.food_dispatch_offers f where f.order_id=j.order_id and f.status='offered');
end $$;

create function tkt_private.food_dispatch_round() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status='searching' and new.delivery_mode='public' and new.vehicle='tuktuk' and
 (old.status is distinct from new.status or old.updated_at is distinct from new.updated_at or old.delivery_mode is distinct from new.delivery_mode) then
  update tkt_private.food_dispatch_offers set status='cancelled' where order_id=new.id and status='offered';
  insert into tkt_private.food_dispatch_jobs(order_id,round_at,zone,deadline,state)
  select new.id,new.updated_at,tkt_private.service_zone((r.location->>0)::float8,(r.location->>1)::float8),
  clock_timestamp()+make_interval(secs=>s.search_s),'searching'
  from tkt_private.restaurants r cross join tkt_private.dispatch_settings s where r.id=new.restaurant_id and s.id
  on conflict(order_id) do update set round_at=excluded.round_at,zone=excluded.zone,started_at=clock_timestamp(),deadline=excluded.deadline,state='searching';
 elsif exists(select 1 from tkt_private.food_dispatch_jobs where order_id=new.id) and (new.status<>'searching' or new.delivery_mode<>'public') then
  update tkt_private.food_dispatch_jobs set state=case when new.status='accepted' then 'matched' else 'stopped' end where order_id=new.id;
  update tkt_private.food_dispatch_offers set status=case when new.status='accepted' and captain_id=new.captain_id then 'accepted' else 'cancelled' end where order_id=new.id and status='offered';
 end if;
 return new;
end $$;
create trigger food_dispatch_round after update on tkt_private.food_orders for each row execute function tkt_private.food_dispatch_round();

create function tkt_private.food_dispatch_notification_gate() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.kind='food' and new.target->>'request_type'='courier' and exists(select 1 from tkt_private.food_dispatch_jobs j join tkt_private.food_orders o on o.id=j.order_id
 where j.order_id::text=new.target->>'order_id' and o.delivery_mode='public' and o.vehicle='tuktuk')
 and not exists(select 1 from tkt_private.food_dispatch_offers f where f.order_id::text=new.target->>'order_id' and f.captain_id=new.user_id and f.status='offered' and f.expires_at>clock_timestamp()) then return null;end if;
 return new;
end $$;
create trigger food_dispatch_notification_gate before insert on public.tkt_notifications for each row execute function tkt_private.food_dispatch_notification_gate();

create function tkt_private.food_dispatch_taxi_reservation() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status='offered' and exists(select 1 from tkt_private.food_dispatch_offers where captain_id=new.captain_id and status='offered' and expires_at>clock_timestamp()) then return null;end if;
 return new;
end $$;
create trigger food_dispatch_taxi_reservation before insert on public.tkt_offers for each row execute function tkt_private.food_dispatch_taxi_reservation();

create function tkt_private.food_dispatch_worker(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare s tkt_private.dispatch_settings;lease tkt_private.food_dispatch_lease;rec jsonb;token uuid;u uuid;
 o tkt_private.food_orders;j tkt_private.food_dispatch_jobs;f tkt_private.food_dispatch_offers;res jsonb;n integer:=0;
begin
 if p_action='lease' and not exists(select 1 from vault.decrypted_secrets where name='tkt_dispatch_worker_token' and decrypted_secret=p_data->>'worker_token') then raise exception 'AUTH_REQUIRED';end if;
 perform pg_advisory_xact_lock(74658291);
 perform tkt_private.food_dispatch_maintenance();
 select * into strict s from tkt_private.dispatch_settings where id;
 select * into strict lease from tkt_private.food_dispatch_lease where id for update;
 if p_action='lease' then
  if not exists(select 1 from vault.decrypted_secrets where name='tkt_dispatch_worker_token' and decrypted_secret=p_data->>'worker_token') then raise exception 'AUTH_REQUIRED';end if;
  if lease.lease_until>clock_timestamp() then return '{"busy":true}';end if;
  token:=gen_random_uuid();update tkt_private.food_dispatch_lease set lease_id=token,lease_until=clock_timestamp()+interval '20 seconds' where id;
  return jsonb_build_object('lease_id',token,'settings',(to_jsonb(s)-'lease_id'-'lease_until')||jsonb_build_object('last_matrix_at',lease.last_matrix_at),
   'jobs',coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'pickup',r.location,'zone',j.zone,'created_at',j.started_at,'tried',coalesce((select jsonb_agg(f.captain_id) from tkt_private.food_dispatch_offers f where f.order_id=o.id and f.round_at=j.round_at),'[]')) order by j.started_at)
   from tkt_private.food_dispatch_jobs j join tkt_private.food_orders o on o.id=j.order_id join tkt_private.restaurants r on r.id=o.restaurant_id
   where j.state='searching' and j.deadline>clock_timestamp() and o.status='searching' and o.delivery_mode='public' and o.updated_at=j.round_at
   and not exists(select 1 from tkt_private.food_dispatch_offers f where f.order_id=o.id and f.status='offered')),'[]'),
   'available_cells',coalesce((select jsonb_agg(distinct jsonb_build_object('zone',l.zone,'cell',l.cell)) from tkt_private.dispatch_locations l
   where tkt_private.food_dispatch_eligible(l.captain_id) and not exists(select 1 from public.tkt_offers where captain_id=l.captain_id and status='offered')
   and not exists(select 1 from tkt_private.food_dispatch_offers where captain_id=l.captain_id and status='offered')),'[]'),'tracking','[]'::jsonb);
 end if;
 if lease.lease_id is distinct from (p_data->>'lease_id')::uuid or lease.lease_until<=clock_timestamp() then raise exception 'LEASE_EXPIRED';end if;
 if p_action='candidates' then
  return coalesce((select jsonb_agg(to_jsonb(c)) from(select l.captain_id as user_id,l.lat,l.lng,l.gps_at,e.eta_s,e.computed_at as cached_at
  from tkt_private.dispatch_locations l left join tkt_private.food_dispatch_eta e on e.ride_id=(p_data->>'ride_id')::uuid and e.captain_id=l.captain_id and e.lat=l.lat and e.lng=l.lng and e.computed_at>clock_timestamp()-interval '30 seconds'
  join tkt_private.food_dispatch_jobs j on j.order_id=(p_data->>'ride_id')::uuid
  join tkt_private.food_orders o on o.id=j.order_id join tkt_private.restaurants r on r.id=o.restaurant_id
  where j.state='searching' and j.deadline>clock_timestamp() and j.round_at=o.updated_at and r.owner_id<>l.captain_id
  and l.zone=j.zone and l.zone=p_data->>'zone' and l.cell in(select jsonb_array_elements_text(p_data->'cells')) and tkt_private.food_dispatch_eligible(l.captain_id)
  and not exists(select 1 from public.tkt_offers where captain_id=l.captain_id and status='offered')
  and not exists(select 1 from tkt_private.food_dispatch_offers where captain_id=l.captain_id and status='offered')
  and not exists(select 1 from tkt_private.food_dispatch_offers f where f.order_id=j.order_id and f.round_at=j.round_at and f.captain_id=l.captain_id)
  order by l.captain_id limit 1000)c),'[]');
 elsif p_action='cache' then
  for rec in select value from jsonb_array_elements(p_data->'results') loop
   insert into tkt_private.food_dispatch_eta(ride_id,captain_id,lat,lng,eta_s) values((rec->>'ride_id')::uuid,(rec->>'captain_id')::uuid,(rec->>'lat')::float8,(rec->>'lng')::float8,(rec->>'eta_s')::integer)
   on conflict(ride_id,captain_id) do update set lat=excluded.lat,lng=excluded.lng,eta_s=excluded.eta_s,computed_at=clock_timestamp();
  end loop;
  update tkt_private.food_dispatch_lease set last_matrix_at=clock_timestamp() where id;return '{"ok":true}';
 elsif p_action='apply' then
  for rec in select value from jsonb_array_elements(p_data->'edges') order by (value->>'eta_s')::integer,(value->>'created_at')::timestamptz,value->>'ride_id',value->>'captain_id' loop
   select * into o from tkt_private.food_orders where id=(rec->>'ride_id')::uuid for update;
   select * into j from tkt_private.food_dispatch_jobs where order_id=o.id for update;
   u:=(rec->>'captain_id')::uuid;perform 1 from public.tkt_profiles where user_id=u for update;
   if o.id is null or j.order_id is null or o.status<>'searching' or o.delivery_mode<>'public' or j.round_at<>o.updated_at or j.state<>'searching' or j.deadline<=clock_timestamp() or not tkt_private.food_dispatch_eligible(u) then continue;end if;
   if (rec->>'eta_s')::integer not between 0 and s.max_eta_s then continue;end if;
   if not exists(select 1 from tkt_private.dispatch_locations l join tkt_private.food_dispatch_eta e on e.captain_id=l.captain_id and e.ride_id=o.id
    join tkt_private.restaurants r on r.id=o.restaurant_id
    where l.captain_id=u and r.owner_id<>u and l.zone=j.zone and e.computed_at>clock_timestamp()-interval '30 seconds' and e.eta_s=(rec->>'eta_s')::integer
    and tkt_private.km(l.lat,l.lng,e.lat,e.lng)<=0.03) then continue;end if;
   if exists(select 1 from public.tkt_offers where captain_id=u and status='offered') or exists(select 1 from tkt_private.food_dispatch_offers where status='offered' and (captain_id=u or order_id=o.id))
    or exists(select 1 from tkt_private.food_dispatch_offers where order_id=o.id and captain_id=u and round_at=j.round_at) then continue;end if;
   insert into tkt_private.food_dispatch_offers(order_id,captain_id,round_at,eta_s,expires_at) values(o.id,u,j.round_at,(rec->>'eta_s')::integer,clock_timestamp()+interval '120 seconds') returning * into f;
   perform tkt_private.notification_add(u,'food-dispatch:'||f.id,'food','طلب توصيل طعام','عندك طلب توصيل طعام؛ عندك دقيقتين للموافقة.',jsonb_build_object('screen','food','order_id',o.id,'request_type','courier','offer_id','f:'||o.id||':c:'||floor(extract(epoch from o.updated_at)*1000000)::bigint::text),f.expires_at);
   update tkt_private.food_dispatch_jobs set deadline=greatest(deadline,f.expires_at+make_interval(secs=>s.search_s)) where order_id=o.id;
   n:=n+1;
  end loop;return jsonb_build_object('offered',n);
 elsif p_action='finish' then
  update tkt_private.food_dispatch_lease set lease_until=null,last_error=p_data->>'error',last_matrix_at=case when coalesce((p_data->>'matrix_used')::boolean,false) then clock_timestamp() else last_matrix_at end where id;
  return '{"ok":true}';
 end if;
 raise exception 'UNKNOWN_ACTION';
end $$;
create function public.tkt_food_dispatch_worker(p_action text,p_data jsonb default '{}') returns jsonb language sql set search_path='' as $$select tkt_private.food_dispatch_worker(p_action,p_data)$$;
revoke all on function public.tkt_food_dispatch_worker(text,jsonb) from public,anon,authenticated;
grant execute on function public.tkt_food_dispatch_worker(text,jsonb) to service_role;
grant execute on function tkt_private.food_dispatch_worker(text,jsonb) to service_role;

create function tkt_private.food_dispatch_commerce(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare u uuid:=auth.uid();s tkt_private.commerce_settings;o tkt_private.food_orders;r tkt_private.restaurants;c public.tkt_profiles;f tkt_private.food_dispatch_offers;result jsonb;item jsonb;
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 if not exists(select 1 from public.tkt_profiles where user_id=u and not blocked and deleted_at is null) then raise exception 'ACCOUNT_BLOCKED';end if;
 select * into strict s from tkt_private.commerce_settings where id;
 if p_action='me' then
  result:=tkt_private.commerce('me',p_data);
  return result||jsonb_build_object('has_private_courier',exists(select 1 from tkt_private.restaurants r join tkt_private.restaurant_couriers rc on rc.restaurant_id=r.id join public.tkt_profiles p on p.user_id=rc.user_id where r.owner_id=u and r.self_delivery and rc.active and not p.blocked and p.deleted_at is null));
 end if;
 if p_action='orders' then
  return coalesce((select jsonb_agg(j order by j->>'created_at' desc) from (
   select to_jsonb(x)||jsonb_build_object('restaurant_name',z.name,'restaurant_phone',z.phone,'restaurant_address',z.address,'restaurant_location',z.location,'captain_name',p.name,'captain_phone',p.phone,'customer_name',cp.name,'customer_phone',cp.phone,'courier_offer_expires_at',case when x.status='searching' then coalesce((select f.expires_at from tkt_private.food_dispatch_offers f where f.order_id=x.id and f.status='offered' and f.captain_id=u),x.updated_at+interval '120 seconds') end,'request_offer_id',case when x.status='pending' then 'f:'||x.id||':r' when x.status='searching' then 'f:'||x.id||':c:'||floor(extract(epoch from x.updated_at)*1000000)::bigint::text end)
    as j from tkt_private.food_orders x join tkt_private.restaurants z on z.id=x.restaurant_id left join public.tkt_profiles p on p.user_id=x.captain_id join public.tkt_profiles cp on cp.user_id=x.customer_id
   where x.customer_id=u or z.owner_id=u or x.captain_id=u or (x.status='searching' and tkt_private.food_offer_active(x.id,x.updated_at,u) and x.delivery_mode='private' and tkt_private.private_courier_eligible(u,x.restaurant_id)) or (x.status='searching' and x.delivery_mode='public' and tkt_private.food_dispatch_eligible(u) and exists(select 1 from tkt_private.food_dispatch_offers f where f.order_id=x.id and f.captain_id=u and f.round_at=x.updated_at and f.status='offered' and f.expires_at>clock_timestamp())) or (not exists(select 1 from tkt_private.food_dispatch_jobs where order_id=x.id) and x.status='searching' and tkt_private.food_offer_active(x.id,x.updated_at,u) and x.delivery_mode='public' and tkt_private.captain_eligible(u,false) and z.owner_id<>u and tkt_private.company_debt(u,'captain_company')<s.captain_debt_limit and exists(select 1 from public.tkt_profiles k left join tkt_private.captain_plans pl on pl.user_id=k.user_id where k.user_id=u and k.captain and k.online and not k.blocked and k.location_at>clock_timestamp()-interval '90 seconds' and tkt_private.km((z.location->>0)::float8,(z.location->>1)::float8,k.lat,k.lng)<=5 and (pl.plan='commission' or k.expires_at>clock_timestamp()) and coalesce(pl.vehicle,'tuktuk')=x.vehicle) and not exists(select 1 from public.tkt_rides where captain_id=u and status in('accepted','arrived','in_progress')) and not exists(select 1 from tkt_private.food_orders where captain_id=u and status in('accepted','heading','picked_up')))
   order by x.created_at desc limit 200) a),'[]');
 end if;

 if p_action='order_details' then
  result:=tkt_private.food_dispatch_commerce('orders','{}');
  select value into item from jsonb_array_elements(result) where value->>'id'=p_data->>'id';
  if item is null then raise exception 'ORDER_UNAVAILABLE';end if;return item;
 end if;
 if p_action in('offer_decline','order_update') then
  select * into o from tkt_private.food_orders where id=(p_data->>'id')::uuid for update;
  if o.delivery_mode='public' and exists(select 1 from tkt_private.food_dispatch_jobs where order_id=o.id) and (p_action='offer_decline' or p_data->>'status'='accepted') then
   perform 1 from public.tkt_profiles where user_id=u for update;
   select * into f from tkt_private.food_dispatch_offers where order_id=o.id and captain_id=u and round_at=o.updated_at and status='offered' for update;
   if f.id is null or f.expires_at<=clock_timestamp() or o.status<>'searching' then raise exception 'OFFER_EXPIRED';end if;
   if p_action='offer_decline' then
    update tkt_private.food_dispatch_offers set status='declined' where id=f.id;
    insert into tkt_private.food_offer_declines values(o.id,u,o.updated_at) on conflict do nothing;
    perform tkt_private.food_requests_stop(o.id,'courier',u);return '{"ok":true}';
   end if;
   if not tkt_private.food_dispatch_eligible(u) then raise exception 'CAPTAIN_UNAVAILABLE';end if;
   select * into strict r from tkt_private.restaurants where id=o.restaurant_id;
   if tkt_private.company_debt(u,'captain_company')>=s.captain_debt_limit then raise exception 'CAPTAIN_DEBT_LIMIT';end if;
   select * into c from public.tkt_profiles where user_id=u for update;
   if not tkt_private.captain_eligible(u,false) then raise exception 'PERMISSION_DENIED';end if;
   if o.status<>'searching' or not c.captain or not c.online or c.blocked or c.location_at is null or c.location_at<clock_timestamp()-interval '90 seconds' or r.owner_id=u then raise exception 'OFFER_EXPIRED';end if;
   if not exists(select 1 from tkt_private.captain_plans where user_id=u and plan='commission') and coalesce(c.expires_at<=clock_timestamp(),true) then raise exception 'CAPTAIN_SUBSCRIPTION_REQUIRED';end if;
   if coalesce((select vehicle from tkt_private.captain_plans where user_id=u),'tuktuk')<>o.vehicle then raise exception 'VEHICLE_MISMATCH';end if;
   if exists(select 1 from public.tkt_rides where captain_id=u and status in('accepted','arrived','in_progress')) or exists(select 1 from tkt_private.food_orders where captain_id=u and status in('accepted','heading','picked_up')) then raise exception 'CAPTAIN_BUSY';end if;
   o.captain_id:=u;
   o.commission_amount:=case when exists(select 1 from tkt_private.captain_plans where user_id=u and plan='commission') then round(o.delivery_fee*o.commission_percent/100)::integer else 0 end;
   perform tkt_private.food_requests_stop(o.id,'courier');
   update tkt_private.food_orders set status='accepted',captain_id=u,commission_amount=o.commission_amount,updated_at=clock_timestamp() where id=o.id returning * into o;
   perform tkt_private.notification_add(o.customer_id,'food:'||o.id||':accepted','food','طلب الطعام','وافق المندوب على طلبك؛ افتح الطلب لعرض معلوماته',jsonb_build_object('screen','food','order_id',o.id));
   perform tkt_private.notification_add(r.owner_id,'food:'||o.id||':accepted','food','حالة طلب الطعام','وافق المندوب على طلبك؛ افتح الطلب لعرض معلوماته',jsonb_build_object('screen','food','order_id',o.id));
   return to_jsonb(o);
  end if;
 end if;
 return tkt_private.commerce(p_action,p_data);
end $$;
create function public.tkt_food_commerce(p_action text,p_data jsonb default '{}') returns jsonb language sql set search_path='' as $$select tkt_private.food_dispatch_commerce(p_action,p_data)$$;
revoke all on function public.tkt_food_commerce(text,jsonb) from public,anon;
grant execute on function public.tkt_food_commerce(text,jsonb) to authenticated;
revoke all on function tkt_private.food_dispatch_commerce(text,jsonb) from public,anon;
grant execute on function tkt_private.food_dispatch_commerce(text,jsonb) to authenticated;

create function tkt_private.food_dispatch_tick() returns void language plpgsql security definer set search_path='' as $$
begin
 perform tkt_private.food_dispatch_maintenance();
 if exists(select 1 from tkt_private.food_dispatch_jobs where state='searching') or exists(select 1 from tkt_private.food_dispatch_offers where status='offered') then
  perform net.http_post(url:='https://typbkzwbrmkrfkfxjrgi.supabase.co/functions/v1/taktooka-food-dispatch',headers:='{"Content-Type":"application/json"}'::jsonb,
   body:=jsonb_build_object('worker_token',(select decrypted_secret from vault.decrypted_secrets where name='tkt_dispatch_worker_token')),timeout_milliseconds:=18000);
 end if;
end $$;
revoke all on function tkt_private.food_dispatch_eligible(uuid),tkt_private.food_dispatch_maintenance(),tkt_private.food_dispatch_round(),tkt_private.food_dispatch_notification_gate(),tkt_private.food_dispatch_taxi_reservation(),tkt_private.food_dispatch_tick() from public,anon,authenticated;
revoke all on function tkt_private.food_dispatch_worker(text,jsonb) from public,anon,authenticated;
select cron.schedule('tkt-food-dispatch-worker','2 seconds','select tkt_private.food_dispatch_tick()');
