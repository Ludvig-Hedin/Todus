# Migration Backlog

Last updated: 2026-03-01

## Current State

The old M1-M7 milestones represent the historical WebView-shell phase and are complete.

The active goal is a **truly native iOS app in `apps/ios`** that reaches feature + behavior parity with `apps/mail` while using native navigation/layout patterns.

Auth/login is currently owned by another agent stream and is excluded from this stream unless explicitly reassigned.

## Status Legend

- `PENDING`
- `IN_PROGRESS`
- `DONE`
- `BLOCKED`

## Current Execution Order (Highest Priority First)

1. `N4-06` Implement undo-send
2. `N4-07` Implement schedule send
3. `N4-08` Implement templates
4. `N4-09` Add M4 tests
5. `N6-01` Build AI chat panel with streaming responses

---

## Legacy Milestones (WebView Shell) — All DONE

<details>
<summary>M1-M7: WebView Shell (click to expand)</summary>

### M1 Foundations (WebView Shell)

| ID    | Task                                                                | Status |
| ----- | ------------------------------------------------------------------- | ------ |
| M1-01 | Create native app foundations (now located in `apps/ios`)           | DONE   |
| M1-02 | Add monorepo packages: shared, api-client, design-tokens, ui-native | DONE   |
| M1-03 | Extract web design tokens into shared token package                 | DONE   |
| M1-04 | Add React Navigation scaffold with Auth/Public/App shells           | DONE   |
| M1-05 | Add Query + Jotai provider stack for native                         | DONE   |
| M1-06 | Add environment config and backend URL wiring                       | DONE   |
| M1-07 | Add secure storage abstraction (token + prefs)                      | DONE   |
| M1-08 | Document native setup in root docs                                  | DONE   |

### M2 Auth + Session (WebView Shell)

| ID          | Task                                         | Status |
| ----------- | -------------------------------------------- | ------ |
| M2-01–M2-06 | Auth flow via WebView + native token storage | DONE   |

### M3-M7 (WebView Shell)

All marked DONE — these are WebView-based, not truly native.

</details>

---

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

| ID    | Task                                                      | Status  | Definition of Done                                                                                                    |
| ----- | --------------------------------------------------------- | ------- | --------------------------------------------------------------------------------------------------------------------- |
| N3-01 | Build native mail sidebar with folder list + counts       | DONE    | Sidebar renders folders from tRPC (mocked for N3-01, implemented correctly in N3-04)                                  |
| N3-02 | Build thread list screen with FlashList                   | DONE    | Thread list loads Dummy data using FlashList, ready for N3-04                                                         |
| N3-03 | Build thread detail screen with message rendering         | DONE    | Messages render with HTML content auto-resizing WebView per-message                                                   |
| N3-04 | Implement thread actions (star/archive/delete/spam/label) | DONE    | All actions work with optimistic updates                                                                              |
| N3-05 | Implement search with filters                             | DONE    | Implemented folder + unread/starred/attachment filters in native search modal                                         |
| N3-06 | Build mail shell layout (sidebar + list + detail)         | DONE    | Adaptive split shell implemented: permanent sidebar + list/detail on iPad/macOS, stacked routing on iPhone            |
| N3-07 | Wire optimistic updates with rollback                     | DONE    | Optimistic cache updates + rollback implemented for archive/delete/spam/star actions                                  |
| N3-08 | Add swipe actions for thread list items                   | DONE    | Swipe direction handling fixed and wired correctly to archive/delete actions                                          |
| N3-09 | Add M3 tests                                              | BLOCKED | Blocked by pre-existing workspace TS/test instability outside iOS scope; unblock after server/types baseline is green |

### N4 Compose + Drafts

| ID    | Task                                                | Status  | Definition of Done                                                                                                           |
| ----- | --------------------------------------------------- | ------- | ---------------------------------------------------------------------------------------------------------------------------- |
| N4-01 | Build compose screen with recipients/CC/BCC/subject | DONE    | Compose now supports To/Cc/Bcc/Subject parity with reply/reply-all/forward prefill updates                                   |
| N4-02 | Integrate @10play/tentap-editor for rich text       | DONE    | Rich text editor + toolbar integrated in compose using TenTap                                                                |
| N4-03 | Implement attachment pick/upload/preview            | DONE    | Compose supports multi-file picking, preview/removal, and serialized attachment upload payloads                              |
| N4-04 | Implement draft auto-save/restore/delete            | DONE    | Compose draft auto-save + restore + clear-on-send implemented via local persisted draft state                                |
| N4-05 | Implement reply/reply-all/forward                   | DONE    | Reply/reply-all/forward actions now enforce web recipient parity, thread-aware send payload fields, and inline action parity |
| N4-06 | Implement undo-send                                 | PENDING | Undo window matches web                                                                                                      |
| N4-07 | Implement schedule send                             | PENDING | Calendar picker for delayed send                                                                                             |
| N4-08 | Implement templates                                 | PENDING | Template selection and insertion                                                                                             |
| N4-09 | Add M4 tests                                        | PENDING | Tests for compose, drafts, send flow                                                                                         |

### N5 Settings

| ID    | Task                                          | Status  | Definition of Done                                                                                                                                       |
| ----- | --------------------------------------------- | ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| N5-01 | Build settings shell with navigation          | DONE    | Settings hub now routes to all parity sections with native stack entries                                                                                 |
| N5-02 | Build all 11 settings screens as native forms | DONE    | Native form parity implemented across general/appearance/categories/notifications/privacy/security/shortcuts/danger-zone plus upgraded existing sections |
| N5-03 | Implement connections management              | DONE    | Set default, disconnect, reconnect (web handoff), and add-account entry point implemented                                                                |
| N5-04 | Implement labels CRUD with color picker       | DONE    | Create/edit/delete label flows with color selection implemented in native settings                                                                       |
| N5-05 | Implement danger zone with confirmations      | DONE    | Confirmation-gated account deletion flow implemented with destructive confirm dialog                                                                     |
| N5-06 | Add M5 tests                                  | BLOCKED | Blocked by pre-existing workspace TS/test instability outside iOS scope; unblock after server/types baseline is green                                    |

### N6 AI + Voice + Integrations

| ID    | Task                                         | Status  | Definition of Done                                                                            |
| ----- | -------------------------------------------- | ------- | --------------------------------------------------------------------------------------------- |
| N6-01 | Build AI chat panel with streaming responses | PENDING | AI send/receive works                                                                         |
| N6-02 | Implement voice with ElevenLabs              | PENDING | Mic permission + voice conversation                                                           |
| N6-03 | Integrate PostHog analytics                  | DONE    | Native PostHog bootstrap, screen tracking, identify, and key mail events are wired for parity |
| N6-04 | Integrate Sentry crash reporting             | DONE    | Native Sentry init + boundary/query capture hooks + expo plugin wiring added                  |
| N6-05 | Implement notes panel                        | PENDING | Notes CRUD on threads                                                                         |
| N6-06 | Add M6 tests                                 | PENDING | AI/voice smoke tests                                                                          |

### N7 Public Pages + Remaining Screens

| ID    | Task                                     | Status  | Definition of Done                    |
| ----- | ---------------------------------------- | ------- | ------------------------------------- |
| N7-01 | Landing/home screens (WebView or native) | PENDING | Accessible from unauthenticated state |
| N7-02 | Legal pages (WebView)                    | PENDING | About, terms, privacy render          |
| N7-03 | Pricing screen                           | PENDING | Billing state + upgrade flow          |
| N7-04 | Contributors/developer screens           | PENDING | Content renders                       |
| N7-05 | Not-found / under-construction screens   | PENDING | Fallback screens exist                |

### N8 Polish, Performance, Release

| ID    | Task                                                         | Status  | Definition of Done                                                                                                                                   |
| ----- | ------------------------------------------------------------ | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| N8-01 | Visual regression pass (screenshots all screens)             | BLOCKED | Screenshot scaffolding and coverage checks are in place; full pass blocked until device/simulator captures + authenticated parity data are available |
| N8-02 | Performance optimization (list scroll, startup, transitions) | DONE    | Added query stale/gc tuning, list virtualization tuning, and row memoization to reduce scroll jank and refetch churn                                 |
| N8-03 | Accessibility pass (VoiceOver, TalkBack, keyboard nav)       | PENDING | Critical flows accessible                                                                                                                            |
| N8-04 | Release pipeline setup (TestFlight, Play Console, macOS)     | PENDING | CI/CD for all platforms                                                                                                                              |
| N8-05 | Deprecate WebView wrapper app flows                          | PENDING | WebView screens removed                                                                                                                              |
| N8-06 | Final QA and signoff                                         | PENDING | All parity checklist items green                                                                                                                     |

---

## Manual Inputs Required

- Apple Developer signing and distribution setup
- Android signing keystore + Play Console tracks
- OAuth redirect updates for native deep-link callbacks
- Production analytics/Intercom/Sentry DSNs/keys
- See `MANUAL_INPUTS_GUIDE.md` for details

## Session Notes (2026-03-01)

- `N3-05` completed in `apps/ios/app/search.tsx` with structured search filters mapped to server query semantics.
- `N5-01` completed by expanding settings navigation and stack routes in `apps/ios/app/(app)/settings/*`.
- `N3-06` completed with adaptive mail shell behavior (`apps/ios/app/(app)/_layout.tsx`, `apps/ios/app/(app)/(mail)/[folder].tsx`) and a reusable detail pane (`apps/ios/src/features/mail/ThreadDetailPane.tsx`).
- `N3-07` completed with optimistic cache updates + rollback utilities in `apps/ios/src/features/mail/optimisticThreadCache.ts`, wired into folder and detail actions.
- `N3-08` completed by fixing swipe direction action mapping in `apps/ios/src/features/mail/SwipeableThreadRow.tsx`.
- `N5-02` completed by replacing settings placeholders with native form screens for categories, notifications, privacy, security, shortcuts, and danger zone; plus upgrading general/appearance forms.
- `N5-03` completed in `apps/ios/app/(app)/settings/connections.tsx` (default, disconnect, reconnect handoff, add account handoff).
- `N5-04` completed in `apps/ios/app/(app)/settings/labels.tsx` with label CRUD and color picker parity.
- `N5-05` completed in `apps/ios/app/(app)/settings/danger-zone.tsx` with confirmation-gated account deletion.
- `N4-01` completed in `apps/ios/app/compose.tsx` by adding Bcc support and parity-oriented reply-all/forward prefills.
- `N4-02` completed in `apps/ios/app/compose.tsx` by integrating `@10play/tentap-editor` (`RichText` + `Toolbar`) for native rich-text composition.
- `N4-03` completed in `apps/ios/app/compose.tsx` with native document picking, attachment preview/removal, and attachment payload serialization for send.
- `N4-04` completed in `apps/ios/app/compose.tsx` with debounce-based draft auto-save, draft restore on reopen, and draft cleanup after successful send.
- `N4-05` completed with reply/reply-all/forward refinements in `apps/ios/app/compose.tsx` and `apps/ios/src/features/mail/ThreadDetailPane.tsx` (recipient parity rules, reply headers/forward metadata payload, and corrected inline action bar layout).
- `N6-03` completed with PostHog integration in native (`apps/ios/src/shared/telemetry/posthog.ts`, provider bootstrap in `apps/ios/src/providers/AppProviders.tsx`, route tracking in `apps/ios/app/_layout.tsx`, user identify in `apps/ios/app/(app)/_layout.tsx`, and event instrumentation in compose/thread actions).
- `N6-04` completed with Sentry integration in native (`apps/ios/src/shared/telemetry/sentry.ts`, initialization in `apps/ios/src/providers/AppProviders.tsx`, app wrapper in `apps/ios/app/_layout.tsx`, and capture hooks in `apps/ios/src/shared/components/ErrorBoundary.tsx` + `apps/ios/src/providers/QueryTrpcProvider.tsx`).
- `N8-01` moved to `BLOCKED` after implementing screenshot governance artifacts in `/parity_screenshots` (`manifest.json`, `SCREENSHOT_LOG.md`, `README.md`) and adding coverage enforcement via `pnpm parity:screenshots:check`; full completion requires runtime captures on web/iOS/Android/macOS.
- `N8-02` completed with targeted native performance improvements in mail flows: list/detail query cache tuning (`staleTime`/`gcTime`), reduced auto-refetch churn, FlashList virtualization tuning, and memoized thread rows.
- Login/auth flow remains untouched in this stream per ownership constraint.
- `N3-09` and `N5-06` remain blocked because current workspace-level test/typecheck runs fail in unrelated server/packages paths, preventing reliable green test baselines.

### Test / Build Status

- Workspace TypeScript checks remain blocked by pre-existing cross-package errors outside iOS scope (not introduced by this stream).
- Screenshot coverage check currently fails intentionally (`0/128`) until parity screenshots are captured and committed.
- Targeted formatting checks pass on all files touched in this session.

---

## Parity Gap Tasks (2026-03-01)

| ID     | Task                                                                                                                                      | Status  | Notes                                                                                                                                                               |
| ------ | ----------------------------------------------------------------------------------------------------------------------------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| PG-001 | Implement native public route set parity (`/`, `/home`, `/about`, `/terms`, `/pricing`, `/privacy`, `/contributors`, `/developer`, `/hr`) | PENDING | Route and content parity for iOS/Android; explicit macOS strategy required                                                                                          |
| PG-002 | Add native `/signup` parity flow                                                                                                          | PENDING | Include Google OAuth-first UX and fallback behavior parity                                                                                                          |
| PG-003 | Complete native mail shell parity for `/mail/:folder`                                                                                     | PENDING | Include category tabs, command palette entry points, bulk selection UX                                                                                              |
| PG-004 | Implement `/mail/create` and `/mail/under-construction/:path` parity behaviors                                                            | PENDING | Redirect/placeholder parity with web semantics                                                                                                                      |
| PG-005 | Rebuild native compose parity (`/mail/compose`)                                                                                           | PENDING | Rich text + attachments + draft lifecycle + reply/reply-all/forward shipped; remaining parity items: templates, schedule send, undo send                            |
| PG-006 | Add native mailto parity (`/api/mailto-handler`)                                                                                          | PENDING | Parse mailto payload and create draft before opening compose                                                                                                        |
| PG-007 | Complete settings parity for missing sections                                                                                             | DONE    | Native forms added for `/settings/categories`, `/settings/notifications`, `/settings/privacy`, `/settings/security`, `/settings/shortcuts`, `/settings/danger-zone` |
| PG-008 | Upgrade native existing settings sections from partial to full parity                                                                     | DONE    | `/settings/general`, `/settings/appearance`, `/settings/connections`, `/settings/labels` upgraded with parity-focused forms/actions                                 |
| PG-009 | Implement labels/categories CRUD + assignment parity in native                                                                            | DONE    | Labels CRUD + color selection and category default/order/filter editing implemented                                                                                 |
| PG-010 | Implement native AI assistant and voice parity                                                                                            | PENDING | Match web AI sidebar workflows and usage gating                                                                                                                     |
| PG-011 | Implement native integrations parity: PostHog + Dub + Sentry + Autumn                                                                     | PENDING | PostHog + Sentry native wiring completed; remaining parity work: Dub + Autumn native coverage and validation                                                        |
| PG-012 | Establish screenshot-driven visual regression proof in `/parity_screenshots/`                                                             | BLOCKED | Naming convention + manifest + diff log + verifier are implemented; blocked on collecting actual screenshots across web/iOS/Android/macOS                           |
| PG-013 | Build parity-focused automated tests (unit/integration/E2E)                                                                               | PENDING | Cover critical workflows and high-risk edge cases                                                                                                                   |
| PG-014 | Resolve macOS architecture blocker                                                                                                        | BLOCKED | Current `apps/macos` is Electron wrapper, not RN macOS parity implementation                                                                                        |
