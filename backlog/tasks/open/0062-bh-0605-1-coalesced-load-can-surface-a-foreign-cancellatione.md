---
id: 0062
title: "BH-0605-1 — Coalesced load can surface a foreign CancellationError if evict/unloadAll cancels the task during"
status: open
priority: P3
tags: [ios, macos, bug-hunt, code-review-backlog]
files: []
created: 2026-06-05
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-05 — Bug hunt (iOS + macOS changed files) → Needs attention (not auto-fixed — TODO added in code where noted)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| BH-0605-1 | iOS local AI | `MLXInferenceService.swift:143` (TODO) | 🟡 med | Coalesced load can surface a foreign `CancellationError` if `evict`/`unloadAll` cancels the task during the `await` after the `!isCancelled` guard passes; cancelled task's inflight slot can also leak. | Have `evict`/`unloadAll` synchronously `removeValue(forKey:)` the slot they cancel; or retry a fresh load when a non-cancelled caller catches `CancellationError`. |
