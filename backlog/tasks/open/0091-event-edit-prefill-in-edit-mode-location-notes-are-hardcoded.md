---
id: 0091
title: "Event-edit prefill — In edit mode location/notes are hardcoded to \"\" because CalendarEvent doesn't carry them;"
status: open
priority: P3
tags: [macos, qa, code-review-backlog]
files: [MacEventEditSheet.swift]
created: 2026-05-28
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-28 — macOS QA deferred features (found, not yet fixed) → Deferred — medium / low (client, but untestable here)

| Area | Where | Severity | Problem | Suggested fix |
|------|-------|----------|---------|---------------|
| Event-edit prefill | `MacEventEditSheet.swift` (~409, edit mode) | 🟡 medium | In edit mode `location`/`notes` are hardcoded to `""` because `CalendarEvent` doesn't carry them; the user sees empty fields and any typed Location is silently discarded on save (`updateEvent` has no location param). | Carry `location`/`notes` on `CalendarEvent` (or fetch the `EKEvent`) and round-trip them through `CalendarService.updateEvent`. |
