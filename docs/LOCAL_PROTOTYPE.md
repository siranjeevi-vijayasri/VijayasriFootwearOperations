# Local prototype behaviour and acceptance notes

The current UI stores demo records in browser local storage under `vijayasri-operations-demo-v1`.

## Workflows available
- Add products with unique SKU, size/colour, MRP, selling price, cost, opening stock and reorder threshold.
- Add suppliers and customer records.
- Record purchases. A purchase marked Received increases product stock and creates a ledger movement; an Ordered purchase does not.
- Adjust inventory with a reason. Negative adjustments are rejected if they would make stock negative.
- Complete POS sales. Sales are rejected when requested quantity exceeds available stock. Successful sales decrement stock and create a ledger movement.
- GST bills accept an operator-entered tax percentage; non-GST bills apply zero tax.
- View staff role labels and export current demo datasets to CSV.

## Known prototype boundaries
- Local browser storage is not a shared database and can be cleared by the browser.
- No authenticated user identity or enforced staff permissions exists yet.
- Product image URL is metadata only; multi-image upload/storage is not implemented.
- No supplier invoice upload, purchase returns, sales returns/refunds, payment settlement, printable GST invoice, PDF, WhatsApp sending or marketplace API.
- No server-side transactional inventory guarantees. Do not use this build for live shop transactions.

## Production acceptance work still required
Dedicated Supabase project; reviewed schema/migrations; RLS policies; auth and role enforcement; RPC/database transactions with concurrency and idempotency tests; audit trail; immutable sale/purchase cost and tax snapshots; GST invoice numbering and document generation; returns/refunds; backups and deployment configuration.
