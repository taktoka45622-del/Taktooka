create table if not exists tkt_private.support_workflow(
 kind text not null check(kind in ('support','recovery','exchange')), room_id uuid not null,
 assignee uuid, status text not null default 'new' check(status in ('new','progress','resolved')),
 note text not null default '' check(length(note)<=500), updated_at timestamptz not null default now(), updated_by uuid,
 primary key(kind,room_id));
alter table tkt_private.support_workflow enable row level security;
revoke all on tkt_private.support_workflow from public,anon,authenticated;
create table if not exists tkt_private.exchange_watch_rules(
 agent_id uuid primary key references tkt_private.exchange_agents(id), debt_limit bigint not null default 100000 check(debt_limit between 1 and 1000000000),
 overdue_days integer not null default 7 check(overdue_days between 1 and 365), hourly_limit bigint not null default 100000 check(hourly_limit between 1 and 1000000000),updated_by uuid,updated_at timestamptz not null default now());
alter table tkt_private.exchange_watch_rules enable row level security;
revoke all on tkt_private.exchange_watch_rules from public,anon,authenticated;
create table if not exists tkt_private.exchange_watch_alerts(
 agent_id uuid not null references tkt_private.exchange_agents(id),kind text not null, active boolean not null default true,amount bigint not null,first_at timestamptz not null default now(),updated_at timestamptz not null default now(),primary key(agent_id,kind));
alter table tkt_private.exchange_watch_alerts enable row level security;
revoke all on tkt_private.exchange_watch_alerts from public,anon,authenticated;
create index if not exists exchange_transactions_agent_time_ops on tkt_private.exchange_transactions(agent_id,created_at);
create index if not exists exchange_settlements_agent_time_ops on tkt_private.exchange_settlements(agent_id,created_at);
create index if not exists support_workflow_assignee_ops on tkt_private.support_workflow(assignee) where assignee is not null;

create or replace function tkt_private.refresh_exchange_watch() returns void language plpgsql security definer set search_path='' as $$
declare a record; k text; hit boolean; was_active boolean; amount_value bigint;
begin
 for a in
 with tx as(select agent_id,sum(amount)filter(where kind='subscription') spent,sum(amount)filter(where kind='subscription' and created_at>now()-interval '1 hour') hourly,min(created_at)filter(where kind='subscription') first_spent from tkt_private.exchange_transactions group by agent_id),
 paid as(select agent_id,sum(amount) settled,max(created_at) last_paid from tkt_private.exchange_settlements group by agent_id)
 select e.id,e.name,coalesce(t.spent,0)-coalesce(p.settled,0) due,coalesce(t.hourly,0) hourly,coalesce(p.last_paid,t.first_spent) debt_since,coalesce(r.debt_limit,100000) debt_limit,coalesce(r.overdue_days,7) overdue_days,coalesce(r.hourly_limit,100000) hourly_limit from tkt_private.exchange_agents e left join tx t on t.agent_id=e.id left join paid p on p.agent_id=e.id left join tkt_private.exchange_watch_rules r on r.agent_id=e.id
 loop
  foreach k in array array['debt','overdue','unusual'] loop
   hit:=case k when 'debt' then a.due>=a.debt_limit when 'overdue' then a.due>0 and a.debt_since<now()-make_interval(days=>a.overdue_days) else a.hourly>=a.hourly_limit end;
   amount_value:=case when k='unusual' then a.hourly else a.due end;
   select active into was_active from tkt_private.exchange_watch_alerts where agent_id=a.id and kind=k;
   if hit then
    insert into tkt_private.exchange_watch_alerts(agent_id,kind,active,amount)values(a.id,k,true,amount_value)on conflict(agent_id,kind)do update set active=true,amount=excluded.amount,updated_at=now(),first_at=case when not exchange_watch_alerts.active then now() else exchange_watch_alerts.first_at end;
    if not coalesce(was_active,false) then perform tkt_private.notify_admins('exchange-watch:'||a.id||':'||k||':'||to_char(now(),'YYYYMMDDHH24'),'exchange_finance','تنبيه رقابي للصيرفة',a.name||' · '||case k when 'debt' then 'تجاوز حد الذمة' when 'overdue' then 'تأخر التسديد' else 'ارتفاع مبالغ التفعيل خلال ساعة' end,jsonb_build_object('screen','exchange_finance','agent_id',a.id));end if;
   elsif coalesce(was_active,false) then update tkt_private.exchange_watch_alerts set active=false,updated_at=now() where agent_id=a.id and kind=k;end if;
  end loop;
 end loop;
end $$;
revoke all on function tkt_private.refresh_exchange_watch() from public,anon,authenticated;

create or replace function exchange_gateway.operations(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb:='{}';a uuid;u uuid:=auth.uid();d1 date;d2 date;t1 timestamptz;t2 timestamptz;offn integer:=greatest(0,least(100000,coalesce((p_data->>'offset')::int,0)));k text;st text;old_value jsonb;new_value jsonb;target uuid;n integer:=0;reminder_row record;
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 if p_action='manage' then if length(coalesce(p_data->>'reason',''))>500 then raise exception 'INVALID_REASON';end if;perform set_config('tkt.audit_reason',coalesce(p_data->>'reason',''),true);return public.tkt_manage(p_data->>'action',coalesce(p_data->'data','{}'));end if;
 if p_action in ('statement','demand','watch','watch_save')then perform tkt_private.require_dashboard(case when p_action='demand' then 'finance' else 'exchanges' end,p_action='watch_save');
 elsif p_action in ('renewals','remind')then perform tkt_private.require_dashboard('users',p_action='remind');
 elsif p_action in ('workflow','workflow_save')then perform tkt_private.require_dashboard('support',p_action='workflow_save');
 elsif p_action='audit' then perform tkt_private.require_dashboard('audit');
 elsif p_action<>'center' then raise exception 'UNKNOWN_ACTION';end if;
 if p_action in ('statement','demand','audit')then
 d1:=coalesce(nullif(p_data->>'from','')::date,(now() at time zone 'Asia/Baghdad')::date-29);d2:=coalesce(nullif(p_data->>'to','')::date,(now() at time zone 'Asia/Baghdad')::date);
 if d2<d1 or d2-d1>365 or d2>(now() at time zone 'Asia/Baghdad')::date then raise exception 'INVALID_PERIOD';end if;
 t1:=d1::timestamp at time zone 'Asia/Baghdad';t2:=(d2+1)::timestamp at time zone 'Asia/Baghdad';end if;
 if p_action='center' then
 if not exists(select 1 from public.tkt_profiles where user_id=u and not blocked)or not(tkt_private.is_admin()or exists(select 1 from tkt_private.staff_accounts where user_id=u and active))then raise exception 'PERMISSION_DENIED';end if;
 if tkt_private.dashboard_permission('rides')then result:=result||jsonb_build_object('rides',coalesce((select jsonb_agg(to_jsonb(x))from(select id,pickup_name,destination_name,created_at from public.tkt_rides where status='pending' order by created_at limit 30)x),'[]'),'ride_count',(select count(*)from public.tkt_rides where status='pending'));end if;
 if tkt_private.dashboard_permission('lines')then result:=result||jsonb_build_object('lines',coalesce((select jsonb_agg(to_jsonb(x))from(select r.line_id,l.passenger_name,r.departure_at from tkt_private.line_runs r join tkt_private.lines l on l.id=r.line_id where l.status='accepted' and r.state in('scheduled','heading','arrived')and r.departure_at<now()-interval '5 minutes' and r.service_date=(now() at time zone 'Asia/Baghdad')::date order by r.departure_at limit 30)x),'[]'),'line_count',(select count(*)from tkt_private.line_runs r join tkt_private.lines l on l.id=r.line_id where l.status='accepted' and r.state in('scheduled','heading','arrived')and r.departure_at<now()-interval '5 minutes' and r.service_date=(now() at time zone 'Asia/Baghdad')::date));end if;
 if tkt_private.dashboard_permission('applications')then result:=result||jsonb_build_object('applications',coalesce((select jsonb_agg(to_jsonb(x))from(select user_id,full_name,submitted_at from public.tkt_captain_applications where status='pending' order by submitted_at limit 30)x),'[]'),'application_count',(select count(*)from public.tkt_captain_applications where status='pending'));end if;
 if tkt_private.dashboard_permission('support')then result:=result||jsonb_build_object('support',coalesce((select jsonb_agg(to_jsonb(x))from(select w.kind,w.room_id,w.assignee,w.status,w.updated_at from tkt_private.support_workflow w where status<>'resolved' order by updated_at desc limit 30)x),'[]'));end if;return result;
 elsif p_action='renewals' then
 k:=coalesce(p_data->>'filter','soon');return jsonb_build_object('counts',(select jsonb_build_object('today',count(*)filter(where (expires_at at time zone 'Asia/Baghdad')::date=(now()at time zone 'Asia/Baghdad')::date and expires_at>now()),'soon',count(*)filter(where expires_at>now()and expires_at<=now()+interval '3 days'),'expired',count(*)filter(where expires_at<=now()),'never',count(*)filter(where expires_at is null))from public.tkt_profiles where captain and not blocked),'items',coalesce((select jsonb_agg(to_jsonb(x))from(select user_id,name,phone,expires_at from public.tkt_profiles where captain and not blocked and case k when 'today' then (expires_at at time zone 'Asia/Baghdad')::date=(now()at time zone 'Asia/Baghdad')::date and expires_at>now() when 'expired' then expires_at<=now() when 'never' then expires_at is null else expires_at>now()and expires_at<=now()+interval '3 days' end order by expires_at nulls last,user_id limit 50 offset offn)x),'[]'));
 elsif p_action='remind' then
 if jsonb_typeof(p_data->'ids')<>'array' or jsonb_array_length(p_data->'ids')not between 1 and 100 then raise exception 'INVALID_RECIPIENTS';end if;
 for reminder_row in select user_id,expires_at from public.tkt_profiles where captain and not blocked and user_id in(select value::uuid from jsonb_array_elements_text(p_data->'ids')) loop
 perform tkt_private.notification_add(reminder_row.user_id,'admin-renewal:'||reminder_row.user_id||':'||(now()at time zone 'Asia/Baghdad')::date,'subscription','تذكير اشتراك تكتوكة',case when reminder_row.expires_at>now() then 'اشتراكك ينتهي قريبًا؛ جدد حتى تستمر باستقبال الطلبات.' else 'جدّد اشتراك تكتوكة حتى تستقبل الطلبات والخطوط.' end,jsonb_build_object('screen','subscription'));n:=n+1;end loop;
 insert into tkt_private.admin_audit(actor_id,action,details)values(u,'renewal_reminders',jsonb_build_object('count',n,'reason',left(coalesce(p_data->>'reason','تذكير تجديد الاشتراك'),500)));return jsonb_build_object('count',n);
 elsif p_action='demand' then
 return jsonb_build_object('from',d1,'to',d2,'areas',coalesce((select jsonb_agg(to_jsonb(x))from(select coalesce(nullif(trim(pickup_name),''),'انطلاق غير مسمى') area,count(*) requested,count(*)filter(where status='completed')completed,count(*)filter(where status='cancelled')cancelled,count(*)filter(where status='cancelled'and captain_id is null)unassigned_cancelled from public.tkt_rides where created_at>=t1 and created_at<t2 group by 1 order by count(*)desc limit 100)x),'[]'),'hours',coalesce((select jsonb_agg(to_jsonb(x))from(select extract(hour from created_at at time zone 'Asia/Baghdad')::int hour_of_day,count(*)requested,count(*)filter(where status='cancelled')cancelled from public.tkt_rides where created_at>=t1 and created_at<t2 group by 1 order by 1)x),'[]'));
 elsif p_action='statement' then
 a:=(p_data->>'agent_id')::uuid;if not exists(select 1 from tkt_private.exchange_agents where id=a)then raise exception 'AGENT_REQUIRED';end if;
 return (with events as(select id,created_at,kind,amount,case when kind='credit'then amount else -amount end balance_delta,case when kind='subscription'then amount else 0 end due_delta from tkt_private.exchange_transactions where agent_id=a union all select id,created_at,'settlement',amount,0,-amount from tkt_private.exchange_settlements where agent_id=a),opening as(select coalesce(sum(balance_delta),0)balance,coalesce(sum(due_delta),0)due from events where created_at<t1),period as(select e.*,o.balance+sum(balance_delta)over(order by created_at,id)balance,o.due+sum(due_delta)over(order by created_at,id)due from events e cross join opening o where created_at>=t1 and created_at<t2)
 select jsonb_build_object('name',(select name from tkt_private.exchange_agents where id=a),'agent_id',a,'from',d1,'to',d2,'opening',(select to_jsonb(o)from opening o),'totals',(select jsonb_build_object('credits',coalesce(sum(amount)filter(where kind='credit'),0),'spent',coalesce(sum(amount)filter(where kind='subscription'),0),'settled',coalesce(sum(amount)filter(where kind='settlement'),0),'count',count(*))from period),'items',coalesce((select jsonb_agg(to_jsonb(x)order by x.created_at,x.id)from(select * from period order by created_at,id limit 100 offset offn)x),'[]')));
 elsif p_action='workflow' then return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(w))from tkt_private.support_workflow w),'[]'),'staff',coalesce((select jsonb_agg(to_jsonb(x))from(select s.user_id,s.name from tkt_private.staff_accounts s join public.tkt_profiles p using(user_id)where s.active and not p.blocked and s.permissions->'support'->>'view'='true' union select p.user_id,p.name from public.tkt_admins a join public.tkt_profiles p using(user_id)where not p.blocked)x),'[]'));
 elsif p_action='workflow_save' then
 k:=p_data->>'kind';a:=(p_data->>'room_id')::uuid;target:=nullif(p_data->>'assignee','')::uuid;st:=p_data->>'status';
 if k not in('support','recovery','exchange')or st not in('new','progress','resolved')or length(coalesce(p_data->>'note',''))>500 then raise exception 'INVALID_WORKFLOW';end if;
 if not(case k when 'support'then exists(select 1 from public.tkt_profiles where user_id=a)when 'recovery'then exists(select 1 from public.tkt_recovery_threads where id=a)else exists(select 1 from tkt_private.exchange_agents where id=a)end)then raise exception 'ROOM_REQUIRED';end if;
 if target is not null and not exists(select 1 from public.tkt_profiles p where p.user_id=target and not p.blocked and(exists(select 1 from public.tkt_admins where user_id=target)or exists(select 1 from tkt_private.staff_accounts where user_id=target and active and permissions->'support'->>'view'='true')))then raise exception 'INVALID_ASSIGNEE';end if;
 perform pg_advisory_xact_lock(hashtextextended(k||a::text,0));select to_jsonb(w)into old_value from tkt_private.support_workflow w where kind=k and room_id=a;
 insert into tkt_private.support_workflow(kind,room_id,assignee,status,note,updated_by)values(k,a,target,st,coalesce(p_data->>'note',''),u)on conflict(kind,room_id)do update set assignee=excluded.assignee,status=excluded.status,note=excluded.note,updated_by=u,updated_at=now()returning to_jsonb(support_workflow.*)into new_value;
 insert into tkt_private.admin_audit(actor_id,action,entity_id,details)values(u,'support_workflow',a::text,jsonb_build_object('before',old_value,'after',new_value,'reason',coalesce(p_data->>'note','')));
 if target is not null and target<>u and old_value->>'assignee' is distinct from target::text then perform tkt_private.notification_add(target,'support-assigned:'||k||a||':'||extract(epoch from clock_timestamp()),'support','تم إسناد محادثة إليك','افتح الدعم لمتابعة المحادثة.',jsonb_build_object('screen',case k when 'support'then 'support'when 'exchange'then 'exchange_support'else 'recovery'end,'user_id',a,'agent_id',a,'thread_id',a));end if;
 perform realtime.send(jsonb_build_object('resource','support_workflow'),'invalidate','tkt:dashboard',true);return new_value;
 elsif p_action='watch_save' then
 a:=(p_data->>'agent_id')::uuid;select to_jsonb(w)into old_value from tkt_private.exchange_watch_rules w where agent_id=a;
 insert into tkt_private.exchange_watch_rules(agent_id,debt_limit,overdue_days,hourly_limit,updated_by)values(a,(p_data->>'debt_limit')::bigint,(p_data->>'overdue_days')::int,(p_data->>'hourly_limit')::bigint,u)on conflict(agent_id)do update set debt_limit=excluded.debt_limit,overdue_days=excluded.overdue_days,hourly_limit=excluded.hourly_limit,updated_by=u,updated_at=now()returning to_jsonb(exchange_watch_rules.*)into new_value;
 insert into tkt_private.admin_audit(actor_id,action,entity_id,details)values(u,'exchange_watch_rule',a::text,jsonb_build_object('before',old_value,'after',new_value,'reason',left(coalesce(p_data->>'reason','تعديل حدود المتابعة'),500)));return new_value;
 elsif p_action='watch' then
 return jsonb_build_object('rules',coalesce((select jsonb_agg(to_jsonb(r))from tkt_private.exchange_watch_rules r),'[]'),'alerts',coalesce((select jsonb_agg(to_jsonb(x))from(select w.*,a.name from tkt_private.exchange_watch_alerts w join tkt_private.exchange_agents a on a.id=w.agent_id where w.active order by w.first_at desc)x),'[]'));
 elsif p_action='audit' then
 return coalesce((select jsonb_agg(to_jsonb(x))from(select a.*,coalesce(s.name,p.name,'النظام')actor_name from tkt_private.admin_audit a left join public.tkt_profiles p on p.user_id=a.actor_id left join tkt_private.staff_accounts s on s.user_id=a.actor_id where a.created_at>=t1 and a.created_at<t2 and(coalesce(p_data->>'search','')=''or a.action ilike '%'||(p_data->>'search')||'%'or a.entity_id ilike '%'||(p_data->>'search')||'%'or coalesce(s.name,p.name,'')ilike '%'||(p_data->>'search')||'%')order by a.created_at desc,a.id desc limit 50 offset offn)x),'[]');end if;
 raise exception 'UNKNOWN_ACTION';
end $$;
revoke all on function exchange_gateway.operations(text,jsonb) from public,anon;
grant execute on function exchange_gateway.operations(text,jsonb) to authenticated;
create or replace function public.tkt_operations(p_action text,p_data jsonb default '{}') returns jsonb language sql set search_path='' as $$select exchange_gateway.operations(p_action,p_data)$$;
revoke all on function public.tkt_operations(text,jsonb) from public,anon;
grant execute on function public.tkt_operations(text,jsonb) to authenticated;

create or replace function tkt_private.support_workflow_incoming() returns trigger language plpgsql security definer set search_path='' as $$
declare k text;a uuid;assigned uuid;
begin
 if new.is_admin then return new;end if;
 k:=case tg_table_name when 'tkt_messages'then 'support'when 'tkt_recovery_messages'then 'recovery'else 'exchange'end;
 a:=case k when 'support'then (to_jsonb(new)->>'user_id')::uuid when 'recovery'then (to_jsonb(new)->>'thread_id')::uuid else (to_jsonb(new)->>'agent_id')::uuid end;
 update tkt_private.support_workflow set status=case when status='resolved'then 'new'else status end,updated_at=new.created_at where kind=k and room_id=a returning assignee into assigned;
 if assigned is not null then perform tkt_private.notification_add(assigned,'assigned-message:'||new.id,'support','رسالة في محادثة مسندة إليك','وصل رد جديد، افتح الدعم.',jsonb_build_object('screen',case k when 'support'then 'support'when 'exchange'then 'exchange_support'else 'recovery'end,'user_id',a,'agent_id',a,'thread_id',a));end if;
 perform realtime.send(jsonb_build_object('resource','support_workflow'),'invalidate','tkt:dashboard',true);return new;
end $$;
revoke all on function tkt_private.support_workflow_incoming() from public,anon,authenticated;
create trigger tkt_workflow_incoming after insert on public.tkt_messages for each row execute function tkt_private.support_workflow_incoming();
create trigger tkt_workflow_incoming after insert on public.tkt_recovery_messages for each row execute function tkt_private.support_workflow_incoming();
create trigger tkt_workflow_incoming after insert on tkt_private.exchange_messages for each row execute function tkt_private.support_workflow_incoming();

create or replace function tkt_private.audit_admin_changes()returns trigger language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();b jsonb;a jsonb;fields text[];
begin
 if actor is null or not(tkt_private.is_admin()or exists(select 1 from tkt_private.staff_accounts where user_id=actor and active))then if tg_op='DELETE'then return old;else return new;end if;end if;
 fields:=case tg_table_name
 when 'tkt_profiles'then array['user_id','name','phone','captain','blocked','expires_at']
 when 'tkt_rides'then array['id','status','fare','captain_id','rider_id','pickup_name','destination_name']
 when 'tkt_payments'then array['id','captain_id','amount','expires_at','admin_id']
 when 'wallets'then array['user_id','balance']
 when 'coupons'then array['code','active','amount','kind','max_uses','expires_at']
 when 'tkt_saved_places'then array['id','user_id','label','lat','lng']
 when 'dispatch_settings'then array['id','zones','search_s','max_eta_s','stale_s']
 when 'pricing_settings'then array['id','tiers','revision','night_amount','night_start','night_end']
 when 'exchange_agents'then array['id','name','active','balance','province','area','street']
 when 'staff_accounts'then array['user_id','name','active','permissions']else array['id','user_id']end;
 if tg_op<>'INSERT'then select jsonb_object_agg(key,value)into b from jsonb_each(to_jsonb(old))where key=any(fields);end if;
 if tg_op<>'DELETE'then select jsonb_object_agg(key,value)into a from jsonb_each(to_jsonb(new))where key=any(fields);end if;
 if a is distinct from b then insert into tkt_private.admin_audit(actor_id,action,entity_id,details)values(actor,lower(tg_op)||':'||tg_table_name,coalesce(a->>'id',a->>'user_id',a->>'code',b->>'id',b->>'user_id',b->>'code'),jsonb_build_object('table',tg_table_name,'operation',tg_op,'before',b,'after',a,'reason',nullif(current_setting('tkt.audit_reason',true),'')));end if;
 if tg_op='DELETE'then return old;else return new;end if;
end $$;
revoke all on function tkt_private.audit_admin_changes() from public,anon,authenticated;
create trigger tkt_operations_audit after insert or update or delete on tkt_private.exchange_agents for each row execute function tkt_private.audit_admin_changes();
create trigger tkt_operations_audit after insert or update or delete on tkt_private.staff_accounts for each row execute function tkt_private.audit_admin_changes();
select cron.schedule('taktooka-exchange-watch','*/15 * * * *','select tkt_private.refresh_exchange_watch()');
notify pgrst,'reload schema';
