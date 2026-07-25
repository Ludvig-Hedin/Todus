---
id: 0054
title: "IOS-0608-2 — Long-press create-event no-ops with no feedback when no writable calendar (rarer than first repor"
status: open
priority: P3
tags: [ios, server, qa, code-review-backlog]
files: []
created: 2026-06-08
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-08 — iOS Simulator QA pass → Still open (verified real, deferred — higher-risk / product call / needs backend)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| IOS-0608-2 | Calendar | `CalendarViewController.swift:~280` | 🟡 med | Long-press create-event no-ops with no feedback when no writable calendar (rarer than first reported — `createNewEvent` only nils on missing `eventStore`/date math; the nil-calendar case fails at save). | Surface a toast when `defaultCalendarForNewEvents` is nil. |
