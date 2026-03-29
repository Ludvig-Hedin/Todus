# TestFlight Checklist (iOS + macOS)

## Active app targets

- iOS app: `apps/ios/Todus` (SwiftUI/Xcode)
- macOS app: `apps/macos` (SwiftUI/Xcode)

Archived apps under `apps/archived/*` are not part of release flow.

## 0. One-time Apple setup

1. Apple Developer account is active.
2. App Store Connect app exists: `Todus`.
3. iOS bundle identifier in `apps/ios/app.config.ts` is correct.
4. EAS credentials/signing are configured for the iOS app.

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

Open `apps/ios/Todus/Todus.xcodeproj` in Xcode, archive the `Todus` scheme, and upload the build via Organizer.

2. In App Store Connect TestFlight tab:
   - wait for build processing
   - add internal testers first
   - add external testers after beta review if needed

## 3. macOS release note

`apps/macos` is now a native SwiftUI macOS app. The current shell scaffold is Xcode-run only and is not yet part of a production TestFlight flow.

## 4. Pre-invite smoke test

1. Fresh install from TestFlight on iPhone.
2. Login works and returns into app.
3. Inbox loads from `api.todus.app`.
4. Sign out/sign in works repeatedly.
5. App icon/name are `Todus`.
