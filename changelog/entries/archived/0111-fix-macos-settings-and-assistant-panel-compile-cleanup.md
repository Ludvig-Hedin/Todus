---
id: 0111
title: "Fix — macOS settings and assistant panel compile cleanup"
status: archived
category: Fixed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Fix — macOS settings and assistant panel compile cleanup

Resolved the current macOS Xcode warnings/errors blocking the `TodusMac` build:

- restored the branded service-row helper used by `MacSettingsView`
- added the missing Apple Reminders connection flag used by the settings UI
- replaced the explicit `Selector(("showHelp:"))` call with `#selector`
- removed ineffective `nonisolated(unsafe)` storage annotations from `MacVoiceController` and updated the speech callback to hop back to the main actor

**Files changed:**

- `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`
- `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift`
