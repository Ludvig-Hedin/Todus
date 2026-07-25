---
id: 0186
title: "PERF-1 — Resolved 2026-07-22 — DocsService rebuilds a parent/workspace index only when allDocs changes; tree l"
status: done
tags: [ios, performance, code-review-backlog]
files: [Features/Docs/DocsListView.swift, Services/Docs/DocsService.swift]
created: 2026-07-11
source: CODE_REVIEW_BACKLOG.md
---

> Source context: iOS performance pass — deferred findings, 2026-07-11

| ID | File | Issue | Fix direction | Why deferred |
|----|------|-------|---------------|--------------|
| ~~PERF-1~~ | `Features/Docs/DocsListView.swift` + `Services/Docs/DocsService.swift` | ~~`listDocs`/`children` filtered and sorted all docs once per tree node~~ | **Resolved 2026-07-22** — `DocsService` rebuilds a parent/workspace index only when `allDocs` changes; tree lookups are direct and already sorted | — |
