# Operations Platform Architecture

## System boundary
This is an independent retail operations application with its own Supabase project. The existing public catalogue repository and its Supabase project remain separate and must not be changed by this work.

## Modules
Dashboard; product and SKU master; suppliers; purchases and receipts; size-wise inventory; POS and billing; customers and staff; reports; future catalogue and marketplace adapters.

## Product and SKU
A product model may have multiple sellable variants. Each sellable combination (model, colour and size) receives a unique SKU. Stock is tracked against the SKU.

## Inventory source of truth
All channels must use one inventory service and ledger. Distinguish on-hand, reserved, available, damaged and quarantined stock. Reservations and sales must be transaction-safe and idempotent. Concurrent requests must not allocate more than available stock. Reservation release, confirmation and expiry must be safe to retry.

## Purchases and sales
Purchases increase stock only on actual receipt. Sales retain snapshots of SKU description, cost basis, price, discount and tax so historical reports remain reproducible. Returns add saleable stock only after inspection.

## Security
Enforce authorization server-side and in the database. Enable RLS for operational tables. Keep service-role credentials server-side only. Audit sensitive actions and apply least privilege for owner/admin, manager, cashier and inventory/purchase roles.

## Integration boundary
The public catalogue and future marketplaces are consumers of controlled product and inventory APIs. They must not use privileged database credentials. Integration requires explicit approval, consistency tests and rollback planning.

## Delivery order
1. App foundation and local developer setup.
2. Dedicated Supabase schema, migrations and RLS tests.
3. Product master, variants, SKUs and stock ledger.
4. Atomic inventory operations and concurrency tests.
5. Suppliers, purchases, POS, payments, invoices and returns.
6. Staff roles and audit.
7. Dashboard and reports.
8. Controlled catalogue integration.
9. Marketplace integrations.
