---
id: 0316
title: "Changed — iOS Tasks tab is less cramped"
status: unreleased
category: Changed
release_date: 2026-07-11
source: CHANGELOG.md
---

### Changed — iOS Tasks tab is less cramped, 2026-07-11

The Tasks tab was uniformly dense (10–14 pt type, 3 pt row padding, a 7 pt-tall segmented picker). Scaled the whole surface up for comfortable reading and tapping, consistently across all four view modes:

- **View-mode picker** (List/Board/Table/Calendar): icon 13→15, label 11→13, taller pills (vpad 7→11).
- **Search + sort bar**: 11–12→13–14 pt, taller field.
- **List rows** (`TaskRowView`): title 14→16, description 12→13, checkbox glyph 16→21 (frame 36→40), row padding 3/6→9/10, meta/status chips 10→11.
- **Board cards** and **Table rows** bumped to match (titles →15, chips →11, taller rows; Table status column widened 76→84 to fit).
- Smart-bucket headers, completed rows, and header stat chips scaled to match.
