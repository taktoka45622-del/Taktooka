begin;
do $test$
#variable_conflict use_variable
declare admin_id uuid:=gen_random_uuid(); customer uuid:=gen_random_uuid(); customer2 uuid:=gen_random_uuid(); captain uuid:=gen_random_uuid(); quote_id uuid; ride_id uuid; again jsonb; result jsonb; before_expiry timestamptz:=now()+interval '7 days'; after_expiry timestamptz; free_code text:='QA_'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)); amount_code text; cancel_code text; rejected boolean;
begin
 amount_code:=free_code||'_A';cancel_code:=free_code||'_C';
 insert into auth.users(id,email) values(admin_id,admin_id||'@example.invalid'),(customer,customer||'@example.invalid'),(customer2,customer2||'@example.invalid'),(captain,captain||'@example.invalid');
 insert into public.tkt_profiles(user_id,name,phone,captain,expires_at) values(admin_id,'QA admin','07000000001',false,null),(customer,'QA customer','07000000002',false,null),(customer2,'QA customer2','07000000003',false,null),(captain,'QA captain','07000000004',true,before_expiry);
 insert into public.tkt_admins(user_id)values(admin_id);
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 perform public.tkt_coupon_rewards('save',jsonb_build_object('code',free_code,'reward_type','free_ride','max_uses',1,'expires_at',now()+interval '1 day','active',true));
 perform public.tkt_coupon_rewards('save',jsonb_build_object('code',amount_code,'reward_type','amount','amount',1000,'max_uses',10,'expires_at',now()+interval '1 day','active',true));
 perform public.tkt_coupon_rewards('save',jsonb_build_object('code',cancel_code,'reward_type','free_ride','max_uses',1,'expires_at',now()+interval '1 day','active',true));
 perform set_config('request.jwt.claim.sub',customer::text,true);
 rejected:=false;begin perform public.tkt_coupon_rewards('list');exception when others then if sqlerrm='PERMISSION_DENIED' then rejected:=true;else raise;end if;end;
 if not rejected then raise exception 'TEST_CUSTOMER_PERMISSION';end if;
 perform public.tkt_extra('coupon',jsonb_build_object('code',lower(free_code)));
 if (public.tkt_extra('snapshot','{}')->'coupon'->>'reward_type')<>'free_ride' then raise exception 'TEST_FREE_ACTIVATION';end if;
 insert into public.tkt_quotes(user_id,pickup,destination,geometry,distance_m,duration_s,fare,route_distance_m,base_fare,night_surcharge,pricing_version,route_provider)
 values(customer,'[33.35,44.4]','[33.36,44.41]','{"type":"LineString","coordinates":[[44.4,33.35],[44.41,33.36]]}',3000,600,5000,3000,5000,0,'iqd-distance-v2','qa') returning id into quote_id;
 insert into tkt_private.booking_prices values(quote_id,now(),5000);
 result:=public.tkt_extra('book',jsonb_build_object('quote_id',quote_id,'payment_method','wallet'));ride_id:=(result->>'id')::uuid;
 if (result->>'customer_due')::integer<>0 or (result->>'discount')::integer<>5000 or result->>'coupon_reward_type'<>'free_ride' then raise exception 'TEST_FREE_PRICE';end if;
 again:=public.tkt_extra('book',jsonb_build_object('quote_id',quote_id,'payment_method','wallet'));
 if again->>'id'<>ride_id::text or (select count(*) from tkt_private.coupon_uses where code=free_code)<>1 then raise exception 'TEST_BOOK_IDEMPOTENCE';end if;
 if (select balance from tkt_private.wallets where user_id=customer)<>0 then raise exception 'TEST_ZERO_WALLET';end if;
 rejected:=false;begin perform public.tkt_extra('coupon',jsonb_build_object('code',free_code));exception when others then if sqlerrm='COUPON_EXPIRED' then rejected:=true;else raise;end if;end;
 if not rejected then raise exception 'TEST_SINGLE_USE';end if;
 perform set_config('request.jwt.claim.sub',customer2::text,true);
 rejected:=false;begin perform public.tkt_extra('coupon',jsonb_build_object('code',free_code));exception when others then if sqlerrm='COUPON_EXPIRED' then rejected:=true;else raise;end if;end;
 if not rejected then raise exception 'TEST_GLOBAL_USE_LIMIT';end if;
 update public.tkt_rides set captain_id=captain,status='accepted' where id=ride_id;
 if (select expires_at from public.tkt_profiles where user_id=captain)<>before_expiry then raise exception 'TEST_NO_EARLY_BONUS';end if;
 update public.tkt_rides set status='in_progress' where id=ride_id;
 update public.tkt_rides set status='completed' where id=ride_id;
 select expires_at into after_expiry from public.tkt_profiles where user_id=captain;
 if after_expiry<>before_expiry+interval '24 hours' then raise exception 'TEST_DAY_BONUS';end if;
 if (select count(*) from tkt_private.coupon_captain_rewards where coupon_captain_rewards.ride_id=ride_id)=0 then raise exception 'TEST_REWARD_LOG';end if;
 if exists(select 1 from tkt_private.ledger l where l.user_id=captain) then raise exception 'TEST_NO_CASH_FREE_REWARD';end if;
 update public.tkt_rides set status='completed' where id=ride_id;
 if (select expires_at from public.tkt_profiles where user_id=captain)<>after_expiry then raise exception 'TEST_BONUS_DUPLICATE';end if;
 perform set_config('request.jwt.claim.sub',customer::text,true);
 perform public.tkt_extra('coupon',jsonb_build_object('code',amount_code));
 insert into public.tkt_quotes(user_id,pickup,destination,geometry,distance_m,duration_s,fare,route_distance_m,base_fare,night_surcharge,pricing_version,route_provider)
 values(customer,'[33.35,44.4]','[33.36,44.41]','{"type":"LineString","coordinates":[[44.4,33.35],[44.41,33.36]]}',3000,600,5000,3000,5000,0,'iqd-distance-v2','qa') returning id into quote_id;
 insert into tkt_private.booking_prices values(quote_id,now(),5000);
 result:=public.tkt_extra('book',jsonb_build_object('quote_id',quote_id,'payment_method','cash'));ride_id:=(result->>'id')::uuid;
 if (result->>'customer_due')::integer<>4000 or (result->>'discount')::integer<>1000 then raise exception 'TEST_AMOUNT_PRICE';end if;
 update public.tkt_rides set captain_id=captain,status='accepted' where id=ride_id;
 update public.tkt_rides set status='in_progress' where id=ride_id;
 update public.tkt_rides set status='completed' where id=ride_id;
 if (select balance from tkt_private.wallets where user_id=captain)<>1000 then raise exception 'TEST_DISCOUNT_COMPENSATION';end if;
 if (select expires_at from public.tkt_profiles where user_id=captain)<>after_expiry then raise exception 'TEST_AMOUNT_NO_BONUS';end if;
 perform set_config('request.jwt.claim.sub',customer2::text,true);
 perform public.tkt_extra('coupon',jsonb_build_object('code',cancel_code));
 insert into public.tkt_quotes(user_id,pickup,destination,geometry,distance_m,duration_s,fare,route_distance_m,base_fare,night_surcharge,pricing_version,route_provider)
 values(customer2,'[33.35,44.4]','[33.36,44.41]','{"type":"LineString","coordinates":[[44.4,33.35],[44.41,33.36]]}',3000,600,5000,3000,5000,0,'iqd-distance-v2','qa') returning id into quote_id;
 insert into tkt_private.booking_prices values(quote_id,now(),5000);
 result:=public.tkt_extra('book',jsonb_build_object('quote_id',quote_id,'payment_method','cash'));ride_id:=(result->>'id')::uuid;
 update public.tkt_rides set status='cancelled' where id=ride_id;
 perform public.tkt_extra('coupon',jsonb_build_object('code',cancel_code));
 if exists(select 1 from tkt_private.coupon_uses where code=cancel_code) then raise exception 'TEST_CANCEL_RESTORE';end if;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 result:=public.tkt_coupon_rewards('history',jsonb_build_object('code',free_code));
 if jsonb_array_length(result->'rows')<>1 or (result->'rows'->0->>'days')::integer<>1 then raise exception 'TEST_ADMIN_HISTORY';end if;
 rejected:=false;begin perform public.tkt_coupon_rewards('save',jsonb_build_object('code',free_code,'reward_type','amount','amount',500,'max_uses',10,'expires_at',now()+interval '1 day'));exception when others then if sqlerrm='COUPON_TYPE_LOCKED' then rejected:=true;else raise;end if;end;
 if not rejected then raise exception 'TEST_TYPE_LOCK';end if;
 perform public.tkt_coupon_rewards('stop',jsonb_build_object('code',cancel_code));
 if (select active from tkt_private.coupons where code=cancel_code) then raise exception 'TEST_STOP';end if;
end $test$;
select 'Coupon activation, zero-fare wallet booking, amount discount, captain day, no cash duplication, single use, global limit, cancellation, permissions and history passed' as checks;

rollback;
