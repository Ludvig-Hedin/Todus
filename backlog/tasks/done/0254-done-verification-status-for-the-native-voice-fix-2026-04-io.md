---
id: 0254
title: "DONE Verification status for the native voice fix (2026-04): iOS xcodebuild -project apps/ios/Todus/"
status: done
tags: [task-md, sprint]
files: [apps/macos/TodusMac/App/TodusMacApp.swift]
created: unknown
source: TASK.md
---

> Source context: TASK.md → Current Native Fix Batch

- `DONE` **Verification status for the native voice fix (2026-04):** iOS `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -configuration Debug -destination 'generic/platform=iOS' build` succeeded after the patch. The earlier macOS compile blocker in `apps/macos/TodusMac/App/TodusMacApp.swift` was resolved by awaiting `Task.yield()` inside `initializeApp()`. Any remaining macOS build failures are now downstream of that fixed async-await issue rather than this call site.
