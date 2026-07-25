---
id: 0116
title: "Enhancement — Resizable & movable AI assistant panels"
status: archived
category: Changed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Enhancement — Resizable & movable AI assistant panels

Made both floating and side pane assistant panels user-resizable:

- **Floating panel resizable**: Bottom-right drag handle (min 320×400, max 700×900) with crosshair cursor
- **Floating panel movable**: Header drag gesture moves panel freely around the window
- **Side pane resizable**: Draggable divider replaces static Divider (min 280px, max 600px) with resize cursor
- **Self-managed sizing**: Floating panel manages its own frame via internal `floatingSize` state; MacRootView no longer imposes fixed dimensions
- **Icon consistency**: AssistantButton uses `sparkles` icon matching iOS

**Files changed:**

- `MacAssistantPanel.swift` — Added `floatingSize`, `floatingOffset`, resize handle overlay, `.frame()` and `.offset()` modifiers
- `MacRootView.swift` — Added `sidePaneWidth` state, draggable resize divider with `NSCursor.resizeLeftRight`, removed fixed floating frame
