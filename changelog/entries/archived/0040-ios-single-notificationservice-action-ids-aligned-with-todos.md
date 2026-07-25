---
id: 0040
title: "iOS — Single `NotificationService`, action IDs aligned with `TodosApp`"
status: archived
category: Changed
release_date: 2026-03-27
source: CHANGELOG.md
---

## [2026-03-27] iOS — Single `NotificationService`, action IDs aligned with `TodosApp`

### Bug Fix / Architecture

- **Removed duplicate `NotificationService`**: Only `Services/Notifications/NotificationService.swift` is compiled now; the old `Resources/NotificationService.swift` copy (different `Action` string constants) is deleted. Xcode file reference moved to `Services/Notifications/`. Action identifiers remain `TASK_COMPLETE` / `TASK_SNOOZE`, matching `UNNotificationAction` registration and `AppDelegate` in `TodosApp.swift`.
- **Merged behavior**: 1-hour-before-due scheduling, `TASK_REMINDER` category, async permission request before scheduling (from the former Resources implementation), plus `clearAll` / `cancel(withIdentifiers:)` helpers.
