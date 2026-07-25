---
id: 0159
title: "Native App Readiness — Critical Bug Fixes & UX Hardening"
status: archived
category: Fixed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] Native App Readiness — Critical Bug Fixes & UX Hardening

### Both Platforms (iOS + macOS)

- **Fix: Silent email mutation failures** — `markAsRead()`, `markAsUnread()`, `archiveThreads()`, `deleteThreads()`, and `toggleStar()` previously had empty `catch {}` blocks. User actions would silently fail with no feedback. All now set `errorMessage` (already rendered in views) and log the error.
- **Fix: Brittle session-expired detection** — Replaced string matching `error.errorDescription?.contains("Session expired")` with type-safe `catch APIError.unauthorized`. The API client already throws this enum case for all 401s.
- **Fix: Network vs server error messages** — `loadThreads()` now distinguishes `URLError` ("No internet connection") from server errors ("Failed to load emails. Please try again.") instead of showing a generic message.

### Shared Auth (`packages/swift-auth`)

- **Fix: Token refresh race condition** — Added `activeRefreshTask` coalescing gate in `refreshAccessToken()`. When multiple API calls receive 401 simultaneously, only one refresh network request fires; subsequent callers await the in-flight result instead of triggering duplicate requests.

### iOS (`apps/ios/Todus`)

- **Fix: Force cast crash in SupabaseEdgeFunctionClient** — Replaced `EmptyResponse() as! Response` with safe conditional cast (`as?`) + guard.
- **Fix: Force unwrap crashes in date computations** — `CalendarTaskView.recomputeBuckets()` and `HomeView.recomputeTasksDueToday()` used `Calendar.date(byAdding:)!`. Replaced with `guard let` + early return.
- **Fix: CalendarService force unwrap after nil check** — `scheduleFolderMapPruneIfNeeded()` used `lastFolderPruneAt!` after a nil check. Replaced with `if let` binding.

### macOS (`apps/macos/TodusMac`)

- **Fix: Settings session revocation errors hidden** — Added `settingsError` state + `.alert()` modifier so users see "Could not revoke session" instead of silent failure.
- **Feature: Offline network banner** — `MacRootView` now reads `networkMonitor.isConnected` and shows a red "No internet connection" capsule banner at the top of the app. Animated in/out with `.snappy`.

### Files changed

- `apps/ios/Todus/Todus/Services/Email/EmailService.swift`
- `apps/macos/TodusMac/Services/Email/EmailService.swift`
- `packages/swift-auth/Sources/TodusAuth/AuthService.swift`
- `apps/ios/Todus/Todus/Services/API/SupabaseEdgeFunctionClient.swift`
- `apps/ios/Todus/Todus/Features/Tasks/CalendarTaskView.swift`
- `apps/ios/Todus/Todus/Features/Home/HomeView.swift`
- `apps/ios/Todus/Todus/Services/Calendar/CalendarService.swift`
- `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`
- `apps/macos/TodusMac/App/MacRootView.swift`
