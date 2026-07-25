---
id: 0189
title: "PERF-4 — Resolved 2026-07-21 — computed once into locals at the top of body; resultsList now takes them as par"
status: done
tags: [ios, performance, code-review-backlog]
files: [Features/Search/GlobalSearchView.swift]
created: 2026-07-11
source: CODE_REVIEW_BACKLOG.md
---

> Source context: iOS performance pass — deferred findings, 2026-07-11

| ID | File | Issue | Fix direction | Why deferred |
|----|------|-------|---------------|--------------|
| ~~PERF-4~~ | `Features/Search/GlobalSearchView.swift` | ~~`taskResults`/`emailResults`/`peopleResults` each computed twice per body~~ | **Resolved 2026-07-21** — computed once into locals at the top of `body`; `resultsList` now takes them as params, `hasResults` derived from the locals | — |
