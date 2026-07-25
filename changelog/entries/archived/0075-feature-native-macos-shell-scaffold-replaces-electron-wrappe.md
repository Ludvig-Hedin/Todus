---
id: 0075
title: "Feature — Native macOS shell scaffold replaces Electron wrapper"
status: archived
category: Added
release_date: 2026-03-29
source: CHANGELOG.md
---

## [2026-03-29] Feature — Native macOS shell scaffold replaces Electron wrapper

### Summary

Replaced the legacy Electron-based `apps/macos` wrapper with a standalone SwiftUI macOS app scaffold driven by XcodeGen.

This first native macOS pass is intentionally shell-only:

- added a single-window `TodusMac` app
- added `NavigationSplitView` shell layout with a custom sidebar
- added placeholder panes for Home, Tasks, Email, and Calendar
- added a SwiftUI content header with notification, menu, edit, and search affordances
- added a floating Assistant button with a placeholder sheet
- added placeholder account menu and Settings modal
- updated canonical docs to describe macOS as a native SwiftUI target
- updated macOS status tracking to reflect shell completion and the remaining Xcode license blocker for CLI build verification

**Files changed:**

- `apps/macos/README.md`
- `apps/macos/project.yml`
- `apps/macos/TodusMac/App/TodusMacApp.swift`
- `apps/macos/TodusMac/App/MacRootView.swift`
- `apps/macos/TodusMac/App/MacSidebarView.swift`
- `apps/macos/TodusMac/App/MacContentHeaderView.swift`
- `apps/macos/TodusMac/App/AssistantButton.swift`
- `apps/macos/TodusMac/Resources/Info.plist`
- `AGENTS.md`
- `APPS_ARCHITECTURE.md`
- `docs/architecture/README.md`
- `docs/architecture/APPS_ARCHITECTURE.md`
- `docs/development/SCRIPTS_GUIDE.md`
- `docs/testflight-checklist.md`
- `docs/guides/AGENTS.md`
- `apps/ios/Todus/status_macos.md`
