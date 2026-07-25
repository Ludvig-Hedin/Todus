---
id: 0200
title: "Fix — iOS CreateSheet Floating Position"
status: archived
category: Fixed
release_date: 2026-04-06
source: CHANGELOG.md
---

## [2026-04-06] Fix — iOS CreateSheet Floating Position

- [Fix] iOS `CreateSheet`: Added `.ignoresSafeArea(.container, edges: .bottom)` to the main `ZStack` so it properly ignores the safe area inset injected by `MainTabView`. This fixes the issue where the input UI was pushed to the top of the screen by double-counting the safe area and keyboard height.
- **Files:** `apps/ios/Todus/Todus/Navigation/CreateSheet.swift`
