---
id: 0097
title: "Fix — macOS/iOS native apps: user profile not loading after OAuth login"
status: archived
category: Fixed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Fix — macOS/iOS native apps: user profile not loading after OAuth login

**Root cause (3 layers):**

1. Better Auth's HTTP `/auth/get-session` returns `null` for bearer-token requests (200 status, body: `null`)
2. The Hono middleware's JWT fallback tried to verify the 32-char session token as a JWT → threw silently
3. Variable shadowing: `const session = await auth.api.getSession()` shadowed the Drizzle `session` schema table, so the session token DB lookup used the wrong object

**Fix:**

- Renamed middleware variable to `authSession` to avoid shadowing the Drizzle `session` schema import
- Added session token DB lookup fallback: when JWT verification fails, looks up the raw token in the `session` table and resolves the user
- Added `GET /api/auth/me` endpoint that returns `c.var.sessionUser` from middleware context
- Updated shared `fetchUserProfile()` to use `/api/auth/me` instead of `/api/auth/get-session`
- Added `.task(id: isAuthenticated)` to MacRootView so profile fetch re-runs after login
- Added `.task { fetchUserProfile() }` to MacSettingsView

**Files:**

- `apps/server/src/main.ts` — `authSession` rename, session token lookup fallback, `/api/auth/me` endpoint
- `packages/swift-auth/Sources/TodusAuth/AuthService.swift` — Use `/auth/me`, debug logging
- `apps/macos/TodusMac/App/MacRootView.swift` — `.task(id: isAuthenticated)` for profile fetch
- `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift` — `.task { fetchUserProfile() }` on open

**Requires:** Backend redeployment (`pnpm deploy:backend`)
