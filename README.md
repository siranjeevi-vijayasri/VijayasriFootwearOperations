# Vijayasri Footwear Operations

A dedicated operations workspace for Vijayasri Footwear, separate from the existing public catalogue.

## Current build
- Dashboard with calculated local demo metrics
- Product/SKU catalogue
- Supplier directory
- Purchase recording and goods-receipt stock updates
- Inventory overview, adjustments and movement ledger
- POS sales with stock checks, payment method and operator-entered GST rate
- Customer directory
- Staff directory with role labels
- CSV exports for products, sales, purchases and stock ledger

## Local run
Requirements: Node.js 20.9+ and npm.

```bash
npm install
npm run dev
```

Open http://localhost:3000. Data is saved in this browser's local storage for demonstration and local testing.

## Important limitations
This is a local prototype, not production-ready accounting or multi-user inventory software. Data does not sync between devices or users. Authentication, enforced roles, database row-level security, server-side validation, atomic concurrent stock operations, tax invoice/PDF generation, refunds, supplier payment reconciliation and marketplace integrations require the dedicated operations Supabase project and further implementation. Do not enter real customer or financial data in this demo.

The existing public catalogue repository and its Supabase project must remain unchanged. Never commit credentials or secrets.
