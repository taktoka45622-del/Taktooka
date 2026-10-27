create or replace function tkt_private.service_zone(lat float8,lng float8)
returns text language plpgsql stable set search_path='' as $$
#variable_conflict use_column
declare z jsonb;pts jsonb;a jsonb;b jsonb;i integer;j integer;inside boolean;
 ax float8;ay float8;bx float8;byy float8;dx float8;dy float8;length_sq float8;cross_product float8;projection float8;
begin
 if lat is null or lng is null or lat='NaN'::float8 or lng='NaN'::float8 then return null;end if;
 for z in select value from jsonb_array_elements((select zones from tkt_private.dispatch_settings where id)) loop
  pts:=z->'geometry'->'coordinates'->0;
  if jsonb_array_length(pts)<4 then continue;end if;
  inside:=false;j:=jsonb_array_length(pts)-1;
  for i in 0..jsonb_array_length(pts)-1 loop
   a:=pts->i;b:=pts->j;ax:=(a->>0)::float8;ay:=(a->>1)::float8;bx:=(b->>0)::float8;byy:=(b->>1)::float8;
   dx:=bx-ax;dy:=byy-ay;length_sq:=dx*dx+dy*dy;
   if length_sq>0 then
    cross_product:=(lng-ax)*dy-(lat-ay)*dx;projection:=(lng-ax)*dx+(lat-ay)*dy;
    if abs(cross_product)<=1e-10*sqrt(length_sq) and projection>=0 and projection<=length_sq then return z->>'id';end if;
   end if;
   if ((ay>lat)<>(byy>lat)) and lng<(bx-ax)*(lat-ay)/(byy-ay)+ax then inside:=not inside;end if;
   j:=i;
  end loop;
  if inside then return z->>'id';end if;
 end loop;
 return null;
end $$;
