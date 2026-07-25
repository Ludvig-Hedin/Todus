---
id: 0035
title: "EM-7 — Full-list lowercasing per keystroke; threadsForSender re-filters+sorts the pool in a computed prop ever"
status: open
priority: P3
tags: [ios, bug-hunt, code-review, code-review-backlog]
files: []
created: 2026-06-08
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Bug Hunt — 2026-06-08 — iOS email surface (`/bug-hunt`) → Needs human review (verified real, deferred — higher-risk / unvalidatable under `--ui-testing` / product calls)

| ID | Area | Where | Sev | Problem | Suggested fix |
|----|------|-------|-----|---------|---------------|
| EM-7 | Email perf | `EmailInboxView.swift:1414` (`recomputeFilteredThreads`), `:1494` (`threadsForSender`), `:790` (`buildSenderGroups`) | 🟡 med | Full-list lowercasing per keystroke; `threadsForSender` re-filters+sorts the pool in a computed prop every `body`; sender groups re-sort on every `threads` change. | Precompute lowercased search fields; cache `threadsForSender` in `@State`; gate group rebuild to People view. |
