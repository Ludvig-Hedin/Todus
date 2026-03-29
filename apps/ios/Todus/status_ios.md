# Todus iOS — Status Tracker

## Current Phase: 2 (Auth + Email Frontend)

---

## Build Status

| Component | Status | Notes |
|-----------|--------|-------|
| Project structure | ✅ Done | All dirs created, files copied |
| Xcode project | ✅ Done | XcodeGen project.yml → .xcodeproj |
| CalendarKit SPM | ✅ Done | richardtop/CalendarKit v1.1.7 |
| Compiles | ✅ Done | Shell builds succeed; Xcode environment reset completed after custom build path + build.db corruption issues |
| Runs on device | ✅ Done | Installs and launches on physical iPhone |

## Auth Status

| Feature | Status | Notes |
|---------|--------|-------|
| Apple Sign In | ✅ Fixed | Native ASAuthorizationAppleIDProvider → Better-Auth backend. Origin header + nested idToken format + redirect/header token extraction |
| Google Sign In | ✅ Fixed | ASWebAuthenticationSession → Google OAuth → /auth/mobile-token → todus://auth-callback?token=JWT. Strong session reference to prevent dealloc |
| Email OTP | ❌ Removed | Backend doesn't support email OTP (only SMS via Twilio). Removed from AuthService and AuthView |
| Keychain storage | ✅ Done | KeychainHelper enum in AuthService.swift |
| Onboarding flow | ✅ Redesigned | AuthView.swift — matches RN app: brand logo, pill-shaped Apple/Google buttons, colored Google logo, error box, terms footer |
| Deep link handling | ✅ Done | TodosApp.swift routes todus://auth-callback to AuthService |

## Tab: Home

| Feature | Status | Notes |
|---------|--------|-------|
| Greeting | ✅ Code written | HomeView.swift |
| Events section | ✅ Code written | Uses CalendarService |
| Tasks section | ✅ Code written | SwiftData @Query |
| Email section | ⬜ Placeholder | Needs EmailService wiring |

## Tab: Tasks

| Feature | Status | Notes |
|---------|--------|-------|
| Task list | ✅ Ported | From MiniTaskApp |
| Board view | ✅ Ported | From MiniTaskApp |
| Table view | ✅ Ported | From MiniTaskApp |
| Calendar view | ✅ Ported | From MiniTaskApp |
| Capture composer | ✅ Ported | From MiniTaskApp |
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

## Navigation

| Feature | Status | Notes |
|---------|--------|-------|
| Custom tab bar | ✅ Code written | MainTabView.swift — liquid glass material |
| FAB button | ✅ Code written | Accent circle + shadow |
| AI chat button | ✅ Code written | Sparkles icon in tab bar |
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

## Last Updated: 2026-03-29
