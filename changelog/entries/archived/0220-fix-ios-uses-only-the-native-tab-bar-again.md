---
id: 0220
title: "Fix — iOS uses only the native tab bar again"
status: archived
category: Fixed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Fix — iOS uses only the native tab bar again

- [Fix] **iOS:** `MainTabView` no longer hides the native `TabView` tab bar or overlays the floating `CustomTabBar`, so the duplicate bottom navigation chrome is gone and only the standard iOS tab bar remains visible.
- [User-facing] The native tab bar now uses labeled `tabItem`s for **Home**, **Tasks**, **Email**, **Calendar**, and **Meetings**.
- [Fix] **iOS onboarding/settings:** the tab-bar customization onboarding step is skipped entirely, its progress count drops from 5 steps to 4, and the Settings entry for customizing the floating tab bar is no longer surfaced.
- [Architectural] The custom tab-bar code is intentionally kept in the codebase for later reuse, but runtime state now defaults `hasConfiguredTabBarPrompt` to complete so older installs do not get stuck on the removed step.
- [Files] `apps/ios/Todus/Todus/Navigation/MainTabView.swift`, `apps/ios/Todus/Todus/App/RootView.swift`, `apps/ios/Todus/Todus/App/AppServices.swift`, `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`, `apps/ios/Todus/status_ios.md`, `apps/ios/Todus/TASK.md`, `CHANGELOG.md`
