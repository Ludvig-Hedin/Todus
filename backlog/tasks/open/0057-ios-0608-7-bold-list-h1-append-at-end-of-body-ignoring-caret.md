---
id: 0057
title: "IOS-0608-7 — Bold/list/H1 append at end of body, ignoring caret."
status: open
priority: P4
tags: [ios, server, qa, code-review-backlog]
files: [EmailComposeView.swift]
created: 2026-06-08
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-08 — iOS Simulator QA pass → Still open (verified real, deferred — higher-risk / product call / needs backend)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| IOS-0608-7 | Email | `EmailComposeView.swift` formatting toolbar | 🔵 low | Bold/list/H1 append at end of body, ignoring caret. | Insert at `RichComposerInput` selection range. |
