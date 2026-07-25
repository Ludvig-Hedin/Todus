---
id: 0055
title: "Review follow-up — OTP fallback, compose draft carry-over, and iOS sync/status fixes"
status: archived
category: Fixed
release_date: 2026-03-27
source: CHANGELOG.md
---

## [2026-03-27] Review follow-up — OTP fallback, compose draft carry-over, and iOS sync/status fixes

### Fixed

- **OTP fallback is now dev-only**: The server no longer retries all failed OTP sends through `resend.dev`. Fallback is restricted to the owner mailbox in non-production environments so normal users are not routed into an impossible delivery path.
- **CreateSheet email drafts now preserve typed text**: Choosing the Email route from the universal create modal now carries the entered text into `EmailComposeView(body:)` instead of discarding it.
- **Reminders sync direction now affects behavior**: The selected direction now governs both initial bootstrap sync/import and live task mutations, so `From Reminders` no longer pushes app changes back out and `To Reminders` no longer imports reminders into Todus.
- **Calendar connection state now recognizes full access**: Settings correctly treats EventKit `fullAccess` as connected, matching the event creation flow on newer iOS versions.
- **Gmail connect screen now refreshes connection state**: After the Gmail consent flow completes, the email tab re-checks the backend connection and loads threads immediately when access is available.
- **Sensitive auth logs were removed from release paths**: Apple auth response logging and Google callback logging in iOS now avoid writing cookies or callback tokens into device logs.
- **Todus simulator build blockers were resolved**: The Xcode target now includes `NetworkMonitor.swift` and `CalendarPermissionView.swift`, and the tracked `CustomTabBar.swift` has been brought back in sync with the implementation expected by `MainTabView`.

### Files

- `apps/server/src/lib/auth.ts`
- `apps/ios/Todus/Todus/App/AppServices.swift`
- `apps/ios/Todus/Todus/Services/Reminders/RemindersSyncState.swift`
- `apps/ios/Todus/Todus/Services/Tasks/TaskCaptureService.swift`
- `apps/ios/Todus/Todus/Navigation/CreateSheet.swift`
- `apps/ios/Todus/Todus/Navigation/MainTabView.swift`
- `apps/ios/Todus/Todus/Features/Home/HomeView.swift`
- `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailConnectView.swift`
- `apps/ios/Todus/TASK.md`
