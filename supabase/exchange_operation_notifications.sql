
create or replace function tkt_private.exchange_operation_notice()returns trigger language plpgsql security definer set search_path='' as $fn$
declare aid uuid;agent_user uuid;shop text;title text;body text;screen text;event_key text;admin_user uuid;
begin
 aid:=new.agent_id;select user_id,name into agent_user,shop from tkt_private.exchange_agents where id=aid;
 if tg_table_name='exchange_messages' then
 if not new.is_admin then return new;end if;
 title:='رد جديد من دعم تكتوكة';body:=left(new.body,160);screen:='support';event_key:='agent-support:'||new.id::text;
 elsif tg_table_name='exchange_settlements' then
 title:=case when new.due_after=0 then 'تم تسديد وتصفير ذمّتك' else 'تم تسجيل تسديد' end;
 body:='تم استلام '||to_char(new.amount,'FM999,999,999,990')||' د.ع. المتبقي بذمّتك: '||to_char(new.due_after,'FM999,999,999,990')||' د.ع.';screen:='settlements';event_key:='agent-settlement:'||new.id::text;
 else
 title:=case when new.kind='credit' then 'تم شحن رصيد الصيرفة' else 'تم تفعيل اشتراك كابتن' end;
 body:=to_char(new.amount,'FM999,999,999,990')||' د.ع. الرصيد المتاح: '||to_char(new.balance_after,'FM999,999,999,990')||' د.ع.';screen:='transactions';event_key:='agent-transaction:'||new.id::text;
 end if;
 if agent_user is not null then perform tkt_private.notification_add(agent_user,event_key,'exchange',title,body,jsonb_build_object('screen','exchange_agent','agent_screen',screen,'agent_id',aid,'transaction_id',new.id));end if;
 if tg_table_name<>'exchange_messages' then
 for admin_user in select a.user_id from public.tkt_admins a join public.tkt_profiles p on p.user_id=a.user_id where not p.blocked and a.user_id is distinct from auth.uid()
 loop perform tkt_private.notification_add(admin_user,event_key,'exchange',shop||' · '||title,body,jsonb_build_object('screen','exchange_finance','agent_id',aid));end loop;
 end if;
 return new;
end $fn$;
revoke all on function tkt_private.exchange_operation_notice() from public,anon,authenticated;
drop trigger if exists tkt_exchange_operation_notice on tkt_private.exchange_messages;
create trigger tkt_exchange_operation_notice after insert on tkt_private.exchange_messages for each row execute function tkt_private.exchange_operation_notice();
drop trigger if exists tkt_exchange_operation_notice on tkt_private.exchange_transactions;
create trigger tkt_exchange_operation_notice after insert on tkt_private.exchange_transactions for each row execute function tkt_private.exchange_operation_notice();
drop trigger if exists tkt_exchange_operation_notice on tkt_private.exchange_settlements;
create trigger tkt_exchange_operation_notice after insert on tkt_private.exchange_settlements for each row execute function tkt_private.exchange_operation_notice();
