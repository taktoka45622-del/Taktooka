create table if not exists tkt_private.company_expenses (
 id uuid primary key,
 spent_on date not null,
 amount bigint not null check(amount between 1 and 1000000000),
 category text not null check(category in('hosting','maps','ads','salaries','office','other')),
 description text not null check(length(description) between 2 and 240),
 created_by uuid not null references public.tkt_profiles(user_id),
 created_at timestamptz not null default clock_timestamp(),
 voided_at timestamptz,
 voided_by uuid references public.tkt_profiles(user_id),
 void_reason text
);
alter table tkt_private.company_expenses enable row level security;
revoke all on tkt_private.company_expenses from public,anon,authenticated;
create index if not exists tkt_company_expenses_date on tkt_private.company_expenses(spent_on) where voided_at is null;
create index if not exists tkt_company_expenses_creator on tkt_private.company_expenses(created_by);
create index if not exists tkt_company_expenses_voider on tkt_private.company_expenses(voided_by);
create index if not exists tkt_payment_created on public.tkt_payments(created_at);
create index if not exists tkt_ride_created on public.tkt_rides(created_at);

create or replace function tkt_private.company_performance(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 u uuid:=auth.uid();report_at timestamptz:=clock_timestamp();today date:=(report_at at time zone 'Asia/Baghdad')::date;
 first_day date:=coalesce(nullif(p_data->>'from','')::date,date_trunc('month',today)::date);
 last_day date:=coalesce(nullif(p_data->>'to','')::date,today);
 first_at timestamptz;last_at timestamptz;previous_at timestamptz;days integer;
 result jsonb;ident uuid;value bigint;kind text;expense_description text;spent date;previous_expense tkt_private.company_expenses%rowtype;
 offset_rows integer:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),1000000));
begin
 perform tkt_private.require_dashboard('finance',false);
 if p_action='expense_add' then
  perform tkt_private.require_dashboard('finance',true);
  ident:=(p_data->>'id')::uuid;value:=(p_data->>'amount')::bigint;kind:=p_data->>'category';expense_description:=trim(p_data->>'description');spent:=(p_data->>'spent_on')::date;
  if ident is null or value is null or value not between 1 and 1000000000 or kind is null or kind not in('hosting','maps','ads','salaries','office','other') or expense_description is null or length(expense_description) not between 2 and 240 or spent is null or spent>today then raise exception 'INVALID_EXPENSE';end if;
  insert into tkt_private.company_expenses(id,spent_on,amount,category,description,created_by) values(ident,spent,value,kind,expense_description,u) on conflict(id) do nothing;
  select * into previous_expense from tkt_private.company_expenses where id=ident;
  if previous_expense.amount<>value or previous_expense.spent_on<>spent or previous_expense.category<>kind or previous_expense.description<>expense_description or previous_expense.created_by<>u then raise exception 'EXPENSE_ID_CONFLICT';end if;
  return jsonb_build_object('id',ident);
 elsif p_action='expense_void' then
  perform tkt_private.require_dashboard('finance',true);
  expense_description:=trim(p_data->>'reason');
  if expense_description is null or length(expense_description) not between 2 and 240 then raise exception 'VOID_REASON_REQUIRED';end if;
  update tkt_private.company_expenses set voided_at=report_at,voided_by=u,void_reason=expense_description where id=(p_data->>'id')::uuid and voided_at is null;
  return '{}';
 end if;
 if first_day>last_day or last_day-first_day>365 or last_day>today then raise exception 'INVALID_REPORT_PERIOD';end if;
 days:=last_day-first_day+1;
 first_at:=first_day::timestamp at time zone 'Asia/Baghdad';last_at:=(last_day+1)::timestamp at time zone 'Asia/Baghdad';previous_at:=(first_day-days)::timestamp at time zone 'Asia/Baghdad';
 if p_action='payments' then
  select jsonb_build_object('items',coalesce(jsonb_agg(j order by created_at desc,id desc) filter(where position<=50),'[]'),'has_more',count(*)>50) into result from (
   select row_number() over(order by p.created_at desc,p.id desc)-offset_rows position,p.created_at,p.id,jsonb_build_object('id',p.id,'captain_id',p.captain_id,'name',c.name,'phone',c.phone,'amount',p.amount,'created_at',p.created_at,'expires_at',p.expires_at,'received_by',a.name) j
   from public.tkt_payments p join public.tkt_profiles c on c.user_id=p.captain_id left join public.tkt_profiles a on a.user_id=p.admin_id
   where p.created_at>=first_at and p.created_at<last_at order by p.created_at desc,p.id desc offset offset_rows limit 51
  ) x;
  return result;
 elsif p_action='expenses' then
  select jsonb_build_object('items',coalesce(jsonb_agg(j order by spent_on desc,created_at desc,id desc) filter(where position<=50),'[]'),'has_more',count(*)>50) into result from (
   select row_number() over(order by e.spent_on desc,e.created_at desc,e.id desc)-offset_rows position,e.spent_on,e.created_at,e.id,to_jsonb(e)||jsonb_build_object('created_by_name',p.name,'voided_by_name',v.name) j
   from tkt_private.company_expenses e left join public.tkt_profiles p on p.user_id=e.created_by left join public.tkt_profiles v on v.user_id=e.voided_by
   where e.spent_on between first_day and last_day order by e.spent_on desc,e.created_at desc,e.id desc offset offset_rows limit 51
  ) x;
  return result;
 elsif p_action<>'report' then raise exception 'UNKNOWN_ACTION';end if;

 select jsonb_build_object('revenue',coalesce(sum(amount),0),'payments',count(*),'paying_captains',count(distinct captain_id)) into result from public.tkt_payments where created_at>=first_at and created_at<last_at;
 result:=result||jsonb_build_object(
  'from',first_day,'to',last_day,'previous_from',first_day-days,'previous_to',first_day-1,'server_now',report_at,'fee',5000,
  'expenses',coalesce((select sum(amount) from tkt_private.company_expenses where spent_on between first_day and last_day and voided_at is null),0),
  'previous_revenue',coalesce((select sum(amount) from public.tkt_payments where created_at>=previous_at and created_at<first_at),0),
  'lifetime_revenue',coalesce((select sum(amount) from public.tkt_payments),0),
  'first_paid_captains',(select count(*) from (select captain_id,min(created_at) first_paid from public.tkt_payments group by captain_id) p where first_paid>=first_at and first_paid<last_at),
  'profiles',(select jsonb_build_object('customers',count(*) filter(where not captain),'captains',count(*) filter(where captain),'active',count(*) filter(where captain and expires_at>report_at),'expired',count(*) filter(where captain and expires_at<=report_at),'never',count(*) filter(where captain and expires_at is null),'blocked',count(*) filter(where captain and blocked),'online_fresh',count(*) filter(where captain and not blocked and online and expires_at>report_at and location_at>report_at-interval '15 seconds'),'expiring_soon',count(*) filter(where captain and expires_at>report_at and expires_at<=report_at+interval '3 days'),'new_customers',count(*) filter(where not captain and created_at>=first_at and created_at<last_at)) from public.tkt_profiles),
  'rides',(select jsonb_build_object('requested',count(*),'completed',count(*) filter(where status='completed'),'cancelled',count(*) filter(where status='cancelled'),'customers_served',count(distinct rider_id) filter(where status='completed'),'captains_worked',count(distinct captain_id) filter(where status='completed'),'completed_fares',coalesce(sum(fare) filter(where status='completed'),0),'average_distance_m',coalesce(round(avg(route_distance_m) filter(where status='completed')),0)) from public.tkt_rides where created_at>=first_at and created_at<last_at),
  'current_operations',(select jsonb_build_object('running',count(*) filter(where status in('pending','accepted','arrived','in_progress')),'pending',count(*) filter(where status='pending'),'long_wait',count(*) filter(where status='pending' and created_at<report_at-interval '10 minutes')) from public.tkt_rides),
  'lines',(select jsonb_build_object('active',count(*) filter(where status='accepted'),'pending',count(*) filter(where status='pending'),'registered',count(*) filter(where created_at>=first_at and created_at<last_at)) from tkt_private.lines),
  'wallets',(select jsonb_build_object('customer_funds',coalesce(sum(greatest(w.balance,0)) filter(where not p.captain),0),'captain_funds',coalesce(sum(greatest(w.balance,0)) filter(where p.captain),0)) from tkt_private.wallets w join public.tkt_profiles p on p.user_id=w.user_id),
  'daily',(with income as (select (created_at at time zone 'Asia/Baghdad')::date as bucket_date,sum(amount) amount from public.tkt_payments where created_at>=first_at and created_at<last_at group by 1),cost as(select spent_on as bucket_date,sum(amount) amount from tkt_private.company_expenses where spent_on between first_day and last_day and voided_at is null group by 1) select jsonb_agg(jsonb_build_object('day',d.bucket_date::date,'revenue',coalesce(i.amount,0),'expenses',coalesce(c.amount,0)) order by d.bucket_date) from generate_series(first_day::timestamp,last_day::timestamp,interval '1 day') d(bucket_date) left join income i on i.bucket_date=d.bucket_date::date left join cost c on c.bucket_date=d.bucket_date::date),
  'expiring',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select user_id,name,phone,expires_at from public.tkt_profiles where captain and not blocked and expires_at>report_at and expires_at<=report_at+interval '3 days' order by expires_at,user_id limit 20) x)
 );
 return result;
end $$;
revoke all on function tkt_private.company_performance(text,jsonb) from public,anon;
grant execute on function tkt_private.company_performance(text,jsonb) to authenticated;
create or replace function public.tkt_company(p_action text,p_data jsonb default '{}') returns jsonb language sql set search_path='' as $$select tkt_private.company_performance(p_action,p_data)$$;
revoke all on function public.tkt_company(text,jsonb) from public,anon;
grant execute on function public.tkt_company(text,jsonb) to authenticated;
