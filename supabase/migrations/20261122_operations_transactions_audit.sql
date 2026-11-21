-- Transaction and audit layer for the Operations core schema.
-- Apply after 20261121_operations_core.sql in the dedicated Operations project.

create table if not exists public.audit_events (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references auth.users(id),
  action text not null,
  entity_type text not null,
  entity_id uuid,
  before_data jsonb,
  after_data jsonb,
  reason text,
  created_at timestamptz not null default now()
);
create index if not exists audit_events_entity_idx on public.audit_events(entity_type,entity_id,created_at desc);
create index if not exists audit_events_actor_idx on public.audit_events(actor_id,created_at desc);
alter table public.audit_events enable row level security;
drop policy if exists "managers read audit events" on public.audit_events;
create policy "managers read audit events" on public.audit_events for select to authenticated
  using (public.ops_has_role(array['owner','admin','manager']));
drop policy if exists "active staff write audit events" on public.audit_events;
create policy "active staff write audit events" on public.audit_events for insert to authenticated
  with check (actor_id = auth.uid() and public.ops_has_role(array['owner','admin','manager','cashier','inventory','purchasing']));
grant select,insert on public.audit_events to authenticated;

create or replace function public.ops_audit_row()
returns trigger language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb; v_id uuid;
begin
  if tg_op = 'INSERT' then
    v_after := to_jsonb(new);
    v_id := (v_after->>'id')::uuid;
  elsif tg_op = 'UPDATE' then
    v_before := to_jsonb(old);
    v_after := to_jsonb(new);
    v_id := coalesce((v_after->>'id')::uuid,(v_before->>'id')::uuid);
  else
    v_before := to_jsonb(old);
    v_id := (v_before->>'id')::uuid;
  end if;
  insert into public.audit_events(actor_id,action,entity_type,entity_id,before_data,after_data)
  values (auth.uid(),lower(tg_op),tg_table_name,v_id,v_before,v_after);
  return coalesce(new,old);
end;
$$;

drop trigger if exists audit_products on public.products;
create trigger audit_products after insert or update or delete on public.products
for each row execute function public.ops_audit_row();
drop trigger if exists audit_product_variants on public.product_variants;
create trigger audit_product_variants after insert or update or delete on public.product_variants
for each row execute function public.ops_audit_row();
drop trigger if exists audit_suppliers on public.suppliers;
create trigger audit_suppliers after insert or update or delete on public.suppliers
for each row execute function public.ops_audit_row();
drop trigger if exists audit_purchase_orders on public.purchase_orders;
create trigger audit_purchase_orders after insert or update or delete on public.purchase_orders
for each row execute function public.ops_audit_row();
drop trigger if exists audit_sales on public.sales;
create trigger audit_sales after insert or update or delete on public.sales
for each row execute function public.ops_audit_row();

-- Receive part/all of a purchase order line exactly once per idempotency key.
-- Stock increases only after a physical receipt is recorded.
create or replace function public.ops_receive_purchase_item(
  p_item_id uuid, p_quantity integer, p_idempotency_key text
) returns integer language plpgsql security definer set search_path = public
as $$
declare v_item public.purchase_order_items%rowtype; v_movement_id uuid; v_received integer;
begin
  if auth.uid() is null or not public.ops_has_role(array['owner','admin','manager','purchasing','inventory']) then
    raise exception 'Not authorised' using errcode = '42501';
  end if;
  if p_quantity <= 0 or length(trim(p_idempotency_key)) = 0 then
    raise exception 'Positive quantity and idempotency key are required';
  end if;
  select * into v_item from public.purchase_order_items where id=p_item_id for update;
  if not found then raise exception 'Purchase order line not found'; end if;
  if exists(select 1 from public.stock_movements where idempotency_key=p_idempotency_key) then
    return v_item.received_qty;
  end if;
  if v_item.received_qty + p_quantity > v_item.ordered_qty then
    raise exception 'Receipt quantity exceeds outstanding purchase quantity';
  end if;
  update public.purchase_order_items set received_qty=received_qty+p_quantity where id=p_item_id returning received_qty into v_received;
  insert into public.stock_movements(variant_id,quantity_delta,movement_type,reason,source_type,source_id,idempotency_key,actor_id)
  values(v_item.variant_id,p_quantity,'purchase_receipt','Goods received','purchase_order_item',p_item_id,p_idempotency_key,auth.uid())
  returning id into v_movement_id;
  update public.purchase_orders po
  set status=case
    when not exists(select 1 from public.purchase_order_items i where i.purchase_order_id=po.id and i.received_qty<i.ordered_qty) then 'received'
    when exists(select 1 from public.purchase_order_items i where i.purchase_order_id=po.id and i.received_qty>0) then 'partially_received'
    else po.status end
  where po.id=v_item.purchase_order_id;
  return v_received;
end;
$$;
grant execute on function public.ops_receive_purchase_item(uuid,integer,text) to authenticated;

-- Stock adjustments are reasoned, permission-checked and idempotent.
create or replace function public.ops_adjust_stock(
  p_variant_id uuid, p_quantity_delta integer, p_reason text, p_idempotency_key text
) returns uuid language plpgsql security definer set search_path = public
as $$
declare v_id uuid;
begin
  if auth.uid() is null or not public.ops_has_role(array['owner','admin','manager','inventory']) then
    raise exception 'Not authorised' using errcode = '42501';
  end if;
  if p_quantity_delta=0 or length(trim(coalesce(p_reason,'')))=0 or length(trim(p_idempotency_key))=0 then
    raise exception 'A non-zero quantity, reason and idempotency key are required';
  end if;
  insert into public.stock_movements(variant_id,quantity_delta,movement_type,reason,source_type,idempotency_key,actor_id)
  values(p_variant_id,p_quantity_delta,'adjustment',p_reason,'manual',p_idempotency_key,auth.uid())
  on conflict(idempotency_key) do update set idempotency_key=excluded.idempotency_key
  returning id into v_id;
  return v_id;
end;
$$;
grant execute on function public.ops_adjust_stock(uuid,integer,text,text) to authenticated;

-- RLS for audit table is intentionally stricter than operational tables.
