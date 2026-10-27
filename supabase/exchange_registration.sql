alter table tkt_private.exchange_agents add column user_id uuid unique references public.tkt_profiles(user_id),add column personal_name text,add column personal_phone text,add column province text,add column area text,add column street text,add column lat double precision check(lat between 29 and 38),add column lng double precision check(lng between 38 and 49),add column accuracy_m double precision,add column location_at timestamptz;
create index exchange_agents_province on tkt_private.exchange_agents(province);
CREATE OR REPLACE FUNCTION exchange_gateway.exchange_portal(p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a tkt_private.exchange_agents; c public.tkt_profiles; tx tkt_private.exchange_transactions; aid uuid; tid uuid; tok text; ph text; w integer; cost bigint; exp timestamptz; n integer; admin_mode boolean:=p_action like 'admin_%'; result jsonb;
begin

if p_action in ('account','register') then
 if auth.uid() is null then raise exception 'AUTH_REQUIRED';end if;
 select * into c from public.tkt_profiles where user_id=auth.uid() and not blocked;
 if not found then raise exception 'ACCOUNT_BLOCKED';end if;
 select * into a from tkt_private.exchange_agents where user_id=auth.uid();
 if p_action='account' then return jsonb_build_object('needs_registration',a.id is null,'personal_name',c.name,'personal_phone',c.phone);end if;
 if a.id is not null then return jsonb_build_object('ok',true,'agent_id',a.id);end if;
 ph:=tkt_private.normalize_phone(p_data->>'shop_phone');
 if ph is null or tkt_private.normalize_phone(p_data->>'personal_phone') is distinct from tkt_private.normalize_phone(c.phone) then raise exception 'INVALID_PHONE';end if;
 if coalesce(length(trim(p_data->>'personal_name')),0) not between 5 and 100 or cardinality(regexp_split_to_array(trim(p_data->>'personal_name'),'\s+'))<3 or coalesce(length(trim(p_data->>'shop_name')),0) not between 2 and 120 or coalesce(length(trim(p_data->>'area')),0) not between 2 and 120 or coalesce(length(trim(p_data->>'street')),0) not between 2 and 160 then raise exception 'INVALID_PROFILE';end if;
 if not coalesce(p_data->>'province'=any(array['بغداد','البصرة','نينوى','أربيل','السليمانية','دهوك','حلبجة','كركوك','ديالى','الأنبار','صلاح الدين','بابل','كربلاء','النجف','واسط','القادسية','ذي قار','ميسان','المثنى']),false) then raise exception 'INVALID_PROVINCE';end if;
 if p_data->>'lat' is null or p_data->>'lng' is null or (p_data->>'lat')::float8 not between 29 and 38 or (p_data->>'lng')::float8 not between 38 and 49 or coalesce((p_data->>'accuracy_m')::float8,0)<0 then raise exception 'LOCATION_REQUIRED';end if;
 insert into tkt_private.exchange_agents(name,phone,pin_hash,user_id,personal_name,personal_phone,province,area,street,lat,lng,accuracy_m,location_at)
 values(trim(p_data->>'shop_name'),ph,extensions.crypt(gen_random_uuid()::text,extensions.gen_salt('bf',12)),auth.uid(),trim(p_data->>'personal_name'),tkt_private.normalize_phone(c.phone),p_data->>'province',trim(p_data->>'area'),trim(p_data->>'street'),(p_data->>'lat')::float8,(p_data->>'lng')::float8,(p_data->>'accuracy_m')::float8,clock_timestamp()) returning id into aid;
 return jsonb_build_object('ok',true,'agent_id',aid);
end if;

if admin_mode then
 if auth.uid() is null or not tkt_private.is_admin() or not exists(select 1 from public.tkt_profiles where user_id=auth.uid() and not blocked) then raise exception 'ADMIN_REQUIRED';end if;
 aid:=nullif(p_data->>'agent_id','')::uuid;

 if p_action='admin_overview' then
 return jsonb_build_object('total',(select count(*) from tkt_private.exchange_agents),'active',(select count(*) from tkt_private.exchange_agents where active),'total_balance',(select coalesce(sum(balance),0) from tkt_private.exchange_agents),'provinces',coalesce((select jsonb_agg(to_jsonb(x)) from(select coalesce(province,'غير محددة') as province,count(*) as count from tkt_private.exchange_agents group by province order by count(*) desc,province)x),'[]'));
 end if;
 if p_action='admin_profile' then
 select * into a from tkt_private.exchange_agents where id=aid;
 if not found then raise exception 'AGENT_REQUIRED';end if;
 return jsonb_build_object('profile',to_jsonb(a)-'pin_hash'-'failures'-'locked_until','summary',(select jsonb_build_object('transactions',count(*),'credits',coalesce(sum(amount)filter(where kind='credit'),0),'spent',coalesce(sum(amount)filter(where kind='subscription'),0),'activations',count(*)filter(where kind='subscription'),'accounts',count(distinct captain_id)filter(where kind='subscription'),'weeks',coalesce(sum(weeks)filter(where kind='subscription'),0)) from tkt_private.exchange_transactions where agent_id=aid));
 end if;
 if p_action='admin_accounts' then
 return coalesce((select jsonb_agg(to_jsonb(x)) from(select p.user_id,p.name,p.phone,p.expires_at,p.blocked,count(*) as activation_count,sum(t.weeks) as total_weeks,sum(t.amount) as total_amount,max(t.created_at) as last_activation from tkt_private.exchange_transactions t join public.tkt_profiles p on p.user_id=t.captain_id where t.agent_id=aid and t.kind='subscription' group by p.user_id order by max(t.created_at) desc,p.user_id limit 100 offset greatest(0,coalesce((p_data->>'offset')::integer,0)))x),'[]');
 end if;

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
 if exists(select 1 from tkt_private.exchange_agents where id=aid and user_id is not null) then raise exception 'NATIVE_PASSWORD_RESET';end if;
 if coalesce(length(p_data->>'pin'),0) not between 8 and 72 then raise exception 'INVALID_DETAILS';end if;
 update tkt_private.exchange_agents set pin_hash=extensions.crypt(p_data->>'pin',extensions.gen_salt('bf',12)),failures=0,locked_until=null where id=aid;
 delete from tkt_private.exchange_sessions where agent_id=aid;
 elsif p_action not in ('admin_list','admin_transactions','admin_messages','admin_send') then raise exception 'UNKNOWN_ACTION';end if;
 if p_action in ('admin_create','admin_credit','admin_toggle','admin_reset') then
 insert into tkt_private.admin_audit(actor_id,action,entity_id,details)values(auth.uid(),p_action,aid::text,p_data-'pin');
 return jsonb_build_object('ok',true,'agent_id',aid);
 end if;
 if p_action='admin_list' then return coalesce((select jsonb_agg(to_jsonb(x))from(select id,name,phone,balance,active,created_at,personal_name,personal_phone,province,area,street,user_id from tkt_private.exchange_agents order by created_at desc)x),'[]');end if;
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
 select id into aid from tkt_private.exchange_agents where user_id=auth.uid();
 if aid is null then select agent_id into aid from tkt_private.exchange_sessions where token_hash=encode(extensions.digest(coalesce(p_data->>'token',''),'sha256'),'hex') and expires_at>now();end if;
 select * into a from tkt_private.exchange_agents where id=aid and active for update;
 if not found then raise exception 'SESSION_EXPIRED';end if;
 if a.user_id is not null and not exists(select 1 from public.tkt_profiles where user_id=a.user_id and not blocked) then raise exception 'ACCOUNT_BLOCKED';end if;
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
 return coalesce((select jsonb_agg(to_jsonb(x))from(select t.*,p.name as captain_name,p.phone as captain_phone from tkt_private.exchange_transactions t left join public.tkt_profiles p on p.user_id=t.captain_id where t.agent_id=aid and (nullif(p_data->>'captain_id','') is null or t.captain_id=(p_data->>'captain_id')::uuid) order by t.created_at desc,t.id desc limit 100 offset greatest(0,coalesce((p_data->>'offset')::integer,0)))x),'[]');
end if;
if p_action in ('send','admin_send') then
 if coalesce(length(trim(p_data->>'body')),0) not between 1 and 2000 then raise exception 'INVALID_MESSAGE';end if;
 tid:=(p_data->>'id')::uuid;if tid is null then raise exception 'INVALID_DETAILS';end if;
 insert into tkt_private.exchange_messages(id,agent_id,body,is_admin)values(tid,aid,trim(p_data->>'body'),admin_mode)on conflict(id)do nothing;
end if;
return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at)from(select id,body,is_admin,created_at from tkt_private.exchange_messages where agent_id=aid order by created_at desc limit 300)x),'[]');
end$function$
;
