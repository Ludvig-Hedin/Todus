# macOS Auth — Gap Analysis & Verification

## What Was Implemented

### Shared Package (`packages/swift-auth/`)
- [x] `Package.swift` — SPM manifest targeting iOS 18+ / macOS 15+
- [x] `AuthService.swift` — Full auth service with `#if canImport` for platform-specific presentation anchor
- [x] `KeychainHelper.swift` — Cross-platform Keychain CRUD
- [x] `NoRedirectDelegate.swift` — Redirect interception for token extraction
- [x] `AppleSignInDelegate.swift` — Async wrapper for Apple Sign In

### iOS Integration
- [x] `project.yml` updated with TodusAuth local package dependency
- [x] Original `AuthService.swift` replaced with `@_exported import TodusAuth` shim
- [x] `import TodusAuth` added to: AppServices, AuthView, TodosAPIClient, AIChatService, VoiceTokenService, NotificationDigestService
- [x] Xcode project regenerated

### macOS Auth
- [x] `project.yml` — TodusAuth dependency, entitlements path
- [x] `Info.plist` — `todus://` URL scheme for OAuth callbacks
- [x] `TodosConfig.plist` — Backend URL configuration
- [x] `TodusMac.entitlements` — Sign in with Apple + network client
- [x] `MacAppServices.swift` — Lightweight service container with AuthService
- [x] `MacAuthView.swift` — Full login UI: email OTP, Apple Sign In, Google Sign In, continue as guest
- [x] `TodusMacApp.swift` — Environment injection, `.onOpenURL` deep link handling
- [x] `MacRootView.swift` — Auth state gating (login vs main app), silent refresh on launch
- [x] `MacSidebarView.swift` — Wired logout, real user display name/initial

## Build Verification
- [x] `swift build` in `packages/swift-auth/` — **PASSES**
- [x] macOS `xcodebuild` (without code signing) — **PASSES**
- [x] iOS `xcodebuild` (without code signing) — Pre-existing errors in CalendarViewController.swift and ChatUISpecView.swift (unrelated to auth). All auth-related compilation succeeds.

## What Remains Incomplete

### Manual Steps Required
1. **App Store Connect**: Register macOS bundle ID (`com.ludvighedin.todus.macos`) for Sign in with Apple capability
2. **Provisioning Profile**: Create Mac App Development provisioning profile for the new bundle ID
3. **Google OAuth**: Verify Google OAuth redirect works with macOS `ASWebAuthenticationSession` (should work — same API, but needs live testing)

### Known Platform Differences
| Feature | iOS | macOS | Notes |
|---------|-----|-------|-------|
| Presentation Anchor | `UIApplication.shared.connectedScenes` | `NSApplication.shared.keyWindow` | Handled via `#if canImport` |
| Open URLs | `UIApplication.shared.open()` | `NSWorkspace.shared.open()` | Handled in platform-specific views |
| Keyboard modifiers | `.keyboardType(.emailAddress)`, `.textInputAutocapitalization(.never)` | N/A on macOS | Omitted in MacAuthView |
| Web Auth UX | System browser overlay | Sheet attached to window | Native framework behavior, no code needed |
| Keychain scope | App sandbox | App sandbox | Same API, items are app-scoped on both |
| Input styling | `Capsule()` shape | `RoundedRectangle(cornerRadius: 8)` | macOS-native feel |

### Not Yet Implemented (Future Work)
- [ ] macOS API client (TodosAPIClient equivalent) — needed for actual data fetching
- [ ] macOS email service — needed for inbox, drafts, sent
- [ ] macOS AI chat integration
- [ ] Keychain sharing between iOS and macOS (optional — requires access group)
- [ ] Session expired banner on macOS (the `isSessionExpired` property is available, just needs UI)
- [ ] Profile fetch on macOS login (silent background call — the method exists, could be triggered)

## Test Scenarios

### macOS Auth Testing
- [ ] Cold launch when logged out → shows MacAuthView
- [ ] Email OTP: enter email → receive code → enter code → authenticated → shows main app
- [ ] Apple Sign In: tap button → native Apple prompt → authenticated
- [ ] Google Sign In: tap button → browser sheet → OAuth → callback → authenticated
- [ ] Session persistence: quit app → relaunch → still authenticated (no login screen)
- [ ] Logout: User menu → "Log Out" → clears auth → returns to MacAuthView
- [ ] Invalid/expired token: relaunch → silent refresh fails → shows login
- [ ] Auth state in sidebar: user email/name displayed, initial in avatar circle
- [ ] "Continue without account" → skips auth → shows main app as guest
- [ ] Error states: wrong OTP code, network failure, cancelled Apple Sign In

### iOS Regression Testing
- [ ] All three auth methods still work (Apple, Google, Email OTP)
- [ ] Session restore on app launch works
- [ ] Logout clears state correctly
- [ ] No missing imports or compilation errors from TodusAuth migration

## Technical Debt
1. **`@_exported import` shim**: The iOS `AuthService.swift` file was kept as a `@_exported import TodusAuth` shim instead of being deleted. This is harmless but means the file exists in two logical places. Ideally delete the shim file and rely on explicit imports only.
2. **iOS pre-existing build errors**: `CalendarViewController.swift:122` and `ChatUISpecView.swift` have Swift 6 concurrency issues unrelated to this change. Should be fixed separately.

## Architecture Notes for Future Auth Changes

All auth logic lives in **one place**: `packages/swift-auth/Sources/TodusAuth/AuthService.swift`

To add a new auth method (e.g., Microsoft, phone number):
1. Add the method to `AuthService.swift` in the shared package
2. Add UI buttons in both `AuthView.swift` (iOS) and `MacAuthView.swift` (macOS)
3. Both platforms automatically get the backend logic

To change session handling, token storage, or refresh logic:
1. Edit only the shared package — changes propagate to both platforms

Platform-specific code should **only** be needed for:
- UI differences (input styling, modifiers, URL opening)
- `presentationAnchor` (already handled with `#if canImport`)
