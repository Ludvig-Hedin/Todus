---
id: 0242
title: "Fix — iOS Home scroll under tab bar"
status: archived
category: Fixed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Fix — iOS Home scroll under tab bar

- [UX] **iOS:** Home dashboard scroll no longer hard-clips at the tab bar. Matches Tasks: `ScrollView` uses `contentMargins(.bottom, 130, for: .scrollContent)` and drops `.clipped()` so content can scroll with the same bottom inset as the Tasks list.
- **Files:** `apps/ios/Todus/Todus/Features/Home/HomeView.swift`
