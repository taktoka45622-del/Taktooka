CREATE OR REPLACE FUNCTION tkt_private.extra(p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u uuid:=auth.uid(); adm boolean; target uuid; res jsonb; q public.tkt_quotes; r public.tkt_rides; c tkt_private.coupons; bal integer; disc integer:=0; due integer; ident uuid; value integer; room uuid; iscap boolean;
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 select captain into iscap from public.tkt_profiles where user_id=u and not blocked for update;
 if not found then raise exception 'ACCOUNT_BLOCKED';end if;
 adm:=tkt_private.is_admin() or case when p_action in('messages','read') then tkt_private.dashboard_permission('support') when p_action='send' then tkt_private.dashboard_permission('support',true) when p_action='admin_snapshot' then tkt_private.dashboard_permission('finance') or tkt_private.dashboard_permission('support') when p_action in('topup','settle','coupon_admin') then tkt_private.dashboard_permission('finance',true) else false end;
 insert into tkt_private.wallets(user_id) values(u) on conflict do nothing;
 insert into tkt_private.preferences(user_id) values(u) on conflict do nothing;
 if p_action='snapshot' then
  select jsonb_build_object('balance',(select balance from tkt_private.wallets where user_id=u),'coupon',(select to_jsonb(cc) from tkt_private.coupons cc join tkt_private.preferences pp on pp.coupon=cc.code where pp.user_id=u and cc.active and cc.expires_at>now() and (select count(*) from tkt_private.coupon_uses where code=cc.code)<cc.max_uses and not exists(select 1 from tkt_private.coupon_uses x where x.code=cc.code and x.user_id=u)),
   'coupon_selected',(select coupon from tkt_private.preferences where user_id=u),
   'coupon_history',coalesce((select jsonb_agg(to_jsonb(h) order by h.selected_at desc) from (select cc.*, ch.selected_at, cu.ride_id, case when cu.ride_id is not null then 'used' when cc.expires_at<=now() then 'expired' when not cc.active or (select count(*) from tkt_private.coupon_uses x where x.code=cc.code)>=cc.max_uses then 'unavailable' when pp.coupon=cc.code then 'active' else 'saved' end as status from tkt_private.coupon_history ch join tkt_private.coupons cc on cc.code=ch.code left join tkt_private.coupon_uses cu on cu.code=ch.code and cu.user_id=u left join tkt_private.preferences pp on pp.user_id=u where ch.user_id=u) h),'[]'::jsonb),
   'addresses',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from tkt_private.addresses a where user_id=u),'[]'::jsonb),
   'ledger',coalesce((select jsonb_agg(to_jsonb(l)) from (select amount,kind,created_at from tkt_private.ledger where user_id=u order by created_at desc limit 100)l),'[]'::jsonb),
   'unread',(select count(*) from public.tkt_messages m join tkt_private.preferences p on p.user_id=m.user_id where m.user_id=u and m.is_admin and m.created_at>p.user_read),
   'captain_requested',(select captain_requested_at is not null from tkt_private.preferences where user_id=u)) into res;
  return res;
 elsif p_action='book' then
  if iscap then raise exception 'RIDER_PROFILE_REQUIRED';end if;
  select * into q from public.tkt_quotes where id=(p_data->>'quote_id')::uuid and user_id=u for update;
  if q.id is null then raise exception 'QUOTE_INVALID';end if;
  select * into r from public.tkt_rides where quote_id=q.id;
  if r.id is not null then return to_jsonb(r);end if;
  if q.expires_at<=now() then raise exception 'QUOTE_EXPIRED';end if;
  if coalesce(p_data->>'payment_method','cash') not in ('cash','wallet') then raise exception 'INVALID_PAYMENT';end if;
  select cc.* into c from tkt_private.coupons cc join tkt_private.preferences pp on pp.coupon=cc.code where pp.user_id=u for update of cc;
  if c.code is not null then
   if not c.active or c.expires_at<=now() or exists(select 1 from tkt_private.coupon_uses where code=c.code and user_id=u) or (select count(*) from tkt_private.coupon_uses where code=c.code)>=c.max_uses then
    c:=null;
    update tkt_private.preferences set coupon=null where user_id=u;
   else disc:=case when c.reward_type='free_ride' then q.fare else least(q.fare,c.amount) end;end if;
  end if;
  due:=q.fare-disc;
  if p_data->>'payment_method'='wallet' then
   select balance into bal from tkt_private.wallets where user_id=u for update;
   if bal<due then raise exception 'INSUFFICIENT_BALANCE';end if;
  end if;
  res:=tkt_private.action('create',jsonb_build_object('quote_id',q.id));
  select * into r from public.tkt_rides where id=(res->>'id')::uuid;
  update public.tkt_rides set pickup_name=left(coalesce(p_data->>'pickup_name','موقع الانطلاق'),256),destination_name=left(coalesce(p_data->>'destination_name','الوجهة'),256),payment_method=coalesce(p_data->>'payment_method','cash'),discount=disc,customer_due=due,coupon_code=c.code,coupon_reward_type=coalesce(c.reward_type,'amount') where id=r.id returning * into r;
  if r.payment_method='wallet' then
   update tkt_private.wallets set balance=balance-due where user_id=u;
   insert into tkt_private.ledger(user_id,amount,kind,ride_id) values(u,-due,'ride_payment',r.id);
  end if;
  if c.code is not null then insert into tkt_private.coupon_uses(ride_id,code,user_id) values(r.id,c.code,u);end if;
  return to_jsonb(r);
 elsif p_action='coupon' then
  if coalesce(p_data->>'code','')='' then update tkt_private.preferences set coupon=null where user_id=u;return '{"ok":true}';end if;
  select * into c from tkt_private.coupons where code=upper(trim(p_data->>'code')) for update;
  if c.code is null or not c.active or c.expires_at<=now() or exists(select 1 from tkt_private.coupon_uses where code=c.code and user_id=u) or (select count(*) from tkt_private.coupon_uses where code=c.code)>=c.max_uses then raise exception 'COUPON_EXPIRED';end if;
  insert into tkt_private.coupon_history(user_id,code) values(u,c.code) on conflict(user_id,code) do update set selected_at=now();
  update tkt_private.preferences set coupon=c.code where user_id=u;
 elsif p_action='address_save' then
  if (select count(*) from tkt_private.addresses where user_id=u)>=30 then raise exception 'ADDRESS_LIMIT';end if;
  insert into tkt_private.addresses(user_id,label,lat,lng) values(u,trim(p_data->>'label'),(p_data->>'lat')::float8,(p_data->>'lng')::float8);
 elsif p_action='address_delete' then delete from tkt_private.addresses where id=(p_data->>'id')::uuid and user_id=u;
 elsif p_action='captain_apply' then
  if exists(select 1 from public.tkt_profiles where user_id=u and (name='' or phone='')) then raise exception 'INVALID_PROFILE';end if;
  update tkt_private.preferences set captain_requested_at=coalesce(captain_requested_at,now()) where user_id=u;
 elsif p_action in ('messages','send','read') then
  room:=coalesce((p_data->>'user_id')::uuid,u);
  if room<>u and not adm then raise exception 'FORBIDDEN';end if;
  if not exists(select 1 from public.tkt_profiles where user_id=room) then raise exception 'PROFILE_REQUIRED';end if;
  insert into tkt_private.preferences(user_id) values(room) on conflict do nothing;
  if p_action='send' then
   if (select count(*) from public.tkt_messages where sender_id=u and created_at>now()-interval '1 minute')>=30 then raise exception 'RATE_LIMIT';end if;
   ident:=(p_data->>'id')::uuid;
   if ident is null then raise exception 'INVALID_MESSAGE';end if;
   insert into public.tkt_messages(id,user_id,sender_id,is_admin,body) values(ident,room,u,adm,trim(p_data->>'body')) on conflict(id) do nothing;
  elsif p_action='read' then
   if adm and room<>u then update tkt_private.preferences set admin_read=now() where user_id=room;
   else update tkt_private.preferences set user_read=now() where user_id=room;end if;
  end if;
  return coalesce((select jsonb_agg(to_jsonb(m) order by m.created_at) from (select * from public.tkt_messages where user_id=room order by created_at desc limit 200)m),'[]'::jsonb);
 elsif p_action='admin_snapshot' then
  if not adm then raise exception 'ADMIN_REQUIRED';end if;
  return jsonb_build_object('wallets',coalesce((select jsonb_agg(to_jsonb(t)) from (select p.user_id,p.name,p.phone,p.captain,w.balance,pr.captain_requested_at from public.tkt_profiles p left join tkt_private.wallets w on w.user_id=p.user_id left join tkt_private.preferences pr on pr.user_id=p.user_id order by p.created_at desc limit 500)t),'[]'::jsonb),
   'coupons',coalesce((select jsonb_agg(to_jsonb(coupon_row)) from tkt_private.coupons coupon_row where coupon_row.batch_id is null),'[]'::jsonb),
   'rooms',coalesce((select jsonb_agg(to_jsonb(t)) from (select p.user_id,p.name,p.phone,max(m.created_at) as last_at,count(*) filter(where not m.is_admin and m.created_at>pr.admin_read) as unread from public.tkt_profiles p join public.tkt_messages m on m.user_id=p.user_id join tkt_private.preferences pr on pr.user_id=p.user_id group by p.user_id,pr.admin_read order by max(m.created_at) desc limit 500)t),'[]'::jsonb));
 elsif p_action in ('topup','settle') then
  if not adm then raise exception 'ADMIN_REQUIRED';end if;
  target:=(p_data->>'user_id')::uuid;ident:=(p_data->>'id')::uuid;value:=(p_data->>'amount')::integer;
  if ident is null or value is null or value not between 1 and 10000000 then raise exception 'INVALID_AMOUNT';end if;
  select captain into iscap from public.tkt_profiles where user_id=target and not blocked for update;
  if not found then raise exception 'PROFILE_REQUIRED';end if;
  if p_action='settle' and not iscap then raise exception 'CAPTAIN_REQUIRED';end if;
  if exists(select 1 from tkt_private.ledger where id=ident) then
   if not exists(select 1 from tkt_private.ledger where id=ident and user_id=target and actor_id=u and kind=p_action and amount=case when p_action='settle' then -value else value end) then raise exception 'REQUEST_CONFLICT';end if;
   return '{"ok":true}';
  end if;
  insert into tkt_private.wallets(user_id) values(target) on conflict do nothing;
  select balance into bal from tkt_private.wallets where user_id=target for update;
  if p_action='settle' and bal<value then raise exception 'INSUFFICIENT_BALANCE';end if;
  insert into tkt_private.ledger(id,user_id,amount,kind,actor_id) values(ident,target,case when p_action='settle' then -value else value end,p_action,u);
  update tkt_private.wallets set balance=balance+(case when p_action='settle' then -value else value end) where user_id=target;
 elsif p_action='coupon_admin' then
  if not adm then raise exception 'ADMIN_REQUIRED';end if;
  select * into c from tkt_private.coupons where code=upper(trim(p_data->>'code')) for update;
  if c.code is not null and exists(select 1 from tkt_private.coupon_history where code=c.code) and coalesce(p_data->>'reward_type',c.reward_type)<>c.reward_type then raise exception 'COUPON_TYPE_LOCKED';end if;
  if coalesce(p_data->>'reward_type',c.reward_type,'amount') not in ('amount','free_ride') then raise exception 'INVALID_COUPON_TYPE';end if;
  if (p_data->>'max_uses')::integer<(select count(*) from tkt_private.coupon_uses where code=c.code) then raise exception 'COUPON_USE_LIMIT';end if;
  insert into tkt_private.coupons(code,amount,expires_at,max_uses,active,reward_type) values(upper(trim(p_data->>'code')),case when coalesce(p_data->>'reward_type',c.reward_type,'amount')='free_ride' then 100000 else (p_data->>'amount')::integer end,(p_data->>'expires_at')::timestamptz,(p_data->>'max_uses')::integer,coalesce((p_data->>'active')::boolean,true),coalesce(p_data->>'reward_type',c.reward_type,'amount')) on conflict(code) do update set amount=excluded.amount,expires_at=excluded.expires_at,max_uses=excluded.max_uses,active=excluded.active,reward_type=excluded.reward_type;
 else raise exception 'UNKNOWN_ACTION';end if;
 return '{"ok":true}'::jsonb;
end $function$
;
CREATE OR REPLACE FUNCTION tkt_private.legacy_action(p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid:=auth.uid(); me public.tkt_profiles; r public.tkt_rides; q public.tkt_quotes; target uuid; until_at timestamptz; result jsonb; dist double precision;
begin
 if uid is null then raise exception 'AUTH_REQUIRED';end if;
 if p_action='me' then
  if not exists(select 1 from public.tkt_profiles where user_id=uid) then insert into public.tkt_profiles(user_id) values(uid) on conflict do nothing;end if;
  select * into me from public.tkt_profiles where user_id=uid;
  return to_jsonb(me)||jsonb_build_object('admin',tkt_private.is_admin());
 end if;
 if p_action in ('snapshot','contact') then select * into me from public.tkt_profiles where user_id=uid;else select * into me from public.tkt_profiles where user_id=uid for update;end if;
 if me.user_id is null then raise exception 'PROFILE_REQUIRED';end if;
 if me.blocked then raise exception 'ACCOUNT_BLOCKED';end if;
 if p_action='profile' then
  if length(trim(p_data->>'name')) not between 1 and 80 or coalesce(p_data->>'phone','') !~ '^(07[0-9]{9}|\+9647[0-9]{9})$' then raise exception 'INVALID_PROFILE';end if;
  if p_data ? 'gender' and coalesce(p_data->>'gender','') not in ('male','female') then raise exception 'PROFILE_GENDER_INVALID';end if;
  update public.tkt_profiles set name=trim(p_data->>'name'),phone=p_data->>'phone',gender=coalesce(p_data->>'gender',gender) where user_id=uid;
 elsif p_action='presence' then
  if not me.captain then raise exception 'CAPTAIN_REQUIRED';end if;
  if coalesce((p_data->>'online')::boolean,false) and coalesce(me.expires_at,now())<=now() and not exists(select 1 from public.tkt_rides where captain_id=uid and status in ('accepted','arrived','in_progress')) then raise exception 'SUBSCRIPTION_EXPIRED';end if;
  if (p_data->>'lat')::double precision not between 29 and 38 or (p_data->>'lng')::double precision not between 38 and 49 then raise exception 'OUTSIDE_SERVICE';end if;
  if p_data->>'lat' is null or p_data->>'lng' is null then raise exception 'LOCATION_REQUIRED';end if;
  update public.tkt_profiles set online=coalesce((p_data->>'online')::boolean,false),lat=(p_data->>'lat')::double precision,lng=(p_data->>'lng')::double precision,location_at=now() where user_id=uid;
 elsif p_action='create' then
  if me.captain or me.name='' or me.phone='' then raise exception 'RIDER_PROFILE_REQUIRED';end if;
  select * into q from public.tkt_quotes where id=(p_data->>'quote_id')::uuid and user_id=uid;
  if q.id is null then raise exception 'QUOTE_INVALID';end if;
  select * into r from public.tkt_rides where quote_id=q.id;
  if r.id is not null then return to_jsonb(r);end if;
  if q.expires_at<=now() then raise exception 'QUOTE_EXPIRED';end if;
  update public.tkt_rides set status='cancelled',updated_at=now() where rider_id=uid and status='pending' and created_at<now()-interval '10 minutes';
  insert into public.tkt_rides(quote_id,rider_id,pickup,destination,geometry,fare,distance_m,duration_s) values(q.id,uid,q.pickup,q.destination,q.geometry,q.fare,q.distance_m,q.duration_s) returning * into r;

  return to_jsonb(r);
 elsif p_action='snapshot' then
  select coalesce(jsonb_agg(to_jsonb(t)),'[]') into result from (select rr.* from public.tkt_rides rr where rr.rider_id=uid or rr.captain_id=uid order by rr.created_at desc limit 100)t;
  return result;
 elsif p_action='requests' then
  if not me.captain or not me.online or coalesce(me.expires_at,now())<=now() or me.location_at<now()-interval '90 seconds' then return '[]'::jsonb;end if;
  if exists(select 1 from public.tkt_rides where captain_id=uid and status in ('accepted','arrived','in_progress')) then return '[]'::jsonb;end if;
  select coalesce(jsonb_agg(to_jsonb(t)),'[]') into result from (
   select id,pickup,destination,fare,distance_m,duration_s,created_at,tkt_private.km(me.lat,me.lng,(pickup->>0)::float8,(pickup->>1)::float8) as away_km from public.tkt_rides
   where status='pending' and rider_id<>uid and created_at>now()-interval '10 minutes' and tkt_private.km(me.lat,me.lng,(pickup->>0)::float8,(pickup->>1)::float8)<=5 order by away_km,created_at limit 10)t;
  return result;
 elsif p_action='claim' then
  if not me.captain or not me.online or me.name='' or me.phone='' or coalesce(me.expires_at,now())<=now() or coalesce(me.location_at,now()-interval '1 day')<now()-interval '90 seconds' then raise exception 'CAPTAIN_UNAVAILABLE';end if;
  select * into r from public.tkt_rides where id=(p_data->>'ride_id')::uuid for update;
  if r.id is null or r.status<>'pending' or r.rider_id=uid or r.created_at<now()-interval '10 minutes' then raise exception 'RIDE_UNAVAILABLE';end if;
  if tkt_private.km(me.lat,me.lng,(r.pickup->>0)::float8,(r.pickup->>1)::float8)>5 then raise exception 'TOO_FAR';end if;
  update public.tkt_rides set captain_id=uid,status='accepted',updated_at=now() where id=r.id returning * into r;
  return to_jsonb(r)-'start_code';
 elsif p_action='ride_status' then
  select * into r from public.tkt_rides where id=(p_data->>'ride_id')::uuid for update;
  if r.id is null or (r.rider_id<>uid and r.captain_id is distinct from uid and not tkt_private.dashboard_permission('rides',true)) then raise exception 'FORBIDDEN';end if;
  if p_data->>'status'='cancelled' and r.status='cancelled' then
   return jsonb_build_object('ok',true);
  end if;
  if p_data->>'status'='cancelled' and (r.rider_id=uid or r.captain_id=uid or tkt_private.dashboard_permission('rides',true)) and r.status in ('pending','accepted','arrived') then
   update public.tkt_rides set status='cancelled',updated_at=now() where id=r.id;
  elsif r.captain_id=uid and me.captain and ((r.status='accepted' and p_data->>'status'='arrived') or (r.status='arrived' and p_data->>'status'='in_progress') or (r.status='in_progress' and p_data->>'status'='completed')) then
   update public.tkt_rides set status=p_data->>'status',updated_at=now() where id=r.id;
  else raise exception 'INVALID_STATUS_OR_CODE';end if;
 elsif p_action='contact' then
  select * into r from public.tkt_rides where id=(p_data->>'ride_id')::uuid;
  if r.id is null or r.status not in ('accepted','arrived','in_progress') or (r.rider_id<>uid and r.captain_id is distinct from uid) then raise exception 'FORBIDDEN';end if;
  target:=case when uid=r.rider_id then r.captain_id else r.rider_id end;
  select jsonb_build_object('name',name,'phone',phone,'lat',lat,'lng',lng,'location_at',location_at,'avatar_path',avatar_path,'subscription_active',coalesce(expires_at>clock_timestamp(),false)) into result from public.tkt_profiles where user_id=target;
  return result;
 elsif p_action='nearby' then
  select coalesce(jsonb_agg(to_jsonb(t)),'[]') into result from (select user_id,lat,lng,location_at from public.tkt_profiles p where captain and online and not blocked and expires_at>now() and location_at>now()-interval '90 seconds' and tkt_private.km((p_data->>'lat')::float8,(p_data->>'lng')::float8,lat,lng)<5 and not exists(select 1 from public.tkt_rides where captain_id=p.user_id and status in ('accepted','arrived','in_progress')) limit 30)t;
  return result;
 elsif p_action in ('role','renew','block') then
  perform tkt_private.require_dashboard('users',true);
  target:=(p_data->>'user_id')::uuid; if exists(select 1 from public.tkt_admins where user_id=target) or exists(select 1 from tkt_private.staff_accounts where user_id=target) then raise exception 'PROTECTED_ADMIN';end if;
  if exists(select 1 from public.tkt_rides where (captain_id=target or rider_id=target) and status in ('accepted','arrived','in_progress')) then raise exception 'ACTIVE_RIDE';end if;
  if p_action='role' then update public.tkt_profiles set captain=(p_data->>'captain')::boolean,online=false where user_id=target;
  elsif p_action='block' then update public.tkt_profiles set blocked=(p_data->>'blocked')::boolean,online=false where user_id=target;
  else
   select * into me from public.tkt_profiles where user_id=target for update;
   if me.user_id is null or not me.captain or me.blocked then raise exception 'INVALID_CAPTAIN';end if;
   if exists(select 1 from public.tkt_payments where id=(p_data->>'payment_id')::uuid) then
    if not exists(select 1 from public.tkt_payments where id=(p_data->>'payment_id')::uuid and captain_id=target and admin_id=uid and amount=5000) then raise exception 'REQUEST_CONFLICT';end if;
    return jsonb_build_object('ok',true);
   end if;
   until_at:=greatest(coalesce(me.expires_at,now()),now())+interval '7 days';
   insert into public.tkt_payments(id,captain_id,admin_id,expires_at) values((p_data->>'payment_id')::uuid,target,uid,until_at);
   update public.tkt_profiles set expires_at=until_at where user_id=target;
  end if;
 else raise exception 'UNKNOWN_ACTION';end if;
 return jsonb_build_object('ok',true);
end$function$
;
