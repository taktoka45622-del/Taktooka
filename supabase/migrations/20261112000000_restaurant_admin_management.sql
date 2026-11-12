begin;
create or replace function tkt_private.admin_restaurants(p_action text,p_data jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
 u uuid:=auth.uid();
 rid uuid:=coalesce(nullif(p_data->>'restaurant_id',''),nullif(p_data->>'id',''))::uuid;
 iid uuid:=nullif(p_data->>'item_id','')::uuid;
 r tkt_private.restaurants;
 category_name text:=nullif(trim(p_data->>'category'),'');
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 if not tkt_private.is_admin() then raise exception 'ADMIN_REQUIRED';end if;
 if not exists(select 1 from public.tkt_profiles where user_id=u and not blocked and deleted_at is null) then raise exception 'ACCOUNT_BLOCKED';end if;
 if p_action='list' then
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (
   select r.id,r.name,r.phone,r.address,r.open,r.created_at,p.name as owner_name,p.phone as owner_phone,
    (select count(*) from tkt_private.restaurant_items i where i.restaurant_id=r.id) as item_count
   from tkt_private.restaurants r left join public.tkt_profiles p on p.user_id=r.owner_id
  ) x),'[]'::jsonb);
 elsif p_action='detail' then
  select * into r from tkt_private.restaurants where id=rid;
  if not found then raise exception 'RESTAURANT_NOT_FOUND';end if;
  return jsonb_build_object(
   'restaurant',to_jsonb(r)||jsonb_build_object('owner_name',(select p.name from public.tkt_profiles p where p.user_id=r.owner_id),'owner_phone',(select p.phone from public.tkt_profiles p where p.user_id=r.owner_id)),
   'categories',coalesce((select jsonb_agg(c.name order by c.name) from (
    select distinct trim(value) as name from (
     select case when jsonb_typeof(v)='object' then coalesce(v->>'name',v->>'title') else trim(both '"' from v::text) end as value
     from jsonb_array_elements(coalesce(r.menu_categories,'[]'::jsonb)) v
     union all select i.category from tkt_private.restaurant_items i where i.restaurant_id=r.id
    ) q where nullif(trim(value),'') is not null
   ) c),'[]'::jsonb),
   'items',coalesce((select jsonb_agg(to_jsonb(i) order by i.sort_order,i.name) from tkt_private.restaurant_items i where i.restaurant_id=r.id),'[]'::jsonb)
  );
 elsif p_action='delete_item' then
  if rid is null or iid is null then raise exception 'INVALID_ITEM';end if;
  delete from tkt_private.restaurant_items where id=iid and restaurant_id=rid;
  if not found then raise exception 'ITEM_NOT_FOUND';end if;
  return jsonb_build_object('ok',true);
 elsif p_action='delete_category' then
  if rid is null or category_name is null then raise exception 'INVALID_CATEGORY';end if;
  update tkt_private.restaurants set menu_categories=coalesce((
   select jsonb_agg(v order by ord) from jsonb_array_elements(coalesce(menu_categories,'[]'::jsonb)) with ordinality a(v,ord)
   where lower(trim(case when jsonb_typeof(v)='object' then coalesce(v->>'name',v->>'title','') else trim(both '"' from v::text) end))<>lower(category_name)
  ),'[]'::jsonb) where id=rid;
  delete from tkt_private.restaurant_items where restaurant_id=rid and lower(trim(coalesce(category,'')))=lower(category_name);
  return jsonb_build_object('ok',true);
 elsif p_action='delete_restaurant' then
  if rid is null then raise exception 'RESTAURANT_NOT_FOUND';end if;
  delete from tkt_private.restaurants where id=rid;
  if not found then raise exception 'RESTAURANT_NOT_FOUND';end if;
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'INVALID_ACTION';
end
$$;
revoke all on function tkt_private.admin_restaurants(text,jsonb) from public,anon,authenticated;
create or replace function public.tkt_admin_restaurants(p_action text,p_data jsonb default '{}'::jsonb)
returns jsonb
language sql
security definer
set search_path=''
as $$ select tkt_private.admin_restaurants(p_action,p_data) $$;
revoke all on function public.tkt_admin_restaurants(text,jsonb) from public,anon;
grant execute on function public.tkt_admin_restaurants(text,jsonb) to authenticated;
commit;
