---
id: 0185
title: "Fix — macOS Xcode target graph for shared auth"
status: archived
category: Fixed
release_date: 2026-04-04
source: CHANGELOG.md
---

## [2026-04-04] Fix — macOS Xcode target graph for shared auth

- [Build] Fixed the macOS Xcode project so shared auth sources resolve from `packages/swift-auth/Sources/TodusAuth` instead of the stale removed `apps/swift-auth` path.
- [Build] Removed the placeholder `App/ConnectionsService.swift` from the macOS target graph and kept the real `Services/ConnectionsService.swift` as the only compiled source.
- [Verification] Confirmed `xcodebuild -project apps/macos/TodusMac.xcodeproj -scheme TodusMac -configuration Debug -derivedDataPath /tmp/todusmac-derived CODE_SIGNING_ALLOWED=NO build` succeeds locally.
- **Files:** `apps/macos/project.yml`, `apps/macos/TodusMac.xcodeproj/project.pbxproj`
