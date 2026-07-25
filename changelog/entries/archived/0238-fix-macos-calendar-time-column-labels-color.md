---
id: 0238
title: "Fix — macOS calendar time column (labels + color)"
status: archived
category: Fixed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Fix — macOS calendar time column (labels + color)

- [Fix] **macOS:** Hour labels disappeared because the foreground gutter used an opaque fill above `hourGridLayer`. The time column is now a clear spacer so labels and tint from `hourGridLayer` show through; `calendarGutterBackground` matches `contentBackground` so the strip is not lighter than the main grid.
- **Files:** `apps/macos/TodusMac/Views/Calendar/CalendarTimeGridView.swift`, `apps/macos/TodusMac/DesignSystem/MacTheme.swift`
