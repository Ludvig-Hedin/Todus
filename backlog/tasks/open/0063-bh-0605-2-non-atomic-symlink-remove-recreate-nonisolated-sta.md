---
id: 0063
title: "BH-0605-2 — Non-atomic symlink remove+recreate; nonisolated static with no serialization → concurrent refresh("
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
| BH-0605-2 | macOS local AI | `HuggingFaceCacheConnector.swift:227` (TODO) | 🟡 med | Non-atomic symlink remove+recreate; `nonisolated static` with no serialization → concurrent `refresh()`/download can leave a missing/stale link → MLX re-downloads multi-GB weights. | Create link at a temp path in the same dir + `fm.replaceItemAt` (atomic rename), or serialize the bridge. |
