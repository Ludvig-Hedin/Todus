---
id: 0183
title: "Deferred MINOR findings (cosmetic — not behavior-changing, no backlog action required)"
status: done
tags: [code-review, code-review-backlog]
files: []
created: 2026-06-20
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Pre-push full-repo review — 2026-06-20

## Deferred MINOR findings (cosmetic — not behavior-changing, no backlog action required)

- `apps/server/src/trpc/routes/subscription.ts:34` — `getActiveProduct` adds a synchronous Autumn round-trip to the `getStatus` hot path for non-free users. Fails soft (no correctness risk). Could cache product id alongside the existing subscription cache.
- `apps/server/src/lib/auth.ts:677` — revoke-failure log wording still reads "Failed to revoke some accounts" even when one account failed. Cosmetic.
- `apps/web/components/ui/bimi-avatar.tsx:181` — `MAX_FAVICON_URLS` raised 6→8 now also caps the primary photo + fallbacks, so the constant name is slightly misleading. Behavior fine.
- `apps/web/app/(routes)/mail/tasks/page.tsx:268` — removed post-create `invalidateQueries`; new tasks insert at list head and reconcile sort on next natural refetch. Acceptable.
