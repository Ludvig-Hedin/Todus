---
id: 0288
title: "DONE Native Meetings legacy schema fallback (2026-04): meet.listMeetings / getMeeting / getIntegrati"
status: done
tags: [task-md, sprint]
files: []
created: unknown
source: TASK.md
---

> Source context: TASK.md → macOS UI

- `DONE` **Native Meetings legacy schema fallback (2026-04):** `meet.listMeetings` / `getMeeting` / `getIntegration` / `syncFromCalendar` no longer hard-fail when production is missing newer `mail0_meet_integration` settings or retention columns. The server reads the legacy integration shape, applies safe defaults, and disables retention pruning until the DB has the retention columns.
