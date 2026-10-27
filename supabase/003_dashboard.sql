begin;
create or replace function public.x_admin_access() returns boolean language sql stable security definer set search_path='' as $$ select x_private.admin() $$;
revoke all on function public.x_admin_access() from public,anon;
grant execute on function public.x_admin_access() to authenticated;
create or replace function public.x_admin_notify(p_user uuid,p_text text) returns void language plpgsql security definer set search_path='' as $$ begin
 if not x_private.admin() then raise exception 'للإدارة فقط'; end if;
 if length(trim(p_text)) not between 1 and 2000 then raise exception 'راجع نص الإشعار'; end if;
 if p_user is not null then
 if not exists(select 1 from public.x_profiles where user_id=p_user) then raise exception 'التاجر غير موجود'; end if;
 perform x_private.notify(p_user,'general',trim(p_text));
 else insert into public.x_notifications(merchant_id,type,text) select user_id,'general',trim(p_text) from public.x_profiles where not blocked; end if;
 insert into public.x_audit(actor_id,action,entity_id) values(auth.uid(),'admin_notification',coalesce(p_user::text,'all'));
end $$;
create or replace function public.x_admin_ticket(p_id text,p_status text) returns void language plpgsql security definer set search_path='' as $$ begin
 if not x_private.admin() then raise exception 'للإدارة فقط'; end if;
 if p_status not in ('open','closed') then raise exception 'حالة غير صحيحة'; end if;
 update public.x_tickets set status=p_status where id=p_id;
 if not found then raise exception 'المحادثة غير موجودة'; end if;
 insert into public.x_audit(actor_id,action,entity_id,data) values(auth.uid(),'ticket_status',p_id,jsonb_build_object('status',p_status));
end $$;
create or replace function public.x_admin_recovery(p_id uuid,p_status text) returns void language plpgsql security definer set search_path='' as $$ begin
 if not x_private.admin() then raise exception 'للإدارة فقط'; end if;
 if p_status not in ('reviewing','resolved','rejected') then raise exception 'حالة غير صحيحة'; end if;
 update public.x_recovery_requests set status=p_status where id=p_id;
 if not found then raise exception 'الطلب غير موجود'; end if;
 insert into public.x_audit(actor_id,action,entity_id,data) values(auth.uid(),'recovery_review',p_id::text,jsonb_build_object('status',p_status));
end $$;
revoke all on function public.x_admin_notify(uuid,text),public.x_admin_ticket(text,text),public.x_admin_recovery(uuid,text) from public,anon;
grant execute on function public.x_admin_notify(uuid,text),public.x_admin_ticket(text,text),public.x_admin_recovery(uuid,text) to authenticated;
create or replace function x_private.catalog_audit() returns trigger language plpgsql security definer set search_path='' as $$begin
 insert into public.x_audit(actor_id,action,entity_id,data) values(auth.uid(),lower(tg_op)||':'||tg_table_name,new.id::text,jsonb_build_object('before',case when tg_op='UPDATE' then to_jsonb(old) else null end,'after',to_jsonb(new)));
 return new; end$$;
revoke all on function x_private.catalog_audit() from public,anon,authenticated;
do $$declare t text;begin foreach t in array array['x_products','x_categories','x_banners','x_settings'] loop
 execute format('drop trigger if exists dashboard_audit on public.%I',t);
 execute format('create trigger dashboard_audit after insert or update on public.%I for each row execute function x_private.catalog_audit()',t);
 end loop;end$$;
drop policy if exists x_attachment_insert on storage.objects;
create policy x_attachment_insert on storage.objects for insert to authenticated with check(bucket_id='x-space-private' and (storage.foldername(name))[1]=auth.uid()::text and case when x_private.admin() then true else x_private.member() is not null end);
do $$begin if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='x_categories') then alter publication supabase_realtime add table public.x_categories;end if;end$$;
commit;
