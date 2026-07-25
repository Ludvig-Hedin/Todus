---
id: 0114
title: "Fix — macOS app shows \"User\" with \"?\" avatar after Google OAuth login"
status: archived
category: Fixed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Fix — macOS app shows "User" with "?" avatar after Google OAuth login

**Root cause:** macOS app never called `fetchUserProfile()` on launch or when settings opened. The iOS app calls it in both `RootView.task{}` and `SettingsView.task{}`, but the macOS equivalents were missing these calls. The only profile fetch happened in `completeAuthentication()`'s fire-and-forget `Task{}`, which could silently fail during the auth→main view transition.

**Fix:** Added `fetchUserProfile()` calls to match iOS behavior:

- `MacRootView.swift` — new `.task{}` that fetches profile on app start
- `MacSettingsView.swift` — new `.task{}` that refreshes profile when settings opens

**Files changed:**

- `apps/macos/TodusMac/App/MacRootView.swift` — Added `.task { await services.authService.fetchUserProfile() }`
- `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift` — Added `.task { await services.authService.fetchUserProfile() }`
