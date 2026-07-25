---
id: 0368
title: "DONE Fixed the macOS Xcode target graph for shared auth: TodusMac.xcodeproj now resolves TodusAuth f"
status: done
tags: [task-md, sprint]
files: [App/ConnectionsService.swift]
created: unknown
source: TASK.md
---

> Source context: TASK.md → Build Fixes

- `DONE` Fixed the macOS Xcode target graph for shared auth: `TodusMac.xcodeproj` now resolves `TodusAuth` from `packages/swift-auth`, excludes the dead `App/ConnectionsService.swift` placeholder, and builds cleanly again.
