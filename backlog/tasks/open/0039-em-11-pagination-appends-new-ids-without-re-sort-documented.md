---
id: 0039
title: "EM-11 — Pagination appends new ids without re-sort (documented contract) — a page-2 thread newer than page-1's"
status: open
priority: P4
tags: [ios, bug-hunt, code-review, code-review-backlog]
files: []
created: 2026-06-08
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Bug Hunt — 2026-06-08 — iOS email surface (`/bug-hunt`) → Needs human review (verified real, deferred — higher-risk / unvalidatable under `--ui-testing` / product calls)

| ID | Area | Where | Sev | Problem | Suggested fix |
|----|------|-------|-----|---------|---------------|
| EM-11 | Email perf | `EmailService.swift:1727-1748` (`mergePages`) | 🔵 low | Pagination appends new ids without re-sort (documented contract) — a page-2 thread newer than page-1's tail lands out of date order. | Optional re-sort by date desc after merge (mind the pinned unit test). |
