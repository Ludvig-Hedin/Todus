---
id: 0269
title: "Fix — shared native auth session restore hardening"
status: archived
category: Fixed
release_date: 2026-04-26
source: CHANGELOG.md
---

## [2026-04-26] Fix — shared native auth session restore hardening

- [Fix] **`packages/swift-auth` session restore now distinguishes revoked sessions from transient failures.** `AuthService`'s refresh path now returns structured outcomes instead of a flat `Bool`, so offline/network failures no longer show a false "Session expired" banner on launch, while genuinely rejected refresh tokens now clear auth state instead of booting into the authenticated shell.
- [Fix] **Confirmed-invalid sessions no longer linger as authenticated in follow-up profile checks.** `restorePersistedSession()` and `fetchUserProfile()` now sign out once `/api/auth/me` rejects both the original and refreshed token, which prevents revoked sessions from continuing to expose cached authenticated UI.
- [Fix] **Token preview redaction is consistent.** The public debug-facing `bearerTokenPreview` accessor now shows length only, matching the logging hardening and avoiding partial token disclosure in screenshots or support captures.
- [Files] `packages/swift-auth/Sources/TodusAuth/AuthService.swift`, `CHANGELOG.md`, `TASK.md`
