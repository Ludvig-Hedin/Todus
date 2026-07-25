---
id: 0042
title: "QA-0608-1 — One errorMessage field is shared by load + markRead/unread + archive/delete/star + connectGmail an"
status: open
priority: P3
tags: [macos, qa, code-review-backlog]
files: [EmailService.swift]
created: 2026-06-08
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-08 — QA pass (macOS app, pre-TestFlight) → Needs attention (not auto-fixed — verified real, deferred as higher-risk/product calls)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| QA-0608-1 | macOS email | `EmailService.swift` `errorMessage` (set at `:531/1204/1225/1259/1271/1293`; read at `MacEmailInboxView.swift:243,814`) | 🟡 med | One `errorMessage` field is shared by load + markRead/unread + archive/delete/star + connectGmail and never cleared on success. A stale action error can flip the inbox to the full-screen "Couldn't load" panel (gate keys off `errorMessage != nil && filteredThreads.isEmpty`) and shows under the Gmail connect card. | Per-surface error: transient toast for action failures, separate from the load-level `errorMessage` that drives the full-screen state; or clear `errorMessage = nil` on each action success. |
