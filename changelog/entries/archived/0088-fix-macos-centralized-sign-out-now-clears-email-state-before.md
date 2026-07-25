---
id: 0088
title: "Fix — macOS centralized sign-out now clears email state before auth reset"
status: archived
category: Fixed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Fix — macOS centralized sign-out now clears email state before auth reset

- Updated the macOS `MacAppServices.signOut()` path to call `emailService.resetForSignOut()` before `authService.signOut()`.
- Removed the stale TODO from the centralized sign-out method so logout behavior now matches the sidebar and settings call sites that already route through this method.
- This prevents cached email threads, pagination tokens, connection status, and email errors from surviving logout and leaking into the next user session.

**Files:** `apps/macos/TodusMac/App/MacAppServices.swift`
