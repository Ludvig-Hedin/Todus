---
id: 0282
title: "DONE Calendar (macOS): MacCalendarView month mode uses a vertically paged month stack (scrollPositio"
status: done
tags: [task-md, sprint]
files: []
created: unknown
source: TASK.md
---

> Source context: TASK.md → macOS UI

- `DONE` **Calendar (macOS)**: `MacCalendarView` month mode uses a vertically paged month stack (`scrollPosition` + `viewAligned` + `scrollBounceBehavior(.basedOnSize)`); horizontal trackpad steps time via `CalendarTrackpadNavigation` (tuned threshold/debounce, `isKeyWindow`); **Day/Week** use a **lenient** horizontal-vs-vertical weight + **⇧+scroll** for time; pinch steps **Day → Week → Month → Year** via `CalendarPinchViewModeCoordinator` (`NSEvent` magnify); **⌘1–4** for view modes; year view scrolls to the focused year + **red dot** on the real-world month; help string documents gestures.
