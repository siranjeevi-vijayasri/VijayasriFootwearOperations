# Production readiness and coordinated catalogue release

## Release boundary

- The Operations app uses a dedicated Supabase project.
- The customer catalogue keeps its current Supabase project and Storage bucket until a separately tested migration is approved.
- Never copy the Operations service-role key into browser code or Git.
- The catalogue maintenance switch is controlled in the catalogue repository's deployment branch. Deploying that branch is what actually puts the customer site into maintenance; creating a Git branch alone does not change production.
- Keep VJSManage accessible to the owner while the customer-facing catalogue is in maintenance.

## Product and image model

- One product model contains one or more colour/size SKU variants.
- Each sellable size + colour combination has a unique SKU.
- Model images and colour-specific image galleries are stored as separate image records; colour galleries are shared across all size SKUs of that colour.
- Images support both Storage uploads and externally hosted HTTPS URLs.
- Each gallery has a primary image, ordering and alt text.
- The public catalogue groups by brand + model and renders colour swatches; selecting a swatch changes the gallery and available-size list.
- Legacy catalogue rows continue to render while variant data is populated gradually.

## Operations database migrations

Apply these files in order to the dedicated Operations Supabase project only:

1. `supabase/migrations/20261121_operations_core.sql`
2. `supabase/migrations/20261122_operations_transactions_audit.sql`
3. `supabase/migrations/20261123_sales_returns_role_rls.sql`

These migrations establish the relational product/variant/image model, inventory balances and ledger, idempotent reservations, purchase receipt, POS sale, customer return request/approval, staff profiles, role-aware RLS, audit events, image Storage and private invoice/document Storage.

The migrations do not migrate live catalogue records and do not connect the two Supabase projects. The Operations schema keeps colour options separate from size SKUs so one gallery can be reused across every size of the same colour. Back up the target project and review the SQL in a staging project before applying it to production.

## Still required before live shop transactions

- [ ] Create the dedicated Operations Supabase project and configure its URL/public anon key as deployment environment variables.
- [ ] Apply and test all migrations in a staging project; verify RLS with each role and anonymous access.
- [ ] Build the Operations login/session UI and connect all modules to Supabase. The current Next.js page is still a localStorage prototype.
- [ ] Replace local-only product entry with model + colour + size variant management and unique SKU validation.
- [ ] Implement Storage uploads in the Operations product-image library, multi-file previews, URL entries, primary image, ordering, removal and variant association.
- [ ] Connect supplier, purchase, receipt, POS, customer, return, staff and report screens to the database RPCs and tables.
- [ ] Add invoice/PDF generation, GST configuration and numbering, payment settlement/refunds and supplier reconciliation.
- [ ] Add backup/restore and operational monitoring.
- [ ] Add an authenticated, retryable catalogue sync worker using the Operations integration outbox. Do not let the public browser write into Operations tables.
- [ ] Migrate catalogue products/images with a mapping report and duplicate/missing-image checks.
- [ ] Test stock sync, size availability, colour image selection, cart and WhatsApp enquiry end to end.
- [ ] Add marketplace adapters only after seller API access and approval; Amazon/Flipkart sync is not enabled by these migrations.
- [ ] Run security review, accessibility/mobile checks, load checks and full regression tests.

## Go-live gates

Do not disable maintenance mode or accept real inventory/POS transactions until:

1. Operations authentication and database-backed screens are complete.
2. RLS and transaction/concurrency tests pass.
3. Image upload and URL galleries pass on desktop and mobile.
4. Catalogue migration counts reconcile with source counts.
5. Colour selection switches to the correct image set and sizes.
6. Cart preserves model, colour and size.
7. Existing catalogue search, filters, image zoom, WhatsApp enquiry, cart, theme and VJSManage sign-in pass regression.
8. A rollback plan and verified backup exist.

## Deployment notes

- The Operations app is Next.js and needs a compatible Next.js host/runtime. Do not assume a static Cloudflare Pages upload is sufficient; configure the host's supported Next.js deployment adapter/runtime.
- The catalogue is static HTML/JavaScript and can be deployed through its existing static-site hosting pipeline.
- The maintenance flag is enabled on the catalogue feature branch for a planned maintenance deployment. It is not live until that branch is deployed to the active production host.
