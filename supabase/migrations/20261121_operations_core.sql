-- Vijayasri Footwear Operations: additive production core schema.
-- Apply to the DEDICATED Operations Supabase project only.
-- Do not run against the existing public catalogue Supabase project.

create extension if not exists pgcrypto;

create table if not exists public.staff_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  role text not null check (role in ('owner','admin','manager','cashier','inventory','purchasing')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.ops_has_role(allowed_roles text[] default array['owner','admin','manager'])
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.staff_profiles s
    where s.user_id = auth.uid() and s.active = true and s.role = any(allowed_roles)
  );
$$;
revoke all on function public.ops_has_role(text[]) from public;
grant execute on function public.ops_has_role(text[]) to authenticated;

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  brand text not null,
  model_code text not null,
  name text not null,
  audience text not null check (audience in ('Men','Women','Kids','Unisex')),
  footwear_type text not null,
  description text,
  published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (brand, model_code)
);

create table if not exists public.product_colours (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  colour_name text not null,
  colour_hex text check (colour_hex is null or colour_hex ~ '^#[0-9A-Fa-f]{6}
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  colour_id uuid not null references public.product_colours(id) on delete restrict,
  sku text not null unique,
  colour_name text not null,
  colour_hex text check (colour_hex is null or colour_hex ~ '^#[0-9A-Fa-f]{6}$'),
  size text not null,
  mrp numeric(12,2) not null default 0 check (mrp >= 0),
  selling_price numeric(12,2) not null default 0 check (selling_price >= 0),
  cost_price numeric(12,2) not null default 0 check (cost_price >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (product_id, colour_name, size),
  unique (colour_id, size)
);
create index if not exists product_variants_product_idx on public.product_variants(product_id, active);
create index if not exists product_variants_colour_idx on public.product_variants(product_id, colour_name);

create table if not exists public.product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid references public.products(id) on delete cascade,
  colour_id uuid references public.product_colours(id) on delete cascade,
  variant_id uuid references public.product_variants(id) on delete cascade,
  image_url text not null,
  storage_path text,
  source_type text not null check (source_type in ('upload','url')),
  alt_text text,
  sort_order integer not null default 0,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  check (((product_id is not null)::integer + (colour_id is not null)::integer + (variant_id is not null)::integer) = 1)
);
create index if not exists product_images_product_order_idx on public.product_images(product_id, sort_order);
create index if not exists product_images_colour_order_idx on public.product_images(colour_id, sort_order);
create index if not exists product_images_variant_order_idx on public.product_images(variant_id, sort_order);
create unique index if not exists product_images_one_primary_model
  on public.product_images(product_id) where product_id is not null and is_primary;
create unique index if not exists product_images_one_primary_colour
  on public.product_images(colour_id) where colour_id is not null and is_primary;
create unique index if not exists product_images_one_primary_variant
  on public.product_images(variant_id) where variant_id is not null and is_primary;

create table if not exists public.inventory_balances (
  variant_id uuid primary key references public.product_variants(id) on delete restrict,
  on_hand integer not null default 0 check (on_hand >= 0),
  reserved integer not null default 0 check (reserved >= 0),
  damaged integer not null default 0 check (damaged >= 0),
  available integer generated always as (on_hand - reserved - damaged) stored,
  updated_at timestamptz not null default now(),
  check (reserved + damaged <= on_hand)
);

create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  variant_id uuid not null references public.product_variants(id) on delete restrict,
  quantity_delta integer not null check (quantity_delta <> 0),
  movement_type text not null check (movement_type in ('opening','purchase_receipt','sale','sale_return','purchase_return','adjustment','transfer_in','transfer_out','write_off')),
  reason text,
  source_type text,
  source_id uuid,
  idempotency_key text unique,
  actor_id uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists stock_movements_variant_date_idx on public.stock_movements(variant_id, created_at desc);

create or replace function public.ops_apply_stock_movement()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.inventory_balances(variant_id, on_hand, reserved, damaged)
  values (new.variant_id, 0, 0, 0) on conflict (variant_id) do nothing;

  update public.inventory_balances
  set on_hand = on_hand + new.quantity_delta, updated_at = now()
  where variant_id = new.variant_id
    and (new.quantity_delta >= 0 or available + new.quantity_delta >= 0);

  if not found then
    raise exception 'Insufficient available inventory for variant %', new.variant_id using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_ops_apply_stock_movement on public.stock_movements;
create trigger trg_ops_apply_stock_movement
after insert on public.stock_movements
for each row execute function public.ops_apply_stock_movement();

create table if not exists public.inventory_reservations (
  id uuid primary key default gen_random_uuid(),
  variant_id uuid not null references public.product_variants(id) on delete restrict,
  quantity integer not null check (quantity > 0),
  reference text not null,
  status text not null default 'reserved' check (status in ('reserved','consumed','released','expired')),
  idempotency_key text not null unique,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.ops_reserve_stock(
  p_variant_id uuid, p_quantity integer, p_reference text, p_idempotency_key text, p_expires_at timestamptz default null
) returns uuid language plpgsql security definer set search_path = public
as $$
declare v_id uuid;
begin
  if auth.uid() is null or not public.ops_has_role(array['owner','admin','manager','cashier']) then
    raise exception 'Not authorised' using errcode = '42501';
  end if;
  if p_quantity <= 0 or length(trim(p_idempotency_key)) = 0 then
    raise exception 'Quantity and idempotency key are required';
  end if;
  select id into v_id from public.inventory_reservations where idempotency_key = p_idempotency_key;
  if v_id is not null then return v_id; end if;

  update public.inventory_balances
  set reserved = reserved + p_quantity, updated_at = now()
  where variant_id = p_variant_id and available >= p_quantity;
  if not found then raise exception 'Insufficient available stock' using errcode = '23514'; end if;

  insert into public.inventory_reservations(variant_id,quantity,reference,idempotency_key,expires_at)
  values (p_variant_id,p_quantity,p_reference,p_idempotency_key,p_expires_at)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.ops_release_reservation(p_reservation_id uuid, p_terminal_status text default 'released')
returns boolean language plpgsql security definer set search_path = public
as $$
declare r public.inventory_reservations%rowtype;
begin
  if auth.uid() is null or not public.ops_has_role(array['owner','admin','manager','cashier']) then
    raise exception 'Not authorised' using errcode = '42501';
  end if;
  select * into r from public.inventory_reservations where id = p_reservation_id for update;
  if not found then return false; end if;
  if r.status <> 'reserved' then return true; end if;
  if p_terminal_status not in ('released','expired') then raise exception 'Invalid terminal status'; end if;
  update public.inventory_balances set reserved = reserved - r.quantity, updated_at = now()
    where variant_id = r.variant_id and reserved >= r.quantity;
  update public.inventory_reservations set status = p_terminal_status, updated_at = now() where id = r.id;
  return true;
end;
$$;

create or replace function public.ops_consume_reservation(p_reservation_id uuid, p_idempotency_key text)
returns boolean language plpgsql security definer set search_path = public
as $$
declare r public.inventory_reservations%rowtype;
begin
  if auth.uid() is null or not public.ops_has_role(array['owner','admin','manager','cashier']) then
    raise exception 'Not authorised' using errcode = '42501';
  end if;
  select * into r from public.inventory_reservations where id = p_reservation_id for update;
  if not found then raise exception 'Reservation not found'; end if;
  if r.status = 'consumed' then return true; end if;
  if r.status <> 'reserved' then raise exception 'Reservation is not active'; end if;

  update public.inventory_balances set reserved = reserved - r.quantity, updated_at = now()
    where variant_id = r.variant_id and reserved >= r.quantity;
  insert into public.stock_movements(variant_id,quantity_delta,movement_type,reason,source_type,source_id,idempotency_key,actor_id)
  values (r.variant_id,-r.quantity,'sale','Reserved stock consumed','reservation',r.id,p_idempotency_key,auth.uid());
  update public.inventory_reservations set status = 'consumed', updated_at = now() where id = r.id;
  return true;
end;
$$;

create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  contact_name text,
  phone text,
  email text,
  gstin text,
  opening_balance numeric(12,2) not null default 0,
  created_at timestamptz not null default now()
);
create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  email text,
  notes text,
  created_at timestamptz not null default now()
);
create table if not exists public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid references public.suppliers(id),
  invoice_number text,
  invoice_storage_path text,
  status text not null default 'ordered' check (status in ('draft','ordered','partially_received','received','cancelled')),
  order_date date not null default current_date,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create table if not exists public.purchase_order_items (
  id uuid primary key default gen_random_uuid(),
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id),
  ordered_qty integer not null check (ordered_qty > 0),
  received_qty integer not null default 0 check (received_qty >= 0 and received_qty <= ordered_qty),
  unit_cost numeric(12,2) not null check (unit_cost >= 0),
  tax_rate numeric(6,3) not null default 0 check (tax_rate >= 0),
  created_at timestamptz not null default now()
);
create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  receipt_number text unique,
  customer_id uuid references public.customers(id),
  bill_type text not null check (bill_type in ('gst','non_gst')),
  payment_status text not null default 'pending' check (payment_status in ('pending','paid','partial','refunded')),
  payment_method text,
  subtotal numeric(12,2) not null default 0,
  discount_total numeric(12,2) not null default 0,
  tax_total numeric(12,2) not null default 0,
  grand_total numeric(12,2) not null default 0,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create table if not exists public.sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id),
  sku_snapshot text not null,
  product_snapshot text not null,
  quantity integer not null check (quantity > 0),
  unit_cost_snapshot numeric(12,2) not null,
  unit_price numeric(12,2) not null,
  discount_amount numeric(12,2) not null default 0,
  tax_rate numeric(6,3) not null default 0,
  tax_amount numeric(12,2) not null default 0,
  line_total numeric(12,2) not null
);
create table if not exists public.integration_outbox (
  id uuid primary key default gen_random_uuid(),
  destination text not null,
  event_type text not null,
  aggregate_type text not null,
  aggregate_id uuid not null,
  payload jsonb not null,
  status text not null default 'pending' check (status in ('pending','processing','sent','failed')),
  attempts integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique(destination,event_type,aggregate_type,aggregate_id)
);

-- Private invoice/document bucket; public product images bucket for catalogue delivery.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('vjs-product-images','vjs-product-images',true,15728640,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=true,file_size_limit=15728640,allowed_mime_types=array['image/jpeg','image/png','image/webp'];
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('vjs-private-documents','vjs-private-documents',false,20971520,array['application/pdf','image/jpeg','image/png'])
on conflict(id) do update set public=false,file_size_limit=20971520,allowed_mime_types=array['application/pdf','image/jpeg','image/png'];

alter table public.staff_profiles enable row level security;
alter table public.products enable row level security;
alter table public.product_colours enable row level security;
alter table public.product_variants enable row level security;
alter table public.product_images enable row level security;
alter table public.inventory_balances enable row level security;
alter table public.stock_movements enable row level security;
alter table public.inventory_reservations enable row level security;
alter table public.suppliers enable row level security;
alter table public.customers enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_items enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.integration_outbox enable row level security;

-- Staff may read their own profile; owner/admin manage staff. All operational data requires an active role.
drop policy if exists "staff read own profile" on public.staff_profiles;
create policy "staff read own profile" on public.staff_profiles for select to authenticated using (user_id=auth.uid() or public.ops_has_role(array['owner','admin']));
drop policy if exists "admins manage staff profiles" on public.staff_profiles;
create policy "admins manage staff profiles" on public.staff_profiles for all to authenticated using (public.ops_has_role(array['owner','admin'])) with check (public.ops_has_role(array['owner','admin']));

do $$
declare t text;
begin
  foreach t in array array['products','product_colours','product_variants','product_images','inventory_balances','stock_movements','inventory_reservations','suppliers','customers','purchase_orders','purchase_order_items','sales','sale_items','integration_outbox'] loop
    execute format('drop policy if exists "active staff access" on public.%I', t);
    execute format('create policy "active staff access" on public.%I for all to authenticated using (public.ops_has_role(array[''owner'',''admin'',''manager'',''cashier'',''inventory'',''purchasing''])) with check (public.ops_has_role(array[''owner'',''admin'',''manager'',''cashier'',''inventory'',''purchasing'']))', t);
  end loop;
end $$;

grant select,insert,update,delete on all tables in schema public to authenticated;
grant usage,select on all sequences in schema public to authenticated;
grant execute on function public.ops_reserve_stock(uuid,integer,text,text,timestamptz) to authenticated;
grant execute on function public.ops_release_reservation(uuid,text) to authenticated;
grant execute on function public.ops_consume_reservation(uuid,text) to authenticated;

drop policy if exists "public reads operations product images" on storage.objects;
create policy "public reads operations product images" on storage.objects for select to anon,authenticated using (bucket_id='vjs-product-images');
drop policy if exists "staff uploads operations product images" on storage.objects;
create policy "staff uploads operations product images" on storage.objects for insert to authenticated with check (bucket_id='vjs-product-images' and public.ops_has_role(array['owner','admin','manager','inventory','purchasing']));
drop policy if exists "staff updates operations product images" on storage.objects;
create policy "staff updates operations product images" on storage.objects for update to authenticated using (bucket_id='vjs-product-images' and public.ops_has_role(array['owner','admin','manager','inventory','purchasing'])) with check (bucket_id='vjs-product-images' and public.ops_has_role(array['owner','admin','manager','inventory','purchasing']));
drop policy if exists "staff deletes operations product images" on storage.objects;
create policy "staff deletes operations product images" on storage.objects for delete to authenticated using (bucket_id='vjs-product-images' and public.ops_has_role(array['owner','admin','manager','inventory','purchasing']));

drop policy if exists "staff manage private operations docs" on storage.objects;
create policy "staff manage private operations docs" on storage.objects for all to authenticated using (bucket_id='vjs-private-documents' and public.ops_has_role(array['owner','admin','manager','purchasing'])) with check (bucket_id='vjs-private-documents' and public.ops_has_role(array['owner','admin','manager','purchasing']));

-- SECURITY: do not expose the Supabase service-role key to browser code. Use public anon key + RLS.
),
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (product_id, colour_name)
);
create index if not exists product_colours_product_idx on public.product_colours(product_id,active,sort_order);

create table if not exists public.product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  sku text not null unique,
  colour_name text not null,
  colour_hex text check (colour_hex is null or colour_hex ~ '^#[0-9A-Fa-f]{6}$'),
  size text not null,
  mrp numeric(12,2) not null default 0 check (mrp >= 0),
  selling_price numeric(12,2) not null default 0 check (selling_price >= 0),
  cost_price numeric(12,2) not null default 0 check (cost_price >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (product_id, colour_name, size)
);
create index if not exists product_variants_product_idx on public.product_variants(product_id, active);
create index if not exists product_variants_colour_idx on public.product_variants(product_id, colour_name);

create table if not exists public.product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid references public.products(id) on delete cascade,
  variant_id uuid references public.product_variants(id) on delete cascade,
  image_url text not null,
  storage_path text,
  source_type text not null check (source_type in ('upload','url')),
  alt_text text,
  sort_order integer not null default 0,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  check ((product_id is not null) <> (variant_id is not null))
);
create index if not exists product_images_product_order_idx on public.product_images(product_id, sort_order);
create index if not exists product_images_variant_order_idx on public.product_images(variant_id, sort_order);
create unique index if not exists product_images_one_primary_model
  on public.product_images(product_id) where product_id is not null and is_primary;
create unique index if not exists product_images_one_primary_variant
  on public.product_images(variant_id) where variant_id is not null and is_primary;

create table if not exists public.inventory_balances (
  variant_id uuid primary key references public.product_variants(id) on delete restrict,
  on_hand integer not null default 0 check (on_hand >= 0),
  reserved integer not null default 0 check (reserved >= 0),
  damaged integer not null default 0 check (damaged >= 0),
  available integer generated always as (on_hand - reserved - damaged) stored,
  updated_at timestamptz not null default now(),
  check (reserved + damaged <= on_hand)
);

create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  variant_id uuid not null references public.product_variants(id) on delete restrict,
  quantity_delta integer not null check (quantity_delta <> 0),
  movement_type text not null check (movement_type in ('opening','purchase_receipt','sale','sale_return','purchase_return','adjustment','transfer_in','transfer_out','write_off')),
  reason text,
  source_type text,
  source_id uuid,
  idempotency_key text unique,
  actor_id uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists stock_movements_variant_date_idx on public.stock_movements(variant_id, created_at desc);

create or replace function public.ops_apply_stock_movement()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.inventory_balances(variant_id, on_hand, reserved, damaged)
  values (new.variant_id, 0, 0, 0) on conflict (variant_id) do nothing;

  update public.inventory_balances
  set on_hand = on_hand + new.quantity_delta, updated_at = now()
  where variant_id = new.variant_id
    and (new.quantity_delta >= 0 or available + new.quantity_delta >= 0);

  if not found then
    raise exception 'Insufficient available inventory for variant %', new.variant_id using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_ops_apply_stock_movement on public.stock_movements;
create trigger trg_ops_apply_stock_movement
after insert on public.stock_movements
for each row execute function public.ops_apply_stock_movement();

create table if not exists public.inventory_reservations (
  id uuid primary key default gen_random_uuid(),
  variant_id uuid not null references public.product_variants(id) on delete restrict,
  quantity integer not null check (quantity > 0),
  reference text not null,
  status text not null default 'reserved' check (status in ('reserved','consumed','released','expired')),
  idempotency_key text not null unique,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.ops_reserve_stock(
  p_variant_id uuid, p_quantity integer, p_reference text, p_idempotency_key text, p_expires_at timestamptz default null
) returns uuid language plpgsql security definer set search_path = public
as $$
declare v_id uuid;
begin
  if auth.uid() is null or not public.ops_has_role(array['owner','admin','manager','cashier']) then
    raise exception 'Not authorised' using errcode = '42501';
  end if;
  if p_quantity <= 0 or length(trim(p_idempotency_key)) = 0 then
    raise exception 'Quantity and idempotency key are required';
  end if;
  select id into v_id from public.inventory_reservations where idempotency_key = p_idempotency_key;
  if v_id is not null then return v_id; end if;

  update public.inventory_balances
  set reserved = reserved + p_quantity, updated_at = now()
  where variant_id = p_variant_id and available >= p_quantity;
  if not found then raise exception 'Insufficient available stock' using errcode = '23514'; end if;

  insert into public.inventory_reservations(variant_id,quantity,reference,idempotency_key,expires_at)
  values (p_variant_id,p_quantity,p_reference,p_idempotency_key,p_expires_at)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.ops_release_reservation(p_reservation_id uuid, p_terminal_status text default 'released')
returns boolean language plpgsql security definer set search_path = public
as $$
declare r public.inventory_reservations%rowtype;
begin
  if auth.uid() is null or not public.ops_has_role(array['owner','admin','manager','cashier']) then
    raise exception 'Not authorised' using errcode = '42501';
  end if;
  select * into r from public.inventory_reservations where id = p_reservation_id for update;
  if not found then return false; end if;
  if r.status <> 'reserved' then return true; end if;
  if p_terminal_status not in ('released','expired') then raise exception 'Invalid terminal status'; end if;
  update public.inventory_balances set reserved = reserved - r.quantity, updated_at = now()
    where variant_id = r.variant_id and reserved >= r.quantity;
  update public.inventory_reservations set status = p_terminal_status, updated_at = now() where id = r.id;
  return true;
end;
$$;

create or replace function public.ops_consume_reservation(p_reservation_id uuid, p_idempotency_key text)
returns boolean language plpgsql security definer set search_path = public
as $$
declare r public.inventory_reservations%rowtype;
begin
  if auth.uid() is null or not public.ops_has_role(array['owner','admin','manager','cashier']) then
    raise exception 'Not authorised' using errcode = '42501';
  end if;
  select * into r from public.inventory_reservations where id = p_reservation_id for update;
  if not found then raise exception 'Reservation not found'; end if;
  if r.status = 'consumed' then return true; end if;
  if r.status <> 'reserved' then raise exception 'Reservation is not active'; end if;

  update public.inventory_balances set reserved = reserved - r.quantity, updated_at = now()
    where variant_id = r.variant_id and reserved >= r.quantity;
  insert into public.stock_movements(variant_id,quantity_delta,movement_type,reason,source_type,source_id,idempotency_key,actor_id)
  values (r.variant_id,-r.quantity,'sale','Reserved stock consumed','reservation',r.id,p_idempotency_key,auth.uid());
  update public.inventory_reservations set status = 'consumed', updated_at = now() where id = r.id;
  return true;
end;
$$;

create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  contact_name text,
  phone text,
  email text,
  gstin text,
  opening_balance numeric(12,2) not null default 0,
  created_at timestamptz not null default now()
);
create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  email text,
  notes text,
  created_at timestamptz not null default now()
);
create table if not exists public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid references public.suppliers(id),
  invoice_number text,
  invoice_storage_path text,
  status text not null default 'ordered' check (status in ('draft','ordered','partially_received','received','cancelled')),
  order_date date not null default current_date,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create table if not exists public.purchase_order_items (
  id uuid primary key default gen_random_uuid(),
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id),
  ordered_qty integer not null check (ordered_qty > 0),
  received_qty integer not null default 0 check (received_qty >= 0 and received_qty <= ordered_qty),
  unit_cost numeric(12,2) not null check (unit_cost >= 0),
  tax_rate numeric(6,3) not null default 0 check (tax_rate >= 0),
  created_at timestamptz not null default now()
);
create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  receipt_number text unique,
  customer_id uuid references public.customers(id),
  bill_type text not null check (bill_type in ('gst','non_gst')),
  payment_status text not null default 'pending' check (payment_status in ('pending','paid','partial','refunded')),
  payment_method text,
  subtotal numeric(12,2) not null default 0,
  discount_total numeric(12,2) not null default 0,
  tax_total numeric(12,2) not null default 0,
  grand_total numeric(12,2) not null default 0,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create table if not exists public.sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id),
  sku_snapshot text not null,
  product_snapshot text not null,
  quantity integer not null check (quantity > 0),
  unit_cost_snapshot numeric(12,2) not null,
  unit_price numeric(12,2) not null,
  discount_amount numeric(12,2) not null default 0,
  tax_rate numeric(6,3) not null default 0,
  tax_amount numeric(12,2) not null default 0,
  line_total numeric(12,2) not null
);
create table if not exists public.integration_outbox (
  id uuid primary key default gen_random_uuid(),
  destination text not null,
  event_type text not null,
  aggregate_type text not null,
  aggregate_id uuid not null,
  payload jsonb not null,
  status text not null default 'pending' check (status in ('pending','processing','sent','failed')),
  attempts integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique(destination,event_type,aggregate_type,aggregate_id)
);

-- Private invoice/document bucket; public product images bucket for catalogue delivery.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('vjs-product-images','vjs-product-images',true,15728640,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=true,file_size_limit=15728640,allowed_mime_types=array['image/jpeg','image/png','image/webp'];
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('vjs-private-documents','vjs-private-documents',false,20971520,array['application/pdf','image/jpeg','image/png'])
on conflict(id) do update set public=false,file_size_limit=20971520,allowed_mime_types=array['application/pdf','image/jpeg','image/png'];

alter table public.staff_profiles enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.product_images enable row level security;
alter table public.inventory_balances enable row level security;
alter table public.stock_movements enable row level security;
alter table public.inventory_reservations enable row level security;
alter table public.suppliers enable row level security;
alter table public.customers enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_items enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.integration_outbox enable row level security;

-- Staff may read their own profile; owner/admin manage staff. All operational data requires an active role.
drop policy if exists "staff read own profile" on public.staff_profiles;
create policy "staff read own profile" on public.staff_profiles for select to authenticated using (user_id=auth.uid() or public.ops_has_role(array['owner','admin']));
drop policy if exists "admins manage staff profiles" on public.staff_profiles;
create policy "admins manage staff profiles" on public.staff_profiles for all to authenticated using (public.ops_has_role(array['owner','admin'])) with check (public.ops_has_role(array['owner','admin']));

do $$
declare t text;
begin
  foreach t in array array['products','product_variants','product_images','inventory_balances','stock_movements','inventory_reservations','suppliers','customers','purchase_orders','purchase_order_items','sales','sale_items','integration_outbox'] loop
    execute format('drop policy if exists "active staff access" on public.%I', t);
    execute format('create policy "active staff access" on public.%I for all to authenticated using (public.ops_has_role(array[''owner'',''admin'',''manager'',''cashier'',''inventory'',''purchasing''])) with check (public.ops_has_role(array[''owner'',''admin'',''manager'',''cashier'',''inventory'',''purchasing'']))', t);
  end loop;
end $$;

grant select,insert,update,delete on all tables in schema public to authenticated;
grant usage,select on all sequences in schema public to authenticated;
grant execute on function public.ops_reserve_stock(uuid,integer,text,text,timestamptz) to authenticated;
grant execute on function public.ops_release_reservation(uuid,text) to authenticated;
grant execute on function public.ops_consume_reservation(uuid,text) to authenticated;

drop policy if exists "public reads operations product images" on storage.objects;
create policy "public reads operations product images" on storage.objects for select to anon,authenticated using (bucket_id='vjs-product-images');
drop policy if exists "staff uploads operations product images" on storage.objects;
create policy "staff uploads operations product images" on storage.objects for insert to authenticated with check (bucket_id='vjs-product-images' and public.ops_has_role(array['owner','admin','manager','inventory','purchasing']));
drop policy if exists "staff updates operations product images" on storage.objects;
create policy "staff updates operations product images" on storage.objects for update to authenticated using (bucket_id='vjs-product-images' and public.ops_has_role(array['owner','admin','manager','inventory','purchasing'])) with check (bucket_id='vjs-product-images' and public.ops_has_role(array['owner','admin','manager','inventory','purchasing']));
drop policy if exists "staff deletes operations product images" on storage.objects;
create policy "staff deletes operations product images" on storage.objects for delete to authenticated using (bucket_id='vjs-product-images' and public.ops_has_role(array['owner','admin','manager','inventory','purchasing']));

drop policy if exists "staff manage private operations docs" on storage.objects;
create policy "staff manage private operations docs" on storage.objects for all to authenticated using (bucket_id='vjs-private-documents' and public.ops_has_role(array['owner','admin','manager','purchasing'])) with check (bucket_id='vjs-private-documents' and public.ops_has_role(array['owner','admin','manager','purchasing']));

-- SECURITY: do not expose the Supabase service-role key to browser code. Use public anon key + RLS.
