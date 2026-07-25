---
id: 0058
title: "iOS Calendar — create events on tap (no long-press required)"
status: archived
category: Changed
release_date: 2026-03-27
source: CHANGELOG.md
---

## [2026-03-27] iOS Calendar — create events on tap (no long-press required)

### Fixed

- **Tap-to-create on timeline**: Tapping an empty time slot in the calendar now immediately starts creating a new event.
- **Long-press still supported**: Existing long-press creation behavior remains available.

### Files

- `apps/ios/Todus/Todus/Features/Calendar/CalendarViewController.swift`
