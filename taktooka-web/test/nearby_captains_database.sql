begin;
do $$
declare rider uuid:=gen_random_uuid();cap uuid:=gen_random_uuid();data jsonb;present boolean;
begin
 insert into auth.users(id,aud,role,email,raw_user_meta_data,raw_app_meta_data,created_at,updated_at)
 values(rider,'authenticated','authenticated',rider||'@nearby-test.invalid','{}','{}',now(),now()),
 (cap,'authenticated','authenticated',cap||'@nearby-test.invalid','{}','{}',now(),now());
 insert into public.tkt_profiles(user_id,name,phone,captain,online,expires_at)
 values(rider,'Nearby rider','07000000007',false,false,null),(cap,'Nearby captain','07000000008',true,true,now()+interval '1 day');
 insert into tkt_private.dispatch_locations(captain_id,lat,lng,gps_at,received_at,zone,cell)
 values(cap,33.54844,44.41179,clock_timestamp(),clock_timestamp(),'husseiniya','883e8e9343fffff');
 perform set_config('request.jwt.claim.sub',rider::text,true);
 data:=tkt_private.action('nearby','{"lat":33.54844,"lng":44.41179}');
 select exists(select 1 from jsonb_array_elements(data)x where x->>'user_id'=cap::text) into present;
 if not present then raise exception 'FRESH_CAPTAIN_MISSING';end if;
 update tkt_private.dispatch_locations set lat=33.5486 where captain_id=cap;
 data:=tkt_private.action('nearby','{"lat":33.54844,"lng":44.41179}');
 if not exists(select 1 from jsonb_array_elements(data)x where x->>'user_id'=cap::text and (x->>'lat')::numeric=33.5486) then raise exception 'LOCATION_NOT_UPDATED';end if;
 update tkt_private.dispatch_locations set gps_at=clock_timestamp()-interval '5 minutes' where captain_id=cap;
 data:=tkt_private.action('nearby','{"lat":33.54844,"lng":44.41179}');
 if exists(select 1 from jsonb_array_elements(data)x where x->>'user_id'=cap::text) then raise exception 'STALE_CAPTAIN_VISIBLE';end if;
 update tkt_private.dispatch_locations set gps_at=clock_timestamp() where captain_id=cap;
 update public.tkt_profiles set online=false where user_id=cap;
 data:=tkt_private.action('nearby','{"lat":33.54844,"lng":44.41179}');
 if exists(select 1 from jsonb_array_elements(data)x where x->>'user_id'=cap::text) then raise exception 'OFFLINE_CAPTAIN_VISIBLE';end if;
end $$;
select 'PASS: nearby available captain, changing coordinates, stale hidden, offline hidden' as result;
rollback;
