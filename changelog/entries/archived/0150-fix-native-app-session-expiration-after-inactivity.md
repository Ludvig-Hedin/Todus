---
id: 0150
title: "Fix — Native app session expiration after inactivity"
status: archived
category: Fixed
release_date: 2026-04-02
source: CHANGELOG.md
---

## [2026-04-02] Fix — Native app session expiration after inactivity

Root cause: Better Auth's `jwt()` plugin defaults to **15-minute expiration**. JWTs minted by `/auth/mobile-token` expired almost immediately, causing native app sign-outs.

### Additional fixes

- **MacAppServices.swift**: Shared folder sync now propagates local fetch failures instead of silently falling back to an empty folder list.
- **nav-main.tsx**: `NavItemExpandable` now receives `isUrlActive` explicitly, fixing a runtime reference error in expandable navigation items.
- **schemas.ts**: `mergeUserSettings` now keeps `categories` typed as full `MailCategory[]` while still allowing nested partial updates elsewhere.
- **MacMeetingsView.swift**: Sync icon rotation now initializes correctly when the meetings view appears during an in-flight sync.
