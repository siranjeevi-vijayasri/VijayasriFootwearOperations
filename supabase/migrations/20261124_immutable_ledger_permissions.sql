-- Protect the stock ledger and derived balances from direct browser writes.
-- Apply after all previous Operations migrations.

-- Stock ledger rows are append-only. RPCs run as SECURITY DEFINER and perform validated writes.
revoke insert, update, delete on public.stock_movements from authenticated;
grant select on public.stock_movements to authenticated;

-- Inventory balances are derived by the stock movement trigger and reservation RPCs.
revoke insert, update, delete on public.inventory_balances from authenticated;
grant select on public.inventory_balances to authenticated;

-- Reservation state changes must go through idempotent reservation RPCs.
revoke insert, update, delete on public.inventory_reservations from authenticated;
grant select on public.inventory_reservations to authenticated;

-- Sale headers/lines are created by the atomic POS RPC; never delete historical sale evidence.
revoke insert, update, delete on public.sales from authenticated;
revoke insert, update, delete on public.sale_items from authenticated;
grant select on public.sales, public.sale_items to authenticated;

-- Purchase receipt quantity and order status are updated only by ops_receive_purchase_item.
revoke update, delete on public.purchase_orders from authenticated;
revoke update, delete on public.purchase_order_items from authenticated;
grant select, insert on public.purchase_orders, public.purchase_order_items to authenticated;

-- Return approval and audit history are function/trigger controlled.
revoke insert, update, delete on public.sale_returns from authenticated;
grant select on public.sale_returns to authenticated;
revoke insert, update, delete on public.audit_events from authenticated;
grant select on public.audit_events to authenticated;

-- Ensure only owner/admin can inspect or operate the integration queue from the client.
revoke insert, update, delete on public.integration_outbox from authenticated;
grant select on public.integration_outbox to authenticated;

-- These table-level privileges complement RLS; neither replaces role checks in the RPCs.
