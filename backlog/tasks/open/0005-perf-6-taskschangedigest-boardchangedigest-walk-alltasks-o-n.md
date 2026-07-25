---
id: 0005
title: "PERF-6 — tasksChangeDigest/boardChangeDigest walk allTasks O(n) on every body eval (they're the .onChange comp"
status: open
priority: P3
tags: [ios, performance, code-review-backlog]
files: []
created: 2026-07-11
source: CODE_REVIEW_BACKLOG.md
---

> Source context: iOS performance pass — deferred findings, 2026-07-11

| ID | File | Issue | Fix direction | Why deferred |
|----|------|-------|---------------|--------------|
| PERF-6 | `Features/Tasks/InboxView.swift:147-160`, `Features/Tasks/BoardView.swift:68-78` | `tasksChangeDigest`/`boardChangeDigest` walk `allTasks` O(n) on every body eval (they're the `.onChange` comparison value) | Cache digest in `@State`, bump it from `TaskCaptureService`/`SyncService` write sites instead of walking in `body` | Knowingly-accepted tradeoff (documented inline); only bites at hundreds+ tasks |
