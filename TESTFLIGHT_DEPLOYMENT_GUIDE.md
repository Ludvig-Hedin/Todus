# TestFlight Deployment Guide

Last updated: 2026-06-19

This guide covers the active native SwiftUI iOS app. It intentionally does not describe the retired
WebView-wrapper flow.

## 1. Preflight

Before archiving:

- Confirm `APP_STORE_AUDIT.md` has no unresolved critical submission blockers.
- Confirm the App Store Connect `.p8` key that was previously committed has been revoked and rotated.
- Confirm production backend, OAuth providers, email delivery, AI providers, and account deletion are
  available during review.
- Confirm App Store Connect metadata is complete: screenshots, privacy labels, age rating, export
  compliance, review notes, support URL, and privacy URL.

## 2. Local Validation

Run targeted plist checks:

```bash
plutil -lint apps/ios/Todus/Todus/Resources/Info.plist \
  apps/ios/Todus/Todus/Resources/PrivacyInfo.xcprivacy \
  apps/ios/Todus/Todus/Resources/Todus.entitlements
```

Run the iOS app locally:

```bash
pnpm ios:simulator
```

For simulator build/test validation, use:

- Project: `apps/ios/Todus/Todus.xcodeproj`
- Scheme: `Todus`
- Simulator: any currently supported iPhone simulator

## 3. Archive

Open the active project:

```bash
open apps/ios/Todus/Todus.xcodeproj
```

In Xcode:

1. Select scheme `Todus`.
2. Select `Any iOS Device`.
3. Confirm signing team, bundle ID `com.ludvighedin.todus`, version, and build number.
4. Product -> Archive.
5. Validate the archive.
6. Upload to App Store Connect.

## 4. TestFlight QA

Install the uploaded build from TestFlight and verify on physical devices:

- Fresh install and launch.
- Apple sign-in and reviewer-account sign-in path.
- Optional permission prompts can be skipped.
- Home, Tasks, Email, Calendar, AI, Docs, Meetings, Settings.
- Offline/reconnect behavior.
- Logout and reinstall.
- Delete-account flow reaches the backend and does not falsely report success on failure.
- Billing screen does not link to external web checkout or hosted billing portals in the iOS build.

## 5. App Review Submission

Before submitting the build for App Review:

- Add detailed App Review notes with reviewer credentials and feature walkthrough.
- Keep backend services live for the full review window.
- Verify the privacy policy URL reflects the current hosted Todus service.
- Verify App Store privacy labels match the app, server, and providers.
- Verify no placeholder/test-only copy is visible in the submitted build.

If a blocker appears during TestFlight QA, fix it before App Review submission rather than explaining
around it in review notes.
