do $$
declare fn regprocedure; definition text;
begin
 foreach fn in array array[to_regprocedure('tkt_private.dispatch_v1(text,jsonb)'),to_regprocedure('tkt_private.dispatch(text,jsonb)')]loop
  if fn is null then continue;end if;
  definition:=pg_get_functiondef(fn);
  if position('delete from tkt_private.dispatch_locations;'in definition)>0 then
   definition:=replace(definition,'delete from tkt_private.dispatch_locations;', 'update tkt_private.dispatch_locations set received_at=''epoch''::timestamptz where captain_id is not null;');
   execute definition;
  end if;
 end loop;
end$$;
