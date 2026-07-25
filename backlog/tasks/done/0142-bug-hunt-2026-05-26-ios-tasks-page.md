---
id: 0142
title: "Bug Hunt — 2026-05-26 — iOS Tasks page"
status: done
tags: [ios, bug-hunt, code-review-backlog]
files: [Services/Tasks/TaskCaptureService.swift]
created: 2026-05-20
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-20 — iOS Mobile App Bug Hunt

## Bug Hunt — 2026-05-26 — iOS Tasks page

_Closed by the 2026-06-13 backlog resolution pass (`CODE_REVIEW_BACKLOG.md` → "No open code defects remain": every code-defect item was fixed, built, tested and committed in passes 1-6). Re-open if this finding is still reproducible._


Scope: `apps/ios/Todus/Todus/Features/Tasks/` + `Services/Tasks/TaskCaptureService.swift` + domain models.

### Auto-fixed (3 issues)

| File:line | Severity | What changed |
|-----------|----------|--------------|
| `InboxView.swift:47` | error | `emptyState` branch fired when `visibleTasks.isEmpty && completedTasks.isEmpty` even if `olderCompletedTasks` had entries — those older completed tasks were rendered by no view in this branch. Users with recently-cleared recent completeds but retained older ones saw "Inbox is empty" and had no way to access older work. Fixed: added `&& olderCompletedTasks.isEmpty` to the condition. |
| `BoardView.swift:63` | warning | `boardChangeDigest` returned `[BoardTaskDigest]` — O(N) array equality check on every SwiftUI body re-evaluation. Every other view uses a `(count, latestUpdate)` digest (O(1)). Replaced with identical `TasksDigest` struct pattern. Removed now-unused `BoardTaskDigest` struct. All mutations bump `updatedAt`, so O(1) digest is safe. |
| `CalendarTaskView.swift:339` | error | Context-menu Delete in `CalendarTaskCard` fired immediately without confirmation, inconsistent with `TaskRowView` and `TaskTableView` which both show a `confirmationDialog`. Added `@State private var showDeleteConfirmation` and a `.confirmationDialog` matching the pattern in `TaskRowView`. |

### Needs human review (2 issues)

| File:line | Severity | Issue | Suggested fix |
|-----------|----------|-------|---------------|
| `BoardColumnView.swift:44` | warning | `@Query(sort: \TaskRecord.createdAt, order: .reverse) private var tasksInApp: [TaskRecord]` inside `BoardColumnView` fetches ALL tasks independently of the `tasks: [TaskRecord]` prop already passed by `BoardView`. Only used in `handleDrop` for a single task lookup by UUID. This means every task mutation triggers an O(N) SwiftUI re-render of ALL `BoardColumnView` instances, not just the affected column. | Replace the `@Query` with a `@Query`-free `modelContext.fetch(FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == taskID }))` call inside `handleDrop` at drop time. |
| `TaskDetailSheet.swift:72` | info | `isSaving` is set to `true` before `saveTask()` and never reset to `false`. `saveTask()` always calls `dismiss()`, which destroys the view, so the state reset doesn't matter in practice. But if a future code path calls `saveTask()` without dismissing (e.g., inline editing), the Save button would be permanently disabled. | Reset `isSaving = false` at the start of the `catch` or error path, or after any non-dismissing code path. |

---
