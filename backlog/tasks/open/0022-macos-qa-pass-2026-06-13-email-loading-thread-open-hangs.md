---
id: 0022
title: "macOS QA pass — 2026-06-13 — email loading / thread-open / hangs"
status: open
priority: P3
tags: [macos, qa, code-review-backlog]
files: [EmailModels.swift, scripts/run-email-decode-tests.sh]
created: 2026-06-13
source: CODE_REVIEW_BACKLOG.md
---

> Section overview — the individual findings from this section are separate items.

# macOS QA pass — 2026-06-13 — email loading / thread-open / hangs

Root-cause investigation of the reported macOS symptoms (emails not loading, errors entering threads, click/navigation hangs). 2 parallel read-only investigators + manual verification against source. App `BUILD SUCCEEDED` before + after. Decode-tolerance regression tests run green (11/11) against the real `EmailModels.swift` via `scripts/run-email-decode-tests.sh`.
