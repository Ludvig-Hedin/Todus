---
id: 0060
title: "IOS-0608-P5 — Optimistically removes the open-loop row but never re-adds on server failure (dismiss/complete s"
status: open
priority: P4
tags: [ios, server, qa, code-review-backlog]
files: []
created: 2026-06-08
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-08 — iOS Simulator QA pass → Still open (verified real, deferred — higher-risk / product call / needs backend)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| IOS-0608-P5 | Email | `EmailService.swift:~1106` (`snoozeBriefingOpenLoop`) | 🔵 low | Optimistically removes the open-loop row but never re-adds on server failure (dismiss/complete share the pattern). | Snapshot + restore the briefing on snooze failure. |
