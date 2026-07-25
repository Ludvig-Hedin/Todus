---
id: 0103
title: "Fix — macOS Calendar UI Round 4"
status: archived
category: Fixed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Fix — macOS Calendar UI Round 4

- **Week view header too tall (ROOT CAUSE):** `Color.clear.frame(width:)` gutter spacer expanded vertically — replaced with `Text("")` + `.fixedSize(horizontal: false, vertical: true)` wrapper
- **Header buttons:** Nav arrows now fully circular (24pt `Circle()`), "Today" pill same 24pt height, all controls aligned
- **Month view scrolling:** Wrapped LazyVGrid in `ScrollView(.vertical)` inside GeometryReader
- **Event deduplication:** Holidays from multiple calendars deduplicated by title+date
- **Day view tint:** Removed blueish accent highlight, now neutral
- **Segmented picker:** Fixed text wrapping with `.labelsHidden()` + wider frame

**Files:** `MacCalendarView.swift`, `CalendarService.swift`, `CalendarTimeGridView.swift`
