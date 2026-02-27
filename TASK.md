# Migration Backlog

Last updated: 2026-02-21

## Current State

The M1-M7 milestones below represent the **WebView shell** implementation — a native app wrapper that embeds the web app in a WebView. These are complete.

**N1-N8 milestones** represent the **truly native UI** rebuild — replacing the WebView with native React Native screens that achieve ~99% visual parity with the web app.

## Status Legend

- `PENDING`
- `IN_PROGRESS`
- `DONE`
- `BLOCKED`

---

## Legacy Milestones (WebView Shell) — All DONE

<details>
<summary>M1-M7: WebView Shell (click to expand)</summary>

### M1 Foundations (WebView Shell)

| ID | Task | Status |
|---|---|---|
| M1-01 | Create `apps/native` RN CLI app with iOS/Android/macOS targets | DONE |
| M1-02 | Add monorepo packages: shared, api-client, design-tokens, ui-native | DONE |
| M1-03 | Extract web design tokens into shared token package | DONE |
| M1-04 | Add React Navigation scaffold with Auth/Public/App shells | DONE |
| M1-05 | Add Query + Jotai provider stack for native | DONE |
| M1-06 | Add environment config and backend URL wiring | DONE |
| M1-07 | Add secure storage abstraction (token + prefs) | DONE |
| M1-08 | Document native setup in root docs | DONE |

### M2 Auth + Session (WebView Shell)

| ID | Task | Status |
|---|---|---|
| M2-01–M2-06 | Auth flow via WebView + native token storage | DONE |

### M3-M7 (WebView Shell)

All marked DONE — these are WebView-based, not truly native.

</details>

---

## Native UI Milestones (Truly Native Rebuild)

### N1 Foundation Reset

| ID | Task | Status | Definition of Done |
|---|---|---|---|
| N1-01 | Update TASK.md with new native milestones | DONE | New milestones reflect truly native rebuild |
| N1-02 | Restructure RootNavigator for native screen hierarchy | DONE | Navigator uses native screens instead of WebView |
| N1-03 | Install core RN dependencies (FlashList, bottom-sheet, etc.) | DONE | All needed deps installed and building |
| N1-04 | Set up native theme provider with design tokens | DONE | Theme context provides light/dark tokens to all screens |
| N1-05 | Create base screen templates (stack, tab, modal patterns) | DONE | Reusable screen wrappers established |
| N1-06 | Update PLANNING.md with WebView→Native transition notes | DONE | Planning doc reflects actual state |

### N2 Native Auth (Visual Parity)

| ID | Task | Status | Definition of Done |
|---|---|---|---|
| N2-01 | Rebuild LoginScreen to match web `/login` UI exactly | DONE | Login screen visually matches web |
| N2-02 | Add proper loading/error states for auth | DONE | All auth edge cases handled with correct UI |
| N2-03 | Verify auth flow on iOS/Android/macOS | DONE | Login/logout works on all 3 platforms |

### N3 Mail Core (Highest Priority)

| ID | Task | Status | Definition of Done |
|---|---|---|---|
| N3-01 | Build native mail sidebar with folder list + counts | DONE | Sidebar renders folders from tRPC (mocked for N3-01, implemented correctly in N3-04) |
| N3-02 | Build thread list screen with FlashList | DONE | Thread list loads Dummy data using FlashList, ready for N3-04 |
| N3-03 | Build thread detail screen with message rendering | DONE | Messages render with HTML content auto-resizing WebView per-message |
| N3-04 | Implement thread actions (star/archive/delete/spam/label) | DONE | All actions work with optimistic updates |
| N3-05 | Implement search with filters | PENDING | Search matches web behavior |
| N3-06 | Build mail shell layout (sidebar + list + detail) | PENDING | 3-column on macOS/iPad, stack on iPhone |
| N3-07 | Wire optimistic updates with rollback | PENDING | Same UX as web for all mail actions |
| N3-08 | Add swipe actions for thread list items | PENDING | Native swipe gestures for quick actions |
| N3-09 | Add M3 tests | PENDING | Integration tests for mail endpoints + UI tests |

### N4 Compose + Drafts

| ID | Task | Status | Definition of Done |
|---|---|---|---|
| N4-01 | Build compose screen with recipients/CC/BCC/subject | PENDING | Compose form matches web |
| N4-02 | Integrate @10play/tentap-editor for rich text | PENDING | Rich text editing with formatting toolbar |
| N4-03 | Implement attachment pick/upload/preview | PENDING | Native file/image picker + upload |
| N4-04 | Implement draft auto-save/restore/delete | PENDING | Drafts persist across sessions |
| N4-05 | Implement reply/reply-all/forward | PENDING | Reply inline matches web behavior |
| N4-06 | Implement undo-send | PENDING | Undo window matches web |
| N4-07 | Implement schedule send | PENDING | Calendar picker for delayed send |
| N4-08 | Implement templates | PENDING | Template selection and insertion |
| N4-09 | Add M4 tests | PENDING | Tests for compose, drafts, send flow |

### N5 Settings

| ID | Task | Status | Definition of Done |
|---|---|---|---|
| N5-01 | Build settings shell with navigation | PENDING | Settings list screen with all sections |
| N5-02 | Build all 11 settings screens as native forms | PENDING | Each screen matches web form fields |
| N5-03 | Implement connections management | PENDING | Add/remove/reconnect connections |
| N5-04 | Implement labels CRUD with color picker | PENDING | Labels fully editable |
| N5-05 | Implement danger zone with confirmations | PENDING | Account deletion with proper warnings |
| N5-06 | Add M5 tests | PENDING | Settings persistence tests |

### N6 AI + Voice + Integrations

| ID | Task | Status | Definition of Done |
|---|---|---|---|
| N6-01 | Build AI chat panel with streaming responses | PENDING | AI send/receive works |
| N6-02 | Implement voice with ElevenLabs | PENDING | Mic permission + voice conversation |
| N6-03 | Integrate PostHog analytics | PENDING | Events visible in dashboard |
| N6-04 | Integrate Sentry crash reporting | PENDING | Crashes visible in Sentry |
| N6-05 | Implement notes panel | PENDING | Notes CRUD on threads |
| N6-06 | Add M6 tests | PENDING | AI/voice smoke tests |

### N7 Public Pages + Remaining Screens

| ID | Task | Status | Definition of Done |
|---|---|---|---|
| N7-01 | Landing/home screens (WebView or native) | PENDING | Accessible from unauthenticated state |
| N7-02 | Legal pages (WebView) | PENDING | About, terms, privacy render |
| N7-03 | Pricing screen | PENDING | Billing state + upgrade flow |
| N7-04 | Contributors/developer screens | PENDING | Content renders |
| N7-05 | Not-found / under-construction screens | PENDING | Fallback screens exist |

### N8 Polish, Performance, Release

| ID | Task | Status | Definition of Done |
|---|---|---|---|
| N8-01 | Visual regression pass (screenshots all screens) | PENDING | All screens compared web vs native |
| N8-02 | Performance optimization (list scroll, startup, transitions) | PENDING | Baselines met |
| N8-03 | Accessibility pass (VoiceOver, TalkBack, keyboard nav) | PENDING | Critical flows accessible |
| N8-04 | Release pipeline setup (TestFlight, Play Console, macOS) | PENDING | CI/CD for all platforms |
| N8-05 | Deprecate WebView wrapper app flows | PENDING | WebView screens removed |
| N8-06 | Final QA and signoff | PENDING | All parity checklist items green |

---

## Manual Inputs Required

- Apple Developer signing and distribution setup
- Android signing keystore + Play Console tracks
- OAuth redirect updates for native deep-link callbacks
- Production analytics/Intercom/Sentry DSNs/keys
- See `MANUAL_INPUTS_GUIDE.md` for details
