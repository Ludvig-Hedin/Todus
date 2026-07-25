---
id: 0153
title: "Performance — Summary-driven inbox and warmer caches"
status: archived
category: Changed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] Performance — Summary-driven inbox and warmer caches

### Web (`apps/mail`)

- **Summary-driven inbox rows:** Mail list rows now render from `mail.listThreads` summary data instead of issuing `mail.get` for every visible row, removing the inbox N+1 fetch pattern that made folder loads feel slow.
- **Predictive thread warming:** The inbox now prefetches the selected thread, nearby threads, and hovered rows so opening a conversation is usually warm by the time the user clicks it.
- **Persisted cache no longer self-invalidates:** Restored inbox cache is kept available on startup instead of being immediately invalidated after hydration, which improves perceived speed after reloads and app restarts.
- **Visible background refresh state:** Cached-first mail, home, tasks, and calendar surfaces now show a subtle updating indicator while background revalidation is running so fast cached paints still communicate that fresher data is on the way.
- **App-start warmup:** Client providers now warm settings, folders, inbox, tasks, and today's calendar window during idle time after the active connection resolves.
- **Task cache patching:** Web task create/update/delete flows now patch cached task queries directly on the tasks page, home page, calendar page, and search page instead of relying on broad refetches.

### Native (`apps/ios`, `apps/macos`)

- **Cached refresh indicators across key surfaces:** iOS and macOS inbox, home, calendar, and tasks surfaces now show a compact `Updating` or `Syncing` badge when cached content is already visible and a background refresh is running.
- **No cached-content flicker on Home:** Native Home events and recent-email sections now keep their warmed content on screen during refresh instead of swapping back to a blocking loading card.
- **Shared-folder sync visibility:** Native task tabs now expose the background shared-folder sync state so task data can stay interactive while sync progress remains visible.

### Backend (`apps/server`)

- **Thread summaries from the local thread store:** `mail.listThreads` now returns richer summary rows for DB-backed folder browsing, including sender, subject, timestamps, label-derived flags, and cache timestamps.
- **Search summary hydration:** Provider-backed search results are hydrated with cached thread detail when summary fields are missing, so search results still render meaningful preview data without regressing the fast folder-browsing path.

### Verification

- `pnpm exec tsc --noEmit -p apps/mail/tsconfig.json | rg "mail-list|use-optimistic-actions|client-providers|query-provider|use-threads|task-cache|mail/search/page|mail/tasks/page|mail/home/page|mail/calendar/page"` [No matches]
- `pnpm exec tsc --noEmit -p apps/server/tsconfig.json | rg "lib/driver/types|routes/agent/index|routes/agent/db/index|trpc/routes/mail.ts"` [Still reports pre-existing errors in unrelated sections of `routes/agent/index.ts` and `routes/mail.ts`]
