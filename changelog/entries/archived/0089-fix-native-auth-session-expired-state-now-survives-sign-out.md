---
id: 0089
title: "Fix — native auth session-expired state now survives sign-out, and Keychain save failures are observable"
status: archived
category: Fixed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Fix — native auth session-expired state now survives sign-out, and Keychain save failures are observable

- Reordered the shared native auth invalid-session flow so `signOut()` runs before the session-expired flag and user-facing error are set, which preserves the warning banner/message instead of clearing them immediately.
- Applied the same ordering in persisted-session restoration so invalid saved sessions now leave the app in a consistent expired state after sign-out.
- Upgraded shared Keychain writes to return success/failure and log OSStatus details instead of silently ignoring `SecItemAdd` / `SecItemDelete` failures.
- Updated iOS and macOS AI conversation persistence to check the new Keychain write result and log failures instead of dropping them silently.
- Verified the macOS project `LastUpgradeCheck = 2640` already matches the installed Xcode 26.4 toolchain, so no project file change was required.

**Files:** `packages/swift-auth/Sources/TodusAuth/AuthService.swift`, `packages/swift-auth/Sources/TodusAuth/KeychainHelper.swift`, `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`, `apps/macos/TodusMac/Services/AI/MacAIChatService.swift`
