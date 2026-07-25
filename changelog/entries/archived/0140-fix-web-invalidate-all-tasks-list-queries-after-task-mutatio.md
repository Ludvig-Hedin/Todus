---
id: 0140
title: "Fix — web: invalidate all `tasks.list` queries after task mutations"
status: archived
category: Fixed
release_date: 2026-03-31
source: CHANGELOG.md
---

## [2026-03-31] Fix — web: invalidate all `tasks.list` queries after task mutations

- Task updates from mail home, calendar, and shared `TaskItem` now call `queryClient.invalidateQueries(trpc.tasks.list.queryFilter())` so every cached `tasks.list` variant (filters, sort, limit) refetches instead of only the one matching a fixed `queryKey({ limit: N })`.
- Mail tasks page `invalidate()` uses the same `queryFilter()` pattern (replacing a path-prefix `predicate` that relied on reference equality between fresh and cached `queryKey[0]` arrays).

**User-facing:** Lists and filters stay in sync after toggling or editing tasks from any surface.

**Files:** `apps/web/app/(routes)/mail/tasks/page.tsx`, `apps/web/app/(routes)/mail/home/page.tsx`, `apps/web/app/(routes)/mail/calendar/page.tsx`, `apps/web/components/tasks/task-item.tsx`, `apps/web/task-item.tsx`
