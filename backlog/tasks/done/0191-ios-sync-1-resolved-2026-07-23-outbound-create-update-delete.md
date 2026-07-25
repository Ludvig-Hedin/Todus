---
id: 0191
title: "IOS-SYNC-1 (resolved 2026-07-23): outbound create/update/delete uses authenticated tasks.sync, inclu"
status: done
tags: [ios, performance, code-review-backlog]
files: []
created: 2026-07-11
source: CODE_REVIEW_BACKLOG.md
---

> Source context: iOS performance pass — deferred findings, 2026-07-11

- **IOS-SYNC-1 (resolved 2026-07-23):** outbound create/update/delete uses authenticated `tasks.sync`, including durable delete retries and account-boundary invalidation. Paginated inbound `tasks.list` upserts hydrate after folders, preserve pending local mutations, resolve by `updatedAt`, and invalidate interrupted pulls across account changes. The server now journals explicit deletions in `task_deletion`; `tasks.deleted` pages that evidence to iOS, deletion wins over stale offline upserts, and the client removes only explicitly tombstoned synced rows plus their reminder/notification mirrors. No deletion is inferred from absence in offset pagination.
