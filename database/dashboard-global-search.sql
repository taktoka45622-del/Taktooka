create or replace function exchange_gateway.global_search(p_query text,p_kind text default 'all',p_offset integer default 0)returns jsonb language plpgsql stable security definer set search_path='' set statement_timeout='8s' as $$
declare q text:=trim(translate(coalesce(p_query,''),'٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹','01234567890123456789'));digits text;pattern text;result jsonb:='{}';offn integer:=greatest(0,least(coalesce(p_offset,0),10000));
begin
 if auth.uid()is null then raise exception 'AUTH_REQUIRED';end if;
 if not exists(select 1 from public.tkt_profiles p where p.user_id=auth.uid()and not p.blocked)or not(tkt_private.is_admin()or exists(select 1 from tkt_private.staff_accounts where user_id=auth.uid()and active))then raise exception 'PERMISSION_DENIED';end if;
 if length(q)<2 then return '{}'::jsonb;end if;
 if length(q)>100 or p_kind not in('all','users','rides','exchanges','lines')then raise exception 'INVALID_SEARCH';end if;
 digits:=regexp_replace(q,'[^0-9]','','g');if digits like '00964%'then digits:='0'||substr(digits,6);elsif digits like '964%'then digits:='0'||substr(digits,4);end if;
 pattern:='%'||replace(replace(replace(q,E'\\',E'\\\\'),'%',E'\\%'),'_',E'\\_')||'%';
 if p_kind in('all','users')and(tkt_private.dashboard_permission('users')or tkt_private.dashboard_permission('inventory'))then
 result:=result||jsonb_build_object('users',coalesce((select jsonb_agg(to_jsonb(x))from(select p.user_id,p.name,p.phone,p.captain,p.blocked,p.expires_at from public.tkt_profiles p where not exists(select 1 from tkt_private.staff_accounts where user_id=p.user_id)and not exists(select 1 from tkt_private.admin_archives where kind='user'and entity_id=p.user_id::text)and(p.name ilike pattern or p.user_id::text ilike pattern or(length(digits)>=3 and regexp_replace(regexp_replace(p.phone,'[^0-9]','','g'),'^964','0')like '%'||digits||'%'))order by case when p.phone=q then 0 when lower(p.name)=lower(q)then 1 else 2 end,p.created_at desc,p.user_id limit 21 offset offn)x),'[]'));
 end if;
 if p_kind in('all','rides')and(tkt_private.dashboard_permission('rides')or tkt_private.dashboard_permission('inventory'))then
 result:=result||jsonb_build_object('rides',coalesce((select jsonb_agg(to_jsonb(x))from(select r.id,r.status,r.pickup_name,r.destination_name,r.created_at,p.name rider_name,c.name captain_name from public.tkt_rides r left join public.tkt_profiles p on p.user_id=r.rider_id left join public.tkt_profiles c on c.user_id=r.captain_id where not exists(select 1 from tkt_private.admin_archives where kind='ride'and entity_id=r.id::text)and(r.id::text ilike pattern or r.pickup_name ilike pattern or r.destination_name ilike pattern or p.name ilike pattern or c.name ilike pattern or(length(digits)>=3 and(regexp_replace(regexp_replace(p.phone,'[^0-9]','','g'),'^964','0')like '%'||digits||'%'or regexp_replace(regexp_replace(c.phone,'[^0-9]','','g'),'^964','0')like '%'||digits||'%')))order by case when r.id::text=q then 0 else 1 end,r.created_at desc,r.id limit 21 offset offn)x),'[]'));
 end if;
 if p_kind in('all','exchanges')and tkt_private.is_admin()then
 result:=result||jsonb_build_object('exchanges',coalesce((select jsonb_agg(to_jsonb(x))from(select a.id,a.name,a.personal_name,a.phone,a.personal_phone,a.province,a.area,a.active from tkt_private.exchange_agents a where a.name ilike pattern or a.personal_name ilike pattern or a.id::text ilike pattern or a.province ilike pattern or a.area ilike pattern or a.street ilike pattern or(length(digits)>=3 and(regexp_replace(regexp_replace(a.phone,'[^0-9]','','g'),'^964','0')like '%'||digits||'%'or regexp_replace(regexp_replace(a.personal_phone,'[^0-9]','','g'),'^964','0')like '%'||digits||'%'))order by a.created_at desc,a.id limit 21 offset offn)x),'[]'));
 end if;
 if p_kind in('all','lines')and tkt_private.dashboard_permission('lines')then
 result:=result||jsonb_build_object('lines',coalesce((select jsonb_agg(to_jsonb(x))from(select l.id,l.passenger_name,l.pickup_name,l.destination_name,l.status,l.created_at from tkt_private.lines l left join public.tkt_profiles p on p.user_id=l.customer_id left join public.tkt_profiles c on c.user_id=l.captain_id where l.id::text ilike pattern or l.passenger_name ilike pattern or l.pickup_name ilike pattern or l.destination_name ilike pattern or p.name ilike pattern or c.name ilike pattern or(length(digits)>=3 and(regexp_replace(regexp_replace(p.phone,'[^0-9]','','g'),'^964','0')like '%'||digits||'%'or regexp_replace(regexp_replace(c.phone,'[^0-9]','','g'),'^964','0')like '%'||digits||'%'))order by l.created_at desc,l.id limit 21 offset offn)x),'[]'));
 end if;return result;
end $$;
revoke all on function exchange_gateway.global_search(text,text,integer)from public,anon;
grant execute on function exchange_gateway.global_search(text,text,integer)to authenticated;
create or replace function public.tkt_global_search(p_query text,p_kind text default 'all',p_offset integer default 0)returns jsonb language sql stable set search_path='' as $$select exchange_gateway.global_search(p_query,p_kind,p_offset)$$;
revoke all on function public.tkt_global_search(text,text,integer)from public,anon;
grant execute on function public.tkt_global_search(text,text,integer)to authenticated;
notify pgrst,'reload schema';
