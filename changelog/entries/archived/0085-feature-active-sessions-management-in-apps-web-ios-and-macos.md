---
id: 0085
title: "Feature — active sessions management in `apps/web`, iOS, and macOS"
status: archived
category: Added
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Feature — active sessions management in `apps/web`, iOS, and macOS

- Added a new backend `sessions` tRPC router with `list`, `revoke`, and `revokeAll`, backed by a new `mail0_session_metadata` table for coarse device/location metadata and last-seen tracking.
- Replaced the `apps/web` security placeholder with a real Active Sessions table showing `Device`, `Location`, `Created`, `Updated`, and per-session `Log out`, plus a `Log out all devices` action.
- Added matching Active Sessions management UI to iOS and macOS settings so signed-in devices can be reviewed and revoked from native clients too.
- Improved native current-session detection by resolving raw Better Auth session tokens from the session table when cookie session lookup is unavailable, and by forwarding the Better Auth `session.id` through the native OAuth handoff for JWT-based native sessions.
- Intentionally left cross-device live sync work out of this change set; that architecture remains a separate follow-up because it touches tasks, settings, AI state, and native persistence broadly.

**Files:** `apps/server/src/db/schema.ts`, `apps/server/src/db/migrations/0040_stiff_living_lightning.sql`, `apps/server/src/main.ts`, `apps/server/src/trpc/index.ts`, `apps/server/src/trpc/routes/sessions.ts`, `apps/web/app/(routes)/settings/security/page.tsx`, `apps/ios/Todus/Todus/Services/API/TodosAPIClient.swift`, `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`, `apps/macos/TodusMac/Services/API/TodosAPIClient.swift`, `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`, `packages/swift-auth/Sources/TodusAuth/AuthService.swift`, `TASK.md`
