begin;
do $$
declare
 owner_id uuid:=gen_random_uuid(); customer_id uuid:=gen_random_uuid(); courier_id uuid:=gen_random_uuid(); second_id uuid:=gen_random_uuid(); captain_id uuid:=gen_random_uuid();
 restaurant_id uuid:=gen_random_uuid(); item_id uuid:=gen_random_uuid(); quote_id uuid:=gen_random_uuid();
 o jsonb; details jsonb; st jsonb; ledger jsonb; record jsonb; fee integer; denied boolean; alert_id text;
begin
 insert into auth.users(id,aud,role,email,raw_user_meta_data,raw_app_meta_data,created_at,updated_at)
 select id,'authenticated','authenticated',id||'@taktooka-transaction-test.invalid','{}','{}',now(),now() from unnest(array[owner_id,customer_id,courier_id,second_id,captain_id]) id;
 insert into public.tkt_profiles(user_id,name,phone,captain,expires_at,online,lat,lng,location_at)
 values(owner_id,'اختبار صاحب مطعم','07000000101',false,null,false,null,null,null),
 (customer_id,'اختبار زبون','07000000102',false,null,false,null,null,null),
 (courier_id,'اختبار مندوب أول','07000000103',false,null,false,null,null,null),
 (second_id,'اختبار مندوب ثان','07000000104',false,null,false,null,null,null),
 (captain_id,'اختبار كابتن','07000000105',true,now()+interval '1 day',true,33.55,44.42,now());
 insert into tkt_private.restaurants(id,owner_id,name,phone,address,location,self_delivery)
 values(restaurant_id,owner_id,'اختبار توصيل خاص','07000000101','الحسينية — اختبار معاملة','[33.55,44.42]',true);
 perform set_config('request.jwt.claim.role','service_role',true);
 perform public.tkt_restaurant_courier_link(owner_id,courier_id);
 perform public.tkt_restaurant_courier_link(owner_id,second_id);
 perform set_config('request.jwt.claim.role','authenticated',true);
 perform set_config('request.jwt.claim.sub',courier_id::text,true);
 perform public.tkt_commerce('courier_location','{"online":true,"lat":33.55,"lng":44.42}');
 perform set_config('request.jwt.claim.sub',second_id::text,true);
 perform public.tkt_commerce('courier_location','{"online":true,"lat":33.55,"lng":44.42}');
 insert into tkt_private.restaurant_items(id,restaurant_id,name,price,image_path) values(item_id,restaurant_id,'وجبة اختبار',1000,'');
 insert into public.tkt_quotes(id,user_id,pickup,destination,geometry,distance_m,duration_s,fare)
 values(quote_id,customer_id,'[33.55,44.42]','[33.56,44.43]','{"type":"LineString","coordinates":[[44.42,33.55],[44.43,33.56]]}',1500,180,1500);
 select service_fee into fee from tkt_private.commerce_settings where id;
 perform set_config('request.jwt.claim.sub',customer_id::text,true);
 o:=public.tkt_commerce('order_create',jsonb_build_object('request_id',gen_random_uuid(),'restaurant_id',restaurant_id,'quote_id',quote_id,'items',jsonb_build_array(jsonb_build_object('id',item_id,'quantity',1)),'customer_address','عنوان الزبون للاختبار','expected_service_fee',fee));
 select target->>'offer_id' into alert_id from public.tkt_notifications where user_id=owner_id and target->>'order_id'=o->>'id' and target->>'request_type'='restaurant';
 if alert_id is null then raise exception 'LIVE_RESTAURANT_RING_MISSING';end if;
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 perform public.tkt_commerce('order_update',jsonb_build_object('id',o->>'id','status','preparing'));
 if not exists(select 1 from public.tkt_notifications where user_id=owner_id and kind='offer_end' and target->>'offer_id'=alert_id) then raise exception 'LIVE_RESTAURANT_RING_NOT_STOPPED';end if;
 perform public.tkt_commerce('order_update',jsonb_build_object('id',o->>'id','status','searching','delivery_mode','private'));
 if (select count(*) from public.tkt_notifications where target->>'order_id'=o->>'id' and target->>'request_type'='courier')<>2 then raise exception 'LIVE_PRIVATE_ALERT_RECIPIENTS';end if;
 perform set_config('request.jwt.claim.sub',captain_id::text,true);
 denied:=false;begin perform public.tkt_commerce('order_details',jsonb_build_object('id',o->>'id'));exception when others then if sqlerrm<>'ORDER_UNAVAILABLE' then raise;end if;denied:=true;end;
 if not denied then raise exception 'LIVE_PRIVATE_DETAILS_LEAK';end if;
 perform set_config('request.jwt.claim.sub',courier_id::text,true);
 details:=public.tkt_commerce('order_details',jsonb_build_object('id',o->>'id'));
 if details->>'customer_name'<>'اختبار زبون' or details->>'customer_phone'<>'07000000102' or (details->>'delivery_fee')::integer<>1500 or details->'restaurant_location' is null or details->'customer_location' is null then raise exception 'LIVE_ORDER_DETAILS_MISSING';end if;
 perform public.tkt_commerce('order_update',jsonb_build_object('id',o->>'id','status','accepted'));
 perform set_config('request.jwt.claim.sub',second_id::text,true);
 denied:=false;begin perform public.tkt_commerce('order_update',jsonb_build_object('id',o->>'id','status','accepted'));exception when others then if sqlerrm<>'OFFER_EXPIRED' then raise;end if;denied:=true;end;
 if not denied then raise exception 'LIVE_DOUBLE_ACCEPT';end if;
 perform set_config('request.jwt.claim.sub',courier_id::text,true);
 perform public.tkt_commerce('order_update',jsonb_build_object('id',o->>'id','status','heading'));
 perform public.tkt_commerce('order_update',jsonb_build_object('id',o->>'id','status','picked_up'));
 perform public.tkt_commerce('order_update',jsonb_build_object('id',o->>'id','status','delivered'));
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 details:=public.tkt_commerce('me');
 if (details->'restaurant_stats'->>'today_orders')::integer<>1 or (details->'restaurant_stats'->>'today_sales')::integer<>1000 then raise exception 'LIVE_DASHBOARD_TOTALS';end if;
 ledger:=public.tkt_commerce('courier_list');
 select value into record from jsonb_array_elements(ledger) where value->>'user_id'=courier_id::text;
 if (record->>'due')::integer<>1000+fee or (record->>'cash_collected')::integer<>2500+fee or (record->>'delivery_total')::integer<>1500 then raise exception 'LIVE_LEDGER_TOTAL';end if;
 st:=public.tkt_commerce('settlement_request',jsonb_build_object('kind','captain_restaurant','captain_id',courier_id));
 perform set_config('request.jwt.claim.sub',courier_id::text,true);
 perform public.tkt_commerce('settlement_confirm',jsonb_build_object('id',st->>'id','code',st->>'code'));
 ledger:=public.tkt_commerce('accounts');
 select value into record from jsonb_array_elements(ledger->'settlements') where value->>'id'=st->>'id';
 if record->>'status'<>'confirmed' or record->>'payer_name'<>'اختبار مندوب أول' or record->>'recipient_name'<>'اختبار توصيل خاص' then raise exception 'LIVE_SETTLEMENT_PARTIES';end if;
 perform set_config('request.jwt.claim.sub',captain_id::text,true);
 insert into tkt_private.captain_plans(user_id,plan,vehicle) values(captain_id,'commission','tuktuk');
 perform public.tkt_commerce('captain_preferences','{"receive_food":true,"receive_rides":true}');
 if tkt_private.captain_eligible(captain_id,false) or not tkt_private.captain_eligible(captain_id,true) then raise exception 'LIVE_COMMISSION_RULE';end if;
 perform tkt_private.dispatch_worker('presence',jsonb_build_object('user_id',captain_id,'online',true,'lat',29.1,'lng',38.1,'gps_at',clock_timestamp()));
 perform tkt_private.legacy_action('presence',jsonb_build_object('online',true,'lat',29.1,'lng',38.1));
 update tkt_private.captain_plans set plan='weekly' where user_id=captain_id;
 perform public.tkt_commerce('captain_preferences','{"receive_food":true,"receive_rides":false}');
 if not tkt_private.captain_eligible(captain_id,false) or tkt_private.captain_eligible(captain_id,true) then raise exception 'LIVE_WEEKLY_SELECTION';end if;
 perform tkt_private.dispatch_worker('presence',jsonb_build_object('user_id',captain_id,'online',true,'lat',29.1,'lng',38.1,'gps_at',clock_timestamp()));
 perform public.tkt_commerce('captain_preferences','{"receive_food":false,"receive_rides":false}');
 denied:=false;begin perform tkt_private.dispatch_worker('presence',jsonb_build_object('user_id',captain_id,'online',true,'lat',29.1,'lng',38.1,'gps_at',clock_timestamp()));exception when others then if sqlerrm<>'SUBSCRIPTION_EXPIRED' then raise;end if;denied:=true;end;
 if not denied then raise exception 'LIVE_PAUSED_SERVICES_STILL_ONLINE';end if;
end $$;
rollback;
select 'PASS: real deployed APIs — order, alert lifecycle, private isolation, first acceptance, details, delivery, cash ledger, settlement parties, commission/weekly rules, dispatch and legacy presence, dashboard totals. Fixtures rolled back.' as result;
