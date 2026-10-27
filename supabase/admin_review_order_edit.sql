create or replace function public.x_admin_edit_order(p_id text,p_customer jsonb,p_items jsonb,p_free boolean) returns jsonb language plpgsql security definer set search_path='' as $$ declare u uuid:=auth.uid(); o public.x_orders; result jsonb; begin
if u is null or not x_private.admin() then raise exception 'للإدارة فقط'; end if;
select * into o from public.x_orders where id=p_id for update;
if not found or o.status not in ('قيد المراجعة','معلق') or o.cancellation_requested then raise exception 'التعديل متاح أثناء المراجعة فقط'; end if;
perform x_private.release_items(o.payload->'items');
result:=o.payload||x_private.reserve(p_items,p_free)||jsonb_build_object('customer',x_private.customer(p_customer));
result:=result||jsonb_build_object('history',jsonb_build_array(jsonb_build_object('date',now(),'by',u,'changes',jsonb_build_array(jsonb_build_object('field','order','before',o.payload-'history','after',result-'history'))))||coalesce(o.payload->'history','[]'));
update public.x_orders set payload=result,updated_at=now() where id=p_id;
insert into public.x_audit(actor_id,action,entity_id) values(u,'admin_edit_order',p_id); return result; end $$;
revoke all on function public.x_admin_edit_order(text,jsonb,jsonb,boolean) from public,anon;
grant execute on function public.x_admin_edit_order(text,jsonb,jsonb,boolean) to authenticated;
