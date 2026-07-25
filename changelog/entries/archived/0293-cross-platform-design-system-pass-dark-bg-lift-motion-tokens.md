---
id: 0293
title: "Cross-platform design system pass: dark bg lift, motion tokens, accent palette, DS viewer + docs"
status: archived
category: Docs
release_date: 2026-05-21
source: CHANGELOG.md
---

## [2026-05-21] Cross-platform design system pass: dark bg lift, motion tokens, accent palette, DS viewer + docs

First unified pass on tokens across `apps/web`, `apps/ios/Todus`, `apps/macos/TodusMac`. Five slices:

- **Dark mode background lifted to Apple system dark `#1c1c1e`** (`Color(white: 0.109)`) on iOS + macOS — previous iOS `#0C0C0C` and macOS `~#141414` were too inky vs reference. Surface tokens stepped in ~0.04–0.06 white increments to preserve hierarchy. Hardcoded `Color(white:)` literals across `MacSettingsView`, `MacCalendarView`, `MacAssistantPanel`, `SettingsView.swift:1758`, and `CalendarViewController.swift:55` refactored to token references so future bg sweeps stay in one place.
- **Motion tokens** — new `Motion.fast/.base/.slow` enums on `AppTheme.swift` (iOS) and `MacTheme.swift` (macOS); new `--motion-duration-fast/base/slow` + `--motion-easing-standard/emphasized` CSS custom properties on web (`apps/web/app/globals.css`). Replaced inline `.snappy(...)`, `.easeOut(...)`, `.easeInOut(...)`, `.spring(...)` durations across ~15 iOS callsites (CustomTabBar, BoardColumnView, BoardTaskCard, TaskRowView, TaskTableView, CalendarTabView, CalendarNavBar, CalendarListView, TabBarOnboardingView, TabBarCustomizationView, ToastOverlay), ~17 macOS callsites (MacSidebarView, MacRootView, MacAssistantPanel, MacCalendarView, MacToastOverlay, MacTasksView, all Email/Home/Voice/Meetings/Docs views), and 9 web shadcn/ui files (button, input, dialog, sheet, accordion, navigation-menu, nav-main, app-sidebar, sidebar). Dropdowns, panels, hover states, and tap feedback now share a tunable duration vocabulary; previously instant transitions on sidebars and menus animate smoothly.
- **iOS accent palette parity** — ported the 6-color accent system (blue / indigo / teal / green / orange / rose) from macOS + web to iOS. New `AppTheme.Accents` enum + `AccentPreference` stored on `AppServices` (UserDefaults-backed, default `.blue`). Picker row added to `AppearanceSettingsView`. Hardcoded `accentBlue` literals on `AuthView` and `StartupOnboardingView` swapped for `AppTheme.Accents.blue`.
- **Hidden Design System viewer on all three platforms**, gated to `TODUS_ALLOWLISTED_EMAILS` (Swift) / `VITE_TODUS_ALLOWLISTED_EMAILS` (web) allowlist:
  - Web: `/settings/design-system` (new route in `apps/web/app/(routes)/settings/design-system/page.tsx`). `clientLoader` redirects non-allowlisted users to `/settings/general`. Settings nav entry conditionally rendered. New `apps/web/lib/developer-access.ts` mirrors the Swift `TodusDeveloperAccess.isAllowlisted(email:)` pattern.
  - iOS: `Features/DesignSystem/DesignSystemView.swift` + `DSTokenRow.swift`. NavigationLink from `SettingsView` developer section, gated by `TodusDeveloperAccess.isAllowlisted`. Xcode project updated.
  - macOS: `Views/Settings/MacDesignSystemView.swift`. Sheet-presenting button in `MacSettingsView` under the existing developer-mode gate (which already requires allowlist). Pbxproj updated.
  - Each viewer renders: Colors (light + dark swatches with hex / token name), Accent palette, Typography (samples per scale), Radius (6-tier chips), Spacing (4 / 8 grid), Shadows (web), Components gallery (buttons, cards, badges, dropdowns, dialogs, sheets, etc.), Motion (live demo blocks animating `fast/base/slow`). Each section ends with a "How to change" callout pointing to the source-of-truth file + line range.
- **Documentation** — new `DESIGN_SYSTEM.md` (canonical token reference with cross-platform mapping table) and `DESIGN_SYSTEM_INCONSISTENCIES.md` (resolved + tracked gaps) at repo root. Design System section added to `CLAUDE.md`, `AGENTS.md`, and `APPS_ARCHITECTURE.md` so future agents know the system exists and where to update it.

Verified: `xcodebuild` builds succeeded on Todus (iOS) and TodusMac (macOS). `tsc --noEmit` + `oxlint --deny-warnings` clean on touched web files.
