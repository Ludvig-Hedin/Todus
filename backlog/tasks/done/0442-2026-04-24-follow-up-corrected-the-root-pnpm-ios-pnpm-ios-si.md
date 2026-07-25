---
id: 0442
title: "2026-04-24 follow-up: corrected the root pnpm ios, pnpm ios:simulator, and pnpm ios:build: entry poi"
status: done
tags: [task-md, sprint]
files: [apps/ios/Todus/Todus.xcodeproj]
created: 2026-03-01
source: TASK.md
---

> Source context: TASK.md → Session Notes (2026-03-01)

- 2026-04-24 follow-up: corrected the root `pnpm ios`, `pnpm ios:simulator`, and `pnpm ios:build:*` entry points so they target `apps/ios/Todus/Todus.xcodeproj` instead of the archived Expo app under `apps/archived/archived-rn`. Verified the real native app with `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`.
