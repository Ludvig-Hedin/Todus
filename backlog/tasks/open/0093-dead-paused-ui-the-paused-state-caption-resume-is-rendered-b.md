---
id: 0093
title: "Dead .paused UI — The .paused state (caption + \"Resume\") is rendered but never produced — ModelDownloadService"
status: open
priority: P4
tags: [macos, qa, code-review-backlog]
files: []
created: 2026-05-28
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-28 — macOS QA deferred features (found, not yet fixed) → Deferred — medium / low (client, but untestable here)

| Area | Where | Severity | Problem | Suggested fix |
|------|-------|----------|---------|---------------|
| Dead `.paused` UI | `MacLocalModelsView` (`.paused` branches in `detailLine`/`actionView`) | 🔵 low | The `.paused` state (caption + "Resume") is rendered but never produced — `ModelDownloadService` has no pause; `cancelDownload` always goes to `.notInstalled`. | Implement pause/resume (URLSession resume data) or remove the `.paused` UI (needs a `default` so the switches stay exhaustive). |
