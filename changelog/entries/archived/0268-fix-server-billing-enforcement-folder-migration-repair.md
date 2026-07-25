---
id: 0268
title: "Fix — server billing enforcement + folder migration repair"
status: archived
category: Fixed
release_date: 2026-04-26
source: CHANGELOG.md
---

## [2026-04-26] Fix — server billing enforcement + folder migration repair

- [Fix] **Billing cache hydration now mutates only on confirmed missing customers.** `refreshSubscriptionCache()` no longer treats every Autumn lookup failure as “customer missing”; transient provider/API failures now preserve the existing cache instead of auto-attaching `free` to whatever state Autumn already has.
- [Fix] **Zero-credit plans are enforced correctly.** `hasAiCredits()` still self-heals legacy zero-state caches, but it no longer fails open when the refreshed quota remains at zero. Only explicit unlimited plans bypass the gate.
- [Fix] **Autumn result objects are handled explicitly.** Billing, signup provisioning, and subscription flows now inspect `autumn-js` `{ data, error, statusCode }` results instead of assuming provider failures throw, which prevents silent local usage-cache drift and surfaces checkout/cancel/billing-portal failures properly.
- [Fix] **Onboarding campaign scheduling now matches Resend’s API contract.** The auth campaign sender now passes `scheduledAt` as an ISO string instead of a raw `Date`, which removes the server type error and keeps delayed onboarding sends shaped correctly for Resend.
- [Fix] **Folder migration repair now covers 0052.** `/admin/run-migrations` `mode=info` reports `mail0_task_folder` / `mail0_folder_item`, and apply mode now repairs the new folder metadata columns, `mail0_folder_item` table, unique constraint, foreign keys, and indexes alongside the earlier docs/billing fixes.
- [Fix] **Docs parent/workspace integrity.** `docs.create` and `docs.update` now validate parent ownership and workspace consistency and inherit the parent workspace when appropriate, preventing cross-user parent links and mismatched workspace trees.
- [Files] `apps/server/src/lib/billing.ts`, `apps/server/src/trpc/routes/subscription.ts`, `apps/server/src/lib/auth.ts`, `apps/server/src/trpc/routes/tasks.ts`, `apps/server/src/trpc/routes/docs.ts`, `apps/server/src/main.ts`, `CHANGELOG.md`, `TASK.md`
