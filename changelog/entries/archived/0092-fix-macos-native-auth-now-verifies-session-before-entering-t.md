---
id: 0092
title: "Fix — macOS native auth now verifies session before entering the app shell"
status: archived
category: Fixed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Fix — macOS native auth now verifies session before entering the app shell

- Hardened the shared native `AuthService` so Google/Apple/OTP callbacks no longer mark the app as authenticated from token presence alone.
- Added post-callback `/api/auth/me` verification with short retry backoff to absorb the native OAuth handoff window before profile hydration completes.
- Added callback deduping so macOS dual callback entrypoints cannot race the same token through auth completion twice.
- Added explicit persisted-session restoration on macOS launch so stale Keychain state is rejected before the main shell renders.
- Namespaced native Keychain entries by bundle-specific service to make session storage deterministic across iOS/macOS and to make full local resets reliable.
- Added a DEBUG-only auth section in macOS Settings showing auth state, token preview, session-expired flag, and profile email for faster diagnosis.

**Files:** `packages/swift-auth/Sources/TodusAuth/AuthService.swift`, `packages/swift-auth/Sources/TodusAuth/KeychainHelper.swift`, `apps/macos/TodusMac/App/MacRootView.swift`, `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`, `apps/macos/README.md`, `TASK.md`
