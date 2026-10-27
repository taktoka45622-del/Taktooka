create or replace function tkt_private.coupon_notification() returns trigger language plpgsql security definer set search_path='' as $fn$
begin
 return new;
end $fn$;
revoke all on function tkt_private.coupon_notification() from public,anon,authenticated;
delete from tkt_private.push_outbox o using public.tkt_notifications n where o.notification_id=n.id and n.kind='coupon' and n.event_key like 'coupon:%';
delete from public.tkt_notifications where kind='coupon' and event_key like 'coupon:%';
