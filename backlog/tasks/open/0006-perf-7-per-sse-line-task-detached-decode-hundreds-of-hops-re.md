---
id: 0006
title: "PERF-7 — Per-SSE-line Task.detached decode (hundreds of hops/reply) and full-markdown reparse on every 80ms to"
status: open
priority: P3
tags: [ios, performance, code-review-backlog]
files: []
created: 2026-07-11
source: CODE_REVIEW_BACKLOG.md
---

> Source context: iOS performance pass — deferred findings, 2026-07-11

| ID | File | Issue | Fix direction | Why deferred |
|----|------|-------|---------------|--------------|
| PERF-7 | `Services/AI/AIChatService.swift:1164` + `Features/AI/MarkdownView.swift:29-38` | Per-SSE-line `Task.detached` decode (hundreds of hops/reply) and full-markdown reparse on every ~80ms token flush (O(N²) over a long reply) | Decode on one reused background queue for the whole stream; make markdown parse incremental (diff-append) | Both sit on deliberate, documented tradeoffs; off-main already, so no hang |
