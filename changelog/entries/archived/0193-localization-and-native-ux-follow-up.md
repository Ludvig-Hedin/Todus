---
id: 0193
title: "Localization and Native UX Follow-Up"
status: archived
category: Changed
release_date: 2026-04-04
source: CHANGELOG.md
---

## [2026-04-04] Localization and Native UX Follow-Up

### iOS (`apps/ios/Todus`)

- **Touch target documentation:** Clarified that `minTouchTarget()` enforces a visible minimum 44x44 frame and then expands the hit target further, so the comment now matches the actual modifier behavior.

### macOS (`apps/macos`)

- **Connection filter recovery:** When removed accounts invalidate the previously enabled set, the macOS connections service now re-enables the remaining current connections instead of leaving the app with an empty enabled set.

### Web (`apps/mail`)

- **Locale cleanup:** Updated targeted Arabic, Spanish, Hungarian, Korean, Czech, French, Catalan, Latvian, English, and Polish message keys for missing translations, terminology consistency, tone consistency, and review-friendly JSON formatting where requested.
- **Translation key normalization:** Standardized `favorites` and `failedToSaveLabel` message keys across the locale catalog, aligned the Arabic bin label with existing trash copy, removed accidental Catalan newline padding, and added the missing Polish `many` plural form for note counts.

### macOS (`apps/macos`)

- **Project portability:** Replaced the hardcoded Swift-auth source path in the Xcode project with a relative reference, removed the duplicate `ConnectionsService.swift` compile entry, and set a concrete default build configuration.
