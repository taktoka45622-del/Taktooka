alter table public.x_products add column if not exists product_number integer generated always as identity (start with 100000 maxvalue 999999 no cycle);
create unique index if not exists x_products_number_unique on public.x_products(product_number);
do $$begin if not exists(select 1 from pg_constraint where conname='x_products_number_six_digits' and conrelid='public.x_products'::regclass) then
 alter table public.x_products add constraint x_products_number_six_digits check(product_number between 100000 and 999999);
end if;end$$;
update public.x_settings set data=jsonb_set(data,'{landingBaseUrl}',to_jsonb('https://x-spece.github.io/x-space-dashboard/landing/'::text),true) where id=true;
