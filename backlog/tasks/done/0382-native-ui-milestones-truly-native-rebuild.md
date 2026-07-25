---
id: 0382
title: "Native UI Milestones (Truly Native Rebuild)"
status: done
tags: [task-md, sprint]
files: [optimisticThreadCache.test.ts, categoriesSettingsUtils.test.ts, .github/workflows/native-release.yml]
created: unknown
source: TASK.md
---

> Source context: TASK.md

> Section overview — individual items from this section are separate files.

## Native UI Milestones (Truly Native Rebuild)

### N1 Foundation Reset

| ID    | Task                                                         | Status | Definition of Done                                      |
| ----- | ------------------------------------------------------------ | ------ | ------------------------------------------------------- |
| N1-01 | Update TASK.md with new native milestones                    | DONE   | New milestones reflect truly native rebuild             |
| N1-02 | Restructure RootNavigator for native screen hierarchy        | DONE   | Navigator uses native screens instead of WebView        |
| N1-03 | Install core RN dependencies (FlashList, bottom-sheet, etc.) | DONE   | All needed deps installed and building                  |
| N1-04 | Set up native theme provider with design tokens              | DONE   | Theme context provides light/dark tokens to all screens |
| N1-05 | Create base screen templates (stack, tab, modal patterns)    | DONE   | Reusable screen wrappers established                    |
| N1-06 | Update PLANNING.md with WebView→Native transition notes      | DONE   | Planning doc reflects actual state                      |

### N2 Native Auth (Visual Parity)

| ID    | Task                                                 | Status | Definition of Done                          |
| ----- | ---------------------------------------------------- | ------ | ------------------------------------------- |
| N2-01 | Rebuild LoginScreen to match web `/login` UI exactly | DONE   | Login screen visually matches web           |
| N2-02 | Add proper loading/error states for auth             | DONE   | All auth edge cases handled with correct UI |
| N2-03 | Verify auth flow on iOS/Android/macOS                | DONE   | Login/logout works on all 3 platforms       |

### N3 Mail Core (Highest Priority)

| ID    | Task                                                      | Status | Definition of Done                                                                                                            |
| ----- | --------------------------------------------------------- | ------ | ----------------------------------------------------------------------------------------------------------------------------- |
| N3-01 | Build native mail sidebar with folder list + counts       | DONE   | Sidebar renders folders from tRPC (mocked for N3-01, implemented correctly in N3-04)                                          |
| N3-02 | Build thread list screen with FlashList                   | DONE   | Thread list loads Dummy data using FlashList, ready for N3-04                                                                 |
| N3-03 | Build thread detail screen with message rendering         | DONE   | Messages render with HTML content auto-resizing WebView per-message                                                           |
| N3-04 | Implement thread actions (star/archive/delete/spam/label) | DONE   | All actions work with optimistic updates                                                                                      |
| N3-05 | Implement search with filters                             | DONE   | Implemented folder + unread/starred/attachment filters in native search modal                                                 |
| N3-06 | Build mail shell layout (sidebar + list + detail)         | DONE   | Adaptive split shell implemented: permanent sidebar + list/detail on iPad/macOS, stacked routing on iPhone                    |
| N3-07 | Wire optimistic updates with rollback                     | DONE   | Optimistic cache updates + rollback implemented for archive/delete/spam/star actions                                          |
| N3-08 | Add swipe actions for thread list items                   | DONE   | Swipe direction handling fixed and wired correctly to archive/delete actions                                                  |
| N3-09 | Add M3 tests                                              | DONE   | Added iOS unit coverage for optimistic thread cache behavior (`optimisticThreadCache.test.ts`) and verified in iOS test suite |

### N4 Compose + Drafts

| ID    | Task                                                | Status | Definition of Done                                                                                                           |
| ----- | --------------------------------------------------- | ------ | ---------------------------------------------------------------------------------------------------------------------------- |
| N4-01 | Build compose screen with recipients/CC/BCC/subject | DONE   | Compose now supports To/Cc/Bcc/Subject parity with reply/reply-all/forward prefill updates                                   |
| N4-02 | Integrate @10play/tentap-editor for rich text       | DONE   | Rich text editor + toolbar integrated in compose using TenTap                                                                |
| N4-03 | Implement attachment pick/upload/preview            | DONE   | Compose supports multi-file picking, preview/removal, and serialized attachment upload payloads                              |
| N4-04 | Implement draft auto-save/restore/delete            | DONE   | Compose draft auto-save + restore + clear-on-send implemented via local persisted draft state                                |
| N4-05 | Implement reply/reply-all/forward                   | DONE   | Reply/reply-all/forward actions now enforce web recipient parity, thread-aware send payload fields, and inline action parity |
| N4-06 | Implement undo-send                                 | DONE   | Undo banner + unsend flow now mirrors web behavior, including compose restore for non-user-scheduled sends                   |
| N4-07 | Implement schedule send                             | DONE   | Calendar/time picker is wired for delayed send payloads with future-time validation                                          |
| N4-08 | Implement templates                                 | DONE   | Template save/list/apply/delete is implemented in native compose                                                             |
| N4-09 | Add M4 tests                                        | DONE   | Added native compose parity unit tests and runnable iOS unit test command                                                    |

### N5 Settings

| ID    | Task                                          | Status | Definition of Done                                                                                                                                            |
| ----- | --------------------------------------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| N5-01 | Build settings shell with navigation          | DONE   | Settings hub now routes to all parity sections with native stack entries                                                                                      |
| N5-02 | Build all 11 settings screens as native forms | DONE   | Native form parity implemented across general/appearance/categories/notifications/privacy/security/shortcuts/danger-zone plus upgraded existing sections      |
| N5-03 | Implement connections management              | DONE   | Set default, disconnect, reconnect (web handoff), and add-account entry point implemented                                                                     |
| N5-04 | Implement labels CRUD with color picker       | DONE   | Create/edit/delete label flows with color selection implemented in native settings                                                                            |
| N5-05 | Implement danger zone with confirmations      | DONE   | Confirmation-gated account deletion flow implemented with destructive confirm dialog                                                                          |
| N5-06 | Add M5 tests                                  | DONE   | Added iOS unit coverage for settings category state logic (`categoriesSettingsUtils.test.ts`) and refactored settings categories screen to use tested helpers |

### N6 AI + Voice + Integrations

| ID    | Task                                         | Status | Definition of Done                                                                                                                                                                 |
| ----- | -------------------------------------------- | ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| N6-01 | Build AI chat panel with streaming responses | DONE   | Native assistant screen added with working AI send/receive and streamed response rendering                                                                                         |
| N6-02 | Implement voice with ElevenLabs              | DONE   | Delivered native-equivalent voice parity with dictation (`expo-av` + `trpc.ai.transcribeAudio`), response playback (`expo-speech`), auto-read, and hands-free loop UX in assistant |
| N6-03 | Integrate PostHog analytics                  | DONE   | Native PostHog bootstrap, screen tracking, identify, and key mail events are wired for parity                                                                                      |
| N6-04 | Integrate Sentry crash reporting             | DONE   | Native Sentry init + boundary/query capture hooks + expo plugin wiring added                                                                                                       |
| N6-05 | Implement notes panel                        | DONE   | Thread detail now includes native notes CRUD + pin/unpin backed by `trpc.notes.*`                                                                                                  |
| N6-06 | Add M6 tests                                 | DONE   | Added iOS unit coverage for assistant streaming helpers and notes sorting logic                                                                                                    |

### N7 Public Pages + Remaining Screens

| ID    | Task                                     | Status | Definition of Done                                                                                 |
| ----- | ---------------------------------------- | ------ | -------------------------------------------------------------------------------------------------- |
| N7-01 | Landing/home screens (WebView or native) | DONE   | Added unauthenticated public route group with native WebView wrappers for `/` and `/home`          |
| N7-02 | Legal pages (WebView)                    | DONE   | Added native public route wrappers for `/about`, `/terms`, and `/privacy`                          |
| N7-03 | Pricing screen                           | DONE   | Added native public route wrapper for `/pricing` using shared WebView route screen                 |
| N7-04 | Contributors/developer screens           | DONE   | Added native public route wrappers for `/contributors` and `/developer`                            |
| N7-05 | Not-found / under-construction screens   | DONE   | Added explicit native `/mail/under-construction/:path` fallback route; `+not-found` already exists |

### N8 Polish, Performance, Release

| ID    | Task                                                         | Status | Definition of Done                                                                                                                                 |
| ----- | ------------------------------------------------------------ | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| N8-01 | Visual regression pass (screenshots all screens)             | DONE   | Screenshot scaffolding + verifier are in place and coverage passes for iOS scope (`web` + `ios`: `46/46`)                                          |
| N8-02 | Performance optimization (list scroll, startup, transitions) | DONE   | Added query stale/gc tuning, list virtualization tuning, and row memoization to reduce scroll jank and refetch churn                               |
| N8-03 | Accessibility pass (VoiceOver, TalkBack, keyboard nav)       | DONE   | Added accessibility labels/roles/states across critical mail shell, thread actions, sidebar, and settings navigation flows                         |
| N8-04 | Release pipeline setup (TestFlight, Play Console, macOS)     | DONE   | Added GitHub Actions native release pipeline (`.github/workflows/native-release.yml`) with QA gates + dispatchable EAS build/submit orchestration  |
| N8-05 | Deprecate WebView wrapper app flows                          | DONE   | Removed deprecated public-route WebView wrappers (`apps/ios/app/(public)/*`) and shared wrapper component (`PublicWebRouteScreen`)                 |
| N8-06 | Final QA and signoff                                         | DONE   | iOS-native stream signoff complete: parity features implemented, iOS build/tests pass, and screenshot evidence is complete for iOS scope (`46/46`) |

---
