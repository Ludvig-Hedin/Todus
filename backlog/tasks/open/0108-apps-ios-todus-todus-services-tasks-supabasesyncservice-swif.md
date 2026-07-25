---
id: 0108
title: "apps/ios/Todus/Todus/Services/Tasks/SupabaseSyncService.swift:45 — claim that queue.popLast() races"
status: open
priority: P3
tags: [ios, bug-hunt, code-review-backlog]
files: []
created: 2026-05-20
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-20 — iOS Mobile App Bug Hunt → Unverified leads (investigator candidates that need a closer look)

- `apps/ios/Todus/Todus/Services/Tasks/SupabaseSyncService.swift:45` — claim that `queue.popLast()` races with concurrent `enqueue()`. Service is `@MainActor` so concurrent calls serialise, *but* the inner `Task { await processQueue }` re-enters the actor between awaits — worth re-reading once we add a `processQueue` test fixture.
