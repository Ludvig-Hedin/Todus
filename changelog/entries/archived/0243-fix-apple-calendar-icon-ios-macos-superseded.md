---
id: 0243
title: "Fix — Apple Calendar icon (iOS + macOS) — superseded"
status: archived
category: Fixed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Fix — Apple Calendar icon (iOS + macOS) — superseded

- **Superseded by** the same-day entry **“Fix — Apple Calendar brand icon (blank white tile)”** above: a **Canvas + Path(SVG `d`)** pass for `AppleCalendarLogo` was tried, but Swift’s path parser often yielded `nil`, so the inner art did not draw. The **current** implementation in `BrandIcons.swift` / `MacBrandIcons.swift` is **layout-based** (red header, “MON”, “12”), not Canvas/SVG `d` paths.
- **Files (historical context only):** `apps/ios/Todus/Todus/DesignSystem/BrandIcons.swift`, `apps/macos/TodusMac/DesignSystem/MacBrandIcons.swift`
