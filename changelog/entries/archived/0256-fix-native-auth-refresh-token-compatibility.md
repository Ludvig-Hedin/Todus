---
id: 0256
title: "Fix — Native auth refresh token compatibility"
status: archived
category: Fixed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Fix — Native auth refresh token compatibility

- [Fix] `/api/auth/refresh-native-token` now accepts both native refresh-token formats during the transition: bearer-plugin tokens from `set-auth-token` and the raw Better Auth session token returned by `/auth/mobile-token`.
- [Fix] If bearer resolution fails, the server rehydrates the raw session token as a signed Better Auth cookie before minting a fresh JWT, so existing iOS/macOS sessions keep refreshing instead of expiring after the first 15-minute access-token window.
- [Fix] `NoRedirectDelegate` now stops at the first redirect for native auth bridge requests, so Gmail linking, Apple sign-in, and OTP fallback flows can inspect the original 3xx `Location` / cookie headers instead of silently following the redirect and losing them.
- **Files:** `apps/server/src/main.ts`, `packages/swift-auth/Sources/TodusAuth/NoRedirectDelegate.swift`
