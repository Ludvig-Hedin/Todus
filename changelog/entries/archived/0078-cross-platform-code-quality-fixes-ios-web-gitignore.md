---
id: 0078
title: "Cross-platform code quality fixes — iOS, web, gitignore"
status: archived
category: Fixed
release_date: 2026-03-29
source: CHANGELOG.md
---

## [2026-03-29] Cross-platform code quality fixes — iOS, web, gitignore

### Summary

Batch of code quality fixes across iOS and web apps:

- **`.gitignore`**: Added `.deriveddata/` and `DerivedData/` to prevent Xcode build artifacts from being committed
- **`Info.plist`**: Added standard bundle identification keys (CFBundleIdentifier, CFBundleVersion, etc.) using build setting variables
- **`project.pbxproj`**: Removed stale build references for deleted files (CardViews.swift, ChatUISpec.swift, ChatUISpecView.swift)
- **`GmailOnboardingView`**: Updated copy to include explicit permission disclosure ("Grant access to...")
- **`EmailInboxView`**: Fixed misleading empty state text — replaced "Pull down to refresh" with "Tap Refresh" since pull-to-refresh is only on the thread list
- **`SettingsView`**: Updated Email & AI section footer to describe all controls in the section
- **`MainTabView`**: Added `.snappy` animation to requestCreateSheet handler to match tab bar behavior
- **`AuthService`**: Reset `isSessionExpired` in `signOut()` to prevent stale banner after sign-out
- **`en.json`**: Added `common.actions.unsavedChanges` i18n key
- **`general/page.tsx`**: Replaced hardcoded "Unsaved changes" with i18n call
- **`mail.tsx`**: Added `aria-label="Compose email"` to floating compose button for screen reader accessibility
- **`signatures/page.tsx`**: Replaced hardcoded title/description with i18n message calls

**Files changed:**

- `.gitignore`
- `apps/ios/Todus/Todus.xcodeproj/Info.plist`
- `apps/ios/Todus/Todus.xcodeproj/project.pbxproj`
- `apps/ios/Todus/Todus/App/GmailOnboardingView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`
- `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`
- `apps/ios/Todus/Todus/Navigation/MainTabView.swift`
- `apps/ios/Todus/Todus/Services/Auth/AuthService.swift`
- `apps/mail/messages/en.json`
- `apps/mail/app/(routes)/settings/general/page.tsx`
- `apps/mail/components/mail/mail.tsx`
- `apps/mail/app/(routes)/settings/signatures/page.tsx`
