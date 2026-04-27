# Todus iOS — Status Tracker

## Current Phase: 2 (Auth + Email Frontend)

---

## Build Status

| Component | Status | Notes |
|-----------|--------|-------|
| Project structure | ✅ Done | All dirs created, files copied |
| Xcode project | ✅ Done | XcodeGen project.yml → .xcodeproj |
| CalendarKit SPM | ✅ Done | richardtop/CalendarKit v1.1.7 |
| Compiles | ✅ Done | Clean Xcode build now succeeds after fixing recursive SwiftUI types, calendar sendability, and the remaining voice/AI sendability issues |
| Runs on device | ✅ Done | Installs and launches on physical iPhone |
| Hang mitigation pass | ✅ Done | EventKit pruning removed from hot fetch paths, startup/tab work throttled, attachment thumbnails now decode lazily off the UI path, and signposts/hang watchdog added for Instruments |

## Auth Status

| Feature | Status | Notes |
|---------|--------|-------|
| Apple Sign In | ✅ Fixed | Native ASAuthorizationAppleIDProvider → Better-Auth backend. Origin header + nested idToken format + redirect/header token extraction |
| Google Sign In | ✅ Fixed | ASWebAuthenticationSession → Google OAuth → /auth/mobile-token → todus://auth-callback?token=JWT. Strong session reference to prevent dealloc |
| Email OTP | ❌ Removed | Backend doesn't support email OTP (only SMS via Twilio). Removed from AuthService and AuthView |
| Keychain storage | ✅ Done | KeychainHelper enum in AuthService.swift |
| Onboarding flow | ✅ Redesigned | AuthView.swift — matches RN app: brand logo, pill-shaped Apple/Google buttons, colored Google logo, error box, terms footer |
| Deep link handling | ✅ Done | TodosApp.swift routes todus://auth-callback to AuthService |
| AI profile settings | ✅ Done | Shared `Context about you` + `Custom instructions` fields now sync through backend `userSettings` and are injected into every AI prompt |

## Tab: Home

| Feature | Status | Notes |
|---------|--------|-------|
| Scroll vs tab bar | ✅ Fixed | Home scroll matches Tasks: `contentMargins(.bottom, 130)` + no `ScrollView.clipped()` so content isn’t cut off at the tab bar |
| Greeting | ✅ Code written | HomeView.swift |
| Events section | ✅ Code written | Uses CalendarService |
| Tasks section | ✅ Code written | SwiftData @Query |
| Email section | ⬜ Placeholder | Needs EmailService wiring |

## Tab: Tasks

| Feature | Status | Notes |
|---------|--------|-------|
| Task list | ✅ Ported | Compact search bar, tighter list spacing, status chip trailing, 2-line titles, 5s delay to “Recently completed”, light-mode row/sheet contrast |
| Board view | ✅ Ported | Added task signature regrouping so in-place status/folder mutations move cards between columns again |
| Table view | ✅ Ported | From MiniTaskApp |
| Calendar view | ✅ Ported | From MiniTaskApp |
| Capture composer | ✅ Ported | Preserves selected attachments when event creation falls back to task capture |
| Folders | ✅ Ported | From MiniTaskApp |
| Search + sort | ✅ Ported | From MiniTaskApp |
| Reminders sync | ✅ Ported | From MiniTaskApp |
| API sync (unified) | ⬜ Not started | Needs TaskService rewiring |

## Tab: Email

| Feature | Status | Notes |
|---------|--------|-------|
| EmailService | ✅ Code written | TRPC wrapper for all email ops |
| Connect flow | ✅ Code written | EmailConnectView.swift |
| Gmail icon sizing | ✅ Fixed | Shared Gmail icon now preserves SVG aspect ratio in onboarding and button usage |
| Fresh install auth reset | ✅ Fixed | First launch clears stale Keychain auth so reinstall shows login again |
| Settings sheet theme sync | ✅ Fixed | Settings sheet now applies the active color scheme immediately on theme change |
| Inbox list | ✅ Code written | EmailInboxView.swift with List + swipe |
| Search | ✅ Code written | Client-side filter + server search on submit |
| Swipe actions | ✅ Code written | Archive, delete, read/unread, star |
| Thread view | ✅ Code written | EmailThreadView.swift with message bubbles |
| HTML rendering | ✅ Code written | EmailHTMLView (WKWebView) with dark mode CSS |
| Compose | ✅ Code written | EmailComposeView.swift — new + reply |
| Reply | ✅ Code written | Reply bar in thread view → compose sheet |

## Tab: Calendar

| Feature | Status | Notes |
|---------|--------|-------|
| Day view | ✅ Ported | CalendarKit UIKit bridge |
| Event display | ✅ Ported | EKWrapper adapter |
| Create/edit events | ✅ Ported | Native EventKit views |
| CalendarService | ✅ Code written | Shared EKEventStore actor |
| Permission gate | ✅ Fixed (2026-04-25) | After in-app “Allow Access”, the tab now unlocks without leaving the app (`Notification` + fixed `CalendarPermissionView` logic; tab switch re-checks auth) |
| Tab header | ✅ Adjusted (2026-04-25) | `CalendarTabView` — removed duplicate calendar icon + “Calendar” label; `AppTopHeader` now shows only the view-mode (Day/…) picker beside avatar and actions |

## Navigation

| Feature | Status | Notes |
|---------|--------|-------|
| Main tab bar | ✅ Fixed (2026-04-26) | `MainTabView` now shows only the native iOS `TabView` bar with labeled tabs; the duplicate floating `CustomTabBar` overlay is no longer rendered |
| FAB button | ✅ Code kept | Floating custom-tab-bar create action remains in code, but is hidden from the live shell |
| AI chat button | ✅ Code kept | Floating custom-tab-bar AI action remains in code, but is hidden from the live shell |
| Create sheet | ✅ Code written | Type selector + text input |
| Settings sheet | ✅ Ported | From MiniTaskApp |
| Auth → Main routing | ✅ Code written | RootView routes auth/onboarding/main |

## API Layer

| Feature | Status | Notes |
|---------|--------|-------|
| TodosAPIClient | ✅ Code written | Bearer auth + TRPC helpers |
| AppConfiguration | ✅ Updated | Supports backendURL + legacy Supabase |
| AppServices | ✅ Updated | Includes all new + legacy services |

## AI Assistant

| Feature | Status | Notes |
|---------|--------|-------|
| Chat UI | ✅ Ported | From MiniTaskApp |
| Chat composer height | ✅ Fixed | Empty RichComposerInput now resolves to a compact single-line intrinsic height instead of stretching tall in conversation view |
| Task tools | ✅ Ported | create, update, delete |
| Email tools | ⬜ Not started | |
| Calendar tools | ⬜ Not started | |
| Multi-domain context | ⬜ Not started | |

## Backend

| Feature | Status | Notes |
|---------|--------|-------|
| Task table (Drizzle) | ✅ Done | apps/server/src/db/schema.ts |
| Folder table (Drizzle) | ✅ Done | apps/server/src/db/schema.ts |
| Task TRPC routes | ✅ Done | list, create, update, delete, sync |
| Folder TRPC routes | ✅ Done | list, create, update, delete |
| Router registration | ✅ Done | tasks + folders in appRouter |
| DB migration | ⬜ Not started | Need to run drizzle-kit push |

---

## Blockers

| Issue | Impact | Resolution |
|-------|--------|------------|
| DB migration not run | Tasks won't persist on backend | Run `drizzle-kit push` |
| TaskService not yet built | Tasks still sync via Supabase | Build TaskService to replace SupabaseSyncService |

## Build Notes

- April 26, 2026: `MainTabView` now uses only the standard iOS tab bar at runtime; `CustomTabBar` stays in source but is not rendered, and the tab-bar onboarding/settings surfaces are hidden.
- April 25, 2026: `MainTabView` — native tab bar unselected icons tinted with `secondaryLabel` (selected uses `label`) so inactive tabs read muted, per [Tab Bar HIG](https://developer.apple.com/design/human-interface-guidelines/tab-bars).
- April 25, 2026: `TabBarOnboardingView` (step 4) — `ScrollView` to prevent clipping; compact rows; `AppPrimaryButtonStyle` for the primary CTA (fixes dark mode); “Other pages” no longer lists Create/AI; tab preview matches native `MainTabView` (five slots, + center, no legacy burger/AI bar).
- April 3, 2026: shipped a consolidated iOS UX remediation pass. Native button hit targets were tightened across shared SwiftUI button styles and header controls without changing layout; Home gained explicit loading states, partial-setup guidance, stronger section actions, and a less dominant `More pages` section; Tasks search/sort now behaves consistently across all modes with clearer mode guidance and `By Date` naming; Email now exposes primary mailbox chips, clearer search-state feedback, a short message preview before AI summary/actions in thread detail, and a first-use folder-switch hint; Gmail/Reminders/tab-bar onboarding now shows progress with lighter, more skippable copy; the floating tab bar gets a one-time coachmark overlay aligned with the `More pages` wording; and Create now guides natural-language input more clearly.
- March 30, 2026: fixed the remaining iOS compile blockers in `CardViews.swift`, `AIChatView.swift`, `VoiceChatViewModel.swift`, and `VoiceInputButton.swift`; verified `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -destination 'generic/platform=iOS Simulator' build` succeeds.
- March 30, 2026: added the shared AI profile settings flow (`Context about you` + `Custom instructions`) to iOS, wired the form to backend `userSettings`, and injected the profile into every AI request path.
- March 30, 2026: tightened AI chat failure handling on iOS and macOS so auth/session issues now surface as explicit messages instead of the generic "Connection lost briefly" banner; macOS build verified with `xcodebuild -project apps/macos/TodusMac.xcodeproj -scheme TodusMac build`.
- March 29, 2026: fixed the `ChatUISpecView` opaque-type recursion by switching the recursive renderer to `AnyView`, then marked `EKWrapper` as `@unchecked Sendable` so CalendarKit event wrappers can cross the background-fetch to main-thread boundary in Swift 6 without a data-race compile error.
- March 29, 2026: Xcode GUI hangs around `RegisterExecutionPolicyException ... CalendarKit.o` were traced to a local Xcode environment problem, not a CalendarKit source dependency problem.
- Root cause: Xcode had custom build output paths configured (`~/XcodeDerivedData/Todus` and `~/Desktop/Build/Intermediates.noindex`). After manual cache cleanup, those non-default paths interacted badly with execution-policy registration and `syspolicyd`.
- Follow-up issue exposed by a truly clean rebuild: the generated Xcode project was stale and missed `Features/AI/ChatUISpec.swift`, `ChatUISpecView.swift`, and `CardViews.swift`, and also included `Navigation/archived/CustomTabBar.swift`.
- Fixes applied:
  - reset Xcode build location defaults back to standard DerivedData
  - cleared Todus DerivedData and SwiftPM caches, then re-resolved packages
  - regenerated `Todus.xcodeproj` from `project.yml`
  - excluded `**/archived/**` from the iOS app target source list
- Manual note: `~/Desktop/Build` still exists because Terminal lacked permission to remove it, but Xcode is no longer configured to use it.

---

## Last Updated: 2026-04-26
