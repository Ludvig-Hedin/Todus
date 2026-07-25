---
id: 0223
title: "Fix — Native navigation/settings credibility pass (iOS + macOS)"
status: archived
category: Fixed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Fix — Native navigation/settings credibility pass (iOS + macOS)

- [Fix] **iOS:** `MainTabView` now uses the existing floating `CustomTabBar` fed by `services.tabBarTabs`, while the underlying `TabView` keeps content state alive. Tab-bar onboarding and Settings customization now change the real navigation shell, including support for pinning **Meetings** into the main bar.
- [Fix] **iOS:** Thread overflow menu now has a real **Set reminder** flow with quick presets (1 hour, tonight, tomorrow morning) backed by local notifications instead of a dead-end placeholder. Reminder scheduling now reports failure when notification permission is off.
- [Fix] **iOS:** Default-mail onboarding copy/button now matches what the app can actually do on-device: it opens Todus inside Settings and explains the manual step back to **Default Apps → Email**, instead of falsely implying the CTA jumps straight there.
- [Fix] **iOS:** Email Settings toggles are now wired through the inbox. `Swipe Gestures` disables/enables mail swipe actions, and `Group by Thread` persists and drives the Threads/People inbox mode instead of being a dead preference.
- [Fix] **macOS:** Launch behavior now separates **Open on Launch** from **Resume Last Viewed Page**. `startupView` is honored by default, and last-view restore remains available as an explicit Settings toggle instead of silently overriding the launch page preference.
- [Fix] **macOS:** Existing preferences now affect real UI. `Compact Sidebar` changes sidebar column width, `Show Unread Badge` controls unread indicators/badges in Mail surfaces, and `Group by Thread` persists and drives the Threads/People inbox mode.
- [Files] `apps/ios/Todus/Todus/Navigation/MainTabView.swift`, `apps/ios/Todus/Todus/Features/Tasks/CustomTabBar.swift`, `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`, `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift`, `apps/ios/Todus/Todus/Services/Notifications/NotificationService.swift`, `apps/ios/Todus/Todus/App/DefaultMailOnboardingView.swift`, `apps/macos/TodusMac/App/MacAppServices.swift`, `apps/macos/TodusMac/App/MacRootView.swift`, `apps/macos/TodusMac/App/MacSidebarView.swift`, `apps/macos/TodusMac/Views/Email/MacEmailInboxView.swift`, `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`
