---
id: 0053
title: "IOS-0608-P2 — Per-connection filter chips toggle enabledConnectionIds but recomputeFilteredThreads never filte"
status: open
priority: P2
tags: [ios, server, qa, code-review-backlog]
files: []
created: 2026-06-08
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-08 — iOS Simulator QA pass → Still open (verified real, deferred — higher-risk / product call / needs backend)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| IOS-0608-P2 | Email | `Features/Email/EmailInboxView.swift:1043` + `1414` | 🟠 high | Per-connection filter chips toggle `enabledConnectionIds` but `recomputeFilteredThreads` never filters by it and `EmailThread` has no `connectionId` → toggling a mailbox does nothing. **Dead feature.** | Add `connectionId` to `EmailThread` (backend) + filter, or remove the chips. |
