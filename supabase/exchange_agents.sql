create table tkt_private.exchange_agents(id uuid primary key default gen_random_uuid(),name text not null,phone text not null unique,pin_hash text not null,balance bigint not null default 0 check(balance>=0),active boolean not null default true,failures integer not null default 0,locked_until timestamptz,created_at timestamptz not null default now());
create table tkt_private.exchange_sessions(token_hash text primary key,agent_id uuid not null references tkt_private.exchange_agents(id),expires_at timestamptz not null);
create table tkt_private.exchange_transactions(id uuid primary key,agent_id uuid not null references tkt_private.exchange_agents(id),kind text not null check(kind in ('credit','subscription')),amount bigint not null check(amount>0),balance_after bigint not null,captain_id uuid references public.tkt_profiles(user_id),weeks integer,expires_at timestamptz,actor_id uuid,created_at timestamptz not null default now());
create index exchange_transactions_agent_time on tkt_private.exchange_transactions(agent_id,created_at desc);
create table tkt_private.exchange_messages(id uuid primary key,agent_id uuid not null references tkt_private.exchange_agents(id),body text not null check(length(body) between 1 and 2000),is_admin boolean not null,created_at timestamptz not null default now());
create index exchange_messages_agent_time on tkt_private.exchange_messages(agent_id,created_at desc);
alter table tkt_private.exchange_agents enable row level security;
alter table tkt_private.exchange_sessions enable row level security;
alter table tkt_private.exchange_transactions enable row level security;
alter table tkt_private.exchange_messages enable row level security;
revoke all on tkt_private.exchange_agents,tkt_private.exchange_sessions,tkt_private.exchange_transactions,tkt_private.exchange_messages from public,anon,authenticated;
create function tkt_private.exchange_portal(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare a tkt_private.exchange_agents; c public.tkt_profiles; tx tkt_private.exchange_transactions; aid uuid; tid uuid; tok text; ph text; w integer; cost bigint; exp timestamptz; n integer; admin_mode boolean:=p_action like 'admin_%'; result jsonb;
begin
if admin_mode then
 if auth.uid() is null or not tkt_private.is_admin() or not exists(select 1 from public.tkt_profiles where user_id=auth.uid() and not blocked) then raise exception 'ADMIN_REQUIRED';end if;
 aid:=nullif(p_data->>'agent_id','')::uuid;
 if p_action='admin_create' then
 ph:=tkt_private.normalize_phone(p_data->>'phone');
 if ph is null or coalesce(length(trim(p_data->>'name')),0) not between 2 and 100 or coalesce(length(p_data->>'pin'),0) not between 8 and 72 then raise exception 'INVALID_DETAILS';end if;
 insert into tkt_private.exchange_agents(name,phone,pin_hash) values(trim(p_data->>'name'),ph,extensions.crypt(p_data->>'pin',extensions.gen_salt('bf',12))) returning id into aid;
 elsif p_action='admin_credit' then
 tid:=(p_data->>'id')::uuid;cost:=(p_data->>'amount')::bigint;
 if tid is null or cost is null or cost not between 1 and 100000000 then raise exception 'INVALID_AMOUNT';end if;
 select * into a from tkt_private.exchange_agents where id=aid for update;if not found then raise exception 'AGENT_REQUIRED';end if;
 select * into tx from tkt_private.exchange_transactions where id=tid;
 if found then if tx.agent_id<>aid or tx.kind<>'credit' or tx.amount<>cost then raise exception 'REQUEST_CONFLICT';end if;return to_jsonb(tx);end if;
 update tkt_private.exchange_agents set balance=balance+cost where id=aid returning * into a;
 insert into tkt_private.exchange_transactions(id,agent_id,kind,amount,balance_after,actor_id)values(tid,aid,'credit',cost,a.balance,auth.uid());
 elsif p_action='admin_toggle' then
 update tkt_private.exchange_agents set active=(p_data->>'active')::boolean where id=aid;
 delete from tkt_private.exchange_sessions where agent_id=aid;
 elsif p_action='admin_reset' then
 if coalesce(length(p_data->>'pin'),0) not between 8 and 72 then raise exception 'INVALID_DETAILS';end if;
 update tkt_private.exchange_agents set pin_hash=extensions.crypt(p_data->>'pin',extensions.gen_salt('bf',12)),failures=0,locked_until=null where id=aid;
 delete from tkt_private.exchange_sessions where agent_id=aid;
 elsif p_action not in ('admin_list','admin_transactions','admin_messages','admin_send') then raise exception 'UNKNOWN_ACTION';end if;
 if p_action in ('admin_create','admin_credit','admin_toggle','admin_reset') then
 insert into tkt_private.admin_audit(actor_id,action,entity_id,details)values(auth.uid(),p_action,aid::text,p_data-'pin');
 return jsonb_build_object('ok',true,'agent_id',aid);
 end if;
 if p_action='admin_list' then return coalesce((select jsonb_agg(to_jsonb(x))from(select id,name,phone,balance,active,created_at from tkt_private.exchange_agents order by created_at desc)x),'[]');end if;
else
 if p_action='login' then
 ph:=tkt_private.normalize_phone(p_data->>'phone');
 select * into a from tkt_private.exchange_agents where phone=ph for update;
 if not found or not a.active then return '{"error":"LOGIN_FAILED"}';end if;
 if a.locked_until>now() then return '{"error":"LOGIN_LOCKED"}';end if;
 if a.locked_until is not null then a.failures:=0;end if;
 if coalesce(length(p_data->>'pin'),0) not between 8 and 72 or extensions.crypt(p_data->>'pin',a.pin_hash) is distinct from a.pin_hash then
 update tkt_private.exchange_agents set failures=a.failures+1,locked_until=case when a.failures+1>=5 then now()+interval '15 minutes' else null end where id=a.id;
 return '{"error":"LOGIN_FAILED"}';end if;
 update tkt_private.exchange_agents set failures=0,locked_until=null where id=a.id;
 tok:=encode(extensions.gen_random_bytes(32),'hex');
 delete from tkt_private.exchange_sessions where expires_at<now();
 insert into tkt_private.exchange_sessions values(encode(extensions.digest(tok,'sha256'),'hex'),a.id,now()+interval '12 hours');
 return jsonb_build_object('token',tok);
 end if;
 select agent_id into aid from tkt_private.exchange_sessions where token_hash=encode(extensions.digest(coalesce(p_data->>'token',''),'sha256'),'hex') and expires_at>now();
 select * into a from tkt_private.exchange_agents where id=aid and active for update;
 if not found then raise exception 'SESSION_EXPIRED';end if;
 if p_action='logout' then delete from tkt_private.exchange_sessions where token_hash=encode(extensions.digest(p_data->>'token','sha256'),'hex');return '{"ok":true}';end if;
 if p_action='me' then return jsonb_build_object('id',a.id,'name',a.name,'phone',a.phone,'balance',a.balance,'weekly_price',5000);end if;
 if p_action in ('lookup','activate') then
 ph:=tkt_private.normalize_phone(p_data->>'phone');if ph is null then raise exception 'INVALID_PHONE';end if;
 select count(*) into n from public.tkt_profiles where tkt_private.normalize_phone(phone)=ph and captain and not blocked;
 if n<>1 then raise exception 'CAPTAIN_NOT_FOUND';end if;
 select * into c from public.tkt_profiles where tkt_private.normalize_phone(phone)=ph and captain and not blocked for update;
 if p_action='lookup' then return jsonb_build_object('id',c.user_id,'name',c.name,'phone',c.phone,'expires_at',c.expires_at);end if;
 w:=(p_data->>'weeks')::integer;tid:=(p_data->>'id')::uuid;
 if w is null or w not between 1 and 52 or tid is null then raise exception 'INVALID_WEEKS';end if;
 if (p_data->>'captain_id')::uuid is distinct from c.user_id then raise exception 'REQUEST_CONFLICT';end if;
 select * into tx from tkt_private.exchange_transactions where id=tid;
 if found then if tx.agent_id<>aid or tx.captain_id<>c.user_id or tx.weeks<>w or tx.kind<>'subscription' then raise exception 'REQUEST_CONFLICT';end if;return to_jsonb(tx);end if;
 cost:=5000*w;
 if a.balance<cost then raise exception 'INSUFFICIENT_BALANCE';end if;
 exp:=greatest(coalesce(c.expires_at,now()),now())+make_interval(days=>7*w);
 update tkt_private.exchange_agents set balance=balance-cost where id=aid returning balance into a.balance;
 update public.tkt_profiles set expires_at=exp where user_id=c.user_id;
 insert into tkt_private.exchange_transactions(id,agent_id,kind,amount,balance_after,captain_id,weeks,expires_at)values(tid,aid,'subscription',cost,a.balance,c.user_id,w,exp) returning * into tx;
 perform tkt_private.notification_add(c.user_id,'exchange:'||tid,'subscription','تم تفعيل اشتراكك','تمت إضافة '||w||' أسبوع إلى اشتراكك في تكتوكة.',jsonb_build_object('expires_at',exp));
 return to_jsonb(tx);
 end if;
 if p_action not in ('transactions','messages','send') then raise exception 'UNKNOWN_ACTION';end if;
end if;
if p_action in ('transactions','admin_transactions') then
 return coalesce((select jsonb_agg(to_jsonb(x))from(select t.*,p.name as captain_name,p.phone as captain_phone from tkt_private.exchange_transactions t left join public.tkt_profiles p on p.user_id=t.captain_id where t.agent_id=aid order by t.created_at desc limit 500)x),'[]');
end if;
if p_action in ('send','admin_send') then
 if coalesce(length(trim(p_data->>'body')),0) not between 1 and 2000 then raise exception 'INVALID_MESSAGE';end if;
 tid:=(p_data->>'id')::uuid;if tid is null then raise exception 'INVALID_DETAILS';end if;
 insert into tkt_private.exchange_messages(id,agent_id,body,is_admin)values(tid,aid,trim(p_data->>'body'),admin_mode)on conflict(id)do nothing;
end if;
return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at)from(select id,body,is_admin,created_at from tkt_private.exchange_messages where agent_id=aid order by created_at desc limit 300)x),'[]');
end$$;
revoke all on function tkt_private.exchange_portal(text,jsonb) from public;
grant execute on function tkt_private.exchange_portal(text,jsonb) to anon,authenticated;
create function public.tkt_exchange(p_action text,p_data jsonb default '{}'::jsonb)returns jsonb language sql security invoker set search_path='' as $$select tkt_private.exchange_portal(p_action,p_data)$$;
revoke all on function public.tkt_exchange(text,jsonb) from public;
grant execute on function public.tkt_exchange(text,jsonb) to anon,authenticated;

create schema exchange_gateway; grant usage on schema exchange_gateway to anon,authenticated; alter function tkt_private.exchange_portal(text,jsonb) set schema exchange_gateway; create or replace function public.tkt_exchange(p_action text,p_data jsonb default '{}'::jsonb) returns jsonb language sql security invoker set search_path='' as $$select exchange_gateway.exchange_portal(p_action,p_data)$$;
alter table public.tkt_payments alter column admin_id drop not null; alter table public.tkt_payments add column exchange_transaction_id uuid references tkt_private.exchange_transactions(id); create index tkt_payments_exchange_transaction on public.tkt_payments(exchange_transaction_id) where exchange_transaction_id is not null; create function exchange_gateway.record_subscription_payment() returns trigger language plpgsql security definer set search_path='' as $$begin if new.kind='subscription' then insert into public.tkt_payments(id,captain_id,admin_id,amount,created_at,expires_at,exchange_transaction_id) select gen_random_uuid(),new.captain_id,null,5000,new.created_at,new.expires_at-make_interval(days=>7*(new.weeks-s.i)),new.id from generate_series(1,new.weeks) s(i);end if;return new;end$$; revoke all on function exchange_gateway.record_subscription_payment() from public,anon,authenticated; create trigger exchange_subscription_record after insert on tkt_private.exchange_transactions for each row execute function exchange_gateway.record_subscription_payment();