---
id: 0248
title: "DONE Offline-first support across iOS, macOS, and web (2026-04): Tasks, folders, and email drafts ar"
status: done
tags: [task-md, sprint]
files: []
created: unknown
source: TASK.md
---

> Source context: TASK.md → Current Offline-First Batch

- `DONE` **Offline-first support across iOS, macOS, and web (2026-04):** Tasks, folders, and email drafts are composable while offline on iOS and macOS via SwiftData-backed mutation queues (`FolderSyncService`, `TaskSyncService`, `DraftRecord`/`DraftService`) that flush on reconnect via `NetworkMonitor.onReconnect`. Web mutations now pause instead of fail with `networkMode: 'offlineFirst'` on TanStack Query. Offline indicator shown on all three platforms. Backend adds `folders.sync` batch endpoint; `tasks.sync` IDOR hardened with `setWhere` userId guard.
