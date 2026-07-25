---
id: 0050
title: "QA-0608-9 — A thread opened from search (not in threads) marks-read fire-and-forget; optimistic update + rollb"
status: open
priority: P4
tags: [macos, qa, code-review-backlog]
files: []
created: 2026-06-08
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-08 — QA pass (macOS app, pre-TestFlight) → Needs attention (not auto-fixed — verified real, deferred as higher-risk/product calls)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| QA-0608-9 | macOS email | `EmailService.swift:1186` (`markAsRead`) | 🔵 low | A thread opened from search (not in `threads`) marks-read fire-and-forget; optimistic update + rollback are no-ops and the failure is set on a service field the thread view doesn't display → possible unread-count desync. | Reconcile mark-read against the detail cache too, or accept server truth on next `loadThreads`. |
