---
id: 0093
title: "Fix — macOS sidebar profile menu now opens settings"
status: archived
category: Fixed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Fix — macOS sidebar profile menu now opens settings

- Removed the no-op `Profile` item from the macOS sidebar account dropdown.
- Wired the profile menu entry to the existing macOS settings overlay so it now opens real profile/account controls.
- Kept the separate gear icon and keyboard shortcut as alternate settings entry points.

**Files:** `apps/macos/TodusMac/App/MacSidebarView.swift`, `apps/macos/README.md`
