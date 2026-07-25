---
id: 0218
title: "Fix — iOS Gmail connect flow + backend fallback for schema drift"
status: archived
category: Fixed
release_date: 2026-04-24
source: CHANGELOG.md
---

## [2026-04-24] Fix — iOS Gmail connect flow + backend fallback for schema drift

- [Fix] Native iOS Gmail linking now requests a non-redirecting Better Auth OAuth URL, uses the correct `/api/auth/native-link-social` endpoint, and opens the returned Google consent URL in `ASWebAuthenticationSession` instead of trying to decode a followed redirect as JSON.
- [Fix] Added an explicit `ASWebAuthenticationSession.start()` failure path so the app no longer silently stalls when the system cannot launch the web auth session.
- [Fix] `connections.list` now falls back to a legacy raw query when the deployed database is missing `mail0_connection.color`, which restores Gmail connection checks and the connections UI on older schemas.
- [Fix] `sessions.list` now degrades gracefully when `mail0_session_metadata` is missing, returning active sessions without device/location enrichment instead of a 500.
- [Fix] `assistant.getBriefing` now returns a task-only fallback briefing when the deployed database is missing `meeting` or assistant tables, preventing the startup 500 seen in iOS logs.
- [Architectural] These backend fallbacks are compatibility shims for environments where production code is ahead of applied Drizzle migrations; they keep user-facing surfaces working while the database is brought up to date.
- **Files:** `packages/swift-auth/Sources/TodusAuth/AuthService.swift`, `apps/server/src/trpc/routes/connections.ts`, `apps/server/src/trpc/routes/sessions.ts`, `apps/server/src/trpc/routes/assistant.ts`
