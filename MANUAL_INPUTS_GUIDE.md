# Manual Inputs Guide (iOS + macOS Native Internal Builds)

Last updated: 2026-02-21

This guide covers every manual input needed to make the native app test-ready for internal distribution on iPhone and macOS using staging backend.

## 1. Scope and Current Facts

This guide is based on current repo configuration:

- Native app root: `/Users/ludvighedin/Programming/personal/mail/apps/native`
- iOS workspace: `/Users/ludvighedin/Programming/personal/mail/apps/native/ios/ZeroNative.xcworkspace`
- macOS workspace: `/Users/ludvighedin/Programming/personal/mail/apps/native/macos/zero-native.xcworkspace`
- Native backend env key currently used in code: `ZERO_PUBLIC_BACKEND_URL` in `/Users/ludvighedin/Programming/personal/mail/apps/native/src/shared/config/env.ts`
- Staging web/backend URLs in config:
  - `https://staging.0.email`
  - `https://sapi.0.email`
- Server auth trusted origins currently include `https://staging.0.email`, `https://sapi.0.email`, and `todus://auth-callback` in `/Users/ludvighedin/Programming/personal/mail/apps/server/src/lib/auth.ts`

Current bundle IDs in native projects:

- iOS target (`ZeroNative`): `com.zero.nativeapp` in `/Users/ludvighedin/Programming/personal/mail/apps/native/ios/ZeroNative.xcodeproj/project.pbxproj`
- macOS target (`zero-native-macOS`): `org.reactjs.native.$(PRODUCT_NAME:rfc1034identifier)` in `/Users/ludvighedin/Programming/personal/mail/apps/native/macos/zero-native.xcodeproj/project.pbxproj`

## 2. Manual Input Checklist (High-Level)

Use this as your tracking list.

- [x] Apple Developer team access confirmed (Account Holder/Admin)
- [x] Final iOS bundle ID chosen and registered
- [x] Final macOS bundle ID chosen and registered
- [x] iOS App ID capabilities configured
- [x] macOS App ID capabilities configured
- [x] iOS signing certificate/provisioning profile ready
- [x] macOS signing certificate/provisioning profile ready
- [x] App Store Connect app records created for iOS and macOS
- [x] Internal tester group created in App Store Connect
- [ ] Google OAuth client(s) created for native redirect strategy
- [ ] Authorized redirect URIs and origins configured for staging
- [ ] Better Auth and server env values updated in staging
- [ ] Native staging env values set for local/internal builds
- [ ] iOS internal archive uploaded successfully
- [ ] macOS internal archive uploaded successfully
- [ ] Internal testers can sign in and use staging backend in both apps

## 3. Apple Developer Setup (Foolproof)

## 3.1 Required Role and Access

1. Log in to [Apple Developer](https://developer.apple.com/account/).
2. Confirm your account role is `Account Holder` or `Admin`.
3. Open [App Store Connect](https://appstoreconnect.apple.com/) and confirm access to:

- Users and Access
- Apps
- TestFlight

## 3.2 Decide Final Bundle IDs

Do not keep placeholder IDs for release tracks.

Recommended format:

- iOS: `com.<company-or-team>.todus.native`
- macOS: `com.<company-or-team>.todus.native.macos`

Record the chosen IDs in your release notes.

## 3.3 Register App IDs

1. Go to Certificates, Identifiers & Profiles.
2. Create two Identifiers (App IDs):

- one for iOS app
- one for macOS app

1. Ensure Bundle ID exactly matches chosen IDs.

## 3.4 Capabilities (minimum)

Enable only what is required by implemented features.

For parity baseline, verify these if used:

- Sign in with Apple (only if product requires)
- Associated Domains (if universal links are implemented)
- Push Notifications (if implemented)
- Keychain Sharing (if secure storage strategy requires shared keychain)

If a capability is not used in code yet, leave it off to reduce signing complexity.

## 3.5 Certificates and Provisioning Profiles

1. Certificates:

- iOS Distribution certificate
- macOS Distribution certificate

1. Profiles:

- iOS App Store profile for iOS app ID
- macOS App Store profile for macOS app ID

1. Download/install certs and profiles on CI/mac build machine.

## 3.6 App Store Connect App Records

1. In App Store Connect -> Apps -> New App.
2. Create app records for:

- iOS
- macOS

1. Select exact bundle IDs and team.
2. Fill minimum app metadata placeholders.

## 3.7 Internal TestFlight Setup

1. Create internal tester group (for team members only).
2. Add users as internal testers.
3. Ensure they have proper role access and accepted invite.

## 4. Update Xcode Project Signing Inputs

## 4.1 iOS Target (ZeroNative)

1. Open `/Users/ludvighedin/Programming/personal/mail/apps/native/ios/ZeroNative.xcworkspace`.
2. Select `ZeroNative` target.
3. In Signing & Capabilities:

- Team: set your Apple Team
- Bundle Identifier: set final iOS ID
- Signing Certificate: Apple Distribution
- Provisioning Profile: App Store profile

1. Apply for both Debug and Release if needed for internal testing consistency.

## 4.2 macOS Target (zero-native-macOS)

1. Open `/Users/ludvighedin/Programming/personal/mail/apps/native/macos/zero-native.xcworkspace`.
2. Select `zero-native-macOS` target.
3. In Signing & Capabilities:

- Team: set your Apple Team
- Bundle Identifier: set final macOS ID
- Signing Certificate: Apple Distribution
- Provisioning Profile: App Store profile

## 4.3 Commit Bundle ID Changes

Bundle IDs are currently defined in project files and must be committed after update:

- `/Users/ludvighedin/Programming/personal/mail/apps/native/ios/ZeroNative.xcodeproj/project.pbxproj`
- `/Users/ludvighedin/Programming/personal/mail/apps/native/macos/zero-native.xcodeproj/project.pbxproj`

## 5. Google OAuth + Better Auth Inputs (Staging)

## 5.1 Google Cloud OAuth Client Setup

You need OAuth client configuration compatible with native handoff/callback design.

1. Open [Google Cloud Console](https://console.cloud.google.com/).
2. Go to APIs & Services -> Credentials.
3. Ensure OAuth consent screen is configured for internal/testing.
4. Create/update OAuth client credentials required by backend auth flow.

Use env keys already required by server:

- `GOOGLE_CLIENT_ID`
- `GOOGLE_CLIENT_SECRET`

These keys are referenced in:

- `/Users/ludvighedin/Programming/personal/mail/apps/server/src/env.ts`
- `/Users/ludvighedin/Programming/personal/mail/apps/server/src/lib/auth-providers.ts`

## 5.2 Redirect URI and Origin Inputs

Ensure staging web/backend domains are allowed where required:

- `https://staging.0.email`
- `https://sapi.0.email`

If native callback URI is used directly, also include scheme callback:

- `todus://auth-callback`

This scheme is currently in trusted origins in server auth config.

## 5.3 Better Auth Staging Values

Ensure these values are correct in staging secrets/config:

- `BETTER_AUTH_SECRET`
- `BETTER_AUTH_URL`
- `VITE_PUBLIC_APP_URL`
- `VITE_PUBLIC_BACKEND_URL`
- `COOKIE_DOMAIN`
- `BETTER_AUTH_TRUSTED_ORIGINS` (if your deployment path uses this env)

Source references:

- `/Users/ludvighedin/Programming/personal/mail/apps/server/src/env.ts`
- `/Users/ludvighedin/Programming/personal/mail/apps/server/src/lib/auth.ts`

## 6. Native Staging Environment Inputs

## 6.1 Required Native Env Key

Set backend URL for native app runtime:

- `ZERO_PUBLIC_BACKEND_URL=https://sapi.0.email`

Code source:

- `/Users/ludvighedin/Programming/personal/mail/apps/native/src/shared/config/env.ts`

## 6.2 Local Command Example

Use this pattern when launching iOS/macOS locally against staging:

```bash
ZERO_PUBLIC_BACKEND_URL=https://sapi.0.email pnpm --filter @zero/native ios
ZERO_PUBLIC_BACKEND_URL=https://sapi.0.email pnpm --filter @zero/native macos
```

## 7. Internal Build Packaging Inputs

## 7.1 iOS Internal Build

1. In Xcode, select `ZeroNative` scheme.
2. Generic iOS Device destination.
3. Product -> Archive.
4. Distribute App -> App Store Connect -> Upload.
5. In App Store Connect -> TestFlight, wait for processing.
6. Assign build to internal tester group.

## 7.2 macOS Internal Build

1. In Xcode, select `zero-native-macOS` scheme.
2. Any Mac (or generic macOS destination).
3. Product -> Archive.
4. Distribute App -> App Store Connect -> Upload.
5. Assign to internal tester group.

## 7.3 Build Metadata Inputs

For both platforms, verify:

- Version (`CFBundleShortVersionString`) is incremented when needed
- Build number (`CFBundleVersion`) is incremented each upload

## 8. Pre-Flight Verification Checklist (Before sharing build)

- [ ] Native app points to staging backend (`https://sapi.0.email`)
- [ ] Login works with test account
- [ ] Session persists across restart
- [ ] Inbox loads real staging data
- [ ] Compose + send works
- [ ] Settings updates persist
- [ ] Logout works and guards redirect correctly
- [ ] No blocking crash in first 10 minutes usage on iPhone
- [ ] No blocking crash in first 10 minutes usage on macOS

## 9. Common Failure Modes and Fixes

## 9.1 OAuth returns to web instead of app

Cause:

- redirect URI mismatch or missing native callback registration.

Fix:

- verify callback URI config in Google and Better Auth trusted origins.
- verify native URL scheme registration in app targets when callback implementation is added.

## 9.2 Staging login works on web but fails in native

Cause:

- native app using wrong backend URL or missing auth headers/session exchange.

Fix:

- confirm `ZERO_PUBLIC_BACKEND_URL` is set to `https://sapi.0.email`.
- verify backend auth endpoints and trusted origins include staging/native callback.

## 9.3 Xcode signing fails during archive

Cause:

- team/profile/certificate mismatch.

Fix:

- re-check target Bundle ID, Team, Signing Certificate, Provisioning Profile for both platforms.

## 9.4 Podfile lock mismatch errors

Cause:

- pods not synced with lock file.

Fix:

```bash
cd /Users/ludvighedin/Programming/personal/mail/apps/native
bundle install
pnpm --filter @zero/native pod-install
```

## 10. Final Manual Signoff Template

Copy this section into your release ticket and mark values explicitly.

- Apple Team ID:
- iOS Bundle ID:
- macOS Bundle ID:
- iOS App Store Connect App ID:
- macOS App Store Connect App ID:
- OAuth Client ID in staging:
- OAuth callback URI(s):
- Native backend URL:
- Internal tester group name:
- iOS build number uploaded:
- macOS build number uploaded:
- Signoff owner:
- Signoff date:
