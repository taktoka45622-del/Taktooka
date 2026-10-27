alter table tkt_private.coupon_card_batches drop constraint coupon_card_batches_card_count_check;
alter table tkt_private.coupon_card_batches add constraint coupon_card_batches_card_count_check check(card_count between 1 and 100000);
alter table tkt_private.coupon_card_batches add column if not exists first_code text;
alter table tkt_private.coupons drop constraint coupon_printed_single_use;
alter table tkt_private.coupons add constraint coupon_printed_single_use check(batch_id is null or (reward_type='free_ride' and max_uses=1 and code ~ '^[0-9]{10}$' and card_index is not null and card_index between 1 and 100000));
do $copy$
declare body text;
begin
 if to_regprocedure('tkt_private.coupon_cards_v1(text,jsonb)') is null then
  select pg_get_functiondef('tkt_private.coupon_cards(text,jsonb)'::regprocedure) into body;
  execute replace(body,'FUNCTION tkt_private.coupon_cards(','FUNCTION tkt_private.coupon_cards_v1(');
 end if;
end $copy$;
revoke all on function tkt_private.coupon_cards_v1(text,jsonb) from public,anon,authenticated;
create or replace function tkt_private.coupon_cards(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $fn$
declare u uuid:=auth.uid(); b tkt_private.coupon_card_batches; ident uuid; count_value integer; expiry timestamptz; active_value boolean; generated integer; i integer; attempts integer; code_value text; inserted_code text; offn integer; lim integer;
begin
 if p_action not in ('start','fill','get_page') then return tkt_private.coupon_cards_v1(p_action,p_data);end if;
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 perform tkt_private.require_dashboard('finance',p_action in('start','fill'));
 if not exists(select 1 from public.tkt_profiles where user_id=u and not blocked) then raise exception 'ACCOUNT_BLOCKED';end if;
 ident:=(p_data->>'id')::uuid;if ident is null then raise exception 'INVALID_CARD_BATCH';end if;
 if p_action='start' then
  count_value:=(p_data->>'count')::integer;expiry:=(p_data->>'expires_at')::timestamptz;active_value:=coalesce((p_data->>'active')::boolean,true);
  if count_value is null or count_value not between 1 and 100000 or expiry is null or expiry<=clock_timestamp() then raise exception 'INVALID_CARD_BATCH';end if;
  perform 1 from public.tkt_profiles where user_id=u for update;
  select * into b from tkt_private.coupon_card_batches where id=ident for update;
  if b.id is not null then
   if b.created_by is distinct from u or b.card_count<>count_value or b.expires_at<>expiry or b.active<>active_value then raise exception 'CARD_BATCH_CONFLICT';end if;
  else
   insert into tkt_private.coupon_card_batches(id,created_by,card_count,expires_at,active,first_code)
    values(ident,u,count_value,expiry,active_value,case when coalesce(p_data->>'first_code','') ~ '^[0-9]{10}$' then p_data->>'first_code' end) returning * into b;
   insert into tkt_private.admin_audit(actor_id,action,entity_id,details)values(u,'coupon_admin',ident::text,jsonb_build_object('generated_cards',count_value,'reward_type','free_ride'));
  end if;
 else
  select * into b from tkt_private.coupon_card_batches where id=ident for update;
  if b.id is null then raise exception 'CARD_BATCH_NOT_FOUND';end if;
 end if;
 select coalesce(max(card_index),0) into generated from tkt_private.coupons where batch_id=b.id;
 if p_action='fill' and generated<b.card_count and coalesce((p_data->>'after')::integer,generated)=generated then
  if b.expires_at<=clock_timestamp() then raise exception 'INVALID_EXPIRY';end if;
  for i in generated+1..least(b.card_count,generated+500) loop
   attempts:=0;
   loop
    attempts:=attempts+1;if attempts>20 then raise exception 'CODE_GENERATION_FAILED';end if;
    code_value:=case when i=1 and attempts=1 and b.first_code is not null then b.first_code else (1000000000+(('x'||substr(replace(gen_random_uuid()::text,'-',''),1,15))::bit(60)::bigint % 9000000000))::text end;
    inserted_code:=null;
    insert into tkt_private.coupons(code,amount,expires_at,max_uses,active,reward_type,batch_id,card_index)
     values(code_value,100000,b.expires_at,1,b.active,'free_ride',b.id,i) on conflict(code)do nothing returning code into inserted_code;
    exit when inserted_code is not null;
   end loop;
  end loop;
  select coalesce(max(card_index),0) into generated from tkt_private.coupons where batch_id=b.id;
 end if;
 if p_action='get_page' then
  offn:=greatest(0,coalesce((p_data->>'offset')::integer,0));lim:=least(5000,greatest(1,coalesce((p_data->>'limit')::integer,2000)));
  return to_jsonb(b)||jsonb_build_object('generated_count',generated,'codes',coalesce((select jsonb_agg(x.code order by x.card_index) from(select code,card_index from tkt_private.coupons where batch_id=b.id and card_index>offn order by card_index limit lim)x),'[]'::jsonb));
 end if;
 return to_jsonb(b)||jsonb_build_object('generated_count',generated);
end $fn$;
revoke all on function tkt_private.coupon_cards(text,jsonb) from public,anon;
grant execute on function tkt_private.coupon_cards(text,jsonb) to authenticated;

do $performance$
declare body text; needle text;
begin
 select pg_get_functiondef('tkt_private.coupon_rewards(text,jsonb)'::regprocedure) into body;
 needle:='from tkt_private.coupons c),''[]''::jsonb)';
 if position(needle in body)=0 then raise exception 'COUPON_LIST_PATCH_MISMATCH';end if;
 execute replace(body,needle,'from tkt_private.coupons c where c.batch_id is null),''[]''::jsonb)');
 select pg_get_functiondef('tkt_private.extra(text,jsonb)'::regprocedure) into body;
 needle:='from tkt_private.coupons coupon_row),''[]''::jsonb)';
 if position(needle in body)=0 then raise exception 'COUPON_SNAPSHOT_PATCH_MISMATCH';end if;
 execute replace(body,needle,'from tkt_private.coupons coupon_row where coupon_row.batch_id is null),''[]''::jsonb)');
end $performance$;
