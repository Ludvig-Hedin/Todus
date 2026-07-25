---
id: 0077
title: "Fix — iOS Xcode build environment reset for CalendarKit registration hangs"
status: archived
category: Fixed
release_date: 2026-03-29
source: CHANGELOG.md
---

## [2026-03-29] Fix — iOS Xcode build environment reset for CalendarKit registration hangs

### Summary

Investigated repeated Xcode GUI hangs around:

- `RegisterExecutionPolicyException ... CalendarKit.o`
- `RegisterExecutionPolicyException ... CalendarKit_CalendarKit.bundle`

This was not caused by CalendarKit source code itself. The package is a simple SwiftPM dependency with no nested package dependencies or binary artifacts. A clean rebuild showed the hang correlated with local Xcode/macOS environment state after manual cache cleanup.

**Root cause found:**

- Xcode had been configured to use custom build output paths:
  - `~/XcodeDerivedData/Todus`
  - `~/Desktop/Build/Intermediates.noindex`
- After caches were manually deleted, those non-default locations interacted badly with execution-policy registration (`syspolicyd`) and later with a corrupted `XCBuildData/build.db`.

**Fixes applied:**

- Reset Xcode build location preferences back to default DerivedData behavior
- Cleared Todus DerivedData and SwiftPM caches
- Re-resolved package dependencies so CalendarKit was checked out fresh
- Regenerated `apps/ios/Todus/Todus.xcodeproj` from `apps/ios/Todus/project.yml`
- Excluded `**/archived/**` from the iOS target so clean builds do not pull in stale duplicate files like `Navigation/archived/CustomTabBar.swift`

**What this proved:**

- `RegisterExecutionPolicyException` for CalendarKit now completes in a clean isolated build path
- The remaining failures after the reset were ordinary project/source issues surfaced by a true clean build, not CalendarKit registration hangs

**Files changed:**

- `apps/ios/Todus/project.yml`
- `apps/ios/Todus/Todus.xcodeproj/project.pbxproj`
- `apps/ios/Todus/status_ios.md`
