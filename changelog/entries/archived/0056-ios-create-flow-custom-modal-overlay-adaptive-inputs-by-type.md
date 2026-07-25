---
id: 0056
title: "iOS Create Flow — custom modal overlay + adaptive inputs by type/tab"
status: archived
category: Changed
release_date: 2026-03-27
source: CHANGELOG.md
---

## [2026-03-27] iOS Create Flow — custom modal overlay + adaptive inputs by type/tab

### Changed

- **`+` action now opens a modal overlay (not system sheet)**: Replaced the old `sheet`-based create UI with an in-app modal overlay that matches the compact floating style.
- **Adaptive create form by selected type**:
  - **Auto**: smart routing (date text -> event, email intent -> email, otherwise task)
  - **Task**: title input + folder selector + due-date picker
  - **Event**: title input + event date/time picker
  - **Email**: title/input mode that opens email compose flow
- **Context-aware defaults by active tab**:
  - **Calendar tab** -> defaults to Event
  - **Tasks tab** -> defaults to Task
  - **Home tab** -> defaults to Auto
  - **Email tab** -> defaults to Email
- **Folder selector default**: Defaults to `Inbox` (no folder) as requested.

### Files

- `apps/ios/Todus/Todus/Navigation/MainTabView.swift`
- `apps/ios/Todus/Todus/Navigation/CreateSheet.swift`
