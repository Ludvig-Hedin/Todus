---
id: 0046
title: "QA-0608-5 — The flag is read by canSave/calendarPicker but never set to true anywhere → the \"original calendar"
status: open
priority: P3
tags: [macos, qa, code-review-backlog]
files: []
created: 2026-06-08
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-08 — QA pass (macOS app, pre-TestFlight) → Needs attention (not auto-fixed — verified real, deferred as higher-risk/product calls)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| QA-0608-5 | macOS calendar | `MacEventEditSheet.swift:53/76/225` (`originalCalendarMissing`) | 🟡 med | The flag is read by `canSave`/`calendarPicker` but **never set to `true`** anywhere → the "original calendar removed, force a fresh pick before Save" safety net is dead; editing an event whose source was removed silently falls back to a default calendar. | In `primeForm` `.edit`, when `event.calendarIdentifier` is non-nil but no writable source matches, set `originalCalendarMissing = true` + `selectedCalendarSourceId = nil`. |
