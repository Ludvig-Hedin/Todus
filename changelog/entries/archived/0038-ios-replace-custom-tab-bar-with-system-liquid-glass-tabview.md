---
id: 0038
title: "iOS — Replace Custom Tab Bar with System Liquid Glass TabView"
status: archived
category: Changed
release_date: 2026-03-26
source: CHANGELOG.md
---

## [2026-03-26] iOS — Replace Custom Tab Bar with System Liquid Glass TabView

### Changed

- **MainTabView**: Replaced the hand-made HStack tab bar with iOS 26's system `TabView` using the new `Tab("Title", systemImage:, value:)` API. The system now renders the Liquid Glass floating bar automatically.
- **Tab selection persistence**: Switched from `@State` to `@SceneStorage("selectedTab")` so the last-used tab is restored across scene sessions.
- **Minimize on scroll**: Added `.tabBarMinimizeBehavior(.onScrollDown)` so the bar shrinks to a pill when scrolling content.
- **Bottom accessory**: Moved the "+" create and AI sparkles buttons into `.tabViewBottomAccessory` — they now float correctly above the glass bar.
- **Accent colors**: Added `AppTheme.accentBlue` (rgb 0.25/0.48/1.0) and `AppTheme.mutedGray` to the design system. Active tab uses accent blue via `.tint()`.
- **AppTab.title**: Added a `title` computed property for human-readable tab labels.
- **Removed padding hacks**: Removed 60–90pt bottom padding workarounds in TasksTabView, EmailInboxView, and EmailThreadView that compensated for the old custom bar.

### Files Updated

- `apps/ios/Todus/Todus/Navigation/MainTabView.swift`
- `apps/ios/Todus/Todus/Navigation/AppTab.swift`
- `apps/ios/Todus/Todus/DesignSystem/AppTheme.swift`
- `apps/ios/Todus/Todus/Features/Tasks/TasksTabView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift`
