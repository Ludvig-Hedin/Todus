# TestFlight Quick Start

Fast path for uploading the active native iOS app. For the full release checklist, see
`TESTFLIGHT_DEPLOYMENT_GUIDE.md` and `APP_STORE_AUDIT.md`.

## 1. Confirm Release Blockers

- Current iOS app: `apps/ios/Todus`
- Xcode project: `apps/ios/Todus/Todus.xcodeproj`
- Scheme: `Todus`
- Bundle ID: `com.ludvighedin.todus`
- Version/build in project config: `1.1` / `3`

Before uploading for review, confirm the manual blockers in `APP_STORE_AUDIT.md` are closed:

- App Store Connect metadata, screenshots, privacy labels, age rating, export compliance, support URL,
  and review notes.
- Reviewer account or full demo-mode access.
- Revoked/rotated App Store Connect `.p8` key material.
- Physical-device TestFlight smoke test.

## 2. Local Validation

From the repo root:

```bash
plutil -lint \
  apps/ios/Todus/Todus/Resources/Info.plist \
  apps/ios/Todus/Todus/Resources/PrivacyInfo.xcprivacy \
  apps/ios/Todus/Todus/Resources/Todus.entitlements \
  packages/swift-widgets/Sources/TodusWidgetsExtension/Info.plist \
  packages/swift-widgets/Sources/TodusWidgetsExtension/TodusWidgets.entitlements

xcodebuild -project apps/ios/Todus/Todus.xcodeproj \
  -scheme Todus \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Run the simulator test suite before archiving if time permits:

```bash
xcodebuild test -quiet \
  -project apps/ios/Todus/Todus.xcodeproj \
  -scheme Todus \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO
```

## 3. Archive and Upload

1. Open `apps/ios/Todus/Todus.xcodeproj` in Xcode.
2. Select the `Todus` scheme.
3. Select `Any iOS Device (arm64)` or a generic iOS device destination.
4. Use `Product -> Archive`.
5. In Organizer, choose `Distribute App -> App Store Connect -> Upload`.
6. Resolve any privacy manifest, signing, entitlement, or upload warnings before assigning testers.

## 4. TestFlight Smoke Test

On a fresh TestFlight install:

- Launch and sign in with the reviewer/test account.
- Verify Home, Tasks, Email, Calendar, AI chat, voice, Docs, Meetings, Settings, Billing, and Account
  Deletion entry points.
- Verify the AI cloud-processing disclosure appears before the first chat send or voice start.
- Verify Billing does not open external web checkout or hosted billing portals in the iOS build.
- Verify public AI share-link creation and `todus://share` viewing are not present in the iOS app.
- Sign out, relaunch, sign back in, and confirm the backend remains reachable.

## 5. App Review Notes

Use the draft in `APP_STORE_AUDIT.md` as the source of truth. Include:

- Reviewer credentials and OTP/password instructions.
- Backend URL: `https://api.todus.app`
- Privacy URL: `https://todus.app/privacy`
- Support URL: `https://todus.app/contact`
- Billing posture: no paid upgrades are offered in the submitted iOS build unless StoreKit has been
  implemented.
- Any beta-disabled features and the account deletion path.
