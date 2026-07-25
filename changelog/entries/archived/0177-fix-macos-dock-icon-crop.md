---
id: 0177
title: "Fix — macOS Dock icon crop"
status: archived
category: Fixed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] Fix — macOS Dock icon crop

### macOS (`apps/macos`)

- **TodusMac/Resources/Assets.xcassets/AppIcon.appiconset**: Regenerated the macOS app icon set from the iOS 1024 px master artwork so the Dock icon uses the same padding and no longer appears cropped.
- **apps/ios/Todus/status_macos.md**: Added a build note documenting the icon asset correction.
