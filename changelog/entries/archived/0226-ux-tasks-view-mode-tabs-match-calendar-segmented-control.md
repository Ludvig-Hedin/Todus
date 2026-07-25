---
id: 0226
title: "UX — Tasks view-mode tabs match Calendar segmented control"
status: archived
category: Changed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] UX — Tasks view-mode tabs match Calendar segmented control

- [UI] iOS and macOS Tasks `List` / `Board` / `Table` (and iOS `Dates`) picker now use the same **recessed track** (0.88 light / 0.13 dark) and **selected pill** (white / 0.22 dark) plus light shadow as the macOS **Calendar** `Day|Week|Month|Year` control — much clearer active state in light and dark mode.
- [Architectural] `MacTheme.segmentedTrack` / `MacTheme.segmentedSelectedPill` and `AppTheme` equivalents; Calendar’s picker reuses the macOS theme tokens.
- **Files:** `MacTheme.swift`, `AppTheme.swift`, `MacTasksView.swift`, `TasksTabView.swift`, `MacCalendarView.swift`
