---
id: 0253
title: "Fix — iOS Gmail OAuth connection flow"
status: archived
category: Fixed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Fix — iOS Gmail OAuth connection flow

- [Fix] iOS Gmail onboarding now uses the Gmail link-social flow instead of auth-only Google sign-in, so the OAuth redirect grants mail scopes and creates the backend connection row before the app marks Gmail as configured.
- [Fix] iOS onboarding, empty-mail connect, and Settings now share `EmailService.connectGmail`, including forced connection polling while Better Auth account hooks persist the connection.
- [Fix] Shared native auth ignores `todus://link-callback` if it is delivered through app URL handling, avoiding a false "Sign-in failed" state after a successful link-social OAuth flow on iOS/macOS.
- **Files:** `apps/ios/Todus/Todus/Services/Email/EmailService.swift`, `apps/ios/Todus/Todus/App/GmailOnboardingView.swift`, `apps/ios/Todus/Todus/Features/Email/EmailConnectView.swift`, `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`, `packages/swift-auth/Sources/TodusAuth/AuthService.swift`
