---
id: 0081
title: "BH-0601-4 — hasWeightFile/directorySize recursively walk multi-GB HF caches with no depth/count cap and no mid"
status: open
priority: P4
tags: [bug-hunt, code-review-backlog]
files: []
created: 2026-06-01
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-01 — Bug hunt (uncommitted + last 3 commits) → Needs attention (not auto-fixed)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| BH-0601-4 | macOS local AI | `HuggingFaceCacheConnector.swift:330` / `LocalModelStateStore.swift:131` | 🔵 low | `hasWeightFile`/`directorySize` recursively walk multi-GB HF caches with no depth/count cap and no mid-walk `Task.isCancelled` check (only checked after `collect()` returns). No crash; can be slow on large external caches. | Add a depth/entry cap and periodic cancellation checks inside the enumerator loop. |
