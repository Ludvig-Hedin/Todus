---
id: 0258
title: "Feature — Offline-first support across iOS, macOS, and web"
status: archived
category: Added
release_date: 2026-04-26
source: CHANGELOG.md
---

## [2026-04-26] Feature — Offline-first support across iOS, macOS, and web

- [Feature] **Tasks, folders, and email drafts are now writable while offline on iOS.** Creating/editing tasks enqueues to `SupabaseSyncService` (already existed); folder mutations queue through new `FolderSyncService`; email compose uses a new `DraftRecord` SwiftData model so drafts survive offline. All three flush automatically on reconnect via `NetworkMonitor.onReconnect`.
- [Feature] **Same offline write queue on macOS.** New `TaskSyncService` queues task creates/updates/deletes through tRPC `tasks.sync`; `FolderSyncService` mirrors the iOS pattern; `DraftRecord` + `MacDraftService.saveAndSend`/`flushPending` handles email drafts. `MacAppServices.setupNetworkSync()` wires the `onReconnect` flush for all three.
- [Feature] **Web mutations now pause instead of fail when offline.** `networkMode: 'offlineFirst'` added to TanStack Query `defaultOptions` for both queries and mutations (with `retry: 1`). The IDB persister was already providing 24-hour read cache; mutations queued offline auto-retry on reconnect within the same tab session.
- [Feature] **`NetworkMonitor` gets an `onReconnect` callback on both iOS and macOS.** `wasConnected` tracks the previous state so only false→true transitions fire the callback, preventing spurious flushes on first launch.
- [Feature] **Offline indicator on all three platforms.** iOS: `OfflineBanner` SwiftUI view slides in from the top of the task/folder list when `networkMonitor.isConnected == false`. macOS: a slim `.ultraThinMaterial` banner with a `wifi.slash` icon overlays the content area (not the sidebar). Web: `<OfflineIndicator />` component using `useNetworkStatus` hook (`navigator.onLine` + window events) renders below the navigation bar.
- [Feature] **Backend: `folders.sync` batch upsert/delete endpoint.** Mirrors the existing `tasks.sync` pattern with discriminated-union input, `onConflictDoUpdate` with `setWhere: eq(taskFolder.userId, ...)` so cross-user overwrites are impossible, and `sql\`EXCLUDED.\*\`` references in the set block.
- [Fix] **`tasks.sync` IDOR hardened.** Added missing `setWhere: eq(task.userId, ctx.sessionUser.id)` to the existing `tasks.sync` upsert so a conflicting task ID from another user cannot overwrite that user's data.
- [Fix] **Stuck "sending" drafts recover on app restart.** `flushPending` now resets any draft still in "sending" state back to "pendingSend" before retrying, covering the crash-during-send case.
- [Files] `apps/server/src/trpc/routes/tasks.ts`, `apps/ios/Todus/Todus/Services/NetworkMonitor.swift`, `apps/ios/Todus/Todus/App/AppServices.swift`, `apps/ios/Todus/Todus/Services/Tasks/FolderSyncService.swift` (NEW), `apps/ios/Todus/Todus/Data/Models/DraftRecord.swift` (NEW), `apps/ios/Todus/Todus/Services/Drafts/DraftService.swift`, `apps/macos/TodusMac/Services/NetworkMonitor.swift`, `apps/macos/TodusMac/App/MacAppServices.swift`, `apps/macos/TodusMac/Services/Tasks/TaskSyncService.swift` (NEW), `apps/macos/TodusMac/Services/Tasks/FolderSyncService.swift` (NEW), `apps/macos/TodusMac/Data/Models/DraftRecord.swift` (NEW), `apps/macos/TodusMac/App/MacRootView.swift`, `apps/web/app/hooks/use-network-status.ts` (NEW), `apps/web/app/components/offline-indicator.tsx` (NEW), `apps/web/app/(routes)/layout.tsx`, `apps/web/providers/query-provider.tsx`, `CHANGELOG.md`, `TASK.md`
