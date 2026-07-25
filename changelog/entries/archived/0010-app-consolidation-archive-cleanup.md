---
id: 0010
title: "App Consolidation + Archive Cleanup"
status: archived
category: Changed
release_date: 2026-03-01
source: CHANGELOG.md
---

## [2026-03-01] App Consolidation + Archive Cleanup

### Changed

- Consolidated active app surface to:
  - `apps/ios` (only active iPhone native app)
  - `apps/macos` (only active desktop webview wrapper)
- Archived duplicate/legacy app implementations to `apps/archived/*`:
  - `apps/native` -> `apps/archived/native`
  - `apps/webview-swift` -> `apps/archived/webview-swift`
  - `apps/apple` -> `apps/archived/apple`
- Removed `native:*` scripts from root `package.json` to prevent accidental double-build paths.

### Updated

- Updated app structure and scripts documentation to reflect the canonical targets.
- Renamed remaining archived native Xcode display/product naming from `Zero*` to `Todus` (display/product/module identifiers in archived native projects).
