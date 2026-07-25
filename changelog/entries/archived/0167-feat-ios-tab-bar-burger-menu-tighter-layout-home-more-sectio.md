---
id: 0167
title: "Feat — iOS tab bar: burger menu, tighter layout, Home More section + Docs"
status: archived
category: Docs
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] Feat — iOS tab bar: burger menu, tighter layout, Home More section + Docs

### iOS (`apps/ios/Todus`)

- **CustomTabBar.swift**: Burger `line.3.horizontal` button now first in the nav pill (replaces ellipsis in action pill). Removed ellipsis from action pill — right pill is now just AI + create. Narrowed all button frames (62→50px nav, 54→50px action). Reduced pill padding and HStack spacing for a tighter look.
- **AppTab.swift**: `defaultNavTabs` remains `[home, tasks, email, calendar]`; the burger sits outside the configured tabs and keeps the visible pill from feeling cramped.
- **AppServices.swift**: `tabBarTabs` decode still clamps invalid values, but the configured tab set remains capped at 4.
- **MoreSheetView.swift**: Added Meetings and Calendar (when not in tab bar) as NavigationLinks. Added "Customize Tab Bar" shortcut. Now uses `@Environment(AppServices.self)` to conditionally show items.
- **HomeView.swift**: Refactored `moreSection` — tapping nav cards opens a sheet (meetings) or navigates the tab (calendar). Added permanent Docs card (always visible, opens as a sheet). Replaced "Open" button pill with a chevron for a standard iOS row feel.
- **TabBarCustomizationView.swift**: Kept the customization UI aligned with the 4-tab cap and the burger slot.
- **TabBarOnboardingView.swift**: Kept the onboarding preview aligned with the 4-tab cap and the burger slot.
