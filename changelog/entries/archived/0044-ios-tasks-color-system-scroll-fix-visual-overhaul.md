---
id: 0044
title: "iOS Tasks — Color System, Scroll Fix, Visual Overhaul"
status: archived
category: Fixed
release_date: 2026-03-27
source: CHANGELOG.md
---

## [2026-03-27] iOS Tasks — Color System, Scroll Fix, Visual Overhaul

### Bug Fixes

- **Board column scroll**: Columns now have internal vertical `ScrollView` so card overflow scrolls instead of being clipped. Header stays sticky above the scroll area.

### Design Overhaul — All Task Views

- **Consistent tinted status system**: Todo = muted gray, Doing = muted blue, Done = muted green. Applied across board columns, table rows, list tags, and calendar headers.
- **Board columns**: Each column has a very subtle tinted background (0.025 opacity) and tinted border (0.08 opacity). Drop highlight intensifies the tint. Column gap tightened (12→10). Dashed add-task button at bottom.
- **Board cards**: Left-edge color indicator bar per status. Priority flag icons. Overdue dates in red, today in amber. Completed tasks show strikethrough with dimmed text. Thinner border (0.5px).
- **Table view**: Status column now shows colored pills with icon + text (tinted bg + border). Checkbox uses status tint color. Priority dot indicator. Color-coded due dates. Uppercase header labels. "Move to…" context menu added.
- **Calendar view**: Bucket headers now have colored icons (sun for Today, sunrise for Tomorrow, calendar for This Week) with tinted count badges. Each bucket has a unique warm→cool color progression.
- **List view (TaskRowView)**: Status tags now use tinted backgrounds matching their column color. Due date tags are color-coded (red=overdue, amber=today). Priority tags use colored flag icons. All tags use consistent 5pt radius with 0.5px tinted borders. Row corner radius refined (16→14).

### Files Changed

- `BoardView.swift` — Column gap 12→10
- `BoardColumnView.swift` — Vertical scroll for cards, sticky header, tinted column bg/border, dashed add-task button
- `BoardTaskCard.swift` — Left-edge color bar, priority flags, due date coloring, strikethrough for completed
- `TaskTableView.swift` — Colored status pills, priority dots, due date colors, uppercase header, "Move to…" context menu
- `CalendarTaskView.swift` — Colored bucket headers with icons, tinted count badges, warm→cool color progression
- `TaskRowView.swift` — Tinted status/due/priority tags, dimmed completed state, refined tag sizing
