---
id: 0095
title: "Fix — macOS `EmailService.resetForSignOut()` (compile unblock)"
status: archived
category: Fixed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Fix — macOS `EmailService.resetForSignOut()` (compile unblock)

- Implemented the missing `resetForSignOut()` on macOS `EmailService` so callers that clear cached threads, pagination, errors, and connection flags after sign-out resolve at link time.
- **Impact:** Fixes a hard build failure (undefined symbol) once logout/delete-account paths reference this API; unrelated to calendar UI work beyond sharing the same release.

**Files:** `apps/macos/TodusMac/Services/Email/EmailService.swift`
