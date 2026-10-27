alter table public.x_landing_pages alter column product_id drop not null;
create or replace function public.x_admin_delete_product(p_id text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not x_private.admin() then raise exception 'Admin access required' using errcode='42501'; end if;
 perform 1 from public.x_products where id=p_id for update;
 if not found then raise exception 'Product not found'; end if;
 update public.x_landing_pages set active=false,product_id=null where product_id=p_id;
 delete from public.x_products where id=p_id;
end;
$$;
revoke all on function public.x_admin_delete_product(text) from public,anon;
grant execute on function public.x_admin_delete_product(text) to authenticated;