---
id: 0263
title: "Fix — iOS HomeView build blockers resolved"
status: archived
category: Fixed
release_date: 2026-04-26
source: CHANGELOG.md
---

## [2026-04-26] Fix — iOS HomeView build blockers resolved

- [Fix] **iOS Home no longer fails to compile after the Home dashboard refactor.** `HomeView` now restores the missing briefing hero/feed adapters, the proactive-suggestion loading flag, and the thread-sheet route state referenced by the updated top-level layout.
- [Architectural] **Home’s refactored top section is bridged back to the existing sections instead of duplicated.** The new hero/checklist/feed composition now maps to the already-implemented setup, assistant-briefing, and proactive-nudge sections so the file builds without introducing a second Home implementation.
- [Verification] **Native iOS build passed.** `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -destination 'generic/platform=iOS Simulator' build` succeeded after the patch.
- [Files] `apps/ios/Todus/Todus/Features/Home/HomeView.swift`, `CHANGELOG.md`, `TASK.md`
