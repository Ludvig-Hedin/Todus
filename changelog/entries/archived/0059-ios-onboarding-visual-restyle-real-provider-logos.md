---
id: 0059
title: "iOS Onboarding — visual restyle + real provider logos"
status: archived
category: Changed
release_date: 2026-03-27
source: CHANGELOG.md
---

## [2026-03-27] iOS Onboarding — visual restyle + real provider logos

### Changed

- **Onboarding visual refresh**: Restyled onboarding layouts to match the app's current spacing, typography, and button rhythm used elsewhere in iOS.
- **Real provider logos**: Replaced generic SF Symbol icons with the same branded provider icons used in Settings:
  - Gmail onboarding now uses `GmailIconView`
  - Reminders onboarding now uses `AppleRemindersIconView`
- **Primary CTA alignment**: Added small provider logos inside the primary connect buttons for stronger visual consistency and recognizability.

### Files

- `apps/ios/Todus/Todus/App/GmailOnboardingView.swift`
- `apps/ios/Todus/Todus/Features/Settings/RemindersSetupView.swift`
