---
id: 0090
title: "Notification cold-launch — Queue the routing intent (category + payload) on the app delegate when services/mod"
status: open
priority: P3
tags: [macos, qa, code-review-backlog]
files: []
created: 2026-05-28
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-28 — macOS QA deferred features (found, not yet fixed) → Deferred — medium / low (client, but untestable here)

| Area | Where | Severity | Problem | Suggested fix |
|------|-------|----------|---------|---------------|
| Notification cold-launch | `TodusMacApp` notification delegate, default-tap branch (`guard let services = self.services else { return }`) | 🟡 medium | A notification tapped during cold launch is dropped — `services` is nil until `initializeApp`, and (unlike deep links) the tap isn't queued/replayed. | Queue the routing intent (category + payload) on the app delegate when `services`/`modelContainer` is nil; replay at the end of `initializeApp` (mirror `pendingDeepLinks`). |
