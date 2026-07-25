---
id: 0111
title: "apps/ios/Todus/Todus/Features/Calendar/CalendarMultiDayView.swift:346 — claim that startOfDay(for: e"
status: open
priority: P3
tags: [ios, bug-hunt, code-review-backlog]
files: []
created: 2026-05-20
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-20 — iOS Mobile App Bug Hunt → Unverified leads (investigator candidates that need a closer look)

- `apps/ios/Todus/Todus/Features/Calendar/CalendarMultiDayView.swift:346` — claim that `startOfDay(for: event.startDate)` vs `startOfDay(for: date)` mismatch causes all-day events to render on the wrong day across DST/timezone boundaries.
