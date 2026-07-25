---
id: 0275
title: "Fix — iOS native tab bar restores center create action"
status: archived
category: Fixed
release_date: 2026-04-26
source: CHANGELOG.md
---

## [2026-04-26] Fix — iOS native tab bar restores center create action

- [Fix] **iOS:** `MainTabView` now uses the native tab order **Home / Tasks / + / Email / Calendar**. The middle `+` is action-only and immediately opens `CreateSheet`.
- [Fix] **iOS:** `Meetings` is no longer a visible native tab, but its screen remains in code and can still be presented from other flows.
- [User-facing] Home content now uses native-tab-bar spacing instead of reserving the old floating custom-bar height.
- [Files] `apps/ios/Todus/Todus/Navigation/MainTabView.swift`, `apps/ios/Todus/Todus/Features/Home/HomeView.swift`, `CHANGELOG.md`, `apps/ios/Todus/TASK.md`
