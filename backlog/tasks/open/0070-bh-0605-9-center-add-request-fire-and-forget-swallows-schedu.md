---
id: 0070
title: "BH-0605-9 — center.add(request) fire-and-forget swallows scheduling errors (e.g. the 64-pending OS cap) → a re"
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
| BH-0605-9 | iOS notifications | `NotificationService.swift:124/157/253/277` | 🔵 low | `center.add(request)` fire-and-forget swallows scheduling errors (e.g. the 64-pending OS cap) → a reminder silently never fires. | Use the completion-handler form and log errors, or `Task { try? await center.add }` like the email-reminder path. |
