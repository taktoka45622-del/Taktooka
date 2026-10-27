create table if not exists tkt_private.coupon_card_batches(
 id uuid primary key,
 created_by uuid references public.tkt_profiles(user_id) on delete set null,
 card_count integer not null check(card_count between 1 and 500),
 expires_at timestamptz not null,
 active boolean not null default true,
 created_at timestamptz not null default clock_timestamp()
);
alter table tkt_private.coupon_card_batches enable row level security;
revoke all on tkt_private.coupon_card_batches from public,anon,authenticated;
alter table tkt_private.coupons add column if not exists batch_id uuid references tkt_private.coupon_card_batches(id);
alter table tkt_private.coupons add column if not exists card_index integer;
alter table tkt_private.coupons add constraint coupon_printed_single_use check(batch_id is null or (reward_type='free_ride' and max_uses=1 and code ~ '^[0-9]{10}$' and card_index is not null and card_index between 1 and 500));
create unique index if not exists coupon_card_batch_order on tkt_private.coupons(batch_id,card_index) where batch_id is not null;
create or replace function tkt_private.coupon_cards(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $fn$
declare u uuid:=auth.uid(); batch tkt_private.coupon_card_batches; batch_id_value uuid; count_value integer; expiry timestamptz; active_value boolean; code_value text; i integer; attempts integer; inserted_code text;
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 perform tkt_private.require_dashboard('finance',p_action='generate');
 if not exists(select 1 from public.tkt_profiles where user_id=u and not blocked) then raise exception 'ACCOUNT_BLOCKED';end if;
 if p_action='list' then
  return coalesce((select jsonb_agg(to_jsonb(b) order by b.created_at desc) from(
   select b.*,(select count(*) from tkt_private.coupons c join tkt_private.coupon_uses x on x.code=c.code where c.batch_id=b.id) as used_cards
   from tkt_private.coupon_card_batches b order by b.created_at desc limit 50)b),'[]'::jsonb);
 elsif p_action='generate' then
  batch_id_value:=(p_data->>'id')::uuid;count_value:=(p_data->>'count')::integer;expiry:=(p_data->>'expires_at')::timestamptz;active_value:=coalesce((p_data->>'active')::boolean,true);
  if batch_id_value is null or count_value is null or count_value not between 1 and 500 or expiry is null or expiry<=clock_timestamp() then raise exception 'INVALID_CARD_BATCH';end if;
  perform 1 from public.tkt_profiles where user_id=u for update;
  select * into batch from tkt_private.coupon_card_batches where id=batch_id_value for update;
  if batch.id is not null then
   if batch.created_by is distinct from u or batch.card_count<>count_value or batch.expires_at<>expiry or batch.active<>active_value then raise exception 'CARD_BATCH_CONFLICT';end if;
  else
   insert into tkt_private.coupon_card_batches(id,created_by,card_count,expires_at,active)values(batch_id_value,u,count_value,expiry,active_value) returning * into batch;
   for i in 1..count_value loop
    attempts:=0;
    loop
     attempts:=attempts+1;
     if attempts>20 then raise exception 'CODE_GENERATION_FAILED';end if;
     code_value:=case when i=1 and attempts=1 and coalesce(p_data->>'first_code','') ~ '^[0-9]{10}$' then p_data->>'first_code'
      else (1000000000+(('x'||substr(replace(gen_random_uuid()::text,'-',''),1,15))::bit(60)::bigint % 9000000000))::text end;
     inserted_code:=null;
     insert into tkt_private.coupons(code,amount,expires_at,max_uses,active,reward_type,batch_id,card_index)
      values(code_value,100000,expiry,1,active_value,'free_ride',batch_id_value,i) on conflict(code) do nothing returning code into inserted_code;
     exit when inserted_code is not null;
    end loop;
   end loop;
   insert into tkt_private.admin_audit(actor_id,action,entity_id,details)values(u,'coupon_admin',batch_id_value::text,jsonb_build_object('generated_cards',count_value,'reward_type','free_ride'));
  end if;
 elsif p_action='get' then
  batch_id_value:=(p_data->>'id')::uuid;
  select * into batch from tkt_private.coupon_card_batches where id=batch_id_value;
  if batch.id is null then raise exception 'CARD_BATCH_NOT_FOUND';end if;
 else raise exception 'UNKNOWN_ACTION';end if;
 return to_jsonb(batch)||jsonb_build_object('codes',coalesce((select jsonb_agg(c.code order by c.card_index) from tkt_private.coupons c where c.batch_id=batch.id),'[]'::jsonb));
end $fn$;
revoke all on function tkt_private.coupon_cards(text,jsonb) from public,anon;
grant execute on function tkt_private.coupon_cards(text,jsonb) to authenticated;
create or replace function public.tkt_coupon_cards(p_action text,p_data jsonb default '{}'::jsonb) returns jsonb language sql security invoker set search_path='' as $fn$
 select tkt_private.coupon_cards(p_action,p_data);
$fn$;
revoke all on function public.tkt_coupon_cards(text,jsonb) from public,anon;
grant execute on function public.tkt_coupon_cards(text,jsonb) to authenticated;

