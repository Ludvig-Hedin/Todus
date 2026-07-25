---
id: 0047
title: "QA-0608-6 — Comments say the calendar picker is \"disabled in edit mode\" but it has no .disabled(); changing it"
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
| QA-0608-6 | macOS calendar | `MacEventEditSheet.swift:250` (calendar picker) | 🔵 low | Comments say the calendar picker is "disabled in edit mode" but it has no `.disabled()`; changing it silently **moves** the event to another calendar with no confirmation. | Add `.disabled(isEditing)` to honor the contract, or relabel it as an intentional "move" action — pick one so code and comment agree. |
