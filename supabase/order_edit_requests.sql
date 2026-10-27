-- X-Space: merchant edits require an admin decision.
begin;
create or replace function x_private.same_order_items(a jsonb,b jsonb) returns boolean language sql immutable set search_path='' as $$
select coalesce((select jsonb_agg(jsonb_build_object('productId',value->>'productId','sale',value->'sale','quantity',value->'quantity','color',coalesce(value->>'color',''),'size',coalesce(value->>'size','')) order by ord) from jsonb_array_elements(a) with ordinality as t(value,ord)),'[]')=coalesce((select jsonb_agg(jsonb_build_object('productId',value->>'productId','sale',value->'sale','quantity',value->'quantity','color',coalesce(value->>'color',''),'size',coalesce(value->>'size','')) order by ord) from jsonb_array_elements(b) with ordinality as t(value,ord)),'[]');$$;
create or replace function public.x_edit_order(p_id text,p_customer jsonb,p_items jsonb,p_free boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=x_private.member();o public.x_orders;requested jsonb;begin
select * into o from public.x_orders where id=p_id and merchant_id=u for update;
if not found or o.status not in ('معلق','قيد المراجعة') or o.cancellation_requested then raise exception 'التعديل متاح أثناء المراجعة فقط';end if;
if o.payload->'pendingEdit'->>'status'='pending' then raise exception 'لديك تعديل بانتظار مراجعة الدعم';end if;
if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items)=0 then raise exception 'أضف منتجًا واحدًا على الأقل';end if;
requested:=jsonb_build_object('customer',x_private.customer(p_customer),'items',p_items,'freeDelivery',p_free);
update public.x_orders set payload=payload||jsonb_build_object('pendingEdit',jsonb_build_object('id',gen_random_uuid(),'status','pending','date',now(),'by',u,'byName',(select data->>'name' from public.x_profiles where user_id=u),'before',o.payload-'history'-'pendingEdit','after',requested)),updated_at=now() where id=p_id returning payload into requested;
insert into public.x_audit(actor_id,action,entity_id) values(u,'request_order_edit',p_id);
return requested;end$$;
create or replace function public.x_admin_order_edit_decision(p_id text,p_request text,p_approve boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();o public.x_orders;r jsonb;a jsonb;result jsonb;entry jsonb;begin
if u is null or not x_private.admin() then raise exception 'للإدارة فقط';end if;
select * into o from public.x_orders where id=p_id for update;r:=o.payload->'pendingEdit';
if not found or r->>'status' is distinct from 'pending' or r->>'id' is distinct from p_request then raise exception 'الطلب تمت مراجعته أو تغيّر';end if;
result:=o.payload;a:=r->'after';
if p_approve then
if o.status not in ('معلق','قيد المراجعة') or o.cancellation_requested then raise exception 'حالة الطلب لا تسمح بالموافقة؛ يمكنك رفض التعديل';end if;
if (o.payload-'history'-'pendingEdit') is distinct from r->'before' then raise exception 'تفاصيل الطلب تغيرت؛ ارفض الطلب واطلب تعديلًا جديدًا';end if;
if x_private.same_order_items(o.payload->'items',a->'items') and coalesce((o.payload->>'freeDelivery')::boolean,false)=coalesce((a->>'freeDelivery')::boolean,false) then
result:=result||jsonb_build_object('customer',x_private.customer(a->'customer'),'items',(select jsonb_agg(old.value||jsonb_build_object('note',left(coalesce(new.value->>'note',''),500)) order by old.ord) from jsonb_array_elements(o.payload->'items') with ordinality old(value,ord) join jsonb_array_elements(a->'items') with ordinality new(value,ord) using(ord)));
else
perform x_private.release_items(o.payload->'items');
result:=result||x_private.reserve(a->'items',(a->>'freeDelivery')::boolean)||jsonb_build_object('customer',x_private.customer(a->'customer'));
end if;
end if;
entry:=jsonb_build_object('date',now(),'by',u,'byName','الدعم','decision',case when p_approve then 'مقبول' else 'مرفوض' end,'changes',jsonb_build_array(jsonb_build_object('field','order','before',r->'before','after',case when p_approve then result-'history'-'pendingEdit' else (r->'before')||a end)));
result:=result||jsonb_build_object('pendingEdit',r||jsonb_build_object('status',case when p_approve then 'approved' else 'rejected' end,'decidedAt',now()),'history',jsonb_build_array(entry)||coalesce(o.payload->'history','[]'));
update public.x_orders set payload=result,updated_at=now() where id=p_id;
perform x_private.notify(o.merchant_id,'orders',case when p_approve then 'وافق الدعم على تعديل الطلب' else 'رفض الدعم تعديل الطلب' end,p_id);
insert into public.x_audit(actor_id,action,entity_id) values(u,case when p_approve then 'approve_order_edit' else 'reject_order_edit' end,p_id);return result;end$$;
revoke all on function x_private.same_order_items(jsonb,jsonb) from public,anon,authenticated;
revoke all on function public.x_edit_order(text,jsonb,jsonb,boolean) from public,anon;
grant execute on function public.x_edit_order(text,jsonb,jsonb,boolean) to authenticated;
revoke all on function public.x_admin_order_edit_decision(text,text,boolean) from public,anon;
grant execute on function public.x_admin_order_edit_decision(text,text,boolean) to authenticated;
commit;
