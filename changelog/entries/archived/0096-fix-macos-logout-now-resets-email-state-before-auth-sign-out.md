---
id: 0096
title: "Fix — macOS logout now resets email state before auth sign-out"
status: archived
category: Fixed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Fix — macOS logout now resets email state before auth sign-out

- Centralized macOS sign-out in `MacAppServices.signOut()` so logout now mirrors the iOS flow.
- Added the missing `emailService.resetForSignOut()` call before `authService.signOut()` to clear threads, connection status, and error state on logout.
- Updated both macOS logout entry points to call the shared service helper:
  - Settings confirmation dialog
  - Sidebar user menu
- Also switched the macOS delete-account flow to the same helper so it leaves the app in a clean post-sign-out state.

**Files:**

- `apps/macos/TodusMac/App/MacAppServices.swift`
- `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`
- `apps/macos/TodusMac/App/MacSidebarView.swift`
