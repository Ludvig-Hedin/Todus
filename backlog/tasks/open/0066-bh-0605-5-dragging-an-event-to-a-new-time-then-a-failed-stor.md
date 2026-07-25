---
id: 0066
title: "BH-0605-5 — Dragging an event to a new time then a failed store.save leaves the pill visually moved (no reload"
status: open
priority: P4
tags: [ios, macos, bug-hunt, code-review-backlog]
files: []
created: 2026-06-05
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-05 — Bug hunt (iOS + macOS changed files) → Needs attention (not auto-fixed — TODO added in code where noted)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| BH-0605-5 | iOS calendar | `CalendarViewController.swift:~329` (`didUpdate`) | 🔵 low | Dragging an event to a new time then a failed `store.save` leaves the pill visually moved (no reload fires) — looks saved but isn't. | On save failure, drop the affected day's cache + `reloadData`; or guard `allowsContentModifications` before save. |
