---
id: 0296
title: "Mail sync recovery: Gmail watch self-heal, getThread shard race fix, folder pagination"
status: archived
category: Fixed
release_date: 2026-05-21
source: CHANGELOG.md
---

## [2026-05-21] Mail sync recovery: Gmail watch self-heal, getThread shard race fix, folder pagination

Native clients (iOS + macOS) were stuck on month-old mail with no new arrivals and "Failed to load thread." on tap. Root causes fixed:

- **`mail.rewatchGmail` mutation** (`apps/server/src/trpc/routes/mail.ts`) — Force-renews the Gmail PubSub watch + push subscription for the active connection. Gmail watches expire after ~7 days; the hourly cron renews any older than 5 days, but a connection whose watch was lost (subscription deleted, IAM blip, missed cron tick) gets stuck and continuous sync stops delivering new mail. Clears `gmail_sub_age` KV + enqueues `subscribe_queue` job. Idempotent (PubSub topic `Already Exists` is swallowed).
- **Backend auto-rewatch when inbox is stale** (`apps/server/src/trpc/routes/mail.ts`) — When `listThreads` sees an empty inbox or a newest-row older than 24h on a Google connection, it now also enqueues a subscribe job alongside the existing resync trigger. Self-heals the "stuck watch" state on the user's next list call without any client-side action.
- **Composite-cursor pagination fix for folder queries** (`apps/server/src/routes/agent/db/index.ts`) — `findThreadsByFolderWithPagination` was still comparing the raw page-token to `latestReceivedOn` lexically. After the d8d471c7 token-format change (JSON `{ latestReceivedOn, id }`), `{` > `2` made `lt` true for every row, so page 2 returned the same newest slice forever. Now reuses `buildPaginationConditions` like the all-threads path.
- **`getThread` shard race no longer picks empty stubs** (`apps/server/src/lib/server-utils.ts`) — `ZeroDriver.getThreadFromDB` returns a truthy `{ messages: [], latest: undefined }` placeholder for shards that don't own the thread (and kicks off an async re-sync in the background). The previous race-success condition `if (thread)` was making `Effect.raceAll` declare the empty shard the winner whenever it resolved first, so users whose thread lived in a later shard hit "Failed to load thread.". Race now only succeeds when the result actually has a message payload.
- **iOS — proactive Gmail rewatch on stale refresh** (`apps/ios/Todus/Todus/Services/Email/EmailService.swift`) — Refresh path now triggers `mail.rewatchGmail` when the displayed inbox / incoming slice is older than 24h, or when both are empty. 6-hour cooldown to avoid flooding `subscribe_queue` on repeat refreshes within the same session. Cleared on sign-out.
- **iOS — surface real backend error on thread tap** (`apps/ios/Todus/Todus/Services/Email/EmailService.swift`) — `friendlyThreadLoadMessage` now parses the tRPC error envelope `{ error: { json: { message } } }` and surfaces the actual server message (e.g. "Thread <id> not found") for 5xx responses instead of the generic "Mail service is unavailable.". Makes silent shard misses diagnosable from the UI.
- **macOS — mirrored rewatch + error parsing** (`apps/macos/TodusMac/Services/Email/EmailService.swift`) — Same proactive `mail.rewatchGmail` trigger on stale refreshes. `loadThread` now uses the same `friendlyThreadLoadMessage` + `parseTRPCErrorMessage` pipeline so the desktop app surfaces backend errors instead of a flat "Failed to load thread.".
