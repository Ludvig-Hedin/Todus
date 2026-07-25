---
id: 0110
title: "apps/ios/Todus/Todus/Features/Calendar/CalendarTimeGridView.swift:295 — multi-day event height colla"
status: open
priority: P3
tags: [ios, bug-hunt, code-review-backlog]
files: []
created: 2026-05-20
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-20 — iOS Mobile App Bug Hunt → Unverified leads (investigator candidates that need a closer look)

- `apps/ios/Todus/Todus/Features/Calendar/CalendarTimeGridView.swift:295` — multi-day event height collapse when `rawEndMinutes` is capped at 1440 without recalculating duration on subsequent days. Reproduce with a 2-day event spanning midnight.
