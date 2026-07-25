---
id: 0101
title: "apps/macos/TodusMac/Services/Tasks/LocalTaskParsingService.swift:75 — daysAhead <= 0 { daysAhead += 7 } — typi"
status: open
priority: P3
tags: [macos, bug-hunt, code-review, code-review-backlog]
files: []
created: 2026-05-20
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-20 — Bug Hunt: macOS app main user flows → Needs human review (3)

| File:line | Severity | Problem | Suggested fix |
|-----------|----------|---------|---------------|
| `apps/macos/TodusMac/Services/Tasks/LocalTaskParsingService.swift:75` | warning | `daysAhead <= 0 { daysAhead += 7 }` — typing "monday" on a Monday schedules next Monday, not today. May be intentional but worth surfacing to product. | Decide policy: (a) same-day-keyword keeps today, (b) same-day-keyword rolls forward. If (a), change to `daysAhead < 0`. |
