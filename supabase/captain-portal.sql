create table if not exists tkt_private.portal_members(user_id uuid primary key references public.tkt_profiles(user_id) on delete cascade,created_at timestamptz not null default now());
create table if not exists tkt_private.portal_settings(id boolean primary key default true check(id),android_url text not null default '',available boolean not null default false,announcement_id uuid);
insert into tkt_private.portal_settings(id) values(true) on conflict do nothing;
create table if not exists tkt_private.password_links(token_hash text primary key,user_id uuid not null references public.tkt_profiles(user_id) on delete cascade,issued_by uuid not null,expires_at timestamptz not null,used_at timestamptz);
alter table tkt_private.portal_members enable row level security;
alter table tkt_private.portal_settings enable row level security;
alter table tkt_private.password_links enable row level security;
revoke all on tkt_private.portal_members,tkt_private.portal_settings,tkt_private.password_links from public,anon,authenticated;
alter table tkt_private.portal_settings add column if not exists ios_url text not null default '', add column if not exists ios_available boolean not null default false;
create or replace function tkt_private.captain_portal(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();s tkt_private.portal_settings;r record;n integer:=0;batch uuid;url text:=btrim(coalesce(p_data->>'android_url',''));ios_link text:=btrim(coalesce(p_data->>'ios_url',''));
begin
 if p_action='settings' then select * into s from tkt_private.portal_settings where id;return jsonb_build_object('available',s.available,'android_available',s.available,'android_url',case when s.available then s.android_url else '' end,'ios_available',s.ios_available,'ios_url',case when s.ios_available then s.ios_url else '' end);end if;
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 if not exists(select 1 from public.tkt_profiles where user_id=u and not blocked) then raise exception 'ACCOUNT_BLOCKED';end if;
 if p_action='join' then
  if exists(select 1 from public.tkt_admins where user_id=u) or exists(select 1 from tkt_private.staff_accounts where user_id=u)then raise exception 'PROTECTED_ADMIN';end if;
  insert into tkt_private.portal_members(user_id)values(u)on conflict do nothing;return '{"ok":true}';
 elsif p_action='admin_get' then
  perform tkt_private.require_dashboard('applications',false);select * into s from tkt_private.portal_settings where id;
  return to_jsonb(s)||jsonb_build_object('members',(select count(*)from tkt_private.portal_members),'subscribed',(select count(distinct m.user_id)from tkt_private.portal_members m join tkt_private.push_devices d using(user_id)where d.platform='web'));
 elsif p_action='save' then
  perform tkt_private.require_dashboard('applications',true);
  if url<>'' and (url!~'^https://[^[:space:]]+$' or length(url)>2048)then raise exception 'INVALID_URL';end if;
  if coalesce((p_data->>'available')::boolean,false) and url=''then raise exception 'INVALID_URL';end if;
  if p_data ? 'ios_url' and ios_link<>'' and (ios_link!~'^https://[^[:space:]]+$' or length(ios_link)>2048)then raise exception 'INVALID_URL';end if;
  select * into s from tkt_private.portal_settings where id for update;
  if coalesce((p_data->>'ios_available')::boolean,s.ios_available) and coalesce(p_data->>'ios_url',s.ios_url)=''then raise exception 'INVALID_URL';end if;
  update tkt_private.portal_settings set android_url=url,available=coalesce((p_data->>'available')::boolean,false),ios_url=case when p_data ? 'ios_url' then ios_link else s.ios_url end,ios_available=coalesce((p_data->>'ios_available')::boolean,s.ios_available) where id;
  insert into tkt_private.admin_audit(actor_id,action,details)values(u,'portal_settings',jsonb_build_object('available',p_data->'available'));return '{"ok":true}';
 elsif p_action='announce' then
  perform tkt_private.require_dashboard('applications',true);select * into s from tkt_private.portal_settings where id for update;
  if not ((s.available and s.android_url<>'') or (s.ios_available and s.ios_url<>''))then raise exception 'APP_NOT_AVAILABLE';end if;
  if s.announcement_id is not null then raise exception 'ANNOUNCEMENT_SENT';end if;
  batch:=gen_random_uuid();
  for r in select m.user_id from tkt_private.portal_members m join public.tkt_profiles p using(user_id)where not p.blocked loop
   perform tkt_private.notification_add(r.user_id,'portal-launch:'||batch::text,'announcement','تكتوكة صار متوفر على '||case when s.available and s.ios_available then 'أندرويد وiOS' when s.ios_available then 'iOS' else 'أندرويد' end,'حمّل التطبيق وادخل بنفس رقمك وكلمة السر اللي سجلت بيها.',jsonb_build_object('url','https://x-spece.github.io/x-space-dashboard/captains/'));n:=n+1;
  end loop;
  update tkt_private.portal_settings set announcement_id=batch where id;
  insert into tkt_private.admin_audit(actor_id,action,details)values(u,'portal_announcement',jsonb_build_object('recipients',n));return jsonb_build_object('queued',n);
 end if;
 raise exception 'UNKNOWN_ACTION';
end $$;
revoke all on function tkt_private.captain_portal(text,jsonb)from public,anon,authenticated;
grant execute on function tkt_private.captain_portal(text,jsonb)to anon,authenticated;
create or replace function public.tkt_captain_portal(p_action text,p_data jsonb default '{}')returns jsonb language sql security invoker set search_path=''as $$select tkt_private.captain_portal(p_action,p_data)$$;
revoke all on function public.tkt_captain_portal(text,jsonb)from public;
grant execute on function public.tkt_captain_portal(text,jsonb)to anon,authenticated;
create or replace function tkt_private.password_link_service(p_action text,p_data jsonb)returns jsonb language plpgsql security definer set search_path=''as $$
declare target uuid;issuer uuid;ph text;rec tkt_private.password_links;
begin
 if p_action='issue' then
  target:=(p_data->>'user_id')::uuid;issuer:=(p_data->>'actor_id')::uuid;
  if not exists(select 1 from public.tkt_profiles where user_id=issuer and not blocked)then raise exception 'FORBIDDEN';end if;
  if not exists(select 1 from public.tkt_admins where user_id=issuer) and not exists(select 1 from tkt_private.staff_accounts where user_id=issuer and active and permissions->'security'->>'view'='true' and permissions->'security'->>'edit'='true')then raise exception 'FORBIDDEN';end if;
  if not exists(select 1 from public.tkt_profiles where user_id=target and not blocked)or exists(select 1 from public.tkt_admins where user_id=target)or exists(select 1 from tkt_private.staff_accounts where user_id=target)then raise exception 'FORBIDDEN';end if;
  if p_data->>'token_hash' is null or p_data->>'token_hash'!~'^[0-9a-f]{64}$'then raise exception 'INVALID_TOKEN';end if;
  perform pg_advisory_xact_lock(hashtextextended(target::text,192));
  update tkt_private.password_links set used_at=now()where user_id=target and used_at is null;
  insert into tkt_private.password_links values(p_data->>'token_hash',target,issuer,now()+interval '30 minutes',null);
  insert into tkt_private.admin_audit(actor_id,action,entity_id,details)values(issuer,'password_link_issued',target::text,'{}');return '{"ok":true}';
 elsif p_action='consume' then
  update tkt_private.password_links set used_at=now()where token_hash=p_data->>'token_hash' and used_at is null and expires_at>now() returning * into rec;
  if not found then raise exception 'LINK_EXPIRED';end if;target:=rec.user_id;issuer:=rec.issued_by;
  if not exists(select 1 from public.tkt_profiles where user_id=issuer and not blocked)then raise exception 'FORBIDDEN';end if;
  if not exists(select 1 from public.tkt_admins where user_id=issuer) and not exists(select 1 from tkt_private.staff_accounts where user_id=issuer and active and permissions->'security'->>'view'='true' and permissions->'security'->>'edit'='true')then raise exception 'FORBIDDEN';end if;
  select phone into ph from public.tkt_profiles where user_id=target and not blocked;
  if ph is null or exists(select 1 from public.tkt_admins where user_id=target)or exists(select 1 from tkt_private.staff_accounts where user_id=target)then raise exception 'FORBIDDEN';end if;
  return jsonb_build_object('user_id',target,'phone',ph,'actor_id',issuer);
 elsif p_action='complete' then
  select * into rec from tkt_private.password_links where token_hash=p_data->>'token_hash' and used_at is not null;
  if not found then raise exception 'LINK_EXPIRED';end if;
  select tkt_private.normalize_phone(phone)into ph from public.tkt_profiles where user_id=rec.user_id;
  update tkt_private.phone_attempts set failures=0,requests=0,window_at=now()where phone=ph;
  insert into tkt_private.admin_audit(actor_id,action,entity_id,details)values(rec.issued_by,'password_link_used',rec.user_id::text,'{}');return '{"ok":true}';
 end if;raise exception 'UNKNOWN_ACTION';
end $$;
revoke all on function tkt_private.password_link_service(text,jsonb)from public,anon,authenticated;
grant execute on function tkt_private.password_link_service(text,jsonb)to service_role;
create or replace function public.tkt_password_link_service(p_action text,p_data jsonb)returns jsonb language sql security invoker set search_path=''as $$select tkt_private.password_link_service(p_action,p_data)$$;
revoke all on function public.tkt_password_link_service(text,jsonb)from public,anon,authenticated;
grant execute on function public.tkt_password_link_service(text,jsonb)to service_role;
