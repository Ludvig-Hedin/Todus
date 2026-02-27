# TestFlight Checklist (iOS + macOS)

## 0. One-time Apple setup

1. Apple Developer account is active.
2. App Store Connect app exists: `Todus`.
3. Bundle IDs are created in Apple Developer:

- `se.ludvighedin.Todus.ios` (iOS)
- `se.ludvighedin.Todus` (macOS)

4. Signing certificates are valid in Xcode.

## 1. Cloudflare production names and domains

1. Frontend Worker: `todus-production`.
2. Backend Worker: `todus-server-v1-production`.
3. Custom domains:

- `todus.app` -> frontend Worker
- `api.todus.app` -> backend Worker

4. Backend/auth env vars match custom domains:

- `VITE_PUBLIC_APP_URL=https://todus.app`
- `VITE_PUBLIC_BACKEND_URL=https://api.todus.app`
- `BETTER_AUTH_URL=https://api.todus.app`
- `COOKIE_DOMAIN=todus.app`

## 2. Xcode project setup (GUI)

1. Open `/Users/ludvighedin/Programming/personal/mail/apps/apple/Todus/Todus.xcodeproj`.
2. Select target `Todus`.
3. In `Signing & Capabilities`:

- Enable `Automatically manage signing`
- Select your team
- Confirm unique bundle IDs per platform

4. In `General`:

- Set app name to `Todus`
- Set version + build number
- Confirm deployment targets

5. In `Archive` scheme:

- Pick `Any iOS Device (arm64)` for iOS archive
- Pick `Any Mac` for macOS archive

## 3. iOS TestFlight release

1. In Xcode, destination: `Any iOS Device (arm64)`.
2. `Product` -> `Archive`.
3. In Organizer, pick latest archive.
4. Click `Distribute App` -> `App Store Connect` -> `Upload`.
5. Wait for processing in App Store Connect (`TestFlight` tab).
6. Add `Internal Testers` first.
7. For friends outside team, submit build for `External Testing`.

## 4. macOS TestFlight release

1. In Xcode, destination: `Any Mac`.
2. `Product` -> `Archive`.
3. In Organizer, upload to App Store Connect.
4. After processing, enable build in `TestFlight` for macOS.
5. Add internal testers, then external testers if needed.

## 5. Pre-invite smoke test

1. Fresh install from TestFlight on iPhone and Mac.
2. Google login opens secure auth and returns to app.
3. Inbox loads from your backend (`api.todus.app`).
4. Sign out/sign in works twice in a row.
5. App icon/name are correct (`Todus`).

## 6. Common blockers

1. Stuck in browser after login: callback URL or trusted origin mismatch.
2. `disallowed_useragent`: OAuth launched inside plain WebView instead of secure auth session.
3. Build uploads but not visible: still processing in App Store Connect (can take 10-30 min).
4. External testers blocked: missing beta app review for that platform/build.
