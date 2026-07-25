---
id: 0057
title: "iOS Tab Screens — unified top header across all tabs"
status: archived
category: Changed
release_date: 2026-03-27
source: CHANGELOG.md
---

## [2026-03-27] iOS Tab Screens — unified top header across all tabs

### Changed

- **Shared top header**: Added a reusable `AppTopHeader` for tab root screens with:
  - user avatar on the top-left (profile image or initials fallback),
  - large page title below,
  - dual-action pill on the top-right.
- **Dual actions**: Added two utility actions in the right pill:
  - notifications button (opens iOS notification settings),
  - more/settings button (opens app Settings sheet).
- **Applied on all tab roots**:
  - Home
  - Tasks
  - Inbox
  - Calendar

### Files

- `apps/ios/Todus/Todus/DesignSystem/AppTheme.swift`
- `apps/ios/Todus/Todus/Features/Home/HomeView.swift`
- `apps/ios/Todus/Todus/Features/Tasks/TasksTabView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`
- `apps/ios/Todus/Todus/Navigation/MainTabView.swift`
