begin;
do $$
declare owner_id uuid:=gen_random_uuid();customer_id uuid:=gen_random_uuid();restaurant_id uuid:=gen_random_uuid();admin_id uuid;cfg jsonb;rows jsonb;denied boolean;
begin
 select a.user_id into strict admin_id from public.tkt_admins a join public.tkt_profiles p using(user_id) where not p.blocked limit 1;
 insert into auth.users(id,aud,role,email,raw_user_meta_data,raw_app_meta_data,created_at,updated_at) select id,'authenticated','authenticated',id||'@radius-transaction-test.invalid','{}','{}',now(),now() from unnest(array[owner_id,customer_id]) id;
 insert into public.tkt_profiles(user_id,name,phone) values(owner_id,'اختبار نطاق مطعم','07000000871'),(customer_id,'اختبار نطاق زبون','07000000872');
 insert into tkt_private.restaurants(id,owner_id,name,phone,address,location,open) values(restaurant_id,owner_id,'اختبار نطاق','07000000871','عنوان اختبار','[33.5,44.4]',true);
 perform set_config('request.jwt.claim.sub',customer_id::text,true);
 denied:=false;begin perform public.tkt_commerce('settings_save','{"commission_percent":20,"service_fee":500,"restaurant_min_distance_m":0,"restaurant_max_distance_m":5000}');exception when others then if sqlerrm<>'PERMISSION_DENIED' then raise;end if;denied:=true;end;if not denied then raise exception 'CUSTOMER_CHANGED_RANGE';end if;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 cfg:=public.tkt_commerce('admin','{}')->'settings';
 perform public.tkt_commerce('settings_save',cfg||'{"restaurant_min_distance_m":0,"restaurant_max_distance_m":5000}');
 perform set_config('request.jwt.claim.sub',customer_id::text,true);
 rows:=public.tkt_commerce('restaurants','{"location":[33.6,44.4],"radius_km":1000}');if exists(select 1 from jsonb_array_elements(rows) r where r->>'id'=restaurant_id::text) then raise exception 'SMALL_MAX_IGNORED';end if;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 perform public.tkt_commerce('settings_save',cfg||'{"restaurant_min_distance_m":1000,"restaurant_max_distance_m":25000}');
 perform set_config('request.jwt.claim.sub',customer_id::text,true);
 rows:=public.tkt_commerce('restaurants','{"location":[33.7,44.4]}');if not exists(select 1 from jsonb_array_elements(rows) r where r->>'id'=restaurant_id::text) then raise exception 'LARGER_MAX_IGNORED';end if;
 rows:=public.tkt_commerce('restaurants','{"location":[33.5,44.4]}');if exists(select 1 from jsonb_array_elements(rows) r where r->>'id'=restaurant_id::text) then raise exception 'MIN_IGNORED';end if;
 if (public.tkt_commerce('me','{}')->>'restaurant_max_distance_m')::int<>25000 then raise exception 'LABEL_CONFIG_STALE';end if;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 denied:=false;begin perform public.tkt_commerce('settings_save',cfg||'{"restaurant_min_distance_m":25000,"restaurant_max_distance_m":1000}');exception when check_violation then denied:=true;end;if not denied then raise exception 'INVALID_RANGE_SAVED';end if;
end $$;
rollback;
select 'PASS: live admin save, permission denial, immediate 5km/25km/minimum filtering, client override denial, config labels, invalid range rejection; rolled back' as result;
