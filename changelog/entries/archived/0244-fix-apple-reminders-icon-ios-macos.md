---
id: 0244
title: "Fix — Apple Reminders icon (iOS + macOS)"
status: archived
category: Fixed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Fix — Apple Reminders icon (iOS + macOS)

- [UX] **Native:** Replaced the layout-mock Reminders glyph with `Canvas` art matching the Reminders light app icon (1024×1024 coordinates: bars + colored rings). **macOS:** `AppIconContainer` now pins the inner icon to a square and clips like iOS so the glyph no longer crops or bleeds past the white app-icon tile.
- **Files:** `apps/ios/Todus/Todus/DesignSystem/BrandIcons.swift`, `apps/macos/TodusMac/DesignSystem/MacBrandIcons.swift`
