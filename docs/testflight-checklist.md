# TestFlight Checklist

## Active app targets

- iOS app: `apps/ios/Todus` (native SwiftUI/Xcode)
- macOS app: `apps/macos` (native SwiftUI/Xcode, separate desktop release flow)

Archived apps under `apps/archived/*` are not part of release flow.
Legacy `apps/mail` is not the active iOS or web release target.

## 0. One-time Apple setup

1. Apple Developer account is active.
2. App Store Connect app exists: `Todus`.
3. iOS bundle identifier is `com.ludvighedin.todus`.
4. Xcode signing is configured for the `Todus` target and the production Apple team.
5. App Store Connect `.p8` keys that were previously committed have been revoked/rotated.

## 1. Cloudflare production names and domains

1. Frontend: `todus.app`
2. Backend: `api.todus.app`
3. Backend/auth env vars match custom domains:
   - `VITE_PUBLIC_APP_URL=https://todus.app`
   - `VITE_PUBLIC_BACKEND_URL=https://api.todus.app`
   - `BETTER_AUTH_URL=https://api.todus.app`
   - `COOKIE_DOMAIN=todus.app`

## 2. iOS TestFlight release (native SwiftUI)

1. From repo root:

Run local validation:

```bash
plutil -lint \
  apps/ios/Todus/Todus/Resources/Info.plist \
  apps/ios/Todus/Todus/Resources/PrivacyInfo.xcprivacy \
  apps/ios/Todus/Todus/Resources/Todus.entitlements

xcodebuild -project apps/ios/Todus/Todus.xcodeproj \
  -scheme Todus \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

2. Open `apps/ios/Todus/Todus.xcodeproj` in Xcode, archive the `Todus` scheme, and upload the build via Organizer.

3. In App Store Connect TestFlight tab:
   - wait for build processing
   - add internal testers first
   - add external testers after beta review if needed

## 3. App Store Connect release metadata

Complete before App Review:

- Screenshots and description.
- Privacy URL: `https://todus.app/privacy`
- Support URL: `https://todus.app/contact`
- App privacy labels matching the iOS app, backend, AI providers, diagnostics, and connected-account data.
- Age rating, export compliance, DSA/trader status, review notes, and reviewer credentials.

## 4. macOS release note

`apps/macos` is a native SwiftUI macOS app, but it is separate from this iOS TestFlight checklist.

## 5. Pre-invite smoke test

1. Fresh install from TestFlight on iPhone.
2. Login works and returns into app.
3. Inbox loads from `api.todus.app`.
4. Sign out/sign in works repeatedly.
5. App icon/name are `Todus`.
6. Billing does not open external web checkout or hosted billing portals.
7. First AI chat send or voice start shows the cloud-processing disclosure.
8. Account deletion can be initiated in Settings and reports backend failure instead of signing out locally.
