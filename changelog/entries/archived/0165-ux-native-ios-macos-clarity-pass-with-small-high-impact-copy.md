---
id: 0165
title: "UX — Native iOS/macOS clarity pass with small, high-impact copy and guidance updates"
status: archived
category: Changed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] UX — Native iOS/macOS clarity pass with small, high-impact copy and guidance updates

- **iOS onboarding (`RootView.swift`, `GmailOnboardingView.swift`, `RemindersSetupView.swift`, `TabBarOnboardingView.swift`):** Added a compact onboarding progress pill across the Gmail, Reminders, and tab-bar setup steps. Tightened the onboarding benefit copy and renamed the tab-bar customization buckets to `Pinned tabs` and `Available tabs`, plus added a clearer preview helper line.
- **iOS shell (`MainTabView.swift`):** Added a one-time, non-blocking coachmark overlay for the floating tab bar so first-time users get quick context for `More spaces`, `Ask AI`, and `Create` without adding permanent tab labels.
- **iOS tasks/email/home/create (`TasksTabView.swift`, `EmailInboxView.swift`, `HomeView.swift`, `CreateSheet.swift`):** Added current-mode and active-sort clarity in Tasks, a first-use folder-switch hint in Email, renamed Home's overflow section to `Other Spaces` with clearer helper text, and refined the Create overlay with simpler placeholder/helper copy plus lighter visual emphasis on advanced metadata controls.
- **macOS shell/auth/search/brief (`MacRootView.swift`, `MacAuthView.swift`, `MacSearchView.swift`, `MacNotificationCenterView.swift`):** Reframed the bell surface as a `Daily Brief`, tightened auth/restoring reassurance copy, clarified search intent, and subtly increased toolbar emphasis for create/search while slightly de-emphasizing secondary controls.
