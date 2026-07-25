---
id: 0056
title: "IOS-0608-P4 — Open-thread star is local @State from mail.get; starring from the inbox swipe (now optimistic on"
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
| IOS-0608-P4 | Email | `EmailThreadView.swift:~944/556` | 🟡 med | Open-thread star is local `@State` from `mail.get`; starring from the inbox swipe (now optimistic on `threads`) doesn't update the open detail. | Derive thread `isStarred` from `emailService.threads` labels (single source). |
