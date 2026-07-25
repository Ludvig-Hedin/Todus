---
id: 0079
title: "iOS UX Fixes — Auth links, onboarding copy, action grouping, create sheet, search indicator, empty states, send error, session confirm, AI detent, settings regrouping"
status: archived
category: Fixed
release_date: 2026-03-29
source: CHANGELOG.md
---

## [2026-03-29] iOS UX Fixes — Auth links, onboarding copy, action grouping, create sheet, search indicator, empty states, send error, session confirm, AI detent, settings regrouping

### Summary

Batch of iOS UX improvements across 9 files:

- **I13 AuthView**: Terms of Service and Privacy Policy are now tappable links opening todus.app/terms and todus.app/privacy
- **I2 GmailOnboardingView**: Updated copy to be benefit-oriented ("See your inbox, reply to emails...")
- **I3 EmailThreadView**: Added visual divider between non-destructive (star, unread) and destructive (archive, trash) action buttons
- **I5 HomeView + AppServices + MainTabView**: Events and Tasks "+" buttons now open CreateSheet directly instead of navigating to another tab
- **I8 EmailInboxView**: Added inline "Searching..." indicator when search is in progress
- **I11 EmailInboxView**: Improved empty state with refresh button and better copy
- **I10 EmailComposeView**: Added error alert when email send fails
- **I12 MainTabView**: Session expired banner now shows confirmation dialog before signing out
- **I15 MainTabView**: AI chat sheet uses .medium detent instead of .fraction(0.5)
- **I9 SettingsView**: Merged 9 sections into 4 logical groups (Preferences, Email & AI, Notifications & Privacy, About)

**Files changed:**

- `apps/ios/Todus/Todus/Features/Auth/AuthView.swift`
- `apps/ios/Todus/Todus/App/GmailOnboardingView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift`
- `apps/ios/Todus/Todus/Features/Home/HomeView.swift`
- `apps/ios/Todus/Todus/App/AppServices.swift`
- `apps/ios/Todus/Todus/Navigation/MainTabView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailComposeView.swift`
- `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`
