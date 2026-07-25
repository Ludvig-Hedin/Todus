---
id: 0158
title: "Native App Readiness — Phase 3 Polish & Performance"
status: archived
category: Changed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] Native App Readiness — Phase 3 Polish & Performance

### Both Platforms (iOS + macOS)

- **Fix: Request timeouts** — All `URLRequest` objects in `TodosAPIClient` now use a 30-second timeout (`timeoutInterval: 30`) to prevent indefinite hangs on bad connectivity.

### iOS (`apps/ios/Todus`)

- **Fix: AppConfiguration URL force unwraps** — Moved hardcoded URL strings to `static let` constants (constructed once, guaranteed valid). Eliminates repeated `URL(string:)!` force unwraps.
- **Fix: GroupChat adaptive polling** — Polling interval now adapts: 5s when the view is active, 30s when the app is backgrounded. Uses `scenePhase` to toggle `setActive()`. Reduces battery drain.

### macOS (`apps/macos/TodusMac`)

- **Feature: Structured logging** — Created `AppLogger.swift` (mirrors iOS). Replaced all 32 `print("[...")` calls across 9 files with `AppLogger.shared.log(...)` for persistent file-based logging and diagnostic sharing.
- **Feature: Email error state + retry** — Added dedicated `errorState` view to `MacEmailInboxView` with error message and "Try Again" button (matching the iOS pattern). Previously, failed loads showed the empty state.
- **Feature: Accessibility labels** — Added `accessibilityLabel` and `accessibilityHint` to toolbar buttons (Notifications, More Options, Create, Search) for VoiceOver support.

### Files changed

- `apps/ios/Todus/Todus/Data/AppConfiguration.swift`
- `apps/ios/Todus/Todus/Services/API/TodosAPIClient.swift`
- `apps/ios/Todus/Todus/Services/AI/GroupChatService.swift`
- `apps/ios/Todus/Todus/Features/AI/GroupChatView.swift`
- `apps/macos/TodusMac/Services/AppLogger.swift` (new)
- `apps/macos/TodusMac/Services/API/TodosAPIClient.swift`
- `apps/macos/TodusMac/Services/Email/EmailService.swift`
- `apps/macos/TodusMac/Services/Meetings/MeetingsService.swift`
- `apps/macos/TodusMac/MeetingsService.swift`
- `apps/macos/TodusMac/App/MacAppServices.swift`
- `apps/macos/TodusMac/App/MacRootView.swift`
- `apps/macos/TodusMac/Views/Tasks/MacTasksView.swift`
- `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`
- `apps/macos/TodusMac/Views/Create/MacCreateSheet.swift`
- `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift`
- `apps/macos/TodusMac/Views/Email/MacEmailInboxView.swift`
- `apps/macos/TodusMac/Domain/EmailModels.swift`
