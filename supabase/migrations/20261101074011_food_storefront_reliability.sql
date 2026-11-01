alter table tkt_private.restaurants add column closing_at timestamptz;
alter table tkt_private.food_orders add column order_number bigint generated always as identity (start with 100001);
create unique index food_orders_order_number on tkt_private.food_orders(order_number);
update tkt_private.restaurants set closing_at=((clock_timestamp() at time zone 'Asia/Baghdad')::date+closing_time) at time zone 'Asia/Baghdad' where open and closing_time is not null;
create function tkt_private.restaurant_closing_deadline() returns trigger language plpgsql security definer set search_path='' as $$
declare local_now timestamp:=clock_timestamp() at time zone 'Asia/Baghdad';deadline timestamp;
begin
 if new.closing_time is null then new.closing_at:=null;
 elsif new.open and (tg_op='INSERT' or old.open is distinct from true or old.closing_time is distinct from new.closing_time or new.closing_at is null) then
  deadline:=local_now::date+new.closing_time;
  if deadline<=local_now then deadline:=deadline+interval '1 day';end if;
  new.closing_at:=deadline at time zone 'Asia/Baghdad';
 end if;
 return new;
end $$;
create trigger restaurant_closing_deadline before insert or update on tkt_private.restaurants for each row execute function tkt_private.restaurant_closing_deadline();
create function tkt_private.close_scheduled_restaurants() returns void language plpgsql security definer set search_path='' as $$
declare r record;
begin
 for r in update tkt_private.restaurants set open=false where open and closing_at<=clock_timestamp() returning owner_id loop
  perform tkt_private.food_requests_stop(null,'restaurant',r.owner_id);
 end loop;
end $$;
create function tkt_private.food_order_availability_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform 1 from tkt_private.restaurants r where r.id=new.restaurant_id and r.open and (r.closing_at is null or r.closing_at>clock_timestamp()) for share;
 if not found then raise exception 'RESTAURANT_UNAVAILABLE';end if;
 return new;
end $$;
create trigger food_order_availability_guard before insert on tkt_private.food_orders for each row execute function tkt_private.food_order_availability_guard();
select cron.schedule('tkt-close-restaurants','* * * * *','select tkt_private.close_scheduled_restaurants()');

create function tkt_private.food_storefront(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare
 u uuid:=auth.uid();r tkt_private.restaurants;i tkt_private.restaurant_items;o tkt_private.food_orders;
 s tkt_private.commerce_settings;q public.tkt_quotes;
 rid uuid;qty integer;code text;item jsonb;basket jsonb:='[]';total bigint:=0;cfg jsonb;chosen jsonb;additions jsonb;opt jsonb;unit_price integer;size_id text;addon_ids text[];note text;
 result jsonb;v text;area_lat float8;area_lng float8;
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 if not exists(select 1 from public.tkt_profiles where user_id=u and not blocked and deleted_at is null) then raise exception 'ACCOUNT_BLOCKED';end if;
 select * into strict s from tkt_private.commerce_settings where id;
 rid:=nullif(p_data->>'restaurant_id','')::uuid;
 if p_action='support_context' then
  return tkt_private.food_support_identity(u)||jsonb_build_object('orders',(select coalesce(jsonb_agg(value),'[]') from(select value from jsonb_array_elements(tkt_private.food_dispatch_commerce('orders','{}')) limit 10)x));
 end if;

 if p_action='category_save' then
  select * into r from tkt_private.restaurants where owner_id=u for update;
  if not found then raise exception 'PERMISSION_DENIED';end if;
  v:=btrim(p_data->>'name');if v is null or length(v) not between 1 and 80 then raise exception 'FIELDS_REQUIRED';end if;
  r.menu_categories:=coalesce(r.menu_categories,'[]');
  if not r.menu_categories ? v and jsonb_array_length(r.menu_categories)>=100 then raise exception 'CATEGORY_LIMIT';end if;
  if nullif(p_data->>'old_name','') is not null then
   perform tkt_private.commerce('category_save',p_data);
  else
   if not r.menu_categories ? v then update tkt_private.restaurants set menu_categories=r.menu_categories||jsonb_build_array(v) where id=r.id;end if;
  end if;
  select * into r from tkt_private.restaurants where id=r.id;return to_jsonb(r);
 elsif p_action='categories' then
  select * into r from tkt_private.restaurants where owner_id=u;
  if not found then raise exception 'PERMISSION_DENIED';end if;
  return coalesce((select jsonb_agg(value order by value) from(select distinct btrim(value) value from jsonb_array_elements_text(coalesce(r.menu_categories,'[]')||coalesce((select jsonb_agg(category) from tkt_private.restaurant_items where restaurant_id=r.id),'[]')) where btrim(value)<>'')x),'[]');
 elsif p_action='restaurants' then
  if jsonb_typeof(p_data->'location') is distinct from 'array' then return '[]';end if;
  if jsonb_array_length(p_data->'location')<>2 or jsonb_typeof(p_data->'location'->0) is distinct from 'number' or jsonb_typeof(p_data->'location'->1) is distinct from 'number' then return '[]';end if;
  area_lat:=(p_data->'location'->>0)::float8;area_lng:=(p_data->'location'->>1)::float8;
  if area_lat not between 29 and 38 or area_lng not between 38 and 49 then return '[]';end if;
  return coalesce((select jsonb_agg(to_jsonb(x)||jsonb_build_object('distance_km',round(d.km::numeric,1)) order by d.km,x.name)
  from tkt_private.restaurants x cross join lateral(select tkt_private.km(area_lat,area_lng,(x.location->>0)::float8,(x.location->>1)::float8) km)d
  where x.open and (x.closing_at is null or x.closing_at>clock_timestamp()) and d.km<=least(15,s.restaurant_max_distance_m/1000.0)
  and tkt_private.company_debt(x.owner_id,'restaurant_fee')<s.restaurant_debt_limit),'[]');
 elsif p_action='catalog' then
  result:=tkt_private.food_storefront('restaurants',p_data);
  return coalesce((select jsonb_agg(payload order by popularity desc,price,id) from (
  select to_jsonb(m)||jsonb_build_object('restaurant_name',rj->>'name','restaurant_id',rj->>'id','restaurant_image',rj->>'image_path') payload,m.price,m.id,
  coalesce((select sum((li->>'quantity')::int) from tkt_private.food_orders fo cross join lateral jsonb_array_elements(fo.items)li where fo.status='delivered' and fo.created_at>clock_timestamp()-interval '30 days' and li->>'id'=m.id::text),0) popularity
  from jsonb_array_elements(result)rj join tkt_private.restaurant_items m on m.restaurant_id=(rj->>'id')::uuid
  where m.available and (coalesce(p_data->>'category','')='' or m.catalog_category=p_data->>'category')
  and (not coalesce((p_data->>'offers')::boolean,false) or m.previous_price>m.price)
  and (coalesce(p_data->>'search','')='' or m.name ilike '%'||(p_data->>'search')||'%' or rj->>'name' ilike '%'||(p_data->>'search')||'%')
  and m.price>=coalesce((p_data->>'min_price')::int,0) and m.price<=coalesce((p_data->>'max_price')::int,1000000)
  order by popularity desc,m.price,m.id limit 100 offset greatest(0,least(100000,coalesce((p_data->>'offset')::int,0))))x),'[]');
 elsif p_action='restaurant_status' then
  select * into r from tkt_private.restaurants where id=rid;
  if not found then raise exception 'RESTAURANT_UNAVAILABLE';end if;
  return to_jsonb(r)||jsonb_build_object('open',r.open and (r.closing_at is null or r.closing_at>clock_timestamp()));
 end if;
 if p_action='order_create' then
  perform pg_advisory_xact_lock(hashtextextended(u::text,9041));
  select * into o from tkt_private.food_orders where customer_id=u and request_id=(p_data->>'request_id')::uuid;
  if found then return to_jsonb(o);end if;
  if exists(select 1 from tkt_private.restaurants where owner_id=u) or exists(select 1 from public.tkt_profiles where user_id=u and captain) or exists(select 1 from tkt_private.restaurant_couriers where user_id=u) then raise exception 'ROLE_CONFLICT';end if;
  select * into strict r from tkt_private.restaurants where id=rid and open for share;
  if r.closing_at is not null and clock_timestamp()>=r.closing_at then raise exception 'RESTAURANT_UNAVAILABLE';end if;
  if tkt_private.company_debt(r.owner_id,'restaurant_fee')>=s.restaurant_debt_limit then raise exception 'RESTAURANT_DEBT_LIMIT';end if;
  select * into q from public.tkt_quotes where id=(p_data->>'quote_id')::uuid and user_id=u for update;
  if not found or q.expires_at<=clock_timestamp() or q.pickup<>r.location or q.round_trip or q.change_ride_id is not null then raise exception 'QUOTE_EXPIRED';end if;
  if tkt_private.km((r.location->>0)::float8,(r.location->>1)::float8,(q.destination->>0)::float8,(q.destination->>1)::float8)>15 then raise exception 'FOOD_DELIVERY_OUTSIDE_RANGE';end if;
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


 result:=tkt_private.food_dispatch_commerce(p_action,p_data);
 if p_action='me' and result->'restaurant' is not null and result->'restaurant'<>'null'::jsonb then
  select * into r from tkt_private.restaurants where owner_id=u;
  result:=jsonb_set(result,'{restaurant}',to_jsonb(r)||jsonb_build_object('open',r.open and (r.closing_at is null or r.closing_at>clock_timestamp())));
 end if;
 return result;
end $$;
create function public.tkt_food_storefront(p_action text,p_data jsonb default '{}') returns jsonb language sql set search_path='' as $$select tkt_private.food_storefront(p_action,p_data)$$;
revoke all on function public.tkt_food_storefront(text,jsonb),tkt_private.food_storefront(text,jsonb) from public,anon;
grant execute on function public.tkt_food_storefront(text,jsonb),tkt_private.food_storefront(text,jsonb) to authenticated;
revoke all on function tkt_private.restaurant_closing_deadline(),tkt_private.close_scheduled_restaurants(),tkt_private.food_order_availability_guard() from public,anon,authenticated;
select tkt_private.close_scheduled_restaurants();

alter table public.tkt_messages add column context jsonb not null default '{}';
create function tkt_private.food_support_identity(p_user uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('user_id',p.user_id,'name',p.name,'phone',p.phone,'role',case when r.id is not null then 'صاحب مطعم' when rc.user_id is not null then 'مندوب خاص' when p.captain then 'كابتن' else 'زبون' end,
 'restaurant_name',r.name,'restaurant_phone',r.phone,'restaurant_address',r.address)
 from public.tkt_profiles p left join tkt_private.restaurants r on r.owner_id=p.user_id left join tkt_private.restaurant_couriers rc on rc.user_id=p.user_id where p.user_id=p_user
$$;
create function tkt_private.support_message_context() returns trigger language plpgsql security definer set search_path='' as $$
declare ident uuid;details jsonb;o tkt_private.food_orders;r tkt_private.restaurants;
begin
 new.context:=coalesce(tkt_private.food_support_identity(new.user_id),'{}')||jsonb_build_object('subject','استفسار عام');
 if not new.is_admin and nullif(current_setting('tkt.support_order',true),'') is not null then
  ident:=current_setting('tkt.support_order',true)::uuid;
  select * into o from tkt_private.food_orders where id=ident;select * into r from tkt_private.restaurants where id=o.restaurant_id;
  if o.id is null or new.sender_id not in(o.customer_id,coalesce(o.captain_id,o.customer_id),r.owner_id) then raise exception 'PERMISSION_DENIED';end if;
  select value into details from jsonb_array_elements(tkt_private.food_dispatch_commerce('orders','{}')) where value->>'id'=ident::text;
  if details is null then raise exception 'PERMISSION_DENIED';end if;
  new.context:=new.context||jsonb_build_object('subject','طلب طعام','order',details-'quote_id'-'request_id'-'request_offer_id');
 end if;
 return new;
end $$;
create trigger support_message_context before insert on public.tkt_messages for each row execute function tkt_private.support_message_context();
create function tkt_private.send_support_message(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED';end if;
 if length(btrim(coalesce(p_data->>'body',''))) not between 1 and 2000 then raise exception 'INVALID_MESSAGE';end if;
 perform set_config('tkt.support_order',coalesce(p_data->>'order_id',''),true);
 result:=tkt_private.extra('send',p_data);
 perform set_config('tkt.support_order','',true);return result;
end $$;
create function public.tkt_support_message(p_data jsonb default '{}') returns jsonb language sql set search_path='' as $$select tkt_private.send_support_message(p_data)$$;
revoke all on function tkt_private.food_support_identity(uuid),tkt_private.support_message_context() from public,anon,authenticated;
revoke all on function public.tkt_support_message(jsonb),tkt_private.send_support_message(jsonb) from public,anon;
grant execute on function public.tkt_support_message(jsonb),tkt_private.send_support_message(jsonb) to authenticated;

create table public.tkt_food_catalog_state(id boolean primary key default true check(id),revision bigint not null default 1);
insert into public.tkt_food_catalog_state(id) values(true);
alter table public.tkt_food_catalog_state enable row level security;
revoke all on public.tkt_food_catalog_state from public,anon,authenticated;
grant select on public.tkt_food_catalog_state to authenticated;
create policy food_catalog_revision_read on public.tkt_food_catalog_state for select to authenticated using(true);
create function tkt_private.food_catalog_changed() returns trigger language plpgsql security definer set search_path='' as $$
begin update public.tkt_food_catalog_state set revision=revision+1 where id;return null;end $$;
create trigger food_catalog_restaurant_changed after insert or update or delete on tkt_private.restaurants for each statement execute function tkt_private.food_catalog_changed();
create trigger food_catalog_item_changed after insert or update or delete on tkt_private.restaurant_items for each statement execute function tkt_private.food_catalog_changed();
create trigger food_catalog_banner_changed after insert or update or delete on public.tkt_home_banners for each statement execute function tkt_private.food_catalog_changed();
revoke all on function tkt_private.food_catalog_changed() from public,anon,authenticated;
do $$begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='tkt_food_catalog_state') then
  alter publication supabase_realtime add table public.tkt_food_catalog_state;
 end if;
end $$;
create function tkt_private.remove_deleted_food_banners() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='restaurant_items' then update public.tkt_home_banners set enabled=false where meal_id=old.id;
 else update public.tkt_home_banners set enabled=false where restaurant_id=old.id;end if;
 return old;
end $$;
create trigger remove_deleted_meal_banners before delete on tkt_private.restaurant_items for each row execute function tkt_private.remove_deleted_food_banners();
create trigger remove_deleted_restaurant_banners before delete on tkt_private.restaurants for each row execute function tkt_private.remove_deleted_food_banners();
revoke all on function tkt_private.remove_deleted_food_banners() from public,anon,authenticated;
