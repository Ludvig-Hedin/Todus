---
id: 0234
title: "Fix — Apple Calendar brand icon (blank white tile)"
status: archived
category: Fixed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Fix — Apple Calendar brand icon (blank white tile)

- [Fix] **Native:** `AppleCalendarLogo` no longer uses `Canvas` + `Path(SVG d)`; Swift’s path parser often returns `nil` for those `d` strings, so the inner art never drew and only the white `AppIconContainer` was visible (Calendar access screen, settings, tab header). The icon is again **layout-based** (red header strip, white “MON”, dark “12”) so it always renders in the inner square. **iOS + macOS:** `BrandIcons.swift` / `MacBrandIcons.swift`.
- [User-facing] Calendar permission, Settings, and calendar tab headers show the full calendar mark again instead of an empty box.
