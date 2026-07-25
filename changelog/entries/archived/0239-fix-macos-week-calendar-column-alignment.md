---
id: 0239
title: "Fix — macOS Week calendar column alignment"
status: archived
category: Fixed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Fix — macOS Week calendar column alignment

- [UX] **macOS:** Week view day headers, all-day row, and the scrolling time grid share one measured column width (via `GeometryReader` + `MacTheme.calendarDayColumnWidth`) so columns stay aligned with the day grid. The time-label gutter uses `calendarGutterBackground`; horizontal hour lines only run to the right of that column, not under the stamps.
- **Files:** `apps/macos/TodusMac/Views/Calendar/MacCalendarView.swift`, `apps/macos/TodusMac/Views/Calendar/CalendarTimeGridView.swift`, `apps/macos/TodusMac/DesignSystem/MacTheme.swift`
