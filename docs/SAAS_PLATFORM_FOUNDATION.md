# SaaS Platform Foundation

Status: Architecture baseline — implementation plan, not a claim of production readiness.

## Product direction

Vijayasri Footwear is the first tenant and design partner for a multi-tenant retail SaaS product. The platform must support independent retailers, multiple stores per tenant, multiple registers per store, and retail-specific workflows without tenant data leakage.

The POS and customer storefront are coordinated applications over the same domain model and transaction services.

## Architecture decisions

### 1. Tenant isolation

Use a shared PostgreSQL database and shared schema initially, with mandatory `tenant_id` ownership on every tenant-scoped business record.

Requirements:
- Every tenant-owned table has a non-null `tenant_id`.
- Every tenant-scoped query and write is protected by PostgreSQL RLS, not only application filters.
- Resolve the active tenant from authenticated membership on the server. Never trust a client-supplied tenant ID by itself.
- Membership roles are scoped to a tenant and optionally to a store.
- Composite unique constraints and foreign keys include tenant ownership where needed, preventing cross-tenant references.
- Security-definer RPCs explicitly validate tenant membership and scope every read/write.
- Automated negative tests prove that Tenant A cannot read, mutate, infer, or reference Tenant B data.
- Platform support access is separate, privileged, audited, time-bound, and never an implicit bypass for normal application roles.

Do not introduce a tenant migration by simply adding nullable tenant IDs and broad policies. The existing single-tenant policies and RPCs must be replaced or made tenant-aware in the same controlled release.

### 2. Core tenancy and organisation model

- `tenants`: retailer account, lifecycle state, locale, timezone, base currency and legal/business profile.
- `tenant_memberships`: user-to-tenant membership, tenant role, status and invitation lifecycle.
- `stores`: physical or online selling locations owned by a tenant.
- `registers`: POS terminals assigned to a store, with register status and session controls.
- `tenant_settings`: tax, receipt, numbering, locale, currency and operational preferences.
- `plans`, `subscriptions`, `feature_entitlements`: SaaS packaging and feature access; payment-provider integration remains replaceable.
- `audit_events`: append-only business and security activity, tenant-scoped and actor-attributed.

### 3. Domain model

Tenant-scoped entities include:
- Catalogue: products, categories, brands, attributes, variants/SKUs, barcodes, media.
- Locations: stores, warehouses, stock locations and transfers.
- Inventory: balances, reservations, immutable stock ledger, counts and adjustments.
- Procurement: suppliers, purchase orders, receipts, supplier invoices and returns.
- Commerce: carts, orders, sales, sale lines, tenders, refunds and returns.
- Customers: profiles, consent, loyalty accounts and customer activity.
- Workforce: memberships, role grants, register sessions and approvals.
- Integrations: API credentials metadata, webhooks, integration connections, retryable outbox/inbox events.

Footwear remains a vertical capability: model -> colour -> size SKU. Other verticals use configurable product attributes and variant dimensions rather than footwear-specific columns everywhere.

### 4. Transaction and inventory integrity

- Sales, payment/tender records, sale-line snapshots and stock movements are committed atomically.
- Idempotency keys protect every externally retryable command.
- Inventory is changed only through validated domain commands/RPCs.
- Stock ledger is append-only; balances are derived/maintained transactionally.
- All sale lines retain historical SKU, description, tax, discount, unit price and cost snapshots.
- Purchase receipt, return approval, transfer and adjustment commands are auditable.
- Concurrency tests cover two registers selling the last unit simultaneously.

### 5. Storefront and channel model

POS, public storefront, assisted sales and future marketplace channels share catalogue and inventory services. Public storefront access is read-only for catalogue/availability and writes through a validated server-side order endpoint or RPC. A public browser must never receive a service-role key or write directly to privileged operational tables.

### 6. Offline-capable POS

Design for an installable/PWA-capable POS with a local encrypted persistence layer and durable command queue. Offline mode must have explicit policy for permitted actions, cached catalogue/prices, receipt sequencing, payment limitations, stock reservations and conflict resolution. Synchronisation is idempotent and observable. Never silently claim globally authoritative stock while a terminal is disconnected.

### 7. SaaS operations

- Tenant onboarding, invitations, tenant lifecycle and controlled data export/deletion.
- Subscription state and entitlement checks on the server.
- Usage metering for stores, registers, users, orders and storage where appropriate.
- Tenant-aware backups, restore drills, observability and support tooling.
- Versioned public APIs, webhooks, rate limits and integration retry/dead-letter handling.
- Data residency and regional deployment strategy evaluated before international expansion.

## Delivery sequence

### Phase 0 — Architecture and security baseline
1. Audit the existing prototype, SQL migrations, RLS policies and RPCs.
2. Define tenancy, roles, store/register context, IDs, naming and migration strategy.
3. Build tenant membership helpers and tenant-scoped test fixtures.
4. Replace broad single-tenant policies with tenant-aware policies.
5. Add automated cross-tenant isolation tests before adding more business features.

### Phase 1 — SaaS-ready core
1. Tenant onboarding and first-owner bootstrap.
2. Tenant memberships, invitations and scoped roles.
3. Stores, warehouses and registers.
4. Tenant settings, locale, timezone, currency and tax configuration.
5. Tenant-aware catalogue, inventory, procurement, POS, returns and audit.
6. Server-side command layer and typed data access.

### Phase 2 — Complete retail product
1. Reliable checkout, tenders, refunds, receipts and cash management.
2. Barcode workflows, stock counts, transfers and replenishment.
3. Customer profiles, consent and loyalty.
4. Reports based on immutable transaction snapshots.
5. Unified customer storefront and online order lifecycle.

### Phase 3 — SaaS commercialisation
1. Plans, subscriptions, entitlements and billing-provider adapter.
2. Tenant onboarding automation, trial, upgrade, downgrade and cancellation.
3. Usage metering, quotas and support console.
4. Public API, webhooks and integration marketplace foundations.
5. Tenant export, retention and deletion workflows.

### Phase 4 — Scale and internationalisation
1. Offline-first register and safe synchronisation.
2. Multi-region strategy, data residency and disaster recovery.
3. Localised tax, fiscal receipt and payment adapters by market.
4. Load, chaos, security and penetration testing.
5. Operational SLOs and customer support readiness.

## Definition of done for SaaS foundation

- A new retailer can create a tenant without developer SQL edits.
- The first owner can invite staff and assign store-scoped roles.
- A user belonging to multiple tenants can switch tenant context safely.
- Every tenant-owned table has RLS and tenant-aware constraints.
- Automated tests demonstrate zero cross-tenant read/write/reference leakage.
- Sales, returns, stock and audit operations are tenant-scoped and idempotent.
- A tenant can have multiple stores and registers without sharing stock accidentally.
- A staging tenant can be exported and restored using a documented procedure.
- No live customer data or real payments are used until security and recovery gates pass.

## Current repository baseline and known gaps

The current Operations application is a localStorage prototype. Its current SQL migrations describe a single-tenant operational schema with global staff roles and broad staff policies. They are not SaaS-safe as-is.

The next engineering task is a schema/RLS/RPC audit and a tenant-aware migration design. Do not apply a tenant migration to a live project until it has been tested against a clean staging Supabase project and the cross-tenant isolation suite passes.

## Release policy

- Keep all SaaS foundation work on a feature branch.
- Do not merge to `main`, create production infrastructure, apply migrations to a live project, or deploy without explicit approval.
- Do not migrate the old catalogue until source counts and image mappings are reconciled.
- POS and customer storefront are released together after end-to-end acceptance.
