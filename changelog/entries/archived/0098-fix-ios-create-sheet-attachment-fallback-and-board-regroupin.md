---
id: 0098
title: "Fix — iOS create-sheet attachment fallback and board regrouping"
status: archived
category: Fixed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Fix — iOS create-sheet attachment fallback and board regrouping

- Forwarded the captured attachment list into event creation fallback paths so failed calendar permission or event-creation errors still preserve user-selected attachments when creating a task instead.
- Restored the Kanban regroup observer using a task signature derived from each task's id, status, and folder so in-place SwiftData mutations move cards between columns again.

**Files:** `apps/ios/Todus/Todus/Navigation/CreateSheet.swift`, `apps/ios/Todus/Todus/Features/Tasks/BoardView.swift`
