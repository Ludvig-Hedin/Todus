---
id: 0164
title: "Fix — iOS startup/runtime hang mitigation and tracing pass"
status: archived
category: Fixed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] Fix — iOS startup/runtime hang mitigation and tracing pass

### iOS (`apps/ios/Todus`)

- **Calendar hot path:** `CalendarService` no longer prunes folder mappings on every event fetch. Pruning is now throttled, bounded to a one-year window, and instrumented with signposts. Added a short-lived today-events cache to avoid repeated EventKit work when returning to Home.
- **Startup/task/email tracing:** Added new `OSSignpost` intervals for calendar fetches, folder-map pruning, shared-folder sync, email connection checks, task-list recomputes, and attachment decoding. Added a debug-only main-thread hang watchdog that logs stalls over 200 ms.
- **Startup/runtime throttling:** `TaskCaptureService.syncSharedFolders`, `EmailService.checkConnection`, and shared AI profile loading are now coalesced/throttled to avoid repeated work when switching tabs or reopening surfaces. `MainTabView` no longer force-rebuilds active tabs with `.id(selectedTab)`.
- **Task-view churn:** Reduced broad observation in the tasks shell by passing narrower dependencies into `InboxView`, `BoardView`, `BoardColumnView`, and `TaskTableView`. Removed the old board string-signature regrouping path and replaced task recompute paths with signposted digest-based updates.
- **Attachment I/O:** Replaced synchronous security-scoped file imports in Create, Task Detail, and AI Chat with async imports. Added thumbnail downsampling/caching in `AttachmentService` and switched attachment previews to lazy thumbnail loading instead of repeated full image decodes during view rendering.
- **Verification:** `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` now succeeds after the performance changes.
