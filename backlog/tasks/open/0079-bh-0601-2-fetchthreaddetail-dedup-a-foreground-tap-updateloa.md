---
id: 0079
title: "BH-0601-2 — fetchThreadDetail dedup: a foreground tap (updateLoadingState:true) that joins an in-flight prefet"
status: open
priority: P3
tags: [bug-hunt, code-review-backlog]
files: []
created: 2026-06-01
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-01 — Bug hunt (uncommitted + last 3 commits) → Needs attention (not auto-fixed)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| BH-0601-2 | macOS email | `apps/macos/TodusMac/Services/Email/EmailService.swift:698` | 🟡 medium | `fetchThreadDetail` dedup: a foreground tap (`updateLoadingState:true`) that joins an in-flight **prefetch** (`updateLoadingState:false`) via `return await existing.value` inherits the prefetch's error handling — on failure `errorMessage` is never set, so the view shows the generic "Could not load thread." instead of the friendly auth/404/timeout copy. Not a crash. | Track the friendliest required `updateLoadingState` per id, or set `errorMessage` in `loadThread` when the joined result is nil. |
