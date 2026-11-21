-- Atomic POS sale and controlled customer-return workflow.
-- Apply after the Operations core and audit migrations.

alter table public.sales add column if not exists idempotency_key text;
create unique index if not exists sales_idempotency_key_unique on public.sales(idempotency_key) where idempotency_key is not null;

create or replace function public.ops_create_sale(
  p_items jsonb,
  p_bill_type text,
  p_payment_method text,
  p_customer_id uuid default null,
  p_idempotency_key text default null
) returns uuid language plpgsql security definer set search_path = public
as $$
declare
  v_sale_id uuid;
  v_item jsonb;
  v_variant_id uuid;
  v_qty integer;
  v_price numeric(12,2);
  v_discount numeric(12,2);
  v_tax_rate numeric(6,3);
  v_tax numeric(12,2);
  v_line numeric(12,2);
  v_subtotal numeric(12,2) := 0;
  v_discount_total numeric(12,2) := 0;
  v_tax_total numeric(12,2) := 0;
  v_grand_total numeric(12,2) := 0;
  v_available integer;
  v_sku text;
  v_product text;
  v_cost numeric(12,2);
  v_index integer := 0;
begin
  if auth.uid() is null or not public.ops_has_role(array['owner','admin','manager','cashier']) then
    raise exception 'Not authorised' using errcode = '42501';
  end if;
  if p_bill_type not in ('gst','non_gst') or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'A bill type and at least one sale line are required';
  end if;
  if coalesce(length(trim(p_idempotency_key)),0)=0 then raise exception 'Idempotency key is required'; end if;

  select id into v_sale_id from public.sales where idempotency_key=p_idempotency_key;
  if v_sale_id is not null then return v_sale_id; end if;

  insert into public.sales(receipt_number,customer_id,bill_type,payment_status,payment_method,idempotency_key,created_by)
  values ('VJS-'||to_char(now(),'YYYYMMDD')||'-'||upper(substr(gen_random_uuid()::text,1,8)),p_customer_id,p_bill_type,
    case when lower(coalesce(p_payment_method,''))='credit' then 'pending' else 'paid' end,p_payment_method,p_idempotency_key,auth.uid())
  returning id into v_sale_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_index := v_index + 1;
    v_variant_id := (v_item->>'variant_id')::uuid;
    v_qty := (v_item->>'quantity')::integer;
    v_price := coalesce((v_item->>'unit_price')::numeric,0);
    v_discount := coalesce((v_item->>'discount_amount')::numeric,0);
    v_tax_rate := case when p_bill_type='gst' then coalesce((v_item->>'tax_rate')::numeric,0) else 0 end;
    if v_qty <= 0 or v_price < 0 or v_discount < 0 or v_tax_rate < 0 then raise exception 'Invalid sale line values'; end if;
    if v_discount > v_qty * v_price then raise exception 'Discount exceeds line amount'; end if;

    select b.available into v_available
      from public.inventory_balances b where b.variant_id=v_variant_id for update;
    if not found or v_available < v_qty then raise exception 'Insufficient stock for variant %',v_variant_id using errcode='23514'; end if;
    select pv.sku,p.name,pv.cost_price into v_sku,v_product,v_cost
      from public.product_variants pv join public.products p on p.id=pv.product_id
      where pv.id=v_variant_id and pv.active=true;
    if not found then raise exception 'Product variant is inactive or missing'; end if;

    v_subtotal := v_subtotal + v_qty*v_price;
    v_discount_total := v_discount_total + v_discount;
    v_tax := round(((v_qty*v_price-v_discount)*v_tax_rate/100),2);
    v_line := v_qty*v_price-v_discount+v_tax;
    v_tax_total := v_tax_total + v_tax;
    v_grand_total := v_grand_total + v_line;

    insert into public.sale_items(sale_id,variant_id,sku_snapshot,product_snapshot,quantity,unit_cost_snapshot,unit_price,discount_amount,tax_rate,tax_amount,line_total)
    values(v_sale_id,v_variant_id,v_sku,v_product,v_qty,v_cost,v_price,v_discount,v_tax_rate,v_tax,v_line);

    insert into public.stock_movements(variant_id,quantity_delta,movement_type,reason,source_type,source_id,idempotency_key,actor_id)
    values(v_variant_id,-v_qty,'sale','POS sale completed','sale',v_sale_id,p_idempotency_key||':'||v_index,auth.uid());
  end loop;

  update public.sales set subtotal=v_subtotal,discount_total=v_discount_total,tax_total=v_tax_total,grand_total=v_grand_total
  where id=v_sale_id;
  return v_sale_id;
end;
$$;
grant execute on function public.ops_create_sale(jsonb,text,text,uuid,text) to authenticated;

create table if not exists public.sale_returns (
  id uuid primary key default gen_random_uuid(),
  sale_item_id uuid not null references public.sale_items(id),
  quantity integer not null check (quantity > 0),
  condition text not null check (condition in ('saleable','damaged')),
  reason text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  idempotency_key text not null unique,
  requested_by uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists sale_returns_item_idx on public.sale_returns(sale_item_id,status);
alter table public.sale_returns enable row level security;
drop policy if exists "active staff manage sale returns" on public.sale_returns;
create policy "active staff manage sale returns" on public.sale_returns for all to authenticated
  using (public.ops_has_role(array['owner','admin','manager','cashier','inventory']))
  with check (public.ops_has_role(array['owner','admin','manager','cashier','inventory']));
grant select,insert,update on public.sale_returns to authenticated;

create or replace function public.ops_request_sale_return(
  p_sale_item_id uuid,p_quantity integer,p_condition text,p_reason text,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path = public
as $$
declare v_item public.sale_items%rowtype; v_id uuid; v_returned integer;
begin
  if auth.uid() is null or not public.ops_has_role(array['owner','admin','manager','cashier']) then raise exception 'Not authorised' using errcode='42501'; end if;
  if p_quantity<=0 or p_condition not in ('saleable','damaged') or length(trim(coalesce(p_reason,'')))=0 then raise exception 'Valid quantity, condition and reason are required'; end if;
  select id into v_id from public.sale_returns where idempotency_key=p_idempotency_key;
  if v_id is not null then return v_id; end if;
  select * into v_item from public.sale_items where id=p_sale_item_id for update;
  if not found then raise exception 'Sale line not found'; end if;
  select coalesce(sum(quantity),0) into v_returned from public.sale_returns where sale_item_id=p_sale_item_id and status in ('pending','approved');
  if v_returned+p_quantity>v_item.quantity then raise exception 'Return quantity exceeds sold quantity'; end if;
  insert into public.sale_returns(sale_item_id,quantity,condition,reason,idempotency_key,requested_by)
  values(p_sale_item_id,p_quantity,p_condition,p_reason,p_idempotency_key,auth.uid()) returning id into v_id;
  return v_id;
end;
$$;
grant execute on function public.ops_request_sale_return(uuid,integer,text,text,text) to authenticated;

create or replace function public.ops_approve_sale_return(p_return_id uuid)
returns boolean language plpgsql security definer set search_path = public
as $$
declare r public.sale_returns%rowtype; v_item public.sale_items%rowtype;
begin
  if auth.uid() is null or not public.ops_has_role(array['owner','admin','manager','inventory']) then raise exception 'Not authorised' using errcode='42501'; end if;
  select * into r from public.sale_returns where id=p_return_id for update;
  if not found then raise exception 'Return request not found'; end if;
  if r.status='approved' then return true; end if;
  if r.status<>'pending' then raise exception 'Return is not pending'; end if;
  select * into v_item from public.sale_items where id=r.sale_item_id;
  insert into public.stock_movements(variant_id,quantity_delta,movement_type,reason,source_type,source_id,idempotency_key,actor_id)
  values(v_item.variant_id,r.quantity,'sale_return','Approved customer return: '||r.reason,'sale_return',r.id,'return:'||r.id::text,auth.uid());
  if r.condition='damaged' then
    update public.inventory_balances set damaged=damaged+r.quantity,updated_at=now() where variant_id=v_item.variant_id;
  end if;
  update public.sale_returns set status='approved',approved_by=auth.uid(),updated_at=now() where id=r.id;
  return true;
end;
$$;
grant execute on function public.ops_approve_sale_return(uuid) to authenticated;

-- Apply role-scoped policies rather than granting every staff role every action.
drop policy if exists "active staff access" on public.products;
drop policy if exists "active staff access" on public.product_colours;
drop policy if exists "active staff access" on public.product_variants;
drop policy if exists "active staff access" on public.product_images;
drop policy if exists "active staff access" on public.inventory_balances;
drop policy if exists "active staff access" on public.stock_movements;
drop policy if exists "active staff access" on public.inventory_reservations;
drop policy if exists "active staff access" on public.suppliers;
drop policy if exists "active staff access" on public.customers;
drop policy if exists "active staff access" on public.purchase_orders;
drop policy if exists "active staff access" on public.purchase_order_items;
drop policy if exists "active staff access" on public.sales;
drop policy if exists "active staff access" on public.sale_items;
drop policy if exists "active staff access" on public.integration_outbox;

create policy "catalogue staff access" on public.products for all to authenticated
  using(public.ops_has_role(array['owner','admin','manager','inventory']))
  with check(public.ops_has_role(array['owner','admin','manager','inventory']));
create policy "colour staff access" on public.product_colours for all to authenticated
  using(public.ops_has_role(array['owner','admin','manager','inventory']))
  with check(public.ops_has_role(array['owner','admin','manager','inventory']));
create policy "variant staff access" on public.product_variants for all to authenticated
  using(public.ops_has_role(array['owner','admin','manager','inventory']))
  with check(public.ops_has_role(array['owner','admin','manager','inventory']));
create policy "image staff access" on public.product_images for all to authenticated
  using(public.ops_has_role(array['owner','admin','manager','inventory']))
  with check(public.ops_has_role(array['owner','admin','manager','inventory']));
create policy "inventory staff access" on public.inventory_balances for all to authenticated
  using(public.ops_has_role(array['owner','admin','manager','cashier','inventory']))
  with check(public.ops_has_role(array['owner','admin','manager','cashier','inventory']));
create policy "movement staff access" on public.stock_movements for all to authenticated
  using(public.ops_has_role(array['owner','admin','manager','cashier','inventory','purchasing']))
  with check(public.ops_has_role(array['owner','admin','manager','cashier','inventory','purchasing']));
create policy "reservation staff access" on public.inventory_reservations for all to authenticated
  using(public.ops_has_role(array['owner','admin','manager','cashier']))
  with check(public.ops_has_role(array['owner','admin','manager','cashier']));
create policy "supplier staff access" on public.suppliers for all to authenticated
  using(public.ops_has_role(array['owner','admin','manager','purchasing']))
  with check(public.ops_has_role(array['owner','admin','manager','purchasing']));
create policy "purchase staff access" on public.purchase_orders for all to authenticated
  using(public.ops_has_role(array['owner','admin','manager','purchasing','inventory']))
  with check(public.ops_has_role(array['owner','admin','manager','purchasing','inventory']));
create policy "purchase line staff access" on public.purchase_order_items for all to authenticated
  using(public.ops_has_role(array['owner','admin','manager','purchasing','inventory']))
  with check(public.ops_has_role(array['owner','admin','manager','purchasing','inventory']));
create policy "customer staff access" on public.customers for all to authenticated
  using(public.ops_has_role(array['owner','admin','manager','cashier']))
  with check(public.ops_has_role(array['owner','admin','manager','cashier']));
create policy "sales staff access" on public.sales for all to authenticated
  using(public.ops_has_role(array['owner','admin','manager','cashier']))
  with check(public.ops_has_role(array['owner','admin','manager','cashier']));
create policy "sale line staff access" on public.sale_items for all to authenticated
  using(public.ops_has_role(array['owner','admin','manager','cashier']))
  with check(public.ops_has_role(array['owner','admin','manager','cashier']));
create policy "integration admin access" on public.integration_outbox for all to authenticated
  using(public.ops_has_role(array['owner','admin']))
  with check(public.ops_has_role(array['owner','admin']));

-- This migration adds a request/approval workflow. Payment refunds still require manual settlement or a configured payment provider.
