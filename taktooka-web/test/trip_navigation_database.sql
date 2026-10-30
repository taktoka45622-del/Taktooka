begin;
do $$
declare rider uuid:=gen_random_uuid(); cap uuid:=gen_random_uuid(); stranger uuid:=gen_random_uuid();
 q public.tkt_quotes; trip public.tkt_rides; body jsonb; data jsonb;
begin
 insert into auth.users(id,aud,role,email,raw_user_meta_data,raw_app_meta_data,created_at,updated_at)
 values(rider,'authenticated','authenticated',rider||'@navigation-test.invalid','{}','{}',now(),now()),
 (cap,'authenticated','authenticated',cap||'@navigation-test.invalid','{}','{}',now(),now()),
 (stranger,'authenticated','authenticated',stranger||'@navigation-test.invalid','{}','{}',now(),now());
 insert into public.tkt_profiles(user_id,name,phone,captain,online,expires_at,lat,lng,location_at)
 values(rider,'Navigation rider','07000000001',false,false,null,null,null,null),
 (cap,'Navigation captain','07000000002',true,true,now()+interval '1 day',33.548,44.411,clock_timestamp()),
 (stranger,'Navigation other','07000000003',false,false,null,null,null,null);
 perform set_config('request.jwt.claim.sub',rider::text,true);
 data:=public.tkt_route_quote(rider,'{"pickup":[33.54844,44.41179],"destination":[33.55,44.415],"geometry":{"type":"LineString","coordinates":[[44.41179,33.54844],[44.415,33.55]]},"distance_m":1200,"duration_s":300,"route_provider":"mapbox-driving-no-motorway","round_trip":false,"wait_minutes":0}'::jsonb);
 select * into q from public.tkt_quotes where id=(data->>'id')::uuid;
 data:=tkt_private.dispatch('book',jsonb_build_object('quote_id',q.id,'expected_fare',q.fare,'lock_displayed_fare',true,'payment_method','cash'));
 update public.tkt_rides set captain_id=cap,status='accepted' where id=(data->>'id')::uuid returning * into trip;
 body:=jsonb_build_object('ride_id',trip.id,'phase','accepted:outbound:0','gps_at',clock_timestamp(),
 'geometry','{"type":"LineString","coordinates":[[44.411,33.548],[44.41179,33.54844]]}'::jsonb);
 perform set_config('request.jwt.claim.sub',cap::text,true);
 perform public.tkt_navigation('publish',body);
 perform set_config('request.jwt.claim.sub',rider::text,true);
 data:=public.tkt_navigation('read',jsonb_build_object('ride_id',trip.id));
 if public.tkt_navigation('read',jsonb_build_object('ride_id',trip.id,'known_updated_at',data->>'updated_at'))->>'unchanged' is distinct from 'true' then raise exception 'UNCHANGED_ROUTE_REDOWNLOADED';end if;
 if data->'geometry' is distinct from body->'geometry' then raise exception 'SHARED_ROUTE_MISSING';end if;
 begin
  perform public.tkt_navigation('publish',body);
  raise exception 'RIDER_PUBLISHED_ROUTE';
 exception when others then if sqlerrm<>'FORBIDDEN' then raise;end if;end;
 perform set_config('request.jwt.claim.sub',stranger::text,true);
 begin
  perform public.tkt_navigation('read',jsonb_build_object('ride_id',trip.id));
  raise exception 'OTHER_USER_READ_ROUTE';
 exception when others then if sqlerrm<>'FORBIDDEN' then raise;end if;end;
 if (select fare from public.tkt_rides where id=trip.id)<>q.fare then raise exception 'NAVIGATION_CHANGED_FARE';end if;
end $$;
select 'PASS: shared route, participant access, captain-only publish, unchanged fare' as result;
rollback;
