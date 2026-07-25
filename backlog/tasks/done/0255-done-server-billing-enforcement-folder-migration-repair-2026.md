---
id: 0255
title: "DONE Server billing enforcement + folder migration repair (2026-04): refreshSubscriptionCache() now"
status: done
tags: [task-md, sprint]
files: []
created: unknown
source: TASK.md
---

> Source context: TASK.md → Current Native Fix Batch

- `DONE` **Server billing enforcement + folder migration repair (2026-04):** `refreshSubscriptionCache()` now lazy-creates Autumn customers only after a confirmed not-found result, zero-credit plans no longer fail open in `hasAiCredits()`, and usage tracking updates the local cache only after Autumn accepts the debit. Signup/delete + subscription flows now inspect `autumn-js` result objects instead of assuming failures throw, and the onboarding campaign sender now serializes Resend `scheduledAt` correctly as ISO text. `/admin/run-migrations` now repairs the 0052 shared-folder schema (`mail0_task_folder` metadata + `mail0_folder_item`) and exposes those tables in `mode=info`. Docs create/update now enforce parent ownership/workspace consistency and inherit the parent workspace when needed.
