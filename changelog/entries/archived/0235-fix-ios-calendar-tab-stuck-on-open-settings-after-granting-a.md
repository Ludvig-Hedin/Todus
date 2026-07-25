---
id: 0235
title: "Fix — iOS Calendar tab stuck on “Open Settings” after granting access"
status: archived
category: Fixed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Fix — iOS Calendar tab stuck on “Open Settings” after granting access

- [Fix] **iOS:** Tapping **Allow Access** no longer swaps the UI to **Open Settings** before the system dialog finishes. The Calendar tab’s permission flag now refreshes when `requestAccess()` completes (notification) and when switching to the Calendar tab, not only on app foreground.
- [User-facing] Users who already granted **Full Access** in Settings see the real calendar after connecting; no spurious “open Settings” loop.
- **Files:** `apps/ios/Todus/Todus/Services/Calendar/CalendarService.swift`, `apps/ios/Todus/Todus/Navigation/MainTabView.swift`, `apps/ios/Todus/Todus/Features/Calendar/CalendarPermissionView.swift`, `apps/ios/Todus/status_ios.md`
