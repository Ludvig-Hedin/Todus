---
id: 0068
title: "iOS Tab Bar — HIG-Compliant Layout, Calendar Fix, Floating Action Pill"
status: archived
category: Fixed
release_date: 2026-03-27
source: CHANGELOG.md
---

## [2026-03-27] iOS Tab Bar — HIG-Compliant Layout, Calendar Fix, Floating Action Pill

### Structural Fix

- **Separated tabs from actions**: Removed `tabViewBottomAccessory` and `safeAreaInset` accessory patterns. Both caused the action buttons to stretch full-width and merge visually with the tab bar, violating Apple HIG (tabs = navigation, actions ≠ tabs).
- **Floating action pill**: AI and Create buttons now live in a compact vertical pill (~44×88pt, glass material) that floats bottom-right above the tab bar — clearly a separate control, not a tab.

### Calendar Clipping Fix

- **Removed double NavigationStack**: `CalendarContainerView` creates its own `UINavigationController` internally. Wrapping it in another `NavigationStack` from `tabContent(for:)` broke safe-area propagation, causing the bottom ~30% of calendar content to be clipped behind the tab bar.

### Tint Color Fix

- **`AppTheme.accentBlue`**: Changed from `Color(red: 0.25, green: 0.48, blue: 1.0)` (purple-shifted) to `Color.blue` (system iOS blue, matches `AppPrimaryButtonStyle`).

### Files Updated

- `apps/ios/Todus/Todus/Navigation/MainTabView.swift`
- `apps/ios/Todus/Todus/DesignSystem/AppTheme.swift`
