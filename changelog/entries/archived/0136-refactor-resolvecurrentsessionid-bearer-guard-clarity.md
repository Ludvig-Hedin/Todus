---
id: 0136
title: "Refactor — `resolveCurrentSessionId` Bearer guard clarity"
status: archived
category: Changed
release_date: 2026-03-31
source: CHANGELOG.md
---

## [2026-03-31] Refactor — `resolveCurrentSessionId` Bearer guard clarity

- Replaced `!authHeader?.startsWith('Bearer ')` with `!authHeader || !authHeader.startsWith('Bearer ')` in `apps/server/src/trpc/routes/sessions.ts`. Behavior is unchanged (null/empty headers still take the hint/early-return path only), but the guard matches the real invariant before `authHeader.slice()` and narrows types explicitly.

**Files:** `apps/server/src/trpc/routes/sessions.ts`
