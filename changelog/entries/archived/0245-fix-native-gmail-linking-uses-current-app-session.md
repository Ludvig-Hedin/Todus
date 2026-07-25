---
id: 0245
title: "Fix — Native Gmail linking uses current app session"
status: archived
category: Fixed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Fix — Native Gmail linking uses current app session

- [Fix] Native Gmail linking now sends the app's stored refresh/session token to `/api/auth/native-link-social`, and the backend validates that exact session for the authenticated user before forwarding to Better Auth `link-social`.
- [Fix] This removes the production 401 path where `/api/auth/me` accepted the native JWT but Gmail linking failed with "No active Better Auth session found for account linking."
- **Files:** `packages/swift-auth/Sources/TodusAuth/AuthService.swift`, `apps/server/src/main.ts`
