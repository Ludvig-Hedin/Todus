---
id: 0083
title: "Subscription cancel — Cancel hardcodes promonthly, so an annual (proannual) subscriber cancels the wrong produ"
status: open
priority: P2
tags: [macos, server, qa, code-review-backlog]
files: [apps/server/src/trpc/routes/subscription.ts]
created: 2026-05-28
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-28 — macOS QA deferred features (found, not yet fixed) → Deferred — needs backend

| Area | Where | Severity | Problem | Suggested fix |
|------|-------|----------|---------|---------------|
| Subscription cancel | `MacSettingsView.performCancelSubscription` (`productId: "pro_monthly"`) + `apps/server/src/trpc/routes/subscription.ts` `getStatus` | ⚠️ high | Cancel hardcodes `pro_monthly`, so an annual (`pro_annual`) subscriber cancels the wrong product. `getStatus` returns only `plan`/`status`/`aiUsage` — no active product id — so the client can't pick the right one. | Backend `getStatus` must return the active `productId` (and ideally interval). Client then passes the real id to `subscription.cancel`. Backend change required. |
