---
id: 0114
title: "Auto-fixed in this run"
status: done
tags: [code-review, code-review-backlog]
files: []
created: 2026-05-02
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-02 — Full-repo Review

## Auto-fixed in this run

| ID | File:line | Status | What changed |
|----|-----------|--------|--------------|
| AF-1 | `apps/macos/TodusMac/Domain/SnoozeOption.swift:35` | auto-fixed | Replaced dead `var components = calendar.dateComponents(...)` (only `.weekday` used) with single `calendar.component(.weekday, from: now)` call. No behavior change. |
| AF-2 | `apps/macos/TodusMac/Services/Email/EmailService.swift:218` | auto-fixed | Doc-comment said "detached task" but the implementation uses `Task { ... }` (an independent top-level Task, not `Task.detached`). Updated wording to match the inline comment further down. Comment-only. |
