do $$
declare definition text;needle text;replacement text;
begin
 definition:=pg_get_functiondef('public.tkt_route_quote(uuid,jsonb)'::regprocedure);
 needle:=$old$if jsonb_array_length(pickup)<>2 or jsonb_array_length(destination)<>2 or tkt_private.service_zone((pickup->>0)::float8,(pickup->>1)::float8) is null or tkt_private.service_zone((destination->>0)::float8,(destination->>1)::float8) is null then raise exception 'OUTSIDE_SERVICE';end if;$old$;
 replacement:=$new$if jsonb_array_length(pickup)<>2 or jsonb_array_length(destination)<>2 then raise exception 'OUTSIDE_SERVICE' using detail='invalid_points';end if;
 if tkt_private.service_zone((pickup->>0)::float8,(pickup->>1)::float8) is null then raise exception 'OUTSIDE_SERVICE' using detail='pickup';end if;
 if tkt_private.service_zone((destination->>0)::float8,(destination->>1)::float8) is null then raise exception 'OUTSIDE_SERVICE' using detail='destination';end if;$new$;
 if position(needle in definition)>0 then execute replace(definition,needle,replacement);
 elsif position(replacement in definition)=0 then raise exception 'COVERAGE_QUOTE_ANCHOR_MISSING';end if;
end $$;
