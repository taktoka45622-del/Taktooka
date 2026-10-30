begin;
do $$
declare rider uuid:=gen_random_uuid(); captain uuid:=gen_random_uuid(); q jsonb; r jsonb; f jsonb;
 minute integer; fee integer; balance integer; single integer; first_total integer; second_total integer; ride_id uuid; rejected boolean;
 payload jsonb:=jsonb_build_object('pickup',jsonb_build_array(33.54844,44.41179),
 'destination',jsonb_build_array(33.54800,44.41100),'geometry',jsonb_build_object('type','LineString','coordinates',jsonb_build_array(jsonb_build_array(44.41179,33.54844),jsonb_build_array(44.41100,33.54800))),
 'distance_m',1000,'duration_s',120,'route_provider','mapbox-driving-no-motorway','round_trip',true,
 'return_distance_m',1200,'return_duration_s',150,
 'return_geometry',jsonb_build_object('type','LineString','coordinates',jsonb_build_array(jsonb_build_array(44.41100,33.54800),jsonb_build_array(44.41179,33.54844))));
begin
 single:=(tkt_private.fare(1000,'2026-10-13 09:00:00+00')->>'fare')::integer;
 foreach minute in array array[1,10,11,15] loop
  fee:=case when minute<=10 then 250 else 500 end;
  f:=tkt_private.trip_fare(1000,'2026-10-13 09:00:00+00',true,minute);
  if (f->>'fare')::integer<>single*2+fee or (f->>'waiting_fee')::integer<>fee then raise exception 'WAIT_FARE_BOUNDARY_FAILED';end if;
 end loop;
 f:=tkt_private.trip_fare(1500,'2026-10-13 01:00:00+00',true,15);
 if (f->>'night_surcharge')::integer<>1000 or (f->>'fare')::integer<>2*(tkt_private.fare(1500,'2026-10-13 01:00:00+00')->>'fare')::integer+500 then raise exception 'ROUND_TRIP_NIGHT_FAILED';end if;
 f:=tkt_private.trip_fare(1000,'2026-10-13 09:00:00+00',false,0);
 if (f->>'fare')::integer<>single then raise exception 'ONE_WAY_PRICE_CHANGED';end if;
 rejected:=false;
 begin perform tkt_private.trip_fare(1000,now(),true,0);exception when others then
  if sqlerrm<>'WAIT_MINUTES_REQUIRED' then raise;end if;rejected:=true;end;
 if not rejected then raise exception 'MISSING_WAIT_ACCEPTED';end if;

 insert into auth.users(id,aud,role,email,raw_user_meta_data,raw_app_meta_data,created_at,updated_at)
 values(rider,'authenticated','authenticated',rider||'@round-trip-test.invalid','{}','{}',now(),now()),
 (captain,'authenticated','authenticated',captain||'@round-trip-test.invalid','{}','{}',now(),now());
 insert into public.tkt_profiles(user_id,name,phone,captain,expires_at)
 values(rider,'Round trip test rider','07000000001',false,null),
 (captain,'Round trip test captain','07000000002',true,now()+interval '1 day');
 insert into tkt_private.wallets(user_id,balance) values(rider,10000),(captain,0);
 perform set_config('request.jwt.claim.sub',rider::text,true);
 first_total:=2*(tkt_private.fare(1000,clock_timestamp())->>'fare')::integer+250;
 second_total:=first_total+250;
 q:=public.tkt_route_quote(rider,payload||jsonb_build_object('wait_minutes',10));
 if (q->>'fare')::integer<>first_total or (q->>'distance_m')::integer<>2200 or (q->>'duration_s')::integer<>870 then raise exception 'QUOTE_TOTAL_FAILED';end if;
 r:=tkt_private.dispatch('book',jsonb_build_object('quote_id',q->>'id','expected_fare',first_total,'payment_method','wallet'));
 ride_id:=(r->>'id')::uuid;
 if not (r->>'round_trip')::boolean or (r->>'wait_minutes')::integer<>10 or (r->>'fare')::integer<>first_total then raise exception 'BOOKING_METADATA_FAILED';end if;
 select w.balance into balance from tkt_private.wallets w where w.user_id=rider;
 if balance<>10000-first_total then raise exception 'WALLET_DEBIT_FAILED';end if;
 update public.tkt_rides set captain_id=captain,status='in_progress' where id=ride_id;
 rejected:=false;
 begin perform public.tkt_round_trip_phase(ride_id,'waiting');exception when others then
  if sqlerrm<>'CAPTAIN_REQUIRED' then raise;end if;rejected:=true;end;
 if not rejected then raise exception 'RIDER_CHANGED_CAPTAIN_PHASE';end if;
 rejected:=false;
 begin update public.tkt_rides set status='completed' where id=ride_id;exception when others then
  if sqlerrm<>'ROUND_TRIP_RETURN_REQUIRED' then raise;end if;rejected:=true;end;
 if not rejected then raise exception 'COMPLETED_BEFORE_RETURN';end if;
 perform set_config('request.jwt.claim.sub',captain::text,true);
 r:=public.tkt_round_trip_phase(ride_id,'waiting');
 if r->>'round_trip_stage'<>'waiting' or r->>'wait_started_at' is null then raise exception 'WAIT_START_FAILED';end if;
 r:=public.tkt_round_trip_phase(ride_id,'returning');
 if r->>'round_trip_stage'<>'returning' or r->'geometry'<>payload->'return_geometry' then raise exception 'RETURN_ROUTE_FAILED';end if;
 perform tkt_private.action('ride_status',jsonb_build_object('ride_id',ride_id,'status','completed'));
 select w.balance into balance from tkt_private.wallets w where w.user_id=captain;
 if balance<>first_total then raise exception 'CAPTAIN_CREDIT_FAILED';end if;

 perform set_config('request.jwt.claim.sub',rider::text,true);
 q:=public.tkt_route_quote(rider,payload||jsonb_build_object('wait_minutes',15));
 r:=tkt_private.dispatch('book',jsonb_build_object('quote_id',q->>'id','expected_fare',second_total,'payment_method','cash'));
 if (r->>'fare')::integer<>second_total or (r->>'waiting_fee')::integer<>500 then raise exception 'CASH_FARE_FAILED';end if;
 perform tkt_private.action('ride_status',jsonb_build_object('ride_id',r->>'id','status','cancelled'));

 q:=public.tkt_route_quote(rider,payload||jsonb_build_object('wait_minutes',11));
 r:=tkt_private.dispatch('book',jsonb_build_object('quote_id',q->>'id','expected_fare',second_total,'payment_method','wallet'));
 perform tkt_private.action('ride_status',jsonb_build_object('ride_id',r->>'id','status','cancelled'));
 select w.balance into balance from tkt_private.wallets w where w.user_id=rider;
 if balance<>10000-first_total then raise exception 'ROUND_TRIP_REFUND_FAILED';end if;
end $$;
select 'PASS: waiting boundaries, doubled fare/night, booking, wallet, cash, authorization, phases, return geometry, completion and refund' as result;
rollback;
