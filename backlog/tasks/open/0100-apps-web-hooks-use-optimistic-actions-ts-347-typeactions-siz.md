---
id: 0100
title: "apps/web/hooks/use-optimistic-actions.ts:347 — typeActions?.size === 1 is checked AFTER typeActions.delete(pen"
status: open
priority: P3
tags: [web, bug-hunt, code-review, code-review-backlog]
files: []
created: 2026-05-20
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-20 — Bug Hunt: apps/web main user flows → Needs human review (1)

| File:line | Severity | Problem | Suggested fix |
|-----------|----------|---------|---------------|
| `apps/web/hooks/use-optimistic-actions.ts:347` | warning | `typeActions?.size === 1` is checked AFTER `typeActions.delete(pendingActionId)` on the previous line mutates the same Set reference. Branch fires only when one OTHER pending action of the same type remains in flight. Single-action case (Set 1 → 0) never enters the branch, so `refreshData()`, `invalidateFolderLists()`, and `removeOptimisticAction()` are skipped: jotai `optimisticActionsAtom` grows unboundedly across a session (memory leak), MOVE/SNOOZE/UNSNOOZE/DELETE_DRAFT actions leave `shouldHide=true` forever in optimistic state, and server folder caches drift until the 5-minute stale window expires. | Almost certainly `=== 0` (i.e. this was the last in flight). Verify intent against the action's design — the current `=== 1` may have been left over from a different cleanup model. TODO comment inserted inline. |
