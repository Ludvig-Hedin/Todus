---
id: 0185
title: "GoogleCalendarService primary fallback ignores hiddenCalendarIds — fixed 2026-07-08 (cold-start conn"
status: done
tags: [ios, bug-hunt, ux, code-review-backlog]
files: []
created: 2026-07-07
source: CODE_REVIEW_BACKLOG.md
---

> Source context: iOS UX assessment + polish + bug hunt — 2026-07-07 (apps/ios) → Deferred (product decisions)

- ~~GoogleCalendarService primary fallback ignores hiddenCalendarIds~~ — fixed 2026-07-08 (cold-start connections with hidden calendars are skipped until their calendar list loads).
