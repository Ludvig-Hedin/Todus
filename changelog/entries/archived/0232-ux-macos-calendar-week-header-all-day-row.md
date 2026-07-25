---
id: 0232
title: "UX — macOS Calendar week header + all-day row"
status: archived
category: Changed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] UX — macOS Calendar week header + all-day row

- [UX] **macOS:** Calendar pane header shows only the month/year title (sidebar app icon removed duplicate mark). Week **all-day** row: label uses a fixed-width `ZStack` so `padding` no longer widens the gutter (day headers + hourly grid + all-day columns align). **all-day** text has no extra background; `calendarAllDayBg` applies only to the day columns, not the label column.
- **Files:** `apps/macos/TodusMac/Views/Calendar/MacCalendarView.swift`
