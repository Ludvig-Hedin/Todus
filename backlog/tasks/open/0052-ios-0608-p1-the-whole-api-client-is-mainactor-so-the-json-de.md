---
id: 0052
title: "IOS-0608-P1 — The whole API client is @MainActor, so the JSON decode + JSONSerialization of the 50-thread mail"
status: open
priority: P1
tags: [ios, server, qa, code-review-backlog]
files: []
created: 2026-06-08
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-08 — iOS Simulator QA pass → Still open (verified real, deferred — higher-risk / product call / needs backend)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| IOS-0608-P1 | Email perf | `Services/API/TodosAPIClient.swift:5` (`@MainActor`) + `EmailService.swift:~785` | 🔴 **critical** | The whole API client is `@MainActor`, so the JSON decode + `JSONSerialization` of the 50-thread `mail.get` batch runs on the **main thread** — UI hitch on every inbox load/refresh. | Move decode off-main: a `nonisolated` batch-parse path (needs `Sendable` conformances on decoded types) or drop `@MainActor` from the client. App-wide; own pass. |
