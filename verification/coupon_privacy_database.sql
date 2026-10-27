begin;
do $test$
declare customer uuid:=gen_random_uuid(); other_customer uuid:=gen_random_uuid(); code1 text:='QA_'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));code2 text; snapshot jsonb;
begin
 code2:=code1||'_F';
 insert into auth.users(id,email)values(customer,customer||'@example.invalid'),(other_customer,other_customer||'@example.invalid');
 insert into public.tkt_profiles(user_id,name,phone)values(customer,'QA coupon recipient','07000000009'),(other_customer,'QA other recipient','07000000010');
 insert into tkt_private.coupons(code,amount,expires_at,max_uses,active,reward_type)values(code1,1000,now()+interval '1 day',1,true,'amount'),(code2,100000,now()+interval '1 day',1,true,'free_ride');
 update tkt_private.coupons set active=false where code in(code1,code2);
 update tkt_private.coupons set active=true where code in(code1,code2);
 if exists(select 1 from public.tkt_notifications where kind='coupon' and (event_key like 'coupon:'||code1||':%' or event_key like 'coupon:'||code2||':%')) then raise exception 'COUPON_BROADCAST_LEAK';end if;
 perform set_config('request.jwt.claim.sub',other_customer::text,true);
 snapshot:=public.tkt_extra('snapshot','{}');
 if snapshot->'coupon'<>'null'::jsonb or jsonb_array_length(snapshot->'coupon_history')<>0 then raise exception 'UNASSIGNED_COUPON_LEAK';end if;
 perform set_config('request.jwt.claim.sub',customer::text,true);
 perform public.tkt_extra('coupon',jsonb_build_object('code',code2));
 snapshot:=public.tkt_extra('snapshot','{}');
 if snapshot->'coupon'->>'code'<>code2 then raise exception 'EXPLICIT_ACTIVATION_FAILED';end if;
 perform set_config('request.jwt.claim.sub',other_customer::text,true);
 snapshot:=public.tkt_extra('snapshot','{}');
 if snapshot->'coupon'<>'null'::jsonb or jsonb_array_length(snapshot->'coupon_history')<>0 then raise exception 'OTHER_CUSTOMER_LEAK';end if;
end $test$;
select jsonb_build_object('broadcast_notifications',(select count(*) from public.tkt_notifications where kind='coupon' and event_key like 'coupon:%'),'queued_broadcasts',(select count(*) from tkt_private.push_outbox o join public.tkt_notifications n on n.id=o.notification_id where n.kind='coupon' and n.event_key like 'coupon:%'),'checks','Create, reactivate and explicit customer activation verified without code broadcasting') as checks;
rollback;
