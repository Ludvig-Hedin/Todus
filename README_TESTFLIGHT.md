# Todus TestFlight Readiness

Last updated: 2026-06-19

This file tracks the current native iOS/macOS release flow. The old WebView-wrapper
instructions are obsolete.

## Active App Targets

| Platform | Path                  | Project                                  | Bundle ID                   |
| -------- | --------------------- | ---------------------------------------- | --------------------------- |
| iOS      | `apps/ios/Todus`      | `apps/ios/Todus/Todus.xcodeproj`         | `com.ludvighedin.todus`     |
| macOS    | `apps/macos/TodusMac` | `apps/macos/TodusMac/TodusMac.xcodeproj` | `com.ludvighedin.todus.mac` |

The iOS app is a native SwiftUI app. It uses native `URLSession` calls for backend APIs and only
uses `WKWebView` for bounded content/editor surfaces such as rendered email or docs editor content.

## Current App Store Status

Use `APP_STORE_AUDIT.md` as the authoritative readiness tracker.

As of 2026-06-19, the iOS codebase builds and simulator tests pass, but submission still requires
manual owner actions:

- Revoke the previously committed App Store Connect `.p8` key and purge/rotate any affected
  credentials.
- Complete App Store Connect metadata, screenshots, privacy labels, age rating, export compliance,
  support URL, and App Review notes.
- Create a reviewer account or full demo mode with reliable access.
- Run a signed TestFlight build on physical devices.
- Verify account deletion and connected-provider revocation in a production-like environment.

## Safe Local Validation

Run targeted checks instead of project-wide lint/format commands.

```bash
plutil -lint apps/ios/Todus/Todus/Resources/Info.plist \
  apps/ios/Todus/Todus/Resources/PrivacyInfo.xcprivacy \
  apps/ios/Todus/Todus/Resources/Todus.entitlements

pnpm ios:simulator
```

For full simulator build/test validation, use Xcode or XcodeBuildMCP against:

- Project: `apps/ios/Todus/Todus.xcodeproj`
- Scheme: `Todus`
- Configuration: `Debug` for local validation, `Release` for archive validation

## App Review Notes

The final App Review notes should include:

- Backend URL and support URL.
- Reviewer credentials and exact sign-in steps.
- Which optional permissions can be skipped.
- How to test account deletion.
- Any disabled/beta features.
- Billing behavior for the submitted iOS build.

Do not submit while App Store Review blockers remain open in `APP_STORE_AUDIT.md`.
