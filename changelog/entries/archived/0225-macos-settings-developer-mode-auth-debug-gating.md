---
id: 0225
title: "macOS Settings — Developer mode + Auth Debug gating"
status: archived
category: Changed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] macOS Settings — Developer mode + Auth Debug gating

- [UX] **macOS:** Settings includes a **Developer Mode** toggle (orange switch) for the same allowlisted account as iOS (`TodusDeveloperAccess`). **Auth Debug** and other debug-only rows show only when Developer Mode is on; the toggle itself is hidden for non-allowlisted users.
- [Architectural] **macOS:** `MacAppServices` persists `developerModeEnabled` under `TaskApp.developerModeEnabled` (shared key with iOS). The Xcode target now compiles `TodusDeveloperAccess.swift` and `TodusHTTPClient.swift` from `packages/swift-auth` into the app module; redundant `import TodusAuth` was removed from mac sources so the build matches the single-module `Todus` target.
- **Files:** `MacAppServices.swift`, `MacSettingsView.swift`, `MacAIChatService.swift`, `TodosAPIClient.swift`, `MacNotificationCenterView.swift`, `TodusMac.xcodeproj/project.pbxproj`
