---
id: 0094
title: "Polish — macOS Calendar UI Round 5"
status: archived
category: Changed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Polish — macOS Calendar UI Round 5

- **Tap-to-create on time grid:** Tapping empty space in Day/Week time grid opens Apple Calendar's new event dialog at that time (snapped to 30-min slot). Uses `x-apple-calevent://new` URL scheme.
- **Segmented control visibility:** Replaced invisible `.thinMaterial` highlight with solid opaque pill (`Color(white: 0.22)` dark, white light) + shadow. Outer track uses matching solid color (`Color(white: 0.13)` dark) instead of `.ultraThickMaterial`.
- **Unified header controls:** Nav arrows, Today button, and segmented picker all use the same `controlBg` color and `headerControlHeight` (30pt). No more mismatched materials/heights.
- **Month view: prev/next month days visible muted:** Empty cells at month start/end now show actual dates from the previous/next months at 35% opacity — matching Apple Calendar behavior.
- **Month view: instant transitions:** Removed animation on month navigation. `.animation(.none, value: selectedDate)` on the grid prevents the "circus" effect of cells moving around.
- **Month view: scrollable:** Grid remains wrapped in ScrollView for overflow.

**Files:** `MacCalendarView.swift`, `CalendarTimeGridView.swift`
