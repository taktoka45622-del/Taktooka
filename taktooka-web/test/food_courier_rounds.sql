begin;
do $t$
declare ord tkt_private.food_orders;actor uuid;rnd timestamptz;offer text;got text;
begin
 select o.* into ord from tkt_private.food_orders o join tkt_private.restaurants r on r.id=o.restaurant_id join public.tkt_profiles p on p.user_id=r.owner_id where not p.blocked and p.deleted_at is null limit 1;
 if ord.id is null then raise exception 'TEST_ORDER_MISSING';end if;
 select owner_id into actor from tkt_private.restaurants where id=ord.restaurant_id;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 rnd:=clock_timestamp();
 update tkt_private.food_orders set status='searching',captain_id=null,updated_at=rnd where id=ord.id;
 offer:='f:'||ord.id||':c:'||floor(extract(epoch from rnd)*1000000)::bigint::text;
 perform tkt_private.notification_add(actor,'test-offer:'||offer,'food','test','test',jsonb_build_object('order_id',ord.id,'request_type','courier','offer_id',offer),rnd+interval '120 seconds');
 if not tkt_private.food_offer_active(ord.id,rnd,actor) then raise exception 'LIVE_OFFER_NOT_ACTIVE';end if;
 perform public.tkt_commerce('offer_decline',jsonb_build_object('id',ord.id));
 if tkt_private.food_offer_active(ord.id,rnd,actor) then raise exception 'DECLINE_NOT_STOPPED';end if;
 if (select status from tkt_private.food_orders where id=ord.id)<>'searching' then raise exception 'DECLINE_CANCELLED_CUSTOMER_ORDER';end if;
 begin perform public.tkt_commerce('order_update',jsonb_build_object('id',ord.id,'status','accepted'));raise exception 'EXPIRED_ACCEPTED';exception when others then if sqlerrm<>'OFFER_EXPIRED' then raise;end if;end;
 perform public.tkt_commerce('order_update',jsonb_build_object('id',ord.id,'status','preparing'));
 if (select status from tkt_private.food_orders where id=ord.id)<>'preparing' then raise exception 'SEARCH_CANCEL_FAILED';end if;
 perform public.tkt_commerce('order_update',jsonb_build_object('id',ord.id,'status','rejected','reason','اختبار رفض الطلب'));
 if (select status from tkt_private.food_orders where id=ord.id)<>'rejected' then raise exception 'OWNER_REJECT_FAILED';end if;
end $t$;
rollback;
