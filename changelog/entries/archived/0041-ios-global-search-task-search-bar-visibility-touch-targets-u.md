---
id: 0041
title: "iOS — Global search, task search bar visibility, touch targets, UI polish"
status: archived
category: Changed
release_date: 2026-03-27
source: CHANGELOG.md
---

## [2026-03-27] iOS — Global search, task search bar visibility, touch targets, UI polish

### New Features

- **Global search sheet**: Magnifying glass button added as first item in `AppTopHeader` action pill. Opens a full-screen sheet (`GlobalSearchView`) that searches tasks (SwiftData), emails (in-memory threads), calendar events, and people — all local, no extra network calls. Tap results to deep-navigate.
- **Touch targets expanded**: Added `minTouchTarget()` extension (`frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())`) and applied to all small buttons across the app — search clear buttons, sort menu, email thread actions, board column controls, AI chat send/stop/config, voice buttons, attachment delete. Skipped dense equal-width rows (view mode picker, tab bar) to avoid conflicts.

### Bug Fixes / Visual Improvements

- **Task search bar visibility**: Changed background from `surfaceSecondary.opacity(0.55)` (nearly invisible) to `surfacePrimary` (full opacity), and border from `cardBorder` to `strongBorder` — clearly visible in both light and dark mode.
- **Avatar resized and made circular**: `AppTopHeader` avatar is now 34×34pt `Circle()` (was 40×40 `RoundedRectangle`), matching the height of the action pill beside it.
- **Calendar header overlap fixed**: `CalendarContainerView` now accepts `topInset: CGFloat` and applies it via `additionalSafeAreaInsets.top` on the `CalendarViewController`, pushing CalendarKit's scroll content below the SwiftUI `AppTopHeader` overlay.

### Files Changed

- `DesignSystem/AppTheme.swift` — minTouchTarget extension, avatar → circle, global search button + sheet in actionsPill
- `Features/Tasks/TasksTabView.swift` — search bar background/border fix + touch targets
- `Features/Search/GlobalSearchView.swift` — **NEW** — full global search sheet
- `Navigation/MainTabView.swift` — calendar header height measurement + topInset wiring
- `Features/Calendar/CalendarContainerView.swift` — `topInset` param + additionalSafeAreaInsets
- Multiple view files — `.minTouchTarget()` applied to small buttons
