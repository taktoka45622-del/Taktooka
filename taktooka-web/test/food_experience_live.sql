begin;
do $$
declare owner_id uuid:=gen_random_uuid();customer_id uuid:=gen_random_uuid();restaurant_id uuid:=gen_random_uuid();item_id uuid:=gen_random_uuid();quote_id uuid:=gen_random_uuid();admin_id uuid;cfg jsonb;o jsonb;q jsonb;denied boolean;fee int;
begin
 insert into auth.users(id,aud,role,email,raw_user_meta_data,raw_app_meta_data,created_at,updated_at)select id,'authenticated','authenticated',id||'@food-experience-test.invalid','{}','{}',now(),now() from unnest(array[owner_id,customer_id]) id;
 insert into public.tkt_profiles(user_id,name,phone)values(owner_id,'صاحب مطعم اختبار تجربة','07000000881'),(customer_id,'زبون اختبار تجربة','07000000882');
 insert into tkt_private.restaurants(id,owner_id,name,phone,address,location,open)values(restaurant_id,owner_id,'مطعم اختبار تجربة','07000000881','عنوان اختبار','[33.55,44.42]',true);
 insert into tkt_private.restaurant_items(id,restaurant_id,name,price,image_path,previous_price,catalog_category)values(item_id,restaurant_id,'بركر اختبار',7000,'',9000,'الأكل الغربي');
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 perform public.tkt_commerce('restaurant_open','{"open":false}');if (public.tkt_commerce('me','{}')->'restaurant'->>'open')::boolean then raise exception 'CLOSE_FAILED';end if;
 perform public.tkt_commerce('restaurant_open','{"open":true}');
 perform public.tkt_commerce('category_save','{"name":"قسم من إنشاء المطعم"}');if not public.tkt_commerce('categories','{}') ? 'قسم من إنشاء المطعم' then raise exception 'CATEGORY_FAILED';end if;
 perform set_config('request.jwt.claim.sub',customer_id::text,true);
 denied:=false;begin perform public.tkt_commerce('accounts','{}');exception when others then if sqlerrm<>'PERMISSION_DENIED' then raise;end if;denied:=true;end;if not denied then raise exception 'CUSTOMER_FINANCE_ACCESS';end if;
 q:=public.tkt_commerce('catalog','{"location":[33.55,44.42],"offers":true,"category":"الأكل الغربي","min_price":6000,"max_price":8000}');if not exists(select 1 from jsonb_array_elements(q) x where x->>'id'=item_id::text) then raise exception 'CATALOG_MISSING';end if;
 if tkt_private.food_delivery_fare(7500)<>1500 or tkt_private.food_delivery_fare(7501)<>2000 or tkt_private.food_delivery_fare(15000)<>2000 then raise exception 'FOOD_FARE_BOUNDARY';end if;
 insert into public.tkt_quotes(id,user_id,pickup,destination,geometry,distance_m,duration_s,fare)values(quote_id,customer_id,'[33.55,44.42]','[33.56,44.43]','{"type":"LineString","coordinates":[[44.42,33.55],[44.43,33.56]]}',8000,1200,4000);
 q:=public.tkt_commerce('food_quote',jsonb_build_object('quote_id',quote_id));if (q->>'fare')::int<>2000 or (select fare from public.tkt_quotes where id=quote_id)<>4000 then raise exception 'TAXI_QUOTE_WAS_CHANGED';end if;
 select service_fee into fee from tkt_private.commerce_settings where id;
 o:=public.tkt_commerce('order_create',jsonb_build_object('request_id',gen_random_uuid(),'restaurant_id',restaurant_id,'quote_id',quote_id,'items',jsonb_build_array(jsonb_build_object('id',item_id,'quantity',1)),'customer_address','عنوان زبون اختبار','expected_service_fee',fee,'expected_delivery_fee',2000,'expected_food_total',7000));if (o->>'delivery_fee')::int<>2000 then raise exception 'ORDER_FEE_MISMATCH';end if;
 select a.user_id into strict admin_id from public.tkt_admins a join public.tkt_profiles p using(user_id)where not p.blocked limit 1;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);cfg:=public.tkt_commerce('admin','{}')->'settings';perform public.tkt_commerce('settings_save',cfg||'{"food_first_distance_m":5000,"food_first_fee":1000,"food_max_distance_m":20000,"food_second_fee":3000}');if tkt_private.food_delivery_fare(6000)<>3000 then raise exception 'LIVE_TIER_SETTINGS_FAILED';end if;
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 insert into tkt_private.restaurant_items(id,restaurant_id,name,price,image_path) values(gen_random_uuid(),restaurant_id,'وجبة ترتيب اختبار',1000,'') returning id into quote_id;
 perform public.tkt_commerce('items_reorder',jsonb_build_object('ids',jsonb_build_array(quote_id,item_id)));
 if (select sort_order from tkt_private.restaurant_items where id=quote_id)<>0 or (select sort_order from tkt_private.restaurant_items where id=item_id)<>1 then raise exception 'ATOMIC_REORDER_FAILED';end if;
end $$;
rollback;
select 'PASS: live close/open without images, custom categories, customer finance denial, catalog/discount/prices, 7500/7501/15000 boundaries, food quote preserving taxi fare, food order pricing, dashboard tier updates; rolled back' as result;
