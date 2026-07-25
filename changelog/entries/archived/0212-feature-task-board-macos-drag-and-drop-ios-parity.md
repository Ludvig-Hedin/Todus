---
id: 0212
title: "Feature — Task board: macOS drag-and-drop + iOS parity"
status: archived
category: Added
release_date: 2026-04-24
source: CHANGELOG.md
---

## [2026-04-24] Feature — Task board: macOS drag-and-drop + iOS parity

- [Feature] macOS Tasks board: drag tasks between columns to update `TaskStatus`, persist with `syncState` pending upload, and highlight the drop target; horizontal scroll when columns do not fit.
- [UX] iOS Tasks board: column chrome and cards aligned with the macOS kanban (uppercase stage labels, count badge, row-style cards with status icon, due/priority/folder meta, trailing chevron); shared short due-date formatter.
- [Fix] iOS AI chat: attachment file chip used a non-existent `AppTheme.surfaceCard` token — use `surfacePrimary` so the target builds.
- **Files:** `apps/macos/TodusMac/Views/Tasks/MacTasksView.swift`, `apps/ios/Todus/Todus/Features/Tasks/BoardColumnView.swift`, `BoardTaskCard.swift`, `DesignSystem/Formatters.swift`, `Features/AI/AIChatView.swift`
