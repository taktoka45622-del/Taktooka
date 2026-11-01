create table if not exists tkt_private.food_offer_declines(order_id uuid not null references tkt_private.food_orders(id) on delete cascade,user_id uuid not null references public.tkt_profiles(user_id) on delete cascade,round_at timestamptz not null,primary key(order_id,user_id,round_at));
alter table tkt_private.food_offer_declines enable row level security;
revoke all on tkt_private.food_offer_declines from public,anon,authenticated;
create or replace function tkt_private.food_offer_active(oid uuid,round_at timestamptz,recipient uuid) returns boolean language sql stable set search_path='' as $f$
select exists(select 1 from public.tkt_notifications n where n.user_id=recipient and n.kind='food' and n.target->>'request_type'='courier' and n.target->>'offer_id'='f:'||oid::text||':c:'||floor(extract(epoch from round_at)*1000000)::bigint::text and n.expires_at>clock_timestamp()) and not exists(select 1 from tkt_private.food_offer_declines d where d.order_id=oid and d.user_id=recipient and d.round_at=food_offer_active.round_at)
$f$;
revoke all on function tkt_private.food_offer_active(uuid,timestamptz,uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION tkt_private.commerce(p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
<<accounting>>
declare
 u uuid:=auth.uid();r tkt_private.restaurants;i tkt_private.restaurant_items;o tkt_private.food_orders;
 s tkt_private.commerce_settings;q public.tkt_quotes;c public.tkt_profiles;st tkt_private.commerce_settlements;
 rid uuid;ident uuid;owner uuid;target uuid;kind text;v text;code text;body text;next_status text;
 item jsonb;basket jsonb:='[]';total bigint:=0;qty integer;ids uuid[];result jsonb;cfg jsonb;chosen jsonb;additions jsonb;opt jsonb;unit_price integer;size_id text;addon_ids text[];note text;due bigint;area_lat double precision;area_lng double precision;
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 if not exists(select 1 from public.tkt_profiles where user_id=u and not blocked and deleted_at is null) then raise exception 'ACCOUNT_BLOCKED';end if;
 select * into strict s from tkt_private.commerce_settings where id;


 if p_action='favorites' then
  return coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'name',r.name,'image_path',r.image_path,'address',r.address,'location',r.location,'open',r.open,'closing_time',r.closing_time) order by f.created_at desc) from tkt_private.restaurant_favorites f join tkt_private.restaurants r on r.id=f.restaurant_id where f.user_id=u),'[]');
 end if;
 if p_action='favorite_set' then
  rid:=(p_data->>'restaurant_id')::uuid;
  if not exists(select 1 from tkt_private.restaurants where id=rid) then raise exception 'RESTAURANT_UNAVAILABLE';end if;
  if (p_data->>'saved')::boolean then insert into tkt_private.restaurant_favorites(user_id,restaurant_id)values(u,rid)on conflict do nothing;
  else delete from tkt_private.restaurant_favorites where user_id=u and restaurant_id=rid;end if;
  return jsonb_build_object('saved',coalesce((p_data->>'saved')::boolean,false));
 end if;
 if p_action in ('category_options','category_options_save') then
  select * into r from tkt_private.restaurants where owner_id=u for update;
  if not found then raise exception 'PERMISSION_DENIED';end if;
  v:=btrim(p_data->>'category');if v is null or length(v) not between 1 and 80 then raise exception 'FIELDS_REQUIRED';end if;
  if p_action='category_options_save' then
   cfg:=tkt_private.food_validate_options(jsonb_build_object('sizes','[]'::jsonb,'addons',p_data->'addons'),u);
   insert into tkt_private.food_option_templates(restaurant_id,category,addons)values(r.id,v,cfg->'addons')on conflict(restaurant_id,category)do update set addons=excluded.addons;
  end if;
  return jsonb_build_object('addons',coalesce((select addons from tkt_private.food_option_templates where restaurant_id=r.id and category=v),'[]'::jsonb));
 end if;
 if p_action='restaurant_open' then update tkt_private.restaurants set open=(p_data->>'open')::boolean where owner_id=u returning * into r;if not found then raise exception 'PERMISSION_DENIED';end if;if not r.open then perform tkt_private.food_requests_stop(null,'restaurant',u);end if;return to_jsonb(r);end if;
 if p_action='items_reorder' then
  select * into strict r from tkt_private.restaurants where owner_id=u for update;
  if jsonb_typeof(p_data->'ids') is distinct from 'array' then raise exception 'FIELDS_REQUIRED';end if;
  if jsonb_array_length(p_data->'ids') not between 1 and 1000 then raise exception 'FIELDS_REQUIRED';end if;
  if (select count(distinct value) from jsonb_array_elements_text(p_data->'ids'))<>jsonb_array_length(p_data->'ids') or exists(select 1 from jsonb_array_elements_text(p_data->'ids') x(id) where not exists(select 1 from tkt_private.restaurant_items i where i.id=x.id::uuid and i.restaurant_id=r.id)) then raise exception 'PERMISSION_DENIED';end if;
  update tkt_private.restaurant_items i set sort_order=x.ord::int-1 from jsonb_array_elements_text(p_data->'ids') with ordinality x(id,ord) where i.id=x.id::uuid and i.restaurant_id=r.id;
  return jsonb_build_object('ok',true);
 end if;
 if p_action='categories' then select * into strict r from tkt_private.restaurants where owner_id=u;return r.menu_categories||coalesce((select jsonb_agg(distinct category) from tkt_private.restaurant_items where restaurant_id=r.id),'[]');end if;
 if p_action='category_save' then select * into strict r from tkt_private.restaurants where owner_id=u for update;v:=btrim(p_data->>'name');if v is null or length(v) not between 1 and 80 then raise exception 'FIELDS_REQUIRED';end if;if jsonb_array_length(r.menu_categories)>=100 and not r.menu_categories ? v then raise exception 'CATEGORY_LIMIT';end if;if nullif(p_data->>'old_name','') is not null then update tkt_private.restaurant_items set category=v where restaurant_id=r.id and category=p_data->>'old_name';insert into tkt_private.food_option_templates(restaurant_id,category,addons)select restaurant_id,v,addons from tkt_private.food_option_templates where restaurant_id=r.id and category=p_data->>'old_name' on conflict(restaurant_id,category)do nothing;delete from tkt_private.food_option_templates where restaurant_id=r.id and category=p_data->>'old_name' and category<>v;r.menu_categories:=coalesce((select jsonb_agg(value) from jsonb_array_elements_text(r.menu_categories) x(value) where value<>p_data->>'old_name'),'[]');end if;if not r.menu_categories ? v then r.menu_categories:=r.menu_categories||jsonb_build_array(v);end if;update tkt_private.restaurants set menu_categories=r.menu_categories where id=r.id;return jsonb_build_object('ok',true);end if;
 if p_action='food_quote' then select * into q from public.tkt_quotes where id=(p_data->>'quote_id')::uuid and user_id=u;if not found or q.expires_at<=clock_timestamp() then raise exception 'QUOTE_EXPIRED';end if;return to_jsonb(q)||jsonb_build_object('fare',tkt_private.food_delivery_fare(q.distance_m));end if;
 if p_action='catalog' then
  result:=tkt_private.commerce('restaurants',p_data);
  return coalesce((select jsonb_agg(payload order by popularity desc,price,id) from (select to_jsonb(m)||jsonb_build_object('restaurant_name',rj->>'name','restaurant_id',rj->>'id','restaurant_image',rj->>'image_path','order_count',coalesce((select sum((li->>'quantity')::integer) from tkt_private.food_orders fo cross join lateral jsonb_array_elements(fo.items) li where fo.status='delivered' and fo.created_at>clock_timestamp()-interval '30 days' and li->>'id'=m.id::text),0)) as payload,coalesce((select sum((li->>'quantity')::integer) from tkt_private.food_orders fo cross join lateral jsonb_array_elements(fo.items) li where fo.status='delivered' and fo.created_at>clock_timestamp()-interval '30 days' and li->>'id'=m.id::text),0) as popularity,m.price,m.id from jsonb_array_elements(result) rj join tkt_private.restaurant_items m on m.restaurant_id=(rj->>'id')::uuid
   where m.available and (coalesce(p_data->>'category','')='' or m.catalog_category=p_data->>'category') and (coalesce((p_data->>'offers')::boolean,false)=false or m.previous_price>m.price) and (coalesce(p_data->>'search','')='' or m.name ilike '%'||(p_data->>'search')||'%' or rj->>'name' ilike '%'||(p_data->>'search')||'%') and m.price>=coalesce((p_data->>'min_price')::int,0) and m.price<=coalesce((p_data->>'max_price')::int,1000000) order by popularity desc,m.price,m.id limit 100 offset greatest(0,least(100000,coalesce((p_data->>'offset')::int,0)))) x),'[]');end if;
 if p_action='courier_admin_target' then
  select * into strict r from tkt_private.restaurants where owner_id=u;
  if p_data->>'user_id' is not null and not exists(select 1 from tkt_private.restaurant_couriers where user_id=(p_data->>'user_id')::uuid and restaurant_id=r.id) then raise exception 'PERMISSION_DENIED';end if;
  return jsonb_build_object('restaurant_id',r.id,'user_id',p_data->>'user_id');
 end if;
 if p_action='self_delivery_save' then
  update tkt_private.restaurants set self_delivery=(p_data->>'enabled')::boolean where owner_id=u returning * into r;
  if not found then raise exception 'PERMISSION_DENIED';end if;return to_jsonb(r);
 end if;
 if p_action='courier_list' then
  select * into strict r from tkt_private.restaurants where owner_id=u;
  return coalesce((select jsonb_agg(to_jsonb(rc)||jsonb_build_object('name',p.name,'phone',p.phone,
   'due',coalesce((select sum(d.amount) from tkt_private.commerce_debts d where d.debtor_id=rc.user_id and d.restaurant_id=r.id and d.kind='captain_restaurant' and d.settled_at is null),0),
   'delivered', (select count(*) from tkt_private.food_orders fo where fo.captain_id=rc.user_id and fo.restaurant_id=r.id and fo.status='delivered'),
   'cash_collected',coalesce((select sum(fo.food_total+fo.service_fee+fo.delivery_fee) from tkt_private.food_orders fo where fo.captain_id=rc.user_id and fo.restaurant_id=r.id and fo.status='delivered'),0),
   'delivery_total',coalesce((select sum(fo.delivery_fee) from tkt_private.food_orders fo where fo.captain_id=rc.user_id and fo.restaurant_id=r.id and fo.status='delivered'),0),
   'busy',exists(select 1 from tkt_private.food_orders fo where fo.captain_id=rc.user_id and fo.status in('accepted','heading','picked_up')),
   'settlements',coalesce((select jsonb_agg(to_jsonb(st)-'code_hash' order by st.created_at desc) from tkt_private.commerce_settlements st where st.restaurant_id=r.id and st.debtor_id=rc.user_id),'[]')) order by p.name)
  from tkt_private.restaurant_couriers rc join public.tkt_profiles p on p.user_id=rc.user_id where rc.restaurant_id=r.id),'[]');
 end if;
 if p_action='courier_active' then
  select * into strict r from tkt_private.restaurants where owner_id=u;
  target:=(p_data->>'user_id')::uuid;
  if exists(select 1 from tkt_private.food_orders where captain_id=target and status in('accepted','heading','picked_up')) then raise exception 'CAPTAIN_BUSY';end if;
  update tkt_private.restaurant_couriers set active=(p_data->>'active')::boolean,online=false where user_id=target and restaurant_id=r.id;
  if not found then raise exception 'PERMISSION_DENIED';end if;
  if not (p_data->>'active')::boolean then perform tkt_private.food_requests_stop(null,'courier',target);end if;return jsonb_build_object('ok',true);
 end if;
 if p_action='courier_location' then
  if not exists(select 1 from tkt_private.restaurant_couriers where user_id=u) then raise exception 'PERMISSION_DENIED';end if;
  if (p_data->>'online')::boolean then
   if not exists(select 1 from tkt_private.restaurant_couriers where user_id=u and active) then raise exception 'PERMISSION_DENIED';end if;
   if (p_data->>'lat')::numeric not between 29 and 38 or (p_data->>'lng')::numeric not between 38 and 49 or p_data->>'lat' is null or p_data->>'lng' is null then raise exception 'OUTSIDE_SERVICE';end if;
   update tkt_private.restaurant_couriers set lat=(p_data->>'lat')::float8,lng=(p_data->>'lng')::float8,location_at=clock_timestamp(),online=true where user_id=u;
  else update tkt_private.restaurant_couriers set online=false where user_id=u;perform tkt_private.food_requests_stop(null,'courier',u);end if;
  return jsonb_build_object('ok',true);
 end if;
 if p_action='captain_preferences' then
  if not exists(select 1 from public.tkt_profiles where user_id=u and captain and not blocked) then raise exception 'PERMISSION_DENIED';end if;
  insert into tkt_private.captain_plans(user_id) values(u) on conflict do nothing;
  update tkt_private.captain_plans set receive_food=case when vehicle<>'bike' and plan='commission' then false else coalesce((p_data->>'receive_food')::boolean,receive_food) end,receive_rides=case when vehicle='bike' then false else coalesce((p_data->>'receive_rides')::boolean,receive_rides) end where user_id=u;
  if exists(select 1 from tkt_private.captain_plans where user_id=u and not receive_food) then perform tkt_private.food_requests_stop(null,'courier',u);end if;
  return jsonb_build_object('ok',true);
 end if;
 if p_action='me' then return jsonb_build_object('commission_percent',s.commission_percent,'service_fee',s.service_fee,'captain_debt_limit',s.captain_debt_limit,'restaurant_debt_limit',s.restaurant_debt_limit,'food_first_distance_m',s.food_first_distance_m,'food_first_fee',s.food_first_fee,'food_max_distance_m',s.food_max_distance_m,'food_second_fee',s.food_second_fee,'restaurant_min_distance_m',s.restaurant_min_distance_m,'restaurant_max_distance_m',s.restaurant_max_distance_m,
  'receive_food',coalesce((select receive_food and (vehicle='bike' or plan='weekly') from tkt_private.captain_plans where user_id=u),true),
  'receive_rides',coalesce((select receive_rides and vehicle<>'bike' from tkt_private.captain_plans where user_id=u),true),
  'self_courier',(select to_jsonb(rc) from tkt_private.restaurant_couriers rc where rc.user_id=u),
  'plan',coalesce((select plan from tkt_private.captain_plans where user_id=u),'weekly'),
  'vehicle',coalesce((select vehicle from tkt_private.captain_plans where user_id=u),'tuktuk'),
  'company_debt',tkt_private.company_debt(u,case when exists(select 1 from tkt_private.restaurants where owner_id=u) then 'restaurant_fee' else 'captain_company' end),
  'debt_blocked',tkt_private.company_debt(u,case when exists(select 1 from tkt_private.restaurants where owner_id=u) then 'restaurant_fee' else 'captain_company' end)>=case when exists(select 1 from tkt_private.restaurants where owner_id=u) then s.restaurant_debt_limit else s.captain_debt_limit end,
  'food_active',exists(select 1 from tkt_private.food_orders where captain_id=u and status in('accepted','heading','picked_up')),
  'restaurant_stats',(select jsonb_build_object(
    'today_orders',(select count(*) from tkt_private.food_orders f where f.restaurant_id=x.id and f.created_at>=(date_trunc('day',clock_timestamp() at time zone 'Asia/Baghdad') at time zone 'Asia/Baghdad')),
    'today_sales',(select coalesce(sum(f.food_total),0) from tkt_private.food_orders f where f.restaurant_id=x.id and f.status='delivered' and f.updated_at>=(date_trunc('day',clock_timestamp() at time zone 'Asia/Baghdad') at time zone 'Asia/Baghdad'))
  ) from tkt_private.restaurants x where x.owner_id=u),
  'restaurant',(select to_jsonb(x) from tkt_private.restaurants x where owner_id=u));end if;
 if p_action='settings_save' then
  perform tkt_private.require_dashboard('finance',true);
  update tkt_private.commerce_settings set commission_percent=(p_data->>'commission_percent')::numeric,service_fee=(p_data->>'service_fee')::integer,captain_debt_limit=coalesce((p_data->>'captain_debt_limit')::integer,captain_debt_limit),restaurant_debt_limit=coalesce((p_data->>'restaurant_debt_limit')::integer,restaurant_debt_limit),restaurant_min_distance_m=coalesce((p_data->>'restaurant_min_distance_m')::integer,restaurant_min_distance_m),restaurant_max_distance_m=coalesce((p_data->>'restaurant_max_distance_m')::integer,restaurant_max_distance_m),food_first_distance_m=coalesce((p_data->>'food_first_distance_m')::int,food_first_distance_m),food_first_fee=coalesce((p_data->>'food_first_fee')::int,food_first_fee),food_max_distance_m=coalesce((p_data->>'food_max_distance_m')::int,food_max_distance_m),food_second_fee=coalesce((p_data->>'food_second_fee')::int,food_second_fee),updated_at=clock_timestamp() where id returning * into s;
  insert into tkt_private.admin_audit(actor_id,action,details)values(u,'commerce_settings',to_jsonb(s));return to_jsonb(s);
 end if;
 if p_action='track' then
  select * into o from tkt_private.food_orders where id=(p_data->>'id')::uuid;
  if not found then raise exception 'ORDER_UNAVAILABLE';end if;
  select * into strict r from tkt_private.restaurants where id=o.restaurant_id;
  if u<>o.customer_id and u<>r.owner_id and u is distinct from o.captain_id then raise exception 'PERMISSION_DENIED';end if;
  return jsonb_build_object('order',to_jsonb(o),'restaurant',jsonb_build_object('name',r.name,'location',r.location,'phone',r.phone),'customer',jsonb_build_object('location',o.customer_location),
   'captain',(select jsonb_build_object('name',p.name,'phone',p.phone,'location',case when o.status in('accepted','heading','picked_up') and exists(select 1 from tkt_private.restaurant_couriers where user_id=o.captain_id) then (select case when rc.online and rc.location_at>clock_timestamp()-interval '90 seconds' then jsonb_build_array(rc.lat,rc.lng) end from tkt_private.restaurant_couriers rc where rc.user_id=o.captain_id) when o.status in('accepted','heading','picked_up') and p.location_at>clock_timestamp()-interval '90 seconds' then jsonb_build_array(p.lat,p.lng) end,'location_at',coalesce((select location_at from tkt_private.restaurant_couriers where user_id=p.user_id),p.location_at)) from public.tkt_profiles p where p.user_id=o.captain_id),
   'geometry',(select geometry from public.tkt_quotes where id=o.quote_id),'server_now',clock_timestamp());
 end if;
 if p_action='restaurants' then
  if jsonb_typeof(p_data->'location') is distinct from 'array' then return '[]'::jsonb;end if;
  if jsonb_array_length(p_data->'location')<>2 then return '[]'::jsonb;end if;
  if jsonb_typeof(p_data->'location'->0) is distinct from 'number' or jsonb_typeof(p_data->'location'->1) is distinct from 'number' then return '[]'::jsonb;end if;
  area_lat:=(p_data->'location'->>0)::float8;area_lng:=(p_data->'location'->>1)::float8;
  if area_lat not between 29 and 38 or area_lng not between 38 and 49 then return '[]'::jsonb;end if;
  return coalesce((select jsonb_agg(to_jsonb(x)||jsonb_build_object('distance_km',round(d.km::numeric,1)) order by d.km,x.name)
   from tkt_private.restaurants x cross join lateral(select tkt_private.km(area_lat,area_lng,(x.location->>0)::float8,(x.location->>1)::float8) as km)d
   where x.open and d.km*1000 between s.restaurant_min_distance_m and s.restaurant_max_distance_m and (x.closing_time is null or (clock_timestamp() at time zone 'Asia/Baghdad')::time<x.closing_time) and tkt_private.company_debt(x.owner_id,'restaurant_fee')<s.restaurant_debt_limit),'[]');
 end if;
 if p_action='restaurant_save' then
  if exists(select 1 from public.tkt_profiles where user_id=u and captain) or exists(select 1 from tkt_private.restaurant_couriers where user_id=u) then raise exception 'ROLE_CONFLICT';end if;
  if length(btrim(coalesce(p_data->>'name','')))<2 or length(btrim(coalesce(p_data->>'phone','')))<10 or length(btrim(coalesce(p_data->>'address','')))<3 or jsonb_array_length(p_data->'location')<>2 or p_data->'location' is null then raise exception 'FIELDS_REQUIRED';end if;
  if (p_data->'location'->>0)::numeric not between 29 and 38 or (p_data->'location'->>1)::numeric not between 38 and 49 then raise exception 'OUTSIDE_SERVICE';end if;
  if coalesce(p_data->>'image_path','')='' or not exists(select 1 from storage.objects where bucket_id='restaurant-images' and name=p_data->>'image_path' and split_part(name,'/',1)=u::text) then raise exception 'FIELDS_REQUIRED';end if;
  insert into tkt_private.restaurants(owner_id,name,phone,address,description,image_path,location,open) values(u,left(btrim(p_data->>'name'),160),left(p_data->>'phone',30),left(p_data->>'address',500),left(coalesce(p_data->>'description',''),2000),coalesce(p_data->>'image_path',''),p_data->'location',coalesce((p_data->>'open')::boolean,true))
  on conflict(owner_id) do update set name=excluded.name,phone=excluded.phone,address=excluded.address,description=excluded.description,image_path=excluded.image_path,location=excluded.location,open=excluded.open returning * into r;
  if p_data ? 'closing_time' then update tkt_private.restaurants set closing_time=nullif(p_data->>'closing_time','')::time where id=r.id returning * into r;end if;
  if not r.open then perform tkt_private.food_requests_stop(null,'restaurant',u);end if;
  return to_jsonb(r);
 end if;
 rid:=nullif(p_data->>'restaurant_id','')::uuid;
 if p_action='menu' then
  select * into r from tkt_private.restaurants where id=rid;
  if not found then raise exception 'RESTAURANT_UNAVAILABLE';end if;
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.sort_order,x.name) from tkt_private.restaurant_items x where restaurant_id=rid and (available or r.owner_id=u)),'[]');
 end if;
 if p_action='item_save' then
  select * into r from tkt_private.restaurants where owner_id=u;
  if not found then raise exception 'RESTAURANT_REQUIRED';end if;
  ident:=coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid());
  if exists(select 1 from tkt_private.restaurant_items where id=ident and restaurant_id<>r.id) then raise exception 'PERMISSION_DENIED';end if;
  if length(btrim(coalesce(p_data->>'name','')))<1 then raise exception 'FIELDS_REQUIRED';end if;
  if (p_data->>'price')::integer is null or (p_data->>'price')::integer not between 1 and 1000000 or (p_data->>'previous_price')::integer <= (p_data->>'price')::integer then raise exception 'INVALID_PRICE';end if;
  basket:=coalesce(p_data->'image_paths',jsonb_build_array(p_data->>'image_path'));
  if jsonb_typeof(basket)<>'array' or jsonb_array_length(basket) not between 1 and 10 then raise exception 'IMAGE_LIMIT';end if;
  if exists(select 1 from jsonb_array_elements_text(basket) x(path) where not exists(select 1 from storage.objects where bucket_id='restaurant-images' and name=x.path and split_part(name,'/',1)=u::text)) then raise exception 'PERMISSION_DENIED';end if;
  insert into tkt_private.restaurant_items(id,restaurant_id,name,description,price,image_path,image_paths,previous_price,category,available,sort_order)
   values(ident,r.id,btrim(p_data->>'name'),left(coalesce(p_data->>'description',''),2000),(p_data->>'price')::integer,basket->>0,basket,(p_data->>'previous_price')::integer,left(coalesce(p_data->>'category','أخرى'),80),coalesce((p_data->>'available')::boolean,true),coalesce((p_data->>'sort_order')::integer,0))
   on conflict(id) do update set name=excluded.name,description=excluded.description,price=excluded.price,image_path=excluded.image_path,image_paths=excluded.image_paths,previous_price=excluded.previous_price,category=excluded.category,available=excluded.available,sort_order=excluded.sort_order returning * into i;update tkt_private.restaurant_items set catalog_source=case when p_data->>'catalog_mode'='auto' then 'auto' when p_data->>'catalog_mode'='manual' and p_data->>'catalog_category' in('الأكل الشرقي','الأكل الغربي','المشويات','الأسماك','الدجاج','الكيك','الحلويات','أخرى') then 'manual' when not p_data ? 'catalog_mode' and p_data->>'catalog_category' in('الأكل الشرقي','الأكل الغربي','المشويات','الأسماك','الدجاج','الكيك','الحلويات') and p_data->>'catalog_category' is distinct from i.catalog_category then 'manual' else i.catalog_source end,catalog_category=coalesce(nullif(p_data->>'catalog_category',''),i.catalog_category) where id=i.id returning * into i;
  if p_data ? 'options' then
   cfg:=tkt_private.food_validate_options(p_data->'options',u);
   if jsonb_array_length(cfg->'sizes')>0 and (cfg->'sizes'->0->>'price')::int<>i.price then raise exception 'INVALID_OPTIONS';end if;
   update tkt_private.restaurant_items set options=cfg where id=i.id returning * into i;
   if coalesce((p_data->>'save_category_addons')::boolean,false) then insert into tkt_private.food_option_templates(restaurant_id,category,addons)values(r.id,i.category,cfg->'addons')on conflict(restaurant_id,category)do update set addons=excluded.addons;end if;
  end if;
  return to_jsonb(i);
 end if;
 if p_action='order_create' then
  perform pg_advisory_xact_lock(hashtextextended(u::text,9041));
  select * into o from tkt_private.food_orders where customer_id=u and request_id=(p_data->>'request_id')::uuid;
  if found then return to_jsonb(o);end if;
  if exists(select 1 from tkt_private.restaurants where owner_id=u) or exists(select 1 from public.tkt_profiles where user_id=u and captain) or exists(select 1 from tkt_private.restaurant_couriers where user_id=u) then raise exception 'ROLE_CONFLICT';end if;
  select * into strict r from tkt_private.restaurants where id=rid and open for share;
  if r.closing_time is not null and (clock_timestamp() at time zone 'Asia/Baghdad')::time>=r.closing_time then raise exception 'RESTAURANT_UNAVAILABLE';end if;
  if tkt_private.company_debt(r.owner_id,'restaurant_fee')>=s.restaurant_debt_limit then raise exception 'RESTAURANT_DEBT_LIMIT';end if;
  select * into q from public.tkt_quotes where id=(p_data->>'quote_id')::uuid and user_id=u for update;
  if not found or q.expires_at<=clock_timestamp() or q.pickup<>r.location or q.round_trip or q.change_ride_id is not null then raise exception 'QUOTE_EXPIRED';end if;
  if exists(select 1 from public.tkt_rides where quote_id=q.id) then raise exception 'QUOTE_USED';end if;
  if jsonb_typeof(p_data->'items')<>'array' or jsonb_array_length(p_data->'items') not between 1 and 100 or p_data->'items' is null then raise exception 'BASKET_REQUIRED';end if;
  for item in select value from jsonb_array_elements(p_data->'items') loop
   qty:=(item->>'quantity')::integer;
   if qty is null or qty not between 1 and 99 then raise exception 'INVALID_QUANTITY';end if;
   select * into i from tkt_private.restaurant_items where id=(item->>'id')::uuid and restaurant_id=rid and available for share;
   if not found then raise exception 'ITEM_UNAVAILABLE';end if;
   cfg:=i.options;chosen:=null;additions:='[]';unit_price:=i.price;
   size_id:=nullif(item->>'size_id','');
   if jsonb_array_length(cfg->'sizes')>0 then
    if size_id is null then chosen:=cfg->'sizes'->0;else select value into chosen from jsonb_array_elements(cfg->'sizes') where value->>'id'=size_id;end if;
    if chosen is null then raise exception 'INVALID_OPTIONS';end if;unit_price:=(chosen->>'price')::integer;
   elsif size_id is not null then raise exception 'INVALID_OPTIONS';end if;
   if item ? 'addon_ids' and jsonb_typeof(item->'addon_ids')<>'array' then raise exception 'INVALID_OPTIONS';end if;
   if jsonb_array_length(coalesce(item->'addon_ids','[]'))>30 then raise exception 'INVALID_OPTIONS';end if;
   addon_ids:=array[]::text[];
   for code in select jsonb_array_elements_text(coalesce(item->'addon_ids','[]')) loop
    if code=any(addon_ids) then raise exception 'INVALID_OPTIONS';end if;
    select value into opt from jsonb_array_elements(cfg->'addons') where value->>'id'=code;
    if opt is null then raise exception 'INVALID_OPTIONS';end if;
    addon_ids:=array_append(addon_ids,code);unit_price:=unit_price+(opt->>'price')::int;additions:=additions||jsonb_build_array(opt);
   end loop;
   note:=btrim(coalesce(item->>'notes',''));if length(note)>250 then raise exception 'INVALID_OPTIONS';end if;
   total:=total+unit_price::bigint*qty;
   basket:=basket||jsonb_build_array(jsonb_build_object('id',i.id,'name',i.name,'price',unit_price,'base_price',coalesce((chosen->>'price')::int,i.price),'quantity',qty,'image_path',i.image_path,'size',chosen,'addons',additions,'notes',note));
  end loop;
  if p_data ? 'expected_delivery_fee' and (p_data->>'expected_delivery_fee')::int is distinct from tkt_private.food_delivery_fare(q.distance_m) then raise exception 'QUOTE_EXPIRED';end if;
  if p_data ? 'expected_food_total' and (p_data->>'expected_food_total')::int is distinct from total then raise exception 'QUOTE_EXPIRED';end if;
  if (p_data->>'expected_service_fee')::integer is distinct from s.service_fee then raise exception 'QUOTE_EXPIRED';end if;
  if total>10000000 or length(btrim(coalesce(p_data->>'customer_address','')))<3 then raise exception 'FIELDS_REQUIRED';end if;
  insert into tkt_private.food_orders(request_id,customer_id,restaurant_id,quote_id,items,food_total,delivery_fee,service_fee,commission_percent,customer_address,customer_location)
   values((p_data->>'request_id')::uuid,u,rid,q.id,basket,total,case when p_data ? 'expected_delivery_fee' then tkt_private.food_delivery_fare(q.distance_m) else q.fare end,s.service_fee,s.commission_percent,left(p_data->>'customer_address',500),q.destination) returning * into o;
  perform tkt_private.notification_add(r.owner_id,'food:'||o.id||':pending','food','طلب طعام جديد','وصل طلب طعام جديد؛ افتح لوحة المطعم لقبوله.',jsonb_build_object('screen','food','order_id',o.id,'request_type','restaurant','offer_id','f:'||o.id||':r'),clock_timestamp()+interval '30 seconds');return to_jsonb(o);
 end if;
 if p_action='orders' then
  return coalesce((select jsonb_agg(j order by j->>'created_at' desc) from (
   select to_jsonb(x)||jsonb_build_object('restaurant_name',z.name,'restaurant_phone',z.phone,'restaurant_address',z.address,'restaurant_location',z.location,'captain_name',p.name,'captain_phone',p.phone,'customer_name',cp.name,'customer_phone',cp.phone,'courier_offer_expires_at',case when x.status='searching' then x.updated_at+interval '120 seconds' end,'request_offer_id',case when x.status='pending' then 'f:'||x.id||':r' when x.status='searching' then 'f:'||x.id||':c:'||floor(extract(epoch from x.updated_at)*1000000)::bigint::text end)
    as j from tkt_private.food_orders x join tkt_private.restaurants z on z.id=x.restaurant_id left join public.tkt_profiles p on p.user_id=x.captain_id join public.tkt_profiles cp on cp.user_id=x.customer_id
   where x.customer_id=u or z.owner_id=u or x.captain_id=u or (x.status='searching' and tkt_private.food_offer_active(x.id,x.updated_at,u) and x.delivery_mode='private' and tkt_private.private_courier_eligible(u,x.restaurant_id)) or (x.status='searching' and tkt_private.food_offer_active(x.id,x.updated_at,u) and x.delivery_mode='public' and tkt_private.captain_eligible(u,false) and z.owner_id<>u and tkt_private.company_debt(u,'captain_company')<s.captain_debt_limit and exists(select 1 from public.tkt_profiles k left join tkt_private.captain_plans pl on pl.user_id=k.user_id where k.user_id=u and k.captain and k.online and not k.blocked and k.location_at>clock_timestamp()-interval '90 seconds' and tkt_private.km((z.location->>0)::float8,(z.location->>1)::float8,k.lat,k.lng)<=5 and (pl.plan='commission' or k.expires_at>clock_timestamp()) and coalesce(pl.vehicle,'tuktuk')=x.vehicle) and not exists(select 1 from public.tkt_rides where captain_id=u and status in('accepted','arrived','in_progress')) and not exists(select 1 from tkt_private.food_orders where captain_id=u and status in('accepted','heading','picked_up')))
   order by x.created_at desc limit 200) a),'[]');
 end if;
 if p_action='order_details' then
  result:=tkt_private.commerce('orders','{}'::jsonb);
  select value into item from jsonb_array_elements(result) where value->>'id'=p_data->>'id';
  if item is null then raise exception 'ORDER_UNAVAILABLE';end if;return item;
 end if;
 if p_action='offer_decline' then
 ident:=(p_data->>'id')::uuid;
 select * into o from tkt_private.food_orders where id=ident for update;
 if not found or o.status<>'searching' or not tkt_private.food_offer_active(o.id,o.updated_at,u) then raise exception 'OFFER_EXPIRED';end if;
 insert into tkt_private.food_offer_declines values(o.id,u,o.updated_at) on conflict do nothing;
 perform tkt_private.food_requests_stop(o.id,'courier',u);
 return jsonb_build_object('ok',true);
 end if;
 if p_action='order_update' then
  if exists(select 1 from tkt_private.restaurant_couriers where user_id=u and not active) then raise exception 'PERMISSION_DENIED';end if;
  ident:=(p_data->>'id')::uuid;next_status:=p_data->>'status';
  select * into o from tkt_private.food_orders where id=ident for update;
  if not found then raise exception 'ORDER_UNAVAILABLE';end if;
  select * into strict r from tkt_private.restaurants where id=o.restaurant_id;
  if next_status='accepted' then
   if not tkt_private.food_offer_active(o.id,o.updated_at,u) then raise exception 'OFFER_EXPIRED';end if;
   if o.delivery_mode='private' then
    perform 1 from public.tkt_profiles where user_id=u for update;
    if o.status<>'searching' or not tkt_private.private_courier_eligible(u,o.restaurant_id) then raise exception 'OFFER_EXPIRED';end if;
    o.captain_id:=u;o.commission_amount:=0;
   else
   if tkt_private.company_debt(u,'captain_company')>=s.captain_debt_limit then raise exception 'CAPTAIN_DEBT_LIMIT';end if;
   select * into c from public.tkt_profiles where user_id=u for update;
   if not tkt_private.captain_eligible(u,false) then raise exception 'PERMISSION_DENIED';end if;
   if o.status<>'searching' or not c.captain or not c.online or c.blocked or c.location_at is null or c.location_at<clock_timestamp()-interval '90 seconds' or r.owner_id=u then raise exception 'OFFER_EXPIRED';end if;
   if not exists(select 1 from tkt_private.captain_plans where user_id=u and plan='commission') and coalesce(c.expires_at<=clock_timestamp(),true) then raise exception 'CAPTAIN_SUBSCRIPTION_REQUIRED';end if;
   if tkt_private.km((r.location->>0)::float8,(r.location->>1)::float8,c.lat,c.lng)>5 or c.lat is null or c.lng is null then raise exception 'CAPTAIN_UNAVAILABLE';end if;
   if coalesce((select vehicle from tkt_private.captain_plans where user_id=u),'tuktuk')<>o.vehicle then raise exception 'VEHICLE_MISMATCH';end if;
   if exists(select 1 from public.tkt_rides where captain_id=u and status in('accepted','arrived','in_progress')) or exists(select 1 from tkt_private.food_orders where captain_id=u and status in('accepted','heading','picked_up')) then raise exception 'CAPTAIN_BUSY';end if;
   o.captain_id:=u;
   o.commission_amount:=case when exists(select 1 from tkt_private.captain_plans where user_id=u and plan='commission') then round(o.delivery_fee*o.commission_percent/100)::integer else 0 end;
   end if;
  elsif r.owner_id=u then
   if o.status='pending' and next_status='preparing' and tkt_private.company_debt(u,'restaurant_fee')>=s.restaurant_debt_limit then raise exception 'RESTAURANT_DEBT_LIMIT';end if;
   if not ((o.status='pending' and next_status in('preparing','rejected')) or (o.status in('preparing','searching') and next_status='searching' and o.captain_id is null) or (o.status='searching' and next_status='preparing' and o.captain_id is null) or (o.status in('preparing','searching') and next_status='rejected')) then raise exception 'INVALID_TRANSITION';end if;
   if next_status='searching' then
    o.delivery_mode:=coalesce(p_data->>'delivery_mode','public');
    if o.delivery_mode not in('public','private') then raise exception 'INVALID_KIND';end if;
    if o.delivery_mode='private' then
     if not r.self_delivery then raise exception 'PERMISSION_DENIED';end if;
     if not exists(select 1 from tkt_private.restaurant_couriers rc where rc.restaurant_id=r.id and tkt_private.private_courier_eligible(rc.user_id,r.id)) then raise exception 'CAPTAIN_UNAVAILABLE';end if;
     o.vehicle:='bike';
    else
     v:=p_data->>'vehicle';if v is null or v not in('tuktuk','bike') then raise exception 'VEHICLE_REQUIRED';end if;o.vehicle:=v;
    end if;

   end if;
  elsif o.customer_id=u and o.status='pending' and next_status='rejected' then
   null;
  elsif o.captain_id=u then
   if not ((o.status='accepted' and next_status='heading') or (o.status='heading' and next_status='picked_up') or (o.status='picked_up' and next_status in('delivered','rejected')) or (o.status in('accepted','heading') and next_status='rejected')) then raise exception 'INVALID_TRANSITION';end if;
  else raise exception 'PERMISSION_DENIED';end if;
  if next_status='rejected' then
   o.reason:=btrim(coalesce(p_data->>'reason',''));if length(o.reason) not between 3 and 1000 then raise exception 'REASON_REQUIRED';end if;
  end if;
  if o.status='pending' then perform tkt_private.food_requests_stop(o.id,'restaurant');end if;
  if o.status='searching' then perform tkt_private.food_requests_stop(o.id,'courier');end if;
  update tkt_private.food_orders set status=next_status,captain_id=o.captain_id,vehicle=o.vehicle,delivery_mode=o.delivery_mode,commission_amount=o.commission_amount,reason=o.reason,updated_at=clock_timestamp() where id=ident returning * into o;
  body:=case next_status when 'preparing' then 'المطعم وافق على طلبك؛ طلبك قيد التحضير' when 'searching' then 'جار البحث عن مندوب توصيل إليك' when 'accepted' then 'وافق المندوب على طلبك؛ افتح الطلب لعرض معلوماته' when 'heading' then 'المندوب متوجه للمطعم' when 'picked_up' then 'استلم المندوب طلبك وهو بالطريق إليك' when 'delivered' then 'تم توصيل طلبك' else 'تم رفض الطلب: '||o.reason end;
  perform tkt_private.notification_add(o.customer_id,'food:'||o.id||':'||next_status,'food','طلب الطعام',body,jsonb_build_object('screen','food','order_id',o.id));
  perform tkt_private.notification_add(r.owner_id,'food:'||o.id||':'||next_status,'food','حالة طلب الطعام',body,jsonb_build_object('screen','food','order_id',o.id));
  if next_status='searching' and o.delivery_mode='private' then
   for target in select rc.user_id from tkt_private.restaurant_couriers rc where rc.restaurant_id=r.id and tkt_private.private_courier_eligible(rc.user_id,r.id) loop
    perform tkt_private.notification_add(target,'food-offer:'||o.id||':'||extract(epoch from o.updated_at)::text,'food','طلب توصيل خاص','عندك طلب جديد من مطعمك',jsonb_build_object('screen','food','order_id',o.id,'request_type','courier','offer_id','f:'||o.id||':c:'||floor(extract(epoch from o.updated_at)*1000000)::bigint::text),clock_timestamp()+interval '120 seconds');
   end loop;
  elsif next_status='searching' then
   for c in select p.* from public.tkt_profiles p left join tkt_private.captain_plans pl on pl.user_id=p.user_id where tkt_private.captain_eligible(p.user_id,false) and p.captain and p.online and not p.blocked and tkt_private.km((r.location->>0)::float8,(r.location->>1)::float8,p.lat,p.lng)<=5 and p.location_at>clock_timestamp()-interval '90 seconds' and coalesce(pl.vehicle,'tuktuk')=o.vehicle and (pl.plan='commission' or p.expires_at>clock_timestamp()) and not exists(select 1 from public.tkt_rides where captain_id=p.user_id and status in('accepted','arrived','in_progress')) and not exists(select 1 from tkt_private.food_orders where captain_id=p.user_id and status in('accepted','heading','picked_up')) loop
    perform tkt_private.notification_add(c.user_id,'food-offer:'||o.id||':'||extract(epoch from o.updated_at)::text,'food','طلب توصيل طعام','عندك طلب توصيل طعام؛ افتح طلبات الطعام لعرضه.',jsonb_build_object('screen','food','order_id',o.id,'request_type','courier','offer_id','f:'||o.id||':c:'||floor(extract(epoch from o.updated_at)*1000000)::bigint::text),clock_timestamp()+interval '120 seconds');
   end loop;
  end if;
  return to_jsonb(o);
 end if;
 if p_action='accounts' then if not exists(select 1 from tkt_private.restaurants where owner_id=u) and not exists(select 1 from public.tkt_profiles where user_id=u and captain) and not exists(select 1 from tkt_private.restaurant_couriers where user_id=u) then raise exception 'PERMISSION_DENIED';end if;
  return jsonb_build_object('statistics',coalesce((select jsonb_agg(to_jsonb(v)) from(select x.restaurant_id,x.captain_id,count(*)filter(where x.status='delivered') as delivered,count(*)filter(where x.status='rejected') as rejected from tkt_private.food_orders x join tkt_private.restaurants z on z.id=x.restaurant_id where x.captain_id=u or z.owner_id=u group by x.restaurant_id,x.captain_id)v),'[]'),'debts',coalesce((select jsonb_agg(to_jsonb(d)||jsonb_build_object('restaurant_name',r.name,'restaurant_phone',r.phone,'restaurant_address',r.address,'captain_name',p.name,'captain_phone',p.phone)) from tkt_private.commerce_debts d left join tkt_private.restaurants r on r.id=d.restaurant_id join public.tkt_profiles p on p.user_id=d.debtor_id where d.debtor_id=u or d.creditor_id=u),'[]'),
   'settlements',coalesce((select jsonb_agg((to_jsonb(x)-'code_hash')||jsonb_build_object('recipient_name',case when x.kind='captain_restaurant' then r.name else 'شركة تكتوكة' end,'payer_name',p.name,'payer_phone',p.phone) order by x.created_at desc) from tkt_private.commerce_settlements x left join tkt_private.restaurants r on r.id=x.restaurant_id join public.tkt_profiles p on p.user_id=x.debtor_id where x.debtor_id=u or x.creditor_id=u),'[]'));
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
end $function$

