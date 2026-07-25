---
id: 0065
title: "BH-0605-4 — initialScan merge can resurrect a just-deleted model as .installed if scanDisk() snapshotted befor"
status: open
priority: P4
tags: [ios, macos, bug-hunt, code-review-backlog]
files: []
created: 2026-06-05
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-05 — Bug hunt (iOS + macOS changed files) → Needs attention (not auto-fixed — TODO added in code where noted)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| BH-0605-4 | iOS local AI | `LocalModelStateStore.swift:160` (iOS) | 🔵 low | `initialScan` merge can resurrect a just-deleted model as `.installed` if `scanDisk()` snapshotted before the delete finished (treats `.none` as safe-to-seed). | Re-check disk presence at merge time for `.none` seeds, or set a deletion tombstone the scan honors. |
