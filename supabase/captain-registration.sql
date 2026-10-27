create table if not exists public.tkt_captain_applications(
 user_id uuid primary key references public.tkt_profiles(user_id),
 full_name text not null default '',phone text not null default '',chassis text not null default '',color text not null default '',model text not null default '',
 documents jsonb not null default '{}',pending_slot text,
 status text not null default 'draft' check(status in('draft','pending','changes_required','approved')),
 revision integer not null default 0,reason text not null default '',reviewed_by uuid references public.tkt_profiles(user_id),
 submitted_at timestamptz,reviewed_at timestamptz,updated_at timestamptz not null default now()
);
alter table public.tkt_captain_applications enable row level security;
revoke all on public.tkt_captain_applications from anon,authenticated;
grant select on public.tkt_captain_applications to authenticated;
create policy captain_application_read on public.tkt_captain_applications for select to authenticated using(
 exists(select 1 from public.tkt_profiles where user_id=(select auth.uid()) and not blocked) and (user_id=(select auth.uid()) or (select tkt_private.is_admin()))
);
create index captain_application_queue on public.tkt_captain_applications(status,submitted_at desc);
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('captain-documents','captain-documents',false,6291456,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
create policy captain_document_read on storage.objects for select to authenticated using(bucket_id='captain-documents' and exists(select 1 from public.tkt_profiles where user_id=(select auth.uid()) and not blocked) and (split_part(name,'/',1)=(select auth.uid())::text or (select tkt_private.is_admin())));
create policy captain_document_upload on storage.objects for insert to authenticated with check(bucket_id='captain-documents' and split_part(name,'/',1)=(select auth.uid())::text and exists(select 1 from public.tkt_profiles where user_id=(select auth.uid()) and not blocked and not captain) and not exists(select 1 from public.tkt_captain_applications where user_id=(select auth.uid()) and status in('pending','approved')));
create policy captain_document_cleanup on storage.objects for delete to authenticated using(bucket_id='captain-documents' and split_part(name,'/',1)=(select auth.uid())::text and not exists(select 1 from public.tkt_captain_applications a where a.user_id=(select auth.uid()) and (a.status in('pending','approved') or exists(select 1 from jsonb_each_text(a.documents)d where d.value=storage.objects.name))));

create policy captain_document_admin_cleanup on storage.objects for delete to authenticated using(bucket_id='captain-documents' and (select tkt_private.is_admin()) and exists(select 1 from public.tkt_profiles where user_id=(select auth.uid()) and not blocked) and not exists(select 1 from public.tkt_captain_applications a cross join lateral jsonb_each_text(a.documents)d where d.value=storage.objects.name));

create or replace function tkt_private.captain_registration(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();a public.tkt_captain_applications;target uuid;slot text;path text;ph text;decision text;why text;lim integer:=least(200,greatest(1,coalesce((p_data->>'limit')::integer,100)));offn integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 if not exists(select 1 from public.tkt_profiles where user_id=u and not blocked)then raise exception 'ACCOUNT_BLOCKED';end if;
 if p_action='get' then return (select to_jsonb(x)from public.tkt_captain_applications x where user_id=u);end if;
 if p_action in('list','review')then
  if not tkt_private.is_admin()then raise exception 'ADMIN_REQUIRED';end if;
  if p_action='list'then return coalesce((select jsonb_agg(to_jsonb(x))from(select app.* from public.tkt_captain_applications app where app.status<>'draft' and (coalesce(p_data->>'status','')='' or app.status=p_data->>'status') and (coalesce(p_data->>'search','')='' or app.full_name ilike '%'||(p_data->>'search')||'%' or app.phone ilike '%'||(p_data->>'search')||'%' or app.chassis ilike '%'||(p_data->>'search')||'%') order by app.submitted_at desc limit lim offset offn)x),'[]'::jsonb);end if;
  target:=(p_data->>'user_id')::uuid;
  perform pg_advisory_xact_lock(74658291);
  select * into a from public.tkt_captain_applications where user_id=target for update;
  if not found or a.status<>'pending' or a.revision is distinct from (p_data->>'revision')::integer then raise exception 'APPLICATION_CHANGED';end if;
  if exists(select 1 from public.tkt_admins where user_id=target)then raise exception 'PROTECTED_ADMIN';end if;
  decision:=p_data->>'decision';why:=btrim(coalesce(p_data->>'reason',''));
  if decision not in('approved','changes_required') or decision is null then raise exception 'INVALID_DECISION';end if;
  if decision='changes_required' and length(why) not between 3 and 2000 then raise exception 'REASON_REQUIRED';end if;
  if decision='approved'then
   if not exists(select 1 from public.tkt_profiles where user_id=target and not blocked)then raise exception 'ACCOUNT_BLOCKED';end if;
   if exists(select 1 from public.tkt_rides where (rider_id=target or captain_id=target)and status in('pending','accepted','arrived','in_progress'))then raise exception 'ACTIVE_RIDE';end if;
   perform set_config('taktooka.reviewing_captain',target::text,true);
   update public.tkt_profiles set captain=true,online=false,name=a.full_name where user_id=target;
  end if;
  update public.tkt_captain_applications set status=decision,reason=case when decision='approved'then '' else why end,reviewed_by=u,reviewed_at=clock_timestamp(),updated_at=clock_timestamp()where user_id=target returning * into a;
  update tkt_private.preferences set captain_requested_at=null where user_id=target;
  insert into tkt_private.admin_audit(actor_id,action,entity_id,details)values(u,'captain_'||decision,target::text,jsonb_build_object('revision',a.revision,'status',decision));
  insert into public.tkt_messages(user_id,sender_id,is_admin,body)values(target,u,true,case when decision='approved'then 'تمت الموافقة على تسجيلك ككابتن؛ حساب الكابتن متاح الآن.'else 'طلب تسجيل الكابتن يحتاج تعديل: '||why end);
  return to_jsonb(a);
 end if;
 if p_action not in('save','submit')then raise exception 'UNKNOWN_ACTION';end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text,7341));
 if exists(select 1 from public.tkt_profiles where user_id=u and captain)then raise exception 'ALREADY_CAPTAIN';end if;
 insert into public.tkt_captain_applications(user_id)values(u)on conflict(user_id)do nothing;
 select * into a from public.tkt_captain_applications where user_id=u for update;
 if a.status in('pending','approved')then
  if p_action='submit' and a.status='pending'then return to_jsonb(a);end if;
  raise exception 'APPLICATION_LOCKED';
 end if;
 if p_action='save'then
  if p_data ? 'full_name'then a.full_name:=btrim(p_data->>'full_name');end if;
  if p_data ? 'phone'then
   ph:=tkt_private.normalize_phone(p_data->>'phone');
   if ph is null or ph is distinct from (select tkt_private.normalize_phone(phone)from public.tkt_profiles where user_id=u)then raise exception 'ACCOUNT_PHONE_REQUIRED';end if;
   a.phone:=ph;
  end if;
  if p_data ? 'chassis'then a.chassis:=btrim(p_data->>'chassis');end if;
  if p_data ? 'color'then a.color:=btrim(p_data->>'color');end if;
  if p_data ? 'model'then a.model:=btrim(p_data->>'model');end if;
  if length(a.full_name)>160 or length(a.chassis)>80 or length(a.color)>50 or length(a.model)>80 then raise exception 'INVALID_FIELDS';end if;
  if p_data ? 'pending_slot'then
   slot:=p_data->>'pending_slot';if slot is not null and slot not in('id_front','id_back','residence_front','residence_back','portrait')then raise exception 'INVALID_DOCUMENT';end if;a.pending_slot:=slot;
  end if;
  if p_data ? 'document'then
   slot:=p_data->'document'->>'slot';path:=p_data->'document'->>'path';
   if slot is null or slot not in('id_front','id_back','residence_front','residence_back','portrait')or path is null or split_part(path,'/',1)<>u::text or not exists(select 1 from storage.objects where bucket_id='captain-documents'and name=path)then raise exception 'INVALID_DOCUMENT';end if;
   a.documents:=jsonb_set(a.documents,array[slot],to_jsonb(path),true);a.pending_slot:=null;
  end if;
 else
  if cardinality(regexp_split_to_array(btrim(a.full_name),'\s+'))<3 or length(a.full_name)<5 then raise exception 'FULL_NAME_REQUIRED';end if;
  if a.phone='' or a.phone is distinct from (select tkt_private.normalize_phone(phone)from public.tkt_profiles where user_id=u)then raise exception 'ACCOUNT_PHONE_REQUIRED';end if;
  if length(a.chassis)<3 or a.color=''or a.model=''then raise exception 'VEHICLE_REQUIRED';end if;
  foreach slot in array array['id_front','id_back','residence_front','residence_back','portrait']loop
   path:=a.documents->>slot;
   if path is null or not exists(select 1 from storage.objects where bucket_id='captain-documents'and name=path and split_part(name,'/',1)=u::text)then raise exception 'DOCUMENTS_REQUIRED';end if;
  end loop;
  a.status:='pending';a.reason:='';a.revision:=a.revision+1;a.submitted_at:=clock_timestamp();a.reviewed_at:=null;a.reviewed_by:=null;a.pending_slot:=null;
  insert into tkt_private.preferences(user_id,captain_requested_at)values(u,clock_timestamp())on conflict(user_id)do update set captain_requested_at=excluded.captain_requested_at;
 end if;
 update public.tkt_captain_applications set full_name=a.full_name,phone=a.phone,chassis=a.chassis,color=a.color,model=a.model,documents=a.documents,pending_slot=a.pending_slot,status=a.status,reason=a.reason,revision=a.revision,submitted_at=a.submitted_at,reviewed_at=a.reviewed_at,reviewed_by=a.reviewed_by,updated_at=clock_timestamp()where user_id=u returning * into a;
 return to_jsonb(a);
end $$;
revoke all on function tkt_private.captain_registration(text,jsonb)from public,anon;
grant execute on function tkt_private.captain_registration(text,jsonb)to authenticated;
create or replace function public.tkt_captain_registration(p_action text,p_data jsonb default '{}')returns jsonb language sql security invoker set search_path='' as $$select tkt_private.captain_registration(p_action,p_data)$$;
revoke all on function public.tkt_captain_registration(text,jsonb)from public,anon;
grant execute on function public.tkt_captain_registration(text,jsonb)to authenticated;

create or replace function tkt_private.guard_captain_application()returns trigger language plpgsql security definer set search_path=''as $$
begin
 if new.captain and not old.captain and exists(select 1 from public.tkt_captain_applications where user_id=new.user_id and status<>'approved')then
  if not tkt_private.is_admin() or current_setting('taktooka.reviewing_captain',true) is distinct from new.user_id::text then raise exception 'USE_VEHICLE_REGISTRATION';end if;
 end if;return new;
end $$;
revoke all on function tkt_private.guard_captain_application()from public,anon,authenticated;
create trigger guard_captain_application before update of captain on public.tkt_profiles for each row execute function tkt_private.guard_captain_application();
