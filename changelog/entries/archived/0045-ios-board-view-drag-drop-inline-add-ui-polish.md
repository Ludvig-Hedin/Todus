---
id: 0045
title: "iOS Board View — Drag/Drop, Inline Add, UI Polish"
status: archived
category: Added
release_date: 2026-03-27
source: CHANGELOG.md
---

## [2026-03-27] iOS Board View — Drag/Drop, Inline Add, UI Polish

### Features

- **Drag & drop tasks between columns**: Drop destination with animated status change and visual drop highlight using column tint colors.
- **Tap column empty area to add task**: Tapping anywhere in a column's empty space opens an inline add field at the top of the card list.
- **+ button in column headers**: Quick-add button in the top-right of each column header, tinted with the column's accent color.
- **"Add task" button at column bottom**: Outlined button with muted column-tint border and text, matching each status's color identity.
- **Context menu "Move to…" submenu**: Board cards now have a status-change submenu in the long-press context menu for quick column moves.
- **`captureInStatus()` method**: New `TaskCaptureService` method for creating tasks directly into a specific status column with full sync.

### UI Polish

- **Column tint colors**: Each `TaskStatus` now has a subtle accent color (slate for Todo, blue for Doing, green for Done) and a status icon.
- **Tighter spacing**: Reduced column width (272→264), card padding (12→10/9), card corner radius (16→10), column corner radius (16→14).
- **Refined typography**: Smaller, denser text (13→12pt cards, 13→12pt headers), tighter tracking, softer foreground opacity.
- **Lighter column backgrounds**: Reduced from solid fill to 55% opacity for a more breathable look.
- **Removed heavy shadows**: Cards use clean border-only styling instead of glassCard with drop shadows.

### Files Changed

- `apps/ios/Todus/Todus/Domain/TaskStatus.swift` — Added `tintColor`, `systemImage` properties
- `apps/ios/Todus/Todus/Services/Tasks/TaskCaptureService.swift` — Added `captureInStatus()` method
- `apps/ios/Todus/Todus/Features/Tasks/BoardColumnView.swift` — Full rewrite with inline add, + button, add-task button, refined styling
- `apps/ios/Todus/Todus/Features/Tasks/BoardTaskCard.swift` — Refined styling, added "Move to…" context menu
- `apps/ios/Todus/Todus/Features/Tasks/BoardView.swift` — Tighter spacing (16→12 gap), removed tap-to-dismiss-keyboard gesture
