CREATE OR REPLACE FUNCTION exchange_gateway.exchange_portal(p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb;aid uuid;ident uuid;paid bigint;spent bigint;debt bigint;amount_value bigint;memo text;prev tkt_private.exchange_settlements;
begin
 if p_action in ('me','settlements') then
 result:=exchange_gateway.exchange_portal_before_settlements('me',p_data);
 aid:=(result->>'id')::uuid;
 if p_action='settlements' then
 return coalesce((select jsonb_agg(to_jsonb(x)) from(select id,amount,due_before,due_after,note,created_at from tkt_private.exchange_settlements where agent_id=aid order by created_at desc,id desc limit 100 offset greatest(0,coalesce((p_data->>'offset')::integer,0)))x),'[]'::jsonb);
 end if;
 select coalesce(sum(amount),0) into spent from tkt_private.exchange_transactions where agent_id=aid and kind='subscription';
 select coalesce(sum(amount),0) into paid from tkt_private.exchange_settlements where agent_id=aid;
 return result||jsonb_build_object('spent',spent,'settled',paid,'due',spent-paid,'last_payment_at',(select max(created_at) from tkt_private.exchange_settlements where agent_id=aid),'last_cleared_at',(select max(created_at) from tkt_private.exchange_settlements where agent_id=aid and due_after=0));
 end if;
 if p_action in ('admin_settle','admin_settlements') then
 if auth.uid() is null or not tkt_private.is_admin() or not exists(select 1 from public.tkt_profiles where user_id=auth.uid() and not blocked) then raise exception 'ADMIN_REQUIRED';end if;
 aid:=nullif(p_data->>'agent_id','')::uuid;
 perform 1 from tkt_private.exchange_agents where id=aid for update;
 if not found then raise exception 'AGENT_REQUIRED';end if;
 if p_action='admin_settlements' then return coalesce((select jsonb_agg(to_jsonb(x)) from(select s.*,p.name as received_by from tkt_private.exchange_settlements s left join public.tkt_profiles p on p.user_id=s.actor_id where s.agent_id=aid order by s.created_at desc,s.id desc limit 100 offset greatest(0,coalesce((p_data->>'offset')::integer,0)))x),'[]');end if;
 ident:=nullif(p_data->>'id','')::uuid;amount_value:=(p_data->>'amount')::bigint;memo:=coalesce(trim(p_data->>'note'),'');
 if ident is null or amount_value is null or amount_value not between 1 and 1000000000 or length(memo)>500 then raise exception 'INVALID_SETTLEMENT';end if;
 select * into prev from tkt_private.exchange_settlements where id=ident;
 if found then if prev.agent_id<>aid or prev.amount<>amount_value or prev.note<>memo or prev.actor_id<>auth.uid() then raise exception 'REQUEST_CONFLICT';end if;return to_jsonb(prev);end if;
 select coalesce(sum(amount),0) into spent from tkt_private.exchange_transactions where agent_id=aid and kind='subscription';
 select coalesce(sum(amount),0) into paid from tkt_private.exchange_settlements where agent_id=aid;
 debt:=spent-paid;
 if amount_value>debt then raise exception 'SETTLEMENT_EXCEEDS_DUE';end if;
 insert into tkt_private.exchange_settlements(id,agent_id,amount,due_before,due_after,note,actor_id)values(ident,aid,amount_value,debt,debt-amount_value,memo,auth.uid())returning * into prev;
 insert into tkt_private.admin_audit(actor_id,action,entity_id,details)values(auth.uid(),'exchange_settlement',aid::text,jsonb_build_object('settlement_id',ident,'amount',amount_value,'due_before',debt,'due_after',debt-amount_value));
 return to_jsonb(prev);
 end if;
 result:=exchange_gateway.exchange_portal_before_settlements(p_action,p_data);
 if p_action='admin_profile' then
 aid:=(result->'profile'->>'id')::uuid;
 select coalesce(sum(amount),0) into paid from tkt_private.exchange_settlements where agent_id=aid;
 result:=jsonb_set(result,'{summary}',(result->'summary')||jsonb_build_object('settled',paid,'due',(result->'summary'->>'spent')::bigint-paid));
 elsif p_action='admin_list' then
 with credits as(select agent_id,coalesce(sum(amount)filter(where kind='credit'),0) credits,coalesce(sum(amount)filter(where kind='subscription'),0) spent from tkt_private.exchange_transactions group by agent_id),
 settlements as(select agent_id,sum(amount) settled from tkt_private.exchange_settlements group by agent_id)
 select coalesce(jsonb_agg(x.value||jsonb_build_object('credits',coalesce(c.credits,0),'spent',coalesce(c.spent,0),'settled',coalesce(s.settled,0),'due',coalesce(c.spent,0)-coalesce(s.settled,0)) order by x.ordinality),'[]'::jsonb)into result from jsonb_array_elements(result)with ordinality x(value,ordinality)left join credits c on c.agent_id=(x.value->>'id')::uuid left join settlements s on s.agent_id=(x.value->>'id')::uuid;
 elsif p_action='admin_overview' then
 result:=result||jsonb_build_object('total_due',(select coalesce(sum(amount),0) from tkt_private.exchange_transactions where kind='subscription')-(select coalesce(sum(amount),0) from tkt_private.exchange_settlements));
 end if;
 return result;
end $function$
;