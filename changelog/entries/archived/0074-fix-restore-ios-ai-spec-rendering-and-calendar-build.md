---
id: 0074
title: "Fix — Restore iOS AI spec rendering and calendar build"
status: archived
category: Fixed
release_date: 2026-03-29
source: CHANGELOG.md
---

## [2026-03-29] Fix — Restore iOS AI spec rendering and calendar build

Resolved the current Xcode build failures in the native iOS app:

- replaced the recursive `some View` renderer in `ChatUISpecView` with `AnyView`-based recursion so SwiftUI type inference no longer feeds itself
- marked `EKWrapper` as `@unchecked Sendable` to satisfy Swift 6 concurrency checking when calendar event wrappers move from the background EventKit fetch back to the main thread
- verified the project builds successfully with `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -destination 'generic/platform=iOS Simulator' build`

**Files changed:**

- `apps/ios/Todus/Todus/Features/AI/ChatUISpecView.swift`
- `apps/ios/Todus/Todus/Features/Calendar/EKWrapper.swift`
- `apps/ios/Todus/status_ios.md`
- `apps/ios/Todus/TASK.md`
