---
id: 0099
title: "Fix — iOS hang triage instrumentation and shell pressure reduction"
status: archived
category: Fixed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Fix — iOS hang triage instrumentation and shell pressure reduction

- Deferred non-critical root startup work so launch no longer immediately competes with reminders import/sync and legacy auth-upgrade work.
- Switched the iOS shell back to rendering only the active tab, reducing hidden SwiftUI invalidation and background work during tab switches, focus changes, and general interaction.
- Added Instruments-friendly trace points around app initialization, deferred startup, tab switching, SwiftData saves, email thread loading, and reminders sync/import.
- Cached bearer tokens in-memory inside the shared native auth service and moved profile/token metadata persistence off the synchronous main-actor path to reduce Security/Keychain stalls.
- Prevented the email inbox from re-running its full initial fetch every time the tab becomes visible, and fixed a create-sheet fallback path so event creation failures preserve attachments when falling back to task capture.

**Files:** `TodosApp.swift`, `RootView.swift`, `MainTabView.swift`, `AppServices.swift`, `AppLogger.swift`, `EmailService.swift`, `EmailInboxView.swift`, `TaskCaptureService.swift`, `BoardView.swift`, `CreateSheet.swift`, `AuthService.swift`
