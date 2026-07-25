---
id: 0082
title: "2026-05-28 — macOS QA deferred features (found, not yet fixed)"
status: open
priority: P1
tags: [macos, qa, code-review-backlog]
files: []
created: 2026-05-28
source: CODE_REVIEW_BACKLOG.md
---

> Section overview — the individual findings from this section are separate items.

# 2026-05-28 — macOS QA deferred features (found, not yet fixed)

Surfaced during the multi-round macOS flow QA (commit `ed8eb057`). The critical/high
flow bugs were fixed + committed; the items below were deferred because they need a
backend change, are net-new features, or aren't safely verifiable in this environment
(no GUI / notification / widget runtime). Each has a concrete entry point + fix.
