---
id: 0067
title: "BH-0605-6 — When a connection's calendar list isn't loaded yet, GoogleCalendarService.events falls back to fet"
status: open
priority: P3
tags: [ios, macos, bug-hunt, code-review-backlog]
files: []
created: 2026-06-05
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-05 — Bug hunt (iOS + macOS changed files) → Needs attention (not auto-fixed — TODO added in code where noted)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| BH-0605-6 | iOS calendar | `UnifiedCalendarService.swift:168` (TODO) | 🟡 med | When a connection's calendar list isn't loaded yet, `GoogleCalendarService.events` falls back to fetching `primary` and ignores `hiddenCalendarIds` → a hidden primary can briefly reappear. | Ensure `refresh()` populates sources for every connection before `events()`; or respect `hiddenCalendarIds` in the primary fallback. |
