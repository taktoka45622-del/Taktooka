begin;

create table if not exists tkt_private.commerce_settings(
 id boolean primary key default true check(id),
 commission_percent numeric(5,2) not null default 20 check(commission_percent between 0 and 100),
 service_fee integer not null default 500 check(service_fee between 0 and 100000),
 captain_debt_limit integer not null default 10000 check(captain_debt_limit>0),
 restaurant_debt_limit integer not null default 10000 check(restaurant_debt_limit>0),
 updated_at timestamptz not null default now()
);
insert into tkt_private.commerce_settings(id) values(true) on conflict do nothing;
create table if not exists tkt_private.restaurants(
 id uuid primary key default gen_random_uuid(),owner_id uuid not null unique references public.tkt_profiles(user_id),
 name text not null check(length(name) between 2 and 160),phone text not null,
 address text not null,description text not null default '',image_path text not null default '',
 location jsonb not null,open boolean not null default true,created_at timestamptz not null default now()
);
create table if not exists tkt_private.restaurant_items(
 id uuid primary key default gen_random_uuid(),restaurant_id uuid not null references tkt_private.restaurants(id),
 name text not null check(length(name) between 1 and 160),description text not null default '',
 price integer not null check(price between 0 and 1000000),image_path text not null default '',
 available boolean not null default true,sort_order integer not null default 0
);
create index if not exists restaurant_items_shop on tkt_private.restaurant_items(restaurant_id,sort_order);
create table if not exists tkt_private.captain_plans(
 user_id uuid primary key references public.tkt_profiles(user_id),
 plan text not null default 'weekly' check(plan in('weekly','commission')),
 vehicle text not null default 'tuktuk' check(vehicle in('tuktuk','bike'))
);
create table if not exists tkt_private.food_orders(
 id uuid primary key default gen_random_uuid(),request_id uuid not null,
 customer_id uuid not null references public.tkt_profiles(user_id),
 restaurant_id uuid not null references tkt_private.restaurants(id),
 captain_id uuid references public.tkt_profiles(user_id),quote_id uuid not null unique references public.tkt_quotes(id),
 items jsonb not null,food_total integer not null check(food_total>=0),
 delivery_fee integer not null check(delivery_fee>=0),service_fee integer not null check(service_fee>=0),
 commission_percent numeric(5,2) not null check(commission_percent between 0 and 100),
 commission_amount integer not null default 0 check(commission_amount>=0),
 status text not null default 'pending' check(status in('pending','preparing','searching','accepted','heading','picked_up','delivered','rejected')),
 vehicle text check(vehicle in('tuktuk','bike')),reason text not null default '',
 customer_address text not null,customer_location jsonb not null,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(customer_id,request_id)
);
create index if not exists food_order_customer on tkt_private.food_orders(customer_id,created_at desc);
create index if not exists food_order_restaurant on tkt_private.food_orders(restaurant_id,created_at desc);
create index if not exists food_order_captain on tkt_private.food_orders(captain_id,status,created_at desc);
create table if not exists tkt_private.commerce_debts(
 id uuid primary key default gen_random_uuid(),source_id uuid not null,
 kind text not null check(kind in('restaurant_fee','captain_company','captain_restaurant')),
 debtor_id uuid not null references public.tkt_profiles(user_id),creditor_id uuid references public.tkt_profiles(user_id),
 restaurant_id uuid references tkt_private.restaurants(id),amount integer not null check(amount>=0),
 created_at timestamptz not null default now(),settled_at timestamptz,settlement_id uuid,
 unique(source_id,kind)
);
create index if not exists commerce_debts_open on tkt_private.commerce_debts(debtor_id,kind) where settled_at is null;
create table if not exists tkt_private.commerce_settlements(
 id uuid primary key default gen_random_uuid(),kind text not null check(kind in('restaurant_fee','captain_company','captain_restaurant')),
 debtor_id uuid not null references public.tkt_profiles(user_id),creditor_id uuid references public.tkt_profiles(user_id),
 restaurant_id uuid references tkt_private.restaurants(id),amount bigint not null check(amount>0),
 status text not null default 'pending' check(status in('pending','confirmed','expired')),
 code_hash bytea,attempts integer not null default 0,expires_at timestamptz,
 created_at timestamptz not null default now(),confirmed_at timestamptz,confirmed_by uuid
);
create unique index if not exists commerce_one_pending on tkt_private.commerce_settlements(debtor_id,kind,coalesce(restaurant_id,'00000000-0000-0000-0000-000000000000'::uuid)) where status='pending';
create table if not exists tkt_private.commerce_settlement_items(
 settlement_id uuid references tkt_private.commerce_settlements(id),debt_id uuid unique references tkt_private.commerce_debts(id),
 primary key(settlement_id,debt_id)
);
create table if not exists tkt_private.restaurant_complaints(
 id uuid primary key default gen_random_uuid(),restaurant_id uuid not null references tkt_private.restaurants(id),
 captain_id uuid not null references public.tkt_profiles(user_id),body text not null check(length(body) between 3 and 2000),
 status text not null default 'open' check(status in('open','handled')),created_at timestamptz not null default now()
);
do $$ declare t text; begin
 foreach t in array array['commerce_settings','restaurants','restaurant_items','captain_plans','food_orders','commerce_debts','commerce_settlements','commerce_settlement_items','restaurant_complaints'] loop
 execute format('alter table tkt_private.%I enable row level security',t);
 execute format('revoke all on tkt_private.%I from public,anon,authenticated',t);
 end loop;
end $$;

create or replace function tkt_private.company_debt(p_user uuid,p_kind text) returns bigint language sql stable security definer set search_path='' as $$
 select coalesce(sum(amount),0)::bigint from tkt_private.commerce_debts where debtor_id=p_user and kind=p_kind and settled_at is null
$$;
revoke all on function tkt_private.company_debt(uuid,text) from public,anon,authenticated;

create or replace function tkt_private.captain_eligible(p_user uuid,p_taxi boolean default true) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.tkt_profiles p left join tkt_private.captain_plans pl on pl.user_id=p.user_id
  cross join tkt_private.commerce_settings s where s.id and p.user_id=p_user and p.captain and not p.blocked and p.deleted_at is null
  and (pl.plan='commission' or p.expires_at>clock_timestamp())
  and (not p_taxi or coalesce(pl.vehicle,'tuktuk')='tuktuk')
  and tkt_private.company_debt(p.user_id,'captain_company')<s.captain_debt_limit
  and not exists(select 1 from tkt_private.food_orders where captain_id=p.user_id and status in('accepted','heading','picked_up')))
$$;
revoke all on function tkt_private.captain_eligible(uuid,boolean) from public,anon,authenticated;

create or replace function tkt_private.food_order_accounting() returns trigger language plpgsql security definer set search_path='' as $$
declare owner uuid;
begin
 if new.status='delivered' and old.status is distinct from 'delivered' then
  select owner_id into strict owner from tkt_private.restaurants where id=new.restaurant_id;
  insert into tkt_private.commerce_debts(source_id,kind,debtor_id,restaurant_id,amount)
   values(new.id,'restaurant_fee',owner,new.restaurant_id,new.service_fee) on conflict do nothing;
  insert into tkt_private.commerce_debts(source_id,kind,debtor_id,creditor_id,restaurant_id,amount)
   values(new.id,'captain_restaurant',new.captain_id,owner,new.restaurant_id,new.food_total+new.service_fee) on conflict do nothing;
  insert into tkt_private.commerce_debts(source_id,kind,debtor_id,restaurant_id,amount)
   values(new.id,'captain_company',new.captain_id,new.restaurant_id,new.commission_amount) on conflict do nothing;
 end if;
 return new;
end $$;
drop trigger if exists food_order_accounting on tkt_private.food_orders;
create trigger food_order_accounting after update on tkt_private.food_orders for each row execute function tkt_private.food_order_accounting();

create or replace function tkt_private.taxi_commission() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.captain_id is not null and new.status='accepted' and (TG_OP='INSERT' or old.captain_id is distinct from new.captain_id or old.status is distinct from 'accepted') then
  if not tkt_private.captain_eligible(new.captain_id,true) then raise exception 'CAPTAIN_UNAVAILABLE';end if;
 end if;
 if TG_OP='INSERT' then
  select commission_percent into new.company_rate from tkt_private.commerce_settings where id;
 elsif new.status='completed' and old.status is distinct from 'completed' and exists(select 1 from tkt_private.captain_plans where user_id=new.captain_id and plan='commission') then
  insert into tkt_private.commerce_debts(source_id,kind,debtor_id,amount)
   values(new.id,'captain_company',new.captain_id,round(new.fare*new.company_rate/100)::integer) on conflict do nothing;
 end if;
 return new;
end $$;
alter table public.tkt_rides add column if not exists company_rate numeric(5,2) not null default 20;
drop trigger if exists taxi_commission on public.tkt_rides;
create trigger taxi_commission before insert or update on public.tkt_rides for each row execute function tkt_private.taxi_commission();

create or replace function tkt_private.commerce(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
<<accounting>>
declare
 u uuid:=auth.uid();r tkt_private.restaurants;i tkt_private.restaurant_items;o tkt_private.food_orders;
 s tkt_private.commerce_settings;q public.tkt_quotes;c public.tkt_profiles;st tkt_private.commerce_settlements;
 rid uuid;ident uuid;owner uuid;target uuid;kind text;v text;code text;body text;next_status text;
 item jsonb;basket jsonb:='[]';total integer:=0;qty integer;ids uuid[];result jsonb;due bigint;
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 if not exists(select 1 from public.tkt_profiles where user_id=u and not blocked and deleted_at is null) then raise exception 'ACCOUNT_BLOCKED';end if;
 select * into strict s from tkt_private.commerce_settings where id;
 if p_action='me' then return jsonb_build_object('commission_percent',s.commission_percent,'service_fee',s.service_fee,'captain_debt_limit',s.captain_debt_limit,'restaurant_debt_limit',s.restaurant_debt_limit,
  'plan',coalesce((select plan from tkt_private.captain_plans where user_id=u),'weekly'),
  'vehicle',coalesce((select vehicle from tkt_private.captain_plans where user_id=u),'tuktuk'),
  'company_debt',tkt_private.company_debt(u,case when exists(select 1 from tkt_private.restaurants where owner_id=u) then 'restaurant_fee' else 'captain_company' end),
  'debt_blocked',tkt_private.company_debt(u,case when exists(select 1 from tkt_private.restaurants where owner_id=u) then 'restaurant_fee' else 'captain_company' end)>=case when exists(select 1 from tkt_private.restaurants where owner_id=u) then s.restaurant_debt_limit else s.captain_debt_limit end,
  'food_active',exists(select 1 from tkt_private.food_orders where captain_id=u and status in('accepted','heading','picked_up')),
  'restaurant',(select to_jsonb(x) from tkt_private.restaurants x where owner_id=u));end if;
 if p_action='settings_save' then
  perform tkt_private.require_dashboard('finance',true);
  update tkt_private.commerce_settings set commission_percent=(p_data->>'commission_percent')::numeric,service_fee=(p_data->>'service_fee')::integer,captain_debt_limit=coalesce((p_data->>'captain_debt_limit')::integer,captain_debt_limit),restaurant_debt_limit=coalesce((p_data->>'restaurant_debt_limit')::integer,restaurant_debt_limit),updated_at=clock_timestamp() where id returning * into s;
  insert into tkt_private.admin_audit(actor_id,action,details)values(u,'commerce_settings',to_jsonb(s));return to_jsonb(s);
 end if;
 if p_action='track' then
  select * into o from tkt_private.food_orders where id=(p_data->>'id')::uuid;
  if not found then raise exception 'ORDER_UNAVAILABLE';end if;
  select * into strict r from tkt_private.restaurants where id=o.restaurant_id;
  if u<>o.customer_id and u<>r.owner_id and u is distinct from o.captain_id then raise exception 'PERMISSION_DENIED';end if;
  return jsonb_build_object('order',to_jsonb(o),'restaurant',jsonb_build_object('name',r.name,'location',r.location,'phone',r.phone),'customer',jsonb_build_object('location',o.customer_location),
   'captain',(select jsonb_build_object('name',p.name,'phone',p.phone,'location',case when o.status in('accepted','heading','picked_up') and p.location_at>clock_timestamp()-interval '90 seconds' then jsonb_build_array(p.lat,p.lng) end,'location_at',p.location_at) from public.tkt_profiles p where p.user_id=o.captain_id),
   'geometry',(select geometry from public.tkt_quotes where id=o.quote_id),'server_now',clock_timestamp());
 end if;
 if p_action='restaurants' then return coalesce((select jsonb_agg(to_jsonb(x) order by x.name) from tkt_private.restaurants x where x.open and tkt_private.company_debt(x.owner_id,'restaurant_fee')<s.restaurant_debt_limit),'[]');end if;
 if p_action='restaurant_save' then
  if exists(select 1 from public.tkt_profiles where user_id=u and captain) then raise exception 'ROLE_CONFLICT';end if;
  if length(btrim(coalesce(p_data->>'name','')))<2 or length(btrim(coalesce(p_data->>'phone','')))<10 or length(btrim(coalesce(p_data->>'address','')))<3 or jsonb_array_length(p_data->'location')<>2 or p_data->'location' is null then raise exception 'FIELDS_REQUIRED';end if;
  if (p_data->'location'->>0)::numeric not between 29 and 38 or (p_data->'location'->>1)::numeric not between 38 and 49 then raise exception 'OUTSIDE_SERVICE';end if;
  if coalesce(p_data->>'image_path','')='' or not exists(select 1 from storage.objects where bucket_id='restaurant-images' and name=p_data->>'image_path' and split_part(name,'/',1)=u::text) then raise exception 'FIELDS_REQUIRED';end if;
  insert into tkt_private.restaurants(owner_id,name,phone,address,description,image_path,location,open) values(u,left(btrim(p_data->>'name'),160),left(p_data->>'phone',30),left(p_data->>'address',500),left(coalesce(p_data->>'description',''),2000),coalesce(p_data->>'image_path',''),p_data->'location',coalesce((p_data->>'open')::boolean,true))
  on conflict(owner_id) do update set name=excluded.name,phone=excluded.phone,address=excluded.address,description=excluded.description,image_path=excluded.image_path,location=excluded.location,open=excluded.open returning * into r;
  return to_jsonb(r);
 end if;
 rid:=nullif(p_data->>'restaurant_id','')::uuid;
 if p_action='menu' then
  select * into r from tkt_private.restaurants where id=rid;
  if not found or not r.open and r.owner_id<>u then raise exception 'RESTAURANT_UNAVAILABLE';end if;
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.sort_order,x.name) from tkt_private.restaurant_items x where restaurant_id=rid and (available or r.owner_id=u)),'[]');
 end if;
 if p_action='item_save' then
  select * into r from tkt_private.restaurants where owner_id=u;
  if not found then raise exception 'RESTAURANT_REQUIRED';end if;
  ident:=coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid());
  if exists(select 1 from tkt_private.restaurant_items where id=ident and restaurant_id<>r.id) then raise exception 'PERMISSION_DENIED';end if;
  insert into tkt_private.restaurant_items(id,restaurant_id,name,description,price,image_path,available,sort_order)
   values(ident,r.id,btrim(p_data->>'name'),left(coalesce(p_data->>'description',''),2000),(p_data->>'price')::integer,coalesce(p_data->>'image_path',''),coalesce((p_data->>'available')::boolean,true),coalesce((p_data->>'sort_order')::integer,0))
   on conflict(id) do update set name=excluded.name,description=excluded.description,price=excluded.price,image_path=excluded.image_path,available=excluded.available,sort_order=excluded.sort_order returning * into i;return to_jsonb(i);
 end if;
 if p_action='order_create' then
  perform pg_advisory_xact_lock(hashtextextended(u::text,9041));
  select * into o from tkt_private.food_orders where customer_id=u and request_id=(p_data->>'request_id')::uuid;
  if found then return to_jsonb(o);end if;
  if exists(select 1 from tkt_private.restaurants where owner_id=u) or exists(select 1 from public.tkt_profiles where user_id=u and captain) then raise exception 'ROLE_CONFLICT';end if;
  select * into strict r from tkt_private.restaurants where id=rid and open for share;
  if tkt_private.company_debt(r.owner_id,'restaurant_fee')>=s.restaurant_debt_limit then raise exception 'RESTAURANT_DEBT_LIMIT';end if;
  select * into q from public.tkt_quotes where id=(p_data->>'quote_id')::uuid and user_id=u for update;
  if not found or q.expires_at<=clock_timestamp() or q.pickup<>r.location or q.round_trip or q.change_ride_id is not null then raise exception 'QUOTE_EXPIRED';end if;
  if exists(select 1 from public.tkt_rides where quote_id=q.id) then raise exception 'QUOTE_USED';end if;
  if jsonb_typeof(p_data->'items')<>'array' or jsonb_array_length(p_data->'items') not between 1 and 100 or p_data->'items' is null then raise exception 'BASKET_REQUIRED';end if;
  for item in select value from jsonb_array_elements(p_data->'items') loop
   qty:=(item->>'quantity')::integer;
   if qty is null or qty not between 1 and 99 then raise exception 'INVALID_QUANTITY';end if;
   select * into i from tkt_private.restaurant_items where id=(item->>'id')::uuid and restaurant_id=rid and available for share;
   if not found or i.id=any(coalesce(ids,array[]::uuid[])) then raise exception 'ITEM_UNAVAILABLE';end if;
   ids:=array_append(ids,i.id);total:=total+i.price*qty;
   basket:=basket||jsonb_build_array(jsonb_build_object('id',i.id,'name',i.name,'price',i.price,'quantity',qty));
  end loop;
  if (p_data->>'expected_service_fee')::integer is distinct from s.service_fee then raise exception 'QUOTE_EXPIRED';end if;
  if total>10000000 or length(btrim(coalesce(p_data->>'customer_address','')))<3 then raise exception 'FIELDS_REQUIRED';end if;
  insert into tkt_private.food_orders(request_id,customer_id,restaurant_id,quote_id,items,food_total,delivery_fee,service_fee,commission_percent,customer_address,customer_location)
   values((p_data->>'request_id')::uuid,u,rid,q.id,basket,total,q.fare,s.service_fee,s.commission_percent,left(p_data->>'customer_address',500),q.destination) returning * into o;
  perform tkt_private.notification_add(r.owner_id,'food:'||o.id||':pending','food','طلب طعام جديد','وصل طلب طعام جديد؛ افتح لوحة المطعم لقبوله.',jsonb_build_object('screen','food','order_id',o.id));return to_jsonb(o);
 end if;
 if p_action='orders' then
  return coalesce((select jsonb_agg(j order by j->>'created_at' desc) from (
   select to_jsonb(x)||jsonb_build_object('restaurant_name',z.name,'restaurant_phone',z.phone,'restaurant_address',z.address,'restaurant_location',z.location,'captain_name',p.name,'captain_phone',p.phone,'customer_phone',case when x.status<>'searching' or x.customer_id=u or z.owner_id=u then cp.phone end)
    as j from tkt_private.food_orders x join tkt_private.restaurants z on z.id=x.restaurant_id left join public.tkt_profiles p on p.user_id=x.captain_id join public.tkt_profiles cp on cp.user_id=x.customer_id
   where x.customer_id=u or z.owner_id=u or x.captain_id=u or (x.status='searching' and z.owner_id<>u and tkt_private.company_debt(u,'captain_company')<s.captain_debt_limit and exists(select 1 from public.tkt_profiles k left join tkt_private.captain_plans pl on pl.user_id=k.user_id where k.user_id=u and k.captain and k.online and not k.blocked and k.location_at>clock_timestamp()-interval '90 seconds' and tkt_private.km((z.location->>0)::float8,(z.location->>1)::float8,k.lat,k.lng)<=5 and (pl.plan='commission' or k.expires_at>clock_timestamp()) and coalesce(pl.vehicle,'tuktuk')=x.vehicle) and not exists(select 1 from public.tkt_rides where captain_id=u and status in('accepted','arrived','in_progress')) and not exists(select 1 from tkt_private.food_orders where captain_id=u and status in('accepted','heading','picked_up')))
   order by x.created_at desc limit 200) a),'[]');
 end if;
 if p_action='order_update' then
  ident:=(p_data->>'id')::uuid;next_status:=p_data->>'status';
  select * into o from tkt_private.food_orders where id=ident for update;
  if not found then raise exception 'ORDER_UNAVAILABLE';end if;
  select * into strict r from tkt_private.restaurants where id=o.restaurant_id;
  if next_status='accepted' then
   if tkt_private.company_debt(u,'captain_company')>=s.captain_debt_limit then raise exception 'CAPTAIN_DEBT_LIMIT';end if;
   select * into c from public.tkt_profiles where user_id=u for update;
   if o.status<>'searching' or not c.captain or not c.online or c.blocked or c.location_at is null or c.location_at<clock_timestamp()-interval '90 seconds' or r.owner_id=u then raise exception 'OFFER_EXPIRED';end if;
   if not exists(select 1 from tkt_private.captain_plans where user_id=u and plan='commission') and coalesce(c.expires_at<=clock_timestamp(),true) then raise exception 'CAPTAIN_SUBSCRIPTION_REQUIRED';end if;
   if tkt_private.km((r.location->>0)::float8,(r.location->>1)::float8,c.lat,c.lng)>5 or c.lat is null or c.lng is null then raise exception 'CAPTAIN_UNAVAILABLE';end if;
   if coalesce((select vehicle from tkt_private.captain_plans where user_id=u),'tuktuk')<>o.vehicle then raise exception 'VEHICLE_MISMATCH';end if;
   if exists(select 1 from public.tkt_rides where captain_id=u and status in('accepted','arrived','in_progress')) or exists(select 1 from tkt_private.food_orders where captain_id=u and status in('accepted','heading','picked_up')) then raise exception 'CAPTAIN_BUSY';end if;
   o.captain_id:=u;
   o.commission_amount:=case when exists(select 1 from tkt_private.captain_plans where user_id=u and plan='commission') then round(o.delivery_fee*o.commission_percent/100)::integer else 0 end;
  elsif r.owner_id=u then
   if o.status='pending' and next_status='preparing' and tkt_private.company_debt(u,'restaurant_fee')>=s.restaurant_debt_limit then raise exception 'RESTAURANT_DEBT_LIMIT';end if;
   if not ((o.status='pending' and next_status in('preparing','rejected')) or (o.status='preparing' and next_status='searching') or (o.status in('preparing','searching') and next_status='rejected')) then raise exception 'INVALID_TRANSITION';end if;
   if next_status='searching' then
    v:=p_data->>'vehicle';if v is null or v not in('tuktuk','bike') then raise exception 'VEHICLE_REQUIRED';end if;o.vehicle:=v;
   end if;
  elsif o.customer_id=u and o.status='pending' and next_status='rejected' then
   null;
  elsif o.captain_id=u then
   if not ((o.status='accepted' and next_status='heading') or (o.status='heading' and next_status='picked_up') or (o.status='picked_up' and next_status in('delivered','rejected')) or (o.status in('accepted','heading') and next_status='rejected')) then raise exception 'INVALID_TRANSITION';end if;
  else raise exception 'PERMISSION_DENIED';end if;
  if next_status='rejected' then
   o.reason:=btrim(coalesce(p_data->>'reason',''));if length(o.reason) not between 3 and 1000 then raise exception 'REASON_REQUIRED';end if;
  end if;
  update tkt_private.food_orders set status=next_status,captain_id=o.captain_id,vehicle=o.vehicle,commission_amount=o.commission_amount,reason=o.reason,updated_at=clock_timestamp() where id=ident returning * into o;
  body:=case next_status when 'preparing' then 'المطعم وافق على طلبك؛ طلبك قيد التحضير' when 'searching' then 'جار البحث عن مندوب توصيل إليك' when 'accepted' then 'وافق المندوب على طلبك؛ افتح الطلب لعرض معلوماته' when 'heading' then 'المندوب متوجه للمطعم' when 'picked_up' then 'استلم المندوب طلبك وهو بالطريق إليك' when 'delivered' then 'تم توصيل طلبك' else 'تم رفض الطلب: '||o.reason end;
  perform tkt_private.notification_add(o.customer_id,'food:'||o.id||':'||next_status,'food','طلب الطعام',body,jsonb_build_object('screen','food','order_id',o.id));
  perform tkt_private.notification_add(r.owner_id,'food:'||o.id||':'||next_status,'food','حالة طلب الطعام',body,jsonb_build_object('screen','food','order_id',o.id));
  if next_status='searching' then
   for c in select p.* from public.tkt_profiles p left join tkt_private.captain_plans pl on pl.user_id=p.user_id where tkt_private.captain_eligible(p.user_id,false) and p.captain and p.online and not p.blocked and tkt_private.km((r.location->>0)::float8,(r.location->>1)::float8,p.lat,p.lng)<=5 and p.location_at>clock_timestamp()-interval '90 seconds' and coalesce(pl.vehicle,'tuktuk')=o.vehicle and (pl.plan='commission' or p.expires_at>clock_timestamp()) and not exists(select 1 from public.tkt_rides where captain_id=p.user_id and status in('accepted','arrived','in_progress')) and not exists(select 1 from tkt_private.food_orders where captain_id=p.user_id and status in('accepted','heading','picked_up')) loop
    perform tkt_private.notification_add(c.user_id,'food-offer:'||o.id,'food','طلب توصيل طعام','عندك طلب توصيل طعام؛ افتح طلبات الطعام لعرضه.',jsonb_build_object('screen','food','order_id',o.id));
   end loop;
  end if;
  return to_jsonb(o);
 end if;
 if p_action='accounts' then
  return jsonb_build_object('statistics',coalesce((select jsonb_agg(to_jsonb(v)) from(select x.restaurant_id,x.captain_id,count(*)filter(where x.status='delivered') as delivered,count(*)filter(where x.status='rejected') as rejected from tkt_private.food_orders x join tkt_private.restaurants z on z.id=x.restaurant_id where x.captain_id=u or z.owner_id=u group by x.restaurant_id,x.captain_id)v),'[]'),'debts',coalesce((select jsonb_agg(to_jsonb(d)||jsonb_build_object('restaurant_name',r.name,'restaurant_phone',r.phone,'restaurant_address',r.address,'captain_name',p.name,'captain_phone',p.phone)) from tkt_private.commerce_debts d left join tkt_private.restaurants r on r.id=d.restaurant_id join public.tkt_profiles p on p.user_id=d.debtor_id where d.debtor_id=u or d.creditor_id=u),'[]'),
   'settlements',coalesce((select jsonb_agg(to_jsonb(x)-'code_hash' order by x.created_at desc) from tkt_private.commerce_settlements x where debtor_id=u or creditor_id=u),'[]'));
 end if;
 if p_action='settlement_request' then
  kind:=p_data->>'kind';target:=u;
  if kind='captain_restaurant' then
   select * into r from tkt_private.restaurants where owner_id=u;
   if not found then raise exception 'RESTAURANT_REQUIRED';end if;
   rid:=r.id;target:=(p_data->>'captain_id')::uuid;
  elsif kind='restaurant_fee' then
   select * into r from tkt_private.restaurants where owner_id=u;
   if not found then raise exception 'RESTAURANT_REQUIRED';end if;rid:=r.id;
  elsif kind='captain_company' then rid:=null;
  else raise exception 'INVALID_KIND';end if;
  perform pg_advisory_xact_lock(hashtextextended(target::text||kind||coalesce(rid::text,''),821));
  update tkt_private.commerce_settlements set status='expired' where debtor_id=target and kind=accounting.kind and restaurant_id is not distinct from rid and status='pending' and expires_at<clock_timestamp();
  select * into st from tkt_private.commerce_settlements x where x.debtor_id=target and x.kind=accounting.kind and x.restaurant_id is not distinct from rid and status='pending';
  if found then
   if kind='captain_restaurant' then
    code:=lpad((floor(random()*1000000))::text,6,'0');
    update tkt_private.commerce_settlements set code_hash=sha256(convert_to(code,'UTF8')),attempts=0,expires_at=clock_timestamp()+interval '15 minutes' where id=st.id returning * into st;
   end if;
   return (to_jsonb(st)-'code_hash')||jsonb_build_object('code',code);
  end if;
  select array_agg(d.id),sum(d.amount) into ids,due from tkt_private.commerce_debts d where d.debtor_id=target and d.kind=accounting.kind and (rid is null or d.restaurant_id=rid) and d.settled_at is null and d.amount>0;
  if coalesce(due,0)=0 then raise exception 'NOTHING_DUE';end if;
  if kind='captain_restaurant' then code:=lpad((floor(random()*1000000))::text,6,'0');end if;
  insert into tkt_private.commerce_settlements(kind,debtor_id,creditor_id,restaurant_id,amount,code_hash,expires_at)
  values(kind,target,case when kind='captain_restaurant' then u end,rid,due,case when code is not null then sha256(convert_to(code,'UTF8')) end,case when code is not null then clock_timestamp()+interval '15 minutes' end) returning * into st;
  delete from tkt_private.commerce_settlement_items x using tkt_private.commerce_settlements z where z.id=x.settlement_id and z.status='expired' and x.debt_id=any(ids);
  insert into tkt_private.commerce_settlement_items(settlement_id,debt_id) select st.id,unnest(ids);
  return (to_jsonb(st)-'code_hash')||jsonb_build_object('code',code);
 end if;
 if p_action='settlement_confirm' then
  select * into st from tkt_private.commerce_settlements where id=(p_data->>'id')::uuid for update;
  if not found then raise exception 'SETTLEMENT_UNAVAILABLE';end if;
  if st.kind='captain_restaurant' then
   if st.debtor_id<>u then raise exception 'PERMISSION_DENIED';end if;
   if st.status='confirmed' then return jsonb_build_object('ok',true);end if;
   if st.status<>'pending' or st.expires_at<=clock_timestamp() or st.attempts>=5 then raise exception 'CODE_EXPIRED';end if;
   if st.code_hash is distinct from sha256(convert_to(coalesce(p_data->>'code',''),'UTF8')) then
    update tkt_private.commerce_settlements set attempts=attempts+1 where id=st.id;
    return jsonb_build_object('ok',false,'error','INVALID_CODE');
   end if;
  else
   perform tkt_private.require_dashboard('finance',true);
   if st.status='confirmed' then return jsonb_build_object('ok',true);end if;
   if st.status<>'pending' then raise exception 'SETTLEMENT_UNAVAILABLE';end if;
   if (p_data->>'confirmed_amount')::bigint is distinct from st.amount then raise exception 'AMOUNT_CHANGED';end if;
  end if;
  update tkt_private.commerce_debts d set settled_at=clock_timestamp(),settlement_id=st.id where d.id in(select debt_id from tkt_private.commerce_settlement_items where settlement_id=st.id) and d.settled_at is null;
  update tkt_private.commerce_settlements set status='confirmed',confirmed_at=clock_timestamp(),confirmed_by=u where id=st.id;
  insert into tkt_private.admin_audit(actor_id,action,entity_id,details) values(u,'commerce_settlement',st.id::text,jsonb_build_object('amount',st.amount,'kind',st.kind));
  return jsonb_build_object('ok',true);
 end if;
 if p_action='complaint' then
  select * into strict r from tkt_private.restaurants where owner_id=u;
  target:=(p_data->>'captain_id')::uuid;
  if not exists(select 1 from tkt_private.food_orders where restaurant_id=r.id and captain_id=target) then raise exception 'PERMISSION_DENIED';end if;
  insert into tkt_private.restaurant_complaints(restaurant_id,captain_id,body) values(r.id,target,btrim(p_data->>'body'));return jsonb_build_object('ok',true);
 end if;
 if p_action='admin' then
  perform tkt_private.require_dashboard('finance',false);
  return jsonb_build_object('settings',to_jsonb(s),'settlements',coalesce((select jsonb_agg(to_jsonb(x)-'code_hash' order by x.created_at desc) from tkt_private.commerce_settlements x where status='pending'),'[]'),
  'debts',coalesce((select jsonb_agg(to_jsonb(d)||jsonb_build_object('name',p.name,'phone',p.phone)) from tkt_private.commerce_debts d join public.tkt_profiles p on p.user_id=d.debtor_id where settled_at is null),'[]'));
 end if;
 if p_action='complaints' then
  perform tkt_private.require_dashboard('support',false);
  return coalesce((select jsonb_agg(to_jsonb(x)||jsonb_build_object('restaurant_name',r.name,'captain_name',p.name,'captain_phone',p.phone) order by x.created_at desc) from tkt_private.restaurant_complaints x join tkt_private.restaurants r on r.id=x.restaurant_id join public.tkt_profiles p on p.user_id=x.captain_id),'[]');
 end if;
 if p_action='complaint_handle' then
  perform tkt_private.require_dashboard('support',true);update tkt_private.restaurant_complaints set status='handled' where id=(p_data->>'id')::uuid;return jsonb_build_object('ok',true);
 end if;
 raise exception 'UNKNOWN_ACTION';
end $$;
revoke all on function tkt_private.food_order_accounting(),tkt_private.taxi_commission(),tkt_private.commerce(text,jsonb) from public,anon,authenticated;
grant execute on function tkt_private.commerce(text,jsonb) to authenticated;
create or replace function public.tkt_commerce(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select tkt_private.commerce(p_action,p_data)$$;
revoke all on function public.tkt_commerce(text,jsonb) from public,anon;
grant execute on function public.tkt_commerce(text,jsonb) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('restaurant-images','restaurant-images',true,10485760,array['image/jpeg','image/png']) on conflict(id) do nothing;
create policy restaurant_image_insert on storage.objects for insert to authenticated with check(bucket_id='restaurant-images' and split_part(name,'/',1)=(select auth.uid())::text and exists(select 1 from public.tkt_profiles where user_id=(select auth.uid()) and not blocked));
create policy restaurant_image_read on storage.objects for select to authenticated using(bucket_id='restaurant-images');

alter table public.tkt_captain_applications add column if not exists work_plan text not null default 'weekly' check(work_plan in('weekly','commission')), add column if not exists vehicle_kind text not null default 'tuktuk' check(vehicle_kind in('tuktuk','bike'));
create or replace function tkt_private.captain_registration(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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
  if exists(select 1 from public.tkt_admins where user_id=target)then raise exception 'PROTECTED_ADMIN';end if;
  decision:=p_data->>'decision';why:=btrim(coalesce(p_data->>'reason',''));
  if decision not in('approved','changes_required') or decision is null then raise exception 'INVALID_DECISION';end if;
  if decision='changes_required' and length(why) not between 3 and 2000 then raise exception 'REASON_REQUIRED';end if;
  if decision='approved'then
   if not exists(select 1 from public.tkt_profiles where user_id=target and not blocked)then raise exception 'ACCOUNT_BLOCKED';end if;
   if exists(select 1 from public.tkt_rides where (rider_id=target or captain_id=target)and status in('pending','accepted','arrived','in_progress'))then raise exception 'ACTIVE_RIDE';end if;
   insert into tkt_private.captain_plans(user_id,plan,vehicle)values(target,a.work_plan,a.vehicle_kind)on conflict(user_id)do update set plan=excluded.plan,vehicle=excluded.vehicle;
   perform set_config('taktooka.reviewing_captain',target::text,true);
   update public.tkt_profiles set captain=true,online=false,name=a.full_name where user_id=target;
  end if;
  update public.tkt_captain_applications set status=decision,reason=case when decision='approved'then '' else why end,reviewed_by=u,reviewed_at=clock_timestamp(),updated_at=clock_timestamp()where user_id=target returning * into a;
  update tkt_private.preferences set captain_requested_at=null where user_id=target;
  insert into tkt_private.admin_audit(actor_id,action,entity_id,details)values(u,'captain_'||decision,target::text,jsonb_build_object('revision',a.revision,'status',decision));
  insert into public.tkt_messages(user_id,sender_id,is_admin,body)values(target,u,true,case when decision='approved'then 'تمت الموافقة على تسجيلك ككابتن؛ حساب الكابتن متاح الآن.'else 'طلب تسجيل الكابتن يحتاج تعديل: '||why end);
  return to_jsonb(a);
 end if;
 if exists(select 1 from tkt_private.restaurants where owner_id=u) then raise exception 'ROLE_CONFLICT';end if;
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
  if p_data ? 'work_plan' then a.work_plan:=p_data->>'work_plan';end if;
  if p_data ? 'vehicle_kind' then a.vehicle_kind:=p_data->>'vehicle_kind';end if;
  if a.work_plan not in('weekly','commission') or a.vehicle_kind not in('tuktuk','bike') then raise exception 'INVALID_FIELDS';end if;
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
   slot:=p_data->>'pending_slot';if slot is not null and slot not in('id_front','id_back','residence_front','residence_back')then raise exception 'INVALID_DOCUMENT';end if;a.pending_slot:=slot;
  end if;
  if p_data ? 'document'then
   slot:=p_data->'document'->>'slot';path:=p_data->'document'->>'path';
   if slot is null or slot not in('id_front','id_back','residence_front','residence_back')or path is null or split_part(path,'/',1)<>u::text or not exists(select 1 from storage.objects where bucket_id='captain-documents'and name=path)then raise exception 'INVALID_DOCUMENT';end if;
   a.documents:=jsonb_set(a.documents,array[slot],to_jsonb(path),true);a.pending_slot:=null;
  end if;
 else
  if cardinality(regexp_split_to_array(btrim(a.full_name),'\s+'))<3 or length(a.full_name)<5 then raise exception 'FULL_NAME_REQUIRED';end if;
  if a.phone='' or a.phone is distinct from (select tkt_private.normalize_phone(phone)from public.tkt_profiles where user_id=u)then raise exception 'ACCOUNT_PHONE_REQUIRED';end if;
  if a.province='' or a.area='' then raise exception 'AREA_REQUIRED';end if;
  foreach slot in array case when a.work_plan='weekly' then array['id_front','id_back','residence_front','residence_back'] else array['id_front','id_back'] end loop
   path:=a.documents->>slot;
   if path is null or not exists(select 1 from storage.objects where bucket_id='captain-documents'and name=path and split_part(name,'/',1)=u::text)then raise exception 'DOCUMENTS_REQUIRED';end if;
  end loop;
  a.status:='pending';a.reason:='';a.revision:=a.revision+1;a.submitted_at:=clock_timestamp();a.reviewed_at:=null;a.reviewed_by:=null;a.pending_slot:=null;
  insert into tkt_private.preferences(user_id,captain_requested_at)values(u,clock_timestamp())on conflict(user_id)do update set captain_requested_at=excluded.captain_requested_at;
 end if;
 update public.tkt_captain_applications set work_plan=a.work_plan,vehicle_kind=a.vehicle_kind,province=a.province,area=a.area,verification=a.verification,full_name=a.full_name,phone=a.phone,chassis=a.chassis,color=a.color,model=a.model,documents=a.documents,pending_slot=a.pending_slot,status=a.status,reason=a.reason,revision=a.revision,submitted_at=a.submitted_at,reviewed_at=a.reviewed_at,reviewed_by=a.reviewed_by,updated_at=clock_timestamp()where user_id=u returning * into a;
 return to_jsonb(a);
end $$;

do $$
declare fn record;definition text;
begin
 for fn in select p.oid,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='tkt_private' and p.proname in('dispatch','dispatch_v1','dispatch_worker','dispatch_maintenance','action','legacy_action') loop
  definition:=pg_get_functiondef(fn.oid);
  definition:=replace(definition,'p.expires_at>clock_timestamp()','tkt_private.captain_eligible(p.user_id,true)');
  definition:=replace(definition,'p.expires_at>now()','tkt_private.captain_eligible(p.user_id,true)');
  definition:=replace(definition,'and expires_at>now() and location_at>','and tkt_private.captain_eligible(p.user_id,true) and location_at>');
  definition:=replace(definition,'coalesce(cc.expires_at,clock_timestamp())<=clock_timestamp()',
   '(not tkt_private.captain_eligible(cc.user_id,false) and not exists(select 1 from tkt_private.food_orders where captain_id=cc.user_id and status in(''accepted'',''heading'',''picked_up'')))');
  definition:=replace(definition,'coalesce(me.expires_at,now())<=now()',
   '(not tkt_private.captain_eligible(me.user_id,false) and not exists(select 1 from tkt_private.food_orders where captain_id=me.user_id and status in(''accepted'',''heading'',''picked_up'')))');
  execute definition;
 end loop;
end $$;

create or replace function tkt_private.block_commission_lines() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.captain_id is not null and (TG_OP='INSERT' or new.captain_id is distinct from old.captain_id or new.status is distinct from old.status) and new.status='accepted' then
  if exists(select 1 from tkt_private.captain_plans where user_id=new.captain_id and (plan='commission' or vehicle='bike')) then raise exception 'CAPTAIN_SUBSCRIPTION_REQUIRED';end if;
 end if;
 return new;
end $$;
revoke all on function tkt_private.block_commission_lines() from public,anon,authenticated;
drop trigger if exists block_commission_lines on tkt_private.lines;
create trigger block_commission_lines before insert or update on tkt_private.lines for each row execute function tkt_private.block_commission_lines();

create or replace function tkt_private.guard_captain_application() returns trigger language plpgsql security definer set search_path='' as $$begin if new.captain and not old.captain and exists(select 1 from public.tkt_captain_applications where user_id=new.user_id and status<>'approved')then if not tkt_private.dashboard_permission('applications',true) or current_setting('taktooka.reviewing_captain',true) is distinct from new.user_id::text then raise exception 'USE_VEHICLE_REGISTRATION';end if;end if;return new;end$$;revoke all on function tkt_private.guard_captain_application() from public,anon,authenticated;

commit;
