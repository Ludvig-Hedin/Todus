---
id: 0043
title: "iOS — Fix Gmail connection persistence + Connect/Permission view consistency"
status: archived
category: Fixed
release_date: 2026-03-27
source: CHANGELOG.md
---

## [2026-03-27] iOS — Fix Gmail connection persistence + Connect/Permission view consistency

### Bug Fixes

- **Gmail connection not persisting after onboarding**: `GmailOnboardingView` now calls `emailService.checkConnection()` + `loadThreads()` after OAuth, so the email tab reflects the connected state immediately.
- **`hasConnection` default changed from `true` to `false`**: Prevents a brief flash of the thread list before `checkConnection()` runs on first load.

### Visual Consistency

- **EmailConnectView**: Rewritten to match `GmailOnboardingView` exactly — uses `GmailIconView(size: 88)` icon, `AppPrimaryButtonStyle()` button with `GmailIconView(size: 20)` inline, same spacing/typography.
- **CalendarPermissionView**: Rewritten to match onboarding styling — uses `AppleCalendarIconView(size: 88)` instead of generic SF Symbol, `AppPrimaryButtonStyle()` buttons, same layout pattern.

### Files Changed

- `GmailOnboardingView.swift` — Added `checkConnection()` + `loadThreads()` after successful OAuth
- `EmailConnectView.swift` — Full rewrite to match onboarding styling
- `CalendarPermissionView.swift` — Full rewrite to match onboarding styling
- `EmailService.swift` — `hasConnection` default changed from `true` to `false`
