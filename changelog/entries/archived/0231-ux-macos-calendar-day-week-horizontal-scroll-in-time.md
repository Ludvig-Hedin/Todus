---
id: 0231
title: "UX — macOS Calendar: Day/Week horizontal scroll in time"
status: archived
category: Changed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] UX — macOS Calendar: Day/Week horizontal scroll in time

- [UX] **macOS:** In **Day** and **Week** views, two-finger **left/right** is easier to trigger over the vertical hour grid (relaxed `adx`/`ady` weight). **Shift + scroll** moves by day/week so the time grid is not also scrolled. Month/Year behavior unchanged.
- **Files:** `apps/macos/TodusMac/Views/Calendar/CalendarTrackpadNavigation.swift`, `apps/macos/TodusMac/Views/Calendar/MacCalendarView.swift`
