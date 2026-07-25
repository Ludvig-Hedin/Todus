---
id: 0049
title: "iOS Code Review Follow-up Fixes"
status: archived
category: Fixed
release_date: 2026-03-27
source: CHANGELOG.md
---

## [2026-03-27] iOS Code Review Follow-up Fixes

### Bug Fixes & Hardening

- **AppServices.swift**: Persist migrated signatures to UserDefaults after legacy migration (prevents re-migration on every launch). Added logging for JSONEncoder failures in signatures didSet.
- **TodosApp.swift**: Moved `appDelegate.modelContainer` assignment into `initializeApp()` before @State properties are set, eliminating notification race condition. Replaced `try?` with `do/catch` + logging for context.save() and notification scheduling.
- **EmailModels.swift**: Replaced `UUID().uuidString` fallback in EmailAttachment with deterministic ID based on filename+size. Changed date parsing fallback from `Date()` to `Date.distantPast` with logging.
- **TodosAPIClient.swift**: Added missing `EmptyResponse` struct. After successful 401 silent refresh, requests now retry automatically instead of throwing.
- **AuthService.swift**: Converted `userName`/`userImage` from computed to stored properties with Keychain-syncing didSet. Added HTTP status check in `fetchUserProfile()` before parsing JSON.
- **TaskCaptureService.swift**: Reschedules notification when transitioning back to `.todo`. Cancels notification on `.done` in `updateTaskDetails()`. Schedules notification after enrichment applies a parsed due date.
- **NotificationService.swift**: `scheduleTaskReminder` now properly checks/requests authorization before scheduling notifications.

### Files

- `App/AppServices.swift` — signature migration persistence + error logging
- `App/TodosApp.swift` — notification race fix + error logging
- `Domain/EmailModels.swift` — deterministic attachment IDs + date fallback
- `Services/API/TodosAPIClient.swift` — EmptyResponse struct + retry-after-refresh
- `Services/Auth/AuthService.swift` — stored userName/userImage + HTTP status check
- `Services/Tasks/TaskCaptureService.swift` — notification lifecycle consistency
- `Resources/NotificationService.swift` — async authorization check
