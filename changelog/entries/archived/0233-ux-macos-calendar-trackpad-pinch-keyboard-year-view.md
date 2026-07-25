---
id: 0233
title: "UX — macOS Calendar: trackpad, pinch, keyboard, year view"
status: archived
category: Changed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] UX — macOS Calendar: trackpad, pinch, keyboard, year view

- [UX] **macOS:** Calendar supports **two-finger horizontal** navigation (faster, lower threshold), **pinch in/out** to change view density (Day ↔ Week ↔ Month ↔ Year), **⌘1–4** to jump view modes, **smoother vertical** month paging (`basedOnSize` bounce), and **year view** that scrolls the selected year into view. The **current calendar month** shows a small **red dot** next to the name. Pointer hit tests use the key window’s `isKeyWindow` to avoid `NSApp` main-actor warnings.
- **Files:** `apps/macos/TodusMac/Views/Calendar/CalendarTrackpadNavigation.swift`, `apps/macos/TodusMac/Views/Calendar/MacCalendarView.swift`, `TASK.md`
