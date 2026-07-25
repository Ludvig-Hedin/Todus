---
id: 0112
title: "apps/ios/Todus/Todus/Services/Calendar/GoogleCalendarService.swift:316–333 — fetchCalendars(for:) ca"
status: open
priority: P3
tags: [ios, bug-hunt, code-review-backlog]
files: []
created: 2026-05-20
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-20 — iOS Mobile App Bug Hunt → Unverified leads (investigator candidates that need a closer look)

- `apps/ios/Todus/Todus/Services/Calendar/GoogleCalendarService.swift:316–333` — `fetchCalendars(for:)` catches errors and returns `[]` while clearing `scopeMissing`. Conflates "no scope" with "network failure". UI gives no retry banner.
