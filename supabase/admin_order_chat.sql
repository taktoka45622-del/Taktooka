create or replace function public.x_admin_open_order_ticket(p_order text) returns text language plpgsql security definer set search_path='' as $$ declare o public.x_orders; tid text; begin
if auth.uid() is null or not x_private.admin() then raise exception 'للإدارة فقط'; end if;
select * into o from public.x_orders where id=p_order; if not found then raise exception 'الطلب غير موجود'; end if;
insert into public.x_tickets(id,merchant_id,order_id,type) values(gen_random_uuid()::text,o.merchant_id,o.id,'دردشة بخصوص طلب '||lpad(o.payload->>'orderNumber',6,'0')) on conflict(order_id) where order_id is not null do nothing;
update public.x_tickets set status='open',type='دردشة بخصوص طلب '||lpad(o.payload->>'orderNumber',6,'0') where order_id=o.id returning id into tid; return tid; end $$;
revoke all on function public.x_admin_open_order_ticket(text) from public,anon;
grant execute on function public.x_admin_open_order_ticket(text) to authenticated;
