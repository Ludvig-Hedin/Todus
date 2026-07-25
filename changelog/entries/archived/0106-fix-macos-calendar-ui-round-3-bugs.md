---
id: 0106
title: "Fix — macOS Calendar UI Round 3 bugs"
status: archived
category: Fixed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Fix — macOS Calendar UI Round 3 bugs

- **Week view all-day events:** Changed from vertical column layout to horizontal per-day-column layout matching Apple Calendar — each day column now shows its own all-day events, preventing the massive tall header
- **Event deduplication:** Holidays and events appearing from multiple calendar sources (e.g. iCloud + Google) are now deduplicated by title+date, keeping only the first occurrence
- **Day view background tint:** Removed blueish accent tint from today's column highlight — now uses neutral `Color.primary.opacity(0.015)` instead of `MacTheme.accent.opacity(0.025)`
- **Segmented picker wrapping:** Fixed "Vie\nw" text wrapping by removing the "View" label text, adding `.labelsHidden()`, and widening frame from 170→180pt

**Files:** `MacCalendarView.swift`, `CalendarService.swift`, `CalendarTimeGridView.swift`
