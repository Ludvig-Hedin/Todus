---
id: 0063
title: "iOS Settings overhaul — Google avatar, functional toggles, sync direction, brand icon fix"
status: archived
category: Fixed
release_date: 2026-03-27
source: CHANGELOG.md
---

## [2026-03-27] iOS Settings overhaul — Google avatar, functional toggles, sync direction, brand icon fix

### Account Section

- **Google avatar + name**: Account card now shows AsyncImage from Google profile URL, display name, and email. Falls back to letter-initial circle if no image. `fetchUserProfile()` called on auth completion and when settings opens.
- **Logout moved into account card**: Removed standalone logout section; logout button now lives inside the Account section card.
- **Removed "Signed in" badge**: Email address shown below name instead.

### Email Section (functional toggles)

- **Swipe Gestures**: Toggle now bound to `services.swipeGesturesEnabled` (was static).
- **Email Signature**: Toggle bound to `services.signatureEnabled`; inline text field appears when enabled, bound to `services.signatureText`.
- **Thread Grouping**: Toggle bound to `services.threadGroupingEnabled` (was `.constant(true)`).

### Reminders Sync Direction

- **`RemindersSyncDirection` enum** added to `SyncModels.swift`: `.twoWay`, `.toReminders`, `.fromReminders` with titles, subtitles, icons.
- **RemindersSetupView**: Added inline picker for sync direction (shown when sync is enabled).

### Icons on all settings items

- Added `Label(_, systemImage:)` to AI, Preferences, About, Privacy sections.

### Brand Icon Fix

- Added `.aspectRatio(1, contentMode: .fit)` to `GmailIconView`, `AppleCalendarIconView`, `AppleRemindersIconView` to prevent stretching.

### Files

- `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift` — Full rewrite
- `apps/ios/Todus/Todus/Features/Settings/RemindersSetupView.swift` — Sync direction picker
- `apps/ios/Todus/Todus/Domain/SyncModels.swift` — RemindersSyncDirection enum
- `apps/ios/Todus/Todus/DesignSystem/BrandIcons.swift` — 1:1 aspect ratio fix
- `apps/ios/Todus/Todus/Services/Auth/AuthService.swift` — fetchUserProfile on auth completion
