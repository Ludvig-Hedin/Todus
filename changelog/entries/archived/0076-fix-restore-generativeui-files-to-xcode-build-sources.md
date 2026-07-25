---
id: 0076
title: "Fix — Restore GenerativeUI files to Xcode build sources"
status: archived
category: Fixed
release_date: 2026-03-29
source: CHANGELOG.md
---

## [2026-03-29] Fix — Restore GenerativeUI files to Xcode build sources

ChatUISpec.swift, ChatUISpecView.swift, and CardViews.swift were removed from the Xcode project (PBXBuildFile, PBXFileReference, PBXGroup, PBXSourcesBuildPhase) during prior cleanup of the GenerativeUI subdirectory, but the files still exist at Features/AI/ and are actively referenced by AIChatMessage.swift, AIChatView.swift, and AIChatService.swift. Re-added all three files to the project to fix "Cannot find type" build errors.

**Files changed:** `apps/ios/Todus/Todus.xcodeproj/project.pbxproj`
