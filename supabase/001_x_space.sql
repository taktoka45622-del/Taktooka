-- X-Space 2.0: rerunnable, no destructive drops, server-authoritative business operations.
begin;
create schema if not exists x_private;
revoke all on schema x_private from public;
create table if not exists public.x_admins(user_id uuid primary key references auth.users(id), created_at timestamptz not null default now());
alter table public.x_admins enable row level security;
create or replace function x_private.admin() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.x_admins where user_id=auth.uid())$$;
create table if not exists public.x_profiles(
 user_id uuid primary key references auth.users(id), phone text not null unique, data jsonb not null default '{}', blocked boolean not null default false, created_at timestamptz not null default now());
create or replace function x_private.member() returns uuid language plpgsql stable security definer set search_path='' as $$begin
 if auth.uid() is null then raise exception 'سجل الدخول'; end if;
 if not exists(select 1 from public.x_profiles where user_id=auth.uid() and not blocked) then raise exception 'الحساب غير مكتمل أو محظور'; end if;
 return auth.uid(); end$$;
create table if not exists public.x_products(id text primary key, data jsonb not null, stock integer not null check(stock>=0), active boolean not null default true, sort_order integer not null default 0, created_at timestamptz not null default now());
create table if not exists public.x_categories(id uuid primary key default gen_random_uuid(), name text not null unique, sort_order integer not null default 0, active boolean not null default true);
create table if not exists public.x_banners(id uuid primary key default gen_random_uuid(), asset text not null, target_url text, active boolean not null default true, sort_order integer not null default 0);
alter table public.x_banners add column if not exists crop jsonb;
create table if not exists public.x_settings(id boolean primary key default true check(id), data jsonb not null default '{}');
insert into public.x_settings(id,data) values(true,'{"deliveryCost":5000,"freeDeliveryMinimumProfit":7000,"bannerEnabled":true,"landingBaseUrl":null}') on conflict do nothing;
create table if not exists public.x_orders(id text primary key, merchant_id uuid not null references public.x_profiles(user_id), payload jsonb not null, status text not null default 'معلق', created_at timestamptz not null default now(), updated_at timestamptz not null default now(), cancellation_requested boolean not null default false, unique(merchant_id,id));
create index if not exists x_orders_merchant on public.x_orders(merchant_id,created_at desc);
create table if not exists public.x_wallet_entries(id uuid primary key default gen_random_uuid(), merchant_id uuid not null references public.x_profiles(user_id), amount bigint not null, source text not null unique, description text not null, created_at timestamptz not null default now());
create table if not exists public.x_withdrawals(id text primary key, merchant_id uuid not null references public.x_profiles(user_id), amount bigint not null check(amount>0), method text not null, number text not null, status text not null default 'قيد الانتظار' check(status in ('قيد الانتظار','تم التسديد','مرفوض')), reason text, receipt_path text, created_at timestamptz not null default now());
create table if not exists public.x_profile_requests(id text primary key, merchant_id uuid not null references public.x_profiles(user_id), data jsonb not null, status text not null default 'pending', created_at timestamptz not null default now());
create unique index if not exists x_profile_pending on public.x_profile_requests(merchant_id) where status='pending';
create table if not exists public.x_notifications(id uuid primary key default gen_random_uuid(), merchant_id uuid not null references public.x_profiles(user_id), type text not null, text text not null, order_id text, ticket_id text, is_read boolean not null default false, created_at timestamptz not null default now());
create table if not exists public.x_tickets(id text primary key, merchant_id uuid not null references public.x_profiles(user_id), order_id text references public.x_orders(id), type text not null default 'دعم عام', status text not null default 'open', created_at timestamptz not null default now());
create unique index if not exists x_one_ticket_per_order on public.x_tickets(order_id) where order_id is not null;
create table if not exists public.x_messages(id text primary key, ticket_id text not null references public.x_tickets(id), sender_id uuid not null references auth.users(id), text text not null check(length(text)<=10000), attachment_path text, file_name text, deleted boolean not null default false, created_at timestamptz not null default now(), edited_at timestamptz);
create index if not exists x_messages_ticket on public.x_messages(ticket_id,created_at);
create table if not exists public.x_excel_uploads(id text primary key, merchant_id uuid not null references public.x_profiles(user_id), fingerprint text not null, data jsonb not null, created_at timestamptz not null default now(), unique(merchant_id,fingerprint));
create table if not exists public.x_import_keys(merchant_id uuid not null references public.x_profiles(user_id), upload_id text not null references public.x_excel_uploads(id), key text not null, order_id text not null references public.x_orders(id), primary key(merchant_id,upload_id,key));
create table if not exists public.x_landing_pages(id text primary key, merchant_id uuid not null references public.x_profiles(user_id), product_id text not null references public.x_products(id), sale bigint not null, free_delivery boolean not null default false, active boolean not null default true, created_at timestamptz not null default now());
create table if not exists public.x_landing_visits(page_id text not null references public.x_landing_pages(id), visitor_id text not null, day date not null default current_date, primary key(page_id,visitor_id,day));
create table if not exists public.x_user_state(merchant_id uuid primary key references public.x_profiles(user_id), data jsonb not null default '{}', updated_at timestamptz not null default now());
create table if not exists public.x_recovery_requests(id uuid primary key default gen_random_uuid(), phone text not null, details text not null, status text not null default 'pending', created_at timestamptz not null default now());
create table if not exists public.x_exchange_requests(id text primary key, merchant_id uuid not null references public.x_profiles(user_id), order_id text not null references public.x_orders(id), data jsonb not null, status text not null default 'قيد المراجعة', created_at timestamptz not null default now());
create table if not exists public.x_employees(id uuid primary key default gen_random_uuid(), merchant_id uuid not null references public.x_profiles(user_id), employee_user_id uuid references public.x_profiles(user_id), data jsonb not null, active boolean not null default true, unique(merchant_id,employee_user_id));
create table if not exists public.x_referrals(referred_id uuid primary key references public.x_profiles(user_id), referrer_id uuid not null references public.x_profiles(user_id), rewarded boolean not null default false, check(referred_id<>referrer_id), created_at timestamptz not null default now());
create table if not exists public.x_audit(id bigint generated always as identity primary key, actor_id uuid, action text not null, entity_id text, data jsonb not null default '{}', created_at timestamptz not null default now());
-- Never put admin/service keys in Flutter. Admin membership is inserted by project owner only.
do $$declare t text; begin
 foreach t in array array['x_profiles','x_products','x_categories','x_banners','x_settings','x_orders','x_wallet_entries','x_withdrawals','x_profile_requests','x_notifications','x_tickets','x_messages','x_excel_uploads','x_import_keys','x_landing_pages','x_landing_visits','x_user_state','x_recovery_requests','x_exchange_requests','x_employees','x_referrals','x_audit'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from anon,authenticated',t);
 end loop;
end$$;
grant usage on schema x_private to anon, authenticated;
grant execute on function x_private.admin() to anon,authenticated;
grant execute on function x_private.member() to authenticated;
grant select on public.x_products,public.x_categories,public.x_banners,public.x_settings to anon,authenticated;
grant select on public.x_profiles,public.x_orders,public.x_wallet_entries,public.x_withdrawals,public.x_profile_requests,public.x_notifications,public.x_tickets,public.x_messages,public.x_excel_uploads,public.x_import_keys,public.x_landing_pages,public.x_user_state,public.x_exchange_requests,public.x_employees,public.x_referrals,public.x_audit,public.x_recovery_requests to authenticated;
grant insert,update on public.x_user_state,public.x_excel_uploads to authenticated;
grant update(is_read) on public.x_notifications to authenticated;
-- Administrative catalogue edits only, business accounting goes through RPCs.
grant insert,update on public.x_products,public.x_categories,public.x_banners,public.x_settings to authenticated;
do $$declare t text; begin foreach t in array array['x_products','x_categories','x_banners'] loop
 execute format('drop policy if exists catalog_read on public.%I',t);
 execute format('create policy catalog_read on public.%I for select using(active or x_private.admin())',t);
 execute format('drop policy if exists catalog_admin on public.%I',t);
 execute format('create policy catalog_admin on public.%I for all to authenticated using(x_private.admin()) with check(x_private.admin())',t);
end loop; end$$;
drop policy if exists settings_read on public.x_settings;
create policy settings_read on public.x_settings for select using(true);
drop policy if exists settings_admin on public.x_settings;
create policy settings_admin on public.x_settings for all to authenticated using(x_private.admin()) with check(x_private.admin());
drop policy if exists profiles_read on public.x_profiles;
create policy profiles_read on public.x_profiles for select to authenticated using(user_id=auth.uid() or x_private.admin());
do $$declare t text; begin foreach t in array array['x_orders','x_wallet_entries','x_withdrawals','x_profile_requests','x_notifications','x_tickets','x_excel_uploads','x_import_keys','x_landing_pages','x_user_state','x_exchange_requests','x_employees'] loop
 execute format('drop policy if exists owner_read on public.%I',t);
 execute format('create policy owner_read on public.%I for select to authenticated using(merchant_id=auth.uid() or x_private.admin())',t);
end loop; end$$;
drop policy if exists state_write on public.x_user_state;
create policy state_write on public.x_user_state for all to authenticated using(merchant_id=x_private.member()) with check(merchant_id=x_private.member());
drop policy if exists excel_write on public.x_excel_uploads;
create policy excel_write on public.x_excel_uploads for all to authenticated using(merchant_id=x_private.member()) with check(merchant_id=x_private.member());
drop policy if exists notification_read on public.x_notifications;
create policy notification_read on public.x_notifications for update to authenticated using(merchant_id=auth.uid()) with check(merchant_id=auth.uid());
drop policy if exists messages_read on public.x_messages;
create policy messages_read on public.x_messages for select to authenticated using(exists(select 1 from public.x_tickets t where t.id=ticket_id and (t.merchant_id=auth.uid() or x_private.admin())));
drop policy if exists referrals_read on public.x_referrals;
create policy referrals_read on public.x_referrals for select to authenticated using(referrer_id=auth.uid() or referred_id=auth.uid() or x_private.admin());
drop policy if exists audit_admin on public.x_audit;
create policy audit_admin on public.x_audit for select to authenticated using(x_private.admin());
drop policy if exists recovery_admin on public.x_recovery_requests;
create policy recovery_admin on public.x_recovery_requests for select to authenticated using(x_private.admin());
create or replace function x_private.notify(p_user uuid,p_type text,p_text text,p_order text default null,p_ticket text default null) returns void language sql security definer set search_path='' as $$insert into public.x_notifications(merchant_id,type,text,order_id,ticket_id) values(p_user,p_type,p_text,p_order,p_ticket)$$;
create or replace function public.x_register_profile(p_data jsonb) returns void language plpgsql security definer set search_path='' as $$declare ph text; begin
 if auth.uid() is null then raise exception 'سجل الدخول'; end if;
 select case when email ~ '^07[0-9]{9}@gmail[.]com$' then split_part(email,'@',1) when ltrim(phone,'+') like '9647%' then '0'||substring(ltrim(phone,'+') from 4) end into ph from auth.users where id=auth.uid();
 if ph is null or ph !~ '^07[0-9]{9}$' then raise exception 'رقم الهاتف غير صحيح'; end if;
 if exists(select 1 from public.x_profiles where user_id=auth.uid()) then return; end if;
 if coalesce(p_data->>'name','')='' or coalesce(p_data->>'province','')='' or coalesce(p_data->>'area','')='' or coalesce(p_data->>'pageName','')='' then raise exception 'بيانات الحساب ناقصة'; end if;
 insert into public.x_profiles(user_id,phone,data) values(auth.uid(),ph,(p_data-'password'-'confirmPassword')||jsonb_build_object('phone',ph));
 insert into public.x_user_state(merchant_id) values(auth.uid());
 insert into public.x_audit(actor_id,action,entity_id) values(auth.uid(),'register',auth.uid()::text);
end$$;
create or replace function public.x_request_profile_change(p_id text,p_data jsonb) returns void language plpgsql security definer set search_path='' as $$declare u uuid:=x_private.member(); ph text; begin
 select phone into ph from public.x_profiles where user_id=u;
 if p_data->>'phone' is distinct from ph then raise exception 'تغيير رقم الدخول يحتاج إجراء خاص من الإدارة'; end if;
 insert into public.x_profile_requests(id,merchant_id,data) values(p_id,u,p_data-'password') on conflict(id) do nothing;
end$$;
-- Server derives costs, totals and delivery, never trusts client profit or status.
create or replace function x_private.price(p public.x_products) returns bigint language plpgsql stable set search_path='' as $$declare base bigint:= (p.data->>'baseCost')::bigint; discount bigint:= (p.data->>'discountPrice')::bigint; begin
 if discount is not null and discount>=0 and discount<base and (p.data->>'discountEndsAt')::timestamptz>now() and coalesce((p.data->>'discountStartsAt')::timestamptz,now())<=now() then return discount; end if;
 return base;
end$$;
create or replace function x_private.reserve(p_items jsonb,p_free boolean) returns jsonb language plpgsql security definer set search_path='' as $$declare item jsonb; p public.x_products; qty int; sale bigint; cost bigint; total_sale bigint:=0; total_cost bigint:=0; delivery bigint; minimum bigint; canonical jsonb:='[]'; begin
 if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 or jsonb_array_length(p_items)>100 then raise exception 'منتجات الطلب غير صحيحة'; end if;
 select coalesce((data->>'deliveryCost')::bigint,5000),coalesce((data->>'freeDeliveryMinimumProfit')::bigint,7000) into delivery,minimum from public.x_settings where id;
 -- deterministic locks avoid order-of-products deadlocks
 perform 1 from public.x_products where id in(select value->>'productId' from jsonb_array_elements(p_items)) order by id for update;
 for item in select value from jsonb_array_elements(p_items) loop
 select * into p from public.x_products where id=item->>'productId' and active;
 if not found then raise exception 'المنتج غير متوفر'; end if;
 qty:=(item->>'quantity')::integer; sale:=(item->>'sale')::bigint; cost:=x_private.price(p);
 if cost is null or cost<0 then raise exception 'سعر المنتج غير مضبوط؛ تواصل مع الإدارة'; end if;
 if qty is null or qty<1 or qty>1000 or qty>p.stock then raise exception 'الكمية غير متوفرة'; end if;
 if (p.data->>'minimumSale') is null or (p.data->>'minimumSale')::bigint<cost or sale is null or sale<(p.data->>'minimumSale')::bigint or sale>coalesce((p.data->>'sellingLimit')::bigint,cost+15000) then raise exception 'سعر البيع خارج الحدود'; end if;
 if jsonb_array_length(coalesce(p.data->'colors','[]')-'قياسي'-'')>0 and not (p.data->'colors' ? coalesce(item->>'color','')) then raise exception 'اللون غير متوفر'; end if;
 if jsonb_array_length(coalesce(p.data->'sizes','[]'))>0 and not (p.data->'sizes' ? coalesce(item->>'size','')) then raise exception 'القياس غير متوفر'; end if;
 update public.x_products set stock=stock-qty where id=p.id;
 canonical:=canonical||jsonb_build_array(jsonb_build_object('productId',p.id,'sale',sale,'quantity',qty,'color',coalesce(item->>'color',''),'size',coalesce(item->>'size',''),'note',left(coalesce(item->>'note',''),500),'unitCost',cost,'name',p.data->>'name','image',coalesce(p.data->>'image',''),'media',coalesce(p.data->'media','[]')));
 total_sale:=total_sale+sale*qty; total_cost:=total_cost+cost*qty;
 end loop;
 if p_free and total_sale-total_cost<minimum then raise exception 'الربح لا يسمح بالتوصيل المجاني'; end if;
 return jsonb_build_object('items',canonical,'sales',total_sale,'wholesale',total_cost,'grossProfit',total_sale-total_cost,'profit',total_sale-total_cost-case when p_free then delivery else 0 end,'delivery',case when p_free then 0 else delivery end,'merchantDeliveryCost',case when p_free then delivery else 0 end,'freeDelivery',p_free);
end$$;
create or replace function x_private.release_items(p_items jsonb) returns void language sql security definer set search_path='' as $$update public.x_products p set stock=stock+s.qty from(select value->>'productId' id,sum((value->>'quantity')::int)::int qty from jsonb_array_elements(p_items) group by 1) s where p.id=s.id$$;
create or replace function x_private.customer(p_customer jsonb) returns jsonb language plpgsql stable set search_path='' as $$begin
 if coalesce(p_customer->>'name','')='' or coalesce(p_customer->>'address','')='' or coalesce(p_customer->>'phone','') !~ '^07[0-9]{9}$' or not(coalesce(p_customer->>'province','')=any(array['بغداد','البصرة','نينوى','أربيل','النجف','كربلاء','بابل','الأنبار','ديالى','واسط','صلاح الدين','كركوك','السليمانية','دهوك','ذي قار','المثنى','ميسان','القادسية','حلبجة'])) then raise exception 'راجع بيانات الزبون'; end if;
 if coalesce(p_customer->>'phone2','')<>'' and p_customer->>'phone2' !~ '^07[0-9]{9}$' then raise exception 'رقم الهاتف الثاني غير صحيح'; end if;
 return jsonb_build_object('name',left(p_customer->>'name',100),'phone',p_customer->>'phone','phone2',coalesce(p_customer->>'phone2',''),'province',p_customer->>'province','address',left(p_customer->>'address',250),'note',left(coalesce(p_customer->>'note',''),2000),'companyNote',left(coalesce(p_customer->>'companyNote',''),2000));
end$$;
create or replace function x_private.create_order(p_merchant uuid,p_id text,p_customer jsonb,p_items jsonb,p_free boolean,p_page text default null) returns jsonb language plpgsql security definer set search_path='' as $$declare result jsonb; existing public.x_orders; begin
 if length(p_id)>200 or p_id='' then raise exception 'رقم طلب غير صحيح'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_merchant::text||p_id,0));
 select * into existing from public.x_orders where id=p_id;
 if found then if existing.merchant_id<>p_merchant then raise exception 'رقم الطلب مستخدم'; end if; return existing.payload; end if;
 if not exists(select 1 from public.x_profiles where user_id=p_merchant and not blocked) then raise exception 'الحساب محظور'; end if;
 result:=x_private.reserve(p_items,p_free)||jsonb_build_object('id',p_id,'customer',x_private.customer(p_customer),'status','معلق','date',now(),'history','[]'::jsonb,'landingPageId',p_page);
 insert into public.x_orders(id,merchant_id,payload) values(p_id,p_merchant,result);
 perform x_private.notify(p_merchant,'orders','تم تثبيت الطلب #'||p_id,p_id);
 insert into public.x_audit(actor_id,action,entity_id,data) values(auth.uid(),'create_order',p_id,jsonb_build_object('merchantId',p_merchant));
 return result;
end$$;
create or replace function public.x_checkout(p_id text,p_customer jsonb,p_items jsonb,p_free boolean) returns jsonb language plpgsql security definer set search_path='' as $$begin return x_private.create_order(x_private.member(),p_id,p_customer,p_items,p_free); end$$;
create or replace function public.x_edit_order(p_id text,p_customer jsonb,p_items jsonb,p_free boolean) returns jsonb language plpgsql security definer set search_path='' as $$declare u uuid:=x_private.member(); o public.x_orders; result jsonb; begin
 select * into o from public.x_orders where id=p_id and merchant_id=u for update;
 if not found or o.status<>'معلق' or o.cancellation_requested then raise exception 'التعديل متاح للمعلق فقط'; end if;
 perform x_private.release_items(o.payload->'items');
 result:=o.payload||x_private.reserve(p_items,p_free)||jsonb_build_object('customer',x_private.customer(p_customer));
 result:=result||jsonb_build_object('history',jsonb_build_array(jsonb_build_object('date',now(),'by',u,'changes',jsonb_build_array(jsonb_build_object('field','order','before',o.payload-'history','after',result-'history'))))||coalesce(o.payload->'history','[]'));
 update public.x_orders set payload=result,updated_at=now() where id=p_id;
 insert into public.x_audit(actor_id,action,entity_id) values(u,'edit_order',p_id);
 return result;
end$$;
create or replace function public.x_cancel_request(p_id text) returns void language plpgsql security definer set search_path='' as $$declare u uuid:=x_private.member(); begin
 update public.x_orders set cancellation_requested=true,payload=payload||'{"cancellationRequested":true}',updated_at=now() where id=p_id and merchant_id=u and status in ('معلق','قيد التجهيز');
 if not found then raise exception 'الإلغاء غير متاح'; end if;
 insert into public.x_audit(actor_id,action,entity_id) values(u,'request_cancellation',p_id);
end$$;
create or replace function public.x_admin_order_status(p_id text,p_status text) returns void language plpgsql security definer set search_path='' as $$declare o public.x_orders; r public.x_referrals; begin
 if not x_private.admin() then raise exception 'للإدارة فقط'; end if;
 if not(p_status=any(array['معلق','قيد التجهيز','قيد التوصيل','تم التوصيل','مرفوض','مؤجل','قيد الاستبدال'])) then raise exception 'حالة غير صحيحة'; end if;
 select * into o from public.x_orders where id=p_id for update;
 if not found then raise exception 'الطلب غير موجود'; end if;
 perform 1 from public.x_profiles where user_id=o.merchant_id for update;
 if o.status=p_status then return; end if;
 if o.status in ('تم التوصيل','مرفوض') then raise exception 'حالة نهائية؛ التصحيح يحتاج حركة حسابية منفصلة'; end if;
 if p_status='مرفوض' then perform x_private.release_items(o.payload->'items'); end if;
 update public.x_orders set status=p_status,updated_at=now(),payload=payload||jsonb_build_object('status',p_status,'history',jsonb_build_array(jsonb_build_object('date',now(),'by',auth.uid(),'changes',jsonb_build_array(jsonb_build_object('field','status','before',o.status,'after',p_status))))||coalesce(payload->'history','[]')) where id=p_id;
 if p_status='تم التوصيل' then
 insert into public.x_wallet_entries(merchant_id,amount,source,description) values(o.merchant_id,(o.payload->>'profit')::bigint,'order:'||p_id,'ربح الطلب #'||p_id) on conflict(source) do nothing;
 select * into r from public.x_referrals where referred_id=o.merchant_id for update;
 if found and not r.rewarded and (select count(*) from public.x_orders where merchant_id=o.merchant_id and status='تم التوصيل')>=3 then
 insert into public.x_wallet_entries(merchant_id,amount,source,description) values(r.referrer_id,1000,'referral:'||r.referred_id,'مكافأة الإحالة') on conflict(source) do nothing;
 update public.x_referrals set rewarded=true where referred_id=r.referred_id;
 end if;
 end if;
 perform x_private.notify(o.merchant_id,'orders','طلب #'||p_id||': '||p_status,p_id);
 insert into public.x_audit(actor_id,action,entity_id,data) values(auth.uid(),'order_status',p_id,jsonb_build_object('before',o.status,'after',p_status));
end$$;
create or replace function public.x_request_withdrawal(p_id text,p_amount bigint,p_method text,p_number text) returns void language plpgsql security definer set search_path='' as $$declare u uuid:=x_private.member(); available bigint; begin
 perform 1 from public.x_profiles where user_id=u for update;
 if exists(select 1 from public.x_withdrawals where id=p_id and merchant_id=u) then
 if not exists(select 1 from public.x_withdrawals where id=p_id and merchant_id=u and amount=p_amount and method=p_method and number=p_number) then raise exception 'طلب سابق بنفس العملية؛ حدّث الصفحة وراجع السحوبات'; end if;
 return; end if;
 select coalesce(sum(amount),0) into available from public.x_wallet_entries where merchant_id=u;
 available:=available-(select coalesce(sum(amount),0) from public.x_withdrawals where merchant_id=u and status='قيد الانتظار');
 if p_amount is null or p_amount<=0 or p_amount>available or p_method not in ('زين كاش','ماستر كارد الرافدين') or length(trim(p_number))<5 then raise exception 'راجع المبلغ أو وسيلة السحب'; end if;
 insert into public.x_withdrawals(id,merchant_id,amount,method,number) values(p_id,u,p_amount,p_method,p_number);
end$$;
create or replace function public.x_admin_withdrawal(p_id text,p_approve boolean,p_reason text default '',p_receipt text default null) returns void language plpgsql security definer set search_path='' as $$declare w public.x_withdrawals; begin
 if not x_private.admin() then raise exception 'للإدارة فقط'; end if;
 select * into w from public.x_withdrawals where id=p_id for update;
 if not found then raise exception 'العملية غير موجودة'; end if;
 perform 1 from public.x_profiles where user_id=w.merchant_id for update;
 if w.status<>'قيد الانتظار' then return; end if;
 if p_approve then insert into public.x_wallet_entries(merchant_id,amount,source,description) values(w.merchant_id,-w.amount,'withdrawal:'||w.id,'تسديد الأرباح') on conflict(source) do nothing; end if;
 update public.x_withdrawals set status=case when p_approve then 'تم التسديد' else 'مرفوض' end,reason=p_reason,receipt_path=p_receipt where id=p_id;
 perform x_private.notify(w.merchant_id,'orders',case when p_approve then 'تم تسديد أرباحك' else 'رفض طلب السحب: '||p_reason end);
 insert into public.x_audit(actor_id,action,entity_id,data) values(auth.uid(),'withdrawal_decision',p_id,jsonb_build_object('approved',p_approve));
end$$;
create or replace function public.x_open_ticket(p_id text,p_type text,p_order text default null) returns text language plpgsql security definer set search_path='' as $$declare u uuid:=x_private.member(); result text; begin
 if p_order is not null then
 if not exists(select 1 from public.x_orders where id=p_order and merchant_id=u) then raise exception 'الطلب غير موجود'; end if;
 insert into public.x_tickets(id,merchant_id,order_id,type) values(p_id,u,p_order,'دعم طلب') on conflict(order_id) where order_id is not null do nothing;
 select id into result from public.x_tickets where order_id=p_order;
 return result;
 end if;
 insert into public.x_tickets(id,merchant_id,type) values(p_id,u,left(p_type,100)) on conflict(id) do nothing;
 if not exists(select 1 from public.x_tickets where id=p_id and merchant_id=u) then raise exception 'التذكرة غير متاحة'; end if;
 return p_id;
end$$;
create or replace function public.x_save_message(p_id text,p_ticket text,p_text text,p_path text default null,p_filename text default null,p_delete boolean default false) returns void language plpgsql security definer set search_path='' as $$declare m public.x_messages; t public.x_tickets; u uuid:=auth.uid(); begin
 if u is null then raise exception 'سجل الدخول'; end if;
 select * into t from public.x_tickets where id=p_ticket;
 if not found or (t.merchant_id<>u and not x_private.admin()) then raise exception 'المحادثة غير متاحة'; end if;
 if not x_private.admin() then perform x_private.member(); end if;
 if p_path is not null and split_part(p_path,'/',1)<>u::text then raise exception 'المرفق غير متاح'; end if;
 select * into m from public.x_messages where id=p_id for update;
 if found then
 if m.sender_id<>u or m.ticket_id<>p_ticket then raise exception 'يمكن تعديل رسائلك فقط'; end if;
 update public.x_messages set text=left(p_text,10000),deleted=p_delete,edited_at=now() where id=p_id;
 else
 if p_delete then return; end if;
 insert into public.x_messages(id,ticket_id,sender_id,text,attachment_path,file_name) values(p_id,p_ticket,u,left(p_text,10000),p_path,p_filename);
 if u<>t.merchant_id then perform x_private.notify(t.merchant_id,'support','رسالة جديدة من الدعم',t.order_id,t.id); end if;
 end if;
end$$;
create or replace function public.x_import_excel(p_upload text,p_drafts jsonb) returns void language plpgsql security definer set search_path='' as $$declare u uuid:=x_private.member(); d jsonb; order_id text; result jsonb; begin
 perform 1 from public.x_excel_uploads where id=p_upload and merchant_id=u for update;
 if not found then raise exception 'الملف غير موجود'; end if;
 if jsonb_typeof(p_drafts)<>'array' or jsonb_array_length(p_drafts)>1000 then raise exception 'ارفع 1000 طلب كحد أقصى للعملية'; end if;
 for d in select value from jsonb_array_elements(p_drafts) loop
 if exists(select 1 from public.x_import_keys where merchant_id=u and upload_id=p_upload and key=d->>'key') then continue; end if;
 order_id:=gen_random_uuid()::text;
 result:=x_private.create_order(u,order_id,d->'customer',d->'items',coalesce((d->>'freeDelivery')::boolean,false));
 update public.x_orders set payload=payload||jsonb_build_object('importId',p_upload,'importKey',d->>'key') where id=order_id;
 insert into public.x_import_keys values(u,p_upload,d->>'key',order_id);
 end loop;
end$$;
create or replace function public.x_create_landing(p_id text,p_product text,p_sale bigint,p_free boolean) returns void language plpgsql security definer set search_path='' as $$declare u uuid:=x_private.member(); p public.x_products; cost bigint; min_profit bigint; begin
 select * into p from public.x_products where id=p_product and active; if not found then raise exception 'المنتج غير موجود'; end if;
 cost:=x_private.price(p); select coalesce((data->>'freeDeliveryMinimumProfit')::bigint,7000) into min_profit from public.x_settings where id;
 if (p.data->>'minimumSale') is null or (p.data->>'minimumSale')::bigint<cost or p_sale is null or p_sale<(p.data->>'minimumSale')::bigint or p_sale>coalesce((p.data->>'sellingLimit')::bigint,cost+15000) or (p_free and p_sale-cost<min_profit) then raise exception 'راجع سعر البيع'; end if;
 insert into public.x_landing_pages(id,merchant_id,product_id,sale,free_delivery) values(p_id,u,p_product,p_sale,p_free) on conflict(id) do nothing;
end$$;
create or replace function public.x_public_landing(p_id text) returns jsonb language plpgsql stable security definer set search_path='' as $$declare p public.x_landing_pages; prod public.x_products; begin
 select * into p from public.x_landing_pages where id=p_id and active; if not found then raise exception 'الصفحة غير متوفرة'; end if;
 select * into prod from public.x_products where id=p.product_id and active; if not found then raise exception 'المنتج غير متوفر'; end if;
 return jsonb_build_object('id',p.id,'product',prod.data||jsonb_build_object('id',prod.id,'stock',prod.stock),'sale',p.sale,'freeDelivery',p.free_delivery,'deliveryCost',(select data->'deliveryCost' from public.x_settings where id));
end$$;
create or replace function public.x_public_booking(p_page text,p_key text,p_customer jsonb,p_quantity integer,p_color text,p_size text) returns text language plpgsql security definer set search_path='' as $$declare p public.x_landing_pages; existing text; oid text; result jsonb; begin
 select * into p from public.x_landing_pages where id=p_page and active; if not found then raise exception 'الصفحة غير متوفرة'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_page||p_key,0));
 if p_key !~ '^[a-f0-9-]{36}$' then raise exception 'مرجع حجز غير صحيح'; end if;
 oid:='landing:'||p_page||':'||p_key;
 if exists(select 1 from public.x_orders where id=oid) then return 'تم استلام الحجز'; end if;
 if exists(select 1 from public.x_orders where payload->>'landingPageId'=p_page and payload->'customer'->>'phone'=p_customer->>'phone' and created_at>now()-interval '1 minute') then raise exception 'انتظر دقيقة قبل حجز جديد'; end if;
 result:=x_private.create_order(p.merchant_id,oid,p_customer,jsonb_build_array(jsonb_build_object('productId',p.product_id,'sale',p.sale,'quantity',p_quantity,'color',p_color,'size',p_size,'note','')),p.free_delivery,p_page);
 return 'تم استلام الحجز';
end$$;
create or replace function public.x_visit_landing(p_page text,p_visitor text) returns void language plpgsql security definer set search_path='' as $$begin
 if p_visitor !~ '^[a-f0-9-]{36}$' then return; end if;
 if exists(select 1 from public.x_landing_pages where id=p_page and active and merchant_id is distinct from auth.uid()) then insert into public.x_landing_visits(page_id,visitor_id) values(p_page,p_visitor) on conflict do nothing; end if;
end$$;
create or replace function public.x_landing_counts() returns jsonb language sql stable security definer set search_path='' as $$select coalesce(jsonb_object_agg(id,n),'{}') from(select p.id,count(v.*) n from public.x_landing_pages p left join public.x_landing_visits v on v.page_id=p.id where p.merchant_id=auth.uid() group by p.id) s$$;
create or replace function public.x_recovery_request(p_phone text,p_details text) returns void language plpgsql security definer set search_path='' as $$begin
 if p_phone !~ '^07[0-9]{9}$' or length(trim(p_details))<10 then raise exception 'أدخل رقمك وتفاصيل إثبات الحساب'; end if;
 if exists(select 1 from public.x_recovery_requests where phone=p_phone and created_at>now()-interval '24 hours') then return; end if;
 insert into public.x_recovery_requests(phone,details) values(p_phone,left(p_details,2000));
end$$;
create or replace function public.x_request_exchange(p_id text,p_order text,p_data jsonb) returns void language plpgsql security definer set search_path='' as $$declare u uuid:=x_private.member(); begin
 if not exists(select 1 from public.x_orders where id=p_order and merchant_id=u and status='تم التوصيل') then raise exception 'الاستبدال متاح للطلبات المسلمة'; end if;
 if coalesce(p_data->>'reason','')='' then raise exception 'اكتب السبب'; end if;
 insert into public.x_exchange_requests(id,merchant_id,order_id,data) values(p_id,u,p_order,p_data) on conflict(id) do nothing;
end$$;
create or replace function public.x_register_referral(p_code text) returns void language plpgsql security definer set search_path='' as $$declare u uuid:=x_private.member(); r uuid; begin
 select user_id into r from public.x_profiles where user_id::text=p_code and not blocked;
 if r is null or r=u then raise exception 'رمز إحالة غير صحيح'; end if;
 if exists(select 1 from public.x_orders where merchant_id=u) then raise exception 'أدخل الإحالة قبل أول طلب'; end if;
 insert into public.x_referrals(referred_id,referrer_id) values(u,r) on conflict(referred_id) do nothing;
end$$;
create or replace function public.x_admin_profile(p_user uuid,p_data jsonb,p_blocked boolean default false) returns void language plpgsql security definer set search_path='' as $$declare ph text; begin
 if not x_private.admin() then raise exception 'للإدارة فقط'; end if;
 select phone into ph from public.x_profiles where user_id=p_user for update;
 update public.x_profiles set data=(p_data-'password')||jsonb_build_object('phone',ph),blocked=p_blocked where user_id=p_user;
 insert into public.x_audit(actor_id,action,entity_id,data) values(auth.uid(),'profile_update',p_user::text,jsonb_build_object('blocked',p_blocked));
end$$;
create or replace function public.x_admin_profile_decision(p_id text,p_approve boolean) returns void language plpgsql security definer set search_path='' as $$declare r public.x_profile_requests; begin
 if not x_private.admin() then raise exception 'للإدارة فقط'; end if;
 select * into r from public.x_profile_requests where id=p_id for update;
 if not found or r.status<>'pending' then return; end if;
 if p_approve then update public.x_profiles set data=r.data where user_id=r.merchant_id; end if;
 update public.x_profile_requests set status=case when p_approve then 'approved' else 'rejected' end where id=p_id;
 perform x_private.notify(r.merchant_id,'orders',case when p_approve then 'تم تحديث بيانات حسابك' else 'تم رفض تعديل البيانات' end);
end$$;
create or replace function public.x_request_account_deletion() returns void language plpgsql security definer set search_path='' as $$declare u uuid:=x_private.member(); begin
 perform public.x_open_ticket('delete:'||u::text,'طلب حذف الحساب',null);
 perform public.x_save_message('delete-request:'||u::text,'delete:'||u::text,'أطلب حذف حسابي وبياناتي بعد تسوية الحسابات');
end$$;
create or replace function public.x_admin_cancellation(p_id text,p_accept boolean) returns void language plpgsql security definer set search_path='' as $$declare o public.x_orders; begin
 if not x_private.admin() then raise exception 'للإدارة فقط'; end if;
 select * into o from public.x_orders where id=p_id for update;
 if not found or not o.cancellation_requested then return; end if;
 if p_accept then
 if o.status not in ('معلق','قيد التجهيز') then raise exception 'لا يمكن قبول الإلغاء بهذه المرحلة'; end if;
 perform public.x_admin_order_status(p_id,'مرفوض');
 end if;
 update public.x_orders set cancellation_requested=false,payload=payload||jsonb_build_object('cancellationRequested',false),updated_at=now() where id=p_id;
 perform x_private.notify(o.merchant_id,'orders',case when p_accept then 'تم قبول إلغاء الطلب' else 'لم توافق الإدارة على إلغاء الطلب' end,p_id);
 insert into public.x_audit(actor_id,action,entity_id,data) values(auth.uid(),'cancellation_decision',p_id,jsonb_build_object('approved',p_accept));
end$$;
create or replace function public.x_admin_exchange(p_id text,p_status text,p_reason text default '') returns void language plpgsql security definer set search_path='' as $$declare r public.x_exchange_requests; begin
 if not x_private.admin() then raise exception 'للإدارة فقط'; end if;
 if p_status not in ('قيد الاستبدال','تم الاستبدال','مرفوض') then raise exception 'حالة غير صحيحة'; end if;
 select * into r from public.x_exchange_requests where id=p_id for update;
 if not found then raise exception 'الطلب غير موجود'; end if;
 if r.status in ('تم الاستبدال','مرفوض') then return; end if;
 update public.x_exchange_requests set status=p_status,data=data||jsonb_build_object('adminReason',left(p_reason,2000)) where id=p_id;
 perform x_private.notify(r.merchant_id,'orders','طلب الاستبدال: '||p_status,r.order_id);
 insert into public.x_audit(actor_id,action,entity_id,data) values(auth.uid(),'exchange_decision',p_id,jsonb_build_object('status',p_status,'reason',p_reason));
end$$;
-- Employees accept invitations; financial data remains owner/admin only.
create or replace function x_private.staff(p_owner uuid,p_action text) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.x_employees where merchant_id=p_owner and employee_user_id=auth.uid() and active and coalesce((data->>p_action)::boolean,false))$$;
grant execute on function x_private.staff(uuid,text) to authenticated;
drop policy if exists owner_read on public.x_orders;
create policy owner_read on public.x_orders for select to authenticated using(merchant_id=auth.uid() or x_private.admin() or x_private.staff(merchant_id,'readOrders'));
drop policy if exists employee_invites on public.x_employees;
create policy employee_invites on public.x_employees for select to authenticated using(employee_user_id=auth.uid());
create or replace function public.x_employee_invite(p_phone text) returns void language plpgsql security definer set search_path='' as $$declare u uuid:=x_private.member(); target uuid; begin
 select user_id into target from public.x_profiles where phone=p_phone and not blocked;
 if target is null or target=u then raise exception 'الموظف يحتاج حساب مستقل برقم صحيح'; end if;
 insert into public.x_employees(merchant_id,employee_user_id,data,active) values(u,target,jsonb_build_object('name',(select data->>'name' from public.x_profiles where user_id=target),'store',(select data->>'pageName' from public.x_profiles where user_id=u),'pending',true,'readOrders',true,'createOrders',true),false) on conflict(merchant_id,employee_user_id) do nothing;
 perform x_private.notify(target,'orders','لديك دعوة للعمل مع تاجر؛ افتح إدارة الموظفين');
end$$;
create or replace function public.x_employee_decision(p_id uuid,p_accept boolean) returns void language plpgsql security definer set search_path='' as $$declare u uuid:=x_private.member(); begin
 update public.x_employees set active=p_accept,data=data||jsonb_build_object('pending',false) where id=p_id and employee_user_id=u and coalesce((data->>'pending')::boolean,false);
end$$;
create or replace function public.x_employee_disable(p_id uuid) returns void language plpgsql security definer set search_path='' as $$declare u uuid:=x_private.member(); begin
 update public.x_employees set active=false,data=data||jsonb_build_object('pending',false) where id=p_id and merchant_id=u;
end$$;
create or replace function public.x_employee_checkout(p_id text,p_owner uuid,p_customer jsonb,p_items jsonb,p_free boolean) returns jsonb language plpgsql security definer set search_path='' as $$begin
 perform x_private.member();
 if not x_private.staff(p_owner,'createOrders') then raise exception 'لا تملك صلاحية تثبيت طلبات لهذا التاجر'; end if;
 return x_private.create_order(p_owner,p_id,p_customer,p_items,p_free);
end$$;
-- RPCs default to PUBLIC execute in PostgreSQL: revoke before granting explicit scope.
do $$declare r record; begin
 for r in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'x_%' loop
 execute format('revoke all on function %s from public,anon,authenticated',r.signature);
 execute format('grant execute on function %s to authenticated',r.signature);
 end loop;
 for r in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='x_private' loop execute format('revoke all on function %s from public,anon,authenticated',r.signature); end loop;
end$$;
grant execute on function x_private.admin() to anon,authenticated;
grant execute on function x_private.member(),x_private.staff(uuid,text) to authenticated;
grant execute on function public.x_public_landing(text),public.x_public_booking(text,text,jsonb,integer,text,text),public.x_visit_landing(text,text),public.x_recovery_request(text,text) to anon;
-- Attachments private; product media public. Private folder names are auth user IDs.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('x-space-media','x-space-media',true,10485760,array['image/jpeg','image/png','image/webp','video/mp4']),('x-space-private','x-space-private',false,2097152,array['image/jpeg','image/png','application/pdf']) on conflict(id) do nothing;
drop policy if exists x_media_public on storage.objects;
create policy x_media_public on storage.objects for select using(bucket_id='x-space-media');
drop policy if exists x_media_admin on storage.objects;
create policy x_media_admin on storage.objects for all to authenticated using(bucket_id='x-space-media' and x_private.admin()) with check(bucket_id='x-space-media' and x_private.admin());
drop policy if exists x_attachment_insert on storage.objects;
create policy x_attachment_insert on storage.objects for insert to authenticated with check(bucket_id='x-space-private' and (storage.foldername(name))[1]=auth.uid()::text and (x_private.member() is not null or x_private.admin()));
drop policy if exists x_attachment_read on storage.objects;
create policy x_attachment_read on storage.objects for select to authenticated using(bucket_id='x-space-private' and ((storage.foldername(name))[1]=auth.uid()::text or x_private.admin() or exists(select 1 from public.x_messages m join public.x_tickets t on t.id=m.ticket_id where m.attachment_path=name and t.merchant_id=auth.uid())));
-- Realtime uses RLS; no other merchant's rows are readable.
do $$declare t text; begin foreach t in array array['x_profiles','x_products','x_banners','x_settings','x_orders','x_wallet_entries','x_withdrawals','x_profile_requests','x_notifications','x_tickets','x_messages','x_exchange_requests','x_employees'] loop
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then execute format('alter publication supabase_realtime add table public.%I',t); end if;
end loop; end$$;
commit;
