set check_function_bodies=off;
create role anon;create role authenticated;create role service_role;create schema auth;create schema tkt_private;create schema storage;create schema extensions;create schema vault;create table auth.users(id uuid primary key,email text,phone text);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create table public.tkt_saved_places("created_at" timestamp with time zone default now(),"id" uuid,"user_id" uuid,"lat" double precision,"lng" double precision,"label" text);
create table tkt_private.booking_prices("confirmed_at" timestamp with time zone,"total" integer,"quote_id" uuid);
create table public.tkt_messages("id" uuid,"user_id" uuid,"sender_id" uuid,"is_admin" boolean,"created_at" timestamp with time zone default now(),"body" text);
create table public.tkt_offers("ride_id" uuid,"captain_id" uuid,"attempt" integer,"eta_s" integer,"created_at" timestamp with time zone default now(),"expires_at" timestamp with time zone,"id" uuid,"status" text);
create table tkt_private.admin_login("id" boolean,"secret_id" uuid,"user_id" uuid,"failures" integer,"locked_until" timestamp with time zone,"last_login" timestamp with time zone,"phone" text,"pin_hash" text,"email" text);
create table tkt_private.dispatch_settings("id" boolean,"max_eta_s" integer,"search_s" integer,"stale_s" integer,"offer_s" integer,"h3_resolution" integer,"zones" jsonb,"lease_id" uuid,"lease_until" timestamp with time zone,"last_worker_at" timestamp with time zone,"last_matrix_at" timestamp with time zone,"mapbox_token" text,"last_error" text);
create table public.tkt_captain_applications("user_id" uuid primary key,"documents" jsonb,"revision" integer,"reviewed_by" uuid,"submitted_at" timestamp with time zone,"reviewed_at" timestamp with time zone,"updated_at" timestamp with time zone,"verification" jsonb,"full_name" text,"phone" text,"chassis" text,"color" text,"model" text,"pending_slot" text,"status" text,"reason" text,"province" text,"area" text);
create table tkt_private.account_deletions("user_id" uuid,"files" jsonb,"requested_at" timestamp with time zone,"completed_at" timestamp with time zone,"status" text);
create table tkt_private.pricing_settings("id" boolean,"tiers" jsonb,"night_amount" integer,"night_min_m" integer,"night_start" integer,"night_end" integer,"overflow_step_m" integer,"overflow_amount" integer,"max_fare" integer,"revision" integer,"updated_at" timestamp with time zone,"updated_by" uuid);
create table public.tkt_notifications("id" uuid,"user_id" uuid,"target" jsonb,"created_at" timestamp with time zone default now(),"read_at" timestamp with time zone,"expires_at" timestamp with time zone,"event_key" text,"kind" text,"title" text,"body" text);
create table tkt_private.push_devices("user_id" uuid,"updated_at" timestamp with time zone,"token" text,"platform" text);
create table tkt_private.push_outbox("notification_id" uuid,"attempts" integer,"next_at" timestamp with time zone,"locked_at" timestamp with time zone,"delivered_at" timestamp with time zone,"status" text,"error" text);
create table public.tkt_home_banners("id" uuid,"slot" smallint,"sort_order" integer,"enabled" boolean,"created_at" timestamp with time zone default now(),"image_path" text,"title" text);
create table tkt_private.wallets("user_id" uuid primary key,"balance" integer);
create table tkt_private.ledger("id" uuid,"user_id" uuid,"amount" integer,"ride_id" uuid,"actor_id" uuid,"created_at" timestamp with time zone default now(),"kind" text);
create table tkt_private.coupons("amount" integer,"expires_at" timestamp with time zone,"active" boolean,"max_uses" integer,"code" text);
create table tkt_private.coupon_uses("ride_id" uuid,"user_id" uuid,"code" text);
create table tkt_private.preferences("user_id" uuid primary key,"user_read" timestamp with time zone,"admin_read" timestamp with time zone,"captain_requested_at" timestamp with time zone,"coupon" text);
create table tkt_private.addresses("id" uuid,"user_id" uuid,"lat" double precision,"lng" double precision,"created_at" timestamp with time zone default now(),"label" text);
create table tkt_private.coupon_history("user_id" uuid,"selected_at" timestamp with time zone,"code" text);
create table tkt_private.phone_attempts("failures" integer,"window_at" timestamp with time zone,"requests" integer,"phone" text);
create table tkt_private.ride_codes("ride_id" uuid,"code" text);
create table tkt_private.wheel_prizes("remaining" integer,"enabled" boolean,"revision" bigint,"key" text,"title" text);
create table tkt_private.wheel_settings("id" boolean,"enabled" boolean);
create table tkt_private.wheel_spins("id" uuid,"user_id" uuid,"created_at" timestamp with time zone default now(),"delivered_at" timestamp with time zone,"delivered_by" uuid,"prize_key" text,"prize_title" text,"status" text);
create table public.tkt_recovery_threads("id" uuid,"created_at" timestamp with time zone default now(),"phone" text,"name" text,"token_hash" text);
create table public.tkt_recovery_messages("id" uuid,"thread_id" uuid,"is_admin" boolean,"created_at" timestamp with time zone default now(),"body" text);
create table tkt_private.dispatch_eta_cache("ride_id" uuid,"captain_id" uuid,"lat" double precision,"lng" double precision,"eta_s" integer,"computed_at" timestamp with time zone);
create table public.tkt_quotes("id" uuid,"user_id" uuid,"pickup" jsonb,"destination" jsonb,"geometry" jsonb,"distance_m" integer,"duration_s" integer,"fare" integer,"created_at" timestamp with time zone default now(),"expires_at" timestamp with time zone,"route_distance_m" numeric,"base_fare" integer,"night_surcharge" integer,"priced_at" timestamp with time zone,"change_ride_id" uuid,"change_revision" integer,"pricing_version" text,"route_provider" text);
create table public.tkt_profiles("user_id" uuid primary key,"captain" boolean default false,"blocked" boolean default false,"expires_at" timestamp with time zone,"online" boolean default false,"lat" double precision,"lng" double precision,"location_at" timestamp with time zone,"created_at" timestamp with time zone default now(),"privacy_accepted_at" timestamp with time zone,"name" text,"phone" text,"avatar_path" text,"privacy_version" text,"gender" text);
create table public.tkt_admins("user_id" uuid primary key);
create table public.tkt_payments("id" uuid,"captain_id" uuid,"admin_id" uuid,"amount" integer,"created_at" timestamp with time zone default now(),"expires_at" timestamp with time zone);
create table public.tkt_rides("id" uuid,"quote_id" uuid,"rider_id" uuid,"captain_id" uuid,"pickup" jsonb,"destination" jsonb,"geometry" jsonb,"fare" integer,"distance_m" integer,"duration_s" integer,"created_at" timestamp with time zone default now(),"updated_at" timestamp with time zone,"search_deadline" timestamp with time zone,"captain_eta_s" integer,"eta_at" timestamp with time zone,"route_distance_m" numeric,"base_fare" integer,"night_surcharge" integer,"priced_at" timestamp with time zone,"destination_revision" integer,"last_change_quote_id" uuid,"discount" integer,"customer_due" integer,"pickup_name" text,"destination_name" text,"dispatch_state" text,"pricing_version" text,"route_provider" text,"payment_method" text,"coupon_code" text,"status" text);
create table tkt_private.admin_audit("id" uuid,"actor_id" uuid,"details" jsonb,"created_at" timestamp with time zone default now(),"action" text,"entity_id" text);
create table tkt_private.admin_archives("actor_id" uuid,"created_at" timestamp with time zone default now(),"kind" text,"entity_id" text);
create table tkt_private.dispatch_locations("captain_id" uuid,"lat" double precision,"lng" double precision,"gps_at" timestamp with time zone,"received_at" timestamp with time zone,"cell" text,"zone" text);
create table tkt_private.dispatch_jobs("ride_id" uuid,"started_at" timestamp with time zone,"deadline" timestamp with time zone,"attempt" integer,"cell" text,"zone" text,"state" text);
create table storage.objects(id uuid,name text,bucket_id text);
CREATE OR REPLACE FUNCTION tkt_private.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$select auth.uid() is not null and exists(select 1 from public.tkt_admins where user_id=auth.uid())$function$;

CREATE OR REPLACE FUNCTION tkt_private.normalize_phone(value text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
select case when d ~ '^07[0-9]{9}$' then '+964'||substr(d,2) when d ~ '^009647[0-9]{9}$' then '+'||substr(d,3) when d ~ '^9647[0-9]{9}$' then '+'||d else null end from (select regexp_replace(translate(value,'٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹','01234567890123456789'),'[^0-9]','','g') d)x $function$;


CREATE OR REPLACE FUNCTION public.tkt_pricing(p_action text DEFAULT 'get'::text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select tkt_private.pricing_admin(p_action,p_data)$function$;


CREATE OR REPLACE FUNCTION public.tkt_wheel(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select tkt_private.wheel(p_action,p_data)$function$;


CREATE OR REPLACE FUNCTION public.tkt_captain_registration(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select tkt_private.captain_registration(p_action,p_data)$function$;

create function public.tkt_manage(p_action text,p_data jsonb default '{}')returns jsonb language sql as $$select tkt_private.manage(p_action,p_data)$$;
