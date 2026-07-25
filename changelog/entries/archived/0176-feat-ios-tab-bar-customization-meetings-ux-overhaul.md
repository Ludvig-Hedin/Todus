---
id: 0176
title: "Feat — iOS tab bar customization + meetings UX overhaul"
status: archived
category: Changed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] Feat — iOS tab bar customization + meetings UX overhaul

### iOS (`apps/ios/Todus`)

- **MeetingsListView.swift**: Fixed title position via `AppTopHeader` pattern; pull-to-refresh replaces toolbar sync button.
- **AppTab.swift**: Added `description`, `isRequired`, `defaultNavTabs`; conforms to `Codable`.
- **AppServices.swift**: Added `tabBarTabs` (persisted, default 4 tabs), `hasConfiguredTabBarPrompt`, `navigateToSheet`.
- **CustomTabBar.swift**: Accepts `tabs: [AppTab]` — renders user-configured tabs (max 4).
- **MainTabView.swift**: Passes `tabBarTabs`; presents non-tab pages as sheets via `navigateToSheet`.
- **TabBarCustomizationView.swift** (new): Drag-reorder + add/remove tabs in Settings.
- **TabBarOnboardingView.swift** (new): One-time onboarding step for tab bar customization.
- **RootView.swift**: Added tab bar onboarding step in sequence.
- **SettingsView.swift**: Added "Navigation → Tab Bar" section.
- **HomeView.swift**: "More" section surfaces non-tab pages with description + "Open" sheet button.
