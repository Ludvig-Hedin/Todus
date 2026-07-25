---
id: 0107
title: "Fix — iOS calendar icon stretched + tasks page too bulky"
status: archived
category: Fixed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Fix — iOS calendar icon stretched + tasks page too bulky

- **Calendar icon:** Added explicit height to `AppleCalendarIconView` so GeometryReader doesn't stretch vertically
- **Search bar:** Reduced vertical padding (9→6) and changed to Capsule shape for a slimmer, rounded look
- **Task rows:** Reduced vertical padding (8→5) and checkbox height (44→32) for more compact list items
- **Completed task rows:** Reduced vertical padding (12→8) and corner radius (16→14)
- **Header spacing:** Reduced view mode picker vertical padding (12→4)

**Files:** `BrandIcons.swift`, `TasksTabView.swift`, `TaskRowView.swift`, `InboxView.swift`
