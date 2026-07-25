---
id: 0109
title: "Fix — Bearer token rotation capture (root cause of \"Session expired\")"
status: archived
category: Fixed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Fix — Bearer token rotation capture (root cause of "Session expired")

Better Auth's bearer plugin returns a rotated session token via `set-auth-token` header when `updateAge` extends the session. Neither iOS nor macOS captured this — they kept the old token until it expired, causing 401s.

- **`AuthService.swift`**: Added `captureRotatedToken(from:)` — checks responses for `set-auth-token` and stores new token. Called from `attemptSilentRefresh()` and `fetchUserProfile()`.
- **`TodosAPIClient.swift` (iOS + macOS)**: Calls `captureRotatedToken` on every API response.
- **`AIChatService.swift` / `MacAIChatService.swift`**: Capture on SSE stream responses.
- **`KeychainHelper.swift`**: Added `saveData`/`readData` for Data blobs.
