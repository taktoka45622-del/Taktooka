alter table public.x_tickets add column if not exists latest_at timestamptz;
update public.x_tickets t set latest_at=greatest(t.created_at,coalesce((select max(m.created_at) from public.x_messages m where m.ticket_id=t.id),t.created_at)) where latest_at is null;
alter table public.x_tickets alter column latest_at set default now();
create or replace function x_private.ticket_activity() returns trigger language plpgsql security definer set search_path='' as $$begin
 update public.x_tickets set latest_at=greatest(coalesce(latest_at,created_at),new.created_at) where id=new.ticket_id;
 return new;
end$$;
revoke all on function x_private.ticket_activity() from public,anon,authenticated;
drop trigger if exists x_ticket_activity on public.x_messages;
create trigger x_ticket_activity after insert on public.x_messages for each row execute function x_private.ticket_activity();
create index if not exists x_products_newest_active on public.x_products(created_at desc,id) where active;
create index if not exists x_tickets_merchant_latest on public.x_tickets(merchant_id,latest_at desc);
create index if not exists x_messages_ticket_newest on public.x_messages(ticket_id,created_at desc,id);
grant select on public.x_landing_visits to authenticated;
drop policy if exists visits_owner_read on public.x_landing_visits;
create policy visits_owner_read on public.x_landing_visits for select to authenticated using(exists(select 1 from public.x_landing_pages p where p.id=page_id and (p.merchant_id=auth.uid() or x_private.admin())));
do $$declare t text; begin
 foreach t in array array['x_excel_uploads','x_import_keys','x_landing_pages','x_landing_visits','x_user_state','x_referrals','x_recovery_requests','x_audit'] loop
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then execute format('alter publication supabase_realtime add table public.%I',t); end if;
 end loop;
end$$;
