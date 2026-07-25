---
id: 0240
title: "UX — macOS AI assistant floating panel"
status: archived
category: Changed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] UX — macOS AI assistant floating panel

- [UX] **macOS:** Floating AI assistant size and position are passed from `MacRootView` (live `@State` + explicit `UserDefaults` sync on move/resize end, mode change, and background) so drags are smooth — no per-frame `AppStorage` writes. Move only from the **title bar strip** (not toolbar buttons): open/closed hand cursors. Resize from **all four edges and corners** (5pt/16pt hit targets) with `resizeUpDown` / `resizeLeftRight` and SF Symbol diagonal cursors; `highPriorityGesture` and disabled layout animation reduce jank.
- [UX] **macOS (earlier in day):** Floating size/position were initially stored in `AppStorage` and passed from `MacRootView` so they survive dock ↔ float. Max float width 800pt.
- **Files:** `apps/macos/TodusMac/App/MacRootView.swift`, `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift`
