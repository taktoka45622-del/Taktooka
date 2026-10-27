alter table tkt_private.coupons add column if not exists reward_type text not null default 'amount' check(reward_type in ('amount','free_ride'));
alter table public.tkt_rides add column if not exists coupon_reward_type text not null default 'amount' check(coupon_reward_type in ('amount','free_ride'));
create table if not exists tkt_private.coupon_captain_rewards(
 ride_id uuid primary key references public.tkt_rides(id) on delete cascade,
 captain_id uuid not null references public.tkt_profiles(user_id) on delete cascade,
 code text not null,
 days integer not null default 1 check(days=1),
 previous_expiry timestamptz,
 expires_at timestamptz not null,
 created_at timestamptz not null default clock_timestamp()
);
alter table tkt_private.coupon_captain_rewards enable row level security;
revoke all on tkt_private.coupon_captain_rewards from public,anon,authenticated;
create index if not exists coupon_captain_rewards_captain on tkt_private.coupon_captain_rewards(captain_id);

do $patch$
declare body text; old_part text; new_part text;
begin
 select pg_get_functiondef('tkt_private.extra(text,jsonb)'::regprocedure) into body;
 old_part:='else disc:=least(q.fare,c.amount);end if;';
 new_part:='else disc:=case when c.reward_type=''free_ride'' then q.fare else least(q.fare,c.amount) end;end if;';
 if position(old_part in body)=0 then raise exception 'COUPON_BOOK_PATCH_MISMATCH';end if;
 body:=replace(body,old_part,new_part);
 old_part:='customer_due=due,coupon_code=c.code where id=r.id';
 new_part:='customer_due=due,coupon_code=c.code,coupon_reward_type=coalesce(c.reward_type,''amount'') where id=r.id';
 if position(old_part in body)=0 then raise exception 'COUPON_RIDE_PATCH_MISMATCH';end if;
 body:=replace(body,old_part,new_part);
 old_part:=$old$  insert into tkt_private.coupons(code,amount,expires_at,max_uses,active) values(upper(trim(p_data->>'code')),(p_data->>'amount')::integer,(p_data->>'expires_at')::timestamptz,(p_data->>'max_uses')::integer,coalesce((p_data->>'active')::boolean,true)) on conflict(code) do update set amount=excluded.amount,expires_at=excluded.expires_at,max_uses=excluded.max_uses,active=excluded.active;$old$;
 new_part:=$new$  select * into c from tkt_private.coupons where code=upper(trim(p_data->>'code')) for update;
  if c.code is not null and exists(select 1 from tkt_private.coupon_history where code=c.code) and coalesce(p_data->>'reward_type',c.reward_type)<>c.reward_type then raise exception 'COUPON_TYPE_LOCKED';end if;
  if coalesce(p_data->>'reward_type',c.reward_type,'amount') not in ('amount','free_ride') then raise exception 'INVALID_COUPON_TYPE';end if;
  if (p_data->>'max_uses')::integer<(select count(*) from tkt_private.coupon_uses where code=c.code) then raise exception 'COUPON_USE_LIMIT';end if;
  insert into tkt_private.coupons(code,amount,expires_at,max_uses,active,reward_type) values(upper(trim(p_data->>'code')),case when coalesce(p_data->>'reward_type',c.reward_type,'amount')='free_ride' then 100000 else (p_data->>'amount')::integer end,(p_data->>'expires_at')::timestamptz,(p_data->>'max_uses')::integer,coalesce((p_data->>'active')::boolean,true),coalesce(p_data->>'reward_type',c.reward_type,'amount')) on conflict(code) do update set amount=excluded.amount,expires_at=excluded.expires_at,max_uses=excluded.max_uses,active=excluded.active,reward_type=excluded.reward_type;$new$;
 if position(old_part in body)=0 then raise exception 'COUPON_ADMIN_PATCH_MISMATCH';end if;
 execute replace(body,old_part,new_part);
end $patch$;

create or replace function tkt_private.money_status() returns trigger language plpgsql security definer set search_path='' as $fn$
declare previous timestamptz; next_expiry timestamptz; granted uuid;
begin
 if new.status=old.status then return new;end if;
 if new.status='cancelled' and old.status in ('pending','accepted','arrived') then
  if old.payment_method='wallet' and coalesce(old.customer_due,old.fare)>0 then
   update tkt_private.wallets set balance=balance+coalesce(old.customer_due,old.fare) where user_id=old.rider_id;
   insert into tkt_private.ledger(user_id,amount,kind,ride_id) values(old.rider_id,coalesce(old.customer_due,old.fare),'refund',old.id);
  end if;
  delete from tkt_private.coupon_uses where ride_id=old.id;
 elsif new.status='completed' and old.status='in_progress' then
  if old.coupon_reward_type='free_ride' then
   if old.coupon_code is null or old.customer_due<>0 or old.discount<>old.fare or old.captain_id is null then raise exception 'INVALID_FREE_RIDE';end if;
   select expires_at into previous from public.tkt_profiles where user_id=old.captain_id and captain for update;
   if not found then raise exception 'CAPTAIN_REQUIRED';end if;
   next_expiry:=greatest(coalesce(previous,clock_timestamp()),clock_timestamp())+interval '24 hours';
   insert into tkt_private.coupon_captain_rewards(ride_id,captain_id,code,previous_expiry,expires_at)
    values(old.id,old.captain_id,old.coupon_code,previous,next_expiry) on conflict(ride_id) do nothing returning ride_id into granted;
   if granted is not null then
    update public.tkt_profiles set expires_at=next_expiry where user_id=old.captain_id;
    perform tkt_private.notification_add(old.captain_id,'free-ride-day:'||old.id,'subscription','انضاف يوم لاشتراكك','أكملت رحلة مجانية؛ انضاف يوم كامل لاشتراكك.',jsonb_build_object('screen','subscription','ride_id',old.id));
   end if;
  else
   insert into tkt_private.wallets(user_id) values(old.captain_id) on conflict do nothing;
   update tkt_private.wallets set balance=balance+(case when old.payment_method='wallet' then old.fare else old.discount end) where user_id=old.captain_id;
   if old.payment_method='wallet' or old.discount>0 then
    insert into tkt_private.ledger(user_id,amount,kind,ride_id) values(old.captain_id,case when old.payment_method='wallet' then old.fare else old.discount end,'captain_earning',old.id);
   end if;
  end if;
 end if;
 return new;
end $fn$;
revoke all on function tkt_private.money_status() from public,anon,authenticated;

create or replace function tkt_private.coupon_rewards(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $fn$
declare u uuid:=auth.uid(); result jsonb; code_value text:=upper(trim(p_data->>'code'));
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 perform tkt_private.require_dashboard('finance',p_action in('save','stop'));
 if not exists(select 1 from public.tkt_profiles where user_id=u and not blocked) then raise exception 'ACCOUNT_BLOCKED';end if;
 if p_action='list' then
  return jsonb_build_object('coupons',coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object(
   'uses',(select count(*) from tkt_private.coupon_uses x where x.code=c.code),
   'completed',(select count(*) from tkt_private.coupon_uses x join public.tkt_rides r on r.id=x.ride_id where x.code=c.code and r.status='completed'),
   'bonus_days',(select coalesce(sum(days),0) from tkt_private.coupon_captain_rewards b where b.code=c.code)
  ) order by c.expires_at desc,c.code) from tkt_private.coupons c),'[]'::jsonb),
  'bonus_days',(select coalesce(sum(days),0) from tkt_private.coupon_captain_rewards),
  'free_completed',(select count(*) from tkt_private.coupon_captain_rewards),
  'server_now',clock_timestamp());
 elsif p_action='save' then
  if (p_data->>'expires_at')::timestamptz<=clock_timestamp() then raise exception 'INVALID_EXPIRY';end if;
  result:=tkt_private.manage('coupon_admin',p_data);
 elsif p_action='stop' then
  perform 1 from tkt_private.coupons where code=code_value for update;
  if not found then raise exception 'COUPON_EXPIRED';end if;
  update tkt_private.coupons set active=false where code=code_value;
  insert into tkt_private.admin_audit(actor_id,action,entity_id,details)values(u,'coupon_admin',code_value,jsonb_build_object('active',false));
  result:='{"ok":true}';
 elsif p_action='history' then
  return jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (
   select r.id,r.created_at,r.status,r.coupon_reward_type,r.fare,r.discount,r.customer_due,p.name as customer_name,p.phone as customer_phone,
   c.user_id as captain_id,c.name as captain_name,c.phone as captain_phone,b.days,b.expires_at as captain_expires_at
   from public.tkt_rides r join public.tkt_profiles p on p.user_id=r.rider_id left join public.tkt_profiles c on c.user_id=r.captain_id
   left join tkt_private.coupon_captain_rewards b on b.ride_id=r.id where r.coupon_code=code_value
   order by r.created_at desc limit 50 offset greatest(0,coalesce((p_data->>'offset')::integer,0))
  )x),'[]'::jsonb));
 else raise exception 'UNKNOWN_ACTION';end if;
 return result;
end $fn$;
revoke all on function tkt_private.coupon_rewards(text,jsonb) from public,anon;
grant execute on function tkt_private.coupon_rewards(text,jsonb) to authenticated;
create or replace function public.tkt_coupon_rewards(p_action text,p_data jsonb default '{}'::jsonb) returns jsonb language sql security invoker set search_path='' as $fn$
 select tkt_private.coupon_rewards(p_action,p_data);
$fn$;
revoke all on function public.tkt_coupon_rewards(text,jsonb) from public,anon;
grant execute on function public.tkt_coupon_rewards(text,jsonb) to authenticated;

