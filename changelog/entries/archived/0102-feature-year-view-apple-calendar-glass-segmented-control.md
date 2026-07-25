---
id: 0102
title: "Feature — Year view + Apple Calendar glass segmented control"
status: archived
category: Added
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Feature — Year view + Apple Calendar glass segmented control

- **Year view:** New infinitely-scrollable vertical year view showing 21 years (±10) as 4×3 grids of mini-month calendars. Each mini-month shows day numbers, today circled in red, event dot indicators (accent color), weekday initials. Tap a mini-month → navigate to Month view for that month. Auto-scrolls to current year on appear.
- **Glass segmented control:** Replaced native `Picker(.segmented)` with custom `CalendarViewModePicker` using Apple Calendar-style glass/material design — `.ultraThickMaterial` outer pill, `.thinMaterial` selected highlight, `matchedGeometryEffect` for smooth animated sliding, 4 segments (Day/Week/Month/Year). Respects light/dark mode via SwiftUI Material.
- **Header buttons:** Nav arrows and "Today" button now use `.ultraThinMaterial` glass backgrounds instead of solid `surfaceCard` — matches the new glass aesthetic across all header controls.
- **Control sizing:** Unified `headerControlHeight` to 28pt for better tap targets.

**Files:** `MacCalendarView.swift`
