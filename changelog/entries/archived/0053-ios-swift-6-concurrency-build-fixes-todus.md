---
id: 0053
title: "iOS — Swift 6 concurrency build fixes (Todus)"
status: archived
category: Fixed
release_date: 2026-03-27
source: CHANGELOG.md
---

## [2026-03-27] iOS — Swift 6 concurrency build fixes (Todus)

### Fixed (Xcode / Swift 6)

- **`TodosApp.swift`**: Removed ineffective `@preconcurrency` on `UNUserNotificationCenterDelegate`. Snooze handling now uses a `Sendable` `SnoozeContentSnapshot` and rebuilds `userInfo` as `["taskID": taskIDString]` on the main actor (avoids sending `UNNotificationContent` / non-Sendable dictionaries across isolation).
- **`CalendarViewController.swift`**: EventKit access completions use a `@Sendable` closure that only schedules `Task { @MainActor [weak self] in ... }`, fixing `EKEventStoreRequestAccessCompletionHandler` data-race diagnostics.
- **`SenderAvatarView.swift`**: Initials avatar background color no longer uses `String.hashValue` (unstable across launches). Uses the same deterministic UTF-16 / JS `<<` algorithm as web `getAvatarColorIndex` in `bimi-avatar.tsx`.
- **`Services/Notifications/NotificationService.swift`**: Snooze now schedules via `enqueueTaskReminder(fireDate:)` at `now + 1h` instead of a synthetic `dueDate` passed through `scheduleTaskReminder` (avoids confusing stacked offsets; behavior unchanged).

### Files

- `apps/ios/Todus/Todus/App/TodosApp.swift`
- `apps/ios/Todus/Todus/Features/Calendar/CalendarViewController.swift`
- `apps/ios/Todus/Todus/Features/Email/SenderAvatarView.swift`
- `apps/ios/Todus/Todus/Services/Notifications/NotificationService.swift`
