---
id: 0127
title: "Feature — S3: iOS Settings navigation-based restructure"
status: archived
category: Added
release_date: 2026-03-31
source: CHANGELOG.md
---

## [2026-03-31] Feature — S3: iOS Settings navigation-based restructure

### iOS — `SettingsView.swift`

- Active Sessions → `SessionsSettingsView` sub-page; main settings shows session-count badge NavigationLink
- AI Assistant → `AIAssistantSettingsView` sub-page (two large TextEditors removed from main list); profile saved on `.onDisappear`
- Appearance → `AppearanceSettingsView` sub-page (vertical row list replaces cramped three-column picker); main settings shows current theme name as subtitle
- Removed unused `headerCell`, `valueCell`, `formatSessionDate`, `revokingSessionIDs`, `isRevokingAllSessions` from main view

**Files:** `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`
