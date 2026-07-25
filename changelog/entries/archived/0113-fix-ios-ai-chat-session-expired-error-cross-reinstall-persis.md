---
id: 0113
title: "Fix — iOS AI chat session expired error & cross-reinstall persistence"
status: archived
category: Fixed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Fix — iOS AI chat session expired error & cross-reinstall persistence

### Session expired despite being logged in

- **Root cause:** `AIChatService` returned "Session expired" immediately on HTTP 401 without attempting a silent session refresh. `TodosAPIClient` already handled this correctly.
- **Fix:** On 401, attempt `authService.attemptSilentRefresh()` first. If refresh succeeds, prompt user to retry. If it fails, mark `isSessionExpired = true` for proper re-auth flow.
- **File:** `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`

### Chat history lost on reinstall

- **Root cause:** Conversations stored in `UserDefaults` which is wiped when the app is uninstalled.
- **Fix:** Moved conversation persistence to Keychain (`KeychainHelper.saveData`/`readData`), which survives app reinstalls. Includes automatic migration from old `UserDefaults` storage.
- **Files:** `packages/swift-auth/Sources/TodusAuth/KeychainHelper.swift` (added Data methods), `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`
