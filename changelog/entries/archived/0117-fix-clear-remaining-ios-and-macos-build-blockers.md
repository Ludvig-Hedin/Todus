---
id: 0117
title: "Fix — Clear remaining iOS and macOS build blockers"
status: archived
category: Fixed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Fix — Clear remaining iOS and macOS build blockers

Resolved the latest Xcode compile errors in both native targets:

- marked the shared AI card date formatter as `nonisolated(unsafe)` so `ISO8601DateFormatter` stops tripping Swift 6 sendability checks
- fixed the voice input controller by storing its completion handler on the main actor and treating `AudioPlayerManager` as the failable optional it is
- removed the `selection` shadowing bug in the macOS root view so the home view can navigate the sidebar state correctly
- verified both targets build successfully with `xcodebuild` for the iOS simulator and macOS

**Files changed:**

- `apps/ios/Todus/Todus/Features/AI/CardViews.swift`
- `apps/ios/Todus/Todus/Features/Voice/VoiceChatViewModel.swift`
- `apps/ios/Todus/Todus/Features/Voice/VoiceInputButton.swift`
- `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`
- `apps/macos/TodusMac/App/MacRootView.swift`
- `apps/ios/Todus/status_ios.md`
- `apps/ios/Todus/status_macos.md`
