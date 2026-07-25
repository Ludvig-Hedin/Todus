---
id: 0276
title: "Change — Hide default-mail onboarding until Apple grants the capability"
status: archived
category: Changed
release_date: 2026-04-26
source: CHANGELOG.md
---

## [2026-04-26] Change — Hide default-mail onboarding until Apple grants the capability

- [Fix] **iOS + macOS:** The default-mail onboarding screens are now skipped in the live onboarding flow, while the underlying views and persisted state remain in the codebase for later re-enablement.
- [User-facing] Native onboarding now ends after the notifications step instead of surfacing a broken “make Todus your mail app” step.
- [Architectural] This is a routing-only change. `DefaultMailOnboardingView`, `MacDefaultMailOnboardingView`, and `hasConfiguredDefaultMailPrompt` were intentionally preserved because `com.apple.developer.mail-client` has not yet been granted for the app IDs.
- [Files] `apps/ios/Todus/Todus/App/RootView.swift`, `apps/macos/TodusMac/App/MacRootView.swift`, `CHANGELOG.md`, `TASK.md`
