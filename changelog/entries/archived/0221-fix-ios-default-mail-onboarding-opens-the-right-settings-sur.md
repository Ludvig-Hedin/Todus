---
id: 0221
title: "Fix — iOS default-mail onboarding opens the right Settings surface"
status: archived
category: Fixed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Fix — iOS default-mail onboarding opens the right Settings surface

- [Fix] **iOS:** `DefaultMailOnboardingView` now uses Apple’s `UIApplication.openDefaultApplicationsSettingsURLString` instead of `openSettingsURLString`, so the CTA targets the global **Default Apps** Settings page rather than Todus’s app-specific Settings page.
- [User-facing] The onboarding button label now reads **Open Default Apps**, and the helper copy explains the fallback path if iOS still lands on Todus settings on a given OS build.
- [Architectural] **iOS + macOS:** Investigation confirmed both native targets already register `mailto` in `Info.plist`, but neither entitlements file currently declares Apple’s `com.apple.developer.mail-client` capability. Without that entitlement being granted in the Apple Developer profile and provisioning setup, Todus will not appear as a selectable default mail app in system settings.
- [Files] `apps/ios/Todus/Todus/App/DefaultMailOnboardingView.swift`, `CHANGELOG.md`, `TASK.md`
