---
id: 0109
title: "apps/ios/Todus/Todus/Services/Reminders/AppleRemindersSyncService.swift:359 — off-by-one in maxCoale"
status: open
priority: P3
tags: [ios, bug-hunt, code-review-backlog]
files: []
created: 2026-05-20
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-20 — iOS Mobile App Bug Hunt → Unverified leads (investigator candidates that need a closer look)

- `apps/ios/Todus/Todus/Services/Reminders/AppleRemindersSyncService.swift:359` — off-by-one in `maxCoalescedRetries` (allows N+1 attempts). Need to read the retry counter increment vs guard to confirm.
