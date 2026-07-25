---
id: 0227
title: "Fix — Docs production schema repair"
status: archived
category: Docs
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Fix — Docs production schema repair

- [Ops] **Backend:** `/admin/run-migrations` now repairs the docs storage schema through the production Hyperdrive connection: creates `mail0_doc_workspace`, `mail0_doc`, docs foreign keys, indexes, and `mail0_doc.is_starred` idempotently. `mode=info` also reports docs table columns so the repair can be verified before/after running it.
- [User-facing] Once this backend is deployed and the admin repair or normal Drizzle migrations are applied, macOS/web Docs will stop returning HTTP 412 “missing doc tables”.
- **Files:** `apps/server/src/main.ts`
