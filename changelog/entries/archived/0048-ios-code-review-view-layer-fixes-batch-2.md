---
id: 0048
title: "iOS Code Review — View Layer Fixes (Batch 2)"
status: archived
category: Fixed
release_date: 2026-03-27
source: CHANGELOG.md
---

## [2026-03-27] iOS Code Review — View Layer Fixes (Batch 2)

### Bug Fixes & Improvements

- **CalendarViewController.swift**: Added `inFlightDates` Set to prevent duplicate background EventKit fetches for the same day during rapid scrolling.
- **EmailConnectView.swift**: Added `@State isLoading` and `errorMessage`, wrapped Task in do-catch, disabled button while loading.
- **EmailRowView.swift**: Replaced hardcoded `Color.blue` with `AppTheme.accentBlue` for the unread indicator. Added combined accessibility label.
- **BoardView.swift**: Added `taskChangeSignature` computed property to detect status-only changes that `@Query` `onChange(of:)` misses.
- **CustomTabBar.swift** (active): Removed ineffective `.tracking()` modifier from Image views (only works on Text). Removed unused `iconTracking` constant.
- **TaskDetailSheet.swift**: Pass trimmed folder name to `createFolder`. Added `.accessibilityLabel("Create folder")` to the create-folder button.
- **TaskRowView.swift**: Increased checkbox tap target from 36x36 to 44x44pt per Apple HIG (visual icon stays at 18pt).
- **CalendarPermissionView.swift**: Updated Settings path from "Privacy → Calendars" to "Privacy & Security → Calendars".
- **SenderAvatarView.swift**: Changed `.task { urlIndex += 1 }` in failure case to `.onAppear` to prevent re-run loops. Reordered `fetchCandidateURLs` to prioritize backend-resolved URLs over local fallbacks.
- **AIChatView.swift + AIChatService.swift**: Retry button now actually replays the last user message via new `retry()` method instead of just clearing the error.
- **Archived CustomTabBar.swift**: Added accessibility labels to AI/create action buttons and tab buttons. Fixed `glassEffect(in:)` → `glassEffect(.regular, in:)` to match correct iOS 26 API. Removed ineffective `.tracking()` from Image views.

### Files Changed

- `Features/Calendar/CalendarViewController.swift`
- `Features/Calendar/CalendarPermissionView.swift`
- `Features/Email/EmailConnectView.swift`
- `Features/Email/EmailRowView.swift`
- `Features/Email/SenderAvatarView.swift`
- `Features/Tasks/BoardView.swift`
- `Features/Tasks/CustomTabBar.swift`
- `Features/Tasks/TaskDetailSheet.swift`
- `Features/Tasks/TaskRowView.swift`
- `Features/AI/AIChatView.swift`
- `Services/AI/AIChatService.swift`
- `Navigation/archived/CustomTabBar.swift`
