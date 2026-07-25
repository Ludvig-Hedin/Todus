---
id: 0199
title: "UX — Removed \"Add Task\" buttons from Tasks page (iOS)"
status: archived
category: Removed
release_date: 2026-04-06
source: CHANGELOG.md
---

## [2026-04-06] UX — Removed "Add Task" buttons from Tasks page (iOS)

- [UX] Removed the "Add Task" button from the `TasksTabView` header to declutter the main task interface.
- [UX] Removed the "Add Task" buttons and plus icons from the `BoardView` columns (headers and footers) to simplify the board layout.
- [UX] Removed the tap-to-add gesture from board columns.
- [UX] Updated empty state messaging in both List and Board views to guide users towards the central "Create" button in the tab bar or dragging existing tasks.
- **Files:** `apps/ios/Todus/Todus/Features/Tasks/TasksTabView.swift`, `apps/ios/Todus/Todus/Features/Tasks/BoardColumnView.swift`, `apps/ios/Todus/Todus/Features/Tasks/InboxView.swift`
