---
id: 0252
title: "Fix — Toggle visibility (iOS + macOS)"
status: archived
category: Fixed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Fix — Toggle visibility (iOS + macOS)

- [Fix] `Toggle` / switch controls no longer use `.tint(.primary)` (which could render as white-on-white in dark mode). Shared tokens `AppTheme.switchTint` and `MacTheme.switchTint` use system blue so the on-state is visible in light and dark mode.
- **Files:** `AppTheme.swift`, `MacTheme.swift`, `SettingsView.swift` (incl. AI Assistant sub-list), `AIChatView.swift`, `RemindersSetupView.swift`, `TaskDetailSheet.swift`, `SignaturesView.swift`, `MacSettingsView.swift`, `MacTasksView.swift`
