---
id: 0177
title: "Needs human review (1) — ✅ RESOLVED 2026-06-15"
status: done
tags: [ios, bug-hunt, code-review, code-review-backlog]
files: [Features/Home/HomeView.swift]
created: 2026-06-14
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Bug Hunt — 2026-06-14 (iOS main user-flow surfaces)

## Needs human review (1) — ✅ RESOLVED 2026-06-15

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| ~~BH-0614-1~~ | Home briefing | `Features/Home/HomeView.swift` (`dismissBriefingItem`/`markBriefingItemDone`/`snoozeBriefingItem`) | 🟠 high | Handlers called the backend with `item.backendId` without re-validating the item still exists in the current briefing → silent mutation failure + local/server divergence. | **RESOLVED** in the 2026-06-15 UX pass: added `briefingItemStillExists(_:)` (mirrors `todayActionLine`'s pool lookup); all three handlers now skip the mutation and call `loadAssistantBriefing()` to reconcile when the item is stale. |
