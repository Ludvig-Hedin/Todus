---
id: 0087
title: "Fix — native Google OAuth now returns a JWT bearer token for iOS/macOS"
status: archived
category: Fixed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Fix — native Google OAuth now returns a JWT bearer token for iOS/macOS

- Updated `/api/auth/mobile-token` to mint a JWT via Better Auth's `jwt()` plugin (`auth.api.getToken`) instead of forwarding the raw session token from the browser session.
- Kept the server auth middleware fallback paths in place, but the native callback now receives the JWT format that `/api/auth/me` already verifies directly.
- Updated the shared native auth comments so the callback token format is documented correctly again.

**Files:** `apps/server/src/main.ts`, `packages/swift-auth/Sources/TodusAuth/AuthService.swift`
