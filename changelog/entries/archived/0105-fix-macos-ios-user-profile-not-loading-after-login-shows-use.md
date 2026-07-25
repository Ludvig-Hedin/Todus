---
id: 0105
title: "Fix — macOS/iOS user profile not loading after login (shows \"User\" / \"?\")"
status: archived
category: Fixed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Fix — macOS/iOS user profile not loading after login (shows "User" / "?")

**Root cause:** Better Auth's HTTP `/auth/get-session` endpoint returns `null` for bearer-token-authenticated requests. The Hono middleware's `auth.api.getSession()` call resolves bearer tokens correctly (tRPC routes work), but the HTTP handler doesn't — so `fetchUserProfile()` always got `null` back.

**Fix:**

- Added `/api/auth/me` endpoint on backend that returns `c.var.sessionUser` from the middleware context (which properly resolves bearer tokens)
- Updated `fetchUserProfile()` in shared AuthService to use `/api/auth/me` instead of `/api/auth/get-session`
- Added `.task(id: isAuthenticated)` to MacRootView so profile fetch re-runs after login (not just on initial view appear)
- Added `.task { fetchUserProfile() }` to MacSettingsView to refresh on settings open

**Files:**

- `apps/server/src/main.ts` — New `/api/auth/me` endpoint
- `packages/swift-auth/Sources/TodusAuth/AuthService.swift` — Use `/auth/me`, added debug logging
- `apps/macos/TodusMac/App/MacRootView.swift` — `.task(id: isAuthenticated)` for profile fetch
- `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift` — `.task { fetchUserProfile() }` on open

**Requires:** Backend deployment before the native apps can fetch profile data.
