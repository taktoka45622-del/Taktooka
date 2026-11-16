create or replace function tkt_private.inventory_finance(p_action text, p_data jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_category text := coalesce(p_data->>'category','');
  v_search text := lower(trim(coalesce(p_data->>'search','')));
  v_limit integer := least(100, greatest(1, coalesce((p_data->>'limit')::integer,30)));
  v_offset integer := greatest(0, coalesce((p_data->>'offset')::integer,0));
  v_rows jsonb := '[]'::jsonb;
  v_total bigint := 0;
  v_result jsonb;
begin
  if auth.uid() is null or not tkt_private.dashboard_permission('inventory') then
    raise exception 'PERMISSION_DENIED';
  end if;

  if p_action = 'summary' then
    select jsonb_build_object(
      'completed_rides',(select count(*) from public.tkt_rides where status='completed'),
      'completed_food_orders',(select count(*) from tkt_private.food_orders where status='delivered'),
      'captains_weekly',(select count(*) from public.tkt_profiles p left join tkt_private.captain_plans cp on cp.user_id=p.user_id where p.captain and not p.blocked and p.deleted_at is null and coalesce(cp.plan,'weekly')='weekly' and p.expires_at>clock_timestamp()),
      'captains_commission',(select count(*) from public.tkt_profiles p join tkt_private.captain_plans cp on cp.user_id=p.user_id where p.captain and not p.blocked and p.deleted_at is null and cp.plan='commission'),
      'captains_no_ride_2d',(select count(*) from public.tkt_profiles p where p.captain and not p.blocked and p.deleted_at is null and not exists(select 1 from public.tkt_rides r where r.captain_id=p.user_id and r.created_at>=clock_timestamp()-interval '48 hours')),
      'customers',(select count(*) from public.tkt_profiles p where not p.captain and not p.blocked and p.deleted_at is null and not exists(select 1 from public.tkt_admins a where a.user_id=p.user_id) and not exists(select 1 from tkt_private.staff_accounts s where s.user_id=p.user_id) and not exists(select 1 from tkt_private.exchange_agents e where e.user_id=p.user_id)),
      'restaurant_service_due',(select coalesce(sum(d.amount),0) from tkt_private.commerce_debts d where d.kind='restaurant_fee' and d.settled_at is null),
      'taxi_commission_due',(select coalesce(sum(d.amount),0) from tkt_private.commerce_debts d where d.kind='captain_company' and d.settled_at is null and exists(select 1 from public.tkt_rides r where r.id=d.source_id)),
      'food_commission_due',(select coalesce(sum(d.amount),0) from tkt_private.commerce_debts d where d.kind='captain_company' and d.settled_at is null and exists(select 1 from tkt_private.food_orders f where f.id=d.source_id)),
      'exchange_funds',(select coalesce(sum(greatest(e.balance,0)),0) from tkt_private.exchange_agents e where e.deleted_at is null),
      'company_profit',
        (select coalesce(sum(p.amount),0) from public.tkt_payments p)
        +(select coalesce(sum(d.amount),0) from tkt_private.commerce_debts d where d.kind in('restaurant_fee','captain_company'))
        -(select coalesce(sum(e.amount),0) from tkt_private.company_expenses e where e.voided_at is null),
      'server_now',clock_timestamp()
    ) into v_result;
    return v_result;
  end if;

  if p_action <> 'rows' then raise exception 'UNKNOWN_ACTION'; end if;

  if v_category='completed_rides' then
    select count(*) into v_total from public.tkt_rides r left join public.tkt_profiles c on c.user_id=r.captain_id left join public.tkt_profiles u on u.user_id=r.rider_id where r.status='completed' and (v_search='' or concat_ws(' ',r.id,r.pickup_name,r.destination_name,c.name,c.phone,u.name,u.phone) ilike '%'||v_search||'%');
    select coalesce(jsonb_agg(to_jsonb(x)),'[]') into v_rows from (select r.id,r.status,r.created_at,r.updated_at,r.fare,r.pickup_name,r.destination_name,r.rider_id,r.captain_id,u.name customer_name,u.phone customer_phone,c.name captain_name,c.phone captain_phone from public.tkt_rides r left join public.tkt_profiles c on c.user_id=r.captain_id left join public.tkt_profiles u on u.user_id=r.rider_id where r.status='completed' and (v_search='' or concat_ws(' ',r.id,r.pickup_name,r.destination_name,c.name,c.phone,u.name,u.phone) ilike '%'||v_search||'%') order by r.updated_at desc,r.id desc limit v_limit offset v_offset)x;
  elsif v_category='completed_food_orders' then
    select count(*) into v_total from tkt_private.food_orders f left join public.tkt_profiles c on c.user_id=f.captain_id left join public.tkt_profiles u on u.user_id=f.customer_id left join tkt_private.restaurants r on r.id=f.restaurant_id where f.status='delivered' and (v_search='' or concat_ws(' ',f.id,r.name,r.phone,c.name,c.phone,u.name,u.phone) ilike '%'||v_search||'%');
    select coalesce(jsonb_agg(to_jsonb(x)),'[]') into v_rows from (select f.id,f.status,f.created_at,f.updated_at,f.food_total,f.delivery_fee,f.service_fee,f.commission_amount,f.commission_percent,f.customer_id,u.name customer_name,u.phone customer_phone,f.captain_id,c.name captain_name,c.phone captain_phone,f.restaurant_id,r.name restaurant_name,r.phone restaurant_phone from tkt_private.food_orders f left join public.tkt_profiles c on c.user_id=f.captain_id left join public.tkt_profiles u on u.user_id=f.customer_id left join tkt_private.restaurants r on r.id=f.restaurant_id where f.status='delivered' and (v_search='' or concat_ws(' ',f.id,r.name,r.phone,c.name,c.phone,u.name,u.phone) ilike '%'||v_search||'%') order by f.updated_at desc,f.id desc limit v_limit offset v_offset)x;
  elsif v_category in('captains_weekly','captains_commission','captains_no_ride_2d') then
    select count(*) into v_total from public.tkt_profiles p left join tkt_private.captain_plans cp on cp.user_id=p.user_id where p.captain and not p.blocked and p.deleted_at is null and (case v_category when 'captains_weekly' then coalesce(cp.plan,'weekly')='weekly' and p.expires_at>clock_timestamp() when 'captains_commission' then cp.plan='commission' else not exists(select 1 from public.tkt_rides r where r.captain_id=p.user_id and r.created_at>=clock_timestamp()-interval '48 hours') end) and (v_search='' or concat_ws(' ',p.name,p.phone,p.user_id) ilike '%'||v_search||'%');
    select coalesce(jsonb_agg(to_jsonb(x)),'[]') into v_rows from (select p.user_id,p.name,p.phone,p.expires_at,p.created_at,coalesce(cp.plan,'weekly') plan,cp.vehicle,(select max(r.created_at) from public.tkt_rides r where r.captain_id=p.user_id) last_ride_at from public.tkt_profiles p left join tkt_private.captain_plans cp on cp.user_id=p.user_id where p.captain and not p.blocked and p.deleted_at is null and (case v_category when 'captains_weekly' then coalesce(cp.plan,'weekly')='weekly' and p.expires_at>clock_timestamp() when 'captains_commission' then cp.plan='commission' else not exists(select 1 from public.tkt_rides r where r.captain_id=p.user_id and r.created_at>=clock_timestamp()-interval '48 hours') end) and (v_search='' or concat_ws(' ',p.name,p.phone,p.user_id) ilike '%'||v_search||'%') order by p.name,p.user_id limit v_limit offset v_offset)x;
  elsif v_category='restaurant_service_due' then
    select count(*) into v_total from (select coalesce(d.restaurant_id::text,d.debtor_id::text) k from tkt_private.commerce_debts d left join tkt_private.restaurants r on r.id=d.restaurant_id left join public.tkt_profiles p on p.user_id=d.debtor_id where d.kind='restaurant_fee' and d.settled_at is null and (v_search='' or concat_ws(' ',r.name,r.phone,r.address,p.name,p.phone,d.debtor_id) ilike '%'||v_search||'%') group by coalesce(d.restaurant_id::text,d.debtor_id::text))g;
    select coalesce(jsonb_agg(to_jsonb(x)),'[]') into v_rows from (select coalesce(d.restaurant_id::text,d.debtor_id::text) id,max(d.restaurant_id::text) restaurant_id,max(d.debtor_id::text) owner_id,coalesce(max(r.name),max(p.name),'حساب مطعم سابق') name,coalesce(max(r.phone),max(p.phone)) phone,max(r.address) address,sum(d.amount) amount,count(*) debt_count,max(d.created_at) last_debt_at,bool_or(r.id is null) legacy_unlinked from tkt_private.commerce_debts d left join tkt_private.restaurants r on r.id=d.restaurant_id left join public.tkt_profiles p on p.user_id=d.debtor_id where d.kind='restaurant_fee' and d.settled_at is null and (v_search='' or concat_ws(' ',r.name,r.phone,r.address,p.name,p.phone,d.debtor_id) ilike '%'||v_search||'%') group by coalesce(d.restaurant_id::text,d.debtor_id::text) order by sum(d.amount) desc limit v_limit offset v_offset)x;
  elsif v_category in('taxi_commission_due','food_commission_due') then
    select count(*) into v_total from tkt_private.commerce_debts d join public.tkt_profiles p on p.user_id=d.debtor_id where d.kind='captain_company' and d.settled_at is null and ((v_category='taxi_commission_due' and exists(select 1 from public.tkt_rides r where r.id=d.source_id)) or (v_category='food_commission_due' and exists(select 1 from tkt_private.food_orders f where f.id=d.source_id))) and (v_search='' or concat_ws(' ',p.name,p.phone,d.source_id) ilike '%'||v_search||'%');
    select coalesce(jsonb_agg(to_jsonb(x)),'[]') into v_rows from (select d.id,d.source_id,d.amount,d.created_at,p.user_id,p.name captain_name,p.phone captain_phone,case when v_category='taxi_commission_due' then 'رحلة تكسي' else 'طلب طعام' end source_type,coalesce(r.pickup_name||' ← '||r.destination_name,f.id::text) source_label,coalesce(r.created_at,f.created_at) source_created_at from tkt_private.commerce_debts d join public.tkt_profiles p on p.user_id=d.debtor_id left join public.tkt_rides r on r.id=d.source_id left join tkt_private.food_orders f on f.id=d.source_id where d.kind='captain_company' and d.settled_at is null and ((v_category='taxi_commission_due' and r.id is not null) or (v_category='food_commission_due' and f.id is not null)) and (v_search='' or concat_ws(' ',p.name,p.phone,d.source_id,r.pickup_name,r.destination_name,f.id) ilike '%'||v_search||'%') order by d.created_at desc,d.id limit v_limit offset v_offset)x;
  elsif v_category='exchange_funds' then
    select count(*) into v_total from tkt_private.exchange_agents e where e.deleted_at is null and e.balance>0 and (v_search='' or concat_ws(' ',e.name,e.phone,e.personal_name,e.personal_phone,e.province,e.area,e.street) ilike '%'||v_search||'%');
    select coalesce(jsonb_agg(to_jsonb(x)),'[]') into v_rows from (select e.id,e.name,e.phone,e.personal_name,e.personal_phone,e.province,e.area,e.street,e.balance,e.active,e.created_at,e.location_at from tkt_private.exchange_agents e where e.deleted_at is null and e.balance>0 and (v_search='' or concat_ws(' ',e.name,e.phone,e.personal_name,e.personal_phone,e.province,e.area,e.street) ilike '%'||v_search||'%') order by e.balance desc,e.name limit v_limit offset v_offset)x;
  elsif v_category='company_profit' then
    select count(*) into v_total from (select p.id from public.tkt_payments p union all select d.id from tkt_private.commerce_debts d where d.kind in('restaurant_fee','captain_company') union all select e.id from tkt_private.company_expenses e where e.voided_at is null) all_rows;
    select coalesce(jsonb_agg(to_jsonb(x)),'[]') into v_rows from (select * from (
      select p.id::text id,'اشتراك كابتن' kind,p.amount amount,p.created_at,pr.name person_name,pr.phone person_phone,'دفعة اشتراك' details from public.tkt_payments p left join public.tkt_profiles pr on pr.user_id=p.captain_id
      union all select d.id::text,'رسوم خدمة المطعم',d.amount,d.created_at,coalesce(r.name,pr.name),coalesce(r.phone,pr.phone),case when r.id is null then 'سجل سابق غير مرتبط بمطعم' else r.address end from tkt_private.commerce_debts d left join tkt_private.restaurants r on r.id=d.restaurant_id left join public.tkt_profiles pr on pr.user_id=d.debtor_id where d.kind='restaurant_fee'
      union all select d.id::text,'عمولة الشركة على الطلبات',d.amount,d.created_at,pr.name,pr.phone,case when exists(select 1 from public.tkt_rides r where r.id=d.source_id) then 'رحلة تكسي' when exists(select 1 from tkt_private.food_orders f where f.id=d.source_id) then 'طلب طعام' else 'طلب قديم غير مرتبط' end from tkt_private.commerce_debts d left join public.tkt_profiles pr on pr.user_id=d.debtor_id where d.kind='captain_company'
      union all select e.id::text,'مصروف شركة',-e.amount,e.created_at,null,null,e.description from tkt_private.company_expenses e where e.voided_at is null
    ) entries where v_search='' or concat_ws(' ',id,kind,person_name,person_phone,details) ilike '%'||v_search||'%' order by created_at desc,id limit v_limit offset v_offset)x;
  else
    raise exception 'INVALID_CATEGORY';
  end if;
  return jsonb_build_object('rows',v_rows,'total',v_total,'has_more',v_offset+jsonb_array_length(v_rows)<v_total,'server_now',clock_timestamp());
end;
$$;

revoke all on function tkt_private.inventory_finance(text,jsonb) from public,anon,authenticated;
grant execute on function tkt_private.inventory_finance(text,jsonb) to authenticated;
create or replace function public.tkt_finance_inventory(p_action text, p_data jsonb default '{}'::jsonb)
returns jsonb language sql security invoker set search_path='' as $$
  select tkt_private.inventory_finance(p_action,p_data)
$$;
revoke all on function public.tkt_finance_inventory(text,jsonb) from public,anon;
grant execute on function public.tkt_finance_inventory(text,jsonb) to authenticated;
