# Tab Bar Backup — Pre-6-Tab Refactor

Snapshot of the tab bar before the 6-tab / FAB-create refactor (2026-05-24).

## Previous tab order (5 tabs)

| Position | Tab | Icon |
|----------|-----|------|
| 1 | Home | house / house.fill |
| 2 | Tasks | checklist |
| 3 | **Create** (placeholder) | plus.circle.fill |
| 4 | Email | envelope / envelope.fill |
| 5 | Calendar | calendar / calendar.badge.plus |

- Create tab was a placeholder — tapping it opened `CreateSheet` then snapped back to the previous tab.
- Meetings was accessible only via Home's "More" section or `navigateToSheet`, shown as a sheet, NOT a real tab.
- Labels were shown below each icon (native `.tabItem { Label(...) }` behaviour).
- Tab bar height was the native iOS 18 default (~49 pt + bottom safe area).
- New-item button: the central create tab.
- AI button: right-side FAB (`sparkles` gradient, `fabSize` 58 pt).

## Revert instructions

1. Restore `AppTab.swift` — remove `case docs` and the associated switch branches.
2. Restore `MainTabView.swift`:
   - Remove `docsTabId` / `meetingsTabId` state, re-add `createTabId`.
   - Remove `customTabBar`, `orderedTabs`, `createFAB`.
   - Restore `.toolbar(.hidden, for: .tabBar)` removal (i.e. delete it so native tab bar shows again).
   - Restore `tabView` with the 5 `.tabItem` tabs including the create placeholder.
   - Restore `onChange(of: selectedTab)` to include the `new == .create` branch.
   - Restore `visibleContentTabs` to `[.home, .tasks, .email, .calendar]`.
   - Restore meetings-as-sheet in `navigateTo` / `navigateToSheet` handlers.
   - Restore FAB positioning: `.overlay(alignment: .bottomTrailing)` with `.padding(.bottom, 68)`.
   - Remove `.safeAreaInset(edge: .bottom)` for custom tab bar.
3. The git history has the pre-refactor state on `main` — run `git diff HEAD~1 apps/ios` to see the exact diff.

## Original MainTabView.swift key sections

```swift
// Tab order
TabView(selection: $selectedTab) {
    NavigationStack { HomeView() }
        .tabItem { Label(AppTab.home.title, systemImage: AppTab.home.inactiveIcon()) }
        .tag(AppTab.home)

    NavigationStack { TasksTabView() }
        .tabItem { Label(AppTab.tasks.title, systemImage: AppTab.tasks.inactiveIcon()) }
        .tag(AppTab.tasks)

    AppTheme.backgroundTop.ignoresSafeArea()
        .tabItem { Label(AppTab.create.title, systemImage: AppTab.create.inactiveIcon()) }
        .tag(AppTab.create)

    NavigationStack { EmailInboxView() }
        .tabItem { Label(AppTab.email.title, systemImage: AppTab.email.inactiveIcon()) }
        .tag(AppTab.email)

    NavigationStack { CalendarTabView() /* + permission guard */ }
        .tabItem { Label(AppTab.calendar.title, systemImage: AppTab.calendar.inactiveIcon()) }
        .tag(AppTab.calendar)
}

// FAB placement
.overlay(alignment: .bottomTrailing) {
    if !services.hideTabBar && !showCreateSheet {
        aiFAB
            .ignoresSafeArea(.keyboard)
            .padding(.trailing, 18)
            .padding(.bottom, 68)
    }
}
```
