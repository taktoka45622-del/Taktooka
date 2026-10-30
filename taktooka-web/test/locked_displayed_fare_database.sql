begin;
do $$
declare rider uuid:=gen_random_uuid();q jsonb;fresh jsonb;r jsonb;old_price int;balance int;rejected boolean;expired jsonb;
 payload jsonb:='{"pickup":[33.54844,44.41179],"destination":[33.548,44.411],"geometry":{"type":"LineString","coordinates":[[44.41179,33.54844],[44.411,33.548]]},"distance_m":400,"duration_s":120,"route_provider":"mapbox-driving-no-motorway","round_trip":false,"wait_minutes":0}';
begin
 insert into auth.users(id,aud,role,email,raw_user_meta_data,raw_app_meta_data,created_at,updated_at)
 values(rider,'authenticated','authenticated',rider||'@locked-fare-test.invalid','{}','{}',now(),now());
 insert into public.tkt_profiles(user_id,name,phone,captain) values(rider,'Locked fare test','07000000009',false);
 insert into tkt_private.wallets(user_id,balance) values(rider,10000);
 perform set_config('request.jwt.claim.sub',rider::text,true);
 q:=public.tkt_route_quote(rider,payload);old_price:=(q->>'fare')::integer;
 update tkt_private.pricing_settings set tiers=(select jsonb_agg(jsonb_set(t,'{fare}',to_jsonb((t->>'fare')::integer+1000))) from jsonb_array_elements(tiers)t),revision=revision+1 where id;
 fresh:=public.tkt_route_quote(rider,payload);
 if (fresh->>'fare')::int<>old_price+1000 then raise exception 'NEW_TARIFF_NOT_APPLIED';end if;
 rejected:=false;
 begin perform tkt_private.dispatch('book',jsonb_build_object('quote_id',q->>'id','expected_fare',1,'lock_displayed_fare',true,'payment_method','wallet'));exception when others then if sqlerrm<>'QUOTE_INVALID' then raise;end if;rejected:=true;end;
 if not rejected then raise exception 'FORGED_PRICE_ACCEPTED';end if;
 r:=tkt_private.dispatch('book',jsonb_build_object('quote_id',q->>'id','expected_fare',old_price,'lock_displayed_fare',true,'payment_method','wallet'));
 if (r->>'fare')::int<>old_price or r?'price_changed' then raise exception 'DISPLAYED_PRICE_CHANGED';end if;
 select w.balance into balance from tkt_private.wallets w where w.user_id=rider;
 if balance<>10000-old_price then raise exception 'WRONG_WALLET_DEBIT';end if;
 r:=tkt_private.dispatch('book',jsonb_build_object('quote_id',q->>'id','expected_fare',old_price,'lock_displayed_fare',true,'payment_method','wallet'));
 select w.balance into balance from tkt_private.wallets w where w.user_id=rider;
 if balance<>10000-old_price then raise exception 'DUPLICATE_DEBIT';end if;
 perform tkt_private.action('ride_status',jsonb_build_object('ride_id',r->>'id','status','cancelled'));
 expired:=public.tkt_route_quote(rider,payload);
 update public.tkt_quotes set expires_at=clock_timestamp()-interval '1 second' where id=(expired->>'id')::uuid;
 rejected:=false;
 begin perform tkt_private.dispatch('book',jsonb_build_object('quote_id',expired->>'id','expected_fare',expired->>'fare','lock_displayed_fare',true,'payment_method','cash'));exception when others then if sqlerrm<>'QUOTE_EXPIRED' then raise;end if;rejected:=true;end;
 if not rejected then raise exception 'EXPIRED_QUOTE_ACCEPTED';end if;
end $$;
select 'PASS: new tariffs sync, displayed fare locked, forged price rejected, wallet exact, retry idempotent, expired quote rejected' as result;
rollback;
