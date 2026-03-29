# macOS Auth Implementation Plan

## Current State (Pre-Implementation)

### iOS Auth Stack
- **Service**: `AuthService` (~770 lines) — `@MainActor @Observable` class
- **Backend**: Better-Auth on Cloudflare Workers (`https://api.todus.app`)
- **Methods**: Apple Sign In (native), Google OAuth (ASWebAuthenticationSession), Email OTP
- **Token Storage**: Keychain via `KeychainHelper` (Security framework)
- **Session Restore**: Reads Keychain on launch, calls `/api/auth/get-session` for silent refresh
- **State Management**: `@Observable` pattern, `AuthState` enum (.guest/.authenticating/.otpPending/.authenticated)
- **Deep Links**: `todus://auth-callback?token=...` for Google OAuth callback
- **Root Gating**: `showsOnboarding` computed property gates between AuthView and MainTabView

### macOS State (Pre-Implementation)
- Pure SwiftUI skeleton with zero auth
- Placeholder user profile ("Username" with "U" avatar)
- No backend connectivity, no API client
- No shared code with iOS

## Architecture Decision

**Shared SPM Package** (`packages/swift-auth/TodusAuth`)

98% of the iOS AuthService is platform-agnostic. Only the `presentationAnchor` method (~12 lines) uses UIKit. Creating a shared package avoids duplicating 770 lines and ensures future auth changes propagate automatically.

### What's Shared (in TodusAuth package)
- `AuthService` — full auth logic with `#if canImport(UIKit/AppKit)` for presentation anchor
- `KeychainHelper` — Keychain CRUD operations (Security framework, identical on both platforms)
- `NoRedirectDelegate` — URLSession delegate for intercepting redirects
- `AppleSignInDelegate` — Async wrapper for ASAuthorizationController

### What's Platform-Specific
- **iOS**: `AuthView.swift` (iOS-specific modifiers like `.keyboardType`, `UIApplication.shared.open`)
- **macOS**: `MacAuthView.swift` (macOS-adapted layout, `NSWorkspace.shared.open`, `RoundedRectangle` inputs)
- **iOS**: `AppServices` (full service container with calendar, reminders, SwiftData, etc.)
- **macOS**: `MacAppServices` (lightweight — auth service only for now)

## Implementation Plan

### Phase 1: Shared Package
1. Create `packages/swift-auth/` with Package.swift targeting iOS 18+ / macOS 15+
2. Extract AuthService, KeychainHelper, NoRedirectDelegate, AppleSignInDelegate
3. Mark public API, add `#if canImport` for platform-specific presentation anchor

### Phase 2: Wire iOS
1. Add TodusAuth as local SPM dependency in iOS project.yml
2. Replace original AuthService.swift with `@_exported import TodusAuth` shim
3. Add `import TodusAuth` to all consuming iOS files
4. Regenerate Xcode project, verify build

### Phase 3: Build macOS Auth
1. Add TodusAuth dependency to macOS project.yml
2. Create entitlements (Sign in with Apple, network client)
3. Add `todus://` URL scheme to Info.plist
4. Create TodosConfig.plist with backend URL
5. Create MacAppServices (lightweight service container)
6. Create MacAuthView (adapted from iOS with macOS styling)
7. Wire TodusMacApp (environment injection, .onOpenURL for deep links)
8. Wire MacRootView (auth state gating)
9. Wire MacSidebarView (logout, user display name)

### Phase 4: Verify
1. Regenerate both Xcode projects
2. Build macOS — verify compilation
3. Build iOS — verify no regressions
4. Test auth flows

## Backend Changes
None required. `todus://auth-callback` is already in `trustedOrigins` at `apps/server/src/lib/auth.ts:426`.

## Risks
1. **Apple Sign In capability**: macOS bundle ID needs to be added to App Store Connect
2. **Provisioning profiles**: First build requires provisioning profile creation
3. **XcodeGen + local SPM**: Works but needs regeneration after project.yml changes
