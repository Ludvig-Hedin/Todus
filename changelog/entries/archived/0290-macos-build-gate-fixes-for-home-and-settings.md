---
id: 0290
title: "macOS build gate fixes for Home and Settings"
status: archived
category: Fixed
release_date: 2026-05-21
source: CHANGELOG.md
---

## [2026-05-21] macOS build gate fixes for Home and Settings

- **Home dashboard compile fix** — Kept `HoverableRow` nested inside `MacHomeView` and restored the correct enclosing brace placement after the helper, fixing the Swift syntax error that stopped the macOS build.
- **Settings compiler complexity fix** — Moved the dynamic single-field settings encoder out of `MacAppServices.syncSetting` because Swift 6 rejects nested generic types in generic functions. Split `MacSettingsView` into smaller layout, sync, lifecycle, and dialog helper chains so SwiftUI type-checking completes reliably.
- **Validation** — `xcodebuild -project apps/macos/TodusMac.xcodeproj -scheme TodusMac build` now succeeds. Existing `MacVoiceChatPanel.swift` `nonisolated(unsafe)` warnings remain.
